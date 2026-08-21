import 'package:flutter_test/flutter_test.dart';
import 'package:juying/infrastructure/tvbox/tvbox_config_parser.dart';
import 'package:juying/infrastructure/tvbox/tvbox_live_playlist_parser.dart';

void main() {
  test('TVBox 配置只提取 lives 中的直连清单，并容忍注释和尾逗号', () {
    final lives = TvboxConfigParser.parseDirectLives(r'''
{
  // 站点与解析器不应被读取
  "sites": [{"api":"https://example.test/drpy.js"}],
  "parses": [{"url":"https://parse.example"}],
  "lives": [
    {"name":"直播", "url":"http://live.example/list.txt",},
    {"name":"代理", "url":"proxy://do=live&type=txt",},
    {"name":"内网", "url":"http://127.0.0.1/list.txt",},
  ],
}
''');

    expect(lives, hasLength(1));
    expect(lives.single.name, '直播');
    expect(lives.single.playlistUri, Uri.parse('http://live.example/list.txt'));
  });

  test('带 UTF-8 BOM 的 TVBox 配置仍可读取直连直播清单', () {
    final lives = TvboxConfigParser.parseDirectLives(
      '\uFEFF{"lives":[{"name":"直播","url":"https://live.example/list.txt"}]}',
    );

    expect(
        lives.single.playlistUri, Uri.parse('https://live.example/list.txt'));
  });

  test('兼容 FongMi/Gson 可读取但标准 JSON 不允许的字符串内换行', () {
    final lives = TvboxConfigParser.parseDirectLives('''
{
  "notice":"第一行
第二行",
  "lives":[{"url":"https://live.example/list.m3u"}]
}
''');

    expect(
        lives.single.playlistUri, Uri.parse('https://live.example/list.m3u'));
  });

  test('FongMi 相对直播地址和来源级安全请求头基于配置地址解析', () {
    final live = TvboxConfigParser.parseDirectLives(
      '''{"lives":[{"url":"./live/list.m3u","ua":"FongMi","referer":"https://portal.example/","header":{"Authorization":"ignored"}}]}''',
      baseUri: Uri.parse('https://config.example/path/config.json'),
    ).single;

    expect(live.playlistUri,
        Uri.parse('https://config.example/path/live/list.m3u'));
    expect(live.httpHeaders, {
      'User-Agent': 'FongMi',
      'Referer': 'https://portal.example/',
    });
  });

  test('FongMi 内嵌 groups/channel 直播配置会保留为可解析清单', () {
    final lives = TvboxConfigParser.parseDirectLives(r'''
{"lives":[{"name":"内嵌直播","groups":[{"name":"新闻","channel":[{"name":"新闻一","urls":["https://stream.example/news.m3u8$主线"]}]}]}]}
''');

    expect(lives.single.playlistUri, isNull);
    expect(
      TvboxLivePlaylistParser.parse(lives.single.inlinePlaylist!).single.name,
      '新闻一',
    );
  });

  test('标准 sites 只提取 XML/JSON 的公开 HTTP 接口', () {
    final sites = TvboxConfigParser.parseStandardSites('''
{
  "sites": [
    {"key":"json","name":"JSON","type":1,"api":"https://api.example/json"},
    {"key":"xml","name":"XML","type":"0","api":"http://api.example/xml"},
    {"key":"script","type":3,"api":"https://api.example/engine.js"},
    {"key":"private","type":1,"api":"http://127.0.0.1/api"}
  ]
}
''');

    expect(sites.map((site) => site.key), ['json', 'xml']);
  });

  test('FongMi type 4 声明式 JSON 接口按标准 JSON 站点接入', () {
    final sites = TvboxConfigParser.parseStandardSites('''
{"sites":[{"key":"extended","type":4,"api":"https://api.example/vod","ext":{"token":"public"}}]}
''');

    expect(sites.single.type, 4);
    expect(sites.single.apiUri, Uri.parse('https://api.example/vod'));
    expect(sites.single.ext, '{"token":"public"}');
  });

  test('type 3 JavaScript 解析器只接入纯 HTTP JavaScript', () {
    final sites = TvboxConfigParser.parseJavascriptSites('''
{
  "sites": [
    {"key":"drpy","name":"DRPY","type":3,"api":"./lib/drpy.js","ext":"./js/site.js"},
    {"key":"jar","type":3,"api":"https://api.example/drpy.js","ext":"./site.js","jar":"./spider.jar"},
    {"key":"csp","type":3,"api":"csp_Douban","ext":"./site.json"},
    {"key":"py","type":3,"api":"py_site","ext":"./site.py"}
  ]
}
''', baseUri: Uri.parse('https://config.example/repo/config.json'));

    expect(sites, hasLength(1));
    expect(sites.single.key, 'drpy');
    expect(sites.single.apiUri,
        Uri.parse('https://config.example/repo/lib/drpy.js'));
    expect(sites.single.ext, 'https://config.example/repo/js/site.js');
  });

  test('type 3 csp 站点继承全局 spider JAR 和 MD5', () {
    final sites = TvboxConfigParser.parseCspSites('''
{
  "spider":"./Yoursmile.jar;md5;69DADB9A99A618EA9E2F4E2B92968E41",
  "sites":[
    {"key":"csp_DouDou","name":"豆豆","type":3,"api":"csp_DouDou","ext":"token"},
    {"key":"js","type":3,"api":"https://example.com/drpy.js"}
  ]
}
''', baseUri: Uri.parse('https://config.example/xhz/config.json'));

    expect(sites, hasLength(1));
    expect(sites.single.className, 'com.github.catvod.spider.DouDou');
    expect(sites.single.jarUri,
        Uri.parse('https://config.example/xhz/Yoursmile.jar'));
    expect(sites.single.jarMd5, '69dadb9a99a618ea9e2f4e2b92968e41');
  });

  test('TVBox 多仓清单只提取去重后的公开 HTTP(S) 子配置', () {
    final repositories = TvboxConfigParser.parseRepositories(r'''
{
  "urls": [
    {"name":"主仓","url":"https://one.example/config.json"},
    {"name":"重复","url":"https://one.example/config.json"},
    {"name":"内网","url":"http://127.0.0.1/config.json"},
    {"name":"脚本","url":"proxy://warehouse"}
  ]
}
''');

    expect(repositories, hasLength(1));
    expect(repositories.single.name, '主仓');
    expect(repositories.single.configUri,
        Uri.parse('https://one.example/config.json'));
  });

  test('播放解析只接入 HTTP JSON 与 WebView 两类声明', () {
    final parsers = TvboxConfigParser.parsePlaybackParsers(r'''
{
  "parses": [
    {"name":"JSON","type":1,"url":"https://parse.example/api?url=","ext":{"flag":["qq"],"header":{"User-Agent":"TVBox"}}},
    {"name":"网页","type":0,"url":"https://web.example/player?url="},
    {"name":"JAR 聚合","type":3,"url":"Demo"},
    {"name":"内网","type":1,"url":"http://127.0.0.1/parse?url="}
  ]
}
''');

    expect(parsers, hasLength(2));
    expect(parsers.first.type, 1);
    expect(parsers.first.flags, {'qq'});
    expect(parsers.first.httpHeaders['User-Agent'], 'TVBox');
    expect(parsers.last.type, 0);
  });

  test('直连直播清单支持 TVBox TXT 分组和 HTTP(S) 频道', () {
    final channels = TvboxLivePlaylistParser.parse('''
央视,#genre#
CCTV-1,http://stream.example/cctv1.m3u8
卫视,#genre#
测试频道,https://stream.example/test.m3u8
代理频道,proxy://do=live
''');
    expect(channels, hasLength(2));
    expect(channels.first.group, '央视');
    expect(channels.last.name, '测试频道');
  });

  test('配置和解析器字段不能被 TXT 解析器误认成直播频道', () {
    expect(
      () => TvboxLivePlaylistParser.parse(r'''
{
  "ext": "分类url:http://web.example/list,flag:YuMi",
  "flags": ["youku", "qiyi"],
  "header": {"User-Agent": "Mozilla/5.0"},
  "parses": [{"name":"暴风酷告","url":"https://parse.example/?url="}]
}
'''),
      throwsFormatException,
    );
  });

  test('JSON 直播清单会忽略密码分组和非直连端点', () {
    final channels = TvboxLivePlaylistParser.parse('''
[
  {"name":"新闻","channel":[
    {"name":"官方新闻","number":"56","urls":["proxy://do=live","https://stream.example/news.m3u8\$主线","http://cdn.example/news-backup.m3u8\$备用"],"logo":"https://image.example/news.png"}
  ]},
  {"name":"受限","pass":"required","channel":[
    {"name":"不应导入","urls":["https://stream.example/private.m3u8"]}
  ]}
]
''');
    expect(channels, hasLength(1));
    expect(channels.single.group, '新闻');
    expect(channels.single.streamUri,
        Uri.parse('https://stream.example/news.m3u8'));
    expect(channels.single.alternateStreamUris,
        [Uri.parse('http://cdn.example/news-backup.m3u8')]);
    expect(channels.single.lineLabels, ['主线', '备用']);
    expect(channels.single.channelNumber, '56');
    expect(
        channels.single.logoUri, Uri.parse('https://image.example/news.png'));
  });
}
