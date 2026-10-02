import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// "Games" disguise: a playable Tic-Tac-Toe against the phone. The secret code
/// (or the PIN) entered under gear → "Redeem code" opens the vault.
class GameDisguise extends StatefulWidget {
  const GameDisguise({super.key});

  @override
  State<GameDisguise> createState() => _GameDisguiseState();
}

class _GameDisguiseState extends State<GameDisguise> {
  static const _bgA = Color(0xFF4C1D95);
  static const _bgB = Color(0xFF831843);
  static const _x = Color(0xFF22D3EE);
  static const _o = Color(0xFFFBBF24);

  final _rng = Random();
  List<String> _b = List.filled(9, '');
  int _you = 0, _cpu = 0, _draws = 0;
  String? _msg;
  List<int>? _line;

  static const _wins = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
  ];

  List<int>? _winner(List<String> b, String p) {
    for (final w in _wins) {
      if (w.every((i) => b[i] == p)) return w;
    }
    return null;
  }

  void _tap(int i) {
    if (_b[i].isNotEmpty || _msg != null) return;
    HapticFeedback.selectionClick();
    setState(() => _b[i] = 'X');
    if (_check()) return;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || _msg != null) return;
      setState(() => _b[_cpuMove()] = 'O');
      _check();
    });
  }

  int _cpuMove() {
    final free = [for (var i = 0; i < 9; i++) if (_b[i].isEmpty) i];
    // Win if possible, otherwise block, otherwise centre/corner/random.
    for (final p in ['O', 'X']) {
      for (final i in free) {
        final t = List.of(_b)..[i] = p;
        if (_winner(t, p) != null) return i;
      }
    }
    if (_b[4].isEmpty && _rng.nextBool()) return 4;
    final corners = [0, 2, 6, 8].where(free.contains).toList();
    if (corners.isNotEmpty && _rng.nextInt(3) > 0) {
      return corners[_rng.nextInt(corners.length)];
    }
    return free[_rng.nextInt(free.length)];
  }

  bool _check() {
    final x = _winner(_b, 'X'), o = _winner(_b, 'O');
    if (x != null || o != null || !_b.contains('')) {
      setState(() {
        _line = x ?? o;
        if (x != null) {
          _you++;
          _msg = 'You win! 🎉';
        } else if (o != null) {
          _cpu++;
          _msg = 'Phone wins';
        } else {
          _draws++;
          _msg = "It's a draw";
        }
      });
      return true;
    }
    return false;
  }

  void _reset() => setState(() {
        _b = List.filled(9, '');
        _msg = null;
        _line = null;
      });

  Future<void> _settings() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Reset scores'),
              onTap: () => Navigator.pop(ctx, 'reset'),
            ),
            ListTile(
              leading: const Icon(Icons.card_giftcard),
              title: const Text('Redeem code'),
              onTap: () => Navigator.pop(ctx, 'code'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'reset') {
      setState(() => _you = _cpu = _draws = 0);
      _reset();
    } else if (choice == 'code') {
      final code = await askDisguiseCode(context, 'Redeem code', 'Enter code');
      if (code == null || !mounted) return;
      if (!await context.read<AppState>().tryDisguiseCode(code) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This code is not valid')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_bgA, _bgB]),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 20),
                    const Expanded(
                      child: Text('Tic Tac Toe',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                        onPressed: _settings,
                        icon: const Icon(Icons.settings, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _score('You (X)', _you, _x),
                    _score('Draw', _draws, Colors.white70),
                    _score('Phone (O)', _cpu, _o),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: GridView.count(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (var i = 0; i < 9; i++)
                          GestureDetector(
                            onTap: () => _tap(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: (_line?.contains(i) ?? false)
                                    ? Colors.white24
                                    : Colors.white10,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Center(
                                child: Text(_b[i],
                                    style: TextStyle(
                                        fontSize: 58,
                                        fontWeight: FontWeight.w900,
                                        color: _b[i] == 'X' ? _x : _o)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: Text(_msg ?? 'Your turn',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _bgA,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14)),
                    onPressed: _reset,
                    icon: const Icon(Icons.replay),
                    label: const Text('New game',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _score(String label, int n, Color c) => Column(
        children: [
          Text('$n',
              style: TextStyle(
                  color: c, fontSize: 30, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      );
}

/// Small numeric code prompt shared by the Game and Flashlight disguises.
Future<String?> askDisguiseCode(BuildContext context, String title, String hint) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        obscureText: true,
        maxLength: 8,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('OK')),
      ],
    ),
  );
}
