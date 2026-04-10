import 'package:flutter/material.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

import '../services/app_settings.dart';
import '../services/chat_history_storage.dart';
import '../theme/saathi_beige_theme.dart';
import '../widgets/floating_voice_nav_bar.dart';
import 'family_screen.dart';
import 'history_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _showSystemPopup(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(color: Colors.black87),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: SaathiBeige.accentDeep.withValues(alpha: 0.45),
            ),
          ),
          elevation: 8,
          duration: const Duration(seconds: 2),
          backgroundColor: SaathiBeige.surfaceElevated.withValues(alpha: 0.96),
        ),
      );
  }

  static String _fontLabel(double scale) {
    if ((scale - 1.0).abs() < 0.001) return 'Small';
    if ((scale - 1.2).abs() < 0.001) return 'Medium';
    return 'Large';
  }

  static Widget _sectionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: SaathiBeige.surfaceElevated.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SaathiBeige.accent.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: SaathiBeige.charcoal.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SaathiBeige.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: SaathiBeige.accentDeep, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: SaathiBeige.charcoal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaathiBeige.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Future<void> _confirmClearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear chat history?'),
          content: const Text(
            'This will remove all locally saved chats and recordings on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await ChatHistoryStorage.instance.clearAllLocalChatData();
    if (!mounted) return;
    _showSystemPopup('Chat history cleared');
  }

  Future<void> _resetSettings() async {
    await AppSettings.instance.setFontScale(1.0);
    await AppSettings.instance.setTtsVolume(1.0);
    if (!mounted) return;
    _showSystemPopup('Settings reset');
  }

  Future<void> _onBottomNavTap(int index) async {
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
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const FamilyScreen()),
      );
      return;
    }
    if (index == 3) {
      return;
    }
    if (index == 4) {
      await Navigator.of(context).pushNamed('/profile');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
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
        title: const Text('Settings'),
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
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: SaathiBeige.backgroundGradient),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, topInset + kToolbarHeight + 12, 16, 132),
          children: [
            Text(
              'Personalize your app',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: SaathiBeige.charcoal,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Display, sound, and theme preferences',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: SaathiBeige.muted),
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<double>(
              valueListenable: AppSettings.instance.fontScaleNotifier,
              builder: (context, fontScale, _) {
                return _sectionCard(
                  context: context,
                  icon: Icons.format_size_rounded,
                  title: 'Font size',
                  subtitle:
                      '${_fontLabel(fontScale)} (${fontScale.toStringAsFixed(2)}x)',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [1.0, 1.2, 1.4].map((scale) {
                      final selected = (fontScale - scale).abs() < 0.001;
                      return ChoiceChip(
                        label: Text(
                          scale == 1.0
                              ? 'Small'
                              : scale == 1.2
                              ? 'Medium'
                              : 'Large',
                        ),
                        selected: selected,
                        onSelected: (_) =>
                            AppSettings.instance.setFontScale(scale),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
            ValueListenableBuilder<double>(
              valueListenable: AppSettings.instance.ttsVolumeNotifier,
              builder: (context, vol, _) {
                final percent = (vol * 100).round().clamp(0, 100);
                return _sectionCard(
                  context: context,
                  icon: Icons.volume_up_rounded,
                  title: 'Voice output volume',
                  subtitle: '$percent%',
                  child: Slider(
                    value: vol,
                    min: 0,
                    max: 1,
                    divisions: 10,
                    onChanged: (v) async {
                      await FlutterVolumeController.setVolume(v);
                      await AppSettings.instance.setTtsVolume(v);
                    },
                  ),
                );
              },
            ),
            _sectionCard(
              context: context,
              icon: Icons.cleaning_services_rounded,
              title: 'Storage',
              subtitle: 'Manage data on this device',
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _confirmClearChat,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Clear chat history'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _resetSettings,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Reset settings'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FloatingVoiceNavBar(
            currentIndex: 3,
            onSelect: (i) => _onBottomNavTap(i),
          ),
        ),
      ),
    );
  }
}
