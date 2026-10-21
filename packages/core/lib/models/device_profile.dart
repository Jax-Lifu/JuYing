/// Hardware quirks and capability flags for DLNA rendering devices.
///
/// **What**: Defines device-specific quirks to compensate for protocol discrepancies
/// across smart TVs and DLNA renderers.
///
/// **Why**: DLNA standards compliance varies significantly across vendors (e.g., Xiaomi,
/// Sony, Huawei, Samsung). Device quirks enable targeted workarounds (such as container
/// remuxing, Range header adjustments, or omitting external subtitles).
class DeviceQuirks {
  const DeviceQuirks({
    this.supportsRange = true,
    this.supportsMkv = true,
    this.supportsHevc = true,
    this.requiresContentFeatures = false,
    this.ignoreSidecarSubtitle = false,
  });

  /// Whether the renderer handles HTTP 206 Partial Content Range streaming.
  final bool supportsRange;

  /// Whether the renderer natively supports MKV containers without remuxing.
  final bool supportsMkv;

  /// Whether the renderer supports H.265 / HEVC video decoding.
  final bool supportsHevc;

  /// Whether the device requires `contentFeatures.dlna.org` headers in responses.
  final bool requiresContentFeatures;

  /// Whether the renderer fails when sidecar external subtitles are attached.
  final bool ignoreSidecarSubtitle;

  DeviceQuirks copyWith({
    bool? supportsRange,
    bool? supportsMkv,
    bool? supportsHevc,
    bool? requiresContentFeatures,
    bool? ignoreSidecarSubtitle,
  }) {
    return DeviceQuirks(
      supportsRange: supportsRange ?? this.supportsRange,
      supportsMkv: supportsMkv ?? this.supportsMkv,
      supportsHevc: supportsHevc ?? this.supportsHevc,
      requiresContentFeatures:
          requiresContentFeatures ?? this.requiresContentFeatures,
      ignoreSidecarSubtitle:
          ignoreSidecarSubtitle ?? this.ignoreSidecarSubtitle,
    );
  }
}

/// Device compatibility profile for matching discovered DLNA renderers.
///
/// **What**: Pairs manufacturer and model regular expressions with [DeviceQuirks].
///
/// **Why**: Appendix 12.2 of the JuYing guidance document mandates device profiles
/// to handle long-tail DLNA compatibility gracefully.
class DeviceProfile {
  const DeviceProfile({
    required this.id,
    this.manufacturer,
    this.modelRegex,
    this.quirks = const DeviceQuirks(),
  });

  /// Unique profile identifier (e.g. `xiaomi-tv`, `sony-bravia`, `generic`).
  final String id;

  /// Optional manufacturer matching string (case-insensitive substring).
  final String? manufacturer;

  /// Optional model regular expression pattern.
  final String? modelRegex;

  /// Device-specific protocol quirks and capabilities.
  final DeviceQuirks quirks;

  /// Evaluates whether this profile matches the given renderer metadata.
  bool matches({
    String? deviceManufacturer,
    String? deviceModel,
  }) {
    if (manufacturer != null && deviceManufacturer != null) {
      if (!deviceManufacturer
          .toLowerCase()
          .contains(manufacturer!.toLowerCase())) {
        return false;
      }
    }
    if (modelRegex != null && deviceModel != null) {
      final reg = RegExp(modelRegex!, caseSensitive: false);
      if (!reg.hasMatch(deviceModel)) {
        return false;
      }
    }
    return true;
  }
}

/// Standard preset device profiles for common TV and renderer brands (Appendix 12.2 & CAST-04).
class StandardDeviceProfiles {
  const StandardDeviceProfiles._();

  /// Default fallback profile for standard UPnP AV MediaRenderers.
  static const DeviceProfile generic = DeviceProfile(
    id: 'generic-renderer',
    quirks: DeviceQuirks(
      supportsRange: true,
      supportsMkv: true,
      supportsHevc: true,
      requiresContentFeatures: false,
    ),
  );

  /// Xiaomi / Redmi smart TV profile (requires contentFeatures, handles MKV/HEVC).
  static const DeviceProfile xiaomiTv = DeviceProfile(
    id: 'xiaomi-tv',
    manufacturer: 'Xiaomi',
    modelRegex: r'^(Mi|Redmi|MITV).*',
    quirks: DeviceQuirks(
      supportsRange: true,
      supportsMkv: true,
      supportsHevc: true,
      requiresContentFeatures: true,
    ),
  );

  /// Sony Bravia Android TV profile (strict subtitle/MIME requirements).
  static const DeviceProfile sonyBravia = DeviceProfile(
    id: 'sony-bravia',
    manufacturer: 'Sony',
    modelRegex: r'^(BRAVIA|KD-|XR-).*',
    quirks: DeviceQuirks(
      supportsRange: true,
      supportsMkv: false, // Needs MP4/TS container remuxing
      supportsHevc: true,
      requiresContentFeatures: true,
      ignoreSidecarSubtitle: true,
    ),
  );

  /// Samsung Tizen TV profile (requires contentFeatures and strict MIME).
  static const DeviceProfile samsungTizen = DeviceProfile(
    id: 'samsung-tizen',
    manufacturer: 'Samsung',
    modelRegex: r'^(Samsung|Tizen|[UQE][A-Z]\d+).*',
    quirks: DeviceQuirks(
      supportsRange: true,
      supportsMkv: false, // Strict container support
      supportsHevc: true,
      requiresContentFeatures: true,
    ),
  );

  /// Huawei Vision TV profile.
  static const DeviceProfile huaweiVision = DeviceProfile(
    id: 'huawei-vision',
    manufacturer: 'Huawei',
    modelRegex: r'^(HUAWEI|Vision|HD\d+).*',
    quirks: DeviceQuirks(
      supportsRange: true,
      supportsMkv: true,
      supportsHevc: true,
      requiresContentFeatures: false,
    ),
  );

  /// Standard default registry containing all vendor presets.
  static const List<DeviceProfile> presets = <DeviceProfile>[
    xiaomiTv,
    sonyBravia,
    samsungTizen,
    huaweiVision,
    generic,
  ];

  /// Finds best matching profile for a discovered device.
  static DeviceProfile resolveProfile({
    String? manufacturer,
    String? model,
  }) {
    for (final profile in presets) {
      if (profile.matches(
        deviceManufacturer: manufacturer,
        deviceModel: model,
      )) {
        return profile;
      }
    }
    return generic;
  }
}
