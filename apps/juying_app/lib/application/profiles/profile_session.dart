import 'package:flutter/foundation.dart';

import '../../domain/models/child_profile.dart';
import 'profile_data_cleaner.dart';
import 'profile_store.dart';

/// 应用内唯一活动档案。所有历史、策略和播放入口都应从此会话取得归属。
class ProfileSession extends ChangeNotifier {
  ProfileSession({
    ProfileStore? store,
    ProfileDataCleaner? dataCleaner,
  })  : _store = store ?? ProfileStore(),
        _dataCleaner = dataCleaner ?? ProfileDataCleaner();

  final ProfileStore _store;
  final ProfileDataCleaner _dataCleaner;
  List<FamilyProfile> _profiles = const [
    FamilyProfile(
      id: ProfileStore.defaultProfileId,
      displayName: '成人',
      kind: ProfileKind.adult,
    ),
  ];
  String _activeProfileId = ProfileStore.defaultProfileId;
  var _isLoaded = false;

  List<FamilyProfile> get profiles => List.unmodifiable(_profiles);
  bool get isLoaded => _isLoaded;
  FamilyProfile get activeProfile => _profiles.firstWhere(
        (profile) => profile.id == _activeProfileId,
        orElse: () => _profiles.first,
      );

  Future<void> initialize() async {
    _profiles = await _store.load();
    final savedId = await _store.loadActiveProfileId();
    _activeProfileId = _profiles.any((profile) => profile.id == savedId)
        ? savedId
        : ProfileStore.defaultProfileId;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> select(String profileId) async {
    if (!_profiles.any((profile) => profile.id == profileId)) {
      throw ArgumentError.value(profileId, 'profileId', '档案不存在');
    }
    _activeProfileId = profileId;
    await _store.setActiveProfileId(profileId);
    notifyListeners();
  }

  Future<void> addChild({
    required String displayName,
    required ChildAgeBand ageBand,
    required int dailyLimitMinutes,
    int allowedStartHour = 0,
    int allowedEndHour = 24,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty ||
        dailyLimitMinutes <= 0 ||
        allowedStartHour < 0 ||
        allowedStartHour > 23 ||
        allowedEndHour < 1 ||
        allowedEndHour > 24 ||
        allowedStartHour == allowedEndHour) {
      throw ArgumentError('儿童姓名和每日时长必须有效');
    }
    final id = 'child-${DateTime.now().microsecondsSinceEpoch}';
    final profile = FamilyProfile(
      id: id,
      displayName: name,
      kind: ProfileKind.child,
      child: ChildProfile(
        id: id,
        displayName: name,
        ageBand: ageBand,
        dailyLimitMinutes: dailyLimitMinutes,
        allowedRating: _ratingFor(ageBand),
        allowedStartHour: allowedStartHour,
        allowedEndHour: allowedEndHour,
      ),
    );
    _profiles = [..._profiles, profile];
    await _store.save(_profiles);
    notifyListeners();
  }

  Future<void> deleteChild(String profileId) async {
    final profile = _profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null || !profile.isChild) {
      throw ArgumentError.value(profileId, 'profileId', '只能删除存在的儿童档案');
    }
    // 先删除档案私有数据；失败时档案保留，用户可安全重试。
    await _dataCleaner.clear(profileId);
    _profiles = _profiles.where((item) => item.id != profileId).toList();
    if (_activeProfileId == profileId) {
      _activeProfileId = ProfileStore.defaultProfileId;
      await _store.setActiveProfileId(_activeProfileId);
    }
    await _store.save(_profiles);
    notifyListeners();
  }

  Future<bool> hasParentPin() => _store.hasParentPin();
  Future<void> setParentPin(String pin) => _store.setParentPin(pin);
  Future<bool> verifyParentPin(String pin) => _store.verifyParentPin(pin);

  static String _ratingFor(ChildAgeBand ageBand) => switch (ageBand) {
        ChildAgeBand.age3to5 => '3+',
        ChildAgeBand.age6to8 => '6+',
        ChildAgeBand.age9to12 => '9+',
        ChildAgeBand.teen => '13+',
      };
}
