import 'package:flutter/material.dart';

import 'login_screen.dart';
import '../models/auth_flow_mode.dart';
import '../theme/saathi_beige_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _openLoginFlow(BuildContext context, AuthFlowMode mode) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => LoginScreen(mode: mode)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: SaathiBeige.cream,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: SaathiBeige.backgroundGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints.expand(),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  Container(
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          SaathiBeige.accent.withValues(alpha: 0.55),
                          SaathiBeige.accentDeep.withValues(alpha: 0.95),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: SaathiBeige.accentDeep.withValues(alpha: 0.28),
                          blurRadius: 26,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.spa_rounded,
                      color: Colors.white,
                      size: 58,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Saathi',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: SaathiBeige.charcoal,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aapki kahani, aapki zubaani',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: SaathiBeige.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(flex: 4),
                  _PrimaryAuthButton(
                    label: 'Register',
                    caption: 'For new users',
                    onTap: () =>
                        _openLoginFlow(context, AuthFlowMode.register),
                  ),
                  const SizedBox(height: 16),
                  _SecondaryAuthButton(
                    label: 'Log In',
                    caption: 'For existing users',
                    onTap: () => _openLoginFlow(context, AuthFlowMode.login),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryAuthButton extends StatelessWidget {
  const _PrimaryAuthButton({
    required this.label,
    required this.caption,
    required this.onTap,
  });

  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: SaathiBeige.accentDeep,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryAuthButton extends StatelessWidget {
  const _SecondaryAuthButton({
    required this.label,
    required this.caption,
    required this.onTap,
  });

  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: SaathiBeige.accentDeep,
          backgroundColor: SaathiBeige.surfaceElevated.withValues(alpha: 0.65),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          side: BorderSide(
            color: SaathiBeige.accentDeep.withValues(alpha: 0.55),
            width: 1.4,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: SaathiBeige.accentDeep,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: SaathiBeige.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
