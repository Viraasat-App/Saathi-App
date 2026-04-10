import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cognito_config.dart';

/// Outcome of requesting an SMS OTP for a phone number.
sealed class SendOtpResult {
  const SendOtpResult();
}

/// SMS was sent; user should enter the code. [normalizedPhone] is E.164.
final class SendOtpCodeSent extends SendOtpResult {
  const SendOtpCodeSent(this.normalizedPhone);
  final String normalizedPhone;
}

final class SendOtpFailure extends SendOtpResult {
  const SendOtpFailure(this.message);
  final String message;
}

/// Successful Cognito session after OTP verification.
final class CognitoSession {
  const CognitoSession({
    required this.username,
    required this.idToken,
    required this.accessToken,
    required this.refreshToken,
    this.tokenType,
    this.expiresIn,
  });

  final String username;
  final String idToken;
  final String accessToken;
  final String refreshToken;
  final String? tokenType;
  final int? expiresIn;

  String? get sub => _decodeJwtSub(idToken);

  Map<String, dynamic> toJson() => {
    'username': username,
    'idToken': idToken,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'tokenType': tokenType,
    'expiresIn': expiresIn,
  };

  factory CognitoSession.fromJson(Map<String, dynamic> json) {
    return CognitoSession(
      username: (json['username'] ?? '') as String,
      idToken: (json['idToken'] ?? '') as String,
      accessToken: (json['accessToken'] ?? '') as String,
      refreshToken: (json['refreshToken'] ?? '') as String,
      tokenType: json['tokenType'] as String?,
      expiresIn: json['expiresIn'] is int
          ? json['expiresIn'] as int
          : int.tryParse('${json['expiresIn']}'),
    );
  }
}

/// Outcome of verifying the SMS code.
sealed class VerifyOtpResult {
  const VerifyOtpResult();
}

final class VerifyOtpSuccess extends VerifyOtpResult {
  const VerifyOtpSuccess(this.session);
  final CognitoSession session;
}

final class VerifyOtpFailure extends VerifyOtpResult {
  const VerifyOtpFailure(this.message);
  final String message;
}

final class _InitiateAuthResult {
  const _InitiateAuthResult.success(this.session) : errorMessage = null;
  const _InitiateAuthResult.failure(this.errorMessage) : session = null;

  final CognitoSession? session;
  final String? errorMessage;
}

enum _OtpFlow { none, signUpConfirm, forgotPassword }

