import 'package:flutter/foundation.dart';

/// Represents an individual file or directory entry inside a Samba, NFS, or WebDAV share.
@immutable
class NasShareItem {
  const NasShareItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.modifiedTime,
  });

  /// File or folder display name (e.g. `Inception.2010.1080p.mkv`).
  final String name;

  /// Relative or absolute path inside the NAS share (e.g. `/Movies/Inception.2010.1080p.mkv`).
  final String path;

  /// Whether this entry is a directory/folder.
  final bool isDirectory;

  /// File size in bytes (0 for directories).
  final int sizeBytes;

  /// Last modified timestamp.
  final DateTime? modifiedTime;

  /// Returns true if this file is a playable video format.
  bool get isMediaFile {
    if (isDirectory) return false;
    final ext = _fileExtension.toLowerCase();
    return const <String>[
      '.mp4',
      '.mkv',
      '.m3u8',
      '.ts',
      '.mov',
      '.avi',
      '.flv',
      '.iso',
      '.wmv',
      '.m4v',
      '.webm',
    ].contains(ext);
  }

  /// Returns true if this file is an external subtitle.
  bool get isSubtitles {
    if (isDirectory) return false;
    final ext = _fileExtension.toLowerCase();
    return const <String>['.srt', '.ass', '.vtt', '.ssa', '.sub'].contains(ext);
  }

  /// Returns true if this file is a Kodi/Emby standard `.nfo` metadata file.
  bool get isNfo {
    if (isDirectory) return false;
    return _fileExtension.toLowerCase() == '.nfo';
  }

  /// Returns true if this file is a poster/backdrop image.
  bool get isImage {
    if (isDirectory) return false;
    final ext = _fileExtension.toLowerCase();
    return const <String>['.jpg', '.jpeg', '.png', '.webp'].contains(ext);
  }

  String get _fileExtension {
    final dotIdx = name.lastIndexOf('.');
    if (dotIdx == -1) return '';
    return name.substring(dotIdx);
  }

  /// Human-readable file type name.
  String get fileTypeName {
    if (isDirectory) return '文件夹';
    if (isMediaFile) {
      final ext = _fileExtension.replaceAll('.', '').toUpperCase();
      return '$ext 视频';
    }
    if (isSubtitles) return '外挂字幕';
    if (isNfo) return 'NFO 元数据';
    if (isImage) return '图像海报';
    return _fileExtension.isNotEmpty
        ? '${_fileExtension.toUpperCase()} 文件'
        : '文件';
  }

  /// Detected resolution tag (4K UHD, 1080P, 720P, etc.).
  String get resolutionTag {
    if (!isMediaFile) return '-';
    final lower = name.toLowerCase();
    if (lower.contains('2160p') ||
        lower.contains('4k') ||
        lower.contains('uhd')) {
      return '4K UHD';
    }
    if (lower.contains('1080p') || lower.contains('fhd')) {
      return '1080P';
    }
    if (lower.contains('720p') || lower.contains('hd')) {
      return '720P';
    }
    return 'HD 原画';
  }

  /// Formatted last modified date & time string.
  String get formattedModifiedTime {
    if (modifiedTime == null) return '-';
    final d = modifiedTime!;
    final year = d.year.toString().padLeft(4, '0');
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  /// Human-readable file size formatting (e.g. `2.45 GB`).
  String get formattedSize {
    if (isDirectory) return '-';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
