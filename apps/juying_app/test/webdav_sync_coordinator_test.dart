import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/core/history/playback_history_service.dart';
import 'package:juying/features/sync/services/webdav_credential_store.dart';
import 'package:juying/features/sync/services/webdav_sync_coordinator.dart';
import 'package:juying/features/sync/services/webdav_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PlaybackHistoryService.instance.clearHistory();
  });

  test('pulls, merges and persists newer remote playback history', () async {
    await PlaybackHistoryService.instance.saveHistory(
      const PlaybackHistoryItem(
        id: 'movie_1',
        title: '本地标题',
        posterUrl: '',
        episodeName: '第 1 集',
        episodeIndex: 1,
        positionMs: 1000,
        durationMs: 10000,
        timestampMs: 1000,
      ),
    );
    final service = _RecordingSyncService(
      remote: const SyncBundle(
        deviceId: 'tv',
        updatedAtMs: 2000,
        history: <Map<String, dynamic>>[
          <String, dynamic>{
            'entityId': 'movie_1',
            'id': 'movie_1',
            'title': '远端标题',
            'posterUrl': '',
            'episodeName': '第 1 集',
            'episodeIndex': 1,
            'positionMs': 8000,
            'durationMs': 10000,
            'timestampMs': 2000,
            'updatedAt': 2000,
            'progressTimestamp': 2000,
            'isDeleted': false,
          },
        ],
      ),
    );
    final coordinator = WebDavSyncCoordinator(
      credentialStore: _MemoryCredentialStore(),
      syncService: service,
      historyService: PlaybackHistoryService.instance,
    );

    expect(await coordinator.syncNow(), isTrue);

    final history = await PlaybackHistoryService.instance.getHistory();
    expect(history.single.positionMs, 8000);
    expect(service.uploaded, isNotNull);
    expect(service.uploaded!.history.single['positionMs'], 8000);
  });

  test('coalesces repeated playback pushes into one sync', () async {
    final service = _RecordingSyncService();
    final coordinator = WebDavSyncCoordinator(
      credentialStore: _MemoryCredentialStore(),
      syncService: service,
      historyService: PlaybackHistoryService.instance,
      pushDebounce: const Duration(milliseconds: 10),
    );
    addTearDown(coordinator.dispose);

    coordinator.schedulePush();
    coordinator.schedulePush();
    coordinator.schedulePush();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(service.downloadCount, 1);
    expect(service.uploadCount, 1);
  });

  for (final firstUploadSucceeds in <bool>[true, false]) {
    test('pushes new progress after an active upload ($firstUploadSucceeds)',
        () async {
      final uploadStarted = Completer<void>();
      final releaseUpload = Completer<void>();
      final followUpUploaded = Completer<void>();
      late _RecordingSyncService service;
      service = _RecordingSyncService(
        beforeUpload: () async {
          if (service.uploadCount == 1) {
            uploadStarted.complete();
            await releaseUpload.future;
            return firstUploadSucceeds;
          }
          followUpUploaded.complete();
          return false;
        },
      );
      final coordinator = WebDavSyncCoordinator(
        credentialStore: _MemoryCredentialStore(),
        syncService: service,
        pushDebounce: const Duration(milliseconds: 10),
      );
      addTearDown(() {
        coordinator.dispose();
        if (!releaseUpload.isCompleted) releaseUpload.complete();
      });

      final sync = coordinator.syncNow();
      await uploadStarted.future;
      await PlaybackHistoryService.instance.saveHistory(
        const PlaybackHistoryItem(
          id: 'during_upload',
          title: '上传期间新增',
          posterUrl: '',
          episodeName: '第 2 集',
          episodeIndex: 2,
          positionMs: 5000,
          durationMs: 10000,
          timestampMs: 2000,
        ),
      );
      coordinator.schedulePush();
      coordinator.schedulePush();
      coordinator.schedulePush();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(service.uploadCount, 1);
      expect(service.uploaded!.history, isEmpty);
      releaseUpload.complete();
      expect(await sync, firstUploadSucceeds);

      await followUpUploaded.future.timeout(const Duration(seconds: 1));
      expect(service.uploaded!.history.single['positionMs'], 5000);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      // A failed follow-up must not turn one local mutation into endless retries.
      expect(service.downloadCount, 2);
      expect(service.uploadCount, 2);
    });
  }

  test('disposing during an upload discards the pending playback push',
      () async {
    final uploadStarted = Completer<void>();
    final releaseUpload = Completer<void>();
    final service = _RecordingSyncService(
      beforeUpload: () async {
        uploadStarted.complete();
        await releaseUpload.future;
        return true;
      },
    );
    final coordinator = WebDavSyncCoordinator(
      credentialStore: _MemoryCredentialStore(),
      syncService: service,
      pushDebounce: const Duration(milliseconds: 10),
    );
    addTearDown(() {
      coordinator.dispose();
      if (!releaseUpload.isCompleted) releaseUpload.complete();
    });

    final sync = coordinator.syncNow();
    await uploadStarted.future;
    coordinator.schedulePush();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    coordinator.dispose();
    releaseUpload.complete();
    expect(await sync, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(service.uploadCount, 1);
  });

  test('a failed remote read never uploads an empty replacement', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final mutations = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'GET') {
        request.response.statusCode = HttpStatus.internalServerError;
      } else {
        mutations.add(request.method);
        request.response.statusCode =
            request.method == 'HEAD' ? HttpStatus.notFound : HttpStatus.created;
      }
      await request.drain<void>();
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final coordinator = WebDavSyncCoordinator(
      credentialStore: _MemoryCredentialStore(
        url: 'http://127.0.0.1:${server.port}',
      ),
    );
    addTearDown(coordinator.dispose);

    expect(await coordinator.syncNow(), isFalse);
    expect(mutations, isEmpty);
  });

  test('retains playback saved while the remote snapshot is downloading',
      () async {
    final downloadStarted = Completer<void>();
    final releaseDownload = Completer<void>();
    final service = _RecordingSyncService(
      remote: const SyncBundle(deviceId: 'tv', updatedAtMs: 1000),
      beforeDownload: () async {
        downloadStarted.complete();
        await releaseDownload.future;
      },
    );
    final coordinator = WebDavSyncCoordinator(
      credentialStore: _MemoryCredentialStore(),
      syncService: service,
    );
    addTearDown(coordinator.dispose);

    final sync = coordinator.syncNow();
    await downloadStarted.future;
    await PlaybackHistoryService.instance.saveHistory(
      const PlaybackHistoryItem(
        id: 'new_playback',
        title: '播放期间新增',
        posterUrl: '',
        episodeName: '第 2 集',
        episodeIndex: 2,
        positionMs: 3000,
        durationMs: 10000,
        timestampMs: 2000,
      ),
    );
    releaseDownload.complete();

    expect(await sync, isTrue);
    final history = await PlaybackHistoryService.instance.getHistory();
    expect(history.map((item) => item.id), contains('new_playback'));
    expect(service.uploaded!.history.single['id'], 'new_playback');
  });
}

