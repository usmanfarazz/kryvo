import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

/// "Shake to lock" and "Face-down to lock": watches the accelerometer only
/// while the vault is open and at least one of the two options is on.
class MotionLock {
  final void Function() onLock;
  MotionLock(this.onLock);

  StreamSubscription<AccelerometerEvent>? _sub;
  bool _shake = false, _faceDown = false;

  DateTime? _lastJolt;
  int _jolts = 0;
  DateTime? _downSince;

  /// Start/stop listening to match the current options and vault state.
  void update({required bool unlocked, required bool shake, required bool faceDown}) {
    _shake = shake;
    _faceDown = faceDown;
    final want = unlocked && (shake || faceDown);
    if (want && _sub == null) {
      _sub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .listen(_onEvent, onError: (_) {});
    } else if (!want && _sub != null) {
      _sub!.cancel();
      _sub = null;
      _jolts = 0;
      _downSince = null;
    }
  }

  void _onEvent(AccelerometerEvent e) {
    final now = DateTime.now();
    if (_shake) {
      // A shake = two strong jolts (> 2.6 g) within 600 ms.
      final g = sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / 9.81;
      if (g > 2.6) {
        if (_lastJolt != null &&
            now.difference(_lastJolt!) < const Duration(milliseconds: 600)) {
          _jolts++;
        } else {
          _jolts = 1;
        }
        _lastJolt = now;
        if (_jolts >= 2) {
          _jolts = 0;
          onLock();
          return;
        }
      }
    }
    if (_faceDown) {
      // Screen facing the table: gravity pulls along -z, held for 0.8 s.
      if (e.z < -8.5 && e.x.abs() < 3 && e.y.abs() < 3) {
        _downSince ??= now;
        if (now.difference(_downSince!) > const Duration(milliseconds: 800)) {
          _downSince = null;
          onLock();
        }
      } else {
        _downSince = null;
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
