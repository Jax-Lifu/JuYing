import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import 'package:juying/core/danmaku/danmaku_models.dart';

/// Parses raw Bilibili XML and DPlayer JSON danmaku streams into normalized [DanmakuItem] lists.
///
/// **What**: Decodes comment timelines, hex color integers, display modes, and timestamps.
///
/// **Why**: Media sources aggregate comments from diverse APIs (Bilibili, DPlayer, Kazumi).
/// Providing a unified parser pipeline ensures timeline synchronization irrespective of source format.
class DanmakuParser {
  /// Parses Bilibili XML comment format (e.g. `<d p="12.345,1,25,16777215,1620000000,0,user,0">文本</d>`).
  static List<DanmakuItem> parseBilibiliXml(String xmlContent) {
    final items = <DanmakuItem>[];
    try {
      final document = XmlDocument.parse(xmlContent);
      final nodes = document.findAllElements('d');

      for (final node in nodes) {
        final p = node.getAttribute('p');
        if (p == null) continue;

        final parts = p.split(',');
        if (parts.isEmpty) continue;

        final timeSec = double.tryParse(parts[0]) ?? 0.0;
        final timestampMs = (timeSec * 1000).round();

        // Mode: 1,2,3 = rolling; 4 = bottom; 5 = top
        final mode = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
        DanmakuType type = DanmakuType.rolling;
        if (mode == 4) {
          type = DanmakuType.bottomFixed;
        } else if (mode == 5) {
          type = DanmakuType.topFixed;
        }

        final fontSize =
            parts.length > 2 ? (double.tryParse(parts[2]) ?? 16.0) : 16.0;

        final colorInt =
            parts.length > 3 ? int.tryParse(parts[3]) ?? 0xFFFFFF : 0xFFFFFF;
        final color = Color(0xFF000000 | colorInt);

        final text = node.innerText.trim();
        if (text.isNotEmpty) {
          items.add(
            DanmakuItem(
              timestampMs: timestampMs,
              text: text,
              type: type,
              fontSize: fontSize.clamp(12.0, 32.0),
              color: color,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error parsing Bilibili XML danmaku: $e');
    }

    items.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return items;
  }

  /// Parses DPlayer JSON comment format (e.g. `[[12.345, 0, 16777215, "author", "文本"]]` or `{"danmaku": [...]}`).
  static List<DanmakuItem> parseDplayerJson(String jsonContent) {
    final items = <DanmakuItem>[];
    try {
      final decoded = json.decode(jsonContent);
      final list = decoded is List
          ? decoded
          : (decoded is Map
              ? (decoded['danmaku'] as List? ?? <dynamic>[])
              : <dynamic>[]);

      for (final raw in list) {
        if (raw is! List || raw.isEmpty) continue;

        final timeSec = (raw[0] is num) ? (raw[0] as num).toDouble() : 0.0;
        final timestampMs = (timeSec * 1000).round();

        final typeCode = raw.length > 1 ? (raw[1] as num?)?.toInt() ?? 0 : 0;
        DanmakuType type = DanmakuType.rolling;
        if (typeCode == 1) {
          type = DanmakuType.topFixed;
        } else if (typeCode == 2) {
          type = DanmakuType.bottomFixed;
        }

        final colorInt =
            raw.length > 2 ? (raw[2] as num?)?.toInt() ?? 0xFFFFFF : 0xFFFFFF;
        final color = Color(0xFF000000 | colorInt);

        final text = raw.length > 4 ? raw[4]?.toString().trim() ?? '' : '';

        if (text.isNotEmpty) {
          items.add(
            DanmakuItem(
              timestampMs: timestampMs,
              text: text,
              type: type,
              color: color,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error parsing DPlayer JSON danmaku: $e');
    }

    items.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return items;
  }
}
