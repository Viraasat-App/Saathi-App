import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';

class ChatHistoryStorage {
  ChatHistoryStorage._();
  static final ChatHistoryStorage instance = ChatHistoryStorage._();

  static const String _keyMessages = 'chat_messages_v1';
  static const String _keyHistoryOwnerUserId = 'chat_history_owner_user_id_v1';
  static const Duration _retention = Duration(days: 7);

  /// Stable identity for deduping (do **not** include audio paths or NBQ ids —
  /// the same bot line is often saved once with `nbqTurnId` and again after chrome clears).
  static String messageDedupeKey(ChatMessage m) {
    return '${m.timestamp.microsecondsSinceEpoch}|${m.isUser}|${m.text}';
  }

  /// Prefer cloud / NBQ cached audio over on-device TTS file (`bot_tts_`), so
  /// "Tap to Hear" + later cloud attach do not leave two history rows with different voices.
  static String? pickBotLocalAudioPath(String? x, String? y) {
    bool isDeviceTtsFile(String? p) =>
        p != null && p.contains('bot_tts_');

    final xe = x != null && x.isNotEmpty;
    final ye = y != null && y.isNotEmpty;
    if (xe && !isDeviceTtsFile(x)) return x;
    if (ye && !isDeviceTtsFile(y)) return y;
    if (xe) return x;
    if (ye) return y;
    return null;
  }

  static ChatMessage mergeDuplicateMessages(ChatMessage a, ChatMessage b) {
    String? pickPath(String? x, String? y) {
      if (x != null && x.isNotEmpty) return x;
      if (y != null && y.isNotEmpty) return y;
      return x ?? y;
    }

    return ChatMessage(
      text: a.text.isNotEmpty ? a.text : b.text,
      isUser: a.isUser,
      isThinking: a.isThinking && b.isThinking,
      timestamp: a.timestamp,
      localUserAudioPath: pickPath(a.localUserAudioPath, b.localUserAudioPath),
      localBotAudioPath: pickBotLocalAudioPath(
        a.localBotAudioPath,
        b.localBotAudioPath,
      ),
      nbqAwaitingVoice: a.nbqAwaitingVoice && b.nbqAwaitingVoice,
      nbqTurnId: a.nbqTurnId ?? b.nbqTurnId,
      nbqVoiceGeneration: a.nbqVoiceGeneration ?? b.nbqVoiceGeneration,
    );
  }

  List<ChatMessage> _dedupeMessages(List<ChatMessage> messages) {
    final map = <String, ChatMessage>{};
    for (final m in messages) {
      final k = messageDedupeKey(m);
      final e = map[k];
      map[k] = e == null ? m : mergeDuplicateMessages(e, m);
    }
    return map.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Merges consecutive bot bubbles with the same text when saves land a few
  /// seconds apart (e.g. Tap to Hear TTS file vs cloud `bot_*.mp3` with different timestamps).
  static List<ChatMessage> dedupeAdjacentIdenticalBotBubbles(
    List<ChatMessage> sortedChronological,
  ) {
    if (sortedChronological.length < 2) return sortedChronological;
    const window = Duration(seconds: 90);
    final out = <ChatMessage>[sortedChronological.first];
    for (var i = 1; i < sortedChronological.length; i++) {
      final m = sortedChronological[i];
      final prev = out.last;
      final t = m.text.trim();
      final merge = t.isNotEmpty &&
          t == prev.text.trim() &&
          !m.isUser &&
          !m.isThinking &&
          !prev.isUser &&
          !prev.isThinking &&
          m.timestamp.difference(prev.timestamp).abs() <= window;
      if (merge) {
        out[out.length - 1] = mergeDuplicateMessages(prev, m);
      } else {
        out.add(m);
      }
    }
    return out;
  }

  List<ChatMessage> _fullDedupe(List<ChatMessage> messages) {
    final once = _dedupeMessages(messages);
    return dedupeAdjacentIdenticalBotBubbles(once);
  }

  Future<List<ChatMessage>> loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyMessages);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      final loaded = decoded
          .whereType<Map>()
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final trimmed = _trimToRetention(loaded);
      final deduped = _fullDedupe(trimmed);
      await _deleteExpiredAudioFiles(loaded, deduped);
      if (deduped.length != loaded.length || deduped.length != trimmed.length) {
        await saveMessages(deduped);
      }
      return deduped;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMessages(List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = _trimToRetention(messages);
    final deduped = _fullDedupe(trimmed);
    await _deleteExpiredAudioFiles(messages, deduped);
    final raw = jsonEncode(deduped.map((m) => m.toJson()).toList());
    await prefs.setString(_keyMessages, raw);
  }

