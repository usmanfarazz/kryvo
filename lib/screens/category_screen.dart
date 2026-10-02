import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'folder_screen.dart';
import 'media_import.dart';
import 'settings_screen.dart';

/// One media section (Safe Photo / Video / Web Image / Audio): its folders,
/// plus the 3-dot menu: Refresh, New folder, Rename, Delete, Media scanning,
/// Import, Remove ads, Settings.
class CategoryScreen extends StatefulWidget {
  final String cat;
  const CategoryScreen({super.key, required this.cat});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  String? _busy;

  String _label(String f) => f.isEmpty ? 'Main' : f;

  Future<String?> _askFolderPin(String title) async {
    final p = await promptText(context,
        title: title,
        hint: '4 to 8 digits',
        obscure: true,
        keyboard: TextInputType.number,
        maxLength: 8,
        ok: 'OK');
    if (p == null) return null;
    if (!RegExp(r'^\d{4,8}$').hasMatch(p)) {
      if (mounted) snack(context, 'The PIN must be 4 to 8 digits');
      return null;
    }
    return p;
  }

  /// Open a folder, asking for its PIN first if it is locked.
  Future<void> _openFolder(AppState app, String f) async {
    if (app.needsFolderPin(widget.cat, f)) {
      final pin = await _askFolderPin('🔒 PIN for "${_label(f)}"');
      if (pin == null || !mounted) return;
      if (!await app.openLockedFolder(widget.cat, f, pin)) {
        if (mounted) snack(context, 'Wrong PIN');
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FolderScreen(cat: widget.cat, folder: f)));
  }

