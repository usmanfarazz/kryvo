import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'settings_pages.dart';

/// Developer links shown under Feedback. Leave a link empty to hide it.
const kGithubUrl = '';
const kLinkedinUrl = 'https://www.linkedin.com/in/usman-farazz';

/// Feedback form. Kryvo has no internet permission, so it can't send
/// anything itself: "Send" opens the phone's email app (Gmail etc.) with the
/// message already written and addressed to [kSupportEmail]; the user just
/// taps Send there.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const _kinds = ['Bug / problem', 'Feature idea', 'Question', 'Other'];
  String _kind = _kinds.first;
  final _msg = TextEditingController();
  int _stars = 0;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  String get _subject => 'Kryvo feedback — $_kind';

  String get _body {
    final b = StringBuffer(_msg.text.trim());
    b.writeln('\n');
    if (_stars > 0) b.writeln('Rating: ${'★' * _stars}${'☆' * (5 - _stars)}');
    b.writeln('App version: $kAppVersion');
    b.writeln('Android: ${Platform.operatingSystemVersion}');
    return b.toString();
  }

  Future<void> _open(Uri uri) async {
    final app = context.read<AppState>();
    // Opening another app pauses Kryvo; don't lock while the user is there.
    app.holdLock();
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) snack(context, 'No app found to open this');
    } catch (_) {
      if (mounted) snack(context, 'No app found to open this');
    } finally {
      // Give the other app time to come up before auto-lock is back on.
      Future.delayed(const Duration(seconds: 2), app.releaseLock);
    }
  }

  Future<void> _send() async {
    if (_msg.text.trim().isEmpty) {
      snack(context, 'Please write your feedback first');
      return;
    }
    await _open(Uri(
      scheme: 'mailto',
      path: kSupportEmail,
      query: _encode({'subject': _subject, 'body': _body}),
    ));
  }

  // Uri(queryParameters:) turns spaces into "+", which mail apps show as-is.
  static String _encode(Map<String, String> p) => p.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Tell us what you think — every message is read.',
              style: TextStyle(color: SV.muted)),
          const SizedBox(height: 16),
          Text('How do you like Kryvo?',
              style: TextStyle(color: SV.txt, fontWeight: FontWeight.w600)),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _stars = i),
                  icon: Icon(i <= _stars ? Icons.star : Icons.star_border,
                      color: const Color(0xFFF5B301), size: 32),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in _kinds)
                ChoiceChip(
                  label: Text(k),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _msg,
            minLines: 6,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Write your feedback here…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _send,
            icon: const Icon(Icons.send),
            label: const Text('Send'),
          ),
          const SizedBox(height: 8),
          Text(
              'Opens your email app (e.g. Gmail) with this message to '
              '$kSupportEmail — just tap Send there. Kryvo itself has no '
              'internet access.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SV.muted, fontSize: 12)),
          const SizedBox(height: 20),
          const SectionHeader('CONTACT THE DEVELOPER'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.email_outlined, color: SV.accent),
                  title: const Text('Email'),
                  subtitle: const Text(kSupportEmail),
                  trailing: IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(
                          const ClipboardData(text: kSupportEmail));
                      snack(context, 'Email address copied');
                    },
                  ),
                  onTap: () =>
                      _open(Uri(scheme: 'mailto', path: kSupportEmail)),
                ),
                if (kGithubUrl.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.code, color: SV.accent),
                    title: const Text('GitHub'),
                    subtitle: const Text(kGithubUrl),
                    onTap: () => _open(Uri.parse(kGithubUrl)),
                  ),
                if (kLinkedinUrl.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.work_outline, color: SV.accent),
                    title: const Text('LinkedIn'),
                    subtitle: const Text(kLinkedinUrl),
                    onTap: () => _open(Uri.parse(kLinkedinUrl)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
