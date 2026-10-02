import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'secure_store.dart';

import 'crypto_service.dart';

/// Makes unlocking instant after the first successful unlock.
///
/// Deriving the vault key (PBKDF2, 310k rounds) takes a few seconds. After a
/// successful unlock we keep that derived key in Android Keystore-backed
/// secure storage (the same protection fingerprint / PIN unlock already use
/// for the master password), together with a cheap salted hash of the
/// password. Unlocking then only needs the cheap hash check, so the vault can
/// open the moment the correct password is typed.
///
/// The cached key is tied to the vault's salt: after a password change or a
/// backup restore the salt differs, the cache is ignored and refreshed on the
/// next full unlock.
class QuickUnlockService {
  static final _s = SecureStore.instance;
  static const _salt = 'kryvo.quick.salt';
  static const _hash = 'kryvo.quick.hash';
  static const _vaultSalt = 'kryvo.quick.vaultSalt';
  static const _key = 'kryvo.quick.key';

  /// Remember [key] (derived from [password] with [vaultSalt]).
  static Future<void> remember(
      String password, List<int> vaultSalt, SecretKey key) async {
    final salt = CryptoService.newSalt();
    await _s.write(key: _salt, value: base64Encode(salt));
    await _s.write(
        key: _hash, value: await CryptoService.quickHash(password, salt));
    await _s.write(key: _vaultSalt, value: base64Encode(vaultSalt));
    await _s.write(key: _key, value: base64Encode(await key.extractBytes()));
  }

  /// The cached vault key if [password] matches and the cache belongs to the
  /// vault with [vaultSalt]; otherwise null.
  static Future<SecretKey?> keyFor(String password, List<int> vaultSalt) async {
    final all = await _s.readAll();
    final salt = all[_salt], hash = all[_hash];
    final vs = all[_vaultSalt], key = all[_key];
    if (salt == null || hash == null || vs == null || key == null) return null;
    if (vs != base64Encode(vaultSalt)) return null;
    if (await CryptoService.quickHash(password, base64Decode(salt)) != hash) {
      return null;
    }
    return SecretKey(base64Decode(key));
  }

  /// The cached vault key without a password check — only for opening the
  /// decoy vault (which shows none of the real data). Null if not cached or
  /// cached for another vault.
  static Future<SecretKey?> cachedKey(List<int> vaultSalt) async {
    final vs = await _s.read(key: _vaultSalt), key = await _s.read(key: _key);
    if (vs == null || key == null || vs != base64Encode(vaultSalt)) return null;
    return SecretKey(base64Decode(key));
  }

  static Future<void> clear() async {
    for (final k in [_salt, _hash, _vaultSalt, _key]) {
      await _s.delete(key: k);
    }
  }
}
