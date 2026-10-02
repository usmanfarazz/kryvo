import 'dart:typed_data';

import 'package:flutter/services.dart';

/// One app on the phone that can be locked.
class LockableApp {
  final String pkg;
  final String name;
  final Uint8List icon;
  LockableApp(this.pkg, this.name, this.icon);
}

/// Current App Lock setup, read from the Android side.
class AppLockState {
  final bool enabled, hasPin, usage, overlay, fingerprint;
  final Set<String> locked;
  AppLockState(this.enabled, this.hasPin, this.usage, this.overlay,
      this.fingerprint, this.locked);

  bool get permissionsOk => usage && overlay;
}

/// App Lock: put a PIN on other apps (WhatsApp, Gallery…). The watcher and
/// the lock screen are native (AppLockService / AppLockActivity); this is the
/// Dart side of the `kryvo/app_lock` channel.
class AppLockService {
  static const _ch = MethodChannel('kryvo/app_lock');

  static Future<AppLockState> state() async {
    final m = Map<String, dynamic>.from(await _ch.invokeMethod('state') as Map);
    return AppLockState(
      m['enabled'] == true,
      m['hasPin'] == true,
      m['usage'] == true,
      m['overlay'] == true,
      m['bio'] == true,
      {for (final p in (m['locked'] as List? ?? const [])) p as String},
    );
  }

  static Future<List<LockableApp>> apps() async {
    final list = await _ch.invokeMethod('apps') as List? ?? const [];
    return [
      for (final e in list)
        LockableApp(
          (e as Map)['pkg'] as String,
          e['name'] as String,
          e['icon'] as Uint8List,
        ),
    ];
  }

  static Future<void> setLocked(Set<String> pkgs) =>
      _ch.invokeMethod('setLocked', {'apps': pkgs.toList()});

  static Future<bool> setPin(String pin) async =>
      await _ch.invokeMethod<bool>('setPin', {'pin': pin}) ?? false;

  static Future<void> setFingerprint(bool on) =>
      _ch.invokeMethod('setBio', {'on': on});

  static Future<bool> setEnabled(bool on) async =>
      await _ch.invokeMethod<bool>('setEnabled', {'on': on}) ?? false;

  static Future<void> openUsageSettings() =>
      _ch.invokeMethod('openUsageSettings');

  static Future<void> openOverlaySettings() =>
      _ch.invokeMethod('openOverlaySettings');
}
