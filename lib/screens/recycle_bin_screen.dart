import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../services/media_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/media_thumb.dart';

/// The Recycle Bin — photos/videos that were deleted. From here the user can
/// restore an item or delete it permanently.
class RecycleBinScreen extends StatelessWidget {
  RecycleBinScreen({super.key});

  Future<void> _itemActions(BuildContext context, MediaItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: SV.panel,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.restore, color: SV.accent),
              title: const Text('Restore'),
              subtitle: Text(
                  'Put it back in ${MediaCat.title(item.category)}',
                  style: TextStyle(color: SV.muted)),
              onTap: () => Navigator.pop(ctx, 'restore'),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: SV.bad),
              title: Text('Delete permanently',
                  style: TextStyle(color: SV.bad)),
              subtitle: Text(
                  'Can be brought back from Recover lost media for '
                  '${MediaService.keepErasedDays} days',
                  style: TextStyle(color: SV.muted)),
              onTap: () => Navigator.pop(ctx, 'purge'),
            ),
          ],
        ),
      ),
    );
    if (action == 'restore') {
      await context.read<AppState>().restoreMedia(item);
    } else if (action == 'purge') {
      await context.read<AppState>().eraseMedia([item]);
    }
  }

  Future<void> _emptyBin(BuildContext context, int count) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SV.panel,
        title: const Text('Empty Recycle Bin?'),
        content: Text(
            'Delete all $count item${count == 1 ? '' : 's'}? For '
            '${MediaService.keepErasedDays} days you can still bring them back '
            'from Settings → Recover lost media.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete all', style: TextStyle(color: SV.bad)),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      await context.read<AppState>().emptyTrash();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = app.trash;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Empty bin',
              icon: Icon(Icons.delete_forever, color: SV.bad),
              onPressed: () => _emptyBin(context, items.length),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 64, color: SV.muted),
                  const SizedBox(height: 12),
                  Text('Recycle Bin is empty',
                      style: TextStyle(color: SV.txt, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Deleted photos, videos and audio show up here',
                      style: TextStyle(color: SV.muted)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                return MediaThumb(
                  item: item,
                  onTap: () => _itemActions(context, item),
                );
              },
            ),
    );
  }
}
