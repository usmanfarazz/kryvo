import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/disguise_service.dart';
import '../state/app_state.dart';
import 'game_disguise.dart' show askDisguiseCode;

/// "Flashlight" disguise: a working torch (camera flash), an SOS blinker and a
/// white "screen light". The secret code (or the PIN) entered under
/// gear → "Calibration code" opens the vault.
class FlashlightDisguise extends StatefulWidget {
  const FlashlightDisguise({super.key});

  @override
  State<FlashlightDisguise> createState() => _FlashlightDisguiseState();
}

class _FlashlightDisguiseState extends State<FlashlightDisguise> {
  bool _on = false;
  bool _sos = false;
  bool _screen = false;
  bool _hasTorch = true;
  Timer? _sosTimer;

  @override
  void initState() {
    super.initState();
    DisguiseService.hasTorch().then((v) {
      if (mounted) setState(() => _hasTorch = v);
    });
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    DisguiseService.torch(false);
    super.dispose();
  }

  Future<void> _toggle() async {
    HapticFeedback.mediumImpact();
    _stopSos();
    final want = !_on;
    final ok = _hasTorch && await DisguiseService.torch(want);
    if (!mounted) return;
    setState(() {
      _on = want;
      if (!ok && want) _screen = true; // no flash: fall back to screen light
      if (!want) _screen = false;
    });
  }

  void _stopSos() {
    _sosTimer?.cancel();
    _sosTimer = null;
    if (_sos) {
      _sos = false;
      DisguiseService.torch(false);
    }
  }

  void _toggleSos() {
    if (_sos) {
      setState(_stopSos);
      return;
    }
    // ... --- ... in 200 ms units: 1 = on, 0 = off
    const pattern = '1010100011101110111000101010000000';
    var i = 0;
    setState(() {
      _sos = true;
      _on = false;
    });
    _sosTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      DisguiseService.torch(pattern[i % pattern.length] == '1');
      i++;
    });
  }

  Future<void> _settings() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('Screen light'),
              subtitle: const Text('Use a white screen as a soft light'),
              onTap: () => Navigator.pop(ctx, 'screen'),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Calibration code'),
              onTap: () => Navigator.pop(ctx, 'code'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'screen') {
      setState(() => _screen = true);
    } else if (choice == 'code') {
      final code =
          await askDisguiseCode(context, 'Calibration code', 'Enter code');
      if (code == null || !mounted) return;
      if (!await context.read<AppState>().tryDisguiseCode(code) && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Invalid code')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_screen) {
      return GestureDetector(
        onTap: () => setState(() {
          _screen = false;
          _on = false;
        }),
        child: const Scaffold(
          backgroundColor: Colors.white,
          body: Center(
              child: Text('Tap to turn off',
                  style: TextStyle(color: Colors.black26))),
        ),
      );
    }
    final lit = _on || _sos;
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F19),
        body: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 20),
                  const Expanded(
                    child: Text('Flashlight',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                      onPressed: _settings,
                      icon: const Icon(Icons.settings, color: Colors.white70)),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTap: _toggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: lit ? const Color(0xFFFDE047) : const Color(0xFF1F2937),
                    boxShadow: lit
                        ? const [
                            BoxShadow(
                                color: Color(0x99FDE047),
                                blurRadius: 80,
                                spreadRadius: 10)
                          ]
                        : const [],
                  ),
                  child: Icon(Icons.power_settings_new,
                      size: 90,
                      color: lit ? const Color(0xFF0B0F19) : Colors.white54),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                  !_hasTorch
                      ? 'No flash on this phone — using screen light'
                      : _sos
                          ? 'SOS'
                          : (_on ? 'ON' : 'OFF'),
                  style: const TextStyle(color: Colors.white70, fontSize: 18)),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: OutlinedButton.icon(
                  onPressed: _hasTorch ? _toggleSos : null,
                  icon: const Icon(Icons.sos),
                  label: Text(_sos ? 'Stop SOS' : 'SOS signal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
