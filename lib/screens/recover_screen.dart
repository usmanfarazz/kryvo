import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';

/// Recover the vault with a recovery key, then set a new master password.
/// Reached from the lock screen's "Forgot password?" flow.
class RecoverScreen extends StatefulWidget {
  RecoverScreen({super.key});

  @override
  State<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends State<RecoverScreen> {
  final _keyCtrl = TextEditingController();
  final _newPw = TextEditingController();
  final _confirm = TextEditingController();

  bool _verified = false; // recovery key accepted, now set a new password
  bool _busy = false;
  bool _obscure = true;
  String? _recoveredPw;
  String? _error;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _newPw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _checkKey() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    final mp = await context.read<AppState>().recoverWithKey(_keyCtrl.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (mp == null) {
      setState(() => _error = 'That recovery key did not work. Check for typos.');
      return;
    }
    // Vault is now unlocked and its entries are loaded in memory. We keep it
    // unlocked so that changeMasterPassword re-encrypts the REAL entries (not
    // an empty vault) when the user sets their new password below.
    setState(() {
      _recoveredPw = mp;
      _verified = true;
    });
  }

  Future<void> _setNewPassword() async {
    setState(() => _error = null);
    if (_newPw.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (_newPw.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() => _busy = true);
    final err = await context
        .read<AppState>()
        .changeMasterPassword(_recoveredPw!, _newPw.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final app = context.read<AppState>();
    // Keep the SAME recovery key working for next time by re-wrapping the new
    // password under it. (changeMasterPassword turned recovery off because the
    // stored copy was for the old password.) The user's saved entries are
    // untouched — only the master password changed.
    await app.setRecoveryWithKey(_newPw.text, _keyCtrl.text);
    // Unlock with the new password so we reliably land in the vault, even if an
    // auto-lock happened while the user was typing.
    await app.unlock(_newPw.text);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New password set — your data is safe ✔')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recover vault')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _verified ? _newPasswordCard() : _keyCard(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter your recovery key',
            style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          'This is the key you saved when you set up recovery. '
          'Dashes and capitalization do not matter.',
          style: TextStyle(color: SV.muted),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _keyCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Recovery key',
                    hintText: 'XXXX-XXXX-XXXX-XXXX-…',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: SV.bad)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _busy ? null : _checkKey,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _newPasswordCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Set a new master password',
            style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Your recovery key worked. Choose a new master password.',
            style: TextStyle(color: SV.muted)),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _newPw,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'New master password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: _obscure,
                  decoration:
                      const InputDecoration(labelText: 'Confirm new password'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: SV.bad)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _busy ? null : _setNewPassword,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save & unlock'),
                ),
                const SizedBox(height: 10),
                Text(
                  'All your saved passwords stay exactly as they were — only '
                  'the master password changes. Your recovery key keeps '
                  'working for next time.',
                  style: TextStyle(color: SV.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