class _MemoryCredentialStore implements WebDavCredentialStore {
  _MemoryCredentialStore({String url = 'https://dav.example.test'})
      : credentials = WebDavCredentials(
          url: url,
          username: 'user',
          password: 'password',
        );

  final WebDavCredentials credentials;

  @override
  Future<WebDavCredentials?> read(
          {SharedPreferences? legacyPreferences}) async =>
      credentials;

  @override
  Future<void> write(
    WebDavCredentials credentials, {
    SharedPreferences? legacyPreferences,
  }) async {}

  @override
  Future<void> clear({SharedPreferences? legacyPreferences}) async {}
}

class _RecordingSyncService extends WebDavSyncService {
  _RecordingSyncService({this.remote, this.beforeDownload, this.beforeUpload});

  final SyncBundle? remote;
  final Future<void> Function()? beforeDownload;
  final Future<bool> Function()? beforeUpload;
  SyncBundle? uploaded;
  int downloadCount = 0;
  int uploadCount = 0;

  @override
  Future<SyncBundle?> downloadSyncBundle({
    required String webDavUrl,
    required String username,
    required String password,
  }) async {
    downloadCount++;
    await beforeDownload?.call();
    return remote;
  }

  @override
  Future<bool> uploadSyncBundle({
    required String webDavUrl,
    required String username,
    required String password,
    required SyncBundle bundle,
  }) async {
    uploadCount++;
    uploaded = bundle;
    return await beforeUpload?.call() ?? true;
  }
}
