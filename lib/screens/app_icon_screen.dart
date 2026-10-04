import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/disguise_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Choose the home-screen icon: a Kryvo colour, or a disguise (Calculator,
/// Notes, Clock, Games, Flashlight) that opens as a real working app and
/// only reveals the vault after the secret code is entered in it.
///
/// Every icon is free.
class AppIconScreen extends StatefulWidget {
  const AppIconScreen({super.key});

  @override
  State<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends State<AppIconScreen> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('App icon & disguise')),
      body: CustomScrollView(
        slivers: [
          _header('KRYVO ICONS', null),
          _grid(app, [
            for (final k in DisguiseService.kryvoIcons) (k.$1, k.$2)
          ]),
          _header(
              'DISGUISE ICONS',
              'Hide the vault completely. Your home screen shows a normal app '
                  '(e.g. "Clock") that really works. The vault opens only '
                  'when you enter your secret code inside it'
                  '${app.pinMode ? ' — your PIN works too' : ''}.'),
          _grid(app, [
            for (final d in DisguiseService.disguiseIcons) (d.$1, d.$2)
          ]),
          if (app.disguised)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline, color: SV.accent),
                        title: Text(
                            'How to open: ${DisguiseService.nameOf(app.appIcon)}'),
                        subtitle: Text(DisguiseService.howToOpen(app.appIcon),
                            style: TextStyle(color: SV.muted)),
                      ),
                      ListTile(
                        leading: Icon(Icons.password, color: SV.accent),
                        title: const Text('Change secret code'),
                        onTap: () => _setCode(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  // ---- Layout -------------------------------------------------------------------

  Widget _header(String title, String? note) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: SV.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4)),
              if (note != null) ...[
                const SizedBox(height: 4),
                Text(note, style: TextStyle(color: SV.muted, fontSize: 12)),
              ],
            ],
          ),
        ),
      );

  Widget _grid(AppState app, List<(String, String)> icons) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemCount: icons.length,
          itemBuilder: (_, i) => _tile(app, icons[i].$1, icons[i].$2),
        ),
      );

  Widget _tile(AppState app, String id, String name) {
    final on = id == app.appIcon;
    return GestureDetector(
      onTap: () => _pick(app, id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: SV.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: on ? SV.accent : SV.line,
            width: on ? 3 : 1,
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(
              child: Image.asset('assets/icons/$id.png', fit: BoxFit.contain),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: SV.txt,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ),
                if (on) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle, color: SV.accent, size: 16),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text('Free',
                style: TextStyle(
                    color: SV.ok, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  /// Ask for a new 4–8 digit secret code (twice). Returns true if saved.
  static Future<bool> _setCode(BuildContext context) async {
    final c1 = await promptText(context,
        title: 'Secret code',
        hint: '4 to 8 digits — you will type this in the disguise app',
        obscure: true,
        keyboard: TextInputType.number,
        maxLength: 8,
        ok: 'Next');
    if (c1 == null || !context.mounted) return false;
    if (!DisguiseService.looksLikeCode(c1)) {
      snack(context, 'The code must be 4 to 8 digits');
      return false;
    }
    final c2 = await promptText(context,
        title: 'Confirm secret code',
        obscure: true,
        keyboard: TextInputType.number,
        maxLength: 8,
        ok: 'Save');
    if (c2 == null || !context.mounted) return false;
    if (c1 != c2) {
      snack(context, 'Codes did not match');
      return false;
    }
    await DisguiseService.setCode(c1);
    if (context.mounted) snack(context, 'Secret code saved ✔');
    return true;
  }

  Future<void> _pick(AppState app, String id) async {
    if (id == app.appIcon) return;
    final name = DisguiseService.nameOf(id);
    final disguise = DisguiseService.isDisguise(id);
    if (disguise && !await DisguiseService.hasCode()) {
      if (!mounted) return;
      if (!await confirm(context,
          title: 'Set a secret code first',
          message: 'With the "$name" disguise, Kryvo opens as a real $name '
              'app. To reach your vault you will enter a secret code inside '
              'it.\n\n${DisguiseService.howToOpen(id)}',
          ok: 'Set code')) {
        return;
      }
      if (!mounted || !await _setCode(context)) return;
    }
    if (!mounted) return;
    final ok = await confirm(context,
        title: disguise ? 'Disguise as $name?' : 'Change app icon?',
        message: disguise
            ? 'Your home screen will show "$name" instead of Kryvo, and the '
                'app will open as $name.\n\nTo open your vault: '
                '${DisguiseService.howToOpen(id)}\n\nKryvo will close — open it '
                'again from the new "$name" icon (it can take a few seconds to '
                'appear).'
            : 'The home-screen icon will change to "$name". Kryvo will close — '
                'open it again from the new icon (it can take a few seconds to '
                'appear). A shortcut you placed on the home screen may need to '
                'be added again.',
        ok: 'Change');
    if (!ok || !mounted) return;
    try {
      await app.setAppIcon(id);
      if (mounted) snack(context, 'App icon changed ✔');
    } catch (e) {
      if (mounted) snack(context, 'Could not change icon: $e');
    }
  }
}
