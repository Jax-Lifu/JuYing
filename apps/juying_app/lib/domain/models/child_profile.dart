enum ChildAgeBand { age3to5, age6to8, age9to12, teen }

enum ProfileKind { adult, child }

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.displayName,
    required this.ageBand,
    required this.dailyLimitMinutes,
    required this.allowedRating,
    this.allowedStartHour = 0,
    this.allowedEndHour = 24,
  })  : assert(allowedStartHour >= 0 && allowedStartHour <= 23),
        assert(allowedEndHour >= 1 && allowedEndHour <= 24),
        assert(allowedStartHour != allowedEndHour);

  final String id;
  final String displayName;
  final ChildAgeBand ageBand;
  final int dailyLimitMinutes;
  final String allowedRating;

  /// 本地时区下的观看时段，起始含、结束不含；可跨午夜。
  final int allowedStartHour;
  final int allowedEndHour;

  bool allowsViewingAt(DateTime now) {
    final hour = now.hour;
    if (allowedStartHour < allowedEndHour) {
      return hour >= allowedStartHour && hour < allowedEndHour;
    }
    return hour >= allowedStartHour || hour < allowedEndHour;
  }
}

/// 家庭档案是用户数据的顶级归属；儿童档案必须携带 [child] 策略。
class FamilyProfile {
  const FamilyProfile({
    required this.id,
    required this.displayName,
    required this.kind,
    this.child,
  }) : assert((kind == ProfileKind.child) == (child != null));

  final String id;
  final String displayName;
  final ProfileKind kind;
  final ChildProfile? child;

  bool get isChild => kind == ProfileKind.child;
}
