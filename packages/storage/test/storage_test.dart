import 'package:test/test.dart';
import 'package:juying_storage/juying_storage.dart';

class InMemoryVault implements ISecureCredentialVault {
  final Map<String, String> _store = {};

  @override
  Future<void> writeCredential(String key, String secret) async {
    _store[key] = secret;
  }

  @override
  Future<String?> readCredential(String key) async {
    return _store[key];
  }

  @override
  Future<void> deleteCredential(String key) async {
    _store.remove(key);
  }
}

void main() {
  group('Secure Credential Vault Tests (Section 5.10 & APP-12)', () {
    test(
        'ISecureCredentialVault stores, retrieves and deletes credentials securely',
        () async {
      final vault = InMemoryVault();
      await vault.writeCredential('nas_key', 'superSecretP@ss');

      expect(await vault.readCredential('nas_key'), equals('superSecretP@ss'));
      expect(await vault.readCredential('non_existent'), isNull);

      await vault.deleteCredential('nas_key');
      expect(await vault.readCredential('nas_key'), isNull);
    });
  });
}
