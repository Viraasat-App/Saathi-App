/// Build with `--dart-define` values to override these defaults, e.g.:
/// `flutter run --dart-define=COGNITO_REGION=ap-south-1 --dart-define=COGNITO_CLIENT_ID=xxxxxxxx`
///
/// Use an **app client without a client secret** when possible (typical for mobile).
/// If your pool requires a client secret, set [clientSecret] (server-side flows are
/// usually better than embedding secrets in a public app).
abstract final class CognitoConfig {
  static const String region = String.fromEnvironment(
    'COGNITO_REGION',
    defaultValue: 'ap-south-1',
  );

  /// Stored for future Lambda/admin flows. The current client auth flow does not require it.
  static const String userPoolId = String.fromEnvironment(
    'COGNITO_USER_POOL_ID',
    defaultValue: 'ap-south-1_1KZt26JgF',
  );

  static const String clientId = String.fromEnvironment(
    'COGNITO_CLIENT_ID',
    defaultValue: '1ttngt8nd1srqtitc2ri2r02no',
  );

  /// Optional; leave empty for public app clients.
  static const String clientSecret = String.fromEnvironment(
    'COGNITO_CLIENT_SECRET',
    defaultValue: '',
  );

  /// Legacy dart-define; not used for validation when [AuthService] development OTP
  /// mode is on (any 6-digit code becomes the dev user id). Kept for tooling/docs.
  static const String devOtp = String.fromEnvironment(
    'DEV_OTP_CODE',
    defaultValue: '123456',
  );
}
