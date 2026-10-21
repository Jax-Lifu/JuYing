import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juying/core/models/media_item.dart';
import 'package:juying/features/cloud_drive/services/cloud_drive_service.dart';
import 'package:juying/features/metadata/services/media_metadata_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unconfigured cloud provider never returns a synthetic stream URL', () {
    final service = CloudDriveService();
    expect(
      service.resolveDirectStreamUrl(
        type: CloudDriveType.aliyun,
        fileId: 'file-1',
      ),
      throwsA(isA<CloudDriveNotConfiguredError>()),
    );
  });

  test(
      'configured cloud provider refreshes expiring token and resolves real URL',
      () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final provider = _FakeCloudProvider();
    final service = CloudDriveService(
      providers: <CloudDriveType, CloudDriveProvider>{
        CloudDriveType.aliyun: provider,
      },
    );
    await service.saveToken(
      CloudDriveType.aliyun,
      CloudDriveToken(
        accessToken: 'old',
        refreshToken: 'refresh',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      ),
    );

    final url = await service.resolveDirectStreamUrl(
      type: CloudDriveType.aliyun,
      fileId: 'file-1',
    );
    expect(provider.refreshCount, 1);
    expect(url, 'https://drive.test/file-1?token=real-access');
  });

  test('metadata service returns unavailable instead of fabricated metadata',
      () async {
    final service = MediaMetadataService();
    final generation = service.nextGeneration();
    final result = await service.prefetchMetadata(
      rawTitle: '三体 [4K]',
      generation: generation,
    );
    expect(result, isA<MetadataUnavailableResult>());
    expect(result.fallbackTitle, '三体');
  });

  test('metadata generation guard discards stale provider responses', () async {
    final service = MediaMetadataService(provider: _FakeMetadataProvider());
    final generation = service.nextGeneration();
    service.nextGeneration();
    final result = await service.prefetchMetadata(
      rawTitle: '流浪地球 1080P',
      generation: generation,
    );
    expect(result, isA<MetadataStaleResult>());
  });
}

class _FakeCloudProvider implements CloudDriveProvider {
  int refreshCount = 0;

  @override
  Future<CloudDriveToken> refreshToken(CloudDriveToken currentToken) async {
    refreshCount++;
    return CloudDriveToken(
      accessToken: 'real-access',
      refreshToken: currentToken.refreshToken,
      expiresAtMs:
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
  }

  @override
  Future<String> resolveDirectStreamUrl({
    required String fileId,
    required CloudDriveToken token,
  }) async {
    return 'https://drive.test/$fileId?token=${token.accessToken}';
  }
}

class _FakeMetadataProvider implements MetadataProvider {
  @override
  Future<MediaItem?> searchByTitle(String title) async {
    return MediaItem(id: 'tmdb-1', title: title);
  }
}
