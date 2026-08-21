import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/infrastructure/tvbox/tvbox_config_parser.dart';
import 'package:juying/infrastructure/tvbox/tvbox_standard_site_adapter.dart';

Future<void> main() async {
  final client = http.Client();
  try {
    final configUri = Uri.parse('http://xhztv.top/4k.json');
    final response = await client.get(configUri);
    final config = utf8.decode(response.bodyBytes, allowMalformed: true);
    final sites =
        TvboxConfigParser.parseStandardSites(config, baseUri: configUri);
    for (final site in sites) {
      try {
        final adapter = TvboxStandardSiteAdapter(
          sourceId: 'probe',
          site: site,
          client: client,
          fallbackUri: configUri,
        );
        final page = await adapter.browse(
          const MediaCatalogQuery(category: MediaCategory.movie),
        );
        if (page.items.isEmpty) continue;
        final item = page.items.first;
        final episodes = await adapter.episodes(item);
        if (episodes.isEmpty) continue;
        final playback = await adapter.resolvePlayback(episodes.first);
        stdout.writeln(
            'site=${site.name} item=${item.title} episodes=${episodes.length} '
            'stream=${playback.nativeStreamUri}');
        return;
      } catch (error) {
        stdout.writeln('site=${site.name} failed=$error');
      }
    }
    throw StateError('没有找到可完成全链路的标准站点');
  } finally {
    client.close();
  }
}
