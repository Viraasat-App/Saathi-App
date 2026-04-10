abstract final class BackendConfig {
  static const String profileSyncEndpoint = String.fromEnvironment(
    'PROFILE_SYNC_ENDPOINT',
    defaultValue:
        'https://e9pp3r6qu6.execute-api.ap-south-1.amazonaws.com/create-memory',
  );
}
