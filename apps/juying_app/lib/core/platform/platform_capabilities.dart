enum DeviceFamily { phone, tablet, tv, car, desktop, web }

class PlatformCapabilities {
  const PlatformCapabilities({
    required this.family,
    required this.supportsTouch,
    required this.supportsRemoteFocus,
    required this.supportsBackgroundAudio,
    required this.canBrowseWhileDriving,
  });

  final DeviceFamily family;
  final bool supportsTouch;
  final bool supportsRemoteFocus;
  final bool supportsBackgroundAudio;
  final bool canBrowseWhileDriving;

  static const safeCarDefaults = PlatformCapabilities(
    family: DeviceFamily.car,
    supportsTouch: false,
    supportsRemoteFocus: true,
    supportsBackgroundAudio: true,
    canBrowseWhileDriving: false,
  );
}
