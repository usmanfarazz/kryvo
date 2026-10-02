import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/password_generator.dart';
import '../theme.dart';

/// Password generator. Pushed as a screen; pops with the chosen password
/// string when the user taps "Use this password", or null if cancelled.
class GeneratorScreen extends StatefulWidget {
  GeneratorScreen({super.key});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  double _length = 16;
  bool _numbers = true;
  bool _symbols = true;
  String _password = '';

  @override
  void initState() {
    super.initState();
    _regen();
  }

  void _regen() {
    setState(() {
      _password = PasswordGenerator.generate(
        length: _length.round(),
        numbers: _numbers,
        symbols: _symbols,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = PasswordGenerator.strength(_password);
    return Scaffold(
      appBar: AppBar(title: Text('Password generator')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _password,
                        style: TextStyle(
                            fontFamily: 'monospace', fontSize: 18),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy, color: SV.accent),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _password));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Copied')),
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh, color: SV.accent),
                      onPressed: _regen,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 8),
            Text('${s.label}  ·  ${_length.round()} chars',
                style: TextStyle(color: SV.muted)),
            SizedBox(height: 16),
            Text('Length: ${_length.round()}'),
            Slider(
              value: _length,
              min: 6,
              max: 40,
              divisions: 34,
              activeColor: SV.accent,
              onChanged: (v) => setState(() => _length = v),
              onChangeEnd: (_) => _regen(),
            ),
            SwitchListTile(
              title: Text('Numbers'),
              value: _numbers,
              activeColor: SV.accent,
              onChanged: (v) {
                setState(() => _numbers = v);
                _regen();
              },
            ),
            SwitchListTile(
              title: Text('Symbols'),
              value: _symbols,
              activeColor: SV.accent,
              onChanged: (v) {
                setState(() => _symbols = v);
                _regen();
              },
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(_password),
              child: Text('Use this password'),
            ),
          ],
        ),
      ),
    );
  }
}