/// AWS Cognito User Pools phone OTP using unauthenticated IdP JSON API
/// (no IAM signing; app client must not require a secret, or provide [CognitoConfig.clientSecret]).
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();
  static const String _cognitoOtpPassword = 'Dummy@1234';
  bool _useDevOtp = kDebugMode;

  String? _username;
  String? _password;
  _OtpFlow _flow = _OtpFlow.none;

  CognitoSession? _session;

  /// Tokens after successful OTP verification; cleared on [signOut].
  CognitoSession? get currentSession => _session;
  bool get useDevelopmentOtp => _useDevOtp;

  void setOtpMode({required bool useDevelopmentOtp}) {
    _useDevOtp = useDevelopmentOtp;
  }

  String? get lastNormalizedPhone => _username;

  void clearPhoneVerificationState() {
    _username = null;
    _password = null;
    _flow = _OtpFlow.none;
  }

  Future<void> signOut() async {
    _session = null;
    clearPhoneVerificationState();
  }

  Future<void> logAuthenticationDebug(CognitoSession session) async {
    debugPrint('Cognito sub: ${session.sub ?? "(parse failed)"}');
    debugPrint('Cognito id token: ${session.idToken}');
    debugPrint('Cognito access token: ${session.accessToken}');
    debugPrint('Cognito refresh token: ${session.refreshToken}');
  }

  /// Normalizes to E.164: optional `+`, or 10 digits → `+91…`.
  static String normalizePhoneNumber(String raw) {
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (trimmed.startsWith('+')) {
      return '+$digits';
    }
    if (digits.length == 10) {
      return '+91$digits';
    }
    return '+$digits';
  }

  static String? validatePhoneForOtp(String raw) {
    final normalized = normalizePhoneNumber(raw);
    if (normalized.length < 8) {
      return 'Enter a valid phone number with country code (e.g. +91…).';
    }
    return null;
  }

  Future<SendOtpResult> sendOtp(String phoneNumber) async {
    if (CognitoConfig.clientId.isEmpty) {
      return const SendOtpFailure(
        'Cognito app client is not configured. Build with '
        '--dart-define=COGNITO_CLIENT_ID=your_app_client_id '
        '(and optionally COGNITO_REGION).',
      );
    }

    final err = validatePhoneForOtp(phoneNumber);
    if (err != null) {
      return SendOtpFailure(err);
    }

    final normalized = normalizePhoneNumber(phoneNumber);
    _username = normalized;
    _password = _cognitoOtpPassword;
    _flow = _OtpFlow.none;

    if (_useDevOtp) {
      _flow = _OtpFlow.signUpConfirm;
      return SendOtpCodeSent(normalized);
    }

    final signUpRes = await _signUp(normalized, _password!);
    if (signUpRes == null) {
      _flow = _OtpFlow.signUpConfirm;
      return SendOtpCodeSent(normalized);
    }

    if (signUpRes.isUsernameExists) {
      final fpRes = await _forgotPassword(normalized);
      if (fpRes == null) {
        _flow = _OtpFlow.forgotPassword;
        return SendOtpCodeSent(normalized);
      }
      if (fpRes.isUserNotConfirmed || fpRes.messageContains('not confirmed')) {
        return SendOtpFailure(
          'This number is already registered but not verified. '
          'Confirm the account in AWS Cognito or use a pool flow that supports resend for your setup.',
        );
      }
      return SendOtpFailure(fpRes.message);
    }

    return SendOtpFailure(signUpRes.message);
  }

  Future<VerifyOtpResult> verifyOtp(String otp) async {
    final code = otp.trim();
    if (code.length < 4) {
      return const VerifyOtpFailure('Enter the verification code from SMS.');
    }

    final username = _username;
    final password = _password;
    if (username == null || password == null || _flow == _OtpFlow.none) {
      return const VerifyOtpFailure('Request OTP first.');
    }

    if (_useDevOtp) {
      // Dev only: user id = entered OTP (digits). Each different code is a distinct user.
      final devSub = code.replaceAll(RegExp(r'\D'), '');
      if (devSub.length < 6) {
        return const VerifyOtpFailure(
          'Enter a 6-digit code in development mode.',
        );
      }
      final session = CognitoSession(
        username: username,
        idToken: _buildDevJwt(username, 'id', devSub),
        accessToken: _buildDevJwt(username, 'access', devSub),
        refreshToken: 'dev-refresh-$devSub',
        tokenType: 'Bearer',
        expiresIn: 3600,
      );
      _session = session;
      clearPhoneVerificationState();
      return VerifyOtpSuccess(session);
    }

    switch (_flow) {
      case _OtpFlow.signUpConfirm:
        final cErr = await _confirmSignUp(username, code);
        if (cErr != null) {
          return VerifyOtpFailure(cErr.message);
        }
        final authResult = await _initiateUserPasswordAuth(username, password);
        final session = authResult.session;
        if (session == null) {
          return VerifyOtpFailure(
            authResult.errorMessage ??
                'Signed up but could not sign in. Check your Cognito app client auth flow settings.',
          );
        }
        _session = session;
        clearPhoneVerificationState();
        return VerifyOtpSuccess(session);

      case _OtpFlow.forgotPassword:
        final cErr = await _confirmForgotPassword(username, code, password);
        if (cErr != null) {
          return VerifyOtpFailure(cErr.message);
        }
        final authResult = await _initiateUserPasswordAuth(username, password);
        final session = authResult.session;
        if (session == null) {
          return VerifyOtpFailure(
            authResult.errorMessage ??
                'Password reset but sign-in failed. Enable password auth for this Cognito app client.',
          );
        }
        _session = session;
        clearPhoneVerificationState();
        return VerifyOtpSuccess(session);

      case _OtpFlow.none:
        return const VerifyOtpFailure('Request OTP first.');
    }
  }

  // --- Cognito IdP JSON API ---

  Uri get _endpoint =>
      Uri.parse('https://cognito-idp.${CognitoConfig.region}.amazonaws.com/');

  String? _secretHash(String username) {
    final secret = CognitoConfig.clientSecret;
    if (secret.isEmpty) return null;
    final key = utf8.encode(secret);
    final bytes = utf8.encode(username + CognitoConfig.clientId);
    final digest = Hmac(sha256, key).convert(bytes);
    return base64.encode(digest.bytes);
  }

  Future<_CognitoError?> _signUp(String username, String password) async {
    final body = <String, dynamic>{
      'ClientId': CognitoConfig.clientId,
      'Username': username,
      'Password': password,
      'UserAttributes': [
        {'Name': 'phone_number', 'Value': username},
      ],
    };
    final sh = _secretHash(username);
    if (sh != null) {
      body['SecretHash'] = sh;
    }

    return _invoke('AWSCognitoIdentityProviderService.SignUp', body);
  }

  Future<_CognitoError?> _forgotPassword(String username) async {
    final body = <String, dynamic>{
      'ClientId': CognitoConfig.clientId,
      'Username': username,
    };
    final sh = _secretHash(username);
    if (sh != null) {
      body['SecretHash'] = sh;
    }
    return _invoke('AWSCognitoIdentityProviderService.ForgotPassword', body);
  }

  Future<_CognitoError?> _confirmSignUp(String username, String code) async {
    final body = <String, dynamic>{
      'ClientId': CognitoConfig.clientId,
      'Username': username,
      'ConfirmationCode': code,
    };
    final sh = _secretHash(username);
    if (sh != null) {
      body['SecretHash'] = sh;
    }
    return _invoke('AWSCognitoIdentityProviderService.ConfirmSignUp', body);
  }

  Future<_CognitoError?> _confirmForgotPassword(
    String username,
    String code,
    String newPassword,
  ) async {
    final body = <String, dynamic>{
      'ClientId': CognitoConfig.clientId,
      'Username': username,
      'ConfirmationCode': code,
      'Password': newPassword,
    };
    final sh = _secretHash(username);
    if (sh != null) {
      body['SecretHash'] = sh;
    }
    return _invoke(
      'AWSCognitoIdentityProviderService.ConfirmForgotPassword',
      body,
    );
  }

  Future<_InitiateAuthResult> _initiateUserPasswordAuth(
    String username,
    String password,
  ) async {
    final body = <String, dynamic>{
      'AuthFlow': 'USER_PASSWORD_AUTH',
      'ClientId': CognitoConfig.clientId,
      'AuthParameters': {'USERNAME': username, 'PASSWORD': password},
    };
    final sh = _secretHash(username);
    if (sh != null) {
      (body['AuthParameters'] as Map<String, dynamic>)['SECRET_HASH'] = sh;
    }

    final client = http.Client();
    try {
      final res = await client.post(
        _endpoint,
        headers: {
          'Content-Type': 'application/x-amz-json-1.1',
          'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth',
        },
        body: jsonEncode(body),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        try {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          final type = '${map['__type'] ?? 'Unknown'}';
          final message = '${map['message'] ?? res.body}';
          debugPrint('InitiateAuth failed: $type $message');
          if (message.contains('USER_PASSWORD_AUTH flow not enabled')) {
            return const _InitiateAuthResult.failure(
              'Cognito app client is not configured for password sign-in. '
              'Enable `ALLOW_USER_PASSWORD_AUTH` in the app client auth flows.',
            );
          }
          return _InitiateAuthResult.failure(message);
        } catch (_) {
          debugPrint('InitiateAuth failed: ${res.body}');
          return _InitiateAuthResult.failure(res.body);
        }
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final auth = map['AuthenticationResult'] as Map<String, dynamic>?;
      if (auth == null) {
        return const _InitiateAuthResult.failure(
          'Cognito returned no authentication result.',
        );
      }
      return _InitiateAuthResult.success(
        CognitoSession(
          username: username,
          idToken: auth['IdToken'] as String,
          accessToken: auth['AccessToken'] as String,
          refreshToken: auth['RefreshToken'] as String,
          tokenType: auth['TokenType'] as String?,
          expiresIn: auth['ExpiresIn'] is int
              ? auth['ExpiresIn'] as int
              : int.tryParse('${auth['ExpiresIn']}'),
        ),
      );
    } catch (error) {
      return _InitiateAuthResult.failure(error.toString());
    } finally {
      client.close();
    }
  }

  Future<_CognitoError?> _invoke(
    String target,
    Map<String, dynamic> body,
  ) async {
    final client = http.Client();
    try {
      final res = await client.post(
        _endpoint,
        headers: {
          'Content-Type': 'application/x-amz-json-1.1',
          'X-Amz-Target': target,
        },
        body: jsonEncode(body),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return null;
      }

      try {
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        final type = map['__type'] as String? ?? 'Unknown';
        final message = map['message'] as String? ?? res.body;
        return _CognitoError(type, message);
      } catch (_) {
        return _CognitoError('HttpError', res.body);
      }
    } catch (e) {
      return _CognitoError('NetworkError', e.toString());
    } finally {
      client.close();
    }
  }
}

class _CognitoError {
  _CognitoError(this.type, this.message);

  final String type;
  final String message;

  bool get isUsernameExists =>
      type.contains('UsernameExistsException') ||
      message.contains('UsernameExistsException');

  bool get isUserNotConfirmed =>
      type.contains('UserNotConfirmedException') ||
      message.toLowerCase().contains('not confirmed');

  bool messageContains(String s) =>
      message.toLowerCase().contains(s.toLowerCase());
}

String? _decodeJwtSub(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    final payload = _base64UrlDecode(parts[1]);
    final map = jsonDecode(payload) as Map<String, dynamic>;
    return map['sub'] as String?;
  } catch (_) {
    return null;
  }
}

String _buildDevJwt(String username, String tokenUse, String sub) {
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode({'sub': sub, 'phone_number': username, 'token_use': tokenUse}),
    ),
  );
  return '$header.$payload.';
}

String _base64UrlDecode(String input) {
  var output = input.replaceAll('-', '+').replaceAll('_', '/');
  switch (output.length % 4) {
    case 0:
      break;
    case 2:
      output += '==';
      break;
    case 3:
      output += '=';
      break;
    default:
      return '';
  }
  return utf8.decode(base64.decode(output));
}
