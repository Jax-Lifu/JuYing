import '../../domain/models/media_source.dart';
import '../../domain/models/child_profile.dart';
import '../../domain/models/unified_media.dart';
import 'child_content_policy.dart';
import 'source_policy.dart';

/// 一次查询或播放会话的用户策略上下文。未提供地区时不会猜测受限来源可用。
class MediaAccessContext {
  const MediaAccessContext({
    this.isChildProfile = false,
    this.childProfile,
    this.now,
    this.regionCode,
  });

  final bool isChildProfile;
  final ChildProfile? childProfile;
  final DateTime? now;
  final String? regionCode;

  static const adult = MediaAccessContext();
}

/// 授权、来源状态、地区与儿童规则的统一决策入口。
abstract final class MediaAccessPolicy {
  static bool allowsCategory(
    MediaCategory category, {
    required MediaAccessContext context,
  }) =>
      _allowsChildWindow(context) &&
      ChildContentPolicy.allowsCategory(
        category,
        isChildProfile: context.isChildProfile,
      );

  static SourceAccessDecision evaluateSource(
    MediaSource source,
    SourceAction action, {
    required MediaAccessContext context,
    required bool explicitSourceSelection,
  }) {
    final sourceDecision = SourcePolicy.evaluate(
      source,
      action,
      explicitSourceSelection: explicitSourceSelection,
    );
    if (!sourceDecision.allowed) return sourceDecision;
    if (!_allowsChildWindow(context)) {
      return const SourceAccessDecision.deny('当前不在儿童档案允许的观看时段');
    }
    final requiredRegion = source.regionCode?.trim().toUpperCase();
    final actualRegion = context.regionCode?.trim().toUpperCase();
    if (requiredRegion != null &&
        requiredRegion.isNotEmpty &&
        requiredRegion != actualRegion) {
      return const SourceAccessDecision.deny('该来源在当前地区不可用');
    }
    return const SourceAccessDecision.allow();
  }

  static SourceAccessDecision evaluateItem(
    MediaSource source,
    MediaItem item,
    SourceAction action, {
    required MediaAccessContext context,
    required bool explicitSourceSelection,
  }) {
    final sourceDecision = evaluateSource(
      source,
      action,
      context: context,
      explicitSourceSelection: explicitSourceSelection,
    );
    if (!sourceDecision.allowed) return sourceDecision;
    if (!ChildContentPolicy.allows(
      item,
      isChildProfile: context.isChildProfile,
    )) {
      return const SourceAccessDecision.deny('当前儿童档案不可访问该内容');
    }
    return const SourceAccessDecision.allow();
  }

  static bool _allowsChildWindow(MediaAccessContext context) {
    final profile = context.childProfile;
    return !context.isChildProfile ||
        profile == null ||
        profile.allowsViewingAt(context.now ?? DateTime.now());
  }
}
