import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// A square tile for one hidden item (image preview, video thumbnail with a
/// play badge, or an audio icon), with an optional selection overlay.
class MediaThumb extends StatelessWidget {
  final MediaItem item;
  final bool selected;
  final bool selecting;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const MediaThumb({
    super.key,
    required this.item,
    this.selected = false,
    this.selecting = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.isAudio)
              _audioTile()
            else
              FutureBuilder<Uint8List>(
                future: app.thumbBytes(item),
                builder: (_, snap) {
                  if (snap.hasData && snap.data!.isNotEmpty) {
                    return Image.memory(
                      snap.data!,
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    );
                  }
                  return _placeholder(
                      loading: snap.connectionState != ConnectionState.done);
                },
              ),
            if (item.isVideo)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 16),
                ),
              ),
            if (item.fav)
              const Positioned(
                left: 5,
                top: 5,
                child: Icon(Icons.star, color: Color(0xFFEAB308), size: 18,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
              ),
            if (selected) Container(color: SV.accent.withValues(alpha: 0.35)),
            if (selecting)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? SV.accent : Colors.black26,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder({bool loading = false}) => Container(
        color: SV.panel2,
        child: Center(
          child: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: SV.muted))
              : Icon(
                  item.isVideo ? Icons.movie_outlined : Icons.image_outlined,
                  color: SV.muted),
        ),
      );

  Widget _audioTile() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              SV.accent.withValues(alpha: 0.85),
              Color.lerp(SV.accent, Colors.black, 0.5)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_note, color: Colors.white, size: 34),
            const SizedBox(height: 6),
            Text(item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      );
}
