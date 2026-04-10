import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/saathi_beige_theme.dart';
import '../voice/voice_ui_phase.dart';

/// Morphing mic: idle mic ↔ slow circular sweep (listening / speaking / processing).
class PremiumVoiceMic extends StatefulWidget {
  const PremiumVoiceMic({
    super.key,
    required this.phase,
    this.inputLevel = 0,
    this.onTap,
    this.size = 104,
  });

  final VoiceUiPhase phase;
  final double inputLevel;
  final VoidCallback? onTap;
  final double size;

  @override
  State<PremiumVoiceMic> createState() => _PremiumVoiceMicState();
}

class _PremiumVoiceMicState extends State<PremiumVoiceMic>
    with TickerProviderStateMixin {
  late final AnimationController _morph;
  late final AnimationController _breath;
  late final AnimationController _orbit;

  @override
  void initState() {
    super.initState();
    _morph = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat(reverse: true);
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    )..repeat();
    _syncMorph();
  }

  void _syncMorph() {
    final alive = widget.phase != VoiceUiPhase.idle;
    if (alive) {
      _morph.forward();
    } else {
      _morph.reverse();
    }
  }

  @override
  void didUpdateWidget(covariant PremiumVoiceMic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _syncMorph();
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    _breath.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final breath = 0.94 + _breath.value * 0.04;
    final ringPulse = widget.phase == VoiceUiPhase.listening
        ? 1 + widget.inputLevel * 0.1
        : 1.0;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: s * 1.08,
        height: s * 1.08,
        child: Stack(
          alignment: Alignment.center,
          children: [
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _breath,
                builder: (context, _) {
                  final g =
                      0.18 + _breath.value * 0.1 + widget.inputLevel * 0.18;
                  return Container(
                    width: s * 1.06 * breath,
                    height: s * 1.06 * breath,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          SaathiBeige.accent.withValues(alpha: g * 0.4),
                          SaathiBeige.accent.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            AnimatedBuilder(
              animation: Listenable.merge([_morph, _breath, _orbit]),
              builder: (context, _) {
                final morph = CurvedAnimation(
                  parent: _morph,
                  curve: Curves.easeInOutCubic,
                ).value;
                return CustomPaint(
                  size: Size(s * ringPulse, s * ringPulse),
                  painter: _VoiceOrbPainter(
                    morph: morph,
                    phase: widget.phase,
                    inputLevel: widget.inputLevel,
                    breath: _breath.value,
                    orbitT: _orbit.value,
                  ),
                  child: SizedBox(
                    width: s * ringPulse,
                    height: s * ringPulse,
                    child: Center(
                      child: widget.phase == VoiceUiPhase.speaking
                          ? Icon(
                              Icons.stop_circle_rounded,
                              size: s * 0.38,
                              color: Colors.white,
                            )
                          : Opacity(
                              opacity: 1 - morph,
                              child: Icon(
                                Icons.mic_rounded,
                                size: s * 0.36,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceOrbPainter extends CustomPainter {
  _VoiceOrbPainter({
    required this.morph,
    required this.phase,
    required this.inputLevel,
    required this.breath,
    required this.orbitT,
  });

  final double morph;
  final VoiceUiPhase phase;
  final double inputLevel;
  final double breath;
  final double orbitT;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    final baseShadow = Paint()
      ..color = SaathiBeige.charcoal.withValues(alpha: 0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(c.translate(0, 4), r * 0.92, baseShadow);

    final body = Paint()
      ..shader = RadialGradient(
        colors: [
          SaathiBeige.accent.withValues(alpha: 0.95),
          SaathiBeige.accentDeep,
        ],
        stops: const [0.35, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r));

    canvas.drawCircle(c, r * (0.96 + breath * 0.015), body);

    if (morph < 0.02) return;

    canvas.save();
    canvas.translate(c.dx, c.dy);

    final ringR = r * 0.88;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.12 * morph)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.045;
    canvas.drawCircle(Offset.zero, ringR, track);

    // Phase-aware ring animation:
    // - Listening: progressive sweep ring
    // - Processing: spinning segmented arcs
    // - Speaking: full circular pulse with moving highlight
    const startLeft = math.pi;
    if (phase == VoiceUiPhase.processing) {
      final segPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.78 * morph)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..strokeCap = StrokeCap.round;
      final t = orbitT * 2 * math.pi;
      for (var i = 0; i < 3; i++) {
        final start = t + i * 2.1;
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: ringR),
          start,
          0.95,
          false,
          segPaint,
        );
      }
    } else if (phase == VoiceUiPhase.speaking) {
      final full = Paint()
        ..color = Colors.white.withValues(alpha: 0.42 * morph)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06;
      canvas.drawCircle(Offset.zero, ringR, full);
      final hi = Paint()
        ..color = Colors.white.withValues(alpha: 0.9 * morph)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: ringR),
        orbitT * 2 * math.pi,
        0.8,
        false,
        hi,
      );
    } else {
      final sweep = 2 * math.pi * orbitT;
      final arcPaint = Paint()
        ..color = Colors.white.withValues(
          alpha: (0.6 + inputLevel * 0.25) * morph,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.065
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: ringR),
        startLeft,
        sweep,
        false,
        arcPaint,
      );
    }

    canvas.restore();

    if (phase == VoiceUiPhase.listening && morph > 0.1) {
      final ring = Paint()
          ..color = Colors.white.withValues(alpha: 0.18 + inputLevel * 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
      canvas.drawCircle(c, r * (1.01 + inputLevel * 0.05), ring);
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceOrbPainter oldDelegate) {
    return oldDelegate.morph != morph ||
        oldDelegate.phase != phase ||
        oldDelegate.inputLevel != inputLevel ||
        oldDelegate.breath != breath ||
        oldDelegate.orbitT != orbitT;
  }
}
