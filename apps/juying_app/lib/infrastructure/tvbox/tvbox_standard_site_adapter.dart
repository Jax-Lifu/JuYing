import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/media_source.dart';
import '../../domain/models/unified_media.dart';
import '../network/safe_text_response_decoder.dart';
import 'tvbox_config_parser.dart';
import 'tvbox_playback_resolver.dart';
import 'tvbox_site_adapter.dart';

class TvboxStandardSiteAdapter implements TvboxSiteAdapter {
  TvboxStandardSiteAdapter({
    required this.sourceId,
    required this.site,
    required this.client,
    required this.fallbackUri,
    this.playbackResolver,
  });

  static const maxResponseBytes = 2 * 1024 * 1024;
  final String sourceId;
  final TvboxStandardSite site;
  final http.Client client;
  final Uri fallbackUri;
  final TvboxPlaybackResolver? playbackResolver;
  List<_VodClass>? _classes;
  int? _lastTotal;

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
    final selectedTypeId = _selectedTypeId(query.sourceSubcategoryId);
    if (query.sourceSubcategoryId != null && selectedTypeId == null) {
      return MediaCatalogPage(items: const [], page: query.page, total: 0);
    }
    await _ensureClasses();
    final typeId = selectedTypeId ?? _typeIdFor(query.category);
    final entries = await _request({
      'pg': query.page.toString(),
      if (typeId != null) 't': typeId,
    });
    final items = entries
        .map((entry) => _item(entry, fallbackCategory: query.category))
        .whereType<MediaItem>()
        .where((item) => item.category == query.category)
        .toList(growable: false);

    final int calculatedTotal;
    if (_lastTotal != null && _lastTotal! > 0) {
      calculatedTotal = _lastTotal!;
    } else if (items.isEmpty) {
      calculatedTotal = (query.page - 1) * query.pageSize;
    } else if (items.length >= 10) {
      calculatedTotal = (query.page + 1) * query.pageSize;
    } else {
      calculatedTotal = (query.page - 1) * query.pageSize + items.length;
    }