  /// Sets [localBotAudioPath] on the stored bot message matching [ref].
  Future<void> mergeLocalBotAudioPath(ChatMessage ref, String path) async {
    final all = await loadMessages();
    final refKey = messageDedupeKey(ref);
    var changed = false;
    final next = all.map((m) {
      if (!m.isUser &&
          !m.isThinking &&
          messageDedupeKey(m) == refKey &&
          (m.localBotAudioPath == null || m.localBotAudioPath!.isEmpty)) {
        changed = true;
        return ChatMessage(
          text: m.text,
          isUser: m.isUser,
          isThinking: m.isThinking,
          timestamp: m.timestamp,
          localUserAudioPath: m.localUserAudioPath,
          localBotAudioPath: path,
          nbqAwaitingVoice: m.nbqAwaitingVoice,
          nbqTurnId: m.nbqTurnId,
          nbqVoiceGeneration: m.nbqVoiceGeneration,
        );
      }
      return m;
    }).toList();
    if (changed) await saveMessages(next);
  }

  Future<void> clearAllLocalChatData() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadMessages();
    for (final message in existing) {
      final p = message.localUserAudioPath;
      if (p != null && p.isNotEmpty) {
        try {
          final file = File(p);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      final bot = message.localBotAudioPath;
      if (bot != null && bot.isNotEmpty) {
        try {
          final file = File(bot);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }

    try {
      final docs = await getApplicationDocumentsDirectory();
      final historyDir = Directory('${docs.path}/chat-audio-history');
      if (await historyDir.exists()) {
        await historyDir.delete(recursive: true);
      }
    } catch (_) {}

    await prefs.remove(_keyMessages);
    await prefs.remove(_keyHistoryOwnerUserId);
  }

  Future<void> clearIfUserChanged(String newUserId) async {
    final normalized = newUserId.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(_keyHistoryOwnerUserId)?.trim();
    if (previous != null && previous.isNotEmpty && previous != normalized) {
      await clearAllLocalChatData();
    }
    final prefsAfter = await SharedPreferences.getInstance();
    await prefsAfter.setString(_keyHistoryOwnerUserId, normalized);
  }

  List<ChatMessage> _trimToRetention(List<ChatMessage> messages) {
    final cutoff = DateTime.now().subtract(_retention);
    return messages.where((m) => m.timestamp.isAfter(cutoff)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> _deleteExpiredAudioFiles(
    List<ChatMessage> original,
    List<ChatMessage> kept,
  ) async {
    final keptPaths = kept
        .map((m) => m.localUserAudioPath)
        .whereType<String>()
        .toSet();
    final keptBotPaths = kept
        .map((m) => m.localBotAudioPath)
        .whereType<String>()
        .toSet();
    final stalePaths = original
        .map((m) => m.localUserAudioPath)
        .whereType<String>()
        .where((p) => !keptPaths.contains(p))
        .toSet();
    final staleBotPaths = original
        .map((m) => m.localBotAudioPath)
        .whereType<String>()
        .where((p) => !keptBotPaths.contains(p))
        .toSet();

    for (final p in stalePaths) {
      try {
        final file = File(p);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Best-effort cleanup for expired audio files.
      }
    }
    for (final p in staleBotPaths) {
      try {
        final file = File(p);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Best-effort cleanup for expired bot audio files.
      }
    }
  }
}
