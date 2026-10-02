import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../services/disguise_service.dart';
import '../services/purchase_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Choose the home-screen icon: a Kryvo colour, or a disguise (Calculator,
/// Notes, Clock, Games, Flashlight) that opens as a real working app and
/// only reveals the vault after the secret code is entered in it.
///
/// Some icons are paid (see PurchaseService): they show a lock and their
/// price, and open the Google Play payment sheet when tapped.
class AppIconScreen extends StatefulWidget {
  const AppIconScreen({super.key});

  @override
  State<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends State<AppIconScreen> {
  Map<String, ProductDetails> _products = {};
  bool _storeReady = false;
  String? _shownMessage;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final ok = await PurchaseService.available();
    final p = ok ? await PurchaseService.products() : <String, ProductDetails>{};
    if (!mounted) return;
    setState(() {
      _storeReady = ok && p.isNotEmpty;
      _products = p;
    });
  }

  String? _price(String productId) => _products[productId]?.price;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // Show a purchase problem (cancelled / failed / pending) once.
    final msg = app.purchaseMessage;
    if (msg != null && msg != _shownMessage) {
      _shownMessage = msg;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) snack(context, msg);
        app.purchaseMessage = null;
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('App icon & disguise'),
        actions: [
          IconButton(
            tooltip: 'Restore purchases',
            icon: const Icon(Icons.restore),
            onPressed: _restore,
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _unlockAllCard()),
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

  // ---- Paid icons -------------------------------------------------------------

  bool get _allOwned =>
      PurchaseService.owned.contains(PurchaseService.allIconsProduct) ||
      PurchaseService.productFor.keys.every(PurchaseService.owns);

  Widget _unlockAllCard() {
    if (_allOwned) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Card(
          child: ListTile(
            leading: Icon(Icons.verified, color: SV.ok),
            title: const Text('All icons unlocked'),
            subtitle: Text('Thank you for supporting Kryvo!',
                style: TextStyle(color: SV.muted)),
          ),
        ),
      );
    }
    final price = _price(PurchaseService.allIconsProduct);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.workspace_premium, color: SV.warn, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Unlock all icons',
                            style: TextStyle(
                                color: SV.txt,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        Text(
                            'Purple, Rose, Emerald, Calculator, Notes and '
                            'Games — one payment, yours forever.',
                            style: TextStyle(color: SV.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _buy(PurchaseService.allIconsProduct),
                icon: const Icon(Icons.lock_open),
                label: Text(price == null ? 'Unlock all' : 'Unlock all · $price'),
              ),
              if (!PurchaseService.enforce)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'Test version: all icons are free until the Play Store '
                      'launch.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SV.muted, fontSize: 11)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _buy(String productId) async {
    final product = _products[productId];
    if (!_storeReady || product == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: SV.panel,
          icon: Icon(Icons.storefront, color: SV.accent, size: 36),
          title: const Text('Coming soon'),
          content: const Text(
              'Buying icons will be available when Kryvo is installed from '
              'the Google Play Store. Payment is made through Google Play.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    try {
      await PurchaseService.buy(product);
    } catch (e) {
      if (mounted) snack(context, 'Could not start the purchase');
    }
  }

  Future<void> _restore() async {
    if (!await PurchaseService.available()) {
      if (mounted) snack(context, 'Google Play is not available on this phone');
      return;
    }
    await PurchaseService.restore();
    if (mounted) snack(context, 'Checking your purchases…');
  }

  /// Sheet for a paid icon the user doesn't own yet.
  Future<void> _offer(String id, String name) async {
    final product = PurchaseService.productFor[id]!;
    final price = _price(product);
    final allPrice = _price(PurchaseService.allIconsProduct);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: SV.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/icons/$id.png', height: 84),
              const SizedBox(height: 10),
              Text('"$name" is a paid icon',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: SV.txt,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Buy it once — it stays unlocked, even offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SV.muted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, product),
                child: Text(price == null ? 'Buy $name' : 'Buy $name · $price'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(ctx, PurchaseService.allIconsProduct),
                child: Text(allPrice == null
                    ? 'Unlock all icons'
                    : 'Unlock all icons · $allPrice'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'restore'),
                child: const Text('Restore purchases'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'restore') {
      await _restore();
    } else {
      await _buy(choice);
    }
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
    final paid = PurchaseService.isPaid(id);
    final owned = PurchaseService.owns(id);
    final price = paid ? _price(PurchaseService.productFor[id]!) : null;
    return GestureDetector(
      onTap: () => _pick(app, id),
      // Long-press shows the buy sheet (also while everything is free).
      onLongPress: paid && !owned ? () => _offer(id, name) : null,
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
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: paid && !owned && PurchaseService.enforce
                          ? 0.55
                          : 1,
                      child: Image.asset('assets/icons/$id.png',
                          fit: BoxFit.contain),
                    ),
                  ),
                  if (paid && !owned)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: SV.warn,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock,
                            size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
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
            Text(
                !paid
                    ? 'Free'
                    : owned
                        ? 'Unlocked'
                        : (price ?? 'PRO'),
                style: TextStyle(
                    color: !paid || owned ? SV.ok : SV.warn,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
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
    if (!PurchaseService.canUse(id)) {
      await _offer(id, name);
      return;
    }
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
