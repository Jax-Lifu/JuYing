import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/services/tvbox_config_service.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';

const bool _runLive = bool.fromEnvironment('TVBOX_LIVE_TEST');

void main() {
  final skipReason = _runLive ? false : '需显式传入 TVBOX_LIVE_TEST=true';

  test(
    'BiliGuard children config -> keyword catalog -> selected page media bytes',
    () async {
      const site = TvBoxSite(
        key: 'bili_guard_children',
        name: '少儿教育',
        type: 3,
        api: 'csp_BiliGuard',
        ext: <String, String>{
          'json':
              'https://nos.netease.com/ysf/89370c8ddf36b5e1beb4d71adb921bda.txt',
        },
      );
      final engine = TvBoxSpiderEngine();
      final categories = await engine.fetchSiteCategories(site);
      expect(categories, isNotEmpty);
      expect(categories.any((category) => category.id == 'peizhi'), isFalse);
      final children = categories.firstWhere(
        (category) => category.id == '宝宝巴士',
      );
      final media = await engine.fetchCategoryMedia(site, children.id);
      expect(media, isNotEmpty);
      var completed = false;
      for (final item in media.take(10)) {
        final candidates = await engine.fetchMediaCandidates(site, item);
        if (candidates.isEmpty || candidates.first.episodes.isEmpty) continue;
        try {
          final episode =
              await candidates.first.episodes.first.resolvePlayback!();
          await _probe(episode.url, headers: episode.headers);
          completed = true;
          break;
        } on Exception {
          continue;
        } on StateError {
          continue;
        } on UnsupportedError {
          continue;
        }
      }
      expect(completed, isTrue);
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'xhztv portal: config -> csp_Bili Dart Spider -> direct playback',
    () async {
      final config = await TvBoxConfigService().loadConfig(
        'http://xhztv.top/xhz/',
      );
      expect(config, isNotNull);
      expect(config!.sites.length, greaterThanOrEqualTo(50));
      final site = config.sites.firstWhere(
        (item) => item.api.toLowerCase() == 'csp_bili',
      );
      final engine = TvBoxSpiderEngine();
      final categories = await engine.fetchSiteCategories(site);
      expect(categories, isNotEmpty);
      final media = await engine.fetchCategoryMedia(site, categories.first.id);
      expect(media, isNotEmpty);
      var completed = false;
      // 真实搜索结果可能混入已删除、地区受限或仅登录可看的视频；在线
      // 回归验证的是适配器能否从当前结果集完成播放链路，而不是把上游
      // 排名第一条的短期可用性误当成本地实现契约。
      for (final item in media.take(10)) {
        final candidates = await engine.fetchMediaCandidates(site, item);
        if (candidates.isEmpty || candidates.first.episodes.isEmpty) continue;
        final unresolved = candidates.first.episodes.first;
        try {
          final episode = unresolved.resolvePlayback == null
              ? unresolved
              : await unresolved.resolvePlayback!();
          await _probe(episode.url, headers: episode.headers);
          completed = true;
          break;
        } on Exception {
          // 选中分 P 时才会发现上游已删除或受限，继续检查当前结果集。
          continue;
        } on StateError {
          continue;
        } on UnsupportedError {
          continue;
        }
      }
      expect(completed, isTrue);
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '4k config: import -> healthy MacCMS -> detail playback candidates',
    () async {
      final config = await TvBoxConfigService().loadConfig(
        'http://xhztv.top/4k.json',
      );
      expect(config, isNotNull);
      expect(config!.sites.length, greaterThanOrEqualTo(45));
      final site = config.sites.firstWhere((item) => item.key == 'gszy');
      final engine = TvBoxSpiderEngine();
      final categories = await engine.fetchSiteCategories(site);
      expect(categories, isNotEmpty);
      final media = await engine.fetchCategoryMedia(site, categories.first.id);
      expect(media, isNotEmpty);
      var completed = false;
      for (final item in media.take(10)) {
        final candidates = await engine.fetchMediaCandidates(site, item);
        if (candidates.isEmpty || candidates.first.episodes.isEmpty) continue;
        final episode = candidates.first.episodes.first;
        await _probe(episode.url, headers: episode.headers);
        completed = true;
        break;
      }
      expect(completed, isTrue);
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'DC multi-warehouse: concurrent expansion -> standard T4 Spider playback',
    () async {
      final config = await TvBoxConfigService().loadConfig(
        'http://xhztv.top/DC.txt',
      );
      expect(config, isNotNull);
      expect(config!.sites.length, greaterThan(100));
      final engine = TvBoxSpiderEngine();
      final site = config.sites.firstWhere((item) => item.key == '酷克PHP');
      final categories = await engine.fetchSiteCategories(site);
      expect(categories, isNotEmpty);
      final media = await engine.fetchCategoryMedia(site, categories.first.id);
      expect(media, isNotEmpty);
      final candidates = await engine.fetchMediaCandidates(site, media.first);
      expect(candidates, isNotEmpty);
      final unresolved = candidates.first.episodes.first;
      final episode = unresolved.resolvePlayback == null
          ? unresolved
          : await unresolved.resolvePlayback!();
      expect(episode.requiresWebView, isFalse,
          reason: 'HTTP live probe only accepts a resolved media URL');
      await _probe(episode.url, headers: episode.headers);
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

/// 读取流的首个数据块后立即取消，避免 Live Test 下载完整视频。
Future<void> _probe(String url, {Map<String, String>? headers}) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: <String, String>{
        ...?headers,
      },
      responseType: ResponseType.stream,
      validateStatus: (status) => status != null && status < 400,
    ),
  );
  final response = await dio.get<ResponseBody>(url);
  expect(response.statusCode, anyOf(HttpStatus.ok, HttpStatus.partialContent));
  final firstChunk = await response.data!.stream.first;
  expect(firstChunk, isNotEmpty);
}
