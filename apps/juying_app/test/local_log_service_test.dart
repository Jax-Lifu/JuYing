import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/logging/local_log_service.dart';

void main() {
  test('a failed log write cannot escape or block later exception records',
      () async {
    final support = await Directory.systemTemp.createTemp('juying-logs-retry-');
    addTearDown(() => support.delete(recursive: true));
    var attempts = 0;
    final service = LocalLogService(supportDirectory: () async {
      if (++attempts == 1) {
        throw const FileSystemException('temporarily denied');
      }
      return support;
    });

    final failed = service.record(StateError('first'), StackTrace.current);
    final recovered = service.record(StateError('second'), StackTrace.current);
    await expectLater(
        Future.wait(<Future<void>>[failed, recovered]), completes);

    final files = await Directory('${support.path}/logs').list().toList();
    expect(await (files.single as File).readAsString(), contains('second'));
    expect(attempts, 2);
  });

  test('local logger writes daily logs and removes files older than seven days',
      () async {
    final support = await Directory.systemTemp.createTemp('juying-logs-');
    addTearDown(() => support.delete(recursive: true));
    final logs = Directory('${support.path}${Platform.pathSeparator}logs');
    await logs.create(recursive: true);
    final expired = File('${logs.path}${Platform.pathSeparator}juying-old.log');
    await expired.writeAsString('old');
    await expired.setLastModified(
      DateTime.now().subtract(const Duration(days: 8)),
    );

    final service = LocalLogService(supportDirectory: () async => support);
    await service.record(StateError('boom'), StackTrace.current);

    expect(await expired.exists(), isFalse);
    final currentFiles = await logs
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    expect(currentFiles, hasLength(1));
    expect(await currentFiles.single.readAsString(), contains('boom'));
  });
}
