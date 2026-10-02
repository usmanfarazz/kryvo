import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
import '../services/resume_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Plays a hidden video OR audio file with full controls: seek bar with
/// current time / total time, ±10 s, speed, unhide and delete.
///
/// The file is decrypted to a temporary copy only while playing; that copy is
/// deleted as soon as the screen closes.
class VideoPlayerScreen extends StatefulWidget {
  final MediaItem item;
  const VideoPlayerScreen({super.key, required this.item});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _c;
  File? _temp;
  bool _loading = true;
  String? _error;
  bool _controls = true;
  Timer? _hide;
  double _speed = 1.0;
  double? _dragMs; // while the user drags the seek bar
  late final AppState _app;

  bool get _audio => widget.item.isAudio;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _app.holdLock(); // don't auto-lock while watching
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await _app.decryptToTemp(widget.item);
      final c = VideoPlayerController.file(f);
      await c.initialize();
      c.addListener(_tick);
      if (!mounted) {
        await c.dispose();
        _deleteQuietly(f);
        return;
      }
      setState(() {
        _temp = f;
        _c = c;
        _loading = false;
      });
      // Continue where it was stopped last time.
      final resume = await ResumeService.positionOf(widget.item.id);
      if (resume != null && resume < c.value.duration.inMilliseconds) {
        await c.seekTo(Duration(milliseconds: resume));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Continuing from ${_fmt(Duration(milliseconds: resume))}'),
            action: SnackBarAction(
                label: 'Start over', onPressed: () => c.seekTo(Duration.zero)),
          ));
        }
      }
      await c.play();
      _scheduleHide();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _deleteQuietly(File? f) {
    try {
      f?.deleteSync();
    } catch (_) {}
  }

  @override
  void dispose() {
    _hide?.cancel();
    final c = _c;
    if (c != null && c.value.isInitialized) {
      ResumeService.save(widget.item.id, c.value.position, c.value.duration);
    }
    _c?.removeListener(_tick);
    _c?.dispose();
    _deleteQuietly(_temp);
    _app.releaseLock();
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (_audio) return; // audio keeps its controls
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) {
        setState(() => _controls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  Future<void> _playPause() async {
    final c = _c;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      if (c.value.position >= c.value.duration) {
        await c.seekTo(Duration.zero);
      }
      await c.play();
    }
    _scheduleHide();
  }

  Future<void> _skip(int seconds) async {
    final c = _c;
    if (c == null) return;
    var t = c.value.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (t > c.value.duration) t = c.value.duration;
    await c.seekTo(t);
    _scheduleHide();
  }

  Future<void> _pickSpeed() async {
    final s = await pickOne<double>(context,
        title: 'Playback speed',
        values: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
        label: (v) => v == 1.0 ? 'Normal' : '${v}x',
        selected: _speed);
    if (s == null) return;
    await _c?.setPlaybackSpeed(s);
    setState(() => _speed = s);
  }

  Future<void> _unhide() async {
    final m = widget.item;
    if (m.isAudio) {
      if (!await confirm(context,
          title: 'Unhide audio?',
          message: 'The audio goes back to your phone (Music/Kryvo) and is '
              'removed from the vault.',
          ok: 'Unhide')) {
        return;
      }
      await _c?.pause();
      if (await _app.unhide([m]) > 0) {
        if (!mounted) return;
        Navigator.pop(context);
        snack(context, 'Audio saved to Music/Kryvo ✔');
        return;
      }
      // Older Android: let the user choose where to save it.
      final temp = _temp;
      if (temp == null) return;
      _app.holdLock();
      String? path;
      try {
        path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save audio',
          fileName: m.name,
          bytes: await temp.readAsBytes(),
        );
      } finally {
        _app.releaseLock();
      }
      if (path == null) return;
      await _app.purgeMedia(m);
      if (!mounted) return;
      Navigator.pop(context);
      snack(context, 'Audio saved ✔');
      return;
    }
    if (!await confirm(context,
        title: 'Unhide video?',
        message:
            'This moves the video back to your phone gallery (Movies/Kryvo) and removes it from the vault.',
        ok: 'Unhide')) {
      return;
    }
    await _c?.pause();
    final n = await _app.unhide([m]);
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
    await _app.deleteMedia(widget.item);
    if (!mounted) return;
    Navigator.pop(context);
    snack(context, 'Moved to Recycle Bin');
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: _audio ? SV.bg : Colors.black,
      body: SafeArea(
        child: _loading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: SV.accent),
                    const SizedBox(height: 14),
                    Text('Decrypting…',
                        style: TextStyle(
                            color: _audio ? SV.txt : Colors.white70)),
                  ],
                ),
              )
            : _error != null || c == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not play this file\n${_error ?? ''}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70)),
                    ),
                  )
                : _audio
                    ? _audioBody(c)
                    : _videoBody(c),
      ),
    );
  }

  // ---- Video layout ----------------------------------------------------------

  Widget _videoBody(VideoPlayerController c) {
    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio:
                  c.value.aspectRatio <= 0 ? 16 / 9 : c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
          AnimatedOpacity(
            opacity: _controls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_controls,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black54,
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black87
                    ],
                    stops: [0, 0.2, 0.7, 1],
                  ),
                ),
                child: Column(
                  children: [
                    _topBar(Colors.white),
                    const Spacer(),
                    _centerButtons(c, Colors.white),
                    const Spacer(),
                    _seekBar(c, Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Audio layout ----------------------------------------------------------

  Widget _audioBody(VideoPlayerController c) {
    return Column(
      children: [
        _topBar(SV.txt),
        const Spacer(),
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            gradient: LinearGradient(
              colors: [SV.accent, Color.lerp(SV.accent, Colors.black, 0.45)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(Icons.music_note, color: Colors.white, size: 110),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(widget.item.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: SV.txt, fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        const Spacer(),
        _seekBar(c, SV.txt),
        _centerButtons(c, SV.txt),
        const SizedBox(height: 24),
      ],
    );
  }

  // ---- Shared pieces -----------------------------------------------------------

  Widget _topBar(Color fg) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
              icon: Icon(Icons.arrow_back, color: fg),
              onPressed: () => Navigator.pop(context)),
          Expanded(
            child: Text(widget.item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          ),
          IconButton(
              tooltip: 'Speed',
              icon: Icon(Icons.speed, color: fg),
              onPressed: _pickSpeed),
          IconButton(
              tooltip: 'Unhide',
              icon: Icon(Icons.lock_open, color: fg),
              onPressed: _unhide),
          IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline, color: fg),
              onPressed: _delete),
        ],
      ),
    );
  }

  Widget _centerButtons(VideoPlayerController c, Color fg) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
            iconSize: 36,
            icon: Icon(Icons.replay_10, color: fg),
            onPressed: () => _skip(-10)),
        const SizedBox(width: 18),
        GestureDetector(
          onTap: _playPause,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: SV.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white, size: 42),
          ),
        ),
        const SizedBox(width: 18),
        IconButton(
            iconSize: 36,
            icon: Icon(Icons.forward_10, color: fg),
            onPressed: () => _skip(10)),
      ],
    );
  }

  Widget _seekBar(VideoPlayerController c, Color fg) {
    final total = c.value.duration.inMilliseconds.toDouble();
    final pos = (_dragMs ?? c.value.position.inMilliseconds.toDouble())
        .clamp(0.0, total <= 0 ? 0.0 : total)
        .toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              activeTrackColor: SV.accent,
              inactiveTrackColor: fg.withValues(alpha: 0.25),
              thumbColor: SV.accent,
              overlayColor: SV.accent.withValues(alpha: 0.2),
            ),
            child: Slider(
              min: 0,
              max: total <= 0 ? 1.0 : total,
              value: total <= 0 ? 0.0 : pos,
              onChangeStart: (_) => _hide?.cancel(),
              onChanged: (v) => setState(() => _dragMs = v),
              onChangeEnd: (v) async {
                await c.seekTo(Duration(milliseconds: v.round()));
                setState(() => _dragMs = null);
                _scheduleHide();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text(_fmt(Duration(milliseconds: pos.round())),
                    style: TextStyle(color: fg, fontSize: 12)),
                const Spacer(),
                Text(_fmt(c.value.duration),
                    style: TextStyle(color: fg, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
