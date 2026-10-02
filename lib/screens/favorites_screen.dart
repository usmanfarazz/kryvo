import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/media_thumb.dart';
import 'photo_viewer.dart';
import 'video_player_screen.dart';

/// Every item marked ⭐ favourite, from all sections.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  void _open(BuildContext context, List<MediaItem> items, MediaItem m) {
    final photos = items.where((x) => x.isImage).toList();
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => m.isImage
            ? PhotoViewer(items: photos, initialIndex: photos.indexOf(m))
            : VideoPlayerScreen(item: m)));
  }

  Future<void> _unfav(BuildContext context, MediaItem m) async {
    if (!await confirm(context,
        title: 'Remove from favourites?',
        message: '"${m.name}" stays in your vault.',
        ok: 'Remove')) {
      return;
    }
    if (context.mounted) await context.read<AppState>().setFavorite([m], false);
  }

  @override
  Widget build(BuildContext context) {
    final items = context.watch<AppState>().favorites;
    return Scaffold(
      appBar: AppBar(title: Text('Favourites (${items.length})')),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.star_outline,
              title: 'No favourites yet',
              subtitle:
                  'In any folder, long-press items and tap ⭐ to add them here.',
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => MediaThumb(
                item: items[i],
                onTap: () => _open(context, items, items[i]),
                onLongPress: () => _unfav(context, items[i]),
              ),
            ),
    );
  }
}
