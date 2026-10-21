import 'package:test/test.dart';
import 'package:juying_core/juying_core.dart';

void main() {
  group('JuYing Core Domain Model Tests', () {
    test('MediaItem model instantiation and immutability', () {
      const item = MediaItem(
        id: 'test_123',
        title: 'Test Movie',
        year: '2026',
        rating: 9.2,
      );
      expect(item.id, 'test_123');
      expect(item.title, 'Test Movie');
      expect(item.rating, 9.2);

      final updated = item.copyWith(title: 'Updated Title');
      expect(updated.title, 'Updated Title');
      expect(updated.id, 'test_123');
    });

    test('DeviceProfile matches hardware manufacturer and regex', () {
      const profile = DeviceProfile(
        id: 'sony-bravia',
        manufacturer: 'Sony',
        modelRegex: r'^KD-.*',
        quirks: DeviceQuirks(supportsMkv: true, supportsRange: true),
      );

      expect(
        profile.matches(
          deviceManufacturer: 'Sony Visual Products',
          deviceModel: 'KD-65X9000H',
        ),
        isTrue,
      );

      expect(
        profile.matches(
          deviceManufacturer: 'Samsung Electronics',
          deviceModel: 'QA65Q70',
        ),
        isFalse,
      );
    });

    test(
        'StandardDeviceProfiles resolves Xiaomi, Sony, Samsung, Huawei presets',
        () {
      final xiaomi = StandardDeviceProfiles.resolveProfile(
        manufacturer: 'Xiaomi Inc.',
        model: 'MiTV-4A',
      );
      expect(xiaomi.id, equals('xiaomi-tv'));
      expect(xiaomi.quirks.requiresContentFeatures, isTrue);

      final sony = StandardDeviceProfiles.resolveProfile(
        manufacturer: 'Sony Corporation',
        model: 'BRAVIA_4K_TV',
      );
      expect(sony.id, equals('sony-bravia'));
      expect(sony.quirks.supportsMkv, isFalse);

      final samsung = StandardDeviceProfiles.resolveProfile(
        manufacturer: 'Samsung Electronics',
        model: 'UA55NU7100',
      );
      expect(samsung.id, equals('samsung-tizen'));

      final huawei = StandardDeviceProfiles.resolveProfile(
        manufacturer: 'HUAWEI TECHNOLOGIES',
        model: 'Vision_X65',
      );
      expect(huawei.id, equals('huawei-vision'));

      final unknown = StandardDeviceProfiles.resolveProfile(
        manufacturer: 'UnknownBrand',
        model: 'GenericBox',
      );
      expect(unknown.id, equals('generic-renderer'));
    });

    test('AppResult and AppFailure functional fold', () {
      const failure = AppFailure(
        code: ErrorCode.liveStreamOffline,
        message: 'IPTV route timed out',
      );
      final result = AppResult<String>.failure(failure);

      expect(result.isFailure, isTrue);
      expect(result.isSuccess, isFalse);
      expect(
        result.fold(
          onSuccess: (val) => 'OK: $val',
          onFailure: (err) => 'ERR: ${err.code.name}',
        ),
        'ERR: liveStreamOffline',
      );
    });
  });
}
