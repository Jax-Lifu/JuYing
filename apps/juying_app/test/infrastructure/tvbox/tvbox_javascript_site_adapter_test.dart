import 'package:flutter_test/flutter_test.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/infrastructure/tvbox/tvbox_config_parser.dart';
import 'package:juying/infrastructure/tvbox/tvbox_javascript_runtime.dart';
import 'package:juying/infrastructure/tvbox/tvbox_javascript_site_adapter.dart';

void main() {
  final site = TvboxJavascriptSite(
    key: 'drpy',
    name: 'DRPY 示例',
    apiUri: Uri.parse('https://plugin.example/drpy.js'),
    ext: 'https://plugin.example/site.js',
  );

  test('DRPY 分类、节目、选集和播放结果映射到统一媒体契约', () async {
    final runtime = _FakeRuntime();
    final adapter = TvboxJavascriptSiteAdapter(
      sourceId: 'tvbox-js',
      site: site,
      runtime: runtime,
      fallbackUri: Uri.parse('https://config.example/tvbox.json'),
    );

    final page = await adapter.browse(const MediaCatalogQuery(
      category: MediaCategory.movie,
      page: 2,
    ));
    expect(page.total, 48);
    expect(page.items.single.sourceItemId, 'drpy::vod-7');
    expect(
        runtime.calls[1].arguments, ['movie', '2', true, <String, String>{}]);

    final episodes = await adapter.episodes(page.items.single);
    expect(episodes.map((episode) => episode.title),
        ['main · 第1集', 'backup · 第1集']);

    final playback = await adapter.resolvePlayback(episodes.first);
    expect(playback.nativeStreamUri,
        Uri.parse('https://stream.example/episode-1.m3u8'));
    expect(playback.httpHeaders['Referer'], 'https://portal.example/');
    expect(runtime.calls.last.method, 'play');
    expect(runtime.calls.last.arguments.first, 'main');
  });

  test('需要网页嗅探的 play 结果不会冒充原生直播放行', () async {
    final adapter = TvboxJavascriptSiteAdapter(
      sourceId: 'tvbox-js',
      site: site,
      runtime: _FakeRuntime(webParse: true),
      fallbackUri: Uri.parse('https://config.example/tvbox.json'),
    );
    final item = (await adapter
            .browse(const MediaCatalogQuery(category: MediaCategory.movie)))
        .items
        .single;
    final episode = (await adapter.episodes(item)).first;

    final playback = await adapter.resolvePlayback(episode);
    expect(playback.nativeStreamUri, isNull);
    expect(playback.officialPageUri, Uri.parse('https://page.example/player'));
  });

  test('DRPY 的 no_data 哨兵不会显示成节目卡片', () async {
    final adapter = TvboxJavascriptSiteAdapter(
      sourceId: 'tvbox-js',
      site: site,
      runtime: _FakeRuntime(noData: true),
      fallbackUri: Uri.parse('https://config.example/tvbox.json'),
    );

    final page = await adapter.browse(
      const MediaCatalogQuery(category: MediaCategory.movie),
    );

    expect(page.items, isEmpty);
  });
}

class _FakeRuntime implements TvboxJavascriptRuntime {
  _FakeRuntime({this.webParse = false, this.noData = false});

  final bool webParse;
  final bool noData;
  final calls = <_Call>[];

  @override
  Future<Object?> invoke(
    TvboxExecutableSite site,
    String method,
    List<Object?> arguments,
  ) async {
    calls.add(_Call(method, arguments));
    return switch (method) {
      'home' => {
          'class': [
            {'type_id': 'movie', 'type_name': '热门电影'},
            {'type_id': 'tv', 'type_name': '热播剧集'},
          ]
        },
      'category' => {
          'total': 48,
          'list': [
            {
              'vod_id': noData ? 'no_data' : 'vod-7',
              'vod_name': noData ? '暂无数据' : '示例电影',
              'vod_pic': 'https://image.example/poster.jpg',
            }
          ]
        },
      'detail' => {
          'list': [
            {
              'vod_id': 'vod-7',
              'vod_name': '示例电影',
              'vod_play_from': r'main$$$backup',
              'vod_play_url':
                  r'第1集$https://page.example/one$$$第1集$https://page.example/two',
            }
          ]
        },
      'play' => webParse
          ? {'parse': 1, 'url': 'https://page.example/player'}
          : {
              'parse': 0,
              'url': 'https://stream.example/episode-1.m3u8',
              'header': {'Referer': 'https://portal.example/'},
            },
      _ => throw StateError('unexpected method: $method'),
    };
  }
}

class _Call {
  const _Call(this.method, this.arguments);
  final String method;
  final List<Object?> arguments;
}
