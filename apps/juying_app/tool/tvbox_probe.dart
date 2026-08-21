import 'package:http/http.dart' as http;
import 'package:juying/infrastructure/tvbox/tvbox_config_parser.dart';
import 'package:juying/infrastructure/network/safe_text_response_decoder.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    throw ArgumentError('用法：dart run tool/tvbox_probe.dart <TVBox 配置 URL>');
  }
  final uri = Uri.parse(arguments.first);
  final response = await http.get(uri).timeout(const Duration(seconds: 15));
  final text = await SafeTextResponseDecoder.decode(
    response.bodyBytes,
    maxDecodedBytes: 512 * 1024,
    contentEncoding: response.headers['content-encoding'],
  );
  final repositories = TvboxConfigParser.parseRepositories(text, baseUri: uri);
  final standard = TvboxConfigParser.parseStandardSites(text, baseUri: uri);
  final javascript = TvboxConfigParser.parseJavascriptSites(text, baseUri: uri);
  final lives = TvboxConfigParser.parseDirectLives(text, baseUri: uri);
  // ignore: avoid_print
  print('HTTP ${response.statusCode}, bytes=${response.bodyBytes.length}, '
      'repositories=${repositories.length}, standard=${standard.length}, '
      'javascript=${javascript.length}, lives=${lives.length}');
  for (final entry in repositories.take(20)) {
    // ignore: avoid_print
    print('repository\t${entry.name}\t${entry.configUri}');
  }
  for (final site in standard.take(30)) {
    // ignore: avoid_print
    print('site\t${site.name}\t${site.apiUri}');
  }
  for (final site in javascript.take(30 - standard.length.clamp(0, 30))) {
    // ignore: avoid_print
    print('site-js\t${site.name}\t${site.apiUri}');
  }
}
