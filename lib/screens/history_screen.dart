import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/auth_storage.dart';
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
  static const String _historyEndpoint =
      'https://91mgbx082j.execute-api.ap-south-1.amazonaws.com/getHistory';
  static const String _introMessage =
      'Press the microphone to talk to your voice companion.';
  static const String _aiAccuracyDisclaimer =
      'AI responses may not always be accurate.';
  List<ChatMessage> _messages = [];
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
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
    try {
      final userId = await AuthStorage.instance.currentUserId();
      if (userId != null && userId.trim().isNotEmpty) {
        await ChatHistoryStorage.instance.hydrateRemoteHistoryOnce(
          userId: userId,
          endpointBase: _historyEndpoint,
        );
      }
    } catch (_) {}

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
    super.dispose();
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
                return Column(
                  children: [
                    if (needsHeader) _dayHeaderPill(context, m.timestamp),
                    MessageBubble(
                      message: m,
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
