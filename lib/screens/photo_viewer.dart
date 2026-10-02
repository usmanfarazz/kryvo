import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Full-screen, swipeable image viewer with slideshow, details, unhide and
/// delete. Honours the Image Viewer settings (zoom level, hide guide, detail
/// view, fit small image, slideshow time).
class PhotoViewer extends StatefulWidget {
  final List<MediaItem> items;
  final int initialIndex;
  const PhotoViewer(
      {super.key, required this.items, required this.initialIndex});

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pc;
  late int _index;
  late bool _chrome; // top/bottom bars visible
  Timer? _slide;
  late final AppState _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pc = PageController(initialPage: _index);
    _chrome = !_app.hideGuide;
  }

  @override
  void dispose() {
    _stopSlideshow();
    _pc.dispose();
    super.dispose();
  }

  MediaItem get _item => widget.items[_index];

  void _toggleSlideshow() {
    if (_slide != null) {
      _stopSlideshow();
      setState(() {});
      return;
    }
    _app.holdLock();
    setState(() => _chrome = false);
    _slide = Timer.periodic(Duration(seconds: _app.slideshowSecs), (_) {
      if (!mounted) return;
      if (_index >= widget.items.length - 1) {
        _stopSlideshow();
        setState(() => _chrome = true);
        return;
      }
      _pc.nextPage(
          duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  void _stopSlideshow() {
    if (_slide != null) {
      _slide!.cancel();
      _slide = null;
      _app.releaseLock();
    }
  }

  Future<void> _details() async {
    final m = _item;
    final added = DateTime.fromMillisecondsSinceEpoch(m.addedAt);
    await showModalBottomSheet(
      context: context,
      backgroundColor: SV.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Details',
                  style: TextStyle(
                      color: SV.txt,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _row('Name', m.name),
              _row('Size', formatBytes(m.sizeBytes)),
              _row('Hidden on',
                  '${added.day}/${added.month}/${added.year}  ${added.hour.toString().padLeft(2, '0')}:${added.minute.toString().padLeft(2, '0')}'),
              _row('Folder', m.folder.isEmpty ? 'Main' : m.folder),
              _row('Protection', 'AES-256 encrypted on this phone'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 96,
                child: Text(k, style: TextStyle(color: SV.muted))),
            Expanded(child: Text(v, style: TextStyle(color: SV.txt))),
          ],
        ),
      );

  Future<void> _unhide() async {
    if (!await confirm(context,
        title: 'Unhide?',
        message:
            'This moves the picture back to your phone gallery (Pictures/Kryvo) and removes it from the vault.',
        ok: 'Unhide')) {
      return;
    }
    final n = await _app.unhide([_item]);
    if (!mounted) return;
    Navigator.pop(context);
    snack(context, n > 0 ? 'Moved back to gallery ✔' : 'Could not unhide');
  }

  Future<void> _delete() async {
    if (!await confirm(context,
        title: 'Move to Recycle Bin?',
        message: 'You can restore it or delete it forever from the Recycle Bin.',
        ok: 'Move to bin',
        danger: true)) {
      return;
    }
    await _app.deleteMedia(_item);
    if (!mounted) return;
    Navigator.pop(context);
    snack(context, 'Moved to Recycle Bin');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final playing = _slide != null;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _chrome
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              title: Text('${_index + 1} / ${widget.items.length}',
                  style: const TextStyle(fontSize: 16, color: Colors.white)),
              actions: [
                if (app.detailView)
                  IconButton(
                      tooltip: 'Details',
                      icon: const Icon(Icons.info_outline),
                      onPressed: _details),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _chrome = !_chrome),
        child: PageView.builder(
          controller: _pc,
          itemCount: widget.items.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => FutureBuilder<Uint8List>(
            future: app.photoBytes(widget.items[i]),
            builder: (_, snap) {
              if (snap.hasError) {
                return const Center(
                    child: Text('Could not open this picture',
                        style: TextStyle(color: Colors.white70)));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return InteractiveViewer(
                minScale: 1,
                maxScale: app.maxZoom.toDouble(),
                child: SizedBox.expand(
                  child: Image.memory(
                    snap.data!,
                    fit: app.fitSmall ? BoxFit.contain : BoxFit.scaleDown,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const Center(
                        child: Text('Could not open this picture',
                            style: TextStyle(color: Colors.white70))),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: _chrome
          ? SafeArea(
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _action(playing ? Icons.pause_circle : Icons.slideshow,
                        playing ? 'Stop' : 'Slideshow', _toggleSlideshow),
                    _action(Icons.lock_open, 'Unhide', _unhide),
                    _action(Icons.delete_outline, 'Delete', _delete),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
