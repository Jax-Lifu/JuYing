import '../../domain/models/media_source.dart';

enum SourceAction { browse, search, episodes, nativePlayback, officialFallback }

class SourceAccessDecision {
  const SourceAccessDecision._(this.allowed, this.reason);

  const SourceAccessDecision.allow() : this._(true, null);
  const SourceAccessDecision.deny(String reason) : this._(false, reason);

  final bool allowed;
  final String? reason;
}

/// 所有来源入口必须先经此策略；UI 不得根据来源名称自行猜测能力。
abstract final class SourcePolicy {
  static SourceAccessDecision evaluate(
    MediaSource source,
    SourceAction action, {
    required bool explicitSourceSelection,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    if (!source.isActive) return const SourceAccessDecision.deny('来源当前未启用');
    if (source.health == SourceHealth.unavailable) {
      return const SourceAccessDecision.deny('来源当前不可用');
    }
    if (source.authorizationExpiresAt?.isBefore(currentTime) ?? false) {
      return const SourceAccessDecision.deny('来源授权已过期');
    }
    if (!_hasCapability(source, action)) {
      return const SourceAccessDecision.deny('来源未声明该能力');
    }

    return switch (source.authorization) {
      SourceAuthorization.licensed ||
      SourceAuthorization.userOwned =>
        const SourceAccessDecision.allow(),
      SourceAuthorization.officialEntryOnly => switch (action) {
          SourceAction.officialFallback => const SourceAccessDecision.allow(),
          SourceAction.browse ||
          SourceAction.search ||
          SourceAction.nativePlayback ||
          SourceAction.episodes when explicitSourceSelection =>
            const SourceAccessDecision.allow(),
          _ => const SourceAccessDecision.deny('该来源仅允许通过官方入口使用'),
        },
      SourceAuthorization.unknown =>
        const SourceAccessDecision.deny('来源授权状态未知'),
    };
  }

  static bool _hasCapability(MediaSource source, SourceAction action) =>
      source.capabilities.contains(switch (action) {
        SourceAction.browse => SourceCapability.browse,
        SourceAction.search => SourceCapability.search,
        SourceAction.episodes => SourceCapability.episodes,
        SourceAction.nativePlayback => SourceCapability.nativePublicPlayback,
        SourceAction.officialFallback => SourceCapability.officialFallback,
      });
}
