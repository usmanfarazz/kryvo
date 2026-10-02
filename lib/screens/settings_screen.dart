import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../services/biometric_service.dart';
import '../services/disguise_service.dart';
import '../services/full_backup_service.dart';
import '../services/pin_service.dart';
import '../services/settings_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'app_icon_screen.dart';
import 'app_lock_screen.dart';
import 'feedback_screen.dart';
import 'intruder_screen.dart';
import 'language_screen.dart';
import 'recover_media_screen.dart';
import 'storage_screen.dart';
import 'settings_pages.dart';
import 'theme_picker_screen.dart';

/// Settings, laid out like a gallery-vault app:
/// Recovery & media · Slideshow · Screen Lock Settings · Image Viewer Settings
/// · App Settings · Backup · Other Settings.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _bioOn = false;
  bool _bioSupported = false;
  String _question = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await BiometricService.isEnabled();
    final sup = await BiometricService.deviceSupportsBiometrics();
    final q = await PinService.question();
    if (!mounted) return;
    setState(() {
      _bioOn = on;
      _bioSupported = sup;
      _question = q;
    });
  }

  Future<String?> _askMasterPassword([String title = 'Confirm master password']) =>
      promptText(context,
          title: title, hint: 'Master password', obscure: true, ok: 'OK');

  // ---- Recovery ---------------------------------------------------------------

  Future<void> _recoveryKey(AppState app) async {
    if (app.recoveryEnabled) {
      final choice = await pickOne<String>(context,
          title: 'Recovery key',
          values: const ['regen', 'off'],
          label: (v) => v == 'regen'
              ? 'Generate a new recovery key'
              : 'Turn off recovery key');
      if (choice == 'off') {
        await app.disableRecovery();
        if (mounted) snack(context, 'Recovery key turned off');
        return;
      }
      if (choice != 'regen') return;
    }
    final pw = await _askMasterPassword();
    if (pw == null || !mounted) return;
    final key = await app.enableRecovery(pw);
    if (!mounted) return;
    if (key == null) {
      snack(context, 'Wrong master password');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: SV.panel,
        title: const Text('Your recovery key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Write this down and keep it safe. It is the only way back in '
                'if you forget your master password. It will not be shown again.',
                style: TextStyle(color: SV.muted, fontSize: 13)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SV.panel2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SV.line),
              ),
              child: SelectableText(key,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      letterSpacing: 1.5)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: key));
              snack(ctx, 'Recovery key copied');
            },
            child: const Text('Copy'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("I've saved it")),
        ],
      ),
    );
  }

  // ---- Screen lock ------------------------------------------------------------

  Future<String?> _askNewPin() async {
    final p1 = await promptText(context,
        title: 'New PIN',
        hint: '4 to 8 digits',
        obscure: true,
        keyboard: TextInputType.number,
        maxLength: 8,
        ok: 'Next');
    if (p1 == null || !mounted) return null;
    if (!RegExp(r'^\d{4,8}$').hasMatch(p1)) {
      snack(context, 'PIN must be 4 to 8 digits');
      return null;
    }
    final p2 = await promptText(context,
        title: 'Confirm PIN',
        obscure: true,
        keyboard: TextInputType.number,
        maxLength: 8,
        ok: 'Save');
    if (p2 == null || !mounted) return null;
    if (p1 != p2) {
      snack(context, 'PINs did not match');
      return null;
    }
    return p1;
  }

  Future<void> _setupPin(AppState app) async {
    final mp = await _askMasterPassword();
    if (mp == null || !mounted) return;
    if (!await app.verifyMasterPassword(mp)) {
      if (mounted) snack(context, 'Wrong master password');
      return;
    }
    final pin = await _askNewPin();
    if (pin == null) return;
    final err = await app.enablePin(pin, mp);
    if (!mounted) return;
    if (err != null) {
      snack(context, err);
      return;
    }
    snack(context, 'PIN lock is on ✔');
    if (_question.isEmpty) await _setQuestion();
  }

  Future<void> _lockType(AppState app) async {
    final pick = await pickOne<String>(context,
        title: 'Screen lock type',
        values: const ['password', 'pin'],
        selected: app.pinMode ? 'pin' : 'password',
        label: (v) => v == 'pin' ? 'PIN (4–8 digits)' : 'Master password');
    if (pick == null || !mounted) return;
    if (pick == 'password' && app.pinMode) {
      await app.disablePin();
      if (mounted) snack(context, 'Lock type: master password');
    } else if (pick == 'pin') {
      await _setupPin(app);
    }
  }

  Future<void> _changePassword(AppState app) async {
    final current = await _askMasterPassword('Current master password');
    if (current == null || !mounted) return;
    final n1 = await promptText(context,
        title: 'New master password',
        hint: 'At least 8 characters',
        obscure: true,
        ok: 'Next');
    if (n1 == null || !mounted) return;
    final n2 = await promptText(context,
        title: 'Confirm new password', obscure: true, ok: 'Change');
    if (n2 == null || !mounted) return;
    if (n1 != n2) {
      snack(context, 'New passwords do not match');
      return;
    }
    final had = app.recoveryEnabled;
    final err = await app.changeMasterPassword(current, n1);
    if (!mounted) return;
    snack(
        context,
        err ??
            (had
                ? 'Password changed. Set up a new recovery key.'
                : 'Master password changed ✔'));
  }

  Future<void> _toggleFingerprint(AppState app, bool on) async {
    if (!on) {
      await BiometricService.disable();
      await _load();
      if (mounted) snack(context, 'Fingerprint unlock off');
      return;
    }
    if (!_bioSupported) {
      snack(context, 'No fingerprint / face is set up on this phone');
      return;
    }
    final pw = await _askMasterPassword();
    if (pw == null || !mounted) return;
    if (!await app.verifyMasterPassword(pw)) {
      if (mounted) snack(context, 'Wrong master password');
      return;
    }
    app.holdLock();
    final bool ok;
    try {
      ok = await BiometricService.authenticate('Enable fingerprint unlock');
    } finally {
      app.releaseLock();
    }
    if (!ok) return;
    await BiometricService.enable(pw);
    await _load();
    if (mounted) snack(context, 'Fingerprint unlock on ✔');
  }

  static const _questions = [
    'What is your favourite food?',
    'What was the name of your first school?',
    'What is your mother\'s birthplace?',
    'What is your childhood nickname?',
    'What is your favourite cricketer?',
  ];

  Future<void> _setQuestion() async {
    final q = await pickOne<String>(context,
        title: 'Choose a security question',
        values: _questions,
        label: (v) => v,
        selected: _question.isEmpty ? null : _question);
    if (q == null || !mounted) return;
    final a = await promptText(context,
        title: q, hint: 'Your answer', ok: 'Save');
    if (a == null || a.trim().isEmpty || !mounted) return;
    await PinService.setQuestion(q, a);
    await _load();
    if (mounted) {
      snack(context, 'Security question saved. Use it if you forget your PIN.');
    }
  }

  Future<void> _setHint(AppState app) async {
    final h = await promptText(context,
        title: 'PIN hint',
        hint: 'Shown on the lock screen (never the PIN itself)',
        initial: app.pinHint,
        ok: 'Save');
    if (h == null || !mounted) return;
    await app.setPinHint(h);
    if (mounted) snack(context, h.trim().isEmpty ? 'Hint removed' : 'Hint saved');
  }

  // ---- Backup ---------------------------------------------------------------------

  Future<void> _backup(AppState app) async {
    final go = await confirm(context,
        title: 'Full backup',
        message: 'Saves ONE encrypted file with all your passwords, photos, '
            'videos, web images, audio and folders.\n\n'
            'Next, choose where to save it — pick "Drive" to keep it in your '
            'Google Drive, or your phone / USB.\n\n'
            'It can only be opened with your master password.',
        ok: 'Continue');
    if (!go || !mounted) return;
    final err = await withProgress(
        context, 'Preparing backup…', (update) => app.createFullBackup(onProgress: update));
    if (mounted) snack(context, err ?? 'Encrypted backup saved ✔');
  }

  Future<void> _restore(AppState app) async {
    if (!await confirm(context,
        title: 'Restore from backup?',
        message: 'Pick a Kryvo backup (from Drive or your phone). Its '
            'passwords, photos, videos and audio are ADDED to this vault — '
            'nothing here is deleted.',
        ok: 'Choose file')) {
      return;
    }
    app.holdLock();
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(type: FileType.any);
    } finally {
      app.releaseLock();
    }
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    final file = File(path);
    try {
      if (!await FullBackupService.isFullBackup(file)) {
        // Older passwords-only backup (.svbackup).
        await _restoreOld(app, file);
        return;
      }
      final pw = await promptText(context,
          title: 'Backup password',
          hint: 'The master password used when this backup was made',
          obscure: true,
          ok: 'Restore');
      if (pw == null || !mounted) return;
      final msg = await withProgress(context, 'Opening backup…',
          (update) => app.restoreFullBackup(file, pw, onProgress: update));
      if (mounted) snack(context, msg);
    } on WrongPassword {
      if (mounted) snack(context, 'Wrong password for this backup');
    } on FormatException {
      if (mounted) snack(context, 'This is not a Kryvo backup file');
    } catch (e) {
      if (mounted) snack(context, 'Restore failed: $e');
    } finally {
      // The picker made a plain copy in Kryvo's cache; remove it.
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// Old passwords-only backups replace the password vault (then unlock
  /// with that backup's master password).
  Future<void> _restoreOld(AppState app, File file) async {
    if (!await confirm(context,
        title: 'Older backup',
        message: 'This is an older passwords-only backup. It REPLACES the '
            "passwords in this vault; then unlock with that backup's master "
            'password.',
        ok: 'Replace',
        danger: true)) {
      return;
    }
    final done = await app.restoreOldBackupFile(file);
    if (!mounted) return;
    if (done) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      snack(context, 'Backup restored. Unlock with its master password.');
    } else {
      snack(context, 'This is not a Kryvo backup file');
    }
  }

  // ---- Fake PIN -----------------------------------------------------------------

  Future<void> _fakePin(AppState app) async {
    if (app.fakePinSet) {
      final c = await pickOne<String>(context,
          title: 'Fake PIN',
          values: const ['change', 'off'],
          label: (v) => v == 'change' ? 'Change fake PIN' : 'Turn off fake PIN');
      if (c == 'off') {
        await app.clearFakePin();
        if (mounted) snack(context, 'Fake PIN turned off');
        return;
      }
      if (c != 'change' || !mounted) return;
    } else {
      if (!await confirm(context,
          title: 'Fake PIN (decoy vault)',
          message: 'If someone forces you to open Kryvo, enter the fake PIN '
              'instead. It opens a separate, nearly empty vault — your real '
              'photos, passwords and settings stay hidden.\n\n'
              'Tip: add a few harmless photos to the fake vault so it looks real.',
          ok: 'Set fake PIN')) {
        return;
      }
    }
    if (!mounted) return;
    final code = await promptText(context,
        title: app.pinMode ? 'Fake PIN' : 'Fake password',
        hint: app.pinMode ? '4 to 8 digits' : 'At least 4 characters',
        obscure: true,
        keyboard: app.pinMode ? TextInputType.number : null,
        maxLength: app.pinMode ? 8 : null,
        ok: 'Save');
    if (code == null || !mounted) return;
    if (app.pinMode && !RegExp(r'^\d{4,8}$').hasMatch(code)) {
      snack(context, 'The fake PIN must be 4 to 8 digits');
      return;
    }
    final err = await app.setFakePin(code);
    if (mounted) snack(context, err ?? 'Fake PIN saved ✔');
  }

  /// Settings inside the decoy vault: only harmless options.
  Widget _decoySettings(AppState app) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        children: [
          const SectionHeader('APP SETTINGS'),
          _tile(Icons.palette_outlined, 'Theme',
              subtitle: SV.current.name,
              onTap: () => _open(ThemePickerScreen())),
          _tile(Icons.translate, 'Language',
              subtitle: kLanguages.firstWhere((l) => l.code == app.lang).name,
              onTap: () => _open(const LanguageScreen())),
          const SectionHeader('OTHER SETTINGS'),
          _tile(Icons.help_outline, 'Usage',
              subtitle: 'How to use Kryvo', onTap: () => _open(const UsagePage())),
          _tile(Icons.info_outline, 'App info',
              onTap: () => _open(const AppInfoPage())),
          _tile(Icons.feedback_outlined, 'Feedback',
              onTap: () => _open(const FeedbackScreen())),
        ],
      ),
    );
  }

  // ---- UI helpers ---------------------------------------------------------------------

  Widget _tile(IconData icon, String title,
      {String? subtitle, VoidCallback? onTap, Widget? trailing}) {
    return ListTile(
      leading: Icon(icon, color: SV.accent),
      title: Text(tr(title)),
      subtitle: subtitle == null
          ? null
          : Text(tr(subtitle), style: TextStyle(color: SV.muted, fontSize: 12.5)),
      trailing: trailing ??
          (onTap == null ? null : Icon(Icons.chevron_right, color: SV.muted)),
      onTap: onTap,
    );
  }

  Widget _switch(IconData icon, String title, bool value,
      ValueChanged<bool> onChanged,
      {String? subtitle}) {
    return SwitchListTile(
      secondary: Icon(icon, color: SV.accent),
      title: Text(tr(title)),
      subtitle: subtitle == null
          ? null
          : Text(tr(subtitle), style: TextStyle(color: SV.muted, fontSize: 12.5)),
      value: value,
      activeColor: SV.accent,
      onChanged: onChanged,
    );
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.decoy) return _decoySettings(app);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          // ---- Recovery & media --------------------------------------------------
          const SectionHeader('RECOVERY & MEDIA'),
          _tile(Icons.vpn_key_outlined, 'Recovery key',
              subtitle: app.recoveryEnabled
                  ? 'On — you can get back in if you forget the password'
                  : 'Off — set one up so you are never locked out',
              onTap: () => _recoveryKey(app)),
          _tile(Icons.healing_outlined, 'Recover lost media',
              subtitle: 'Scan for lost files · bring back items deleted from the Recycle Bin',
              onTap: () => _open(const RecoverMediaScreen())),
          _tile(Icons.slideshow_outlined, 'Slideshow running time',
              subtitle: '${app.slideshowSecs} seconds per picture',
              onTap: () async {
            final v = await pickOne<int>(context,
                title: 'Slideshow running time',
                values: const [2, 3, 5, 8, 10],
                selected: app.slideshowSecs,
                label: (s) => '$s seconds');
            if (v != null) await app.setIntPref(PrefKeys.slideshowSecs, v);
          }),

          // ---- Screen lock --------------------------------------------------------
          const SectionHeader('SCREEN LOCK SETTINGS'),
          _tile(Icons.lock_outline, 'Screen lock type',
              subtitle: app.pinMode ? 'PIN' : 'Master password'),
          _tile(Icons.swap_horiz, 'Change screen lock type',
              subtitle: 'Master password or PIN',
              onTap: () => _lockType(app)),
          _tile(Icons.password, 'Change password',
              subtitle: 'Your master password (encrypts the vault)',
              onTap: () => _changePassword(app)),
          if (app.pinMode)
            _tile(Icons.dialpad, 'Change PIN', onTap: () => _setupPin(app)),
          _tile(Icons.theater_comedy_outlined, 'Fake PIN (decoy vault)',
              subtitle: app.fakePinSet
                  ? 'On — opens a fake, nearly empty vault'
                  : 'A second PIN that opens a fake vault if you are forced',
              onTap: () => _fakePin(app)),
          _switch(Icons.fingerprint, 'Enable fingerprint', _bioOn,
              (v) => _toggleFingerprint(app, v),
              subtitle: _bioSupported
                  ? 'Unlock with fingerprint or face'
                  : 'Not available on this phone'),
          // PIN-pad options only matter with PIN lock.
          if (app.pinMode)
            _switch(Icons.vibration, 'Vibration feedback', app.vibration,
                (v) => app.setBoolPref(PrefKeys.vibration, v),
                subtitle: 'Vibrate on PIN key presses'),
          _tile(Icons.lock_person_outlined, 'App Lock',
              subtitle: 'Put a PIN on WhatsApp, Gallery or any app',
              onTap: () => _open(const AppLockScreen())),
          _tile(Icons.camera_front_outlined, 'Intruder alert',
              subtitle: app.intruderEnabled
                  ? 'Selfie on — see who tried to open Kryvo'
                  : 'Break-in log of wrong PIN / password tries',
              onTap: () => _open(const IntruderScreen())),
          _switch(Icons.vibration_outlined, 'Shake to lock', app.shakeLock,
              (v) => app.setBoolPref(PrefKeys.shakeLock, v),
              subtitle: 'Shake the phone to lock Kryvo instantly'),
          _switch(Icons.screen_rotation_alt_outlined, 'Face-down to lock',
              app.faceDownLock,
              (v) => app.setBoolPref(PrefKeys.faceDownLock, v),
              subtitle: 'Put the phone screen-down on a table to lock'),
          if (app.pinMode) ...[
            _tile(Icons.quiz_outlined, 'Q&A for PIN',
                subtitle: _question.isEmpty
                    ? 'Security question to reset a forgotten PIN'
                    : _question,
                onTap: _setQuestion),
            _tile(Icons.lightbulb_outline, 'PIN hint',
                subtitle: app.pinHint.isEmpty ? 'Not set' : app.pinHint,
                onTap: () => _setHint(app)),
          ],
          _tile(Icons.timer_outlined, 'Auto-lock',
              subtitle: app.autoLockSeconds == 0
                  ? 'Never while using the app (locks when you leave it)'
                  : app.autoLockSeconds < 60
                      ? 'After ${app.autoLockSeconds} seconds of no touch'
                      : 'After ${app.autoLockSeconds ~/ 60} minute${app.autoLockSeconds >= 120 ? 's' : ''} of no touch',
              onTap: () async {
            final v = await pickOne<int>(context,
                title: 'Auto-lock after no touch',
                values: const [30, 60, 120, 300, 600, 0],
                selected: app.autoLockSeconds,
                label: (s) => s == 0
                    ? 'Never'
                    : s < 60
                        ? '$s seconds'
                        : '${s ~/ 60} min');
            if (v != null) await app.setAutoLockSeconds(v);
          }),

          // ---- Image viewer --------------------------------------------------------
          const SectionHeader('IMAGE VIEWER SETTINGS'),
          _tile(Icons.zoom_in, 'Zoom level',
              subtitle: 'Up to ${app.maxZoom}x', onTap: () async {
            final v = await pickOne<int>(context,
                title: 'Maximum zoom',
                values: const [2, 3, 4, 6, 8],
                selected: app.maxZoom,
                label: (z) => '${z}x');
            if (v != null) await app.setIntPref(PrefKeys.maxZoom, v);
          }),
          _switch(Icons.visibility_off_outlined, 'Hide guide', app.hideGuide,
              (v) => app.setBoolPref(PrefKeys.hideGuide, v),
              subtitle: 'Open pictures full-screen without the top/bottom bars'),
          _switch(Icons.info_outline, 'Image detail view', app.detailView,
              (v) => app.setBoolPref(PrefKeys.detailView, v),
              subtitle: 'Show the details (i) button in the viewer'),
          _switch(Icons.fit_screen_outlined, 'Fit small image', app.fitSmall,
              (v) => app.setBoolPref(PrefKeys.fitSmall, v),
              subtitle: 'Enlarge small pictures to fill the screen'),

          // ---- App settings --------------------------------------------------------
          const SectionHeader('APP SETTINGS'),
          _tile(Icons.palette_outlined, 'Theme',
              subtitle: SV.current.name,
              onTap: () => _open(ThemePickerScreen())),
          _tile(Icons.storage_rounded, 'Storage',
              subtitle: 'How much space the vault uses',
              onTap: () => _open(const StorageScreen())),
          _tile(Icons.apps_outlined, 'App icon & disguise',
              subtitle: app.disguised
                  ? 'Disguised as ${DisguiseService.nameOf(app.appIcon)}'
                  : 'Change the icon, or hide Kryvo as a Calculator…',
              onTap: () => _open(const AppIconScreen())),
          _switch(Icons.folder_off_outlined, 'Hide thumbnails of folder',
              app.hideFolderThumbs,
              (v) => app.setBoolPref(PrefKeys.hideFolderThumbs, v),
              subtitle: 'Show a plain folder icon instead of a preview'),

          // ---- Backup ---------------------------------------------------------------
          const SectionHeader('BACKUP'),
          _tile(Icons.cloud_upload_outlined, 'Full backup',
              subtitle: 'Passwords + photos + videos + audio in one encrypted '
                  'file — save to Google Drive or phone',
              onTap: () => _backup(app)),
          _tile(Icons.cloud_download_outlined, 'Restore from backup',
              subtitle: 'Pick a Kryvo backup from Drive or your phone',
              onTap: () => _restore(app)),

          // ---- Other ------------------------------------------------------------------
          const SectionHeader('OTHER SETTINGS'),
          _tile(Icons.share_outlined, 'Recommend to friend',
              onTap: () => recommendToFriend(context)),
          _tile(Icons.help_outline, 'Usage',
              subtitle: 'How to use Kryvo', onTap: () => _open(const UsagePage())),
          _tile(Icons.slideshow_outlined, 'Welcome tour',
              subtitle: 'See what Kryvo can do',
              onTap: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                app.replayOnboarding();
              }),
          _tile(Icons.info_outline, 'App info',
              onTap: () => _open(const AppInfoPage())),
          _tile(Icons.feedback_outlined, 'Feedback',
              onTap: () => _open(const FeedbackScreen())),
          _tile(Icons.block, 'Ad free',
              subtitle: 'No ads, no trackers', onTap: () => showAdFree(context)),
          _tile(Icons.translate, 'Language',
              subtitle: kLanguages.firstWhere((l) => l.code == app.lang).name,
              onTap: () => _open(const LanguageScreen())),
          _tile(Icons.apps, 'More apps', onTap: () => _open(const MoreAppsPage())),
          const SizedBox(height: 16),
          Center(
            child: Text('Kryvo 1.0 · Built by Faraz Labs',
                style: TextStyle(color: SV.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
