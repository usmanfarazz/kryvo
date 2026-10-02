import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';

/// Short "what Kryvo can do" tour, shown once after the vault is first
/// opened (and once after an update that adds it).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Slide {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _Slide(this.icon, this.color, this.title, this.body);
}

const _slides = [
  _Slide(
    Icons.lock_rounded,
    Color(0xFF4F8CFF),
    'Your private vault',
    'Hide photos, videos, audio and passwords. Everything is encrypted with '
        'AES-256 on this phone — no internet, no cloud, no ads.',
  ),
  _Slide(
    Icons.calculate_rounded,
    Color(0xFFF59E0B),
    'Hide Kryvo itself',
    'Change the icon to a working Calculator, Clock, Notes, Game or '
        'Flashlight. Only your secret code opens the vault.\n\n'
        'Settings → App icon & disguise',
  ),
  _Slide(
    Icons.camera_front_rounded,
    Color(0xFFEF4444),
    'Catch snoopers',
    'Intruder selfie takes a photo of anyone who enters a wrong PIN. '
        'App Lock puts a PIN on WhatsApp, Gallery or any app.',
  ),
  _Slide(
    Icons.theater_comedy_rounded,
    Color(0xFF8B5CF6),
    'Fake PIN',
    'Forced to open Kryvo? Enter your fake PIN — it opens a separate, '
        'nearly empty vault and your real files stay hidden.\n\n'
        'Settings → Fake PIN',
  ),
  _Slide(
    Icons.cloud_sync_rounded,
    Color(0xFF22C55E),
    'Never lose anything',
    'Make a full encrypted backup to Google Drive, and turn on a Recovery '
        'key so you can get back in if you forget your password.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _i = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _done() => context.read<AppState>().finishOnboarding();

  @override
  Widget build(BuildContext context) {
    final last = _i == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _done,
                child: Text('Skip', style: TextStyle(color: SV.muted)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _i = i),
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            color: s.color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(s.icon, color: s.color, size: 64),
                        ),
                        const SizedBox(height: 36),
                        Text(s.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: SV.txt,
                                fontSize: 24,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 14),
                        Text(s.body,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: SV.muted, fontSize: 15, height: 1.45)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _i ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _i ? SV.accent : SV.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: last
                      ? _done
                      : () => _page.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut),
                  child: Text(last ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
