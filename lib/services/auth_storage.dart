import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

class AuthStorage {
  AuthStorage._();
  static final AuthStorage instance = AuthStorage._();

  static const String _keyIsLoggedIn = 'isLoggedIn';
  static const String _keyCognitoSession = 'cognito_session';
  static const String _keyUserId = 'user_id';

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
    final sessionJson = prefs.getString(_keyCognitoSession);
    return loggedIn && sessionJson != null && sessionJson.isNotEmpty;
  }

  Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, value);
  }

  Future<void> saveSession(CognitoSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCognitoSession, jsonEncode(session.toJson()));
    await prefs.setString(_keyUserId, session.sub ?? '');
    await prefs.setBool(_keyIsLoggedIn, true);
  }

  Future<CognitoSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCognitoSession);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return CognitoSession.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<String?> currentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyUserId);
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final session = await loadSession();
    return session?.sub;
  }

  Future<String?> currentPhoneNumber() async {
    final session = await loadSession();
    return session?.username;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, false);
    await prefs.remove(_keyCognitoSession);
    await prefs.remove(_keyUserId);
  }
}
