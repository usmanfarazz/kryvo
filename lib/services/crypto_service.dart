import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Zero-knowledge crypto core.
///
/// Scheme (matches the SecureVault web app):
///   - Key derivation: PBKDF2-HMAC-SHA256, 310,000 iterations, 256-bit key
///   - Encryption:     AES-256-GCM (authenticated) with a random 12-byte IV
///   - Salt:           random 16 bytes, stored alongside the ciphertext
///
/// The master password is NEVER stored. Only the salt + ciphertext + IV + MAC
/// are persisted. A wrong password fails the GCM authentication tag, so it is
/// impossible to decrypt the vault without the exact master password.
class CryptoService {
  static const int pbkdf2Iterations = 310000;
  static const int _saltLen = 16;
  static const int _ivLen = 12;

  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: pbkdf2Iterations,
    bits: 256,
  );
  static final _aes = AesGcm.with256bits();
  static final Random _rng = Random.secure();

  /// Derive a 256-bit AES key from the master password and salt.
  static Future<SecretKey> deriveKey(String masterPassword, List<int> salt) {
    return _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(masterPassword)),
      nonce: salt,
    );
  }

  static final _quickPbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 10000,
    bits: 256,
  );

  /// Cheap salted hash (base64) used only to check a secret against a value
  /// kept in Keystore-backed secure storage — fast enough to run on every
  /// keystroke. Never used to encrypt anything.
  static Future<String> quickHash(String secret, List<int> salt) async {
    final k = await _quickPbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: salt,
    );
    return base64Encode(await k.extractBytes());
  }

  static Uint8List randomBytes(int n) {
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = _rng.nextInt(256);
    }
    return b;
  }

  static Uint8List newSalt() => randomBytes(_saltLen);

  /// Encrypt a plaintext string with the given key.
  /// Returns a self-describing JSON map (base64 fields) safe to store/export.
  static Future<Map<String, dynamic>> encryptString(
    String plaintext,
    SecretKey key,
    List<int> salt,
  ) async {
    final iv = randomBytes(_ivLen);
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: iv,
    );
    return <String, dynamic>{
      'v': 1,
      'alg': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iter': pbkdf2Iterations,
      'salt': base64Encode(salt),
      'iv': base64Encode(box.nonce),
      'ct': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  /// Decrypt a blob produced by [encryptString] with the given key.
  /// Throws if the key is wrong (GCM auth tag mismatch) or data is corrupt.
  static Future<String> decryptString(
    Map<String, dynamic> blob,
    SecretKey key,
  ) async {
    final box = SecretBox(
      base64Decode(blob['ct'] as String),
      nonce: base64Decode(blob['iv'] as String),
      mac: Mac(base64Decode(blob['mac'] as String)),
    );
    final clear = await _aes.decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }

  static List<int> saltFromBlob(Map<String, dynamic> blob) =>
      base64Decode(blob['salt'] as String);

  // ---- Binary helpers (for media files) ------------------------------------
  //
  // On-disk format for an encrypted media file:
  //   [ iv: 12 bytes ][ mac: 16 bytes ][ ciphertext: N bytes ]
  // Self-describing enough to decrypt with the same key. GCM's tag is 16 bytes.

  static const int _gcmTagLen = 16;

  /// Encrypt raw bytes (a photo/video) with [key]. Returns iv||mac||ciphertext.
  static Future<Uint8List> encryptBytes(List<int> data, SecretKey key) async {
    final iv = randomBytes(_ivLen);
    final box = await _aes.encrypt(data, secretKey: key, nonce: iv);
    final out = BytesBuilder(copy: false);
    out.add(iv);
    out.add(box.mac.bytes);
    out.add(box.cipherText);
    return out.toBytes();
  }

  /// Decrypt bytes produced by [encryptBytes]. Throws if the key is wrong or
  /// the data is corrupt (GCM auth-tag mismatch).
  static Future<Uint8List> decryptBytes(Uint8List blob, SecretKey key) async {
    final iv = blob.sublist(0, _ivLen);
    final mac = blob.sublist(_ivLen, _ivLen + _gcmTagLen);
    final ct = blob.sublist(_ivLen + _gcmTagLen);
    final box = SecretBox(ct, nonce: iv, mac: Mac(mac));
    final clear = await _aes.decrypt(box, secretKey: key);
    return Uint8List.fromList(clear);
  }

  /// A random 256-bit key, base64-encoded (used as the stable media key).
  static String newRandomKeyB64() => base64Encode(randomBytes(32));

  static SecretKey keyFromB64(String b64) => SecretKey(base64Decode(b64));
}
