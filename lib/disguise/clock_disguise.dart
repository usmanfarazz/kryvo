import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// "Clock" disguise: a working clock, stopwatch and timer. Typing the secret
/// code (or the PIN) as the timer's time and pressing Start opens the vault.
class ClockDisguise extends StatefulWidget {
  const ClockDisguise({super.key});

  @override
  State<ClockDisguise> createState() => _ClockDisguiseState();
}

const _bg = Color(0xFF0B1220);
const _card = Color(0xFF162033);
const _accent = Color(0xFF38BDF8);
const _muted = Color(0xFF8A99B2);

class _ClockDisguiseState extends State<ClockDisguise> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(primary: _accent, surface: _card),
      ),
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: const [_ClockTab(), _StopwatchTab(), _TimerTab()],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: _card,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.access_time), label: 'Clock'),
            NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Stopwatch'),
            NavigationDestination(icon: Icon(Icons.hourglass_bottom), label: 'Timer'),
          ],
        ),
      ),
    );
  }
}

// ---- Clock --------------------------------------------------------------------

class _ClockTab extends StatefulWidget {
  const _ClockTab();

  @override
  State<_ClockTab> createState() => _ClockTabState();
}

class _ClockTabState extends State<_ClockTab> {
  late Timer _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1),
        (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
      'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    final h = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final mm = _now.minute.toString().padLeft(2, '0');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 250,
          height: 250,
          child: CustomPaint(painter: _DialPainter(_now)),
        ),
        const SizedBox(height: 36),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$h:$mm',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w300)),
            const SizedBox(width: 8),
            Text(_now.hour < 12 ? 'AM' : 'PM',
                style: const TextStyle(color: _muted, fontSize: 22)),
          ],
        ),
        Text(
            '${days[_now.weekday - 1]}, ${_now.day} ${months[_now.month - 1]}',
            style: const TextStyle(color: _muted, fontSize: 16)),
      ],
    );
  }
}

class _DialPainter extends CustomPainter {
  final DateTime t;
  _DialPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = _card);
    final tick = Paint()
      ..color = _muted
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final a = i * math.pi / 30;
      final big = i % 5 == 0;
      tick.strokeWidth = big ? 3 : 1;
      final r1 = r - (big ? 18 : 10);
      canvas.drawLine(c + Offset(math.sin(a), -math.cos(a)) * r1,
          c + Offset(math.sin(a), -math.cos(a)) * (r - 6), tick);
    }
    void hand(double turns, double len, double w, Color col) {
      final a = turns * 2 * math.pi;
      canvas.drawLine(
          c,
          c + Offset(math.sin(a), -math.cos(a)) * len,
          Paint()
            ..color = col
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round);
    }

    hand((t.hour % 12 + t.minute / 60) / 12, r * 0.5, 6, Colors.white);
    hand((t.minute + t.second / 60) / 60, r * 0.72, 4, Colors.white);
    hand(t.second / 60, r * 0.8, 2, _accent);
    canvas.drawCircle(c, 6, Paint()..color = _accent);
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.t != t;
}

// ---- Stopwatch -----------------------------------------------------------------

class _StopwatchTab extends StatefulWidget {
  const _StopwatchTab();

  @override
  State<_StopwatchTab> createState() => _StopwatchTabState();
}

class _StopwatchTabState extends State<_StopwatchTab> {
  final _sw = Stopwatch();
  final _laps = <Duration>[];
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _startStop() {
    setState(() {
      if (_sw.isRunning) {
        _sw.stop();
        _tick?.cancel();
      } else {
        _sw.start();
        _tick = Timer.periodic(
            const Duration(milliseconds: 30), (_) => setState(() {}));
      }
    });
  }

  void _lapReset() {
    setState(() {
      if (_sw.isRunning) {
        _laps.insert(0, _sw.elapsed);
      } else {
        _sw.reset();
        _laps.clear();
      }
    });
  }

