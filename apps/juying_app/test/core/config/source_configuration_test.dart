import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:juying/application/sources/media_source_adapter_factory.dart';
import 'package:juying/core/config/app_config.dart';
import 'package:juying/core/config/source_configuration.dart';
import 'package:juying/infrastructure/cctv/cctv_repository.dart';

void main() {
  const cctvEntry =
      'https://tv.cctv.com/yxg/index.shtml?spm=C28340.P2qo7O8Q1Led.EEfEAhEnQFPl.64#datacid=dhp&datafl=&datadq=&fc=%E5%8A%A8%E7%94%BB%E7%89%87&dataszm=';

  test('受审计来源清单可构建内建适配器并保留用户启用状态', () {
    final config = SourceConfiguration.fromJsonString('''
      {"version":1,"sources":[
        {"id":"cctv-official","name":{"zh-CN":"央视"},
         "kind":"officialWeb","adapter":"cctvOfficial",
         "entryUrl":"$cctvEntry","enabled":false,
         "authorization":"officialEntryOnly",
         "capabilities":["browse","search","episodes","officialFallback"]}
      ]}
    ''');
    final repository = CctvRepository();
    addTearDown(repository.close);
    final adapters = MediaSourceAdapterFactory(
      cctvRepository: repository,
      client: MockClient((_) async => throw StateError('不应访问网络')),
    ).createAll(config);

    expect(adapters, hasLength(1));
    expect(adapters.single.source.name, '央视');
    expect(adapters.single.source.enabled, isFalse);
  });

  test('开发回退配置包含 CCTV、IPTV 与三个指定 TVBox 默认来源', () {
    final config = AppConfig.developmentSourceConfiguration();
    final ids = config.sources.map((entry) => entry.source.id).toList();

    expect(ids, [
      'cctv-official',
      'cctv-live-official',
      'iptv-default',
      'xhztv-xhz',
      'xhztv-4k',
      'xhztv-dc',
    ]);
    expect(
      config.sources.skip(3).map((entry) => entry.adapter).toSet(),
      {'tvboxConfig'},
    );
    expect(config.sources[2].adapter, 'playlistConfig');
  });

  test('未知适配器和远程执行字段会在配置边界被拒绝', () {
    expect(
      () => SourceConfiguration.fromJsonString('''
        {"version":1,"sources":[
          {"id":"unsafe","name":"不安全","kind":"custom",
           "adapter":"remoteJar","entryUrl":"https://example.test/config.json",
           "enabled":true,"authorization":"unknown","capabilities":[],
           "spider":"https://example.test/spider.jar"}
        ]}
      '''),
      throwsA(isA<SourceConfigurationException>()),
    );
  });

  test('版本与优先级只能使用受控整数范围', () {
    final config = SourceConfiguration.fromJsonString('''
      {"version":1,"sources":[
        {"id":"cctv-official","name":"央视","kind":"officialWeb",
         "adapter":"cctvOfficial","entryUrl":"$cctvEntry",
         "enabled":true,"authorization":"officialEntryOnly",
         "configVersion":2,"priority":42,"capabilities":["browse"]}
      ]}
    ''');

    expect(config.sources.single.source.configVersion, 2);
    expect(config.sources.single.source.priority, 42);
    expect(
      () => SourceConfiguration.fromJsonString('''
        {"version":1,"sources":[
          {"id":"cctv-official","name":"央视","kind":"officialWeb",
           "adapter":"cctvOfficial","entryUrl":"$cctvEntry",
           "enabled":true,"authorization":"officialEntryOnly",
           "priority":101,"capabilities":["browse"]}
        ]}
      '''),
      throwsA(isA<SourceConfigurationException>()),
    );
  });

  test('配置不能扩大内建来源的播放能力或替换官方入口', () {
    final config = SourceConfiguration.fromJsonString('''
      {"version":1,"sources":[
        {"id":"cctv-official","name":"央视","kind":"officialWeb",
         "adapter":"cctvOfficial","entryUrl":"https://not-cctv.example",
         "enabled":true,"authorization":"officialEntryOnly",
         "capabilities":["nativePublicPlayback"]}
      ]}
    ''');
    final repository = CctvRepository();
    addTearDown(repository.close);

    expect(
      () => MediaSourceAdapterFactory(
        cctvRepository: repository,
        client: MockClient((_) async => throw StateError('不应访问网络')),
      ).createAll(config),
      throwsA(isA<SourceConfigurationException>()),
    );
  });
}
