import 'package:shared_preferences/shared_preferences.dart';

/// 只保存用户主动停用的来源 ID；来源本身的授权和健康状态仍由注册表管理。
abstract interface class SourceEnablementStorage {
  Future<List<String>?> readStringList(String key);
  Future<void> writeStringList(String key, List<String> value);
}

class SharedPreferencesSourceEnablementStorage
    implements SourceEnablementStorage {
  SharedPreferencesSourceEnablementStorage({SharedPreferencesAsync? prefs})
      : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  @override
  Future<List<String>?> readStringList(String key) => _prefs.getStringList(key);

  @override
  Future<void> writeStringList(String key, List<String> value) =>
      _prefs.setStringList(key, value);
}

class SourceEnablementStore {
  SourceEnablementStore({SourceEnablementStorage? storage})
      : _storage = storage;

  static const _disabledKey = 'sources.disabled.v1';
  final SourceEnablementStorage? _storage;

  Future<Set<String>> loadDisabledSourceIds() async {
    try {
      final values =
          await (_storage ?? SharedPreferencesSourceEnablementStorage())
                  .readStringList(_disabledKey) ??
              const [];
      return values.where((item) => item.trim().isNotEmpty).toSet();
    } catch (_) {
      return const {};
    }
  }

  Future<void> setEnabled(String sourceId, bool enabled) async {
    try {
      final disabled = await loadDisabledSourceIds();
      if (enabled) {
        disabled.remove(sourceId);
      } else {
        disabled.add(sourceId);
      }
      await (_storage ?? SharedPreferencesSourceEnablementStorage())
          .writeStringList(_disabledKey, disabled.toList()..sort());
    } catch (_) {
      // 偏好写入失败不应绕过当前会话已生效的注册表策略。
    }
  }
}
