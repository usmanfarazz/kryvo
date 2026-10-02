import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The app's single Keystore-backed secure storage, with an in-memory cache.
///
/// Every service used to read its own keys one by one at startup (15+ round
/// trips to Android, each decrypting a value), which made the app sit on a
/// loading spinner. Now everything is read once with [preload] and later
/// reads come from memory. Writes go to storage and update the cache.
class SecureStore {
  SecureStore._();
  static final instance = SecureStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Map<String, String>? _cache;
  Future<void>? _loading;

  /// Load every value into memory (safe to call more than once).
  Future<void> preload() => _loading ??= () async {
        try {
          _cache = await _storage.readAll();
        } catch (_) {
          _cache = null; // fall back to direct reads
        }
      }();

  Future<String?> read({required String key}) async {
    await preload();
    final c = _cache;
    if (c != null) return c[key];
    return _storage.read(key: key);
  }

  Future<Map<String, String>> readAll() async {
    await preload();
    final c = _cache;
    if (c != null) return Map.of(c);
    return _storage.readAll();
  }

  Future<void> write({required String key, required String? value}) async {
    if (value == null) return delete(key: key);
    await _storage.write(key: key, value: value);
    _cache?[key] = value;
  }

  Future<void> delete({required String key}) async {
    await _storage.delete(key: key);
    _cache?.remove(key);
  }
}
