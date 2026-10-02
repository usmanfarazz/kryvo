import 'dart:convert';

import 'crypto_service.dart';
import 'secure_store.dart';

/// Extra PIN on single folders. Only a salted hash per folder is stored.
/// Keys are "space|category|folder" so the decoy vault's folders are separate.
class FolderLockService {
  static final _s = SecureStore.instance;
  static const _key = 'kryvo.folder.locks';

  static String keyOf(String space, String cat, String folder) =>
      '$space|$cat|$folder';

  /// key -> "saltB64:hashB64"
  static Future<Map<String, String>> load() async {
    final s = await _s.read(key: _key);
    if (s == null || s.isEmpty) return {};
    return (jsonDecode(s) as Map<String, dynamic>).cast<String, String>();
  }

  static Future<void> _save(Map<String, String> m) =>
      _s.write(key: _key, value: jsonEncode(m));

  static Future<Map<String, String>> set(String key, String pin) async {
    final m = await load();
    final salt = CryptoService.newSalt();
    m[key] = '${base64Encode(salt)}:${await CryptoService.quickHash(pin, salt)}';
    await _save(m);
    return m;
  }

  static Future<Map<String, String>> remove(String key) async {
    final m = await load()..remove(key);
    await _save(m);
    return m;
  }

  static Future<Map<String, String>> rename(String from, String to) async {
    final m = await load();
    final v = m.remove(from);
    if (v != null) m[to] = v;
    await _save(m);
    return m;
  }

  static Future<bool> check(Map<String, String> locks, String key, String pin) async {
    final v = locks[key];
    if (v == null) return true;
    final parts = v.split(':');
    if (parts.length != 2) return false;
    return await CryptoService.quickHash(pin, base64Decode(parts[0])) == parts[1];
  }

  static Future<void> clear() => _s.delete(key: _key);
}
