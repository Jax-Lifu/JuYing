import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 将未捕获异常串行写入按日切分的本地日志，并只保留最近七天。
class LocalLogService {
  LocalLogService({Future<Directory> Function()? supportDirectory})
      : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;
  Future<void> _pendingWrite = Future<void>.value();

  Future<void> record(Object error, StackTrace stackTrace) {
    // 日志本身位于全局异常处理链，写入失败不能再抛错或阻断后续记录。
    _pendingWrite = _pendingWrite
        .then((_) => _write(error, stackTrace))
        .catchError((Object _) {});
    return _pendingWrite;
  }

  Future<void> _write(Object error, StackTrace stackTrace) async {
    final root = await _supportDirectory();
    final logDirectory = Directory(p.join(root.path, 'logs'));
    await logDirectory.create(recursive: true);
    final now = DateTime.now();
    await _deleteExpiredLogs(logDirectory, now);
    final day = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final logFile = File(p.join(logDirectory.path, 'juying-$day.log'));
    await logFile.writeAsString(
      '[${now.toIso8601String()}] $error\n$stackTrace\n\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> _deleteExpiredLogs(Directory directory, DateTime now) async {
    final cutoff = now.subtract(const Duration(days: 7));
    await for (final entity in directory.list()) {
      if (entity is! File || !p.basename(entity.path).startsWith('juying-')) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) await entity.delete();
    }
  }
}
