import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../services/biometric_service.dart';
import '../services/pin_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'recover_screen.dart';

/// Unlock screen: PIN pad (if PIN lock is on) or master password, plus
/// fingerprint and "Forgot" options.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pw = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _bio = false;
  bool _usePassword = false; // switch from PIN pad to password
  String _pin = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _maybeBiometric();
  }

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _maybeBiometric() async {
    final enabled = await BiometricService.isEnabled();
    if (!mounted) return;
    setState(() => _bio = enabled);
    if (enabled) _biometricUnlock();
  }

  Future<void> _biometricUnlock() async {
    final pw = await BiometricService.unlockPassword();
    if (pw == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await context.read<AppState>().unlock(pw);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'Fingerprint unlock failed. Use your PIN or password.';
    });
  }

  Future<void> _unlockPassword() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    final app = context.read<AppState>();
    final ok = await app.unlock(_pw.text);
    if (!ok && app.status == VaultStatus.locked) {
      app.noteWrongAttempt('password');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = app.errorMessage;
    });
  }

  // Opens the vault the moment the typed password / PIN is correct, without
  // pressing Unlock. Checks run one at a time; if the text changed while a
  // check was running, the newest text is checked next.
  bool _checking = false;

  Future<void> _autoTry(String Function() current,
      Future<bool> Function(AppState app, String value) attempt) async {
    if (_checking || _busy) return;
    _checking = true;
    final app = context.read<AppState>();
    try {
      String tried;
      do {
        tried = current();
        if (await attempt(app, tried)) return;
      } while (mounted && current() != tried);
    } finally {
      _checking = false;
    }
  }

  void _autoTryPassword() =>
      _autoTry(() => _pw.text, (app, v) => app.tryQuickUnlock(v));

  // ---- PIN pad -----------------------------------------------------------------

  void _tap(String d) {
    final app = context.read<AppState>();
    if (app.vibration) HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      if (d == '<') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 8) {
        _pin += d;
      }
    });
    if (_pin.length >= 4) {
      _autoTry(() => _pin, (app, v) => app.tryQuickPin(v));
    }
  }

  Future<void> _submitPin() async {
    if (_pin.length < 4) {
      setState(() => _error = 'Enter your 4–8 digit PIN');
      return;
    }
    final app = context.read<AppState>();
    if (app.vibration) HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    final err = await app.unlockWithPin(_pin);
    if (err != null && app.status == VaultStatus.locked) {
      app.noteWrongAttempt('pin');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      _error = err;
    });
    if (err != null && app.vibration) HapticFeedback.heavyImpact();
  }

  // ---- Forgot -------------------------------------------------------------------

  Future<void> _forgot() async {
    final app = context.read<AppState>();
    final q = await PinService.question();
    if (!mounted) return;
    final pinMode = app.pinMode && !_usePassword;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: SV.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text(pinMode ? 'Forgot your PIN?' : 'Forgot your password?',
                  style: TextStyle(
                      color: SV.txt,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
            ),
            if (pinMode && q.isNotEmpty)
              ListTile(
                leading: Icon(Icons.quiz_outlined, color: SV.accent),
                title: const Text('Answer my security question'),
                subtitle: Text(q, style: TextStyle(color: SV.muted)),
                onTap: () => Navigator.pop(ctx, 'question'),
              ),
            if (pinMode)
              ListTile(
                leading: Icon(Icons.password, color: SV.accent),
                title: const Text('Use master password instead'),
                onTap: () => Navigator.pop(ctx, 'password'),
              ),
            if (app.recoveryEnabled)
              ListTile(
                leading: Icon(Icons.vpn_key_outlined, color: SV.accent),
                title: const Text('Use my recovery key'),
                subtitle: Text('Get back in and set a new password',
                    style: TextStyle(color: SV.muted)),
                onTap: () => Navigator.pop(ctx, 'recover'),
              ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: SV.bad),
              title: Text('Reset vault', style: TextStyle(color: SV.bad)),
              subtitle: Text('Erase everything and start fresh',
                  style: TextStyle(color: SV.muted)),
              onTap: () => Navigator.pop(ctx, 'reset'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'question':
        await _answerQuestion(q);
      case 'password':
        setState(() {
          _usePassword = true;
          _error = null;
        });
      case 'recover':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => RecoverScreen()));
      case 'reset':
        if (await confirm(context,
            title: 'Reset vault?',
            message:
                'This permanently erases all hidden photos, videos, audio and '
                'passwords on this phone. It cannot be undone.',
            ok: 'Erase everything',
            danger: true)) {
          if (mounted) await context.read<AppState>().resetVault();
        }
    }
  }

  Future<void> _answerQuestion(String q) async {
    final a = await promptText(context, title: q, hint: 'Your answer', ok: 'Check');
    if (a == null || !mounted) return;
    if (!await PinService.checkAnswer(a)) {
      if (mounted) setState(() => _error = 'That answer is not correct');
      return;
    }
    final mp = await PinService.storedMasterPassword();
    if (mp == null || !mounted) return;
    final p1 = await promptText(context,
        title: 'Set a new PIN',
        hint: '4 to 8 digits',
        obscure: true,
        keyboard: TextInputType.number,
        maxLength: 8,
        ok: 'Next');
    if (p1 == null || !mounted) return;
    if (!RegExp(r'^\d{4,8}$').hasMatch(p1)) {
      setState(() => _error = 'PIN must be 4 to 8 digits');
      return;
    }
    final p2 = await promptText(context,
        title: 'Confirm new PIN',
        obscure: true,
        keyboard: TextInputType.number,
        maxLength: 8,
        ok: 'Save');
    if (p2 == null || !mounted) return;
    if (p1 != p2) {
      setState(() => _error = 'PINs did not match');
      return;
    }
    final app = context.read<AppState>();
    await app.enablePin(p1, mp);
    await app.unlock(mp);
  }

  // ---- UI ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pinPad = app.pinMode && !_usePassword;
    // Behind a disguise, Back returns to the disguise app instead of closing.
    return PopScope(
      canPop: !app.disguised,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) app.hideLockScreen();
      },
      child: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset('assets/kryvo_logo.png',
                        width: 84,
                        height: 84,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.shield, size: 72, color: SV.accent)),
                  ),
                  const SizedBox(height: 14),
                  Text('Kryvo',
                      style: TextStyle(
                          color: SV.txt,
                          fontSize: 26,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(tr(pinPad ? 'Enter your PIN' : 'Enter your master password'),
                      style: TextStyle(color: SV.muted)),
                  if (pinPad && app.pinHint.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Hint: ${app.pinHint}',
                        style: TextStyle(color: SV.accent, fontSize: 13)),
                  ],
                  const SizedBox(height: 22),
                  if (pinPad) _pinPad() else _passwordCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(tr(_error!),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: SV.bad)),
                  ],
                  if (_bio) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _busy ? null : _biometricUnlock,
                      icon: Icon(Icons.fingerprint, color: SV.accent, size: 28),
                      label: Text(tr('Use fingerprint'),
                          style: TextStyle(color: SV.accent)),
                    ),
                  ],
                  if (app.pinMode && _usePassword)
                    TextButton(
                      onPressed: () => setState(() {
                        _usePassword = false;
                        _error = null;
                      }),
                      child: Text(tr('Use PIN instead'),
                          style: TextStyle(color: SV.accent)),
                    ),
                  TextButton(
                    onPressed: _busy ? null : _forgot,
                    child: Text(tr(pinPad ? 'Forgot PIN?' : 'Forgot password?'),
                        style: TextStyle(color: SV.muted)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _passwordCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _pw,
              obscureText: _obscure,
              autofocus: true,
              onChanged: (_) => _autoTryPassword(),
              onSubmitted: (_) => _unlockPassword(),
              decoration: InputDecoration(
                labelText: tr('Master password'),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy ? null : _unlockPassword,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(tr('Unlock')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinPad() {
    return Column(
      children: [
        // Dots
        SizedBox(
          height: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < (_pin.length < 4 ? 4 : _pin.length); i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? SV.accent : Colors.transparent,
                    border: Border.all(color: SV.accent, width: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['<', '0', 'ok'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [for (final k in row) _key(k)],
            ),
          ),
      ],
    );
  }

  Widget _key(String k) {
    final isOk = k == 'ok';
    final isBack = k == '<';
    return SizedBox(
      width: 76,
      height: 76,
      child: Material(
        color: isOk ? SV.accent : SV.panel,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _busy ? null : (isOk ? _submitPin : () => _tap(k)),
          child: Center(
            child: _busy && isOk
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : isOk
                    ? const Icon(Icons.check, color: Colors.white, size: 30)
                    : isBack
                        ? Icon(Icons.backspace_outlined, color: SV.txt)
                        : Text(k,
                            style: TextStyle(
                                color: SV.txt,
                                fontSize: 28,
                                fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}
