import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme.dart';
import '../services/media_service.dart';

/// Small shared UI pieces so every screen looks the same.

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: SV.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 46, color: SV.accent),
            ),
            const SizedBox(height: 16),
            Text(tr(title),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: SV.txt, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(tr(subtitle),
                textAlign: TextAlign.center,
                style: TextStyle(color: SV.muted)),
          ],
        ),
      ),
    );
  }
}

class BusyOverlay extends StatelessWidget {
  final String text;
  const BusyOverlay({super.key, this.text = 'Please wait…'});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: SV.panel,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: SV.accent),
              const SizedBox(height: 16),
              Text(tr(text),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: SV.txt, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Keep Kryvo open until this finishes',
                  style: TextStyle(color: SV.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Big section heading used in Settings.
class SectionHeader extends StatelessWidget {
  final String text;
  const SectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
      child: Text(tr(text),
          style: TextStyle(
              color: SV.accent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4)),
    );
  }
}

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(tr(msg))));
}

Future<bool> confirm(BuildContext context,
    {required String title,
    required String message,
    String ok = 'OK',
    bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SV.panel,
      title: Text(tr(title)),
      content: Text(tr(message)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'), style: TextStyle(color: SV.muted))),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr(ok),
              style: TextStyle(
                  color: danger ? SV.bad : SV.accent,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r == true;
}

/// Ask for one line of text.
Future<String?> promptText(BuildContext context,
    {required String title,
    String hint = '',
    String initial = '',
    String ok = 'OK',
    bool obscure = false,
    TextInputType? keyboard,
    int? maxLength}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SV.panel,
      title: Text(tr(title)),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: obscure,
        keyboardType: keyboard,
        maxLength: maxLength,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancel'), style: TextStyle(color: SV.muted))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(tr(ok),
                style: TextStyle(
                    color: SV.accent, fontWeight: FontWeight.w700))),
      ],
    ),
  );
}

/// Pick one option from a list.
Future<T?> pickOne<T>(BuildContext context,
    {required String title,
    required List<T> values,
    required String Function(T) label,
    T? selected}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => SimpleDialog(
      backgroundColor: SV.panel,
      title: Text(tr(title)),
      children: [
        for (final v in values)
          ListTile(
            title: Text(label(v)),
            trailing: v == selected
                ? Icon(Icons.check_circle, color: SV.accent)
                : null,
            onTap: () => Navigator.pop(ctx, v),
          ),
      ],
    ),
  );
}

/// Pick one or more options from a list (checkboxes + "All"). Returns the
/// chosen values, or null if cancelled.
Future<List<T>?> pickMany<T>(BuildContext context,
    {required String title,
    required List<T> values,
    required String Function(T) label,
    String ok = 'OK',
    bool danger = false}) {
  final chosen = <T>{};
  return showDialog<List<T>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final all = chosen.length == values.length;
        return AlertDialog(
          backgroundColor: SV.panel,
          title: Text(tr(title)),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (values.length > 1)
                  CheckboxListTile(
                    value: all,
                    activeColor: SV.accent,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('Select all',
                        style: TextStyle(
                            color: SV.txt, fontWeight: FontWeight.w600)),
                    onChanged: (_) => setState(() {
                      all ? chosen.clear() : chosen.addAll(values);
                    }),
                  ),
                for (final v in values)
                  CheckboxListTile(
                    value: chosen.contains(v),
                    activeColor: SV.accent,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(label(v)),
                    onChanged: (_) => setState(() {
                      if (!chosen.remove(v)) chosen.add(v);
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Cancel'), style: TextStyle(color: SV.muted))),
            TextButton(
              onPressed: chosen.isEmpty
                  ? null
                  : () => Navigator.pop(
                      ctx, [for (final v in values) if (chosen.contains(v)) v]),
              child: Text(
                  chosen.isEmpty ? ok : '$ok (${chosen.length})',
                  style: TextStyle(
                      color: chosen.isEmpty
                          ? SV.muted
                          : danger
                              ? SV.bad
                              : SV.accent,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    ),
  );
}

/// Show the result of "Recover lost media" / "Media scanning".
Future<void> showRecoverReport(BuildContext context, RecoverReport r) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SV.panel,
      icon: Icon(
          r.recovered > 0 ? Icons.restore : Icons.verified_outlined,
          color: SV.accent,
          size: 36),
      title: const Text('Recover lost media'),
      content: Text(r.describe()),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK',
                style: TextStyle(
                    color: SV.accent, fontWeight: FontWeight.w700))),
      ],
    ),
  );
}

/// Run [job] behind a small non-dismissible progress dialog. [job] gets an
/// `update` callback to change the status text.
Future<T> withProgress<T>(BuildContext context, String initial,
    Future<T> Function(void Function(String status) update) job) async {
  final status = ValueNotifier<String>(initial);
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: SV.panel,
        content: Row(
          children: [
            const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 18),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (_, s, __) => Text(tr(s)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  try {
    return await job((s) => status.value = s);
  } finally {
    nav.pop();
    status.dispose();
  }
}
