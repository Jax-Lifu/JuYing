class PlayableMedia {
  const PlayableMedia({
    required this.id,
    required this.title,
    required this.streamUri,
    required this.officialPageUri,
    this.posterUri,
    this.duration,
    this.qualityOptions = const [],
    this.httpHeaders = const {},
  });

  final String id;
  final String title;
  final Uri streamUri;
  final Uri officialPageUri;
  final Uri? posterUri;
  final Duration? duration;
  final List<PlaybackQuality> qualityOptions;
  final Map<String, String> httpHeaders;

  PlayableMedia copyWith({
    List<PlaybackQuality>? qualityOptions,
    Map<String, String>? httpHeaders,
  }) =>
      PlayableMedia(
        id: id,
        title: title,
        streamUri: streamUri,
        officialPageUri: officialPageUri,
        posterUri: posterUri,
        duration: duration,
        qualityOptions: qualityOptions ?? this.qualityOptions,
        httpHeaders: httpHeaders ?? this.httpHeaders,
      );
}

/// 已由来源适配器校验的清晰度选项，播放器不自行拼接来源 URL。
class PlaybackQuality {
  const PlaybackQuality({
    required this.id,
    required this.label,
    required this.streamUri,
    this.httpHeaders = const {},
    this.width,
    this.height,
    this.bandwidth,
  });

  final String id;
  final String label;
  final Uri streamUri;
  final Map<String, String> httpHeaders;
  final int? width;
  final int? height;
  final int? bandwidth;
}
