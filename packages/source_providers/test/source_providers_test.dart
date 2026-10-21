import 'package:test/test.dart';
import 'package:juying_source_providers/juying_source_providers.dart';

void main() {
  group('SourceProviders Validation & Capabilities Tests (Section 5.2)', () {
    test(
        'CmsSourceProvider validates HTTP endpoint and exposes VOD capabilities',
        () async {
      final provider = CmsSourceProvider();
      expect(provider.type, equals('cms'));
      expect(provider.capabilities, contains(SourceCapability.vod));
      expect(provider.capabilities, contains(SourceCapability.search));

      final validRes = await provider.validate(
        const SourceConfig(
          id: 'cms-1',
          type: 'cms',
          name: 'CMS Test',
          endpoint: 'https://example.com/api.php/provide/vod',
        ),
      );
      expect(validRes.isValid, isTrue);

      final invalidRes = await provider.validate(
        const SourceConfig(
          id: 'cms-2',
          type: 'cms',
          name: 'CMS Bad',
          endpoint: 'not-a-valid-url',
        ),
      );
      expect(invalidRes.isValid, isFalse);
    });

    test('M3uSourceProvider validates live endpoints', () async {
      final provider = M3uSourceProvider();
      expect(provider.type, equals('m3u'));
      expect(provider.capabilities, contains(SourceCapability.live));

      final res = await provider.validate(
        const SourceConfig(
          id: 'm3u-1',
          type: 'm3u',
          name: 'Live Test',
          endpoint: 'https://example.com/channels.m3u',
        ),
      );
      expect(res.isValid, isTrue);
    });

    test('StorageProviders (SMB, WebDAV, NFS) validate correctly', () async {
      final smb = SmbSourceProvider();
      expect(smb.type, equals('smb'));
      final smbRes = await smb.validate(
        const SourceConfig(
          id: 'smb-1',
          type: 'smb',
          name: 'NAS Video',
          endpoint: 'smb://192.168.1.10/video',
        ),
      );
      expect(smbRes.isValid, isTrue);

      final webdav = WebDavSourceProvider();
      expect(webdav.type, equals('webdav'));
      final webdavRes = await webdav.validate(
        const SourceConfig(
          id: 'dav-1',
          type: 'webdav',
          name: 'Alist DAV',
          endpoint: 'http://127.0.0.1:5244/dav',
        ),
      );
      expect(webdavRes.isValid, isTrue);

      final nfs = NfsSourceProvider();
      expect(nfs.type, equals('nfs'));
      final nfsRes = await nfs.validate(
        const SourceConfig(
          id: 'nfs-1',
          type: 'nfs',
          name: 'NFS Share',
          endpoint: 'nfs://192.168.1.10/media',
        ),
      );
      expect(nfsRes.isValid, isTrue);
    });
  });
}
