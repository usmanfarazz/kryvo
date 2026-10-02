import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';

/// Pick one of the app's colour themes. Each card is a mini live preview.
class ThemePickerScreen extends StatelessWidget {
  ThemePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Themes')),
      body: GridView.builder(
        padding: const EdgeInsets.all(14),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemCount: SV.palettes.length,
        itemBuilder: (_, i) {
          final p = SV.palettes[i];
          final on = p.id == app.themeId;
          return GestureDetector(
            onTap: () => app.setTheme(p.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: p.bg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: on ? p.accent : p.line,
                  width: on ? 3 : 1,
                ),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fake app bar
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: p.accent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Icon(Icons.lock,
                            color: Colors.white, size: 11),
                      ),
                      const SizedBox(width: 6),
                      Container(
                          width: 46,
                          height: 7,
                          decoration: BoxDecoration(
                              color: p.txt.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Fake photo grid
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      physics: const NeverScrollableScrollPhysics(),
                      children: List.generate(
                        6,
                        (k) => Container(
                          decoration: BoxDecoration(
                            color: k == 1 ? p.accent.withValues(alpha: 0.55)
                                : p.panel2,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Fake nav bar
                  Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: p.panel,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Icon(Icons.photo, size: 10, color: p.accent),
                        Icon(Icons.videocam, size: 10, color: p.muted),
                        Icon(Icons.lock, size: 10, color: p.muted),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.txt,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ),
                      if (on)
                        Icon(Icons.check_circle, color: p.accent, size: 18),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
