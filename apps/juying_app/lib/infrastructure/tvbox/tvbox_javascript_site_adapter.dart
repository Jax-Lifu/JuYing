import 'dart:convert';

import '../../domain/models/media_source.dart';
import '../../domain/models/unified_media.dart';
import 'tvbox_config_parser.dart';
import 'tvbox_javascript_runtime.dart';
import 'tvbox_playback_resolver.dart';
import 'tvbox_site_adapter.dart';

class TvboxJavascriptSiteAdapter implements TvboxSiteAdapter {
  TvboxJavascriptSiteAdapter({
    required this.sourceId,
    required this.site,
    required this.runtime,
    required this.fallbackUri,
    this.playbackResolver,
  });

  final String sourceId;
  final TvboxExecutableSite site;
  final TvboxJavascriptRuntime runtime;
  final Uri fallbackUri;
  final TvboxPlaybackResolver? playbackResolver;
  List<_JavascriptClass>? _classes;

  @override
  String get siteKey => site.key;

  @override
  MediaSource get source => MediaSource(
        id: sourceId,
        name: site.name,
        kind: MediaSourceKind.custom,
        entryUrl: site.apiUri.toString(),
        enabled: true,
        authorization: SourceAuthorization.userOwned,
        capabilities: const {
          SourceCapability.browse,
          SourceCapability.search,
          SourceCapability.episodes,
          SourceCapability.nativePublicPlayback,
          SourceCapability.officialFallback,
        },
      );

  @override
  Future<MediaCatalogPage> browse(MediaCatalogQuery query) async {
    if (query.category == MediaCategory.live) {
      return MediaCatalogPage(items: const [], page: query.page, total: 0);
    }
    await _ensureClasses();
    final selected = _selectedClassId(query.sourceSubcategoryId);
    if (query.sourceSubcategoryId != null && selected == null) {
      return MediaCatalogPage(items: const [], page: query.page, total: 0);
    }
    final typeId = selected ?? _typeIdFor(query.category);
    if (typeId == null) {
      return MediaCatalogPage(items: const [], page: query.page, total: 0);
    }
    final response = _map(await runtime.invoke(
      site,
      'category',
      [typeId, query.page.toString(), true, const <String, String>{}],
    ));
    final entries = _list(response['list']);
    final items = entries
        .map((entry) => _item(entry, categoryOverride: query.category))
        .whereType<MediaItem>()
        .toList(growable: false);
    final page = _integer(response['page']) ?? query.page;
    final pageCount = _integer(response['pagecount']);
    final limit = _integer(response['limit']) ?? query.pageSize;
    final total = _integer(response['total']) ??
        (pageCount != null ? pageCount * limit : items.length);
    return MediaCatalogPage(
      items: items,
      page: page,
      total: total,
    );
  }

