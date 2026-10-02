import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';

/// A gallery browser the user picks from (albums + multi-select). Returns the
/// chosen [AssetEntity]s so the caller can import them AND delete originals.
class GalleryPickerScreen extends StatefulWidget {
  final RequestType type;
  final String title;
  GalleryPickerScreen({super.key, required this.type, required this.title});

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen> {
  final List<AssetEntity> _assets = [];
  final Set<String> _selected = {};
  final Map<String, Future<ImageProvider?>> _thumbs = {};
  final ScrollController _scroll = ScrollController();

  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  int _page = 0;
  bool _more = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _denied = false;
  bool _limited = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 800) {
        _loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: RequestType.common,
            mediaLocation: false,
          ),
        ),
      );
      if (!ps.hasAccess) {
        setState(() {
          _denied = true;
          _loading = false;
        });
        return;
      }
      _denied = false;
      _limited = !ps.isAuth;
      final albums = await PhotoManager.getAssetPathList(
        type: widget.type,
        hasAll: true,
        onlyAll: false,
      );
      // Put the "All / Recent" album first.
      albums.sort((a, b) => (b.isAll ? 1 : 0).compareTo(a.isAll ? 1 : 0));
      _albums = albums;
      await _openAlbum(albums.isNotEmpty ? albums.first : null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openAlbum(AssetPathEntity? album) async {
    _album = album;
    _assets.clear();
    _thumbs.clear();
    _page = 0;
    _more = album != null;
    if (album != null) await _loadMore(force: true);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore({bool force = false}) async {
    if (_album == null || !_more || (_loadingMore && !force)) return;
    _loadingMore = true;
    try {
      final batch = await _album!.getAssetListPaged(page: _page, size: 90);
      if (batch.length < 90) _more = false;
      _page++;
      _assets.addAll(batch);
    } catch (e) {
      _error = '$e';
      _more = false;
    }
    _loadingMore = false;
    if (mounted) setState(() {});
  }

  /// First preview error seen (shown in a banner so problems aren't silent).
  String? _thumbError;

  void _noteError(String e) {
    if (_thumbError == null && mounted) setState(() => _thumbError = e);
  }

  // At most this many previews are requested from the phone at once. Asking
  // for a whole page (90) at the same time can stall the phone's thumbnail
  // loader, which left the grid as empty grey boxes on some phones.
  static const _maxParallel = 6;
  int _running = 0;
  final List<void Function()> _waiting = [];

  Future<T> _throttled<T>(Future<T> Function() job) async {
    if (_running >= _maxParallel) {
      final ready = Completer<void>();
      _waiting.add(ready.complete);
      await ready.future;
    }
    _running++;
    try {
      return await job();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0)();
    }
  }

  /// Preview for a grid cell, tried in order until one works:
  ///   1. the phone's own thumbnail (fast, works for photos and videos),
  ///   2. a video frame via the thumbnail options API,
  ///   3. for photos: the image file itself, decoded small by Flutter.
  ///
  /// The first previews after opening the picker can fail while the phone's
  /// image loader is still starting up (they showed a cross until you
  /// scrolled), so a failed preview is retried a few times before giving up.
  Future<ImageProvider?> _thumb(AssetEntity a) =>
      _thumbs.putIfAbsent(a.id, () => _throttled(() => _loadWithRetry(a)));

  Future<ImageProvider?> _loadWithRetry(AssetEntity a) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted) return null;
      final img = await _loadThumb(a);
      if (img != null) return img;
      await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }
    return null;
  }

  Future<ImageProvider?> _loadThumb(AssetEntity a) async {
    const wait = Duration(seconds: 6);
    try {
      final t = await a
          .thumbnailDataWithSize(const ThumbnailSize.square(240), quality: 80)
          .timeout(wait);
      if (t != null && t.isNotEmpty) return MemoryImage(t);
    } catch (e) {
      _noteError('$e');
    }
    if (a.type == AssetType.video) {
      try {
        final t = await a
            .thumbnailDataWithOption(const ThumbnailOption(
              size: ThumbnailSize.square(200),
              format: ThumbnailFormat.png,
            ))
            .timeout(wait);
        if (t != null && t.isNotEmpty) return MemoryImage(t);
      } catch (e) {
        _noteError('$e');
      }
      return null;
    }
    try {
      final f = await a.file.timeout(wait);
      if (f != null && await f.exists()) {
        return ResizeImage(FileImage(f), width: 240);
      }
    } catch (e) {
      _noteError('$e');
    }
    try {
      final raw = await a.originBytes.timeout(wait);
      if (raw != null && raw.isNotEmpty) {
        return ResizeImage(MemoryImage(raw), width: 240);
      }
    } catch (e) {
      _noteError('$e');
    }
    return null;
  }

  void _toggle(AssetEntity a) {
    setState(() {
      if (!_selected.remove(a.id)) _selected.add(a.id);
    });
  }

  void _confirm() {
    final chosen = _assets.where((a) => _selected.contains(a.id)).toList();
    Navigator.pop(context, chosen);
  }

  Future<void> _selectMore() async {
    await PhotoManager.presentLimited(type: widget.type);
    await _init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _albums.length > 1
            ? DropdownButtonHideUnderline(
                child: DropdownButton<AssetPathEntity>(
                  value: _album,
                  dropdownColor: SV.panel,
                  isExpanded: true,
                  style: TextStyle(
                      color: SV.txt,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                  items: _albums
                      .map((a) => DropdownMenuItem(
                            value: a,
                            child: Text(
                              a.isAll ? 'All ${_kind()}' : a.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (a) {
                    if (a == null) return;
                    setState(() => _loading = true);
                    _openAlbum(a);
                  },
                ),
              )
            : Text(widget.title),
        actions: [
          if (_assets.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == _assets.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(_assets.map((e) => e.id));
                }
              }),
              child: Text(
                _selected.length == _assets.length ? 'None' : 'All',
                style: TextStyle(color: SV.accent),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_limited) _limitedBanner(),
          if (_thumbError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SV.warn.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SV.warn.withValues(alpha: 0.4)),
              ),
              child: Text(
                'Some previews could not load on this phone. You can still '
                'select them, or go back and use "Phone\'s photo picker".\n'
                'Details: $_thumbError',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: SV.txt, fontSize: 11),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ElevatedButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.lock),
                  label: Text('Hide ${_selected.length} '
                      '${_selected.length == 1 ? 'item' : 'items'}'),
                ),
              ),
            ),
    );
  }

  String _kind() => widget.type == RequestType.video ? 'videos' : 'photos';

  Widget _limitedBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SV.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SV.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kryvo can only see some of your ${_kind()}.',
              style: TextStyle(color: SV.txt, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Allow full access to see everything in your gallery.',
              style: TextStyle(color: SV.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                  onPressed: _selectMore,
                  child: Text('Select more',
                      style: TextStyle(color: SV.accent))),
              const SizedBox(width: 8),
              TextButton(
                  onPressed: () => PhotoManager.openSetting(),
                  child: Text('Allow all',
                      style: TextStyle(
                          color: SV.accent, fontWeight: FontWeight.w700))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_denied) {
      return _message(
        icon: Icons.lock_outline,
        title: 'Gallery permission needed',
        body: 'Kryvo needs access to your photos and videos to move them '
            'into the vault. Tap below and choose "Allow all".',
        button: 'Open settings',
        onTap: () async {
          await PhotoManager.openSetting();
        },
        secondButton: 'Try again',
        onSecond: _init,
      );
    }
    if (_error != null && _assets.isEmpty) {
      return _message(
        icon: Icons.error_outline,
        title: 'Could not read your gallery',
        body: _error!,
        button: 'Try again',
        onTap: _init,
      );
    }
    if (_assets.isEmpty) {
      return _message(
        icon: widget.type == RequestType.video
            ? Icons.video_library_outlined
            : Icons.photo_library_outlined,
        title: 'No ${_kind()} found',
        body: _limited
            ? 'You only allowed some items. Tap "Select more" above.'
            : 'Your gallery has no ${_kind()} yet.',
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(3),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemCount: _assets.length,
      itemBuilder: (_, i) {
        final a = _assets[i];
        final on = _selected.contains(a.id);
        return GestureDetector(
          onTap: () => _toggle(a),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<ImageProvider?>(
                future: _thumb(a),
                builder: (_, snap) {
                  final broken = Container(
                    color: SV.panel2,
                    child: Icon(
                      a.type == AssetType.video
                          ? Icons.videocam_off_outlined
                          : Icons.image_not_supported_outlined,
                      color: SV.muted,
                    ),
                  );
                  if (snap.hasData && snap.data != null) {
                    return Image(
                      image: snap.data!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, e, __) {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _noteError('$e'));
                        return broken;
                      },
                    );
                  }
                  if (snap.hasError ||
                      snap.connectionState == ConnectionState.done) {
                    return broken;
                  }
                  return Container(
                    color: SV.panel2,
                    child: const Center(
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  );
                },
              ),
              if (a.type == AssetType.video)
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow,
                            color: Colors.white, size: 12),
                        Text(_fmt(a.videoDuration),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              if (on) Container(color: SV.accent.withValues(alpha: 0.25)),
              Positioned(
                right: 5,
                top: 5,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? SV.accent : Colors.black26,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: on
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    String? button,
    VoidCallback? onTap,
    String? secondButton,
    VoidCallback? onSecond,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: SV.muted),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: SV.txt, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: SV.muted)),
            if (button != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onTap, child: Text(button)),
            ],
            if (secondButton != null)
              TextButton(
                onPressed: onSecond,
                child:
                    Text(secondButton, style: TextStyle(color: SV.accent)),
              ),
          ],
        ),
      ),
    );
  }
}
