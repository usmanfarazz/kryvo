import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import '../models/vault_entry.dart';
import 'crypto_service.dart';
import 'intruder_service.dart';
import 'media_service.dart';

/// Full encrypted backup of the vault in ONE ".kryvo" file: passwords,
/// photos, videos, web images, audio and folders.
///
/// File layout
///   "KRYVOBK1" | u32 header length | header JSON | item data…
/// Header (nothing in it is readable without the master password):
///   vault — the password vault blob, already encrypted with the vault key
///           (PBKDF2 of the master password + the salt stored inside it)
///   mk    — this phone's media key, encrypted with the vault key
///   man   — list of items + folders, encrypted with the vault key
/// Item data: each item's encrypted file, then its encrypted thumbnail —
///   copied as-is (they stay encrypted with the media key).
///
/// Restoring MERGES into the current vault: on a new phone, set Kryvo up,
/// then restore. Items already in the vault are skipped.
class FullBackupService {
  static const _magic = 'KRYVOBK1';

  static bool _isFull(List<int> head) =>
      head.length >= 8 && String.fromCharCodes(head.take(8)) == _magic;

  /// True if [file] is a full backup (false: old passwords-only backup).
  static Future<bool> isFullBackup(File file) async {
    final raf = await file.open();
    try {
      return _isFull(await raf.read(8));
    } finally {
      await raf.close();
    }
  }

  static Uint8List _u32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);

  /// Write a backup to a temporary file and return it (the caller saves it
  /// where the user wants and then deletes it).
  static Future<File> create({
    required Map<String, dynamic> vaultBlob,
    required SecretKey vaultKey,
    required List<MediaItem> media,
    required Map<String, List<String>> folders,
    void Function(int done, int total)? onProgress,
  }) async {
    // Trash and intruder photos are not backed up.
    final items = media
        .where((m) => !m.inTrash && m.category != IntruderService.category)
        .toList();
    final entries = <Map<String, dynamic>>[];
    final parts = <(File, File?)>[];
    for (final m in items) {
      final enc = await MediaService.encFileOf(m.id);
      if (!await enc.exists()) continue;
      final th = await MediaService.thumbFileOf(m.id);
      final hasThumb = await th.exists();
      entries.add({
        ...m.toJson(),
        'encLen': await enc.length(),
        'thumbLen': hasThumb ? await th.length() : 0,
      });
      parts.add((enc, hasThumb ? th : null));
    }
    final manifest = utf8.encode(jsonEncode({'items': entries, 'folders': folders}));
    final header = utf8.encode(jsonEncode({
      'v': 1,
      'app': 'Kryvo',
      'created': DateTime.now().millisecondsSinceEpoch,
      'count': entries.length,
      'vault': vaultBlob,
      'mk': base64Encode(await CryptoService.encryptBytes(
          await MediaService.mediaKeyBytes(), vaultKey)),
      'man': base64Encode(await CryptoService.encryptBytes(manifest, vaultKey)),
    }));

    final out = File('${(await getTemporaryDirectory()).path}/kryvo_backup.kryvo');
    final sink = out.openWrite();
    try {
      sink.add(utf8.encode(_magic));
      sink.add(_u32(header.length));
      sink.add(header);
      for (var i = 0; i < parts.length; i++) {
        onProgress?.call(i, parts.length);
        await sink.addStream(parts[i].$1.openRead());
        if (parts[i].$2 != null) await sink.addStream(parts[i].$2!.openRead());
      }
      onProgress?.call(parts.length, parts.length);
    } finally {
      await sink.flush();
      await sink.close();
    }
    return out;
  }

  /// Read and check a backup with [password]. Throws [FormatException] for a
  /// file that isn't a Kryvo backup and [WrongPassword] for a wrong password.
  static Future<OpenedBackup> open(File file, String password) async {
    final raf = await file.open();
    try {
      if (!_isFull(await raf.read(8))) {
        throw const FormatException('Not a Kryvo backup');
      }
      final len = ByteData.sublistView(Uint8List.fromList(await raf.read(4)))
          .getUint32(0, Endian.big);
      final header =
          jsonDecode(utf8.decode(await raf.read(len))) as Map<String, dynamic>;
      final vault = header['vault'] as Map<String, dynamic>;
      final key =
          await CryptoService.deriveKey(password, CryptoService.saltFromBlob(vault));
      String vaultJson;
      try {
        vaultJson = await CryptoService.decryptString(vault, key);
      } catch (_) {
        throw WrongPassword();
      }
      final mediaKey = SecretKey(await CryptoService.decryptBytes(
          base64Decode(header['mk'] as String), key));
      final man = jsonDecode(utf8.decode(await CryptoService.decryptBytes(
          base64Decode(header['man'] as String), key))) as Map<String, dynamic>;
      return OpenedBackup(
        file: file,
        dataStart: 8 + 4 + len,
        entries: (jsonDecode(vaultJson) as List)
            .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        mediaKey: mediaKey,
        items: (man['items'] as List).cast<Map<String, dynamic>>(),
        folders: (man['folders'] as Map<String, dynamic>? ?? {}).map(
            (k, v) => MapEntry(k, (v as List).cast<String>())),
      );
    } finally {
      await raf.close();
    }
  }

  /// Bring the backup's media into this vault (skipping ids in [existing]).
  /// Returns the new index items; the caller adds them to the index.
  static Future<List<MediaItem>> importMedia(
    OpenedBackup b, {
    required Set<String> existing,
    void Function(int done, int total)? onProgress,
  }) async {
    final added = <MediaItem>[];
    final raf = await b.file.open();
    final chunk = File('${(await getTemporaryDirectory()).path}/m_backup_part');
    try {
      var pos = b.dataStart;
      for (var i = 0; i < b.items.length; i++) {
        onProgress?.call(i, b.items.length);
        final e = b.items[i];
        final encLen = e['encLen'] as int, thumbLen = e['thumbLen'] as int;
        final item = MediaItem.fromJson(e);
        if (!existing.contains(item.id)) {
          // Copy this item's encrypted file out of the backup, in pieces.
          await raf.setPosition(pos);
          final sink = chunk.openWrite();
          var left = encLen;
          while (left > 0) {
            final part = await raf.read(left > (1 << 20) ? 1 << 20 : left);
            if (part.isEmpty) break;
            sink.add(part);
            left -= part.length;
          }
          await sink.flush();
          await sink.close();
          final thumb = thumbLen > 0 ? await raf.read(thumbLen) : null;
          await MediaService.importForeign(
              enc: chunk, thumbEnc: thumb, fromKey: b.mediaKey, id: item.id);
          added.add(item);
        }
        pos += encLen + thumbLen;
      }
      onProgress?.call(b.items.length, b.items.length);
    } finally {
      await raf.close();
      if (await chunk.exists()) await chunk.delete();
    }
    return added;
  }
}

class WrongPassword implements Exception {}

class OpenedBackup {
  final File file;
  final int dataStart;
  final List<VaultEntry> entries;
  final SecretKey mediaKey;
  final List<Map<String, dynamic>> items;
  final Map<String, List<String>> folders;

  OpenedBackup({
    required this.file,
    required this.dataStart,
    required this.entries,
    required this.mediaKey,
    required this.items,
    required this.folders,
  });
}
