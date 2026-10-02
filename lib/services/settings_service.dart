import 'secure_store.dart';

/// Small persistent app settings (theme, auto-lock). Not secret, but reusing
/// the same secure storage keeps things simple.
class SettingsService {
  static final _storage = SecureStore.instance;
  static const _themeKey = 'securevault.settings.dark';
  static const _autoLockKey = 'securevault.settings.autolock';

  static Future<bool> readDark() async {
    final v = await _storage.read(key: _themeKey);
    return v == null ? true : v == '1'; // default dark
  }

  static Future<void> writeDark(bool dark) =>
      _storage.write(key: _themeKey, value: dark ? '1' : '0');

  static const _themeIdKey = 'kryvo.settings.theme';

  /// Selected colour theme id. Migrates the old dark/light switch.
  static Future<String> readThemeId() async {
    final v = await _storage.read(key: _themeIdKey);
    if (v != null && v.isNotEmpty) return v;
    return (await readDark()) ? 'midnight' : 'light';
  }

  static Future<void> writeThemeId(String id) =>
      _storage.write(key: _themeIdKey, value: id);

  static Future<int> readAutoLockSeconds() async {
    final v = await _storage.read(key: _autoLockKey);
    return int.tryParse(v ?? '') ?? 60; // default 60s
  }

  static Future<void> writeAutoLockSeconds(int seconds) =>
      _storage.write(key: _autoLockKey, value: '$seconds');

  // ---- Generic helpers ------------------------------------------------------

  static Future<bool> getBool(String key, bool def) async {
    final v = await _storage.read(key: key);
    return v == null ? def : v == '1';
  }

  static Future<void> setBool(String key, bool v) =>
      _storage.write(key: key, value: v ? '1' : '0');

  static Future<String?> getString(String key) => _storage.read(key: key);

  static Future<void> setString(String key, String v) =>
      _storage.write(key: key, value: v);

  static Future<int> getInt(String key, int def) async =>
      int.tryParse(await _storage.read(key: key) ?? '') ?? def;

  static Future<void> setInt(String key, int v) =>
      _storage.write(key: key, value: '$v');
}

/// Keys for the gallery-style settings.
class PrefKeys {
  static const slideshowSecs = 'kryvo.slideshow.secs';
  static const maxZoom = 'kryvo.viewer.maxZoom';
  static const hideGuide = 'kryvo.viewer.hideGuide';
  static const detailView = 'kryvo.viewer.detail';
  static const fitSmall = 'kryvo.viewer.fitSmall';
  static const hideFolderThumbs = 'kryvo.app.hideFolderThumbs';
  static const vibration = 'kryvo.lock.vibration';
  static const shakeLock = 'kryvo.lock.shake';
  static const lang = 'kryvo.app.lang';
  static const onboarded = 'kryvo.app.onboarded';
  static const faceDownLock = 'kryvo.lock.faceDown';
}
