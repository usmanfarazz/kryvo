import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'secure_store.dart';

/// Paid app icons, sold with Google Play Billing (one-time purchases).
///
/// Payment happens entirely inside the Google Play app; Kryvo itself needs no
/// internet permission. Bought icons are remembered on the phone, so they
/// keep working offline, and "Restore purchases" brings them back after a
/// reinstall (they are tied to the Google account).
///
/// Before launch:
///   1. In Play Console → Monetize → In-app products, create one-time
///      products with exactly the ids in [productFor] / [allIconsProduct]
///      and set their prices.
///   2. Set [enforce] to true.
class PurchaseService {
  /// While false every icon can be used for free (development / before the
  /// Play Store launch); paid icons still show their "PRO" badge and the Buy
  /// sheet. Set to true for the Play Store release.
  static const enforce = false;

  /// Unlocks every paid icon at once.
  static const allIconsProduct = 'icons_all';

  /// Icon id → Play Console product id. Icons not listed here are free.
  static const productFor = {
    'purple': 'icon_purple',
    'rose': 'icon_rose',
    'green': 'icon_emerald',
    'calc': 'icon_calculator',
    'notes': 'icon_notes',
    'game': 'icon_games',
  };

  static bool isPaid(String iconId) => productFor.containsKey(iconId);

  static final _s = SecureStore.instance;
  static const _ownedKey = 'kryvo.purchases.owned';

  static final _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Product ids the user owns (cached on the phone).
  static Set<String> owned = {};

  /// Called whenever [owned] changes or a purchase fails / is cancelled.
  static void Function(String? error)? onUpdate;

  static bool owns(String iconId) {
    final p = productFor[iconId];
    if (p == null) return true; // free icon
    return owned.contains(p) || owned.contains(allIconsProduct);
  }

  /// May the user switch to this icon right now?
  static bool canUse(String iconId) => !enforce || owns(iconId);

  static Future<void> init() async {
    final s = await _s.read(key: _ownedKey);
    if (s != null) owned = {...(jsonDecode(s) as List).cast<String>()};
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      debugPrint('Kryvo purchases: $e');
    });
  }

  static Future<void> _save() =>
      _s.write(key: _ownedKey, value: jsonEncode(owned.toList()));

  static Future<void> _onPurchases(List<PurchaseDetails> list) async {
    String? error;
    var changed = false;
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          changed |= owned.add(p.productID);
        case PurchaseStatus.error:
          error = p.error?.message ?? 'Purchase failed';
        case PurchaseStatus.canceled:
          error = 'Purchase cancelled';
        case PurchaseStatus.pending:
          error = 'Payment is pending — the icon unlocks once it completes';
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
    if (changed) await _save();
    onUpdate?.call(error);
  }

  /// Is Google Play Billing reachable (false on phones without Play Store,
  /// or when the app wasn't installed from Play)?
  static Future<bool> available() async {
    try {
      return await _iap.isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Prices from Play Console, keyed by product id. Empty if unavailable.
  static Future<Map<String, ProductDetails>> products() async {
    if (!await available()) return {};
    try {
      final r = await _iap.queryProductDetails(
          {...productFor.values, allIconsProduct});
      return {for (final d in r.productDetails) d.id: d};
    } catch (_) {
      return {};
    }
  }

  /// Opens the Google Play payment sheet. The result arrives via [onUpdate].
  static Future<bool> buy(ProductDetails product) =>
      _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));

  static Future<void> restore() => _iap.restorePurchases();
}
