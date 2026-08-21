import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:juying/domain/models/tvbox_source.dart';
import 'package:juying/domain/models/unified_media.dart';
import 'package:juying/infrastructure/tvbox/tvbox_config_adapter.dart';

Future<void> main(List<String> args) async {
  final urls = args.isEmpty
      ? const [
          'http://xhztv.top/xhz/',
          'http://xhztv.top/4k.json',
          'http://xhztv.top/DC.txt',
        ]
      : args;
  final client = http.Client();
  try {
    for (final raw in urls) {
      final uri = Uri.parse(raw);
      final adapter = TvboxConfigAdapter(
        definition: TvboxSourceDefinition(
          id: 'probe-${uri.path.hashCode}',
          name: raw,
          configUri: uri,
          rightsConfirmedAt: DateTime.now(),
        ),
        client: client,
        initialCategory: MediaCategory.movie,
      );
      stdout.writeln('\nSOURCE $raw');
      try {
        await adapter.validate().timeout(const Duration(seconds: 20));
        final scopes =
            await adapter.catalogScopes().timeout(const Duration(seconds: 30));
        stdout.writeln('scopes=${scopes.length}');
        final page = await adapter
            .browse(const MediaCatalogQuery(
              category: MediaCategory.movie,
              pageSize: 8,
            ))
            .timeout(const Duration(seconds: 45));
        stdout.writeln(
          'selected=${adapter.selectedCatalogScopeId} items=${page.items.length}',
        );
        if (page.items.isEmpty) continue;
        final item = page.items.first;
        stdout.writeln('item=${item.title} id=${item.sourceItemId}');
        final episodes =
            await adapter.episodes(item).timeout(const Duration(seconds: 60));
        stdout.writeln('episodes=${episodes.length}');
        if (episodes.isEmpty) continue;
        Object? lastError;
        for (final episode in episodes.take(5)) {
          try {
            final playback = await adapter
                .resolvePlayback(episode)
                .timeout(const Duration(seconds: 30));
            stdout.writeln(
              'PLAY ${episode.title} => ${playback.nativeStreamUri}',
            );
            lastError = null;
            break;
          } catch (error) {
            lastError = error;
          }
        }
        if (lastError != null) stdout.writeln('play failed=$lastError');
      } catch (error, stack) {
        stdout.writeln('FAILED $error\n$stack');
      }
    }
  } finally {
    client.close();
  }
}