  Future<void> _menu(String v) async {
    final app = context.read<AppState>();
    switch (v) {
      case 'refresh': {
        await app.loadMedia();
        if (mounted) snack(context, 'Refreshed');
      }
      case 'new': {
        final name = await promptText(context,
            title: 'New folder', hint: 'Folder name', ok: 'Create');
        if (name == null || !mounted) return;
        final err = await app.createFolder(widget.cat, name);
        if (mounted) snack(context, err ?? 'Folder "${name.trim()}" created');
      }
      case 'rename': {
        final list =
            app.foldersOf(widget.cat).where((f) => f.isNotEmpty).toList();
        if (list.isEmpty) {
          snack(context, 'Create a folder first (the Main folder keeps its name)');
          return;
        }
        final from = await pickOne<String>(context,
            title: 'Rename which folder?', values: list, label: (f) => f);
        if (from == null || !mounted) return;
        final to = await promptText(context,
            title: 'Rename folder', initial: from, ok: 'Rename');
        if (to == null || !mounted) return;
        final err = await app.renameFolder(widget.cat, from, to);
        if (mounted) snack(context, err ?? 'Renamed to "${to.trim()}"');
      }
      case 'delete': {
        final list =
            app.foldersOf(widget.cat).where((f) => f.isNotEmpty).toList();
        if (list.isEmpty) {
          snack(context, 'No folders to delete (the Main folder stays)');
          return;
        }
        final picked = await pickMany<String>(context,
            title: 'Delete which folders?',
            values: list,
            label: (f) {
              final n = app.itemsOf(widget.cat, folder: f).length;
              return '$f  ($n)';
            },
            ok: 'Delete',
            danger: true);
        if (picked == null || picked.isEmpty || !mounted) return;
        final n = picked.fold<int>(
            0, (s, f) => s + app.itemsOf(widget.cat, folder: f).length);
        final what = picked.length == 1
            ? '"${picked.first}"'
            : '${picked.length} folders';
        if (!await confirm(context,
            title: 'Delete $what?',
            message: n == 0
                ? (picked.length == 1
                    ? 'The folder is empty.'
                    : 'The folders are empty.')
                : '$n item${n == 1 ? '' : 's'} inside will go to the Recycle Bin.',
            ok: 'Delete',
            danger: true)) {
          return;
        }
        String? err;
        for (final f in picked) {
          err ??= await app.deleteFolder(widget.cat, f);
        }
        if (mounted) {
          snack(
              context,
              err ??
                  (picked.length == 1
                      ? 'Folder deleted'
                      : '${picked.length} folders deleted'));
        }
      }
      case 'lockfolder': {
        final f = await pickOne<String>(context,
            title: 'Lock or unlock which folder?',
            values: app.foldersOf(widget.cat),
            label: (f) =>
                '${app.isFolderLocked(widget.cat, f) ? '🔒 ' : ''}${_label(f)}');
        if (f == null || !mounted) return;
        if (app.isFolderLocked(widget.cat, f)) {
          final pin = await _askFolderPin('Current PIN of "${_label(f)}"');
          if (pin == null || !mounted) return;
          if (!await app.openLockedFolder(widget.cat, f, pin)) {
            if (mounted) snack(context, 'Wrong PIN');
            return;
          }
          await app.unlockFolderForGood(widget.cat, f);
          if (mounted) snack(context, '"${_label(f)}" is no longer locked');
          return;
        }
        final p1 = await _askFolderPin('New PIN for "${_label(f)}"');
        if (p1 == null || !mounted) return;
        final p2 = await _askFolderPin('Confirm PIN');
        if (p2 == null || !mounted) return;
        if (p1 != p2) {
          snack(context, 'PINs did not match');
          return;
        }
        await app.lockFolder(widget.cat, f, p1);
        if (mounted) snack(context, '"${_label(f)}" locked 🔒');
      }
      case 'scan': {
        setState(() => _busy = 'Scanning media…');
        final r = await app.recoverLostMedia();
        if (!mounted) return;
        setState(() => _busy = null);
        await showRecoverReport(context, r);
      }
      case 'import': {
        await _import('');
      }
      case 'ads': {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: SV.panel,
            icon: Icon(Icons.verified, color: SV.ok, size: 40),
            title: const Text('Kryvo is ad-free'),
            content: const Text(
                'There are no ads in Kryvo — and no trackers. Your photos and '
                'passwords never leave your phone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Great')),
            ],
          ),
        );
      }
      case 'settings': {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => SettingsScreen()));
      }
    }
  }

  Future<void> _import(String folder) async {
    final msg = await importMedia(context,
        cat: widget.cat,
        folder: folder,
        setBusy: (t) {
          if (mounted) setState(() => _busy = t);
        });
    if (msg != null && mounted) snack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final folders = app.foldersOf(widget.cat);
    final total = app.itemsOf(widget.cat).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(MediaCat.title(widget.cat)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: SV.panel,
            onSelected: _menu,
            itemBuilder: (_) => [
              _item('refresh', Icons.refresh, 'Refresh'),
              _item('new', Icons.create_new_folder_outlined, 'New folder'),
              _item('rename', Icons.drive_file_rename_outline, 'Rename'),
              _item('delete', Icons.folder_delete_outlined, 'Delete'),
              _item('lockfolder', Icons.lock_outline, 'Lock / unlock folder'),
              _item('scan', Icons.manage_search, 'Media scanning'),
              _item('import', Icons.file_download_outlined, 'Import'),
              _item('settings', Icons.settings_outlined, 'Settings'),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Text(
                    '$total ${MediaCat.noun(widget.cat)} · ${folders.length} folder${folders.length == 1 ? '' : 's'}',
                    style: TextStyle(color: SV.muted)),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.86,
                ),
                itemCount: folders.length,
                itemBuilder: (_, i) {
                  final f = folders[i];
                  final items = app.itemsOf(widget.cat, folder: f);
                  final locked = app.isFolderLocked(widget.cat, f);
                  return _FolderTile(
                    name: _label(f),
                    count: items.length,
                    // A locked folder never shows a preview of its contents.
                    cover: locked || app.hideFolderThumbs || items.isEmpty
                        ? null
                        : items.first,
                    cat: widget.cat,
                    locked: locked,
                    onTap: () => _openFolder(app, f),
                  );
                },
              ),
            ],
          ),
          if (_busy != null) BusyOverlay(text: _busy!),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy != null ? null : () => _import(''),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }

  PopupMenuItem<String> _item(String v, IconData icon, String text) =>
      PopupMenuItem(
        value: v,
        child: Row(
          children: [
            Icon(icon, color: SV.muted, size: 20),
            const SizedBox(width: 12),
            Text(text),
          ],
        ),
      );
}

class _FolderTile extends StatelessWidget {
  final String name;
  final int count;
  final MediaItem? cover;
  final String cat;
  final bool locked;
  final VoidCallback onTap;
  const _FolderTile({
    required this.name,
    required this.count,
    required this.cover,
    required this.cat,
    required this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final c = cover;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: SV.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SV.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: (c == null || c.isAudio)
                    ? Container(
                        color: SV.accent.withValues(alpha: 0.12),
                        child: Icon(
                          locked
                              ? Icons.lock
                              : cat == MediaCat.audio
                                  ? Icons.library_music
                                  : Icons.folder,
                          color: SV.accent,
                          size: 56,
                        ),
                      )
                    : FutureBuilder<Uint8List>(
                        future: app.thumbBytes(c),
                        builder: (_, snap) => snap.hasData &&
                                snap.data!.isNotEmpty
                            ? Image.memory(snap.data!,
                                fit: BoxFit.cover,
                                cacheWidth: 360,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) =>
                                    Container(color: SV.panel2))
                            : Container(
                                color: SV.panel2,
                                child: Icon(Icons.folder, color: SV.muted)),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Icon(locked ? Icons.lock : Icons.folder,
                      color: SV.accent, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: SV.txt, fontWeight: FontWeight.w700)),
                  ),
                  Text('$count', style: TextStyle(color: SV.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
