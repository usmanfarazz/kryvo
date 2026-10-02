import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'media_service.dart';
import 'secure_store.dart';

/// One failed unlock attempt.
class IntruderEvent {
  final int at; // epoch ms
  final String method; // 'pin' | 'password'
  final String? photoId; // MediaItem id of the selfie, if one was taken

  IntruderEvent(this.at, this.method, this.photoId);

  Map<String, dynamic> toJson() => {'at': at, 'm': method, 'p': photoId};
  factory IntruderEvent.fromJson(Map<String, dynamic> j) => IntruderEvent(
      j['at'] as int? ?? 0, j['m'] as String? ?? 'pin', j['p'] as String?);
}

/// Break-in log + intruder selfie.
///
/// Every wrong PIN / password on the lock screen is logged. With "Intruder
/// selfie" on, from the 2nd wrong try in a row the front camera silently
/// takes a photo, which is stored encrypted in the vault like any other
/// photo (category [category]) — only you can see it after unlocking.
class IntruderService {
  static final _s = SecureStore.instance;
  static const _enabledKey = 'kryvo.intruder.on';
  static const _logKey = 'kryvo.intruder.log';
  static const _unseenKey = 'kryvo.intruder.unseen';

  /// Media category used for intruder photos (not shown in the 4 sections).
  static const category = 'intruder';

  /// Wrong attempts in a row before a selfie is taken.
  static const threshold = 2;

  /// At most this many photos per series of wrong attempts.
  static const maxPhotosPerSeries = 3;

  static Future<bool> isEnabled() async =>
      (await _s.read(key: _enabledKey)) == '1';

  static Future<void> setEnabled(bool on) =>
      _s.write(key: _enabledKey, value: on ? '1' : '0');

  static Future<List<IntruderEvent>> log() async {
    final s = await _s.read(key: _logKey);
    if (s == null || s.isEmpty) return [];
    return (jsonDecode(s) as List)
        .map((e) => IntruderEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> _saveLog(List<IntruderEvent> l) =>
      _s.write(key: _logKey, value: jsonEncode(l.map((e) => e.toJson()).toList()));

  static Future<int> unseen() async =>
      int.tryParse(await _s.read(key: _unseenKey) ?? '') ?? 0;

  static Future<void> markSeen() => _s.delete(key: _unseenKey);

  static Future<void> clear() async {
    await _s.delete(key: _logKey);
    await _s.delete(key: _unseenKey);
  }

  // Attempts are handled one at a time, so two quick wrong tries can't
  // overwrite each other's log entry or photo.
  static Future<void> _queue = Future.value();

  /// Completes when every pending attempt (and its photo) has been saved.
  static Future<void> idle() => _queue;

  /// Record a failed attempt; [takePhoto] decides whether to try a selfie.
  static Future<void> record(String method, {required bool takePhoto}) =>
      _queue = _queue.then((_) => _record(method, takePhoto)).catchError((e) {
        debugPrint('Kryvo intruder: $e');
      });

  static Future<void> _record(String method, bool takePhoto) async {
    String? photoId;
    if (takePhoto && await isEnabled()) photoId = await _selfie();
    final l = await log();
    l.insert(0, IntruderEvent(DateTime.now().millisecondsSinceEpoch, method, photoId));
    if (l.length > 100) l.removeRange(100, l.length);
    await _saveLog(l);
    await _s.write(key: _unseenKey, value: '${await unseen() + 1}');
  }

  /// Ask for camera permission now (when the user turns the feature on), by
  /// opening and closing the front camera once. Returns false if refused.
  static Future<bool> warmUp() async {
    final c = await _open();
    if (c == null) return false;
    await c.dispose();
    return true;
  }

  static Future<CameraController?> _open() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        debugPrint('Kryvo intruder: no camera');
        return null;
      }
      final front = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cams.first);
      final c = CameraController(front, ResolutionPreset.medium,
          enableAudio: false);
      await c.initialize();
      return c;
    } catch (e) {
      debugPrint('Kryvo intruder: camera open failed: $e');
      return null;
    }
  }

  /// Take a front-camera photo and store it encrypted. Returns its id.
  static Future<String?> _selfie() async {
    final c = await _open();
    if (c == null) return null;
    try {
      final shot = await c.takePicture();
      final file = File(shot.path);
      final bytes = await file.readAsBytes();
      try {
        await file.delete(); // never leave the plain photo on disk
      } catch (_) {}
      final item = await MediaService.addPhotoBytes(
        bytes: bytes,
        name: 'intruder_${DateTime.now().millisecondsSinceEpoch}.jpg',
        category: category,
      );
      return item.id;
    } catch (e) {
      debugPrint('Kryvo intruder: photo failed: $e');
      return null;
    } finally {
      await c.dispose();
    }
  }
}
