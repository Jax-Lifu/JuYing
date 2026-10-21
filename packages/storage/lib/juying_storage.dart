/// Storage and Credential Persistence Abstraction for JuYing.
///
/// **What**: Provides interfaces for key-value settings, database queries,
/// and secure hardware credential vaults (Section 5.10).
///
/// **Why**: Sensitive NAS and WebDAV passwords must only reside in platform-level
/// secure storage (Windows Credential Vault / Android Keystore), while sources and
/// channels live in relational storage with schema migrations.
library;

export 'sync/lww_conflict_resolver.dart';
export 'sync/sync_entity.dart';

/// Key-value secure credential storage contract.
abstract interface class ISecureCredentialVault {
  Future<void> writeCredential(String key, String secret);
  Future<String?> readCredential(String key);
  Future<void> deleteCredential(String key);
}
