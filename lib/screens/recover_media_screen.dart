import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../services/media_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Recover lost media:
///   * scan the vault for hidden files that went missing from the list, and
///   * bring back items deleted from the Recycle Bin (kept for
///     MediaService.keepErasedDays days) into the Recycle Bin.
class RecoverMediaScreen extends StatefulWidget {
  const RecoverMediaScreen({super.key});

  @override
  State<RecoverMediaScreen> createState() => _RecoverMediaScreenState();
}

class _RecoverMediaScreenState extends State<RecoverMediaScreen> {
  List<MediaItem>? _erased;
  final Set<String> _sel = {};
  final Map<String, Future<Uint8List>> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await MediaService.expireErased();
    final l = await MediaService.loadErased();
    if (!mounted) return;
    setState(() {
      _erased = l;
      _sel.removeWhere((id) => !l.any((m) => m.id == id));
    });
  }

  Future<void> _scan(AppState app) async {
    final r = await withProgress(
        context, 'Searching the vault for lost media…', (_) => app.recoverLostMedia());
    if (mounted) await showRecoverReport(context, r);
  }

  List<MediaItem> get _selected =>
      (_erased ?? const []).where((m) => _sel.contains(m.id)).toList();

  Future<void> _restore(AppState app) async {
    final list = _selected;
    await app.restoreErased(list);
    await _load();
    if (mounted) {
      snack(context,
          '${list.length} item${list.length == 1 ? '' : 's'} moved back to the Recycle Bin ✔');
    }
  }

  Future<void> _eraseNow() async {
    final list = _selected;
    if (!await confirm(context,
        title: 'Erase ${list.length} item${list.length == 1 ? '' : 's'} now?',
        message: 'They will be gone forever and cannot be recovered.',
        ok: 'Erase',
        danger: true)) {
      return;
    }
    await MediaService.eraseNow(list);
    await _load();
  }

  int _daysLeft(MediaItem m) {
    final end = DateTime.fromMillisecondsSinceEpoch(m.deletedAt)
        .add(const Duration(days: MediaService.keepErasedDays));
    final d = end.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final erased = _erased;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recover lost media'),
        actions: [
          if (erased != null && erased.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                if (_sel.length == erased.length) {
                  _sel.clear();
                } else {
                  _sel.addAll(erased.map((m) => m.id));
                }
              }),
              child: Text(_sel.length == erased.length ? 'None' : 'All',
                  style: TextStyle(color: SV.accent)),
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Card(
                child: ListTile(
                  leading: Icon(Icons.manage_search, color: SV.accent, size: 30),
                  title: const Text('Scan for lost files'),
                  subtitle: Text(
                      'Finds hidden files that went missing from your vault '
                      '(e.g. the app closed during an import) and brings them '
                      'back.',
                      style: TextStyle(color: SV.muted)),
                  trailing: FilledButton(
                      onPressed: () => _scan(app), child: const Text('Scan')),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(
              child: SectionHeader('DELETED FROM RECYCLE BIN')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(
                  'Items you deleted permanently are kept here, encrypted, for '
                  '${MediaService.keepErasedDays} days. Select them to move '
                  'them back to the Recycle Bin.',
                  style: TextStyle(color: SV.muted, fontSize: 12)),
            ),
          ),
          if (erased == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (erased.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.delete_outline,
                title: 'Nothing here',
                subtitle: 'Items deleted from the Recycle Bin will show up here.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 90),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: erased.length,
                itemBuilder: (_, i) => _tile(erased[i]),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _sel.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _restore(app),
                        icon: const Icon(Icons.restore),
                        label: Text('Restore (${_sel.length})'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _eraseNow,
                      icon: Icon(Icons.delete_forever, color: SV.bad),
                      label: Text('Erase', style: TextStyle(color: SV.bad)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _tile(MediaItem m) {
    final on = _sel.contains(m.id);
    final days = _daysLeft(m);
    return GestureDetector(
      onTap: () => setState(() => on ? _sel.remove(m.id) : _sel.add(m.id)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List>(
              future: _thumbs.putIfAbsent(
                  m.id, () => MediaService.readErasedThumb(m)),
              builder: (_, s) {
                if (s.hasData && s.data!.isNotEmpty) {
                  return Image.memory(s.data!, fit: BoxFit.cover);
                }
                return Container(
                  color: SV.panel2,
                  child: Icon(
                      m.isVideo
                          ? Icons.videocam
                          : m.isAudio
                              ? Icons.music_note
                              : Icons.image,
                      color: SV.muted),
                );
              },
            ),
            if (on) Container(color: SV.accent.withValues(alpha: 0.3)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('$days day${days == 1 ? '' : 's'} left',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ),
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
      ),
    );
  }
}
