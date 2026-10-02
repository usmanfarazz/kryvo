import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'secure_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/media_item.dart';
import 'crypto_service.dart';

/// Stores hidden photos / videos / web images / audio as encrypted files in the
/// app's private storage.
///
///   * File bytes are encrypted with a random 256-bit "media key" kept in
///     Android Keystore-backed secure storage, so media survives a master
///     password change. The whole app still sits behind the lock screen.
///   * Each item is `<id>.enc`; videos can also have `<id>.thumb`.
///   * Big files are encrypted in 1 MiB chunks ("KRV2" format) so a large
///     video never has to fit in memory. Older single-shot files still open.
///   * Deleting is a two-step recycle bin: soft-delete, then purge.
///   * Nothing here ever touches the internet.
class MediaService {
  static final _storage = SecureStore.instance;
  static const _keyKey = 'kryvo.media.key';
  static const _indexKey = 'kryvo.media.index';
  static const _foldersKey = 'kryvo.media.folders';

  static Future<SecretKey> _mediaKey() async {
    var b64 = await _storage.read(key: _keyKey);
    if (b64 == null) {
      b64 = CryptoService.newRandomKeyB64();
      await _storage.write(key: _keyKey, value: b64);
    }
    return CryptoService.keyFromB64(b64);
  }

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/kryvo_media');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> _encFile(String id) async =>
      File('${(await _dir()).path}/$id.enc');

  // ---- Index ---------------------------------------------------------------

