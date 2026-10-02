// Unit tests for the parts of Kryvo that don't need a phone: encryption,
// the password generator and the Calculator disguise's arithmetic.
// (Screens that use secure storage, biometrics or the gallery are tested on a
// device with the "Kryvo Dev" debug build.)
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securevault/disguise/calculator_disguise.dart';
import 'package:securevault/services/crypto_service.dart';
import 'package:securevault/services/password_generator.dart';

void main() {
  group('CryptoService', () {
    test('string round trip with the right password', () async {
      final salt = CryptoService.newSalt();
      final key = await CryptoService.deriveKey('correct horse', salt);
      final blob = await CryptoService.encryptString('secret data', key, salt);
      expect(blob['ct'], isNot(contains('secret')));
      expect(await CryptoService.decryptString(blob, key), 'secret data');
    });

    test('wrong password cannot decrypt', () async {
      final salt = CryptoService.newSalt();
      final key = await CryptoService.deriveKey('right', salt);
      final wrong = await CryptoService.deriveKey('wrong', salt);
      final blob = await CryptoService.encryptString('x', key, salt);
      expect(() => CryptoService.decryptString(blob, wrong), throwsA(anything));
    });

    test('bytes round trip and tamper detection', () async {
      final key = SecretKey(CryptoService.randomBytes(32));
      final data = Uint8List.fromList(utf8.encode('photo bytes'));
      final enc = await CryptoService.encryptBytes(data, key);
      expect(await CryptoService.decryptBytes(enc, key), data);
      enc[enc.length - 1] ^= 1; // flip one bit
      expect(() => CryptoService.decryptBytes(enc, key), throwsA(anything));
    });

    test('quick hash depends on secret and salt', () async {
      final s1 = CryptoService.newSalt(), s2 = CryptoService.newSalt();
      final a = await CryptoService.quickHash('1234', s1);
      expect(await CryptoService.quickHash('1234', s1), a);
      expect(await CryptoService.quickHash('1235', s1), isNot(a));
      expect(await CryptoService.quickHash('1234', s2), isNot(a));
    });
  });

  group('PasswordGenerator', () {
    test('length and character sets', () {
      final pw = PasswordGenerator.generate(length: 20);
      expect(pw.length, 20);
      expect(PasswordGenerator.generate(length: 2).length, 6); // clamped
      final letters = PasswordGenerator.generate(numbers: false, symbols: false);
      expect(RegExp(r'^[a-zA-Z]+$').hasMatch(letters), isTrue);
    });

    test('strength buckets', () {
      expect(PasswordGenerator.strength('abc').label, 'Weak');
      expect(PasswordGenerator.strength('Xk9#mQ2!vL7@pZ4&').score, 4);
    });
  });

  group('Calculator disguise', () {
    double? calc(String s) => CalcEngine.eval(s);

    test('precedence and operators', () {
      expect(calc('2+3×4'), 14);
      expect(calc('10÷4'), 2.5);
      expect(calc('7−10'), -3);
      expect(calc('−5+2'), -3);
      expect(calc('50%'), 0.5);
    });

    test('bad input', () {
      expect(calc(''), isNull);
      expect(calc('5÷0'), isNull);
      expect(calc('2+'), 2); // trailing operator ignored
    });

    test('formatting', () {
      expect(CalcEngine.format(14), '14');
      expect(CalcEngine.format(2.5), '2.5');
      expect(CalcEngine.format(-3), '−3');
      expect(CalcEngine.format(1 / 3), '0.3333333333');
    });
  });
}
