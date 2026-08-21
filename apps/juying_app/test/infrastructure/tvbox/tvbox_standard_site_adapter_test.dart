import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/infrastructure/tvbox/tvbox_config_parser.dart';
import 'package:juying/infrastructure/tvbox/tvbox_standard_site_adapter.dart';

void main() {
  final site = TvboxStandardSite(
    key: 'public-api',
    name: '公开接口',
    type: 1,
    apiUri: Uri.parse('https://api.example/provide/vod'),
  );

  test('标准 JSON 站点映射为统一条目、选集和播放描述', () async {
    final adapter = TvboxStandardSiteAdapter(
      sourceId: 'tvbox-standard',
      site: site,
      fallbackUri: Uri.parse('https://config.example/source.json'),
      client: MockClient((request) async {
        if (request.url.queryParameters['ids'] == '42') {
          return http.Response.bytes(
            utf8.encode(
                '{"list":[{"vod_id":"42","vod_name":"示例电影","vod_play_url":"正片\$https://stream.example/movie.m3u8"}]}'),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(
              '{"list":[{"vod_id":"42","vod_name":"示例电影","type_name":"电影","vod_remarks":"高清"}]}'),
          200,
        );
      }),
    );

    final item = (await adapter
            .browse(const MediaCatalogQuery(category: MediaCategory.movie)))
        .items
        .single;
    expect(item.sourceItemId, 'public-api::42');
    expect(item.category, MediaCategory.movie);
    final episode = (await adapter.episodes(item)).single;
    final playback = await adapter.resolvePlayback(episode);
    expect(playback.nativeStreamUri,
        Uri.parse('https://stream.example/movie.m3u8'));
  });

  test('标准 XML 站点映射为统一条目与播放描述', () async {
    final adapter = TvboxStandardSiteAdapter(
      sourceId: 'tvbox-xml',
      site: TvboxStandardSite(
        key: 'xml-api',
        name: 'XML 接口',
        type: 0,
        apiUri: Uri.parse('https://api.example/xml'),
      ),
      fallbackUri: Uri.parse('https://config.example/source.json'),
      client: MockClient((request) async {
        final detail = request.url.queryParameters['ids'] == '7';
        return http.Response.bytes(
          utf8.encode(detail
              ? '<rss><list><video><vod_id>7</vod_id><vod_name>示例剧集</vod_name><vod_play_url>第1集\$http://stream.example/episode.m3u8</vod_play_url></video></list></rss>'
              : '<rss><list><video><vod_id>7</vod_id><vod_name>示例剧集</vod_name><type_name>电视剧</type_name></video></list></rss>'),
          200,
        );
      }),
    );

    final item = (await adapter
            .browse(const MediaCatalogQuery(category: MediaCategory.drama)))
        .items
        .single;
    final episode = (await adapter.episodes(item)).single;
    final playback = await adapter.resolvePlayback(episode);
    expect(item.sourceItemId, 'xml-api::7');
    expect(playback.nativeStreamUri,
        Uri.parse('http://stream.example/episode.m3u8'));
  });

  test('标准站点按 play_from 与三美元分隔符展开多线路选集', () async {
    final adapter = TvboxStandardSiteAdapter(
      sourceId: 'tvbox-multi-line',
      site: TvboxStandardSite(
        key: 'multi',
        name: '多线路',
        type: 1,
        apiUri: Uri.parse('https://api.example/vod'),
        httpHeaders: const {
          'User-Agent': 'LivingRoom',
          'Referer': 'https://portal.example/',
        },
      ),
      fallbackUri: Uri.parse('https://config.example/source.json'),
      client: MockClient((request) async {
        expect(request.url.queryParameters['ac'], 'videolist');
        expect(request.headers['User-Agent'], 'LivingRoom');
        if (request.url.queryParameters['ids'] == '9') {
          return http.Response.bytes(
            utf8.encode(
              '{"list":[{"vod_id":"9","vod_name":"节目","vod_play_from":"主线\$\$\$备用","vod_play_url":"第1集\$https://one.example/1.m3u8#第2集\$https://one.example/2.m3u8\$\$\$第1集\$https://two.example/1.m3u8"}]}',
            ),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(
            '{"list":[{"vod_id":"9","vod_name":"节目","type_name":"电视剧"}]}',
          ),
          200,
        );
      }),
    );

    final item = (await adapter
            .browse(const MediaCatalogQuery(category: MediaCategory.drama)))
        .items
        .single;
    final episodes = await adapter.episodes(item);
    final playback = await adapter.resolvePlayback(episodes.last);

    expect(episodes.map((episode) => episode.title),
        ['主线 · 第1集', '主线 · 第2集', '备用 · 第1集']);
    expect(playback.nativeStreamUri, Uri.parse('https://two.example/1.m3u8'));
    expect(playback.httpHeaders['Referer'], 'https://portal.example/');
  });

  test('标准 JSON 站点按远端 class 映射分类、子分类和页码', () async {
    final requests = <Uri>[];
    final adapter = TvboxStandardSiteAdapter(
      sourceId: 'tvbox-catalog',
      site: site,
      fallbackUri: Uri.parse('https://config.example/source.json'),
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response.bytes(
          utf8.encode('''
{
  "page": 2,
  "total": 80,
  "class": [
    {"type_id":"1","type_pid":"0","type_name":"电影"},
    {"type_id":"7","type_pid":"1","type_name":"喜剧片"}
  ],
  "list": [
    {"vod_id":"88","vod_name":"喜剧节目","type_id":"7","type_name":"喜剧片"}
  ]
}
'''),
          200,
        );
      }),
    );

    final page = await adapter.browse(const MediaCatalogQuery(
      category: MediaCategory.movie,
      page: 2,
    ));
    final item = page.items.single;

    expect(requests.last.queryParameters['t'], '1');
    expect(requests.last.queryParameters['pg'], '2');
    expect(page.total, 80);
    expect(item.sourceSubcategoryId, 'public-api::type:7');
    expect(item.sourceSubcategoryLabel, '喜剧片');
  });
}
