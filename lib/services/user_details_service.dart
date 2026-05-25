import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/user_profile.dart';
import 'backend_config.dart';

sealed class FetchUserDetailsResult {
  const FetchUserDetailsResult();
}

class FetchUserDetailsSuccess extends FetchUserDetailsResult {
  const FetchUserDetailsSuccess(this.profile);
  final UserProfile profile;
}

class FetchUserDetailsFailure extends FetchUserDetailsResult {
  const FetchUserDetailsFailure(this.message);
  final String message;
}

sealed class UpdateUserDetailsResult {
  const UpdateUserDetailsResult();
}

class UpdateUserDetailsSuccess extends UpdateUserDetailsResult {
  const UpdateUserDetailsSuccess(this.profile);
  final UserProfile profile;
}

class UpdateUserDetailsFailure extends UpdateUserDetailsResult {
  const UpdateUserDetailsFailure(this.message);
  final String message;
}

/// Fetches a stored user profile from the backend `getUserDetails` API
/// (used during the "Log In" flow for existing users).
class UserDetailsService {
  UserDetailsService._();
  static final UserDetailsService instance = UserDetailsService._();

  static const Duration _timeout = Duration(seconds: 20);

  Future<FetchUserDetailsResult> fetchUserDetails({
    required String userId,
    required String phoneNumber,
  }) async {
    if (userId.trim().isEmpty) {
      return const FetchUserDetailsFailure('Missing user id.');
    }
    final endpoint = BackendConfig.userDetailsEndpoint.trim();
    if (endpoint.isEmpty) {
      return const FetchUserDetailsFailure(
        'User details endpoint is not configured.',
      );
    }

    final baseUri = Uri.parse(endpoint);
    final uri = baseUri.replace(
      queryParameters: {
        ...baseUri.queryParameters,
        'userId': userId,
      },
    );

    try {
      final response = await http.get(uri).timeout(_timeout);
      if (kDebugMode) {
        debugPrint(
          '[getUserDetails] GET $uri status=${response.statusCode}',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return FetchUserDetailsFailure(
          'Could not load profile (HTTP ${response.statusCode}).',
        );
      }

      final dynamic parsed;
      try {
        parsed = jsonDecode(response.body);
      } catch (_) {
        return const FetchUserDetailsFailure('Invalid profile response.');
      }
      if (parsed is! Map<String, dynamic>) {
        return const FetchUserDetailsFailure('Invalid profile response.');
      }
      final status = (parsed['status'] as String?)?.toLowerCase();
      final data = parsed['data'];
      if (status != 'success' || data is! Map<String, dynamic>) {
        return const FetchUserDetailsFailure(
          'User does not exist. Please complete your profile.',
        );
      }

      String asString(dynamic v) =>
          v == null ? '' : v.toString().trim();
      int asAge(dynamic v) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(asString(v)) ?? 0;
      }

      final name = asString(data['name']);
      final age = asAge(data['age']);
      final gender = asString(data['gender']);
      final language = asString(data['language']);
      final city = asString(data['city']);
      final occupation = asString(data['occupation']);
      final hobbies = asString(data['hobbies']);

      // Backend returns success with empty fields when no profile exists yet.
      // Treat that as "user not found" so caller can route to profile setup.
      final isEmpty = name.isEmpty &&
          age == 0 &&
          gender.isEmpty &&
          language.isEmpty &&
          city.isEmpty &&
          occupation.isEmpty &&
          hobbies.isEmpty;
      if (isEmpty) {
        return const FetchUserDetailsFailure(
          'User does not exist. Please complete your profile.',
        );
      }

      final profile = UserProfile(
        userId: userId,
        phoneNumber: phoneNumber,
        name: name,
        age: age,
        gender: gender,
        language: language,
        city: city,
        occupation: occupation,
        hobbies: hobbies,
      );
      return FetchUserDetailsSuccess(profile);
    } on TimeoutException {
      return const FetchUserDetailsFailure('Profile request timed out.');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[getUserDetails] error: $e\n$st');
      }
      return FetchUserDetailsFailure('Could not load profile.');
    }
  }

  /// PUT only the changed fields to the backend. [changes] should already
  /// contain only the modified keys (e.g. `name`, `age`, `gender`, ...).
  /// On success, returns a [UserProfile] parsed from `data.user_details`.
  Future<UpdateUserDetailsResult> updateUserDetails({
    required String userId,
    required String phoneNumber,
    required Map<String, dynamic> changes,
  }) async {
    if (userId.trim().isEmpty) {
      return const UpdateUserDetailsFailure('Missing user id.');
    }
    if (changes.isEmpty) {
      return const UpdateUserDetailsFailure('Nothing to update.');
    }
    final endpoint = BackendConfig.updateUserDetailsEndpoint.trim();
    if (endpoint.isEmpty) {
      return const UpdateUserDetailsFailure(
        'Update endpoint is not configured.',
      );
    }

    final body = <String, dynamic>{
      'userId': userId,
      ...changes,
    };

    try {
      final response = await http
          .put(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (kDebugMode) {
        debugPrint(
          '[updateUserDetails] PUT $endpoint status=${response.statusCode}',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return UpdateUserDetailsFailure(
          'Could not save profile (HTTP ${response.statusCode}).',
        );
      }

      final dynamic parsed;
      try {
        parsed = jsonDecode(response.body);
      } catch (_) {
        return const UpdateUserDetailsFailure('Invalid update response.');
      }
      if (parsed is! Map<String, dynamic>) {
        return const UpdateUserDetailsFailure('Invalid update response.');
      }
      final status = (parsed['status'] as String?)?.toLowerCase();
      final data = parsed['data'];
      if (status != 'success' || data is! Map<String, dynamic>) {
        final msg = data is Map<String, dynamic>
            ? (data['message'] as String?) ?? 'Could not save profile.'
            : 'Could not save profile.';
        return UpdateUserDetailsFailure(msg);
      }
      final details = data['user_details'];
      if (details is! Map<String, dynamic>) {
        return const UpdateUserDetailsFailure(
          'Update succeeded but response was malformed.',
        );
      }

      String asString(dynamic v) => v == null ? '' : v.toString().trim();
      int asAge(dynamic v) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(asString(v)) ?? 0;
      }

      final profile = UserProfile(
        userId: asString(details['user_id']).isNotEmpty
            ? asString(details['user_id'])
            : userId,
        phoneNumber: phoneNumber,
        name: asString(details['name']),
        age: asAge(details['age']),
        gender: asString(details['gender']),
        language: asString(details['language']),
        city: asString(details['city']),
        occupation: asString(details['occupation']),
        hobbies: asString(details['hobbies']),
      );
      return UpdateUserDetailsSuccess(profile);
    } on TimeoutException {
      return const UpdateUserDetailsFailure('Update request timed out.');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[updateUserDetails] error: $e\n$st');
      }
      return const UpdateUserDetailsFailure('Could not save profile.');
    }
  }
}
