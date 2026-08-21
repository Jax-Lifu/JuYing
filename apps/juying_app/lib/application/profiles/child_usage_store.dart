import 'package:shared_preferences/shared_preferences.dart';

/// 儿童每日观看时长仅归属具体儿童档案与当天，不能与成人历史混用。
class ChildUsageStore {
  ChildUsageStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  final SharedPreferencesAsync? _preferences;

  Future<Duration> consumedToday(String profileId, {DateTime? now}) async {
    try {
      final seconds = await (_preferences ?? SharedPreferencesAsync()).getInt(
            _key(profileId, now ?? DateTime.now()),
          ) ??
          0;
      return Duration(seconds: seconds.clamp(0, 24 * 60 * 60));
    } catch (_) {
      return Duration.zero;
    }
  }

  Future<Duration> addWatchTime(
    String profileId,
    Duration delta, {
    DateTime? now,
  }) async {
    if (delta <= Duration.zero) return consumedToday(profileId, now: now);
    final current = await consumedToday(profileId, now: now);
    final total = current + delta;
    try {
      final preferences = _preferences ?? SharedPreferencesAsync();
      final value = now ?? DateTime.now();
      final key = _key(profileId, value);
      await preferences.setInt(
        key,
        total.inSeconds.clamp(0, 24 * 60 * 60),
      );
      final days = await preferences.getStringList(_daysKey(profileId)) ??
          const <String>[];
      final day = _day(value);
      if (!days.contains(day)) {
        await preferences.setStringList(_daysKey(profileId), [...days, day]);
      }
    } catch (_) {
      // 存储暂时不可用时不阻塞当前授权播放；下次计量会重新尝试。
    }
    return total;
  }

  Future<void> clearProfile(String profileId) async {
    final preferences = _preferences ?? SharedPreferencesAsync();
    final days = await preferences.getStringList(_daysKey(profileId)) ??
        const <String>[];
    for (final day in days) {
      await preferences.remove('child.usage.v1.$profileId.$day');
    }
    await preferences.remove(_daysKey(profileId));
  }

  String _key(String profileId, DateTime value) {
    final day = _day(value);
    return 'child.usage.v1.$profileId.$day';
  }

  String _day(DateTime value) => '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  String _daysKey(String profileId) => 'child.usage.days.v1.$profileId';
}
