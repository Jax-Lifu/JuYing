import '../favorites/favorite_store.dart';
import '../playback/playback_history_store.dart';
import '../playback/playback_preference_store.dart';
import 'child_usage_store.dart';

/// 删除档案前清除仅归属该档案的本地数据；不触及其他成人或儿童档案。
class ProfileDataCleaner {
  ProfileDataCleaner({
    PlaybackHistoryStore? historyStore,
    FavoriteStore? favoriteStore,
    PlaybackPreferenceStore? preferenceStore,
    ChildUsageStore? childUsageStore,
  })  : _historyStore = historyStore,
        _favoriteStore = favoriteStore,
        _preferenceStore = preferenceStore,
        _childUsageStore = childUsageStore;

  // 默认实现延迟到真正删除档案时创建，避免应用启动和纯界面测试初始化
  // 尚未注册的平台偏好存储。
  final PlaybackHistoryStore? _historyStore;
  final FavoriteStore? _favoriteStore;
  final PlaybackPreferenceStore? _preferenceStore;
  final ChildUsageStore? _childUsageStore;

  Future<void> clear(String profileId) async {
    await Future.wait([
      (_historyStore ?? PlaybackHistoryStore())
          .clearProfile(profileId: profileId),
      (_favoriteStore ?? FavoriteStore()).clearProfile(profileId),
      (_preferenceStore ?? PlaybackPreferenceStore()).clearProfile(profileId),
      (_childUsageStore ?? ChildUsageStore()).clearProfile(profileId),
    ]);
  }
}
