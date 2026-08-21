import 'package:flutter_test/flutter_test.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/infrastructure/cctv/cctv_channel_logo_resolver.dart';
import 'package:juying/infrastructure/cctv/cctv_live_official_adapter.dart';

void main() {
  final adapter = CctvLiveOfficialAdapter();

  test('官方直播来源输出统一直播目录、选集和官网回退', () async {
    final page = await adapter.browse(
      const MediaCatalogQuery(category: MediaCategory.live, pageSize: 24),
    );
    final channel = page.items.first;
    final episode = (await adapter.episodes(channel)).single;
    final fallback = await adapter.resolveOfficialFallback(episode);

    expect(channel.sourceId, CctvLiveOfficialAdapter.sourceId);
    expect(channel.category, MediaCategory.live);
    expect(page.total, greaterThanOrEqualTo(18));
    expect(channel.posterUri, isNotNull);
    expect(channel.posterUri.toString(), contains('CCTV1.png'));
    expect(fallback.officialPageUri.host, 'tv.cctv.com');
    expect(fallback.nativeStreamUri, isNull);

    final nativePlayback = await adapter.resolvePlayback(episode);
    expect(nativePlayback.nativeStreamUri, isNotNull);
    expect(nativePlayback.nativeStreamUri.toString(), contains('.m3u8'));
    expect(nativePlayback.httpHeaders['Referer'], contains('cctv.com'));
  });

  test('官方直播来源搜索频道名称', () async {
    final hits = await adapter.search('少儿');
    expect(hits.single.item.title, 'CCTV-14 少儿');
    expect(hits.single.item.posterUri.toString(), contains('CCTV14.png'));
  });

  test('CctvChannelLogoResolver 解析不同频道的图标封面', () {
    expect(
      CctvChannelLogoResolver.resolve('CCTV-1 综合')?.toString(),
      'https://live.fanmingming.com/tv/CCTV1.png',
    );
    expect(
      CctvChannelLogoResolver.resolve('CCTV5+ 体育赛事')?.toString(),
      'https://live.fanmingming.com/tv/CCTV5plus.png',
    );
    expect(
      CctvChannelLogoResolver.resolve('CCTV-13 新闻')?.toString(),
      'https://live.fanmingming.com/tv/CCTV13.png',
    );
    expect(
      CctvChannelLogoResolver.resolve('CCTV 4K')?.toString(),
      'https://live.fanmingming.com/tv/CCTV4K.png',
    );
    expect(
      CctvChannelLogoResolver.resolve('湖南卫视')?.toString(),
      contains('%E6%B9%96%E5%8D%97%E5%8D%AB%E8%A7%86.png'),
    );
  });
}
