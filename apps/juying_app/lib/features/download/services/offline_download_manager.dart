import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Lifecycle state of an offline download task.
enum DownloadTaskStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
}

/// Represents an offline video download task.
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.title,
    required this.episodeName,
    required this.m3u8Url,
    required this.targetDirectory,
    Map<String, String>? headers,
    this.status = DownloadTaskStatus.queued,
    this.progress = 0.0,
    this.totalSegments = 0,
    this.downloadedSegments = 0,
    this.outputFilePath,
    this.failureReason,
  }) : headers = headers == null ? null : Map.unmodifiable(headers);

  final String id;
  final String title;
  final String episodeName;
  final String m3u8Url;
  final String targetDirectory;

  /// Playback request headers are shared by every HLS request for this task.
  final Map<String, String>? headers;
  DownloadTaskStatus status;
  double progress;
  int totalSegments;
  int downloadedSegments;
  String? outputFilePath;

  /// 可选失败分类；未支持的 HLS 布局使用 `unsupported_hls_layout`。
  String? failureReason;
}

/// Multi-threaded M3U8 video segment downloader and offline caching manager.
///
/// **What**: Parses master playlists, downloads `.ts` segments concurrently,
/// handles AES-128 key fetching, and concatenates pieces into an offline-playable file.
///
/// **Why**: Mobile and laptop users require offline viewing during travel.
/// Concurrently downloading 4-8 segments maximizes network bandwidth utilization.
class OfflineDownloadManager {
  OfflineDownloadManager({
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
              ),
            );

  static final OfflineDownloadManager instance = OfflineDownloadManager();

  final Dio _dio;
  final List<DownloadTask> _tasks = <DownloadTask>[];
  final Map<String, CancelToken> _taskCancelTokens = <String, CancelToken>{};
  final Map<String, Future<void>> _taskRuns = <String, Future<void>>{};
  final StreamController<List<DownloadTask>> _tasksController =
      StreamController<List<DownloadTask>>.broadcast();

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;

  void _notifyUpdate() {
    if (!_tasksController.isClosed) {
      _tasksController.add(List.unmodifiable(_tasks));
    }
  }

  /// Submits a new download task.
  DownloadTask enqueueTask({
    required String id,
    required String title,
    required String episodeName,
    required String m3u8Url,
    required String targetDirectory,
    Map<String, String>? headers,
  }) {
    // Prevent duplicate download of same episode
    final existing = _tasks.where((t) => t.id == id).firstOrNull;
    if (existing != null) {
      if (existing.status == DownloadTaskStatus.paused ||
          existing.status == DownloadTaskStatus.failed) {
        _launchTask(existing);
      }
      return existing;
    }

    final task = DownloadTask(
      id: id,
      title: title,
      episodeName: episodeName,
      m3u8Url: m3u8Url,
      targetDirectory: targetDirectory,
      headers: headers,
    );
    _tasks.add(task);
    _notifyUpdate();
    _launchTask(task);
    return task;
  }

  void _launchTask(DownloadTask task) {
    final previous = _taskRuns[task.id];
    final cancelToken = CancelToken();
    _taskCancelTokens[task.id] = cancelToken;
    task.status = DownloadTaskStatus.downloading;
    task.failureReason = null;
    _notifyUpdate();
    // 恢复必须等旧 worker 关闭文件；新 token 立即生效，排队期间仍可再次暂停。
    final run = previous == null
        ? _startTask(task, cancelToken)
        : previous.then((_) => _startTask(task, cancelToken));
    _taskRuns[task.id] = run;
    unawaited(
      run.whenComplete(() {
        if (identical(_taskRuns[task.id], run)) _taskRuns.remove(task.id);
        if (identical(_taskCancelTokens[task.id], cancelToken)) {
          _taskCancelTokens.remove(task.id);
        }
      }),
    );
  }

  /// 等待指定任务达到稳定状态，供生命周期协调和端到端测试使用。
  Future<void> waitForTask(String id) => _taskRuns[id] ?? Future<void>.value();

