import 'dart:convert';

import 'crypto_service.dart';
import 'secure_store.dart';

/// Fake PIN / password for the decoy vault. Only a salted hash is stored.
/// Entering it on the lock screen (or in a disguise app) opens an almost
/// empty "decoy" vault instead of the real one — for when someone forces you
/// to open Kryvo.
class DecoyService {
  static final _s = SecureStore.instance;
  static const _hash = 'kryvo.decoy.hash';
  static const _salt = 'kryvo.decoy.salt';

  static Future<bool> isSet() async => (await _s.read(key: _hash)) != null;

  static Future<void> set(String code) async {
    final salt = CryptoService.newSalt();
    await _s.write(key: _salt, value: base64Encode(salt));
    await _s.write(key: _hash, value: await CryptoService.quickHash(code, salt));
  }

  static Future<void> clear() async {
    await _s.delete(key: _hash);
    await _s.delete(key: _salt);
  }

  static Future<bool> matches(String code) async {
    if (code.isEmpty) return false;
    final salt = await _s.read(key: _salt);
    final hash = await _s.read(key: _hash);
    if (salt == null || hash == null) return false;
    return await CryptoService.quickHash(code, base64Decode(salt)) == hash;
  }
}
