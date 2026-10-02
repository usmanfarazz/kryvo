import 'dart:convert';

import 'secure_store.dart';

import 'crypto_service.dart';

/// Optional Recovery Key — a way back into the vault if the master password is
/// forgotten, WITHOUT breaking zero-knowledge.
///
/// How it stays zero-knowledge:
///   * The recovery key is 160 random bits, generated on-device and shown to
///     the user exactly once. It is never stored in plaintext and never leaves
///     the phone.
///   * We store only the master password *encrypted with a key derived from
///     the recovery key* (PBKDF2 -> AES-256-GCM, the same core as the vault).
///   * Without the recovery key that blob is undecryptable, so the developer /
///     a server / a thief with the phone learns nothing.
///
/// If the user changes their master password later, this stored blob would be
/// stale, so the app disables recovery on password change and asks the user to
/// generate a fresh recovery key.
class RecoveryService {
  static final _storage = SecureStore.instance;
  static const _blobKey = 'securevault.recovery.blob';

  // Crockford-style base32 alphabet: no I, L, O, U (avoids look-alike chars).
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// True once a recovery key has been set up.
  static Future<bool> isEnabled() async {
    final v = await _storage.read(key: _blobKey);
    return v != null && v.isNotEmpty;
  }

  /// Generate a fresh, human-friendly recovery key, e.g.
  /// `K4M9-2XQ7-...` (8 groups of 4 = 160 bits of entropy).
  static String generateRecoveryKey() {
    final bytes = CryptoService.randomBytes(20); // 160 bits
    // Map each 5-bit group to a base32 char (20 bytes = 160 bits = 32 chars).
    final bits = StringBuffer();
    for (final b in bytes) {
      bits.write(b.toRadixString(2).padLeft(8, '0'));
    }
    final s = bits.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i += 5) {
      final chunk = s.substring(i, i + 5);
      out.write(_alphabet[int.parse(chunk, radix: 2)]);
    }
    final raw = out.toString(); // 32 chars
    // Group into 8 blocks of 4 separated by dashes.
    final groups = <String>[];
    for (var i = 0; i < raw.length; i += 4) {
      groups.add(raw.substring(i, i + 4));
    }
    return groups.join('-');
  }

  /// Normalize user input: uppercase, keep only alphabet chars.
  static String _normalize(String input) {
    final up = input.toUpperCase();
    final sb = StringBuffer();
    for (final ch in up.split('')) {
      if (_alphabet.contains(ch)) sb.write(ch);
    }
    return sb.toString();
  }

  /// Enable recovery: store [masterPassword] encrypted under [recoveryKey].
  /// The caller must have already verified [masterPassword] against the vault.
  static Future<void> enable(String masterPassword, String recoveryKey) async {
    final salt = CryptoService.newSalt();
    final key = await CryptoService.deriveKey(_normalize(recoveryKey), salt);
    final blob = await CryptoService.encryptString(masterPassword, key, salt);
    await _storage.write(key: _blobKey, value: jsonEncode(blob));
  }

  static Future<void> disable() async {
    await _storage.delete(key: _blobKey);
  }

  /// Try to recover the master password using [recoveryKey].
  /// Returns the master password, or null if the key is wrong / not set up.
  static Future<String?> recoverMasterPassword(String recoveryKey) async {
    final s = await _storage.read(key: _blobKey);
    if (s == null || s.isEmpty) return null;
    try {
      final blob = jsonDecode(s) as Map<String, dynamic>;
      final salt = CryptoService.saltFromBlob(blob);
      final key = await CryptoService.deriveKey(_normalize(recoveryKey), salt);
      return await CryptoService.decryptString(blob, key); // throws if wrong
    } catch (_) {
      return null;
    }
  }
}
