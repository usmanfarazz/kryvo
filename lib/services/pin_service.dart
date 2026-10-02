import 'dart:convert';

import 'secure_store.dart';

import 'crypto_service.dart';

/// Optional PIN screen lock (instead of typing the master password).
///
/// The vault is still encrypted with the master password. When PIN lock is on,
/// the master password is kept in Android Keystore-backed secure storage and
/// only released after the correct PIN — the same approach as fingerprint
/// unlock. Wrong PINs are rate-limited (lockout after 5 tries).
/// The PIN itself is never stored, only a salted PBKDF2 hash.
class PinService {
  static final _s = SecureStore.instance;
  static const _type = 'kryvo.lock.type'; // 'password' | 'pin'
  static const _hash = 'kryvo.pin.hash';
  static const _salt = 'kryvo.pin.salt';
  static const _mp = 'kryvo.pin.mp';
  static const _hint = 'kryvo.pin.hint';
  static const _q = 'kryvo.pin.question';
  static const _a = 'kryvo.pin.answer';
  static const _aSalt = 'kryvo.pin.answerSalt';
  static const _fails = 'kryvo.pin.fails';
  static const _until = 'kryvo.pin.lockUntil';
  // Fast check of the PIN (see CryptoService.quickHash) so the PIN pad can
  // open the vault the moment the right PIN is entered.
  static const _qHash = 'kryvo.pin.quickHash';
  static const _qSalt = 'kryvo.pin.quickSalt';

  static Future<void> _writeQuick(String pin) async {
    final salt = CryptoService.newSalt();
    await _s.write(key: _qSalt, value: base64Encode(salt));
    await _s.write(key: _qHash, value: await CryptoService.quickHash(pin, salt));
  }

  /// null = no fast hash stored yet (older install), else whether it matches.
  static Future<bool?> _quickMatches(String pin) async {
    final salt = await _s.read(key: _qSalt);
    final hash = await _s.read(key: _qHash);
    if (salt == null || hash == null) return null;
    return await CryptoService.quickHash(pin, base64Decode(salt)) == hash;
  }

  /// Silent check while the PIN is being typed: returns the master password
  /// if [pin] is right. Wrong guesses here are NOT counted as failed tries
  /// (the user hasn't pressed OK yet).
  static Future<String?> quickVerify(String pin) async {
    if (await lockoutLeft() > 0) return null;
    if (await _quickMatches(pin) != true) return null;
    await _s.delete(key: _fails);
    return _s.read(key: _mp);
  }

  static Future<bool> isPinMode() async =>
      (await _s.read(key: _type)) == 'pin' &&
      (await _s.read(key: _hash)) != null;

  static Future<String> _hashOf(String secret, List<int> salt) async {
    final k = await CryptoService.deriveKey(secret, salt);
    return base64Encode(await k.extractBytes());
  }

  /// Turn on PIN lock. [masterPassword] must already be verified.
  static Future<void> enable(String pin, String masterPassword) async {
    final salt = CryptoService.newSalt();
    await _s.write(key: _salt, value: base64Encode(salt));
    await _s.write(key: _hash, value: await _hashOf(pin, salt));
    await _writeQuick(pin);
    await _s.write(key: _mp, value: masterPassword);
    await _s.write(key: _type, value: 'pin');
    await _s.delete(key: _fails);
    await _s.delete(key: _until);
  }

  /// Back to master-password lock. Keeps hint/question for next time.
  static Future<void> disable() async {
    await _s.write(key: _type, value: 'password');
    await _s.delete(key: _hash);
    await _s.delete(key: _salt);
    await _s.delete(key: _mp);
    await _s.delete(key: _qHash);
    await _s.delete(key: _qSalt);
  }

  static Future<void> updateMasterPassword(String mp) async {
    if (await isPinMode()) await _s.write(key: _mp, value: mp);
  }

  /// Seconds left in a wrong-PIN lockout (0 = can try now).
  static Future<int> lockoutLeft() async {
    final until = int.tryParse(await _s.read(key: _until) ?? '') ?? 0;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? (left / 1000).ceil() : 0;
  }

  /// Returns the master password if [pin] is right, otherwise null.
  static Future<String?> verify(String pin) async {
    if (await lockoutLeft() > 0) return null;
    final saltB64 = await _s.read(key: _salt);
    final hash = await _s.read(key: _hash);
    if (saltB64 == null || hash == null) return null;
    final quick = await _quickMatches(pin);
    final ok = quick ?? await _hashOf(pin, base64Decode(saltB64)) == hash;
    if (ok) {
      if (quick == null) await _writeQuick(pin); // upgrade older installs
      await _s.delete(key: _fails);
      return _s.read(key: _mp);
    }
    final fails = (int.tryParse(await _s.read(key: _fails) ?? '') ?? 0) + 1;
    await _s.write(key: _fails, value: '$fails');
    if (fails >= 5) {
      // 30s, then 60s, 120s ... for repeated failures.
      final secs = 30 * (1 << ((fails - 5).clamp(0, 5)));
      await _s.write(
          key: _until,
          value: '${DateTime.now().millisecondsSinceEpoch + secs * 1000}');
    }
    return null;
  }

  /// Master password stored for PIN mode (after a verified security answer).
  static Future<String?> storedMasterPassword() => _s.read(key: _mp);

  // ---- Hint -----------------------------------------------------------------

  static Future<String> hint() async => await _s.read(key: _hint) ?? '';
  static Future<void> setHint(String h) => h.trim().isEmpty
      ? _s.delete(key: _hint)
      : _s.write(key: _hint, value: h.trim());

  // ---- Security question ----------------------------------------------------

  static Future<String> question() async => await _s.read(key: _q) ?? '';

  static String _norm(String a) => a.trim().toLowerCase();

  static Future<void> setQuestion(String q, String answer) async {
    final salt = CryptoService.newSalt();
    await _s.write(key: _q, value: q.trim());
    await _s.write(key: _aSalt, value: base64Encode(salt));
    await _s.write(key: _a, value: await _hashOf(_norm(answer), salt));
  }

  static Future<bool> checkAnswer(String answer) async {
    final saltB64 = await _s.read(key: _aSalt);
    final hash = await _s.read(key: _a);
    if (saltB64 == null || hash == null) return false;
    return await _hashOf(_norm(answer), base64Decode(saltB64)) == hash;
  }

  static Future<void> wipe() async {
    for (final k in [_type, _hash, _salt, _mp, _hint, _q, _a, _aSalt, _fails, _until, _qHash, _qSalt]) {
      await _s.delete(key: k);
    }
  }
}
