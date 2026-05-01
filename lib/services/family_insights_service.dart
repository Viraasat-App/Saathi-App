import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_config.dart';

sealed class FamilyInsightsResult {
  const FamilyInsightsResult();
}

final class FamilyInsightsSuccess extends FamilyInsightsResult {
  const FamilyInsightsSuccess({
    required this.topPeople,
    required this.topEmotions,
  });

  final List<String> topPeople;
  final List<String> topEmotions;
}

final class FamilyInsightsFailure extends FamilyInsightsResult {
  const FamilyInsightsFailure(this.message);

  final String message;
}

final class FamilyMemory {
  const FamilyMemory({
    required this.memoryId,
    required this.summary,
    required this.audioUrl,
  });

  final String memoryId;
  final String summary;
  final String audioUrl;
}

sealed class FamilyMemoriesResult {
  const FamilyMemoriesResult();
}

final class FamilyMemoriesSuccess extends FamilyMemoriesResult {
  const FamilyMemoriesSuccess(this.memories);

  final List<FamilyMemory> memories;
}

final class FamilyMemoriesFailure extends FamilyMemoriesResult {
  const FamilyMemoriesFailure(this.message);

  final String message;
}

class FamilyInsightsService {
  FamilyInsightsService._();

  static final FamilyInsightsService instance = FamilyInsightsService._();

  Future<FamilyInsightsResult> fetchInsights({required String userId}) async {
    final endpoint = BackendConfig.familyInsightsEndpoint.trim();
    if (endpoint.isEmpty) {
      return const FamilyInsightsFailure(
        'Family insights endpoint is not configured.',
      );
    }

    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return const FamilyInsightsFailure('User id is empty.');
    }

    final body = jsonEncode(<String, String>{'user_id': normalizedUserId});
    late final http.Response response;
    try {
      response = await http.post(
        Uri.parse(endpoint),
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (error) {
      return FamilyInsightsFailure('Family insights request failed: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return FamilyInsightsFailure(
        'Family insights failed (${response.statusCode}): ${response.body}',
      );
    }

    final parsed = jsonDecode(response.body);
    if (parsed is! Map<String, dynamic>) {
      return const FamilyInsightsFailure('Invalid family insights response.');
    }

    final people = _extractStringList(parsed['top_people']);
    final emotions = _extractStringList(parsed['top_emotions']);
    return FamilyInsightsSuccess(topPeople: people, topEmotions: emotions);
  }

  Future<FamilyMemoriesResult> fetchMemories({
    required String userId,
    required String type,
    required String value,
  }) async {
    final endpoint = BackendConfig.memoriesEndpoint.trim();
    if (endpoint.isEmpty) {
      return const FamilyMemoriesFailure(
        'Memories endpoint is not configured.',
      );
    }

    final normalizedUserId = userId.trim();
    final normalizedType = type.trim().toLowerCase();
    final normalizedValue = value.trim();
    if (normalizedUserId.isEmpty) {
      return const FamilyMemoriesFailure('User id is empty.');
    }
    if (normalizedType != 'person' && normalizedType != 'emotion') {
      return const FamilyMemoriesFailure('Invalid memories request type.');
    }
    if (normalizedValue.isEmpty) {
      return const FamilyMemoriesFailure('Invalid memories request value.');
    }

    final body = jsonEncode(<String, String>{
      'user_id': normalizedUserId,
      'type': normalizedType,
      'value': normalizedValue,
    });
    late final http.Response response;
    try {
      response = await http.post(
        Uri.parse(endpoint),
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (error) {
      return FamilyMemoriesFailure('Memories request failed: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return FamilyMemoriesFailure(
        'Memories request failed (${response.statusCode}): ${response.body}',
      );
    }

    final parsed = jsonDecode(response.body);
    final normalizedPayload = _normalizeMapPayload(parsed);
    if (normalizedPayload == null) {
      return const FamilyMemoriesFailure('Invalid memories response.');
    }
    final rawMemories =
        _extractMemoriesList(normalizedPayload) ??
        _extractMemoriesListFromAny(normalizedPayload);
    if (rawMemories is! List) {
      return const FamilyMemoriesFailure(
        'Memories response missing memories list.',
      );
    }

    final memories = <FamilyMemory>[];
    for (final item in rawMemories.whereType<Map>()) {
      final map = Map<String, dynamic>.from(item);
      final memoryId = (map['memory_id'] as String? ?? '').trim();
      final summary = (map['summary'] as String? ?? '').trim();
      final audioUrl = (map['audio_url'] as String? ?? '').trim();
      if (summary.isEmpty || audioUrl.isEmpty) continue;
      memories.add(
        FamilyMemory(memoryId: memoryId, summary: summary, audioUrl: audioUrl),
      );
    }
    return FamilyMemoriesSuccess(memories);
  }

  static List<String> _extractStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item is String ? item.trim() : '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static Map<String, dynamic>? _normalizeMapPayload(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final body = payload['body'];
      if (body is String && body.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {
          // Keep using the original payload shape.
        }
      }
      return payload;
    }
    if (payload is String && payload.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          return _normalizeMapPayload(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  static List<dynamic>? _extractMemoriesList(Map<String, dynamic> map) {
    final direct = map['memories'];
    if (direct is List) return direct;
    return null;
  }

  static List<dynamic>? _extractMemoriesListFromAny(dynamic node) {
    if (node is Map<String, dynamic>) {
      final direct = node['memories'];
      if (direct is List) return direct;

      for (final key in const ['data', 'result', 'payload']) {
        final nested = node[key];
        final found = _extractMemoriesListFromAny(nested);
        if (found != null) return found;
      }

      for (final value in node.values) {
        final found = _extractMemoriesListFromAny(value);
        if (found != null) return found;
      }
      return null;
    }

    if (node is List) {
      final looksLikeMemories =
          node.isNotEmpty &&
          node.every((e) => e is Map && e.containsKey('summary'));
      if (looksLikeMemories) {
        return node.cast<dynamic>();
      }
      for (final item in node) {
        final found = _extractMemoriesListFromAny(item);
        if (found != null) return found;
      }
    }

    if (node is String && node.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(node);
        return _extractMemoriesListFromAny(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
