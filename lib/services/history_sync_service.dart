import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';
import 'backend_config.dart';
import 'chat_history_storage.dart';

sealed class HistorySyncResult {
  const HistorySyncResult();
}

final class HistorySyncSuccess extends HistorySyncResult {
  const HistorySyncSuccess(this.messageCount);

  final int messageCount;
}

final class HistorySyncFailure extends HistorySyncResult {
  const HistorySyncFailure(this.message);

  final String message;
}

class HistorySyncService {
  HistorySyncService._();

  static final HistorySyncService instance = HistorySyncService._();

  Future<HistorySyncResult> syncHistoryForUser({required String userId}) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return const HistorySyncFailure('User id is empty.');
    }

    final endpoint = BackendConfig.historyEndpoint.trim();
    if (endpoint.isEmpty) {
      return const HistorySyncFailure('History endpoint is not configured.');
    }

    final baseUri = Uri.parse(endpoint);
    final uri = baseUri.replace(
      queryParameters: <String, String>{
        ...baseUri.queryParameters,
        'userId': normalizedUserId,
      },
    );

    late final http.Response response;
    try {
      response = await http.get(uri);
    } catch (error) {
      return HistorySyncFailure('History fetch failed: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return HistorySyncFailure(
        'History fetch failed (${response.statusCode}): ${response.body}',
      );
    }

    final parsed = jsonDecode(response.body);
    if (parsed is! Map<String, dynamic>) {
      return const HistorySyncFailure('History API returned invalid JSON.');
    }

    final status = (parsed['status'] as String?)?.trim().toLowerCase() ?? '';
    if (status != 'success') {
      return HistorySyncFailure(
        'History API returned non-success status: ${parsed['status']}',
      );
    }

    final data = parsed['data'];
    if (data is! List) {
      return const HistorySyncFailure('History API payload missing data list.');
    }

    final records = data.whereType<Map>().map((raw) {
      return Map<String, dynamic>.from(raw);
    }).toList()..sort(_compareByCreatedAtThenInput);

    final messages = <ChatMessage>[];
    final downloadedByUrl = <String, String?>{};
    final safeUserId = normalizedUserId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    for (var index = 0; index < records.length; index++) {
      final row = records[index];
      final createdAt =
          _parseCreatedAt(row['created_at']) ??
          DateTime.now().subtract(
            Duration(milliseconds: records.length - index),
          );
      final userInput = (row['user_input'] as String? ?? '').trim();
      final nbq = (row['nbq'] as String? ?? '').trim();
      final userAudioUrl = _pickAudioUrl(row);
      String? localUserAudioPath;
      if (userAudioUrl != null) {
        if (downloadedByUrl.containsKey(userAudioUrl)) {
          localUserAudioPath = downloadedByUrl[userAudioUrl];
        } else {
          final downloaded = await _downloadHistoryAudio(
            url: userAudioUrl,
            safeUserId: safeUserId,
            rowIndex: index,
          );
          downloadedByUrl[userAudioUrl] = downloaded;
          localUserAudioPath = downloaded;
        }
      }

      // Keep deterministic order and avoid accidental dedupe collisions
      // for repeated same-text rows with same timestamp.
      final baseTs = createdAt.add(Duration(milliseconds: index * 2));
      if (userInput.isNotEmpty) {
        messages.add(
          ChatMessage(
            text: userInput,
            isUser: true,
            isThinking: false,
            timestamp: baseTs,
            localUserAudioPath: localUserAudioPath,
          ),
        );
      }
      if (nbq.isNotEmpty) {
        messages.add(
          ChatMessage(
            text: nbq,
            isUser: false,
            isThinking: false,
            timestamp: baseTs.add(const Duration(milliseconds: 1)),
          ),
        );
      }
    }

    await ChatHistoryStorage.instance.saveMessages(messages);
    return HistorySyncSuccess(messages.length);
  }

  static int _compareByCreatedAtThenInput(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final at = _parseCreatedAt(a['created_at']);
    final bt = _parseCreatedAt(b['created_at']);
    if (at != null && bt != null) {
      final byDate = at.compareTo(bt);
      if (byDate != 0) {
        return byDate;
      }
    } else if (at != null) {
      return -1;
    } else if (bt != null) {
      return 1;
    }

    final aText = (a['user_input'] as String? ?? '').trim();
    final bText = (b['user_input'] as String? ?? '').trim();
    return aText.compareTo(bText);
  }

  static DateTime? _parseCreatedAt(dynamic raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  static String? _pickAudioUrl(Map<String, dynamic> row) {
    const keys = ['audio_url', 'audioUrl'];
    for (final key in keys) {
      final raw = row[key];
      if (raw is String) {
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
    }
    return null;
  }

  Future<String?> _downloadHistoryAudio({
    required String url,
    required String safeUserId,
    required int rowIndex,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    try {
      final response = await http
          .get(uri, headers: {'Accept': 'audio/*'})
          .timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (response.bodyBytes.isEmpty) return null;

      final docs = await getApplicationDocumentsDirectory();
      final historyDir = Directory('${docs.path}/chat-audio-history');
      if (!await historyDir.exists()) {
        await historyDir.create(recursive: true);
      }

      final ext = _audioExtensionFromUri(uri);
      final file = File(
        '${historyDir.path}/${safeUserId}_history_${DateTime.now().microsecondsSinceEpoch}_$rowIndex$ext',
      );
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static String _audioExtensionFromUri(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.wav')) return '.wav';
    if (path.endsWith('.aac')) return '.aac';
    if (path.endsWith('.m4a')) return '.m4a';
    if (path.endsWith('.ogg')) return '.ogg';
    return '.mp3';
  }
}
