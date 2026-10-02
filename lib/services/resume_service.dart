import 'dart:convert';

import 'secure_store.dart';

/// Remembers where each video / audio was stopped, so it continues from
/// there next time. Kept for the 100 most recent items.
class ResumeService {
  static final _s = SecureStore.instance;
  static const _key = 'kryvo.media.resume';

  static Future<Map<String, int>> _load() async {
    final s = await _s.read(key: _key);
    if (s == null || s.isEmpty) return {};
    return (jsonDecode(s) as Map<String, dynamic>).cast<String, int>();
  }

  /// Saved position in ms, or null.
  static Future<int?> positionOf(String id) async => (await _load())[id];

  /// Save the position; near the start or the end it is cleared instead.
  static Future<void> save(String id, Duration pos, Duration total) async {
    final m = await _load();
    m.remove(id);
    final nearStart = pos < const Duration(seconds: 5);
    final nearEnd = total > Duration.zero &&
        pos > total * 0.95; // finished — start over next time
    if (!nearStart && !nearEnd) m[id] = pos.inMilliseconds;
    // Keep the newest 100 entries (insertion order = most recent last).
    while (m.length > 100) {
      m.remove(m.keys.first);
    }
    await _s.write(key: _key, value: jsonEncode(m));
  }
}
