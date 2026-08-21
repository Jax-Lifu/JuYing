import '../../domain/models/live_program.dart';

abstract final class XmltvProgramParser {
  static List<LiveProgram> parse(
    String xml, {
    required String sourceId,
    required String sourceItemId,
    required String channelId,
  }) {
    final programs = <LiveProgram>[];
    final pattern = RegExp(
      r'<programme\b([^>]*)>([\s\S]*?)</programme>',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(xml)) {
      final attributes = match.group(1) ?? '';
      if (_attribute(attributes, 'channel') != channelId) continue;
      final start = _timestamp(_attribute(attributes, 'start'));
      final stop = _timestamp(_attribute(attributes, 'stop'));
      final body = match.group(2) ?? '';
      final title = _element(body, 'title');
      if (start == null ||
          stop == null ||
          !stop.isAfter(start) ||
          title == null) {
        continue;
      }
      programs.add(LiveProgram(
        sourceId: sourceId,
        sourceItemId: sourceItemId,
        title: title,
        startsAt: start,
        endsAt: stop,
        description: _element(body, 'desc'),
      ));
    }
    programs.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return programs;
  }

  static String? _attribute(String attributes, String name) => RegExp(
        '$name\\s*=\\s*["\\\']([^"\\\']*)["\\\']',
        caseSensitive: false,
      ).firstMatch(attributes)?.group(1);

  static String? _element(String body, String name) {
    final match =
        RegExp('<$name\\b[^>]*>([\\s\\S]*?)</$name>', caseSensitive: false)
            .firstMatch(body);
    final value = match?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    if (value == null || value.isEmpty) return null;
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  static DateTime? _timestamp(String? value) {
    if (value == null || value.length < 14) return null;
    final digits = value.substring(0, 14);
    if (!RegExp(r'^\d{14}$').hasMatch(digits)) return null;
    final offset = RegExp(r'([+-]\d{4})').firstMatch(value)?.group(1);
    final iso =
        '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6, 8)}T${digits.substring(8, 10)}:${digits.substring(10, 12)}:${digits.substring(12, 14)}${offset == null ? 'Z' : '${offset.substring(0, 3)}:${offset.substring(3)}'}';
    return DateTime.tryParse(iso)?.toLocal();
  }
}
