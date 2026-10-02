import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/secure_store.dart';
import '../state/app_state.dart';

/// "Notes" disguise: a real, simple notes app. Saving a note that contains
/// only the secret code (or the PIN) opens the vault instead of saving it.
class NotesDisguise extends StatefulWidget {
  const NotesDisguise({super.key});

  @override
  State<NotesDisguise> createState() => _NotesDisguiseState();
}

class _Note {
  final String text;
  final int at;
  _Note(this.text, this.at);
  Map<String, dynamic> toJson() => {'t': text, 'at': at};
  factory _Note.fromJson(Map<String, dynamic> j) =>
      _Note(j['t'] as String? ?? '', j['at'] as int? ?? 0);
}

class _NotesDisguiseState extends State<NotesDisguise> {
  static const _key = 'kryvo.disguise.notes';
  static const _bg = Color(0xFFFFFBEB);
  static const _ink = Color(0xFF1F2937);
  static const _accent = Color(0xFFF59E0B);

  List<_Note> _notes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SecureStore.instance.read(key: _key);
    if (s == null || !mounted) return;
    setState(() => _notes = (jsonDecode(s) as List)
        .map((e) => _Note.fromJson(e as Map<String, dynamic>))
        .toList());
  }

  Future<void> _save() => SecureStore.instance
      .write(key: _key, value: jsonEncode(_notes.map((n) => n.toJson()).toList()));

  Future<void> _open([int? index]) async {
    final text = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) =>
            _NoteEditor(initial: index == null ? '' : _notes[index].text)));
    if (text == null || !mounted) return;
    final t = text.trim();
    if (index == null && t.isNotEmpty) {
      if (await context.read<AppState>().tryDisguiseCode(t)) return;
    }
    if (!mounted) return;
    setState(() {
      if (t.isEmpty) {
        if (index != null) _notes.removeAt(index);
      } else if (index == null) {
        _notes.insert(0, _Note(text, DateTime.now().millisecondsSinceEpoch));
      } else {
        _notes[index] = _Note(text, DateTime.now().millisecondsSinceEpoch);
      }
    });
    await _save();
  }

  Future<void> _delete(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _notes.removeAt(i));
    await _save();
  }

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: _accent)),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          title: const Text('Notes',
              style: TextStyle(
                  color: _ink, fontWeight: FontWeight.w800, fontSize: 26)),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          onPressed: () => _open(),
          child: const Icon(Icons.edit),
        ),
        body: _notes.isEmpty
            ? const Center(
                child: Text('No notes yet.\nTap ✎ to write one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 16)))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                itemCount: _notes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final n = _notes[i];
                  final lines = n.text.trim().split('\n');
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _open(i),
                      onLongPress: () => _delete(i),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(lines.first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: _ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16)),
                            if (lines.length > 1) ...[
                              const SizedBox(height: 4),
                              Text(lines.skip(1).join(' '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Color(0xFF6B7280))),
                            ],
                            const SizedBox(height: 6),
                            Text(_date(n.at),
                                style: const TextStyle(
                                    color: Color(0xFF9CA3AF), fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _NoteEditor extends StatefulWidget {
  final String initial;
  const _NoteEditor({required this.initial});

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_c.text);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFBEB),
        appBar: AppBar(
          backgroundColor: const Color(0xFFFFFBEB),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () => Navigator.of(context).pop(_c.text),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: TextField(
            controller: _c,
            autofocus: widget.initial.isEmpty,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 17, color: Color(0xFF1F2937)),
            decoration: const InputDecoration(
              hintText: 'Start writing…',
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }
}
