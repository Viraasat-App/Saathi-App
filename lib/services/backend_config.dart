abstract final class BackendConfig {
  static const String profileSyncEndpoint = String.fromEnvironment(
    'PROFILE_SYNC_ENDPOINT',
    defaultValue:
        'https://e9pp3r6qu6.execute-api.ap-south-1.amazonaws.com/create-memory',
  );

  static const String streamingTranscribeEndpoint = String.fromEnvironment(
    'STREAMING_TRANSCRIBE_ENDPOINT',
    defaultValue:
        'https://i7foxopo01.execute-api.ap-south-1.amazonaws.com/prod/streaming_service',
  );

  static const String streamingProxyWsEndpoint = String.fromEnvironment(
    'STREAMING_PROXY_WS_ENDPOINT',
    defaultValue: 'ws://13.126.129.118/speech-proxy/ws',
  );
}
