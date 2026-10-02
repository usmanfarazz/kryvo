import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../services/media_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// How much space the vault uses, per section, with a quick clean-up.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  int? _onDisk;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final b = await MediaService.storageUsed();
    if (mounted) setState(() => _onDisk = b);
  }

  Future<void> _emptyBin(AppState app) async {
    final n = app.trash.length;
    if (!await confirm(context,
        title: 'Empty Recycle Bin?',
        message: 'Frees space now. For ${MediaService.keepErasedDays} days the '
            'items can still be brought back from Recover lost media.',
        ok: 'Empty',
        danger: true)) {
      return;
    }
    await app.emptyTrash();
    await _measure();
    if (mounted) snack(context, '$n item${n == 1 ? '' : 's'} removed');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rows = <(String, IconData, Color, int, int)>[
      for (final c in MediaCat.all)
        (
          MediaCat.title(c),
          c == MediaCat.photo
              ? Icons.photo_library_rounded
              : c == MediaCat.video
                  ? Icons.video_library_rounded
                  : c == MediaCat.web
                      ? Icons.public_rounded
                      : Icons.library_music_rounded,
          c == MediaCat.photo
              ? const Color(0xFF3D8BFF)
              : c == MediaCat.video
                  ? const Color(0xFFE53935)
                  : c == MediaCat.web
                      ? const Color(0xFF00BCD4)
                      : const Color(0xFFFF9800),
          app.itemsOf(c).length,
          app.itemsOf(c).fold<int>(0, (s, m) => s + m.sizeBytes),
        ),
      (
        'Recycle Bin',
        Icons.delete_sweep_rounded,
        const Color(0xFF8B5CF6),
        app.trash.length,
        app.trash.fold<int>(0, (s, m) => s + m.sizeBytes),
      ),
    ];
    final total = rows.fold<int>(0, (s, r) => s + r.$5);

    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vault size',
                      style: TextStyle(color: SV.muted, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(formatBytes(_onDisk ?? total),
                      style: TextStyle(
                          color: SV.txt,
                          fontSize: 30,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  // One coloured bar split by section.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 12,
                      child: Row(
                        children: [
                          for (final r in rows)
                            if (r.$5 > 0)
                              Expanded(
                                flex: (r.$5 * 1000 ~/ (total == 0 ? 1 : total))
                                    .clamp(1, 1000),
                                child: Container(color: r.$3),
                              ),
                          if (total == 0)
                            Expanded(child: Container(color: SV.panel2)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final r in rows)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: r.$3.withValues(alpha: 0.15),
                child: Icon(r.$2, color: r.$3),
              ),
              title: Text(r.$1),
              subtitle: Text('${r.$4} item${r.$4 == 1 ? '' : 's'}',
                  style: TextStyle(color: SV.muted)),
              trailing: Text(formatBytes(r.$5),
                  style: TextStyle(color: SV.txt, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 12),
          if (app.trash.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _emptyBin(app),
              icon: Icon(Icons.cleaning_services_outlined, color: SV.accent),
              label: Text('Free up ${formatBytes(rows.last.$5)} — empty Recycle Bin'),
            ),
          const SizedBox(height: 8),
          Text(
              'Sizes are the original file sizes. Everything is stored '
              'encrypted in Kryvo\'s private folder on this phone.',
              style: TextStyle(color: SV.muted, fontSize: 12)),
        ],
      ),
    );
  }
}
