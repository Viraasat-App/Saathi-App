import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum SarvamSpeechEvent { startSpeech, endSpeech }

class SarvamStreamingService {
  SarvamStreamingService({
    required this.websocketProxyUrl,
    this.sampleRate = 16000,
    this.languageCode = 'hi-IN',
    this.model = 'saaras:v3',
    this.mode = 'translit',
  });

  final String websocketProxyUrl;
  final int sampleRate;
  final String languageCode;
  final String model;
  final String mode;

  WebSocketChannel? _socket;
  Uri? _activeUri;
  bool _manualCloseRequested = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 2;
  static const Duration _reconnectDelay = Duration(milliseconds: 700);
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();
  final StreamController<String> _finalController =
      StreamController<String>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<SarvamSpeechEvent> _speechEventController =
      StreamController<SarvamSpeechEvent>.broadcast();
  Completer<String>? _finalTranscriptCompleter;

  Stream<String> get partialTranscripts => _partialController.stream;
  Stream<String> get finalTranscripts => _finalController.stream;
  Stream<String> get errors => _errorController.stream;
  Stream<SarvamSpeechEvent> get speechEvents => _speechEventController.stream;

  bool get isConnected => _socket != null;

  Future<void> connect() async {
    _manualCloseRequested = false;
    _reconnectAttempts = 0;
    final proxyUrl = websocketProxyUrl.trim();
    if (proxyUrl.isEmpty) {
      throw Exception('Missing STREAMING_PROXY_WS_ENDPOINT');
    }
    if (_socket != null) return;

    final queryParameters = <String, String>{
      'model': model,
      'mode': mode,
      'language-code': languageCode,
      'sample_rate': sampleRate.toString(),
      'input_audio_codec': 'pcm_s16le',
      'vad_signals': 'true',
      'flush_signal': 'true',     
    };
    final baseUri = Uri.parse(proxyUrl);
    final uri = baseUri.replace(
      queryParameters: {...baseUri.queryParameters, ...queryParameters},
    );
    _activeUri = uri;

    _attachSocket(
      kIsWeb ? WebSocketChannel.connect(uri) : IOWebSocketChannel.connect(uri),
      source: 'connect',
    );
  }

  void sendAudioChunk(Uint8List pcmChunk) {
    final socket = _socket;
    if (socket == null) return;
    socket.sink.add(
      jsonEncode({
        'audio': {
          'data': base64Encode(pcmChunk),
          'sample_rate': sampleRate.toString(),
          'encoding': 'audio/wav',
        },
      }),
    );
  }

  Future<String> finishAndGetFinalTranscript({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_socket == null) {
      throw Exception('WebSocket is not connected');
    }
    _finalTranscriptCompleter = Completer<String>();
    final completer = _finalTranscriptCompleter!;
    _sendJson({'type': 'flush'});
    final transcript = await completer.future.timeout(timeout);
    return transcript.trim();
  }

  Future<void> requestFlush() async {
    _sendJson({'type': 'flush'});
  }

  Future<void> close() async {
    _manualCloseRequested = true;
    await _socket?.sink.close();
    _socket = null;
    _activeUri = null;
    _reconnectAttempts = 0;
  }

  void dispose() {
    _partialController.close();
    _finalController.close();
    _errorController.close();
    _speechEventController.close();
  }

