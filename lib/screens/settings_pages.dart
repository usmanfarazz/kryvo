import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// Contact address shown under Feedback / Translation support.
/// Change this one line if you want a different support email.
const kSupportEmail = 'usmanfaraz1818@gmail.com';
const kAppVersion = '1.0.0';

/// Public privacy policy (hosted on GitHub Pages, repo usmanfarazz/kryvo, docs/privacy.html).
const kPrivacyPolicyUrl = 'https://usmanfarazz.github.io/kryvo/privacy.html';

/// Play Store page (works once Kryvo is published there).
const kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.farazlabs.kryvo';

const _share = MethodChannel('kryvo/media');

String _inviteText() =>
    '🔒 I use Kryvo to hide my private photos, videos, audio and passwords. '
    'Everything is encrypted on the phone — no ads, no cloud, works without '
    'internet. It can even look like a Calculator!\n\n'
    'Get it free: $kPlayStoreUrl';

/// Share Kryvo with a friend: straight to WhatsApp / Telegram / Messenger /
/// Instagram if installed, copy the invite, or the phone's share menu.
Future<void> recommendToFriend(BuildContext context) async {
  const targets = [
    ('com.whatsapp', 'WhatsApp', Icons.chat, Color(0xFF25D366)),
    ('com.whatsapp.w4b', 'WhatsApp Business', Icons.business_center,
        Color(0xFF128C7E)),
    ('org.telegram.messenger', 'Telegram', Icons.send, Color(0xFF229ED9)),
    ('com.facebook.orca', 'Messenger', Icons.forum, Color(0xFF0084FF)),
    ('com.instagram.android', 'Instagram', Icons.camera_alt,
        Color(0xFFE1306C)),
  ];
  final installed = <(String, String, IconData, Color)>[];
  for (final t in targets) {
    try {
      if (await _share.invokeMethod<bool>('isInstalled', {'package': t.$1}) ==
          true) {
        installed.add(t);
      }
    } catch (_) {}
  }
  if (!context.mounted) return;
  final text = _inviteText();

  Future<void> send([String? pkg]) async {
    try {
      await _share.invokeMethod('share',
          {'text': text, 'package': pkg, 'title': 'Share Kryvo'});
    } catch (_) {}
  }

  Widget option(IconData icon, Color color, String label, VoidCallback onTap) =>
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 78,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color,
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(color: SV.txt, fontSize: 12)),
            ],
          ),
        ),
      );

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: SV.panel,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.favorite, color: SV.accent, size: 34),
            const SizedBox(height: 6),
            Text('Recommend Kryvo',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: SV.txt, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Help a friend keep their photos private.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SV.muted)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SV.panel2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(text,
                  style: TextStyle(color: SV.txt, fontSize: 13)),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 12,
              children: [
                for (final t in installed)
                  option(t.$3, t.$4, t.$2, () {
                    Navigator.pop(ctx);
                    send(t.$1);
                  }),
                option(Icons.copy, const Color(0xFF64748B), 'Copy', () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invite copied')));
                }),
                option(Icons.share, SV.accent, 'More…', () {
                  Navigator.pop(ctx);
                  send();
                }),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void showAdFree(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SV.panel,
      icon: Icon(Icons.verified, color: SV.ok, size: 40),
      title: const Text('Ad free'),
      content: const Text(
          'Kryvo has no ads and no trackers — ever. Nothing you hide leaves '
          'your phone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Great')),
      ],
    ),
  );
}

class _InfoScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _InfoScaffold({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Card(this.icon, this.title, this.body);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SV.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SV.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: SV.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: SV.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: SV.txt,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(color: SV.muted, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class UsagePage extends StatelessWidget {
  const UsagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _InfoScaffold(title: 'Usage', children: [
      _Card(Icons.add_photo_alternate_outlined, 'Hide photos & videos',
          'Open Safe Photo or Safe Video, tap + Add, pick items and tap Hide. '
          'Kryvo encrypts them and removes the originals from your gallery.'),
      _Card(Icons.create_new_folder_outlined, 'Folders',
          'Use the 3-dot menu → New folder. Long-press items and tap Move to '
          'put them in a folder. Rename or Delete folders from the same menu.'),
      _Card(Icons.lock_open_outlined, 'Unhide',
          'Open a picture or video and tap Unhide, or long-press several and '
          'tap Unhide. They go back to your gallery (Pictures/Kryvo, Movies/Kryvo).'),
      _Card(Icons.delete_sweep_outlined, 'Recycle Bin',
          'Deleted items wait in the Recycle Bin. Restore them, or delete them '
          'forever from there.'),
      _Card(Icons.key_outlined, 'Passwords',
          'Safe Password stores your logins encrypted. Tap an entry to copy '
          'the password; it is cleared from the clipboard after 30 seconds.'),
      _Card(Icons.dialpad, 'PIN, fingerprint & recovery',
          'Settings → Screen Lock lets you use a PIN or fingerprint. Set up a '
          'Recovery key and a PIN question so you are never locked out.'),
      _Card(Icons.cloud_upload_outlined, 'Backup',
          'Settings → Backup to Google Drive saves an encrypted backup of your '
          'passwords. Choose Drive in the save screen.'),
    ]);
  }
}

class AppInfoPage extends StatelessWidget {
  const AppInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _InfoScaffold(title: 'App info', children: [
      Center(
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset('assets/kryvo_logo.png',
                  width: 96,
                  height: 96,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.shield, size: 80, color: SV.accent)),
            ),
            const SizedBox(height: 12),
            Text('Kryvo',
                style: TextStyle(
                    color: SV.txt, fontSize: 24, fontWeight: FontWeight.w800)),
            Text('Version $kAppVersion',
                style: TextStyle(color: SV.muted)),
            const SizedBox(height: 20),
          ],
        ),
      ),
      const _Card(Icons.business_outlined, 'Developer', 'Faraz Labs'),
      const _Card(Icons.enhanced_encryption_outlined, 'Encryption',
          'AES-256-GCM. Passwords are protected by your master password '
          '(PBKDF2, 310,000 rounds). Media keys live in the Android Keystore.'),
      const _Card(Icons.privacy_tip_outlined, 'Privacy',
          'Kryvo has no internet permission, no ads and no analytics. Your data '
          'never leaves this phone unless you export a backup yourself.'),
      const _Card(Icons.mail_outline, 'Contact', kSupportEmail),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => launchUrl(Uri.parse(kPrivacyPolicyUrl),
            mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.policy_outlined),
        label: const Text('Privacy policy'),
      ),
    ]);
  }
}

class MoreAppsPage extends StatelessWidget {
  const MoreAppsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _InfoScaffold(title: 'More apps', children: [
      _Card(Icons.lock_outline, 'SecureVault',
          'Offline, zero-knowledge password manager by Faraz Labs.'),
      _Card(Icons.hourglass_empty, 'More coming soon',
          'Faraz Labs is building more privacy-first apps.'),
    ]);
  }
}