  Future<void> _startTask(DownloadTask task, CancelToken cancelToken) async {
    if (cancelToken.isCancelled) return;
    // The same key URL may return different bytes for another task's identity.
    final keyCache = <String, List<int>>{};
    task.status = DownloadTaskStatus.downloading;
    _notifyUpdate();
    try {
      // 主清单只描述码率变体，必须先选择最高带宽的媒体清单再解析分片。
      final mediaPlaylist = await _resolveMediaPlaylist(
        task.m3u8Url,
        cancelToken,
        headers: task.headers,
      );
      // 直接拼接 TS 无法保留初始化段或字节区间语义，必须在下载前拒绝，
      // 避免发布缺少初始化信息或重复整文件的“已完成”缓存。
      if (mediaPlaylist.content.split(RegExp(r'\r?\n')).any((line) =>
          line.trim().startsWith('#EXT-X-MAP:') ||
          line.trim().startsWith('#EXT-X-BYTERANGE:'))) {
        task.failureReason = 'unsupported_hls_layout';
        task.outputFilePath = null;
        throw UnsupportedError('暂不支持含初始化段或字节区间的 HLS 离线缓存');
      }
      final segments = _parseMediaPlaylist(
        mediaPlaylist.content,
        mediaPlaylist.url,
      );

      task.totalSegments = segments.length;
      task.downloadedSegments = 0;
      task.progress = 0;
      if (task.totalSegments == 0) {
        task.status = DownloadTaskStatus.failed;
        _notifyUpdate();
        return;
      }

      // 3. Prepare local output directory
      final dir = Directory(p.join(task.targetDirectory, task.id));
      if (!await dir.exists()) await dir.create(recursive: true);

      // 4. 固定 worker 池避免一次性创建数千 Future；失败分片最多重试 3 次。
      var nextSegmentIndex = 0;
      Future<void> worker() async {
        while (!cancelToken.isCancelled) {
          final idx = nextSegmentIndex++;
          if (idx >= segments.length) return;
          final segFile = File(p.join(dir.path, 'seg_$idx.ts'));
          if (await segFile.exists() && await segFile.length() > 0) {
            task.downloadedSegments++;
            task.progress = task.downloadedSegments / task.totalSegments;
            _notifyUpdate();
            continue;
          }
          await _downloadSegmentWithRetry(
            segments[idx],
            segFile,
            cancelToken,
            headers: task.headers,
            keyCache: keyCache,
          );
          task.downloadedSegments++;
          task.progress = task.downloadedSegments / task.totalSegments;
          _notifyUpdate();
        }
      }

      await Future.wait(
        List<Future<void>>.generate(
          min(8, segments.length),
          (_) => worker(),
        ),
      );

      if (cancelToken.isCancelled) {
        if (identical(_taskCancelTokens[task.id], cancelToken)) {
          task.status = DownloadTaskStatus.paused;
        }
        _notifyUpdate();
        return;
      }

      // 5. 完整性门：所有分片都存在且非空，才允许进入拼接阶段。
      final segmentFiles = List<File>.generate(
        task.totalSegments,
        (index) => File(p.join(dir.path, 'seg_$index.ts')),
      );
      if (!await _allSegmentsComplete(segmentFiles)) {
        throw const FileSystemException('分片不完整或包含空文件');
      }

      // 当前版本尚未接入 FFmpeg remux，因此明确保留 MPEG-TS 扩展名。
      // 临时文件原子改名可以避免播放器看到半成品。
      final temporaryFile = File(p.join(dir.path, '${task.id}.ts.tmp'));
      final outputFile = File(p.join(dir.path, '${task.id}.ts'));
      final sink = temporaryFile.openWrite();

      for (final segmentFile in segmentFiles) {
        await sink.addStream(segmentFile.openRead());
      }
      await sink.close();
      if (cancelToken.isCancelled) return;
      if (await outputFile.exists()) await outputFile.delete();
      await temporaryFile.rename(outputFile.path);
      for (final segmentFile in segmentFiles) {
        await segmentFile.delete();
      }

      task.outputFilePath = outputFile.path;
      task.status = DownloadTaskStatus.completed;
      task.progress = 1.0;
      _notifyUpdate();
      debugPrint('[Download] Task ${task.id} finished: ${outputFile.path}');
    } catch (e) {
      if (cancelToken.isCancelled) {
        if (identical(_taskCancelTokens[task.id], cancelToken)) {
          task.status = DownloadTaskStatus.paused;
        }
      } else {
        task.status = DownloadTaskStatus.failed;
        debugPrint('[Download] Task ${task.id} encountered fatal error: $e');
      }
      _notifyUpdate();
    }
  }

