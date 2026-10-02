import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/vault_entry.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'add_entry_screen.dart';
import 'password_health_screen.dart';
import 'settings_screen.dart';

class VaultScreen extends StatefulWidget {
  VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  String _category = 'All';
  String _query = '';

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    context.read<AppState>().registerActivity();
    // Auto-clear the clipboard after 30 seconds (matches the web app).
    Timer(Duration(seconds: 30), () async {
      final data = await Clipboard.getData('text/plain');
      if (data?.text == value) {
        await Clipboard.setData(ClipboardData(text: ''));
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied · clears in 30s')),
    );
  }

  Future<void> _add({VaultEntry? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddEntryScreen(existing: existing)),
    );
  }

  Future<void> _export() async {
    final app = context.read<AppState>();
    final err = await withProgress(context, 'Preparing backup…',
        (update) => app.createFullBackup(onProgress: update));
    if (mounted) snack(context, err ?? 'Encrypted backup saved ✔');
  }

  Future<void> _confirmDelete(VaultEntry e) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SV.panel,
        title: Text('Delete entry?'),
        content: Text('“${e.title}” will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: SV.bad)),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await context.read<AppState>().deleteEntry(e.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = app
        .view(category: _category, query: _query)
        .where((e) => e.category != 'Notes')
        .toList();
    // Notes have their own screen (Private Notes).
    final chips = ['All', ...kCategories.where((c) => c != 'Notes')];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => context.read<AppState>().registerActivity(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Passwords'),
          actions: [
            PopupMenuButton<String>(
              color: SV.panel,
              onSelected: (v) {
                if (v == 'settings') {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SettingsScreen()));
                }
                if (v == 'lock') app.lock(force: true);
                if (v == 'export') _export();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'settings', child: Text('Settings')),
                // Not in the fake vault: a backup would contain everything.
                if (!app.decoy)
                  PopupMenuItem(value: 'export', child: Text('Export backup')),
                PopupMenuItem(value: 'lock', child: Text('Lock now')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // Password health banner (weak / reused / old passwords).
            Builder(builder: (context) {
              final issues = PasswordHealth.of(app.entries).issues;
              if (issues == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Material(
                  color: SV.warn.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.health_and_safety_outlined, color: SV.warn),
                    title: Text(
                        '$issues password${issues == 1 ? ' needs' : 's need'} attention'),
                    trailing: Icon(Icons.chevron_right, color: SV.muted),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const PasswordHealthScreen())),
                  ),
                ),
              );
            }),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: Icon(Icons.search, color: SV.muted),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 16),
                itemCount: chips.length,
                separatorBuilder: (_, __) => SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final c = chips[i];
                  final active = c == _category;
                  return ChoiceChip(
                    label: Text(c),
                    selected: active,
                    backgroundColor: SV.panel,
                    selectedColor: SV.accent,
                    labelStyle: TextStyle(
                        color: active ? Colors.white : SV.muted),
                    onSelected: (_) => setState(() => _category = c),
                  );
                },
              ),
            ),
            SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('No entries yet. Tap + to add one.',
                          style: TextStyle(color: SV.muted)),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 96),
                      itemCount: items.length,
                      itemBuilder: (_, i) =>
                          _EntryCard(entry: items[i], parent: this),
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: SV.accent,
          onPressed: () => _add(),
          icon: Icon(Icons.add),
          label: Text('Add'),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final VaultEntry entry;
  final _VaultScreenState parent;
  _EntryCard({required this.entry, required this.parent});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: SV.panel2,
          child: Text(entry.title.isEmpty ? '?' : entry.title[0].toUpperCase(),
              style: TextStyle(color: SV.accent)),
        ),
        title: Row(
          children: [
            Flexible(child: Text(entry.title)),
            if (entry.pinned)
              Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.push_pin, size: 14, color: SV.warn),
              ),
          ],
        ),
        subtitle: Text(
          [entry.username, entry.category].where((s) => s.isNotEmpty).join(' · '),
          style: TextStyle(color: SV.muted),
        ),
        trailing: PopupMenuButton<String>(
          color: SV.panel,
          onSelected: (v) {
            switch (v) {
              case 'copyPw':
                parent._copy('Password', entry.password);
                break;
              case 'copyUser':
                parent._copy('Username', entry.username);
                break;
              case 'pin':
                context.read<AppState>().togglePin(entry.id);
                break;
              case 'edit':
                parent._add(existing: entry);
                break;
              case 'delete':
                parent._confirmDelete(entry);
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'copyPw', child: Text('Copy password')),
            if (entry.username.isNotEmpty)
              PopupMenuItem(
                  value: 'copyUser', child: Text('Copy username')),
            PopupMenuItem(
                value: 'pin',
                child: Text(entry.pinned ? 'Unpin' : 'Pin to top')),
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: SV.bad))),
          ],
        ),
        onTap: () => parent._copy('Password', entry.password),
      ),
    );
  }
}

