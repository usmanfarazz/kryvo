import 'package:flutter/material.dart';

import 'calculator_disguise.dart';
import 'clock_disguise.dart';
import 'flashlight_disguise.dart';
import 'game_disguise.dart';
import 'notes_disguise.dart';

/// The disguise app shown instead of the lock screen while a disguise icon
/// (see DisguiseService) is active.
class DisguiseHost extends StatelessWidget {
  final String id;
  const DisguiseHost({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    switch (id) {
      case 'notes':
        return const NotesDisguise();
      case 'clock':
        return const ClockDisguise();
      case 'game':
        return const GameDisguise();
      case 'torch':
        return const FlashlightDisguise();
      default:
        return const CalculatorDisguise();
    }
  }
}
