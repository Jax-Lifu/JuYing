/// 作品聚类只用于展示，永远不能替代 sourceId:sourceItemId 或集键。
///
/// 适配器只有在拿到可信的跨来源权威 ID 时才可填入；标题相同并不构成身份。
enum MediaWorkIdentityEvidence {
  verifiedExternalId('已验证权威作品 ID'),
  manualOverride('人工确认');

  const MediaWorkIdentityEvidence(this.label);
  final String label;
}

class MediaWorkIdentity {
  const MediaWorkIdentity({
    required this.id,
    required this.evidence,
  });

  /// 与来源无关且长期稳定的作品键，例如获得授权的权威内容 ID。
  final String id;
  final MediaWorkIdentityEvidence evidence;
}
