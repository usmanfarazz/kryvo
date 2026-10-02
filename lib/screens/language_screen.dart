import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Pick the app language.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Language'))),
      body: ListView(
        children: [
          for (final l in kLanguages)
            ListTile(
              title: Text(l.name,
                  style: TextStyle(
                      color: SV.txt,
                      fontWeight: l.code == app.lang
                          ? FontWeight.w700
                          : FontWeight.w400)),
              trailing: l.code == app.lang
                  ? Icon(Icons.check_circle, color: SV.accent)
                  : null,
              onTap: () => app.setLang(l.code),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
                'Some screens are still in English and will be translated '
                'in updates. Want to help? Use Feedback.',
                style: TextStyle(color: SV.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
