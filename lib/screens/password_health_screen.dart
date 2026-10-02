import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vault_entry.dart';
import '../services/password_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'add_entry_screen.dart';

/// Password health: weak, reused and old passwords. Everything is checked on
/// the phone — no password is ever sent anywhere.
class PasswordHealth {
  final List<VaultEntry> weak, reused, old;
  PasswordHealth(this.weak, this.reused, this.old);

  int get issues => {...weak, ...reused, ...old}.length;

  factory PasswordHealth.of(List<VaultEntry> entries) {
    final list =
        entries.where((e) => e.category != 'Notes' && e.password.isNotEmpty);
    final count = <String, int>{};
    for (final e in list) {
      count[e.password] = (count[e.password] ?? 0) + 1;
    }
    final yearAgo = DateTime.now()
        .subtract(const Duration(days: 365))
        .millisecondsSinceEpoch;
    return PasswordHealth(
      list.where((e) => PasswordGenerator.strength(e.password).score <= 1).toList(),
      list.where((e) => count[e.password]! > 1).toList(),
      list.where((e) => e.updatedAt > 0 && e.updatedAt < yearAgo).toList(),
    );
  }
}

class PasswordHealthScreen extends StatelessWidget {
  const PasswordHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final h = PasswordHealth.of(app.entries);
    final total = app.entries
        .where((e) => e.category != 'Notes' && e.password.isNotEmpty)
        .length;
    final score = total == 0 ? 100 : (100 * (total - h.issues) / total).round();
    final color = score >= 80
        ? SV.ok
        : score >= 50
            ? SV.warn
            : SV.bad;

    Widget section(String title, String why, IconData icon, Color c,
            List<VaultEntry> items) =>
        items.isEmpty
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader('$title (${items.length})'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                    child: Text(why,
                        style: TextStyle(color: SV.muted, fontSize: 12)),
                  ),
                  for (final e in items)
                    ListTile(
                      leading: Icon(icon, color: c),
                      title: Text(e.title.isEmpty ? 'Untitled' : e.title),
                      subtitle: Text(e.username,
                          style: TextStyle(color: SV.muted)),
                      trailing: Icon(Icons.chevron_right, color: SV.muted),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => AddEntryScreen(existing: e))),
                    ),
                ],
              );

    return Scaffold(
      appBar: AppBar(title: const Text('Password health')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    SizedBox(
                      width: 76,
                      height: 76,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: score / 100,
                            strokeWidth: 8,
                            color: color,
                            backgroundColor: SV.panel2,
                          ),
                          Center(
                            child: Text('$score',
                                style: TextStyle(
                                    color: SV.txt,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(
                          total == 0
                              ? 'No passwords saved yet.'
                              : h.issues == 0
                                  ? 'All $total passwords look good ✔'
                                  : '${h.issues} of $total passwords need attention. '
                                      'Tap one to change it.',
                          style: TextStyle(color: SV.txt)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          section('WEAK', 'Easy to guess. Use the generator for a long random one.',
              Icons.warning_amber_rounded, SV.bad, h.weak),
          section(
              'REUSED',
              'The same password on several accounts: if one leaks, all are at risk.',
              Icons.copy_all_rounded,
              SV.warn,
              h.reused),
          section('OLD', 'Not changed for over a year.', Icons.history,
              SV.muted, h.old),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Checked on this phone only — nothing is sent anywhere.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SV.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