    return MediaCatalogPage(
      items: items,
      page: query.page,
      total: calculatedTotal,
    );
  }

  @override
  Future<List<MediaSearchHit>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    return (await _request({'wd': query.trim()}))
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
    final id = _itemId(item.sourceItemId);
    final entries = await _request({'ids': id});
    final entry = entries.firstWhere(
      (entry) => _text(entry['vod_id']) == id,
      orElse: () => throw StateError('节目详情已从来源移除'),
    );
    final title = _text(entry['vod_name']).isEmpty
        ? item.title
        : _text(entry['vod_name']);
    final poster = _uri(entry['vod_pic']);
    return _playEntries(
      entry['vod_play_url'],
      playFrom: entry['vod_play_from'],
    )
        .indexed
        .map((entry) => MediaEpisode(
              sourceId: sourceId,
              sourceEpisodeId: '${site.key}::$id:${entry.$1}',
              title: entry.$2.title,
              officialPageUri: site.apiUri,
              posterUri: poster,
              brief: title,
              episodeNumber: entry.$1 + 1,
            ))
        .toList(growable: false);
  }

  @override
  Future<PlaybackDescriptor> resolvePlayback(MediaEpisode episode) async {
    _assertSource(episode.sourceId);
    final separator = episode.sourceEpisodeId.lastIndexOf(':');
    if (separator < 1) throw StateError('节目播放标识无效');
    final id = _itemId(episode.sourceEpisodeId.substring(0, separator));
    final index =
        int.tryParse(episode.sourceEpisodeId.substring(separator + 1));
    if (index == null) throw StateError('节目播放标识无效');
    final entries = await _request({'ids': id});
    final entry = entries.firstWhere(
      (entry) => _text(entry['vod_id']) == id,
      orElse: () => throw StateError('节目详情已从来源移除'),
    );
    final plays = _playEntries(
      entry['vod_play_url'],
      playFrom: entry['vod_play_from'],
    );
    if (index >= plays.length) throw StateError('播放线路已从来源移除');
    final play = plays[index];
    final mergedHeaders = {
      ...site.httpHeaders,
      ...play.httpHeaders,
    };
    final resolved = playbackResolver == null
        ? TvboxResolvedPlayback(
            pageUri: play.url,
            streamUri: play.url,
            httpHeaders: mergedHeaders,
          )
        : await playbackResolver!.resolve(
            play.url,
            flag: play.flag,
            httpHeaders: mergedHeaders,
          );
    return PlaybackDescriptor(
      sourceId: sourceId,
      sourceEpisodeId: episode.sourceEpisodeId,
      title: play.title,
      officialPageUri: resolved.pageUri,
      nativeStreamUri: resolved.streamUri,
      posterUri: _uri(entry['vod_pic']),
      httpHeaders: resolved.httpHeaders,
    );
  }

  @override
  Future<PlaybackDescriptor> resolveOfficialFallback(MediaEpisode episode) =>
      resolvePlayback(episode);

  Future<void> probe() async {
    await _request();
  }

  Future<List<Map<String, String>>> _request(
      [Map<String, String>? parameters]) async {
    final query = <String, String>{...site.apiUri.queryParameters};
    query['ac'] = 'videolist';
    if (parameters != null) query.addAll(parameters);
    if (site.type == 4 && site.ext != null) {
      query['ext'] = base64.encode(utf8.encode(site.ext!));
    }
    final requestUri = site.apiUri.replace(queryParameters: query);
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      ...site.httpHeaders,
    };

    http.Response response;
    var attempts = 0;
    while (true) {
      attempts++;
      response = await client
          .get(requestUri, headers: headers)
          .timeout(const Duration(seconds: 8));

      // 遇到 502 / 503 / 504 网关临时错误时自动重试 1 次
      if ((response.statusCode == 502 ||
              response.statusCode == 503 ||
              response.statusCode == 504) &&
          attempts < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        continue;
      }
      break;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('${site.name} 请求失败（HTTP ${response.statusCode}）');
    }
    if (response.bodyBytes.length > maxResponseBytes) {
      throw StateError('${site.name} 响应超过安全上限');
    }
    final text = await SafeTextResponseDecoder.decode(response.bodyBytes,
        maxDecodedBytes: maxResponseBytes,
        contentEncoding: response.headers['content-encoding']);
    return site.type == 0 ? _xmlEntries(text) : _jsonEntries(text);
  }

  MediaItem? _item(
    Map<String, String> entry, {
    MediaCategory? fallbackCategory,
  }) {
    final id = _text(entry['vod_id']);
    final title = _text(entry['vod_name']);
    if (id.isEmpty || title.isEmpty) return null;
    return MediaItem(
      sourceId: sourceId,
      sourceItemId: '${site.key}::$id',
      title: title,
      category: _category(
        _text(entry['type_name']),
        typeId: _text(entry['type_id']),
        fallbackCategory: fallbackCategory,
      ),
      officialDetailUri: site.apiUri,
      defaultEpisodePageUri: site.apiUri,
      posterUri: _uri(entry['vod_pic']),
      brief: _blankToNull(entry['vod_content']) ??
          _blankToNull(entry['vod_remarks']),
      year: _blankToNull(entry['vod_year']),
      area: _blankToNull(entry['vod_area']),
      sourceCategoryLabel: _blankToNull(entry['type_name']),
      sourceSubcategoryId: _subcategoryId(entry['type_id']),
      sourceSubcategoryLabel: _blankToNull(entry['type_name']),
    );
  }

  Future<void> _ensureClasses() async {
    if (_classes != null) return;
    await _request({'pg': '1'});
    _classes ??= const [];
  }

  String? _typeIdFor(MediaCategory category) {
    final classes = _classes ?? const <_VodClass>[];
    final matching =
        classes.where((entry) => _category(entry.name) == category);
    if (matching.isEmpty) return null;
    return matching.where((entry) => entry.parentId == '0').firstOrNull?.id ??
        matching.first.id;
  }

  String? _selectedTypeId(String? id) {
    if (id == null) return null;
    final prefix = '${site.key}::type:';
    if (!id.startsWith(prefix)) return null;
    final value = id.substring(prefix.length).trim();
    return value.isEmpty ? null : value;
  }

  String? _subcategoryId(Object? value) {
    final id = _text(value).trim();
    return id.isEmpty ? null : '${site.key}::type:$id';
  }

  List<_StandardPlay> _playEntries(
    String? raw, {
    String? playFrom,
  }) {
    final results = <_StandardPlay>[];
    final groups = _text(raw).split(r'$$$');
    final sources = _text(playFrom).split(r'$$$');
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final sourceLabel =
          groupIndex < sources.length ? sources[groupIndex].trim() : '';
      for (final line in groups[groupIndex].split(RegExp(r'[#\r\n]+'))) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        final separator = trimmedLine.lastIndexOf(r'$');
        final rawUrl = (separator >= 0
                ? trimmedLine.substring(separator + 1)
                : trimmedLine)
            .trim();
        final (uri, headers) = _parseUrlAndHeaders(rawUrl);
        if (uri == null) continue;
        final episodeLabel = separator > 0 &&
                trimmedLine.substring(0, separator).trim().isNotEmpty
            ? trimmedLine.substring(0, separator).trim()
            : '播放 ${results.length + 1}';
        final name = groups.length > 1 && sourceLabel.isNotEmpty
            ? '$sourceLabel · $episodeLabel'
            : episodeLabel;
        results.add(_StandardPlay(
          title: name,
          url: uri,
          flag: sourceLabel,
          httpHeaders: headers,
        ));
      }
    }
    return results;
  }

  (Uri?, Map<String, String>) _parseUrlAndHeaders(String raw) {
    var urlPart = raw.trim();
    final headers = <String, String>{};

    // 解析 JSON 格式请求头: url;{"User-Agent": "..."}
    final jsonMatch = RegExp(r';\s*(\{[\s\S]*\})\s*$').firstMatch(urlPart);
    if (jsonMatch != null) {
      try {
        final decoded = jsonDecode(jsonMatch.group(1)!);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final key = entry.key.toString().trim();
            final value = entry.value?.toString().trim() ?? '';
            if (key.isNotEmpty && value.isNotEmpty) {
              headers[key] = value;
            }
          }
        }
        urlPart = urlPart.substring(0, jsonMatch.start).trim();
      } catch (_) {}
    }

    // 解析 TVBox 分号/艾特格式请求头: url;User-Agent@xxx 或 url;header=xxx
    final semicolonIdx = urlPart.indexOf(';');
    if (semicolonIdx > 0 && headers.isEmpty) {
      final headerPart = urlPart.substring(semicolonIdx + 1).trim();
      urlPart = urlPart.substring(0, semicolonIdx).trim();
      for (final part in headerPart.split(';')) {
        if (part.contains('@')) {
          final kv = part.split('@');
          if (kv.length == 2 && kv[0].trim().isNotEmpty) {
            headers[kv[0].trim()] = kv[1].trim();
          }
        } else if (part.contains('=')) {
          final kv = part.split('=');
          if (kv.length == 2 && kv[0].trim().isNotEmpty) {
            headers[kv[0].trim()] = kv[1].trim();
          }
        }
      }
    }

    final atIdx = urlPart.lastIndexOf('@');
    if (atIdx > 0 && headers.isEmpty && !urlPart.contains('://', atIdx)) {
      final headerPart = urlPart.substring(atIdx + 1).trim();
      if (headerPart.contains('=')) {
        urlPart = urlPart.substring(0, atIdx).trim();
        for (final part in headerPart.split(';')) {
          final kv = part.split('=');
          if (kv.length == 2 && kv[0].trim().isNotEmpty) {
            headers[kv[0].trim()] = kv[1].trim();
          }
        }
      }
    }

    final uri = _uri(urlPart);
    return (uri, headers);
  }

  List<Map<String, String>> _jsonEntries(String input) {
    final decoded = jsonDecode(input);
    if (decoded is Map) {
      final parsedTotal = int.tryParse(_text(decoded['total'])) ??
          int.tryParse(_text(decoded['recordcount']));
      final parsedPageCount = int.tryParse(_text(decoded['pagecount']));
      final parsedLimit = int.tryParse(_text(decoded['limit'])) ?? 20;
      if (parsedTotal != null && parsedTotal > 0) {
        _lastTotal = parsedTotal;
      } else if (parsedPageCount != null && parsedPageCount > 0) {
        _lastTotal = parsedPageCount * parsedLimit;
      }

      final classes = decoded['class'];
      if (classes is List) {
        _classes = classes
            .whereType<Map>()
            .map((value) {
              return _VodClass(
                id: _text(value['type_id']).trim(),
                parentId: _text(value['type_pid']).trim(),
                name: _text(value['type_name']).trim(),
              );
            })
            .where((entry) => entry.id.isNotEmpty && entry.name.isNotEmpty)
            .toList(growable: false);
      }
    }
    final list = decoded is Map ? decoded['list'] ?? decoded['data'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((value) => value.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? '')))
        .toList();
  }

  List<Map<String, String>> _xmlEntries(String input) {
    final listMatch = RegExp(
      r'<list[^>]*?(?:recordcount="(\d+)"|pagecount="(\d+)"|pagesize="(\d+)")[^>]*?>',
      caseSensitive: false,
    ).firstMatch(input);
    if (listMatch != null) {
      final rec = int.tryParse(listMatch.group(1) ?? '');
      final pgc = int.tryParse(listMatch.group(2) ?? '');
      final pgs = int.tryParse(listMatch.group(3) ?? '') ?? 20;
      if (rec != null && rec > 0) {
        _lastTotal = rec;
      } else if (pgc != null && pgc > 0) {
        _lastTotal = pgc * pgs;
      }
    }

    final videos = RegExp(r'<video>([\s\S]*?)</video>', caseSensitive: false)
        .allMatches(input);
    return videos.map((video) {
      final entry = <String, String>{};
      for (final field
          in RegExp(r'<([a-zA-Z0-9_]+)>([\s\S]*?)</\1>', caseSensitive: false)
              .allMatches(video.group(1)!)) {
        entry[field.group(1)!.toLowerCase()] = _decodeXml(field.group(2)!);
      }
      return entry;
    }).toList();
  }

  MediaCategory _category(
    String name, {
    String? typeId,
    MediaCategory? fallbackCategory,
  }) {
    final value = name.trim().toLowerCase();
    if (value.contains('电影') ||
        value.contains('影院') ||
        value.contains('动作') ||
        value.contains('喜剧') ||
        value.contains('科幻') ||
        value.contains('恐怖') ||
        value.contains('爱情') ||
        value.contains('战争') ||
        value.contains('故事') ||
        value.contains('预告') ||
        value.endsWith('片')) {
      return MediaCategory.movie;
    }
    if (value.contains('剧') || value.contains('连续剧')) {
      return MediaCategory.drama;
    }
    if (value.contains('动漫') || value.contains('动画') || value.contains('番剧')) {
      return MediaCategory.animation;
    }
    if (value.contains('纪录') || value.contains('记录')) {
      return MediaCategory.documentary;
    }
    if (value.contains('综艺')) return MediaCategory.variety;
    if (value.contains('少儿') || value.contains('儿童')) {
      return MediaCategory.kids;
    }
    if (typeId != null && _classes != null) {
      final matchedClass =
          _classes!.where((c) => c.id == typeId).firstOrNull;
      if (matchedClass != null && matchedClass.parentId != '0') {
        final parent = _classes!
            .where((c) => c.id == matchedClass.parentId)
            .firstOrNull;
        if (parent != null) {
          return _category(parent.name);
        }
      }
    }
    if (fallbackCategory != null && fallbackCategory != MediaCategory.live) {
      return fallbackCategory;
    }
    return MediaCategory.other;
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

  String _decodeXml(String input) => input
      .replaceAll('<![CDATA[', '')
      .replaceAll(']]>', '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .trim();

  String _text(Object? value) => value?.toString().trim() ?? '';

  String? _blankToNull(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  Uri? _uri(Object? value) {
    final raw = _text(value).trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }
}

class _VodClass {
  const _VodClass({
    required this.id,
    required this.parentId,
    required this.name,
  });

  final String id;
  final String parentId;
  final String name;
}

class _StandardPlay {
  const _StandardPlay({
    required this.title,
    required this.url,
    this.flag = '',
    this.httpHeaders = const {},
  });

  final String title;
  final Uri url;
  final String flag;
  final Map<String, String> httpHeaders;
}