  Future<void> _downloadSegmentWithRetry(
    _HlsSegment segment,
    File target,
    CancelToken cancelToken, {
    Map<String, String>? headers,
    required Map<String, List<int>> keyCache,
  }) async {
    Object? lastError;
    // 恢复只识别正式分片名；中断或进程退出留下的临时文件不能当作完整缓存。
    final temporaryFile = File('${target.path}.tmp');
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (cancelToken.isCancelled) throw StateError('下载任务已取消');
      try {
        if (await temporaryFile.exists()) await temporaryFile.delete();
        if (segment.keyUrl == null) {
          await _dio.download(
            segment.url,
            temporaryFile.path,
            cancelToken: cancelToken,
            options: Options(headers: headers),
          );
        } else {
          final response = await _dio.get<List<int>>(
            segment.url,
            cancelToken: cancelToken,
            options:
                Options(responseType: ResponseType.bytes, headers: headers),
          );
          final encryptedBytes = response.data ?? <int>[];
          final key = await _readEncryptionKey(
            segment.keyUrl!,
            cancelToken,
            headers: headers,
            keyCache: keyCache,
          );
          final decrypted = _decryptAes128(
            encryptedBytes,
            key,
            segment.iv ?? _sequenceIv(segment.sequence),
          );
          await temporaryFile.writeAsBytes(decrypted, flush: true);
        }
        if (await temporaryFile.length() <= 0) {
          throw const FileSystemException('下载结果为空');
        }
        if (await target.exists()) await target.delete();
        await temporaryFile.rename(target.path);
        return;
      } catch (error) {
        lastError = error;
        if (await temporaryFile.exists()) await temporaryFile.delete();
        if (cancelToken.isCancelled) rethrow;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 100 * attempt));
        }
      }
    }
    throw FileSystemException('分片下载重试耗尽: $lastError', target.path);
  }

  Future<_MediaPlaylist> _resolveMediaPlaylist(
    String playlistUrl,
    CancelToken cancelToken, {
    Map<String, String>? headers,
  }) async {
    final response = await _dio.get<String>(
      playlistUrl,
      cancelToken: cancelToken,
      options: Options(headers: headers),
    );
    final content = response.data ?? '';
    final lines = content.split(RegExp(r'\r?\n'));
    final variants = <_HlsVariant>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final bandwidth = int.tryParse(
            RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '',
          ) ??
          0;
      for (var next = index + 1; next < lines.length; next++) {
        final uri = lines[next].trim();
        if (uri.isEmpty) continue;
        if (!uri.startsWith('#')) {
          variants.add(
            _HlsVariant(
              url: Uri.parse(playlistUrl).resolve(uri).toString(),
              bandwidth: bandwidth,
            ),
          );
        }
        break;
      }
    }
    if (variants.isEmpty) {
      return _MediaPlaylist(url: playlistUrl, content: content);
    }
    variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    final selected = variants.first.url;
    final selectedResponse = await _dio.get<String>(
      selected,
      cancelToken: cancelToken,
      options: Options(headers: headers),
    );
    return _MediaPlaylist(url: selected, content: selectedResponse.data ?? '');
  }

  List<_HlsSegment> _parseMediaPlaylist(String content, String playlistUrl) {
    final segments = <_HlsSegment>[];
    String? keyUrl;
    Uint8List? iv;
    var sequence = 0;
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.tryParse(line.split(':').last) ?? 0;
      } else if (line.startsWith('#EXT-X-KEY:')) {
        final method = RegExp(r'METHOD=([^,]+)').firstMatch(line)?.group(1);
        if (method == 'NONE') {
          keyUrl = null;
          iv = null;
          continue;
        }
        if (method != 'AES-128') {
          throw UnsupportedError('暂不支持 HLS 加密方式: $method');
        }
        final keyPath = RegExp(r'URI="([^"]+)"').firstMatch(line)?.group(1);
        if (keyPath == null) throw const FormatException('AES-128 缺少密钥 URI');
        keyUrl = Uri.parse(playlistUrl).resolve(keyPath).toString();
        final ivHex = RegExp(r'IV=0x([0-9a-fA-F]+)').firstMatch(line)?.group(1);
        iv = ivHex == null ? null : _decodeIv(ivHex);
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        segments.add(
          _HlsSegment(
            url: Uri.parse(playlistUrl).resolve(line).toString(),
            sequence: sequence,
            keyUrl: keyUrl,
            iv: iv,
          ),
        );
        sequence++;
      }
    }
    return segments;
  }

  Future<List<int>> _readEncryptionKey(
    String url,
    CancelToken cancelToken, {
    Map<String, String>? headers,
    required Map<String, List<int>> keyCache,
  }) async {
    final cached = keyCache[url];
    if (cached != null) return cached;
    final response = await _dio.get<List<int>>(
      url,
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.bytes, headers: headers),
    );
    final key = response.data ?? <int>[];
    if (key.length != 16) throw const FormatException('AES-128 密钥必须为 16 字节');
    keyCache[url] = key;
    return key;
  }

  List<int> _decryptAes128(
    List<int> bytes,
    List<int> key,
    Uint8List iv,
  ) {
    final cipher = encrypt.Encrypter(
      encrypt.AES(
        encrypt.Key(Uint8List.fromList(key)),
        mode: encrypt.AESMode.cbc,
      ),
    );
    return cipher.decryptBytes(
      encrypt.Encrypted(Uint8List.fromList(bytes)),
      iv: encrypt.IV(iv),
    );
  }

  Uint8List _decodeIv(String hex) {
    final normalized = hex.padLeft(32, '0');
    if (normalized.length != 32) throw const FormatException('AES IV 长度无效');
    return Uint8List.fromList(
      List<int>.generate(
        16,
        (index) => int.parse(normalized.substring(index * 2, index * 2 + 2),
            radix: 16),
      ),
    );
  }

  Uint8List _sequenceIv(int sequence) {
    final iv = Uint8List(16);
    var value = sequence;
    for (var index = 15; index >= 0 && value > 0; index--) {
      iv[index] = value & 0xff;
      value >>= 8;
    }
    return iv;
  }

  Future<bool> _allSegmentsComplete(List<File> files) async {
    for (final file in files) {
      if (!await file.exists() || await file.length() == 0) return false;
    }
    return true;
  }

  /// Pauses an active download task.
  void pauseTask(String id) {
    final token = _taskCancelTokens[id];
    token?.cancel('Task paused by user');
    final task = _tasks.where((t) => t.id == id).firstOrNull;
    if (task != null) {
      task.status = DownloadTaskStatus.paused;
      _notifyUpdate();
    }
  }

  /// Resumes a paused download task.
  void resumeTask(String id) {
    final task = _tasks.where((t) => t.id == id).firstOrNull;
    if (task != null && task.status == DownloadTaskStatus.paused) {
      _launchTask(task);
    }
  }

  /// Cancels and deletes a download task.
  void deleteTask(String id) {
    pauseTask(id);
    _tasks.removeWhere((t) => t.id == id);
    _taskCancelTokens.remove(id);
    _notifyUpdate();
  }

  /// 应用进入后台时暂停所有活动任务，防止移动平台直接杀进程导致文件损坏。
  void pauseAll() {
    for (final task in List<DownloadTask>.of(_tasks)) {
      if (task.status == DownloadTaskStatus.downloading) pauseTask(task.id);
    }
  }

  void resumeAll() {
    for (final task in List<DownloadTask>.of(_tasks)) {
      if (task.status == DownloadTaskStatus.paused) resumeTask(task.id);
    }
  }

  Future<void> dispose() async {
    pauseAll();
    await Future.wait(_taskRuns.values.toList(growable: false));
    await _tasksController.close();
  }
}

class _MediaPlaylist {
  const _MediaPlaylist({required this.url, required this.content});

  final String url;
  final String content;
}

class _HlsVariant {
  const _HlsVariant({required this.url, required this.bandwidth});

  final String url;
  final int bandwidth;
}

class _HlsSegment {
  const _HlsSegment({
    required this.url,
    required this.sequence,
    required this.keyUrl,
    required this.iv,
  });

  final String url;
  final int sequence;
  final String? keyUrl;
  final Uint8List? iv;
}
