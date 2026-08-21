import 'package:flutter_test/flutter_test.dart';
import 'package:juying/infrastructure/playlist/live_channel_sorter.dart';
import 'package:juying/infrastructure/playlist/m3u_playlist_parser.dart';

void main() {
  test('直播频道优先按显式频道号排序', () {
    final channels = [
      _channel('未编号', null),
      _channel('二台', '2'),
      _channel('十台', '10'),
      _channel('一台', '1'),
    ];

    expect(
      LiveChannelSorter.sort(channels).map((channel) => channel.name),
      ['一台', '二台', '十台', '未编号'],
    );
  });
}

M3uChannel _channel(String name, String? number) => M3uChannel(
      id: name,
      name: name,
      streamUri: Uri.parse('https://stream.example/$name.m3u8'),
      channelNumber: number,
    );
