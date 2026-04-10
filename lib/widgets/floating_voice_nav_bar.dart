import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/saathi_beige_theme.dart';

class FloatingVoiceNavBar extends StatelessWidget {
  const FloatingVoiceNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const _labels = ['Home', 'History', 'Family', 'Settings', 'Profile'];

  static const _icons = [
    Icons.home_rounded,
    Icons.history_rounded,
    Icons.groups_rounded,
    Icons.settings_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: SaathiBeige.surfaceElevated.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: SaathiBeige.accent.withValues(alpha: 0.22),
              ),
              boxShadow: [
                BoxShadow(
                  color: SaathiBeige.charcoal.withValues(alpha: 0.08),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
              child: Row(
                children: List.generate(5, (i) {
                  final selected = i == currentIndex;
                  return Expanded(
                    child: _NavCell(
                      icon: _icons[i],
                      label: _labels[i],
                      selected: selected,
                      onTap: () => onSelect(i),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = selected ? SaathiBeige.accentDeep : SaathiBeige.muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: SaathiBeige.accent.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: Icon(icon, size: 24, color: c),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: c,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                height: 3,
                width: selected ? 22 : 0,
                decoration: BoxDecoration(
                  color: SaathiBeige.accent.withValues(
                    alpha: selected ? 0.9 : 0,
                  ),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: SaathiBeige.accent.withValues(alpha: 0.45),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