  void _sendJson(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null) return;
    socket.sink.add(jsonEncode(payload));
  }

  void _handleIncomingMessage(dynamic raw) {
    // Consider connection healthy once any frame arrives.
    _reconnectAttempts = 0;
    Map<String, dynamic>? obj;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          obj = decoded;
        }
      } catch (_) {}
    }
    if (obj == null) return;
    if (kDebugMode) {
      debugPrint('[streaming] <- $obj');
    }

    final payload = _readMap(obj, const ['data']) ?? obj;
    final msgType = _readString(obj, const ['type'])?.toLowerCase();
    if (msgType == 'error') {
      final err = _readString(payload, const ['error', 'message']) ??
          _readString(obj, const ['error', 'message']) ??
          'Unknown streaming error';
      _errorController.add(err);
      return;
    }

    final partial = _readString(payload, const [
      'partial_transcript',
      'partial',
      'text_partial',
    ]);
    if (partial != null && partial.isNotEmpty) {
      _partialController.add(partial);
    }

    final finalText = _readString(payload, const [
      'transcript',
      'final_transcript',
      'text',
    ]);
    final signalType =
        _readString(payload, const ['signal_type', 'event_type'])?.toUpperCase();
    if (signalType == 'START_SPEECH') {
      _speechEventController.add(SarvamSpeechEvent.startSpeech);
    } else if (signalType == 'END_SPEECH') {
      _speechEventController.add(SarvamSpeechEvent.endSpeech);
    }

    final isFinal = _readBool(payload, const ['is_final', 'final']) ||
        signalType == 'END_SPEECH' ||
        msgType == 'data';

    if (isFinal && finalText != null && finalText.trim().isNotEmpty) {
      _finalController.add(finalText.trim());
      final completer = _finalTranscriptCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(finalText.trim());
      }
    }
  }

  Map<String, dynamic>? _readMap(Map<String, dynamic> obj, List<String> keys) {
    for (final key in keys) {
      final value = obj[key];
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    return null;
  }

  String? _readString(Map<String, dynamic> obj, List<String> keys) {
    for (final key in keys) {
      final value = obj[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  bool _readBool(Map<String, dynamic> obj, List<String> keys) {
    for (final key in keys) {
      final value = obj[key];
      if (value is bool) return value;
      if (value is String) {
        final v = value.toLowerCase().trim();
        if (v == 'true') return true;
      }
      if (value is num && value != 0) return true;
    }
    return false;
  }

  void _attachSocket(WebSocketChannel socket, {required String source}) {
    _socket = socket;
    if (kDebugMode) {
      debugPrint('[streaming] websocket connected ($source)');
    }
    socket.stream.listen(
      _handleIncomingMessage,
      onDone: () {
        final closeDetails = _socketCloseDetails(socket);
        _socket = null;
        if (kDebugMode) {
          debugPrint('[streaming] websocket closed by server$closeDetails');
        }
        if (_manualCloseRequested) return;
        _errorController.add('Streaming socket closed by server$closeDetails');
        unawaited(_attemptReconnect());
      },
      onError: (Object error) {
        _socket = null;
        if (kDebugMode) {
          debugPrint('[streaming] websocket error: $error');
        }
        if (_manualCloseRequested) return;
        _errorController.add('Streaming socket error: $error');
        unawaited(_attemptReconnect());
      },
      cancelOnError: true,
    );
  }

  String _socketCloseDetails(WebSocketChannel socket) {
    if (socket is IOWebSocketChannel) {
      final code = socket.closeCode;
      final reason = socket.closeReason;
      if (code != null || (reason != null && reason.isNotEmpty)) {
        return ' (code: ${code ?? 'unknown'}, reason: ${reason ?? 'none'})';
      }
    }
    return '';
  }

  Future<void> _attemptReconnect() async {
    if (_manualCloseRequested || _socket != null) return;
    final uri = _activeUri;
    if (uri == null) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (kDebugMode) {
        debugPrint('[streaming] reconnect skipped: max attempts reached');
      }
      return;
    }
    _reconnectAttempts += 1;
    if (kDebugMode) {
      debugPrint('[streaming] reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts');
    }
    await Future.delayed(_reconnectDelay);
    if (_manualCloseRequested || _socket != null) return;
    try {
      _attachSocket(
        kIsWeb ? WebSocketChannel.connect(uri) : IOWebSocketChannel.connect(uri),
        source: 'reconnect',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[streaming] reconnect failed: $e');
      }
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        _errorController.add('Streaming reconnect failed after retries');
      } else {
        unawaited(_attemptReconnect());
      }
    }
  }
}