  /// All items (active + trashed), newest first.
  static Future<List<MediaItem>> loadIndex() async {
    final s = await _storage.read(key: _indexKey);
    if (s == null || s.isEmpty) return [];
    final list = (jsonDecode(s) as List)
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  static Future<void> _saveIndex(List<MediaItem> items) async {
    await _storage.write(
      key: _indexKey,
      value: jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> _append(MediaItem item) => appendMany([item]);

  /// Add several items to the index with ONE write (the index is rewritten as
  /// a whole, so writing once per item made big imports slow). Items added
  /// with `save: false` must be passed here afterwards; until then they are
  /// still on disk and "Recover lost media" would find them.
  static Future<void> appendMany(List<MediaItem> items) async {
    if (items.isEmpty) return;
    final idx = await loadIndex();
    idx.addAll(items);
    await _saveIndex(idx);
  }

  /// Apply [change] to every item whose id is in [ids].
  static Future<void> updateMany(
      Set<String> ids, MediaItem Function(MediaItem) change) async {
    final idx = await loadIndex();
    for (var i = 0; i < idx.length; i++) {
      if (ids.contains(idx[i].id)) idx[i] = change(idx[i]);
    }
    await _saveIndex(idx);
  }

  static Future<void> setDeleted(String id, int deletedAt) =>
      updateMany({id}, (m) => m.copyWith(deletedAt: deletedAt));

  static String _newId(String name) =>
      'm_${DateTime.now().microsecondsSinceEpoch}_${name.hashCode & 0x7fffffff}';

  // ---- Folders ---------------------------------------------------------------

  /// category -> folder names (the main folder '' is implicit).
  static Future<Map<String, List<String>>> loadFolders() async {
    final s = await _storage.read(key: _foldersKey);
    if (s == null || s.isEmpty) return {};
    final raw = jsonDecode(s) as Map<String, dynamic>;
    return raw.map((k, v) =>
        MapEntry(k, (v as List).map((e) => e as String).toList()));
  }

  static Future<void> saveFolders(Map<String, List<String>> f) async {
    await _storage.write(key: _foldersKey, value: jsonEncode(f));
  }

  // ---- Chunked format (v2) ---------------------------------------------------
  //   "KRV2" | repeat{ u32 length | iv(12) mac(16) ciphertext }

  static const List<int> _magic = [0x4B, 0x52, 0x56, 0x32]; // "KRV2"
  static const int _chunkSize = 1 << 20; // 1 MiB

  static bool _isV2(List<int> head) =>
      head.length >= 4 &&
      head[0] == _magic[0] &&
      head[1] == _magic[1] &&
      head[2] == _magic[2] &&
      head[3] == _magic[3];

  static Uint8List _u32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);

  static int _readU32(List<int> b) =>
      Uint8List.fromList(b).buffer.asByteData().getUint32(0, Endian.big);

  static Future<void> _encryptFile(File src, File dst, SecretKey key,
      {void Function(double progress)? onProgress}) async {
    final total = await src.length();
    final raf = await src.open();
    final sink = dst.openWrite();
    var done = 0;
    try {
      sink.add(_magic);
      while (true) {
        final chunk = await raf.read(_chunkSize);
        if (chunk.isEmpty) break;
        final enc = await CryptoService.encryptBytes(chunk, key);
        sink.add(_u32(enc.length));
        sink.add(enc);
        done += chunk.length;
        onProgress?.call(total == 0 ? 1 : done / total);
      }
    } finally {
      await raf.close();
      await sink.flush();
      await sink.close();
    }
  }

  static Future<void> _decryptFile(File src, File dst, SecretKey key) async {
    final raf = await src.open();
    final sink = dst.openWrite();
    try {
      final head = await raf.read(4);
      if (!_isV2(head)) {
        sink.add(
            await CryptoService.decryptBytes(await src.readAsBytes(), key));
        return;
      }
      while (true) {
        final lenB = await raf.read(4);
        if (lenB.length < 4) break;
        final block = await raf.read(_readU32(lenB));
        sink.add(await CryptoService.decryptBytes(block, key));
      }
    } finally {
      await raf.close();
      await sink.flush();
      await sink.close();
    }
  }

  // ---- Adding ------------------------------------------------------------------

  /// Encrypt in-memory image [bytes] (photo or web image) into the vault.
  static Future<MediaItem> addPhotoBytes({
    required Uint8List bytes,
    required String name,
    String category = MediaCat.photo,
    String folder = '',
    String space = '',
    bool save = true,
  }) async {
    final key = await _mediaKey();
    final enc = await CryptoService.encryptBytes(bytes, key);
    final id = _newId(name);
    await (await _encFile(id)).writeAsBytes(enc, flush: true);
    final item = MediaItem(
      id: id,
      type: 'photo',
      category: category,
      folder: folder,
      name: name,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      sizeBytes: bytes.length,
      space: space,
    );
    if (save) await _append(item);
    return item;
  }

  /// Encrypt a FILE of any size (video / audio), streamed, plus an optional
  /// JPEG thumbnail.
  static Future<MediaItem> addStreamedFile({
    required File src,
    required String type, // 'video' | 'audio'
    required String category,
    required String name,
    String folder = '',
    Uint8List? thumbBytes,
    void Function(double progress)? onProgress,
    String space = '',
    bool save = true,
  }) async {
    final key = await _mediaKey();
    final id = _newId(name);
    final size = await src.length();
    await _encryptFile(src, await _encFile(id), key, onProgress: onProgress);
    if (thumbBytes != null && thumbBytes.isNotEmpty) {
      final encThumb = await CryptoService.encryptBytes(thumbBytes, key);
      await File('${(await _dir()).path}/$id.thumb')
          .writeAsBytes(encThumb, flush: true);
    }
    final item = MediaItem(
      id: id,
      type: type,
      category: category,
      folder: folder,
      name: name,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      sizeBytes: size,
      space: space,
    );
    if (save) await _append(item);
    return item;
  }

  // ---- Reading -----------------------------------------------------------------

  /// Decrypt an item's main bytes into memory (images; small files).
  static Future<Uint8List> readBytes(MediaItem item) async {
    final key = await _mediaKey();
    final enc = await (await _encFile(item.id)).readAsBytes();
    if (!_isV2(enc)) return CryptoService.decryptBytes(enc, key);
    final out = BytesBuilder(copy: false);
    var pos = 4;
    while (pos + 4 <= enc.length) {
      final len = _readU32(enc.sublist(pos, pos + 4));
      pos += 4;
      out.add(await CryptoService.decryptBytes(
          Uint8List.sublistView(enc, pos, pos + len), key));
      pos += len;
    }
    return out.toBytes();
  }

  /// Grid preview: a video's thumbnail, an image's bytes, or empty.
  static Future<Uint8List> readThumb(MediaItem item) async {
    final tf = File('${(await _dir()).path}/${item.id}.thumb');
    if (await tf.exists()) {
      final key = await _mediaKey();
      return CryptoService.decryptBytes(await tf.readAsBytes(), key);
    }
    if (!item.isImage) return Uint8List(0); // never decrypt a video for a tile
    return readBytes(item);
  }

  /// Decrypt an item to a temporary file (playback / unhide). Caller deletes.
  static Future<File> decryptToTemp(MediaItem item) async {
    final key = await _mediaKey();
    final tmp = await getTemporaryDirectory();
    final safe = item.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final f = File('${tmp.path}/${item.id}_$safe');
    await _decryptFile(await _encFile(item.id), f, key);
    return f;
  }

  // ---- Unhide ------------------------------------------------------------------

  static const _native = MethodChannel('kryvo/media');

  /// Put an item back on the phone: photos → Pictures/Kryvo, videos →
  /// Movies/Kryvo, audio → Music/Kryvo. Returns true on success. (Audio needs
  /// Android 10+; on older phones the UI asks where to save it.)
  static Future<bool> restoreToGallery(MediaItem item) async {
    if (item.isAudio) {
      final tmp = await decryptToTemp(item);
      try {
        return await _native.invokeMethod<bool>('saveAudio', {
              'path': tmp.path,
              'name': item.name.isEmpty ? '${item.id}.mp3' : item.name,
            }) ??
            false;
      } catch (_) {
        return false;
      } finally {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
    if (item.isImage) {
      final bytes = await readBytes(item);
      var name = item.name.isEmpty ? '${item.id}.jpg' : item.name;
      if (!name.contains('.')) name = '$name.jpg';
      await PhotoManager.editor.saveImage(
        bytes,
        filename: name,
        relativePath: 'Pictures/Kryvo',
      );
      return true;
    }
    if (item.isVideo) {
      final tmp = await decryptToTemp(item);
      try {
        await PhotoManager.editor.saveVideo(
          tmp,
          title: item.name.isEmpty ? '${item.id}.mp4' : item.name,
          relativePath: 'Movies/Kryvo',
        );
        return true;
      } finally {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
    return false;
  }

  // ---- Deleting / maintenance ------------------------------------------------

  static Future<void> purge(MediaItem item) => purgeMany([item]);

  /// Delete several items' files, then update the index once.
  static Future<void> purgeMany(List<MediaItem> items) async {
    if (items.isEmpty) return;
    final dir = await _dir();
    for (final item in items) {
      for (final ext in ['.enc', '.thumb']) {
        final f = File('${dir.path}/${item.id}$ext');
        if (await f.exists()) await f.delete();
      }
    }
    final ids = {for (final i in items) i.id};
    final idx = await loadIndex();
    idx.removeWhere((e) => ids.contains(e.id));
    await _saveIndex(idx);
  }

  // ---- Full backup helpers ------------------------------------------------------

  /// Encrypted file of an item (and its thumbnail, if any) — for backups.
  static Future<File> encFileOf(String id) => _encFile(id);
  static Future<File> thumbFileOf(String id) async =>
      File('${(await _dir()).path}/$id.thumb');

  /// Raw bytes of the media key (only ever written into a backup encrypted
  /// with the vault key).
  static Future<List<int>> mediaKeyBytes() async =>
      (await _mediaKey()).extractBytes();

  /// Bring in an item encrypted with ANOTHER media key (from a backup):
  /// decrypt with [fromKey], re-encrypt with this phone's media key as [id].
  /// The short-lived plain copy is named "m_…" so "Recover lost media" would
  /// clean it up if the app were killed half-way.
  static Future<void> importForeign({
    required File enc,
    Uint8List? thumbEnc,
    required SecretKey fromKey,
    required String id,
  }) async {
    final key = await _mediaKey();
    final tmp = File('${(await getTemporaryDirectory()).path}/m_import_$id');
    try {
      await _decryptFile(enc, tmp, fromKey);
      await _encryptFile(tmp, await _encFile(id), key);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
    if (thumbEnc != null && thumbEnc.isNotEmpty) {
      final t = await CryptoService.decryptBytes(thumbEnc, fromKey);
      await (await thumbFileOf(id))
          .writeAsBytes(await CryptoService.encryptBytes(t, key), flush: true);
    }
  }

  // ---- Deleted from the Recycle Bin (kept for a while) -------------------------
  //
  // "Delete permanently" in the Recycle Bin doesn't wipe the files at once:
  // they move (still encrypted) to kryvo_media/erased and are listed under
  // Recover lost media for [keepErasedDays] days, so a mistake can be undone.
  // After that — or with "Erase now" — they are really deleted.

  static const _erasedKey = 'kryvo.media.erased';
  static const keepErasedDays = 30;

  static Future<Directory> _erasedDir() async {
    final d = Directory('${(await _dir()).path}/erased');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Erased items, newest first. [MediaItem.deletedAt] is when it was erased.
  static Future<List<MediaItem>> loadErased() async {
    final s = await _storage.read(key: _erasedKey);
    if (s == null || s.isEmpty) return [];
    final list = (jsonDecode(s) as List)
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return list;
  }

  static Future<void> _saveErased(List<MediaItem> l) => _storage.write(
      key: _erasedKey, value: jsonEncode(l.map((e) => e.toJson()).toList()));

  static Future<void> _move(File f, String to) async {
    if (!await f.exists()) return;
    try {
      await f.rename(to);
    } catch (_) {
      await f.copy(to);
      await f.delete();
    }
  }

  /// "Delete permanently" from the Recycle Bin: keep for [keepErasedDays].
  static Future<void> eraseMany(List<MediaItem> items) async {
    if (items.isEmpty) return;
    final dir = await _dir();
    final er = await _erasedDir();
    for (final m in items) {
      for (final ext in ['.enc', '.thumb']) {
        await _move(File('${dir.path}/${m.id}$ext'), '${er.path}/${m.id}$ext');
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final erased = await loadErased()
      ..addAll(items.map((m) => m.copyWith(deletedAt: now)));
    await _saveErased(erased);
    final ids = {for (final m in items) m.id};
    final idx = await loadIndex();
    idx.removeWhere((e) => ids.contains(e.id));
    await _saveIndex(idx);
  }

  /// Bring erased items back into the Recycle Bin.
  static Future<void> restoreErased(List<MediaItem> items) async {
    if (items.isEmpty) return;
    final dir = await _dir();
    final er = await _erasedDir();
    final back = <MediaItem>[];
    for (final m in items) {
      final enc = File('${er.path}/${m.id}.enc');
      if (!await enc.exists()) continue;
      await _move(enc, '${dir.path}/${m.id}.enc');
      await _move(File('${er.path}/${m.id}.thumb'), '${dir.path}/${m.id}.thumb');
      back.add(m.copyWith(deletedAt: DateTime.now().millisecondsSinceEpoch));
    }
    await appendMany(back);
    final ids = {for (final m in items) m.id};
    await _saveErased((await loadErased())..removeWhere((e) => ids.contains(e.id)));
  }

  /// Really delete erased items now.
  static Future<void> eraseNow(List<MediaItem> items) async {
    if (items.isEmpty) return;
    final er = await _erasedDir();
    for (final m in items) {
      for (final ext in ['.enc', '.thumb']) {
        final f = File('${er.path}/${m.id}$ext');
        if (await f.exists()) await f.delete();
      }
    }
    final ids = {for (final m in items) m.id};
    await _saveErased((await loadErased())..removeWhere((e) => ids.contains(e.id)));
  }

  /// Really delete erased items older than [keepErasedDays].
  static Future<void> expireErased() async {
    final limit = DateTime.now()
        .subtract(const Duration(days: keepErasedDays))
        .millisecondsSinceEpoch;
    final old = (await loadErased()).where((m) => m.deletedAt < limit).toList();
    await eraseNow(old);
  }

  /// Preview of an erased item (thumbnail, or the photo itself).
  static Future<Uint8List> readErasedThumb(MediaItem m) async {
    final er = await _erasedDir();
    final key = await _mediaKey();
    final t = File('${er.path}/${m.id}.thumb');
    if (await t.exists()) return CryptoService.decryptBytes(await t.readAsBytes(), key);
    if (!m.isImage) return Uint8List(0);
    final enc = File('${er.path}/${m.id}.enc');
    final tmp = File('${(await getTemporaryDirectory()).path}/m_erased_${m.id}');
    try {
      await _decryptFile(enc, tmp, key);
      return await tmp.readAsBytes();
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  /// Folder that recovered (previously lost) items are put into.
  static const recoveredFolder = 'Recovered';

  /// "Recover lost media": a full repair of the vault.
  ///
  ///   * Encrypted files that exist on disk but are missing from the index
  ///     (e.g. the app was closed in the middle of an import, or the index
  ///     write failed) are decrypted just enough to tell what they are and put
  ///     back into the vault, in a "Recovered" folder.
  ///   * Index entries whose file is gone are removed.
  ///   * Stray thumbnails and leftover decrypted temp copies (from a video
  ///     that was playing when the app was killed) are deleted.
  static Future<RecoverReport> recoverLost() async {
    final dir = await _dir();
    final key = await _mediaKey();
    final idx = await loadIndex();
    final known = idx.map((m) => m.id).toSet();

    // 1. Drop entries whose encrypted file is gone.
    final keep = <MediaItem>[];
    var cleaned = 0;
    for (final m in idx) {
      if (await (await _encFile(m.id)).exists()) {
        keep.add(m);
      } else {
        cleaned++;
      }
    }

    // 2. Bring back encrypted files the index forgot about.
    var recovered = 0, unreadable = 0;
    final recoveredCats = <String>{};
    final files = await dir.list().where((e) => e is File).cast<File>().toList();
    final encIds = <String>{};
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.enc')) continue;
      final id = name.substring(0, name.length - 4);
      encIds.add(id);
      if (known.contains(id)) continue;
      final info = await _identify(f, key);
      if (info == null) {
        unreadable++;
        continue;
      }
      final (type, ext, size) = info;
      final cat = type == 'video'
          ? MediaCat.video
          : type == 'audio'
              ? MediaCat.audio
              : MediaCat.photo;
      final stat = await f.stat();
      keep.add(MediaItem(
        id: id,
        type: type,
        category: cat,
        folder: recoveredFolder,
        name: 'Recovered_${recovered + 1}.$ext',
        addedAt: stat.modified.millisecondsSinceEpoch,
        sizeBytes: size,
      ));
      recoveredCats.add(cat);
      recovered++;
    }

    // 3. Thumbnails whose item no longer exists.
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.thumb') &&
          !encIds.contains(name.substring(0, name.length - 6))) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    // 4. Decrypted temp copies left behind (playback / unhide / share).
    var tempCleaned = 0;
    try {
      final tmp = await getTemporaryDirectory();
      await for (final e in tmp.list()) {
        if (e is File && e.uri.pathSegments.last.startsWith('m_')) {
          try {
            await e.delete();
            tempCleaned++;
          } catch (_) {}
        }
      }
    } catch (_) {}

    if (cleaned > 0 || recovered > 0) await _saveIndex(keep);
    if (recovered > 0) {
      final folders = await loadFolders();
      for (final c in recoveredCats) {
        final list = folders[c] ?? <String>[];
        if (!list.contains(recoveredFolder)) {
          folders[c] = [...list, recoveredFolder];
        }
      }
      await saveFolders(folders);
    }
    return RecoverReport(
      healthy: keep.length - recovered,
      cleaned: cleaned,
      recovered: recovered,
      unreadable: unreadable,
      tempCleaned: tempCleaned,
    );
  }

  /// Decrypt the first block of an encrypted file and tell what it holds:
  /// (type, file extension, plaintext size). Null if it can't be decrypted.
  static Future<(String, String, int)?> _identify(File f, SecretKey key) async {
    try {
      final raf = await f.open();
      Uint8List head;
      var size = 0;
      try {
        final magic = await raf.read(4);
        if (_isV2(magic)) {
          final total = await raf.length();
          var pos = 4;
          Uint8List? first;
          while (pos + 4 <= total) {
            await raf.setPosition(pos);
            final len = _readU32(await raf.read(4));
            if (first == null) {
              first = await CryptoService.decryptBytes(await raf.read(len), key);
            }
            size += len - 28; // iv(12) + mac(16) per block
            pos += 4 + len;
          }
          if (first == null) return null;
          head = first;
        } else {
          head = await CryptoService.decryptBytes(await f.readAsBytes(), key);
          size = head.length;
        }
      } finally {
        await raf.close();
      }
      final t = _sniff(head);
      return t == null ? null : (t.$1, t.$2, size);
    } catch (_) {
      return null; // wrong key / corrupt
    }
  }

  /// Recognise common photo / video / audio formats from their first bytes.
  static (String, String)? _sniff(Uint8List b) {
    bool at(int o, List<int> sig) {
      if (b.length < o + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[o + i] != sig[i]) return false;
      }
      return true;
    }

    String ascii(int o, int n) =>
        b.length < o + n ? '' : String.fromCharCodes(b.sublist(o, o + n));

    if (at(0, [0xFF, 0xD8, 0xFF])) return ('photo', 'jpg');
    if (at(0, [0x89, 0x50, 0x4E, 0x47])) return ('photo', 'png');
    if (ascii(0, 4) == 'GIF8') return ('photo', 'gif');
    if (at(0, [0x42, 0x4D])) return ('photo', 'bmp');
    if (ascii(0, 4) == 'RIFF') {
      final kind = ascii(8, 4);
      if (kind == 'WEBP') return ('photo', 'webp');
      if (kind == 'WAVE') return ('audio', 'wav');
      if (kind == 'AVI ') return ('video', 'avi');
    }
    if (ascii(4, 4) == 'ftyp') {
      final brand = ascii(8, 4);
      if (const ['heic', 'heix', 'heim', 'heis', 'mif1', 'msf1', 'avif']
          .contains(brand)) {
        return ('photo', brand == 'avif' ? 'avif' : 'heic');
      }
      if (const ['M4A ', 'M4B ', 'M4P '].contains(brand)) {
        return ('audio', 'm4a');
      }
      if (brand.startsWith('3g')) return ('video', '3gp');
      if (brand == 'qt  ') return ('video', 'mov');
      return ('video', 'mp4');
    }
    if (at(0, [0x1A, 0x45, 0xDF, 0xA3])) return ('video', 'mkv');
    if (ascii(0, 3) == 'ID3') return ('audio', 'mp3');
    if (b.length > 1 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) {
      return ('audio', (b[1] & 0x06) == 0 ? 'aac' : 'mp3');
    }
    if (ascii(0, 4) == 'OggS') return ('audio', 'ogg');
    if (ascii(0, 4) == 'fLaC') return ('audio', 'flac');
    if (ascii(0, 5) == '#!AMR') return ('audio', 'amr');
    return null;
  }

  /// Total bytes used by the vault's encrypted files.
  static Future<int> storageUsed() async {
    final dir = await _dir();
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  static Future<void> wipeAll() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
    await _storage.delete(key: _indexKey);
    await _storage.delete(key: _keyKey);
    await _storage.delete(key: _foldersKey);
    await _storage.delete(key: _erasedKey);
  }
}

/// Result of [MediaService.recoverLost].
class RecoverReport {
  final int healthy; // items that were fine
  final int cleaned; // index entries removed because their file was gone
  final int recovered; // lost files brought back into the vault
  final int unreadable; // files that could not be decrypted / identified
  final int tempCleaned; // leftover decrypted temp copies deleted

  const RecoverReport({
    required this.healthy,
    required this.cleaned,
    required this.recovered,
    required this.unreadable,
    required this.tempCleaned,
  });

  String describe() {
    final lines = <String>[];
    if (recovered > 0) {
      lines.add('$recovered lost item${recovered == 1 ? ' was' : 's were'} '
          'recovered. Find them in the "${MediaService.recoveredFolder}" folder.');
    } else {
      lines.add('No lost media found.');
    }
    lines.add('$healthy hidden item${healthy == 1 ? ' is' : 's are'} healthy ✔');
    if (cleaned > 0) {
      lines.add('$cleaned broken entr${cleaned == 1 ? 'y' : 'ies'} '
          '(file missing) cleaned up.');
    }
    if (unreadable > 0) {
      lines.add('$unreadable file${unreadable == 1 ? '' : 's'} could not be '
          'read and were left untouched.');
    }
    if (tempCleaned > 0) {
      lines.add('$tempCleaned leftover temporary file'
          '${tempCleaned == 1 ? '' : 's'} removed.');
    }
    return lines.join('\n\n');
  }
}
