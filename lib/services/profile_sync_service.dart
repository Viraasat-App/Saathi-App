import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/user_profile.dart';
import 'auth_service.dart';
import 'backend_config.dart';

sealed class ProfileSyncResult {
  const ProfileSyncResult();
}

final class ProfileSyncSuccess extends ProfileSyncResult {
  const ProfileSyncSuccess();
}

final class ProfileSyncFailure extends ProfileSyncResult {
  const ProfileSyncFailure(this.message);

  final String message;
}

class ProfileSyncService {
  ProfileSyncService._();

  static final ProfileSyncService instance = ProfileSyncService._();

  Future<ProfileSyncResult> syncProfile({
    required CognitoSession session,
    required UserProfile profile,
  }) async {
    final endpoint = BackendConfig.profileSyncEndpoint.trim();
    if (endpoint.isEmpty) {
      return const ProfileSyncFailure(
        'Profile sync endpoint is not configured.',
      );
    }

    final payload = <String, dynamic>{
      'user_id': profile.userId,
      'name': profile.name,
      'age': profile.age,
      'gender': profile.gender,
      'language': profile.language,
      'city': profile.city,
      'occupation': profile.occupation,
      'hobbies': profile.hobbies,
    };

    final headers = {
      'Content-Type': 'application/json',
      if (session.idToken.isNotEmpty)
        'Authorization': 'Bearer ${session.idToken}',
    };
    final body = jsonEncode(payload);

    try {
      var response = await http.post(
        Uri.parse(endpoint),
        headers: headers,
        body: body,
      );

      // Some backends use PUT for updates; fallback automatically for better compatibility.
      if (response.statusCode == 404 || response.statusCode == 405) {
        response = await http.put(
          Uri.parse(endpoint),
          headers: headers,
          body: body,
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const ProfileSyncSuccess();
      }

      return ProfileSyncFailure(
        'Profile sync failed (${response.statusCode}): ${response.body}',
      );
    } catch (error) {
      return ProfileSyncFailure('Profile sync failed: $error');
    }
  }
}
