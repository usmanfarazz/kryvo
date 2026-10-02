import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../services/intruder_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Break-in log: every wrong PIN / password, with the intruder's photo when
/// "Intruder selfie" is on.
class IntruderScreen extends StatefulWidget {
  const IntruderScreen({super.key});

  @override
  State<IntruderScreen> createState() => _IntruderScreenState();
}

class _IntruderScreenState extends State<IntruderScreen> {
  List<IntruderEvent>? _log;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().clearNewIntrusions();
    _load();
  }

  Future<void> _load() async {
    // A photo from a wrong try may still be saving; wait for it.
    await IntruderService.idle();
    if (mounted) await context.read<AppState>().loadMedia();
    final l = await IntruderService.log();
    if (mounted) setState(() => _log = l);
  }

  Future<void> _toggle(AppState app, bool on) async {
    if (on) {
      // The camera permission dialog would otherwise trigger auto-lock.
      app.holdLock();
      final ok = await IntruderService.warmUp();
      app.releaseLock();
      if (!mounted) return;
      if (!ok) {
        snack(context, 'Camera permission is needed for intruder selfies');
        return;
      }
    }
    await app.setIntruderEnabled(on);
  }

  Future<void> _clear(AppState app) async {
    if (!await confirm(context,
        title: 'Clear the break-in log?',
        message: 'All entries and intruder photos will be deleted.',
        ok: 'Clear',
        danger: true)) {
      return;
    }
    for (final m in app.media
        .where((m) => m.category == IntruderService.category)
        .toList()) {
      await app.purgeMedia(m);
    }
    await IntruderService.clear();
    await _load();
  }

  String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final photos = {
      for (final m in app.media) m.id: m,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Intruder alert'),
        actions: [
          if (_log?.isNotEmpty ?? false)
            IconButton(
                tooltip: 'Clear',
                onPressed: () => _clear(app),
                icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SwitchListTile(
            value: app.intruderEnabled,
            onChanged: (v) => _toggle(app, v),
            secondary: Icon(Icons.camera_front_outlined, color: SV.accent),
            title: const Text('Intruder selfie'),
            subtitle: Text(
                'After ${IntruderService.threshold} wrong tries in a row, '
                'silently take a front-camera photo. Photos stay encrypted '
                'in your vault.',
                style: TextStyle(color: SV.muted)),
          ),
          const SectionHeader('BREAK-IN LOG'),
          if (_log == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_log!.isEmpty)
            const EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'No break-in attempts',
              subtitle: 'Wrong PIN or password tries will be listed here.',
            )
          else
            for (final e in _log!) _entry(app, e, photos[e.photoId]),
        ],
      ),
    );
  }

  Widget _entry(AppState app, IntruderEvent e, MediaItem? m) {
    final what = e.method == 'pin' ? 'PIN' : 'password';
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: m == null ? null : () => _show(app, m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (m != null)
              SizedBox(
                height: 230,
                child: FutureBuilder<Uint8List>(
                  future: app.photoBytes(m),
                  builder: (_, s) => s.hasData
                      ? Image.memory(s.data!, fit: BoxFit.cover)
                      : Container(
                          color: SV.panel2,
                          child: const Center(
                              child: CircularProgressIndicator())),
                ),
              ),
            ListTile(
              leading: Icon(
                  m == null
                      ? Icons.no_photography_outlined
                      : Icons.warning_amber_rounded,
                  color: SV.bad),
              title: Text('Someone entered a wrong $what'),
              subtitle: Text(
                  m == null
                      ? '${_when(e.at)}  ·  no photo'
                          '${app.intruderEnabled ? '' : ' (selfie was off)'}'
                      : '${_when(e.at)}  ·  tap photo to enlarge',
                  style: TextStyle(color: SV.muted)),
            ),
          ],
        ),
      ),
    );
  }

  void _show(AppState app, MediaItem m) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<Uint8List>(
          future: app.photoBytes(m),
          builder: (_, s) => s.hasData
              ? Image.memory(s.data!, fit: BoxFit.contain)
              : const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator())),
        ),
      ),
    );
  }
}
