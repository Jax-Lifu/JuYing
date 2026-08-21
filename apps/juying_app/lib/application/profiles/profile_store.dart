import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/child_profile.dart';

/// 非敏感档案数据放在本机偏好；家长 PIN 只写入系统安全存储。
class ProfileStore {
  ProfileStore({
    SharedPreferencesAsync? preferences,
    FlutterSecureStorage? secureStorage,
  })  : _preferences = preferences,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const defaultProfileId = 'adult-default';
  static const _profilesKey = 'profiles.v1';
  static const _activeProfileKey = 'profiles.active.v1';
  static const _parentPinKey = 'profiles.parent-pin.v1';
  final SharedPreferencesAsync? _preferences;
  final FlutterSecureStorage _secureStorage;

  Future<List<FamilyProfile>> load() async {
    try {
      final raw = await (_preferences ?? SharedPreferencesAsync())
          .getString(_profilesKey);
      if (raw == null) return const [_defaultAdult];
      final value = jsonDecode(raw);
      if (value is! List) return const [_defaultAdult];
      final profiles = value
          .whereType<Map>()
          .map((item) => _decodeProfile(Map<String, dynamic>.from(item)))
          .whereType<FamilyProfile>()
          .toList(growable: false);
      return profiles.any((item) => item.id == defaultProfileId)
          ? profiles
          : [_defaultAdult, ...profiles];
    } catch (_) {
      return const [_defaultAdult];
    }
  }

  Future<void> save(List<FamilyProfile> profiles) async {
    if (!profiles.any((profile) => profile.id == defaultProfileId)) {
      throw ArgumentError('必须保留默认成人档案');
    }
    await (_preferences ?? SharedPreferencesAsync()).setString(
      _profilesKey,
      jsonEncode(profiles.map(_encodeProfile).toList(growable: false)),
    );
  }

  Future<String> loadActiveProfileId() async {
    try {
      return await (_preferences ?? SharedPreferencesAsync()).getString(
            _activeProfileKey,
          ) ??
          defaultProfileId;
    } catch (_) {
      return defaultProfileId;
    }
  }

  Future<void> setActiveProfileId(String id) =>
      (_preferences ?? SharedPreferencesAsync())
          .setString(_activeProfileKey, id);

  Future<bool> hasParentPin() async {
    try {
      return await _secureStorage.containsKey(key: _parentPinKey);
    } catch (_) {
      return false;
    }
  }

  Future<void> setParentPin(String pin) async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw ArgumentError.value(pin, 'pin', 'PIN 必须为 4–8 位数字');
    }
    await _secureStorage.write(key: _parentPinKey, value: pin);
  }

  Future<bool> verifyParentPin(String pin) async {
    try {
      return await _secureStorage.read(key: _parentPinKey) == pin;
    } catch (_) {
      return false;
    }
  }

  static const _defaultAdult = FamilyProfile(
    id: defaultProfileId,
    displayName: '成人',
    kind: ProfileKind.adult,
  );

  Map<String, Object?> _encodeProfile(FamilyProfile profile) => {
        'id': profile.id,
        'displayName': profile.displayName,
        'kind': profile.kind.name,
        if (profile.child != null)
          'child': {
            'ageBand': profile.child!.ageBand.name,
            'dailyLimitMinutes': profile.child!.dailyLimitMinutes,
            'allowedRating': profile.child!.allowedRating,
            'allowedStartHour': profile.child!.allowedStartHour,
            'allowedEndHour': profile.child!.allowedEndHour,
          },
      };

  FamilyProfile? _decodeProfile(Map<String, dynamic> value) {
    final id = value['id'];
    final displayName = value['displayName'];
    final kind = ProfileKind.values
        .where((item) => item.name == value['kind'])
        .firstOrNull;
    if (id is! String || displayName is! String || kind == null) return null;
    if (kind == ProfileKind.adult) {
      return FamilyProfile(id: id, displayName: displayName, kind: kind);
    }
    final child = value['child'];
    if (child is! Map) return null;
    final ageBand = ChildAgeBand.values
        .where((item) => item.name == child['ageBand'])
        .firstOrNull;
    final dailyLimit = child['dailyLimitMinutes'];
    final rating = child['allowedRating'];
    final startHour = child['allowedStartHour'];
    final endHour = child['allowedEndHour'];
    if (ageBand == null || dailyLimit is! int || rating is! String) return null;
    return FamilyProfile(
      id: id,
      displayName: displayName,
      kind: kind,
      child: ChildProfile(
        id: id,
        displayName: displayName,
        ageBand: ageBand,
        dailyLimitMinutes: dailyLimit,
        allowedRating: rating,
        allowedStartHour: startHour is int && startHour >= 0 && startHour <= 23
            ? startHour
            : 0,
        allowedEndHour:
            endHour is int && endHour >= 1 && endHour <= 24 ? endHour : 24,
      ),
    );
  }
}
