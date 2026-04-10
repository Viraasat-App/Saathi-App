import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onNbqSayNow;
  final VoidCallback? onUserAudioTap;
  final VoidCallback? onUserAudioPause;
  final VoidCallback? onUserAudioStop;
  final bool isUserAudioActive;
  final bool isUserAudioPaused;
  final VoidCallback? onBotAudioTap;
  final VoidCallback? onBotAudioPause;
  final VoidCallback? onBotAudioStop;
  final bool isBotAudioActive;
  final bool isBotAudioPaused;

  const MessageBubble({
    super.key,
    required this.message,
    this.onNbqSayNow,
    this.onUserAudioTap,
    this.onUserAudioPause,
    this.onUserAudioStop,
    this.isUserAudioActive = false,
    this.isUserAudioPaused = false,
    this.onBotAudioTap,
    this.onBotAudioPause,
    this.onBotAudioStop,
    this.isBotAudioActive = false,
    this.isBotAudioPaused = false,
  });

  /// Outgoing bubble — beige theme.
  static const Color _waOutgoing = Color(0xFFEBE0BE);
  static const Color _waIncoming = Color(0xFFFFFFFF);
  static const Color _waIncomingBorder = Color(0xFFE1E8ED);
  static const Color _waText = Color(0xFF111B21);
  static const Color _waThinkingBg = Color(0xFFF0F2F5);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final maxBubble = math.min(260.0, MediaQuery.sizeOf(context).width * 0.68);

    late final Color bubbleColor;
    late final Color textColor;
    BoxBorder? bubbleBorder;
    List<BoxShadow>? bubbleShadow;

    if (message.isThinking) {
      bubbleColor = _waThinkingBg;
      textColor = _waText.withValues(alpha: 0.72);
      bubbleBorder = Border.all(color: _waIncomingBorder);
    } else if (isUser) {
      bubbleColor = _waOutgoing;
      textColor = _waText;
      bubbleShadow = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];
    } else {
      bubbleColor = _waIncoming;
      textColor = _waText;
      bubbleBorder = Border.all(color: _waIncomingBorder);
      bubbleShadow = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];
    }

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isUser ? 16 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 16),
    );

    final showNbqChrome = message.nbqAwaitingVoice && onNbqSayNow != null;
    final tod = TimeOfDay.fromDateTime(message.timestamp);
    final minute = tod.minute.toString().padLeft(2, '0');
    final period = tod.period == DayPeriod.am ? 'am' : 'pm';
    final hour12 = (tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod).toString();
    final timeLabel = '$hour12:$minute$period';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        label: isUser
            ? 'Your message'
            : (message.isThinking ? 'AI is thinking' : 'AI message'),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          constraints: BoxConstraints(maxWidth: maxBubble),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: radius,
            border: bubbleBorder,
            boxShadow: bubbleShadow,
          ),
          child: message.isThinking
              ? Text(
                  message.text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      message.text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: textColor,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    if (showNbqChrome) ...[
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            scheme.surface.withValues(alpha: 0.22),
                            bubbleColor,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: scheme.outline.withValues(alpha: 0.45),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExcludeSemantics(
                                child: Text(
                                  'Generating voice...',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: textColor.withValues(
                                          alpha: 0.92,
                                        ),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        fontStyle: FontStyle.italic,
                                        letterSpacing: 0.2,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    button: true,
                                    label:
                                        'Say now. Play this question using your device text to speech',
                                    child: OutlinedButton(
                                      onPressed: onNbqSayNow,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: scheme.primary,
                                        backgroundColor: scheme.surface
                                            .withValues(alpha: 0.35),
                                        side: BorderSide(
                                          color: scheme.primary.withValues(
                                            alpha: 0.85,
                                          ),
                                          width: 1.75,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 12,
                                        ),
                                        minimumSize: const Size(0, 44),
                                        tapTargetSize:
                                            MaterialTapTargetSize.padded,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        textStyle: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                            ),
                                      ),
                                      child: const Text('Say now'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: ExcludeSemantics(
                                        child: Text(
                                          'Waiting for cloud audio. Nothing plays until it arrives or you tap Say now.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: textColor.withValues(
                                                  alpha: 0.78,
                                                ),
                                                fontSize: 14,
                                                height: 1.35,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: isUser
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: _audioActionForBubble(
                                context: context,
                                textColor: textColor,
                                isUser: isUser,
                              ) ??
                              const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timeLabel,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: textColor.withValues(alpha: 0.55),
                                fontSize: 10,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Explicit branching so bot “Tap to Hear” is never dropped by nested `if` layout rules.
  Widget? _audioActionForBubble({
    required BuildContext context,
    required Color textColor,
    required bool isUser,
  }) {
    if (isUser) {
      if (isUserAudioActive) {
        return _audioControlRow(
          context: context,
          textColor: textColor,
          paused: isUserAudioPaused,
          onPause: onUserAudioPause,
          onStop: onUserAudioStop,
        );
      }
      if (onUserAudioTap != null) {
        return _audioTapChip(
          context: context,
          textColor: textColor,
          onTap: onUserAudioTap!,
        );
      }
      return null;
    }
    if (isBotAudioActive) {
      return _audioControlRow(
        context: context,
        textColor: textColor,
        paused: isBotAudioPaused,
        onPause: onBotAudioPause,
        onStop: onBotAudioStop,
      );
    }
    if (onBotAudioTap != null) {
      return _audioTapChip(
        context: context,
        textColor: textColor,
        onTap: onBotAudioTap!,
      );
    }
    return null;
  }

  Widget _audioControlRow({
    required BuildContext context,
    required Color textColor,
    required bool paused,
    required VoidCallback? onPause,
    VoidCallback? onStop,
  }) {
    final btnStyle = OutlinedButton.styleFrom(
      foregroundColor: textColor.withValues(alpha: 0.9),
      side: BorderSide(color: textColor.withValues(alpha: 0.55), width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: onPause,
          icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 18),
          label: Text(paused ? 'Play' : 'Pause'),
          style: btnStyle,
        ),
        if (onStop != null)
          OutlinedButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop, size: 18),
            label: const Text('Stop'),
            style: btnStyle,
          ),
      ],
    );
  }

  Widget _audioTapChip({
    required BuildContext context,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: textColor.withValues(alpha: 0.55), width: 1.2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.volume_up_rounded,
                  size: 22,
                  color: textColor.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 4),
                Text(
                  'Tap to Hear',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: textColor.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
