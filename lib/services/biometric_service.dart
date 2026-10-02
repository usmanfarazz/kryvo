import 'secure_store.dart';
import 'package:local_auth/local_auth.dart';

/// Optional fingerprint / face unlock.
///
/// Zero-knowledge is preserved: biometrics do NOT derive the key. Instead,
/// when the user opts in, the master password is stored in Android
/// Keystore-backed secure storage and only released after a successful
/// biometric (or device-credential) check. If the phone has no biometrics
/// enrolled, this feature simply stays off.
class BiometricService {
  static final _auth = LocalAuthentication();
  static final _storage = SecureStore.instance;
  static const _pwKey = 'securevault.biometric.mp';
  static const _flagKey = 'securevault.biometric.enabled';

  static Future<bool> deviceSupportsBiometrics() async {
    try {
      final can = await _auth.canCheckBiometrics ||
          await _auth.isDeviceSupported();
      return can;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    return (await _storage.read(key: _flagKey)) == '1' &&
        (await _storage.read(key: _pwKey)) != null;
  }

  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Store the master password behind biometrics. Call only after the password
  /// has been verified against the vault.
  static Future<void> enable(String masterPassword) async {
    await _storage.write(key: _pwKey, value: masterPassword);
    await _storage.write(key: _flagKey, value: '1');
  }

  static Future<void> disable() async {
    await _storage.delete(key: _pwKey);
    await _storage.delete(key: _flagKey);
  }

  /// Returns the stored master password after a successful biometric check,
  /// or null if unavailable / cancelled.
  static Future<String?> unlockPassword() async {
    if (!await isEnabled()) return null;
    final ok = await authenticate('Unlock SecureVault');
    if (!ok) return null;
    return _storage.read(key: _pwKey);
  }
}
