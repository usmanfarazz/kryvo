import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/media_item.dart';
import '../services/disguise_service.dart';
import '../services/settings_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'app_icon_screen.dart';
import 'app_lock_screen.dart';
import 'category_screen.dart';
import 'favorites_screen.dart';
import 'feedback_screen.dart';
import 'intruder_screen.dart';
import 'language_screen.dart';
import 'notes_screen.dart';
import 'recover_media_screen.dart';
import 'recycle_bin_screen.dart';
import 'settings_pages.dart';
import 'settings_screen.dart';
import 'theme_picker_screen.dart';
import 'vault_screen.dart';

/// Every Kryvo feature in one place — tap one to open it.
class FeaturesScreen extends StatelessWidget {
  const FeaturesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    void open(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    Widget item(IconData icon, Color color, String title, String subtitle,
            VoidCallback onTap) =>
        ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          title: Text(tr(title)),
          subtitle: Text(tr(subtitle), style: TextStyle(color: SV.muted)),
          trailing: Icon(Icons.chevron_right, color: SV.muted),
          onTap: onTap,
        );

    Widget toggle(IconData icon, Color color, String title, String subtitle,
            bool value, ValueChanged<bool> onChanged) =>
        SwitchListTile(
          secondary: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          title: Text(tr(title)),
          subtitle: Text(tr(subtitle), style: TextStyle(color: SV.muted)),
          value: value,
          activeColor: SV.accent,
          onChanged: onChanged,
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('All features'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionHeader('HIDE & PROTECT'),
          item(
              Icons.calculate_rounded,
              const Color(0xFFF59E0B),
              'App icon & disguise',
              app.disguised
                  ? 'Disguised as ${DisguiseService.nameOf(app.appIcon)}'
                  : 'Hide Kryvo as a Calculator, Notes, Clock, Game or Flashlight',
              () => open(const AppIconScreen())),
          item(
              Icons.lock_person_rounded,
              const Color(0xFF0EA5E9),
              'App Lock',
              'Put a PIN on WhatsApp, Gallery or any app',
              () => open(const AppLockScreen())),
          item(
              Icons.camera_front_rounded,
              const Color(0xFFEF4444),
              'Intruder alert',
              'Photo of anyone who enters a wrong PIN',
              () => open(const IntruderScreen())),
          toggle(
              Icons.vibration,
              const Color(0xFF8B5CF6),
              'Shake to lock',
              'Shake the phone to lock Kryvo instantly',
              app.shakeLock,
              (v) => app.setBoolPref(PrefKeys.shakeLock, v)),
          toggle(
              Icons.screen_rotation_alt,
              const Color(0xFF06B6D4),
              'Face-down to lock',
              'Put the phone screen-down on a table to lock',
              app.faceDownLock,
              (v) => app.setBoolPref(PrefKeys.faceDownLock, v)),
          item(
              Icons.theater_comedy_rounded,
              const Color(0xFF8B5CF6),
              'Fake PIN',
              app.fakePinSet
                  ? 'On — opens a fake vault'
                  : 'A second PIN that opens a fake vault',
              () => open(const SettingsScreen())),
          item(Icons.lock_clock, const Color(0xFF3B82F6), 'Screen lock settings',
              'PIN, password, fingerprint, auto-lock',
              () => open(const SettingsScreen())),
          const SectionHeader('YOUR FILES'),
          for (final c in MediaCat.all)
            item(
                c == MediaCat.photo
                    ? Icons.photo_library_rounded
                    : c == MediaCat.video
                        ? Icons.video_library_rounded
                        : c == MediaCat.web
                            ? Icons.public_rounded
                            : Icons.library_music_rounded,
                const Color(0xFF3D8BFF),
                MediaCat.title(c),
                '${app.itemsOf(c).length} ${MediaCat.noun(c)}',
                () => open(CategoryScreen(cat: c))),
          item(Icons.star_rounded, const Color(0xFFEAB308), 'Favourites',
              '${app.favorites.length} items',
              () => open(const FavoritesScreen())),
          item(Icons.sticky_note_2_rounded, const Color(0xFF14B8A6),
              'Private Notes', '${app.view(category: 'Notes').length} notes',
              () => open(const NotesScreen())),
          item(Icons.key_rounded, const Color(0xFF22C55E), 'Safe Password',
              '${app.entries.length} saved', () => open(VaultScreen())),
          item(Icons.delete_sweep_rounded, const Color(0xFF8B5CF6),
              'Recycle Bin', '${app.trash.length} items',
              () => open(RecycleBinScreen())),
          item(Icons.healing_rounded, const Color(0xFF10B981),
              'Recover lost media',
              'Lost files and items deleted from the Recycle Bin',
              () => open(const RecoverMediaScreen())),
          const SectionHeader('PERSONALIZE'),
          item(Icons.palette_rounded, const Color(0xFFEC4899), 'Theme',
              '${SV.palettes.length} colour themes',
              () => open(ThemePickerScreen())),
          item(
              Icons.translate,
              const Color(0xFF0EA5E9),
              'Language',
              kLanguages.firstWhere((l) => l.code == currentLang).name,
              () => open(const LanguageScreen())),
          const SectionHeader('BACKUP & HELP'),
          item(Icons.cloud_sync_rounded, const Color(0xFF6366F1),
              'Backup & restore', 'Encrypted backup to Google Drive or phone',
              () => open(const SettingsScreen())),
          item(Icons.help_outline_rounded, const Color(0xFF64748B), 'Usage',
              'How to use Kryvo', () => open(const UsagePage())),
          item(Icons.feedback_rounded, const Color(0xFFF97316), 'Feedback',
              'Report a problem or share an idea',
              () => open(const FeedbackScreen())),
        ],
      ),
    );
  }
}
