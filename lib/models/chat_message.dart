class ChatMessage {
  final String text;
  final bool isUser;
  final bool isThinking;
  final DateTime timestamp;
  final String? localUserAudioPath;
  final String? localBotAudioPath;

  /// Bot NBQ: show “Generating voice…” + Say now until cloud or device TTS finishes.
  final bool nbqAwaitingVoice;

  /// Stable id for this NBQ row (Say now + voice session).
  final String? nbqTurnId;

  /// [_ChatScreenState._nbqPlaybackGeneration] when this NBQ was added.
  final int? nbqVoiceGeneration;

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.isThinking,
    required this.timestamp,
    this.localUserAudioPath,
    this.localBotAudioPath,
    this.nbqAwaitingVoice = false,
    this.nbqTurnId,
    this.nbqVoiceGeneration,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final timestampRaw = json['timestamp'] as String?;
    final parsedTimestamp = timestampRaw == null
        ? null
        : DateTime.tryParse(timestampRaw);

    return ChatMessage(
      text: (json['text'] as String?) ?? '',
      isUser: (json['isUser'] as bool?) ?? false,
      isThinking: (json['isThinking'] as bool?) ?? false,
      timestamp: parsedTimestamp ?? DateTime.now(),
      localUserAudioPath: json['localUserAudioPath'] as String?,
      localBotAudioPath: json['localBotAudioPath'] as String?,
      nbqAwaitingVoice: (json['nbqAwaitingVoice'] as bool?) ?? false,
      nbqTurnId: json['nbqTurnId'] as String?,
      nbqVoiceGeneration: json['nbqVoiceGeneration'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'isThinking': isThinking,
    'timestamp': timestamp.toIso8601String(),
    'localUserAudioPath': localUserAudioPath,
    'localBotAudioPath': localBotAudioPath,
    'nbqAwaitingVoice': nbqAwaitingVoice,
    'nbqTurnId': nbqTurnId,
    'nbqVoiceGeneration': nbqVoiceGeneration,
  };
}
