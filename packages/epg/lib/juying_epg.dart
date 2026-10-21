/// XMLTV EPG Parsing and Channel Matching Abstraction for JuYing.
///
/// **What**: Parses XMLTV electronic program guides, normalizes channel names
/// (e.g. CCTV-1 / 央视一套), and evaluates catchup timeshift templates (Section 5.6).
///
/// **Why**: Offloads large XML/GZ parsing to isolated workers and handles timezone offsets.
library;

/// Normalizes raw channel names to standard aliases.
class ChannelNameNormalizer {
  static String normalize(String rawName) {
    var name = rawName.trim().toUpperCase();
    name = name.replaceAll(RegExp(r'[\s\-_\(\)（）\[\]【】]+'), '');
    name = name.replaceAll('央视一套', 'CCTV1');
    name = name.replaceAll('央视二套', 'CCTV2');
    name = name.replaceAll('综合', '');
    name = name.replaceAll('高清', '');
    name = name.replaceAll('HD', '');
    name = name.replaceAll('4K', '');
    return name;
  }
}
