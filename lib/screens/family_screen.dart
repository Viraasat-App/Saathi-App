import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/saathi_beige_theme.dart';
import '../widgets/floating_voice_nav_bar.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  Future<void> _onBottomNavTap(BuildContext context, int index) async {
    if (index == 0) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (index == 1) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
      );
      return;
    }
    if (index == 2) {
      return;
    }
    if (index == 3) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
      );
      return;
    }
    if (index == 4) {
      await Navigator.of(context).pushNamed('/profile');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaathiBeige.cream,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: SaathiBeige.charcoal,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Family'),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: SaathiBeige.backgroundGradient),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: SaathiBeige.accent.withValues(alpha: 0.2),
          ),
        ),
      ),
      body: const DecoratedBox(
        decoration: BoxDecoration(gradient: SaathiBeige.backgroundGradient),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              'Family (coming soon)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SaathiBeige.muted,
                fontSize: 16,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FloatingVoiceNavBar(
            currentIndex: 2,
            onSelect: (i) => unawaited(_onBottomNavTap(context, i)),
          ),
        ),
      ),
    );
  }
}

