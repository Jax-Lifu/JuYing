import '../playlist/m3u_playlist_parser.dart';

/// TVBox 直连直播清单兼容层，支持扩展 M3U 和 `频道,地址` TXT 格式。
abstract final class TvboxLivePlaylistParser {
  static const maxChannels = 10000;

  static List<M3uChannel> parse(
    String input, {
    Uri? baseUri,
    Map<String, String> defaultHeaders = const {},
  }) =>
      M3uPlaylistParser.parse(
        input,
        baseUri: baseUri,
        defaultHeaders: defaultHeaders,
      );
}
