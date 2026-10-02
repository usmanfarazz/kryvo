import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../services/gallery_cleanup.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'gallery_picker_screen.dart';

/// Import flow for one category into one folder.
///
/// [setBusy] shows/hides the progress overlay (null = hide). Returns a short
/// summary to show in a snackbar, or null if the user cancelled.
Future<String?> importMedia(
  BuildContext context, {
  required String cat,
  required String folder,
  required void Function(String? text) setBusy,
}) async {
  final isAudio = cat == MediaCat.audio;
  final src = isAudio ? 'system' : await _chooseSource(context, cat);
  if (src == null || !context.mounted) return null;

  final app = context.read<AppState>();
  app.holdLock(); // pickers & delete dialogs are system screens
  try {
    if (cat == MediaCat.video) {
      return src == 'kryvo'
          ? await _videosFromKryvo(context, app, folder, setBusy)
          : await _filesFromSystem(context, app, cat, folder, setBusy);
    }
    if (isAudio) {
      return await _filesFromSystem(context, app, cat, folder, setBusy);
    }
    return src == 'kryvo'
        ? await _imagesFromKryvo(context, app, cat, folder, setBusy)
        : await _imagesFromSystem(context, app, cat, folder, setBusy);
  } catch (e) {
    return 'Could not import: $e';
  } finally {
    setBusy(null);
    app.releaseLock();
  }
}

Future<String?> _chooseSource(BuildContext context, String cat) {
  final isVideo = cat == MediaCat.video;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: SV.panel,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
                color: SV.line, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text('Add ${MediaCat.noun(cat)}',
                style: TextStyle(
                    color: SV.txt, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: SV.accent.withValues(alpha: 0.15),
              child: Icon(isVideo ? Icons.video_library : Icons.photo_library,
                  color: SV.accent),
            ),
            title: const Text('From gallery'),
            subtitle: Text('Albums inside Kryvo · hides the originals',
                style: TextStyle(color: SV.muted)),
            onTap: () => Navigator.pop(ctx, 'kryvo'),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: SV.accent.withValues(alpha: 0.15),
              child: Icon(Icons.folder_open, color: SV.accent),
            ),
            title: const Text("Phone's picker / files"),
            subtitle: Text('Downloads, WhatsApp, any folder',
                style: TextStyle(color: SV.muted)),
            onTap: () => Navigator.pop(ctx, 'system'),
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

String _summary(int n, int removed, String noun) {
  final base = '$n $noun locked ✔';
  return removed > 0
      ? '$base · $removed removed from gallery'
      : '$base · originals still in gallery';
}

/// Platform-decoded JPEG, capped at 1920px, falling back to original bytes.
Future<Uint8List?> _decodableJpeg(AssetEntity a) async {
  var w = a.width, h = a.height;
  if (w <= 0 || h <= 0) {
    w = 1920;
    h = 1920;
  }
  final long = w > h ? w : h;
  if (long > 1920) {
    final s = 1920 / long;
    w = (w * s).round();
    h = (h * s).round();
  }
  try {
    final d = await a.thumbnailDataWithSize(
        ThumbnailSize(w < 1 ? 1 : w, h < 1 ? 1 : h),
        quality: 90);
    if (d != null && d.isNotEmpty) return d;
  } catch (_) {}
  return a.originBytes;
}

Future<Uint8List> _thumbOf(AssetEntity a) async {
  try {
    return await a.thumbnailDataWithSize(const ThumbnailSize(500, 500),
            quality: 80) ??
        Uint8List(0);
  } catch (_) {
    return Uint8List(0);
  }
}

Future<String?> _imagesFromKryvo(BuildContext context, AppState app,
    String cat, String folder, void Function(String?) setBusy) async {
  final chosen = await Navigator.of(context).push<List<AssetEntity>>(
    MaterialPageRoute(
      builder: (_) => GalleryPickerScreen(
          type: RequestType.image, title: 'Add ${MediaCat.noun(cat)}'),
    ),
  );
  if (chosen == null || chosen.isEmpty) return null;
  // Originals are encrypted straight from their file (fast, full quality,
  // with a small preview for the grid). Only HEIC/HEIF photos, which the app
  // can't display, are converted to JPEG first.
  final files = <(String, File, Uint8List)>[];
  final converted = <(String, Uint8List)>[];
  final ids = <String>[];
  Object? err;
  var i = 0;
  for (final a in chosen) {
    i++;
    setBusy('Preparing $i of ${chosen.length}…');
    try {
      final name = (a.title?.isNotEmpty ?? false) ? a.title! : 'img_${a.id}.jpg';
      final mime = (a.mimeType ?? '').toLowerCase();
      final lower = name.toLowerCase();
      final heif = mime.contains('heic') ||
          mime.contains('heif') ||
          lower.endsWith('.heic') ||
          lower.endsWith('.heif');
      if (!heif) {
        final f = await a.originFile ?? await a.file;
        if (f != null) {
          files.add((name, f, await _thumbOf(a)));
          ids.add(a.id);
          continue;
        }
      }
      final d = await _decodableJpeg(a);
      if (d != null && d.isNotEmpty) {
        converted.add((name.replaceFirst(RegExp(r'.hei[cf]$', caseSensitive: false), '.jpg'), d));
        ids.add(a.id);
      }
    } catch (e) {
      err ??= e;
    }
  }
  if (files.isEmpty && converted.isEmpty) {
    return 'Could not read the selected items${err == null ? '' : ': $err'}';
  }
  var n = 0;
  if (files.isNotEmpty) {
    n += await app.addFiles(files,
        category: cat,
        folder: folder,
        onProgress: (k, _) =>
            setBusy('Encrypting ${k + 1} of ${files.length + converted.length}…'));
    await _dropCacheCopies(files);
  }
  if (converted.isNotEmpty) {
    setBusy('Encrypting…');
    n += await app.addImages(converted, category: cat, folder: folder);
  }
  setBusy('Removing originals from gallery…');
  final removed = await GalleryCleanup.deleteIds(ids);
  return _summary(n, removed, MediaCat.noun(cat));
}

/// Plain copies some pickers leave in the app cache must not stay on disk
/// once the item is encrypted.
/// Only files inside Kryvo's own cache folder are deleted — never a file
/// that belongs to the gallery or another app.
Future<void> _dropCacheCopies(List<(String, File, Uint8List)> files) async {
  final cache = (await getTemporaryDirectory()).path;
  for (final it in files) {
    try {
      if (it.$2.path.startsWith('$cache/')) await it.$2.delete();
    } catch (_) {}
  }
}

Future<String?> _imagesFromSystem(BuildContext context, AppState app,
    String cat, String folder, void Function(String?) setBusy) async {
  final res = await FilePicker.platform
      .pickFiles(type: FileType.image, allowMultiple: true);
  if (res == null || res.files.isEmpty) return null;
  final items = <(String, Uint8List)>[];
  final names = <String>[];
  var i = 0;
  for (final f in res.files) {
    i++;
    setBusy('Encrypting $i of ${res.files.length}…');
    final bytes =
        f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) continue;
    items.add((f.name, bytes));
    names.add(f.name);
  }
  if (items.isEmpty) return 'Could not read the selected items';
  final n = await app.addImages(items, category: cat, folder: folder);
  setBusy('Removing originals from gallery…');
  final removed =
      await GalleryCleanup.removeOriginalsByName(names, RequestType.image);
  return _summary(n, removed, MediaCat.noun(cat));
}

