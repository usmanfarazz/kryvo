import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vault_entry.dart';
import '../services/password_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'generator_screen.dart';

class AddEntryScreen extends StatefulWidget {
  final VaultEntry? existing;
  AddEntryScreen({super.key, this.existing});

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> {
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _notes;
  late String _category;
  late bool _pinned;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _password = TextEditingController(text: e?.password ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _category = e?.category ?? 'Other';
    _pinned = e?.pinned ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _username.dispose();
    _password.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _openGenerator() async {
    final pw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => GeneratorScreen()),
    );
    if (pw != null) setState(() => _password.text = pw);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please add a title.')),
      );
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = VaultEntry(
      id: widget.existing?.id ?? 'e_${now}_${_title.text.hashCode}',
      title: _title.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
      category: _category,
      notes: _notes.text.trim(),
      pinned: _pinned,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );
    await context.read<AppState>().upsertEntry(entry);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = PasswordGenerator.strength(_password.text);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add entry' : 'Edit entry'),
        actions: [
          IconButton(
              onPressed: _save,
              icon: Icon(Icons.check, color: SV.accent)),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              decoration: InputDecoration(
                  labelText: 'Title', hintText: 'e.g. Instagram'),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _username,
              decoration: InputDecoration(
                  labelText: 'Username / email / phone'),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    IconButton(
                      icon: Icon(Icons.autorenew, color: SV.accent),
                      tooltip: 'Generate',
                      onPressed: _openGenerator,
                    ),
                  ],
                ),
              ),
            ),
            if (_password.text.isNotEmpty) ...[
              SizedBox(height: 6),
              Text('Strength: ${s.label}',
                  style: TextStyle(
                      color: _strengthColor(s.score), fontSize: 12)),
            ],
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              dropdownColor: SV.panel,
              decoration: InputDecoration(labelText: 'Category'),
              // Notes live in Private Notes; keep it only for an old entry.
              items: kCategories
                  .where((c) => c != 'Notes' || c == _category)
                  .map((c) =>
                      DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'Other'),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(labelText: 'Notes (optional)'),
            ),
            SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Pin to top'),
              value: _pinned,
              activeColor: SV.accent,
              onChanged: (v) => setState(() => _pinned = v),
            ),
            SizedBox(height: 16),
            ElevatedButton(onPressed: _save, child: Text('Save')),
          ],
        ),
      ),
    );
  }

  Color _strengthColor(int score) {
    switch (score) {
      case 1:
        return SV.bad;
      case 2:
        return SV.fair;
      case 3:
        return SV.ok;
      case 4:
        return SV.ok;
      default:
        return SV.muted;
    }
  }
}
