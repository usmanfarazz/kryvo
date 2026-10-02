import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vault_entry.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Private notes. They are stored inside the encrypted password vault (as
/// entries of the "Notes" category), so they are protected by the master
/// password exactly like passwords.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String _query = '';

  Future<void> _edit([VaultEntry? note]) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _NoteEditor(note: note)));
  }

  static String _titleOf(VaultEntry n) {
    if (n.title.isNotEmpty) return n.title;
    final first = n.notes.trim().split('\n').first.trim();
    return first.isEmpty ? 'Untitled' : first;
  }

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final notes = app.view(category: 'Notes', query: _query);
    return Scaffold(
      appBar: AppBar(title: const Text('Private Notes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.edit),
        label: const Text('New note'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Search notes'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: notes.isEmpty
                ? const EmptyState(
                    icon: Icons.sticky_note_2_outlined,
                    title: 'No notes yet',
                    subtitle:
                        'Write private things here — they are encrypted with '
                        'your master password.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: notes.length,
                    itemBuilder: (_, i) {
                      final n = notes[i];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                              n.pinned ? Icons.push_pin : Icons.sticky_note_2,
                              color: SV.accent),
                          // No title: show the note's first line instead.
                          title: Text(_titleOf(n),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${_date(n.updatedAt)} · ${n.notes.replaceAll('\n', ' ')}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: SV.muted)),
                          onTap: () => _edit(n),
                          onLongPress: () => app.togglePin(n.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoteEditor extends StatefulWidget {
  final VaultEntry? note;
  const _NoteEditor({this.note});

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = TextEditingController(text: widget.note?.notes ?? '');

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim(), body = _body.text;
    if (title.isEmpty && body.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final n = widget.note ??
        VaultEntry(
            id: 'n_$now', title: '', category: 'Notes', createdAt: now, updatedAt: now);
    n
      ..title = title
      ..notes = body
      ..category = 'Notes';
    await context.read<AppState>().upsertEntry(n);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context,
        title: 'Delete this note?',
        message: 'It cannot be recovered.',
        ok: 'Delete',
        danger: true)) {
      return;
    }
    if (!mounted) return;
    await context.read<AppState>().deleteEntry(widget.note!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            if (widget.note != null)
              IconButton(
                  tooltip: 'Delete',
                  onPressed: _delete,
                  icon: Icon(Icons.delete_outline, color: SV.bad)),
            IconButton(
                tooltip: 'Save', onPressed: _save, icon: const Icon(Icons.check)),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              TextField(
                controller: _title,
                style: TextStyle(
                    color: SV.txt, fontSize: 22, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                    hintText: 'Title', border: InputBorder.none),
              ),
              Expanded(
                child: TextField(
                  controller: _body,
                  autofocus: widget.note == null,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(color: SV.txt, fontSize: 16),
                  decoration: const InputDecoration(
                      hintText: 'Write your note…', border: InputBorder.none),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
