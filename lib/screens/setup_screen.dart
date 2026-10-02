import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';

class SetupScreen extends StatefulWidget {
  SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _error = null);
    if (_pw.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (_pw.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() => _busy = true);
    final ok = await context.read<AppState>().createVault(_pw.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) setState(() => _error = context.read<AppState>().errorMessage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Logo(),
                  SizedBox(height: 14),
                  Text('Kryvo',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('Create a master password to protect your vault',
                      style: TextStyle(color: SV.muted)),
                  SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _pw,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Create master password',
                              suffixIcon: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility
                                    : Icons.visibility_off),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          SizedBox(height: 12),
                          TextField(
                            controller: _confirm,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                                labelText: 'Confirm master password',
                                hintText: 'Type it again'),
                          ),
                          if (_error != null) ...[
                            SizedBox(height: 10),
                            Text(_error!,
                                style: TextStyle(color: SV.bad)),
                          ],
                          SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _busy ? null : _create,
                            child: _busy
                                ? SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Text('Create vault'),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Your vault is encrypted with this password — it is '
                            'never stored anywhere. After setup, add a recovery '
                            'key in Settings so you are never permanently locked '
                            'out if you forget it.',
                            style:
                                TextStyle(color: SV.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 14),
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SV.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SV.line),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.shield_outlined,
                            color: SV.accent, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '100% offline. Everything is encrypted and stored '
                            'only on this device. No password ever leaves this '
                            'app or reaches any server.',
                            style: TextStyle(color: SV.muted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  _Logo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [SV.accent, Color.lerp(SV.accent, Colors.black, 0.35)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset('assets/kryvo_logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.lock, color: Colors.white, size: 30)),
    );
  }
}
