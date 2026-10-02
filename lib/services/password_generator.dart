import 'dart:math';

/// Strong password generator + strength estimator.
class PasswordGenerator {
  static final Random _rng = Random.secure();

  static const String _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const String _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _nums = '0123456789';
  static const String _syms = '!@#\$%^&*()-_=+[]{};:,.?/';

  /// Build a random password. Lowercase + uppercase are always included;
  /// numbers and symbols are optional toggles.
  static String generate({
    int length = 16,
    bool numbers = true,
    bool symbols = true,
  }) {
    var charset = _lower + _upper;
    if (numbers) charset += _nums;
    if (symbols) charset += _syms;

    final len = length.clamp(6, 64);
    final sb = StringBuffer();
    for (var i = 0; i < len; i++) {
      sb.write(charset[_rng.nextInt(charset.length)]);
    }
    return sb.toString();
  }

  /// Rough Shannon-style entropy in bits, based on the pools actually used.
  static double entropyBits(String pw) {
    if (pw.isEmpty) return 0;
    var pool = 0;
    if (RegExp(r'[a-z]').hasMatch(pw)) pool += 26;
    if (RegExp(r'[A-Z]').hasMatch(pw)) pool += 26;
    if (RegExp(r'[0-9]').hasMatch(pw)) pool += 10;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(pw)) pool += 32;
    if (pool == 0) pool = 1;
    return pw.length * (log(pool) / log(2));
  }

  /// 0..4 strength bucket with a label.
  static ({int score, String label}) strength(String pw) {
    final bits = entropyBits(pw);
    if (pw.isEmpty) return (score: 0, label: '');
    if (bits < 40) return (score: 1, label: 'Weak');
    if (bits < 60) return (score: 2, label: 'Fair');
    if (bits < 80) return (score: 3, label: 'Strong');
    return (score: 4, label: 'Very strong');
  }
}
