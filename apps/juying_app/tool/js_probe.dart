import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/infrastructure/tvbox/tvbox_config_parser.dart';
import 'package:juying/infrastructure/tvbox/tvbox_javascript_runtime.dart';
import 'package:juying/infrastructure/tvbox/tvbox_javascript_site_adapter.dart';

Future<void> main() async {
  final configUri = Uri.parse('http://xhztv.top/4k.json');
  final response = await http.get(configUri);
  final config = utf8.decode(response.bodyBytes, allowMalformed: true);
  final sites = TvboxConfigParser.parseJavascriptSites(
    config,
    baseUri: configUri,
  );
  final runtime = ProcessTvboxJavascriptRuntime(
    executablePath: File(
      'build/windows/x64/runner/Debug/juying_tvbox_js_host.exe',
    ).absolute.path,
  );
  for (final site in sites) {
    try {
      final adapter = TvboxJavascriptSiteAdapter(
        sourceId: 'probe',
        site: site,
        runtime: runtime,
        fallbackUri: configUri,
      );
      for (final category in [
        MediaCategory.movie,
        MediaCategory.drama,
        MediaCategory.other,
      ]) {
        final page =
            await adapter.browse(MediaCatalogQuery(category: category));
        if (page.items.isEmpty) continue;
        final item = page.items.first;
        final episodes = await adapter.episodes(item);
        if (episodes.isEmpty) continue;
        final playback = await adapter.resolvePlayback(episodes.first);
        stdout.writeln('site=${site.name} item=${item.title} '
            'episodes=${episodes.length} stream=${playback.nativeStreamUri}');
        return;
      }
    } catch (error) {
      stdout.writeln('site=${site.name} failed=$error');
    }
  }
  throw StateError('没有找到可完成全链路的 JavaScript type=3 站点');
}
