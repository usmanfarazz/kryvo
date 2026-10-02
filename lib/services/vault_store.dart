import 'dart:convert';

import 'secure_store.dart';

/// Persists the *encrypted* vault blob.
///
/// The blob is already AES-256-GCM encrypted before it reaches here, so even
/// the storage layer never sees plaintext. We additionally keep it in
/// Android Keystore-backed secure storage for defense in depth.
class VaultStore {
  static const _key = 'securevault.blob.v1';

  static final _storage = SecureStore.instance;

  /// True once a vault has been created on this device.
  static Future<bool> exists() async {
    final v = await _storage.read(key: _key);
    return v != null && v.isNotEmpty;
  }

  /// Read the stored encrypted blob (as a JSON map), or null if none.
  static Future<Map<String, dynamic>?> readBlob() async {
    final s = await _storage.read(key: _key);
    if (s == null || s.isEmpty) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }

  /// Overwrite the stored encrypted blob.
  static Future<void> writeBlob(Map<String, dynamic> blob) async {
    await _storage.write(key: _key, value: jsonEncode(blob));
  }

  /// Permanently delete the vault from this device.
  static Future<void> wipe() async {
    await _storage.delete(key: _key);
  }
}
