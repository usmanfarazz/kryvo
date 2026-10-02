import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/media_item.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../services/disguise_service.dart';
import '../services/intruder_service.dart';
import '../services/media_service.dart';
import 'app_icon_screen.dart';
import 'app_lock_screen.dart';
import 'category_screen.dart';
import 'favorites_screen.dart';
import 'features_screen.dart';
import 'notes_screen.dart';
import 'intruder_screen.dart';
import 'recycle_bin_screen.dart';
import 'settings_screen.dart';
import 'vault_screen.dart';

/// The main screen once unlocked: the five "Safe" sections plus the
/// Recycle Bin, and a 3-dot menu.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _menu(BuildContext context, String v) async {
    final app = context.read<AppState>();
    switch (v) {
      case 'refresh':
        await app.loadMedia();
        if (context.mounted) snack(context, 'Refreshed');
      case 'scan':
        final r = await app.recoverLostMedia();
        if (context.mounted) await showRecoverReport(context, r);
      case 'features':
        _open(context, const FeaturesScreen());
      case 'settings':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => SettingsScreen()));
      case 'lock':
        app.lock(force: true);
    }
  }

  Future<Uint8List?> _latestIntruderPhoto(AppState app) async {
    await IntruderService.idle();
    for (final e in await IntruderService.log()) {
      if (e.photoId == null) continue;
      final m = (await MediaService.loadIndex())
          .where((m) => m.id == e.photoId)
          .firstOrNull;
      if (m != null) return app.photoBytes(m);
    }
    return null;
  }

  void _intruderAlert(BuildContext context, int n) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SV.panel,
        icon: Icon(Icons.warning_amber_rounded, color: SV.bad, size: 40),
        title: const Text('Someone tried to open Kryvo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$n wrong '
                '${n == 1 ? 'attempt was' : 'attempts were'} made since you '
                'last checked.'),
            const SizedBox(height: 12),
            // The latest intruder photo, if one was taken.
            FutureBuilder<Uint8List?>(
              future: _latestIntruderPhoto(context.read<AppState>()),
              builder: (_, s) => s.data == null
                  ? const SizedBox.shrink()
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(s.data!,
                          height: 220, fit: BoxFit.cover),
                    ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _open(context, const IntruderScreen());
            },
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  static bool _sharedDialogOpen = false;

  /// Files shared to Kryvo from another app: hide them, or throw them away.
  Future<void> _sharedDialog(BuildContext context, AppState app) async {
    final n = app.pendingShared.length;
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: SV.panel,
        icon: Icon(Icons.move_to_inbox, color: SV.accent, size: 36),
        title: Text('Hide $n shared item${n == 1 ? '' : 's'}?'),
        content: const Text(
            'They will be encrypted into your vault (photos → Safe Photo, '
            'videos → Safe Video, audio → Safe Audio).\n\n'
            'The original stays in the app you shared it from — delete it '
            'there yourself if you want it gone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hide')),
        ],
      ),
    );
    if (!context.mounted) {
      _sharedDialogOpen = false;
      return;
    }
    if (yes == true) {
      final added = await withProgress(context, 'Encrypting…',
          (update) => app.importShared(onProgress: update));
      if (context.mounted) snack(context, '$added item${added == 1 ? '' : 's'} hidden ✔');
    } else {
      await app.discardShared();
    }
    _sharedDialogOpen = false;
  }

  void _open(BuildContext context, Widget page) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    int n(String c) => app.itemsOf(c).length;

    if (app.pendingShared.isNotEmpty && !_sharedDialogOpen) {
      _sharedDialogOpen = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _sharedDialog(context, app));
    }

    final intrusions = app.decoy ? 0 : app.takeNewIntrusions();
    if (intrusions > 0) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _intruderAlert(context, intrusions));
    }

    final tiles = <_Tile>[
      _Tile(MediaCat.title(MediaCat.photo), Icons.photo_library_rounded,
          '${n(MediaCat.photo)} photos', const Color(0xFF3D8BFF),
          () => _open(context, CategoryScreen(cat: MediaCat.photo))),
      _Tile(MediaCat.title(MediaCat.video), Icons.video_library_rounded,
          '${n(MediaCat.video)} videos', const Color(0xFFE53935),
          () => _open(context, CategoryScreen(cat: MediaCat.video))),
      _Tile(MediaCat.title(MediaCat.web), Icons.public_rounded,
          '${n(MediaCat.web)} images', const Color(0xFF00BCD4),
          () => _open(context, CategoryScreen(cat: MediaCat.web))),
      _Tile(MediaCat.title(MediaCat.audio), Icons.library_music_rounded,
          '${n(MediaCat.audio)} files', const Color(0xFFFF9800),
          () => _open(context, CategoryScreen(cat: MediaCat.audio))),
      _Tile('Safe Password', Icons.key_rounded,
          '${app.entries.where((e) => e.category != 'Notes').length} saved',
          const Color(0xFF22C55E),
          () => _open(context, VaultScreen())),
      _Tile('Recycle Bin', Icons.delete_sweep_rounded,
          '${app.trash.length} items', const Color(0xFF8B5CF6),
          () => _open(context, RecycleBinScreen())),
      _Tile('Favourites', Icons.star_rounded,
          '${app.favorites.length} items', const Color(0xFFEAB308),
          () => _open(context, const FavoritesScreen())),
      _Tile('Private Notes', Icons.sticky_note_2_rounded,
          () {
            final n = app.view(category: 'Notes').length;
            return '$n note${n == 1 ? '' : 's'}';
          }(),
          const Color(0xFF14B8A6),
          () => _open(context, const NotesScreen())),
      // Hidden in the decoy vault: they would give the real vault away.
      if (!app.decoy) ...[
      _Tile('Intruder Alert', Icons.camera_front_rounded,
          app.intruderEnabled ? 'Selfie on' : 'Break-in log',
          const Color(0xFFEF4444),
          () => _open(context, const IntruderScreen())),
      _Tile('App Lock', Icons.lock_person_rounded,
          'Lock WhatsApp, Gallery…', const Color(0xFF0EA5E9),
          () => _open(context, const AppLockScreen())),
      _Tile('Change Icon', Icons.calculate_rounded,
          app.disguised
              ? 'Now: ${DisguiseService.nameOf(app.appIcon)}'
              : 'Calculator, Clock, Game…',
          const Color(0xFFF59E0B),
          () => _open(context, const AppIconScreen())),
      ],
    ];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: app.registerActivity,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset('assets/kryvo_logo.png',
                    width: 34,
                    height: 34,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.shield, color: SV.accent)),
              ),
              const SizedBox(width: 10),
              const Text('Kryvo'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Lock now',
              icon: const Icon(Icons.lock_outline),
              onPressed: () => app.lock(force: true),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              color: SV.panel,
              onSelected: (v) => _menu(context, v),
              itemBuilder: (_) => [
                for (final (v, label) in [
                  ('refresh', 'Refresh'),
                  if (!app.decoy) ('scan', 'Media scanning'),
                  if (!app.decoy) ('features', 'All features'),
                  ('settings', 'Settings'),
                  ('lock', 'Lock now'),
                ])
                  PopupMenuItem(value: v, child: Text(tr(label))),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _Banner(total: app.media.where((m) => !m.inTrash).length),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.45,
              children: [for (final t in tiles) _TileCard(t)],
            ),
            const SizedBox(height: 14),
            if (!app.decoy)
            Card(
              child: ListTile(
                leading: Icon(Icons.auto_awesome, color: SV.accent),
                title: Text(tr('All features')),
                subtitle: Text(tr('Tap any feature to open it'),
                    style: TextStyle(color: SV.muted)),
                trailing: Icon(Icons.chevron_right, color: SV.muted),
                onTap: () => _open(context, const FeaturesScreen()),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text('Encrypted on this phone · Built by Faraz Labs',
                  style: TextStyle(color: SV.muted, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final int total;
  const _Banner({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [SV.accent, Color.lerp(SV.accent, Colors.black, 0.45)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.verified_user,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Your private vault'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('$total items protected with AES-256',
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile {
  final String title;
  final IconData icon;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  _Tile(this.title, this.icon, this.subtitle, this.color, this.onTap);
}

class _TileCard extends StatelessWidget {
  final _Tile t;
  const _TileCard(this.t);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SV.panel,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: t.onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: SV.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: t.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(t.icon, color: t.color, size: 28),
              ),
              const Spacer(),
              Text(tr(t.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: SV.txt,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(t.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: SV.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
