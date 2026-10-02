import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_thumb.dart';
import 'media_import.dart';
import 'photo_viewer.dart';
import 'video_player_screen.dart';

/// The contents of one folder of one category. Tap to open, long-press to
/// select; selected items can be unhidden, moved or sent to the Recycle Bin.
class FolderScreen extends StatefulWidget {
  final String cat;
  final String folder;
  const FolderScreen({super.key, required this.cat, required this.folder});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  final Set<String> _sel = {};
  String? _busy;
  String _sort = 'newest'; // newest | oldest | name | size
  bool _favOnly = false;
  bool _searching = false;
  String _query = '';

  bool get _selecting => _sel.isNotEmpty;

  void _toggle(MediaItem m) =>
      setState(() => _sel.contains(m.id) ? _sel.remove(m.id) : _sel.add(m.id));

  static const _sorts = {
    'newest': 'Newest first',
    'oldest': 'Oldest first',
    'name': 'Name (A–Z)',
    'size': 'Largest first',
  };

  List<MediaItem> _items(AppState app) {
    final q = _query.trim().toLowerCase();
    final l = app
        .itemsOf(widget.cat, folder: widget.folder)
        .where((m) =>
            (!_favOnly || m.fav) &&
            (q.isEmpty || m.name.toLowerCase().contains(q)))
        .toList();
    l.sort((a, b) {
      switch (_sort) {
        case 'oldest':
          return a.addedAt.compareTo(b.addedAt);
        case 'name':
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'size':
          return b.sizeBytes.compareTo(a.sizeBytes);
        default:
          return b.addedAt.compareTo(a.addedAt);
      }
    });
    return l;
  }

  Future<void> _favSel(AppState app) async {
    final list = _selected(app);
    // If all are favourites already, the button removes them; else adds.
    final add = !list.every((m) => m.fav);
    await app.setFavorite(list, add);
    if (!mounted) return;
    setState(() => _sel.clear());
    snack(context,
        add ? '${list.length} added to favourites ⭐' : 'Removed from favourites');
  }