  static String fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final cs = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$m:$s.$cs';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 70),
        Text(fmt(_sw.elapsed),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 62,
                fontWeight: FontWeight.w300,
                fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _round(_sw.isRunning ? 'Lap' : 'Reset', _card, _lapReset),
            _round(_sw.isRunning ? 'Stop' : 'Start',
                _sw.isRunning ? const Color(0xFFEF4444) : _accent, _startStop),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.builder(
            itemCount: _laps.length,
            itemBuilder: (_, i) => ListTile(
              title: Text('Lap ${_laps.length - i}',
                  style: const TextStyle(color: _muted)),
              trailing: Text(fmt(_laps[i]),
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ),
        ),
      ],
    );
  }
}

Widget _round(String label, Color color, VoidCallback onTap) => SizedBox(
      width: 96,
      height: 96,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600))),
        ),
      ),
    );

// ---- Timer -------------------------------------------------------------------------

class _TimerTab extends StatefulWidget {
  const _TimerTab();

  @override
  State<_TimerTab> createState() => _TimerTabState();
}

class _TimerTabState extends State<_TimerTab> {
  String _digits = ''; // typed like a microwave: up to HHMMSS
  Duration? _left;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Duration get _typed {
    final d = _digits.padLeft(6, '0');
    return Duration(
        hours: int.parse(d.substring(0, 2)),
        minutes: int.parse(d.substring(2, 4)),
        seconds: int.parse(d.substring(4, 6)));
  }

  void _key(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '⌫') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        }
      } else if (_digits.length < 8 && !(_digits.isEmpty && k == '0')) {
        _digits += k;
      }
    });
  }

  Future<void> _start() async {
    final entry = _digits;
    if (entry.length >= 4 &&
        await context.read<AppState>().tryDisguiseCode(entry)) {
      if (mounted) setState(() => _digits = '');
      return;
    }
    if (!mounted) return;
    // Real timers use at most 6 digits (HH MM SS).
    if (_digits.length > 6) _digits = _digits.substring(_digits.length - 6);
    final d = _typed;
    if (d == Duration.zero) return;
    setState(() => _left = d);
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _left! - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        _t?.cancel();
        setState(() => _left = null);
        HapticFeedback.heavyImpact();
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Time's up"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      } else {
        setState(() => _left = left);
      }
    });
  }

  void _cancel() {
    _t?.cancel();
    setState(() {
      _left = null;
      _digits = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_left != null) {
      final l = _left!;
      final txt =
          '${l.inHours.toString().padLeft(2, '0')}:${(l.inMinutes % 60).toString().padLeft(2, '0')}:${(l.inSeconds % 60).toString().padLeft(2, '0')}';
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(txt,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w300)),
          const SizedBox(height: 40),
          _round('Cancel', const Color(0xFFEF4444), _cancel),
        ],
      );
    }
    final d = _digits.padLeft(6, '0').substring(
        _digits.length > 6 ? _digits.length - 6 : 0);
    TextSpan part(String v, String unit) => TextSpan(children: [
          TextSpan(
              text: v,
              style: TextStyle(
                  color: _digits.isEmpty ? _muted : Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w300)),
          TextSpan(
              text: '$unit ',
              style: const TextStyle(color: _muted, fontSize: 20)),
        ]);
    return Column(
      children: [
        const SizedBox(height: 40),
        Text.rich(TextSpan(children: [
          part(d.substring(0, 2), 'h'),
          part(d.substring(2, 4), 'm'),
          part(d.substring(4, 6), 's'),
        ])),
        const Spacer(),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '⌫'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final k in row)
                  SizedBox(
                    width: 72,
                    height: 60,
                    child: k.isEmpty
                        ? null
                        : TextButton(
                            onPressed: () => _key(k),
                            child: k == '⌫'
                                ? const Icon(Icons.backspace_outlined,
                                    color: Colors.white)
                                : Text(k,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 28)),
                          ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        _round('Start', _accent, _start),
        const SizedBox(height: 20),
      ],
    );
  }
}