Future<String?> _videosFromKryvo(BuildContext context, AppState app,
    String folder, void Function(String?) setBusy) async {
  final chosen = await Navigator.of(context).push<List<AssetEntity>>(
    MaterialPageRoute(
      builder: (_) =>
          GalleryPickerScreen(type: RequestType.video, title: 'Add videos'),
    ),
  );
  if (chosen == null || chosen.isEmpty) return null;
  setBusy('Preparing…');
  final items = <(String, File, Uint8List)>[];
  final ids = <String>[];
  for (final a in chosen) {
    final file = await a.originFile ?? await a.file;
    if (file == null) continue;
    items.add((
      (a.title?.isNotEmpty ?? false) ? a.title! : 'video_${a.id}.mp4',
      file,
      await _thumbOf(a),
    ));
    ids.add(a.id);
  }
  if (items.isEmpty) return 'Could not open the selected videos';
  final n = await app.addFiles(items,
      category: MediaCat.video,
      folder: folder,
      onProgress: (i, p) => setBusy(
          'Encrypting video ${i + 1} of ${items.length} · ${(p * 100).toStringAsFixed(0)}%'));
  await _dropCacheCopies(items);
  setBusy('Removing originals from gallery…');
  final removed = await GalleryCleanup.deleteIds(ids);
  return _summary(n, removed, 'videos');
}

/// Videos or audio picked with the phone's picker (streamed, any size).
Future<String?> _filesFromSystem(BuildContext context, AppState app,
    String cat, String folder, void Function(String?) setBusy) async {
  final isAudio = cat == MediaCat.audio;
  final res = await FilePicker.platform.pickFiles(
      type: isAudio ? FileType.audio : FileType.video, allowMultiple: true);
  if (res == null || res.files.isEmpty) return null;
  setBusy('Preparing…');
  final type = isAudio ? RequestType.audio : RequestType.video;
  final names = [
    for (final f in res.files)
      if (f.path != null) f.name
  ];
  final found = await GalleryCleanup.findByNames(names, type);
  final items = <(String, File, Uint8List)>[];
  final ids = <String>[];
  for (final f in res.files) {
    if (f.path == null) continue;
    final asset = found[f.name];
    items.add((
      f.name,
      File(f.path!),
      (asset == null || isAudio) ? Uint8List(0) : await _thumbOf(asset),
    ));
    if (asset != null) ids.add(asset.id);
  }
  if (items.isEmpty) return 'Could not open the selected files';
  final noun = MediaCat.noun(cat);
  final n = await app.addFiles(items,
      category: cat,
      folder: folder,
      onProgress: (i, p) => setBusy(
          'Encrypting ${i + 1} of ${items.length} · ${(p * 100).toStringAsFixed(0)}%'));
  setBusy('Removing originals…');
  final removed = await GalleryCleanup.deleteIds(ids);
  // file_picker keeps a cached copy; remove it now that it is encrypted.
  await _dropCacheCopies(items);
  return _summary(n, removed, noun);
}
