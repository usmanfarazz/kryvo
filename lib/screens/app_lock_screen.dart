import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_lock_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// App Lock: choose apps on the phone (WhatsApp, Gallery…) that need a PIN to
/// open. The apps stay where they are — they just get a lock screen.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen>
    with WidgetsBindingObserver {
  AppLockState? _state;
  List<LockableApp>? _apps;
  Set<String> _locked = {};
  String _query = '';
  bool _waitingForSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    AppLockService.apps().then((a) {
      if (mounted) setState(() => _apps = a);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_waitingForSettings) context.read<AppState>().releaseLock();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Back from the phone's settings page: re-check the permissions.
    if (s == AppLifecycleState.resumed && _waitingForSettings) {
      _waitingForSettings = false;
      context.read<AppState>().releaseLock();
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final st = await AppLockService.state();
    if (!mounted) return;
    setState(() {
      _state = st;
      _locked = {...st.locked};
    });
  }

  Future<void> _openSettings(Future<void> Function() open) async {
    // Going to the phone's settings would otherwise lock Kryvo.
    if (!_waitingForSettings) context.read<AppState>().holdLock();
    _waitingForSettings = true;
    await open();
  }

  Future<bool> _setPin() async {
    final p1 = await promptText(context,
        title: 'App Lock PIN',
        hint: '4 to 8 digits — asked when a locked app opens',
        obscure: true,
        keyboard: TextInputType.number,
        maxLength: 8,
        ok: 'Next');
    if (p1 == null || !mounted) return false;
    if (!RegExp(r'^\d{4,8}$').hasMatch(p1)) {
      snack(context, 'PIN must be 4 to 8 digits');
      return false;
    }
    final p2 = await promptText(context,
        title: 'Confirm App Lock PIN',
        obscure: true,
        keyboard: TextInputType.number,
        maxLength: 8,
        ok: 'Save');
    if (p2 == null || !mounted) return false;
    if (p1 != p2) {
      snack(context, 'PINs did not match');
      return false;
    }
    await AppLockService.setPin(p1);
    if (mounted) snack(context, 'App Lock PIN saved ✔');
    await _refresh();
    return true;
  }

  Future<void> _toggleEnabled(bool on) async {
    final st = _state!;
    if (on) {
      if (!st.permissionsOk) {
        snack(context, 'First allow the 2 permissions above');
        return;
      }
      if (!st.hasPin && !await _setPin()) return;
    }
    final ok = await AppLockService.setEnabled(on);
    if (!ok && mounted) snack(context, 'Could not start App Lock');
    await _refresh();
  }

  Future<void> _toggleApp(String pkg, bool lock) async {
    setState(() => lock ? _locked.add(pkg) : _locked.remove(pkg));
    await AppLockService.setLocked(_locked);
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    return Scaffold(
      appBar: AppBar(title: const Text('App Lock')),
      body: st == null
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(st)),
                if (_apps == null)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else
                  _appList(),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
    );
  }

  Widget _header(AppLockState st) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
              'Lock apps like WhatsApp or Gallery with a PIN. The apps stay on '
              'your phone as normal — when someone opens one, Kryvo asks for '
              'your App Lock PIN first.',
              style: TextStyle(color: SV.muted)),
        ),
        if (!st.permissionsOk) ...[
          const SectionHeader('STEP 1 · ALLOW 2 PERMISSIONS'),
          _permission(
              'Usage access',
              'Lets Kryvo see which app is opened',
              st.usage,
              () => _openSettings(AppLockService.openUsageSettings)),
          _permission(
              'Display over other apps',
              'Lets Kryvo show the lock screen over a locked app',
              st.overlay,
              () => _openSettings(AppLockService.openOverlaySettings)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
                'In the list that opens, find Kryvo and switch it on, then '
                'come back here.',
                style: TextStyle(color: SV.muted, fontSize: 12)),
          ),
        ],
        const SectionHeader('APP LOCK'),
        SwitchListTile(
          value: st.enabled,
          onChanged: _toggleEnabled,
          activeColor: SV.accent,
          secondary: Icon(Icons.lock_person_outlined, color: SV.accent),
          title: const Text('App Lock'),
          subtitle: Text(
              st.enabled
                  ? '${_locked.length} app${_locked.length == 1 ? '' : 's'} locked'
                  : 'Off',
              style: TextStyle(color: SV.muted)),
        ),
        ListTile(
          leading: Icon(Icons.dialpad, color: SV.accent),
          title: Text(st.hasPin ? 'Change App Lock PIN' : 'Set App Lock PIN'),
          subtitle: Text('Separate from your Kryvo vault PIN',
              style: TextStyle(color: SV.muted)),
          onTap: _setPin,
        ),
        SwitchListTile(
          value: st.fingerprint,
          onChanged: (v) async {
            await AppLockService.setFingerprint(v);
            await _refresh();
          },
          activeColor: SV.accent,
          secondary: Icon(Icons.fingerprint, color: SV.accent),
          title: const Text('Unlock with fingerprint'),
        ),
        const SectionHeader('CHOOSE APPS TO LOCK'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search apps',
            ),
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
          ),
        ),
      ],
    );
  }

  Widget _permission(
      String title, String subtitle, bool granted, VoidCallback onTap) {
    return ListTile(
      leading: Icon(granted ? Icons.check_circle : Icons.error_outline,
          color: granted ? SV.ok : SV.warn),
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: SV.muted)),
      trailing: granted
          ? null
          : FilledButton(onPressed: onTap, child: const Text('Allow')),
    );
  }

  Widget _appList() {
    final apps = _apps!
        .where((a) => _query.isEmpty || a.name.toLowerCase().contains(_query))
        .toList();
    return SliverList.builder(
      itemCount: apps.length,
      itemBuilder: (_, i) {
        final a = apps[i];
        final on = _locked.contains(a.pkg);
        return SwitchListTile(
          value: on,
          onChanged: (v) => _toggleApp(a.pkg, v),
          activeColor: SV.accent,
          secondary: Image.memory(a.icon, width: 40, height: 40),
          title: Text(a.name),
          subtitle: on
              ? Text('Locked', style: TextStyle(color: SV.accent, fontSize: 12))
              : null,
        );
      },
    );
  }
}
