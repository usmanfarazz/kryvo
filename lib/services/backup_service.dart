import 'dart:convert';
import 'dart:io';

/// Older passwords-only backups (".svbackup"): the encrypted vault blob
/// (salt + iv + ciphertext + mac) as JSON. New backups are full backups —
/// see FullBackupService.
class BackupService {
  /// Read an old backup file. Returns null if it isn't one.
  static Future<Map<String, dynamic>?> readOldBackup(File file) async {
    try {
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final k in ['ct', 'iv', 'mac', 'salt']) {
        if (!map.containsKey(k)) return null;
      }
      return map;
    } catch (_) {
      return null;
    }
  }
}
