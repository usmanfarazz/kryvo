import 'dart:convert';

import 'package:flutter/services.dart';

import 'crypto_service.dart';
import 'secure_store.dart';

/// Launcher icon + disguise mode.
///
/// The icons are <activity-alias> entries in AndroidManifest.xml, switched by
/// MainActivity over the `kryvo/app_icon` channel. With a disguise icon the
/// app opens as a working Calculator / Notes / Clock / Game / Flashlight; the
/// vault only appears after the user enters their secret code (or PIN) there.
class DisguiseService {
  static const _ch = MethodChannel('kryvo/app_icon');
  static final _s = SecureStore.instance;

  static const _codeHash = 'kryvo.disguise.codeHash';
  static const _codeSalt = 'kryvo.disguise.codeSalt';
  static const _fails = 'kryvo.disguise.fails';
  static const _until = 'kryvo.disguise.lockUntil';

  static const kryvoIcons = <(String, String)>[
    ('default', 'Classic blue'),
    ('purple', 'Purple'),
    ('green', 'Emerald'),
    ('dark', 'Midnight'),
    ('rose', 'Rose'),
  ];

  /// (id, name shown on the home screen, how to open the vault from it)
  static const disguiseIcons = <(String, String, String)>[
    ('calc', 'Calculator', 'Type your secret code, then press  =.'),
    ('notes', 'Notes', 'Write a note with only your secret code in it and save it.'),
    ('clock', 'Clock', 'Open Timer, type your secret code as the time and press Start.'),
    ('game', 'Games', 'Tap the gear icon → "Redeem code" and enter your secret code.'),
    ('torch', 'Flashlight', 'Tap the gear icon → "Calibration code" and enter your secret code.'),
  ];

  static bool isDisguise(String id) => disguiseIcons.any((d) => d.$1 == id);

  static String nameOf(String id) {
    for (final d in disguiseIcons) {
      if (d.$1 == id) return d.$2;
    }
    for (final k in kryvoIcons) {
      if (k.$1 == id) return k.$2;
    }
    return 'Kryvo';
  }

  static String howToOpen(String id) =>
      disguiseIcons.firstWhere((d) => d.$1 == id, orElse: () => ('', '', '')).$3;

  // ---- Launcher icon ----------------------------------------------------------

  static Future<String> currentIcon() async {
    try {
      return await _ch.invokeMethod<String>('get') ?? 'default';
    } catch (_) {
      return 'default';
    }
  }

  static Future<void> setIcon(String id) =>
      _ch.invokeMethod('set', {'id': id});

  // ---- Flashlight ---------------------------------------------------------------

  static Future<bool> hasTorch() async {
    try {
      return await _ch.invokeMethod<bool>('hasTorch') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> torch(bool on) async {
    try {
      return await _ch.invokeMethod<bool>('torch', {'on': on}) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---- Secret code ----------------------------------------------------------------

  static Future<bool> hasCode() async => (await _s.read(key: _codeHash)) != null;

  static Future<void> setCode(String code) async {
    final salt = CryptoService.newSalt();
    await _s.write(key: _codeSalt, value: base64Encode(salt));
    await _s.write(
        key: _codeHash, value: await CryptoService.quickHash(code, salt));
  }

  static Future<bool> checkCode(String code) async {
    final salt = await _s.read(key: _codeSalt);
    final hash = await _s.read(key: _codeHash);
    if (salt == null || hash == null) return false;
    return await CryptoService.quickHash(code, base64Decode(salt)) == hash;
  }

  static Future<void> clearCode() async {
    await _s.delete(key: _codeHash);
    await _s.delete(key: _codeSalt);
  }

  // ---- Guessing limit -----------------------------------------------------------
  // Code-like entries (4–8 digits) that don't match are counted; after 10 in a
  // row the disguise silently stops accepting codes for 5 minutes, so nobody
  // can try every PIN on the calculator. Normal calculations are not counted.

  static Future<bool> lockedOut() async {
    final until = int.tryParse(await _s.read(key: _until) ?? '') ?? 0;
    return until > DateTime.now().millisecondsSinceEpoch;
  }

  static Future<void> noteFail() async {
    final fails = (int.tryParse(await _s.read(key: _fails) ?? '') ?? 0) + 1;
    if (fails >= 10) {
      await _s.write(
          key: _until,
          value: '${DateTime.now().millisecondsSinceEpoch + 5 * 60 * 1000}');
      await _s.delete(key: _fails);
    } else {
      await _s.write(key: _fails, value: '$fails');
    }
  }

  static Future<void> resetFails() async {
    await _s.delete(key: _fails);
    await _s.delete(key: _until);
  }

  /// True for entries that look like a secret code (4–8 digits).
  static bool looksLikeCode(String s) => RegExp(r'^\d{4,8}$').hasMatch(s);
}
