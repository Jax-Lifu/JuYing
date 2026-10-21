import 'package:flutter/material.dart';

/// Defines the display type of a danmaku item.
enum DanmakuType {
  /// Scrolls horizontally from right to left across the screen.
  rolling,

  /// Fixed at the top center of the screen.
  topFixed,

  /// Fixed at the bottom center of the screen.
  bottomFixed,
}

/// Represents an individual danmaku comment entry on the playback timeline.
///
/// **What**: Holds timestamp, text payload, display mode, text color, and layout properties.
///
/// **Why**: Bilibili XML and DPlayer JSON store comment data in compact string tuples.
/// Normalizing into a structured [DanmakuItem] allows the 2D Canvas renderer to manage
/// lane collisions, alpha fading, and keyword filtering efficiently.
class DanmakuItem {
  const DanmakuItem({
    required this.timestampMs,
    required this.text,
    this.type = DanmakuType.rolling,
    this.color = Colors.white,
    this.fontSize = 16.0,
    this.senderId,
  });

  /// Playback timeline position in milliseconds when this danmaku should appear.
  final int timestampMs;

  /// Comment text content.
  final String text;

  /// Display mode (rolling, top fixed, bottom fixed).
  final DanmakuType type;

  /// Custom text render color.
  final Color color;

  /// Render font size in pixels.
  final double fontSize;

  /// Optional hashed sender identifier for user blocking.
  final String? senderId;
}