  @override
  Future<List<MediaSearchHit>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final response = _map(await runtime.invoke(
      site,
      'search',
      [query.trim(), false, '1'],
    ));
    return _list(response['list'])
        .map(_item)
        .whereType<MediaItem>()
        .map((item) => MediaSearchHit(
              item: item,
              query: query,
              matchedField: 'title',
              relevance: 1,
              playable: true,
            ))
        .toList(growable: false);
  }

  @override
  Future<List<MediaEpisode>> episodes(MediaItem item) async {
    _assertSource(item.sourceId);
    final itemId = _itemId(item.sourceItemId);
    final response = _map(await runtime.invoke(
      site,
      'detail',
      [itemId],
    ));
    final detail = _list(response['list']).firstOrNull ?? const {};
    final title = _text(detail['vod_name']).trim().isEmpty
        ? item.title
        : _text(detail['vod_name']).trim();
    final poster = _uri(detail['vod_pic']) ?? item.posterUri;
    return _playEntries(
      detail['vod_play_url'],
      playFrom: detail['vod_play_from'],
    ).indexed.map((indexed) {
      final play = indexed.$2;
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({
            'item': itemId,
            'flag': play.flag,
            'url': play.url,
            'title': play.title,
            if (poster != null) 'poster': poster.toString(),
          })))
          .replaceAll('=', '');
      return MediaEpisode(
        sourceId: sourceId,
        sourceEpisodeId: '${site.key}::js:$payload',
        title: play.title,
        officialPageUri: _uri(play.url) ?? fallbackUri,
        posterUri: poster,
        brief: title,
        episodeNumber: indexed.$1 + 1,
      );
    }).toList(growable: false);
  }

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) async {
    _assertSource(episode.sourceId);
    final play = _episodePayload(episode.sourceEpisodeId);
    final response = _map(await runtime.invoke(site, 'play', [
      _text(play['flag']),
      _text(play['url']),
      const <String>[],
    ]));
    final resolved = _uri(response['url']);
    final requiresParse = _integer(response['parse']) == 1;
    if (resolved == null) throw StateError('站点没有返回有效播放地址');
    final playback = playbackResolver == null
        ? TvboxResolvedPlayback(
            pageUri: resolved,
            streamUri: requiresParse ? null : resolved,
            httpHeaders: {
              ...site.httpHeaders,
              ..._headers(response['header']),
            },
          )
        : await playbackResolver!.resolve(
            resolved,
            flag: _text(play['flag']),
            httpHeaders: {
              ...site.httpHeaders,
              ..._headers(response['header']),
            },
            forceParse: requiresParse,
          );
    return PlaybackDescriptor(
      sourceId: sourceId,
      sourceEpisodeId: episode.sourceEpisodeId,
      title: _text(play['title']).isEmpty
          ? episode.title
          : _text(play['title']),
      officialPageUri: playback.pageUri,
      nativeStreamUri: playback.streamUri,
      posterUri: _uri(play['poster']) ?? episode.posterUri,
      httpHeaders: playback.httpHeaders,
    );
  }

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(MediaEpisode episode) =>
      resolvePlayback(episode);

  Future<void> _ensureClasses() async {
    if (_classes != null) return;
    final home = _map(await runtime.invoke(site, 'home', const []));
    _classes = _list(home['class'])
        .map((entry) => _JavascriptClass(
              id: _text(entry['type_id']).trim(),
              name: _text(entry['type_name']).trim(),
            ))
        .where((entry) => entry.id.isNotEmpty && entry.name.isNotEmpty)
        .toList(growable: false);
  }

  MediaItem? _item(
    Map<String, dynamic> entry, {
    MediaCategory? categoryOverride,
  }) {
    final id = _text(entry['vod_id']).trim();
    final title = _text(entry['vod_name']).trim();
    if (id.isEmpty || title.isEmpty) return null;
    if (id == 'no_data' || title == 'no_data') return null;
    final typeName = _text(entry['type_name']).trim();
    final resolvedCategory = typeName.isEmpty
        ? (categoryOverride ?? MediaCategory.other)
        : _category(typeName);
    return MediaItem(
      sourceId: sourceId,
      sourceItemId: '${site.key}::$id',
      title: title,
      category: resolvedCategory,
      officialDetailUri: site.apiUri,
      defaultEpisodePageUri: site.apiUri,
      posterUri: _uri(entry['vod_pic']),
      brief: _blank(entry['vod_content']) ?? _blank(entry['vod_remarks']),
      year: _blank(entry['vod_year']),
      area: _blank(entry['vod_area']),
      sourceCategoryLabel: _blank(entry['type_name']),
      sourceSubcategoryId: _subcategoryId(entry['type_id']),
      sourceSubcategoryLabel: _blank(entry['type_name']),
    );
  }

  String? _typeIdFor(MediaCategory category) {
    final classes = _classes ?? const <_JavascriptClass>[];
    return classes
        .where((entry) => _category(entry.name) == category)
        .map((entry) => entry.id)
        .firstOrNull;
  }

  String? _selectedClassId(String? id) {
    if (id == null) return null;
    final prefix = '${site.key}::class:';
    if (!id.startsWith(prefix)) return null;
    final value = id.substring(prefix.length).trim();
    return value.isEmpty ? null : value;
  }

  String? _subcategoryId(Object? value) {
    final id = _text(value).trim();
    return id.isEmpty ? null : '${site.key}::class:$id';
  }

  List<_JavascriptPlay> _playEntries(Object? raw, {Object? playFrom}) {
    final groups = _text(raw).split(r'$$$');
    final flags = _text(playFrom).split(r'$$$');
    final result = <_JavascriptPlay>[];
    for (var group = 0; group < groups.length; group++) {
      final flag = group < flags.length ? flags[group].trim() : '';
      for (final line in groups[group].split(RegExp(r'[#\r\n]+'))) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final separator = trimmed.lastIndexOf(r'$');
        final url = separator >= 0
            ? trimmed.substring(separator + 1).trim()
            : trimmed;
        final title = separator > 0 &&
                trimmed.substring(0, separator).trim().isNotEmpty
            ? trimmed.substring(0, separator).trim()
            : '播放 ${result.length + 1}';
        final groupTitle =
            groups.length > 1 && flag.isNotEmpty ? '$flag · $title' : title;
        result.add(_JavascriptPlay(
          flag: flag,
          url: url,
          title: groupTitle,
        ));
      }
    }
    return result;
  }

  Map<String, dynamic> _episodePayload(String sourceEpisodeId) {
    final marker = '${site.key}::js:';
    if (!sourceEpisodeId.startsWith(marker)) {
      throw StateError('选集标识无效');
    }
    final encoded = sourceEpisodeId.substring(marker.length);
    final normalized = base64Url.normalize(encoded);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is! Map) throw StateError('选集负载无效');
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  String _itemId(String value) {
    final separator = value.indexOf('::');
    return separator < 0 ? value : value.substring(separator + 2);
  }

  void _assertSource(String actualSourceId) {
    if (actualSourceId != sourceId) {
      throw StateError('来源标识不匹配：期望 $sourceId，实际 $actualSourceId');
    }
  }

  MediaCategory _category(String name) {
    final value = name.trim().toLowerCase();
    if (value.contains('电影') || value.contains('影院')) {
      return MediaCategory.movie;
    }
    if (value.contains('剧') || value.contains('连续剧')) {
      return MediaCategory.drama;
    }
    if (value.contains('动漫') || value.contains('动画')) {
      return MediaCategory.animation;
    }
    if (value.contains('纪录') || value.contains('记录')) {
      return MediaCategory.documentary;
    }
    if (value.contains('综艺')) return MediaCategory.variety;
    if (value.contains('少儿') || value.contains('儿童')) {
      return MediaCategory.kids;
    }
    return MediaCategory.other;
  }

  Map<String, String> _headers(Object? raw) {
    Object? decoded = raw;
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {}
    }
    if (decoded is! Map) return const {};
    final result = <String, String>{};
    for (final entry in decoded.entries) {
      final key = entry.key.toString().trim();
      final value = entry.value?.toString().trim() ?? '';
      if (key.isNotEmpty && value.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  Map<String, dynamic> _map(Object? raw) =>
      raw is Map ? raw.map((key, value) => MapEntry(key.toString(), value)) : {};

  List<Map<String, dynamic>> _list(Object? raw) => raw is List
      ? raw
          .whereType<Map>()
          .map((entry) =>
              entry.map((key, value) => MapEntry(key.toString(), value)))
          .toList(growable: false)
      : const [];

  String _text(Object? raw) => raw?.toString().trim() ?? '';

  String? _blank(Object? raw) {
    final text = _text(raw);
    return text.isEmpty ? null : text;
  }

  int? _integer(Object? raw) =>
      raw is int ? raw : int.tryParse(_text(raw));

  Uri? _uri(Object? raw) {
    final text = _text(raw);
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }
}

class _JavascriptClass {
  const _JavascriptClass({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

class _JavascriptPlay {
  const _JavascriptPlay({
    required this.flag,
    required this.url,
    required this.title,
  });

  final String flag;
  final String url;
  final String title;
}
