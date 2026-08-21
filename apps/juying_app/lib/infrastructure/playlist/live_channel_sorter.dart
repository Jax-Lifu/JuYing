import 'm3u_playlist_parser.dart';

abstract final class LiveChannelSorter {
  static List<M3uChannel> sort(Iterable<M3uChannel> channels) {
    final result = channels.toList(growable: false);
    result.sort((left, right) {
      final leftNumber = int.tryParse(left.channelNumber ?? '');
      final rightNumber = int.tryParse(right.channelNumber ?? '');
      if (leftNumber != null && rightNumber != null) {
        final comparison = leftNumber.compareTo(rightNumber);
        if (comparison != 0) return comparison;
      } else if (leftNumber != null) {
        return -1;
      } else if (rightNumber != null) {
        return 1;
      }
      return left.name.compareTo(right.name);
    });
    return result;
  }
}