  void _open(List<MediaItem> items, int i) {
    final m = items[i];
    if (m.isImage) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PhotoViewer(
              items: items.where((x) => x.isImage).toList(),
              initialIndex:
                  items.where((x) => x.isImage).toList().indexOf(m))));
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(item: m)));
    }
  }

  Future<void> _add() async {
    final msg = await importMedia(context,
        cat: widget.cat,
        folder: widget.folder,
        setBusy: (t) {
          if (mounted) setState(() => _busy = t);
        });
    if (msg != null && mounted) snack(context, msg);
  }

  List<MediaItem> _selected(AppState app) =>
      _items(app).where((m) => _sel.contains(m.id)).toList();

  Future<void> _unhideSel(AppState app) async {
    final list = _selected(app);
    if (!await confirm(context,
        title: 'Unhide ${list.length} item${list.length == 1 ? '' : 's'}?',
        message: 'They go back to your phone (photos → Pictures/Kryvo, '
            'videos → Movies/Kryvo, audio → Music/Kryvo) and are removed '
            'from the vault.',
        ok: 'Unhide')) {
      return;
    }
    setState(() => _busy = 'Moving back to your phone…');
    final n = await app.unhide(list,
        onProgress: (d, t) {
          if (mounted) setState(() => _busy = 'Unhiding ${d + 1} of $t…');
        });
    if (!mounted) return;
    setState(() {
      _busy = null;
      _sel.clear();
    });
    snack(
        context,
        n == list.length
            ? '$n moved back to your phone ✔'
            : '$n of ${list.length} unhidden — open the rest one by one');
  }

  Future<void> _moveSel(AppState app) async {
    final targets =
        app.foldersOf(widget.cat).where((f) => f != widget.folder).toList();
    const newFolder = '\u0000new';
    final pick = await pickOne<String>(context,
        title: 'Move to folder',
        values: [...targets, newFolder],
        label: (f) => f == newFolder
            ? '+ New folder…'
            : (f.isEmpty ? 'Main' : f));
    if (pick == null || !mounted) return;
    var dest = pick;
    if (pick == newFolder) {
      final name = await promptText(context,
          title: 'New folder', hint: 'Folder name', ok: 'Create');
      if (name == null || !mounted) return;
      final err = await app.createFolder(widget.cat, name);
      if (err != null) {
        if (mounted) snack(context, err);
        return;
      }
      dest = name.trim();
    }
    await app.moveToFolder(_selected(app), dest);
    if (!mounted) return;
    setState(() => _sel.clear());
    snack(context, 'Moved to ${dest.isEmpty ? 'Main' : dest}');
  }

  Future<void> _deleteSel(AppState app) async {
    final list = _selected(app);
    if (!await confirm(context,
        title: 'Move ${list.length} to Recycle Bin?',
        message: 'You can restore them or delete them forever from the Recycle Bin.',
        ok: 'Move to bin',
        danger: true)) {
      return;
    }
    for (final m in list) {
      await app.deleteMedia(m);
    }
    if (!mounted) return;
    setState(() => _sel.clear());
    snack(context, '${list.length} moved to Recycle Bin');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = _items(app);
    final title = widget.folder.isEmpty ? 'Main' : widget.folder;

    return Scaffold(
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_sel.clear)),
              title: Text('${_sel.length} selected'),
              actions: [
                IconButton(
                  tooltip: 'Select all',
                  icon: const Icon(Icons.select_all),
                  onPressed: () =>
                      setState(() => _sel.addAll(items.map((e) => e.id))),
                ),
              ],
            )
          : AppBar(
              title: _searching
                  ? TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                          hintText: 'Search by name', border: InputBorder.none),
                      onChanged: (v) => setState(() => _query = v),
                    )
                  : Text(title),
              actions: [
                IconButton(
                  tooltip: _searching ? 'Close search' : 'Search',
                  icon: Icon(_searching ? Icons.close : Icons.search),
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _query = '';
                  }),
                ),
                IconButton(
                  tooltip: 'Favourites only',
                  icon: Icon(_favOnly ? Icons.star : Icons.star_border,
                      color: _favOnly ? const Color(0xFFEAB308) : null),
                  onPressed: () => setState(() => _favOnly = !_favOnly),
                ),
                PopupMenuButton<String>(
                  color: SV.panel,
                  onSelected: (v) {
                    if (_sorts.containsKey(v)) setState(() => _sort = v);
                    if (v == 'select' && items.isNotEmpty) {
                      setState(() => _sel.add(items.first.id));
                    }
                  },
                  itemBuilder: (_) => [
                    for (final e in _sorts.entries)
                      CheckedPopupMenuItem(
                          value: e.key,
                          checked: _sort == e.key,
                          child: Text(e.value)),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'select', child: Text('Select')),
                  ],
                ),
              ],
            ),
      body: Stack(
        children: [
          if (items.isEmpty)
            EmptyState(
              icon: widget.cat == MediaCat.audio
                  ? Icons.library_music_outlined
                  : widget.cat == MediaCat.video
                      ? Icons.video_library_outlined
                      : Icons.photo_library_outlined,
              title: _query.isNotEmpty || _favOnly
                  ? 'Nothing matches'
                  : 'This folder is empty',
              subtitle: _query.isNotEmpty || _favOnly
                  ? 'Try another search, or turn off the ⭐ filter'
                  : 'Tap + to lock ${MediaCat.noun(widget.cat)} into this folder',
            )
          else
            GridView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 110),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: widget.cat == MediaCat.audio ? 2 : 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final m = items[i];
                return MediaThumb(
                  item: m,
                  selecting: _selecting,
                  selected: _sel.contains(m.id),
                  onTap: () => _selecting ? _toggle(m) : _open(items, i),
                  onLongPress: () => _toggle(m),
                );
              },
            ),
          if (_busy != null) BusyOverlay(text: _busy!),
        ],
      ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              child: Container(
                color: SV.panel,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _selAction(Icons.lock_open, 'Unhide', () => _unhideSel(app)),
                    _selAction(Icons.star_outline, 'Favourite',
                        () => _favSel(app)),
                    _selAction(Icons.drive_file_move_outline, 'Move',
                        () => _moveSel(app)),
                    _selAction(Icons.delete_outline, 'Delete',
                        () => _deleteSel(app),
                        color: SV.bad),
                  ],
                ),
              ),
            )
          : null,
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy != null ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
    );
  }

  Widget _selAction(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    final c = color ?? SV.txt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: c, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
