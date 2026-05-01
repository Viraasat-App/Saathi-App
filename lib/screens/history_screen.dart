import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';
import '../services/chat_history_storage.dart';
import '../theme/saathi_beige_theme.dart';
import '../widgets/floating_voice_nav_bar.dart';
import '../widgets/message_bubble.dart';
import 'family_screen.dart';
import 'settings_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const String _introMessage =
      'Press the microphone to talk to your voice companion.';
  static const String _aiAccuracyDisclaimer =
      'AI responses may not always be accurate.';
  List<ChatMessage> _messages = [];
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  String? _activeAudioPath;
  bool _isAudioPaused = false;
  StreamSubscription<PlayerState>? _playerStateSub;

  @override
  void initState() {
    super.initState();
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _activeAudioPath = null;
          _isAudioPaused = false;
        });
      }
    });
    unawaited(_configureTts());
    _loadHistory();
  }

  Future<void> _configureTts() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.awaitSynthCompletion(true);
    } catch (_) {}
  }

  Future<String?> _synthesizeBotSpeechToFile(String text) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    if (kIsWeb) return null;
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final historyDir = Directory('${docs.path}/chat-audio-history');
      if (!await historyDir.exists()) {
        await historyDir.create(recursive: true);
      }
      final out =
          '${historyDir.path}/bot_tts_${DateTime.now().microsecondsSinceEpoch}.wav';
      await _tts.awaitSynthCompletion(true);
      await _tts.synthesizeToFile(t, out, true);
      final f = File(out);
      if (await f.exists() && await f.length() > 0) return out;
    } catch (e) {
      debugPrint('History TTS synthesizeToFile: $e');
    }
    return null;
  }

  /// Oldest at the top, newest at the bottom. Same timestamp: user before bot.
  static int _historyChronologicalCmp(ChatMessage a, ChatMessage b) {
    final byTime = a.timestamp.compareTo(b.timestamp);
    if (byTime != 0) return byTime;
    if (a.isUser != b.isUser) return a.isUser ? -1 : 1;
    return 0;
  }

  static List<ChatMessage> _prepareHistoryMessages(
    Iterable<ChatMessage> messages,
  ) {
    final filtered = messages
        .where(
          (m) =>
              !m.isThinking &&
              m.text.trim().isNotEmpty &&
              m.text.trim() != _introMessage,
        )
        .toList()
      ..sort(_historyChronologicalCmp);
    return filtered;
  }

  void _scheduleJumpToBottom() {
    var frames = 0;
    void afterLayout() {
      if (!mounted) return;
      frames++;
      if (_scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        if (max > 0) _scrollController.jumpTo(max);
      }
      // Variable-height [ListView.builder]: extent can grow over a few layouts.
      if (frames < 5) {
        WidgetsBinding.instance.addPostFrameCallback((_) => afterLayout());
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => afterLayout());
  }

  Future<void> _loadHistory() async {
    final messages = await ChatHistoryStorage.instance.loadMessages();
    if (!mounted) return;
    setState(() {
      _messages = _prepareHistoryMessages(messages);
      _loading = false;
    });
    if (_messages.isNotEmpty) _scheduleJumpToBottom();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _playerStateSub?.cancel();
    _player.dispose();
    unawaited(_tts.stop());
    super.dispose();
  }

  Future<void> _playUserAudio(ChatMessage message) async {
    final path = message.localUserAudioPath;
    if (path == null || path.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No local recording for this message')),
      );
      return;
    }
    final f = File(path);
    if (!await f.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This recording is no longer available')),
      );
      return;
    }
    try {
      if (!mounted) return;
      setState(() {
        _activeAudioPath = path;
        _isAudioPaused = false;
      });
      await _player.stop();
      await _player.setFilePath(path);
      unawaited(_player.play());
    } catch (_) {
      if (mounted) {
        setState(() {
          _activeAudioPath = null;
          _isAudioPaused = false;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play this recording')),
      );
    }
  }

  Future<void> _playBotAudio(ChatMessage message) async {
    var path = message.localBotAudioPath;
    if (path == null || path.isEmpty) {
      if (message.text.trim().isEmpty) return;
      final synthesized = await _synthesizeBotSpeechToFile(message.text);
      if (synthesized != null) {
        final savedPath = synthesized;
        path = savedPath;
        await ChatHistoryStorage.instance.mergeLocalBotAudioPath(
          message,
          savedPath,
        );
        if (!mounted) return;
        final refKey = ChatHistoryStorage.messageDedupeKey(message);
        setState(() {
          _messages = _messages.map((m) {
            if (!m.isUser &&
                !m.isThinking &&
                ChatHistoryStorage.messageDedupeKey(m) == refKey) {
              return ChatMessage(
                text: m.text,
                isUser: m.isUser,
                isThinking: m.isThinking,
                timestamp: m.timestamp,
                localUserAudioPath: m.localUserAudioPath,
                localBotAudioPath: savedPath,
                nbqAwaitingVoice: m.nbqAwaitingVoice,
                nbqTurnId: m.nbqTurnId,
                nbqVoiceGeneration: m.nbqVoiceGeneration,
              );
            }
            return m;
          }).toList();
        });
      }
    }
    if (path == null || path.isEmpty) {
      if (message.text.trim().isEmpty) return;
      try {
        await _player.stop();
        await _tts.stop();
        await _tts.speak(message.text);
      } catch (_) {}
      return;
    }
    final f = File(path);
    if (!await f.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This response audio is no longer available')),
      );
      return;
    }
    try {
      if (!mounted) return;
      setState(() {
        _activeAudioPath = path;
        _isAudioPaused = false;
      });
      await _tts.stop();
      await _player.stop();
      await _player.setFilePath(path);
      unawaited(_player.play());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activeAudioPath = null;
        _isAudioPaused = false;
      });
    }
  }

  Future<void> _pauseOrResumeAudio() async {
    if (_activeAudioPath == null) return;
    try {
      if (_isAudioPaused) {
        unawaited(_player.play());
        if (!mounted) return;
        setState(() => _isAudioPaused = false);
      } else {
        await _player.pause();
        if (!mounted) return;
        setState(() => _isAudioPaused = true);
      }
    } catch (_) {}
  }

  Future<void> _stopAudio() async {
    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _activeAudioPath = null;
      _isAudioPaused = false;
    });
  }

  String _dayHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isCalendarToday(DateTime t) {
    final now = DateTime.now();
    return t.year == now.year && t.month == now.month && t.day == now.day;
  }

  bool get _hasTodayMessages =>
      _messages.any((m) => _isCalendarToday(m.timestamp));

  /// Older days above; append [Today] + empty hint when nothing logged today.
  bool get _showTrailingTodayEmpty =>
      _messages.isNotEmpty && !_hasTodayMessages;

  Widget _dayHeaderPill(BuildContext context, DateTime date) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(_dayHeader(date)),
        ),
      ),
    );
  }

  Widget _todayNoMessagesBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dayHeaderPill(context, DateTime.now()),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 2),
          child: Text(
            'No messages',
            textAlign: TextAlign.center,
            style: TextStyle(color: SaathiBeige.muted, fontSize: 15),
          ),
        ),
      ],
    );
  }

  Future<void> _onBottomNavTap(int index) async {
    if (index == 0) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (index == 1) {
      return;
    }
    if (index == 2) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const FamilyScreen()),
      );
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
    const contentTop = 8.0;
    final trailingToday = _showTrailingTodayEmpty ? 1 : 0;
    return Scaffold(
      backgroundColor: SaathiBeige.cream,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: SaathiBeige.cream,
        surfaceTintColor: SaathiBeige.cream,
        foregroundColor: SaathiBeige.charcoal,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('History'),
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
        child: _loading
            ? Padding(
                padding: EdgeInsets.only(top: contentTop),
                child: const Center(child: CircularProgressIndicator()),
              )
            : _messages.isEmpty
            ? Padding(
                padding: EdgeInsets.fromLTRB(8, contentTop, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          'No chats from the last 7 days',
                          style: TextStyle(
                            color: SaathiBeige.muted,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 132),
                      child: _todayNoMessagesBody(context),
                    ),
                  ],
                ),
              )
            : ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(8, contentTop, 8, 132),
              itemCount: _messages.length + trailingToday,
              itemBuilder: (context, index) {
                if (index >= _messages.length) {
                  return _todayNoMessagesBody(context);
                }
                final m = _messages[index];
                final prev = index == 0 ? null : _messages[index - 1];
                final needsHeader =
                    prev == null || !_isSameDay(prev.timestamp, m.timestamp);
                final hasBotPath =
                    (m.localBotAudioPath ?? '').trim().isNotEmpty;
                return Column(
                  children: [
                    if (needsHeader) _dayHeaderPill(context, m.timestamp),
                    MessageBubble(
                      message: m,
                      onUserAudioTap: m.isUser && !m.isThinking
                          ? () => _playUserAudio(m)
                          : null,
                      isUserAudioActive:
                          m.localUserAudioPath != null &&
                          m.localUserAudioPath == _activeAudioPath,
                      isUserAudioPaused:
                          m.localUserAudioPath != null &&
                          m.localUserAudioPath == _activeAudioPath &&
                          _isAudioPaused,
                      onUserAudioPause:
                          m.localUserAudioPath != null &&
                              m.localUserAudioPath == _activeAudioPath
                          ? _pauseOrResumeAudio
                          : null,
                      onUserAudioStop:
                          m.localUserAudioPath != null &&
                              m.localUserAudioPath == _activeAudioPath
                          ? _stopAudio
                          : null,
                      onBotAudioTap: !m.isUser &&
                              !m.isThinking &&
                              m.text.trim().isNotEmpty &&
                              hasBotPath
                          ? () => _playBotAudio(m)
                          : null,
                      onBotAudioPause: (m.localBotAudioPath ?? '').isNotEmpty &&
                              m.localBotAudioPath == _activeAudioPath
                          ? _pauseOrResumeAudio
                          : null,
                      onBotAudioStop: (m.localBotAudioPath ?? '').isNotEmpty &&
                              m.localBotAudioPath == _activeAudioPath
                          ? _stopAudio
                          : null,
                      isBotAudioActive: (m.localBotAudioPath ?? '').isNotEmpty &&
                          m.localBotAudioPath == _activeAudioPath,
                      isBotAudioPaused: (m.localBotAudioPath ?? '').isNotEmpty &&
                          m.localBotAudioPath == _activeAudioPath &&
                          _isAudioPaused,
                    ),
                  ],
                );
              },
            ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FloatingVoiceNavBar(
                currentIndex: 1,
                onSelect: (i) => unawaited(_onBottomNavTap(i)),
              ),
              const SizedBox(height: 6),
              Text(
                _aiAccuracyDisclaimer,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  color: SaathiBeige.muted.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
