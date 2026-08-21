import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:juying/infrastructure/tvbox/tvbox_config_parser.dart';
import 'package:juying/infrastructure/tvbox/tvbox_csp_runtime.dart';

Future<void> main() async {
  final client = http.Client();
  try {
    final configUri = Uri.parse('http://xhztv.top/xhz/');
    final response = await client.get(configUri);
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final sites = TvboxConfigParser.parseCspSites(text, baseUri: configUri);
    stdout.writeln('csp sites=${sites.map((site) => site.key).join(',')}');
    final site = sites.firstWhere((site) => site.key == 'csp_DouDou');
    final runtime = ProcessTvboxCspRuntime(
      client: client,
      hostDirectory: Directory('build/windows/x64/runner/Debug/tvbox_csp_host')
          .absolute
          .path,
    );
    final stopwatch = Stopwatch()..start();
    final home = await runtime.invoke(site, 'home', [true]) as Map;
    stdout.writeln('home classes=${(home['class'] as List?)?.length ?? 0} '
        'items=${(home['list'] as List?)?.length ?? 0} '
        'elapsed=${stopwatch.elapsedMilliseconds}ms');
    final firstClass = (home['class'] as List).first as Map;
    final category = await runtime.invoke(site, 'category', [
      firstClass['type_id'].toString(),
      '1',
      true,
      <String, String>{},
    ]) as Map;
    final items = category['list'] as List? ?? const [];
    stdout.writeln('category=${firstClass['type_name']} items=${items.length} '
        'sample=${items.isEmpty ? '-' : (items.first as Map)['vod_name']} '
        'elapsed=${stopwatch.elapsedMilliseconds}ms');
    if (items.isNotEmpty) stdout.writeln('sample item=${items.first}');

    final kkys = TvboxCspSite(
      key: 'probe_Kkys',
      name: 'Kkys probe',
      apiUri: site.jarUri,
      ext: '',
      className: 'com.github.catvod.spider.Kkys',
      jarUri: site.jarUri,
      jarMd5: site.jarMd5,
    );
    try {
      final kkysHome = await runtime.invoke(kkys, 'home', [true]) as Map;
      final kkysClass = (kkysHome['class'] as List).first as Map;
      final kkysCategory = await runtime.invoke(kkys, 'category', [
        kkysClass['type_id'].toString(),
        '1',
        true,
        <String, String>{},
      ]) as Map;
      final kkysItem = (kkysCategory['list'] as List).first as Map;
      final kkysDetail = await runtime.invoke(
        kkys,
        'detail',
        [kkysItem['vod_id'].toString()],
      ) as Map;
      final kkysDetailItem = (kkysDetail['list'] as List).first as Map;
      final kkysPlay =
          kkysDetailItem['vod_play_url'].toString().split('#').first;
      final kkysSeparator = kkysPlay.indexOf(r'$');
      final kkysPlayer = await runtime.invoke(kkys, 'play', [
        kkysDetailItem['vod_play_from'].toString().split(r'$$$').first,
        kkysSeparator < 0 ? kkysPlay : kkysPlay.substring(kkysSeparator + 1),
        <String>[],
      ]);
      stdout.writeln('csp full-flow site=Kkys item=${kkysItem['vod_name']} '
          'player=$kkysPlayer');
    } catch (error) {
      stdout.writeln('csp full-flow site=Kkys failed=$error');
    }

    TvboxCspSite? playableSite;
    Map? playableHome;
    Map? playableCategory;
    for (final key in [
      'csp_Czsapp',
      'csp_YQKan',
      'csp_NanGua',
      '酷看',
      '率率',
      '萌米',
      '星奇',
      'csp_Auete',
      'csp_MLYS',
      'csp_Kuaikan',
      'csp_Kunyu77',
      'csp_Dm84',
    ]) {
      final candidate = sites.firstWhere((site) => site.key == key);
      try {
        final homeResult = await runtime.invoke(candidate, 'home', [true]);
        if (homeResult is! Map ||
            (homeResult['class'] as List?)?.isNotEmpty != true) {
          continue;
        }
        final candidateClass = (homeResult['class'] as List).first as Map;
        final categoryResult = await runtime.invoke(candidate, 'category', [
          candidateClass['type_id'].toString(),
          '1',
          true,
          <String, String>{},
        ]);
        if (categoryResult is! Map ||
            (categoryResult['list'] as List?)?.isNotEmpty != true) {
          continue;
        }
        playableSite = candidate;
        playableHome = homeResult;
        playableCategory = categoryResult;
        break;
      } catch (error) {
        stdout.writeln('home site=${candidate.name} failed=$error');
      }
    }
    if (playableSite == null ||
        playableHome == null ||
        playableCategory == null) {
      throw StateError('没有找到可验证的完整 CSP 站点');
    }
    final playableItem = (playableCategory['list'] as List).first as Map;
    final detail = await runtime.invoke(
      playableSite,
      'detail',
      [playableItem['vod_id'].toString()],
    ) as Map;
    final detailItem = (detail['list'] as List).first as Map;
    final firstPlay = detailItem['vod_play_url'].toString().split('#').first;
    final separator = firstPlay.indexOf(r'$');
    final player = await runtime.invoke(playableSite, 'play', [
      detailItem['vod_play_from'].toString().split(r'$$$').first,
      separator < 0 ? firstPlay : firstPlay.substring(separator + 1),
      <String>[],
    ]);
    stdout.writeln('playable site=${playableSite.name} '
        'item=${playableItem['vod_name']} player=$player');
  } finally {
    client.close();
  }
}
