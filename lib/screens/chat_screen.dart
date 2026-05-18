import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../models/chat_message.dart';
import '../services/app_settings.dart';
import '../services/auth_storage.dart';
import '../services/backend_config.dart';
import '../services/chat_history_storage.dart';
import '../services/chat_session_snapshot.dart';
import '../services/profile_storage.dart';
import '../services/sarvam_streaming_service.dart';
import '../theme/saathi_beige_theme.dart';
import '../voice/voice_ui_phase.dart';
import '../widgets/floating_voice_nav_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/premium_voice_header.dart';
import '../widgets/premium_voice_mic.dart';
import 'family_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

/// Shown in chat when presigned URL / setup step fails before storage.
class _UploadFlowException implements Exception {
  const _UploadFlowException(this.userMessage);
  final String userMessage;
}

/// Shown when audio reached storage but transcript/NBQ pipeline could not complete.
class _TranscriptFlowException implements Exception {
  const _TranscriptFlowException(this.userMessage);
  final String userMessage;
}

/// One NBQ row: poll S3 audio unless user taps Say now (TTS only then).
class _NbqVoiceSession {
  _NbqVoiceSession({
    required this.turnId,
    required this.generation,
    required this.nbqText,
    required this.uploadedFileName,
  });

  final String turnId;
  final int generation;
  final String nbqText;
  final String uploadedFileName;
  bool userChoseTts = false;
  bool cancelled = false;
  bool finished = false;
}

class _TranscriptNbqResult {
  const _TranscriptNbqResult({
    required this.transcript,
    this.nextBestQuestion,
    this.nbqAudioUrl,
  });

  final String transcript;
  final String? nextBestQuestion;

  /// Pre-generated NBQ audio from GET API (`nbq_audio_url`), when present.
  final String? nbqAudioUrl;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _bottomBarKey = GlobalKey();
  double _bottomBarHeight = 0;

  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isBotAudioPlaying = false;
  int _selectedBottomTab = 0;
  String? _audioId;
  double _micInputLevel = 0;
  final AudioRecorder _bargeInRecorder = AudioRecorder();
  StreamSubscription<Amplitude>? _bargeAmpSub;
  String? _bargeInPath;
  String? _playingNbqTurnId;

  String? _userId;
  String? _userName;
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Amplitude>? _micAmpSub;
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _nbqAudioPlayer = AudioPlayer();
  final AudioPlayer _userAudioPlayer = AudioPlayer();
  final AudioPlayer _botAudioPlayer = AudioPlayer();
  String? _activeUserAudioPath;
  bool _isUserAudioPaused = false;
  StreamSubscription<PlayerState>? _userPlayerStateSub;
  String? _activeBotAudioPath;
  bool _isBotAudioPaused = false;
  StreamSubscription<PlayerState>? _botPlayerStateSub;
  StreamSubscription<PlayerState>? _nbqPlayerStateSub;
  static const String _uploadAudioEndpoint =
      'https://i8g5rlsv55.execute-api.ap-south-1.amazonaws.com/upload-audio';
  static const String _transcriptEndpoint =
      'https://v3y43z8hj3.execute-api.ap-south-1.amazonaws.com/get-transcript';
  static const String _streamingTranscribeEndpoint =
      BackendConfig.streamingTranscribeEndpoint;
  static const String _streamingProxyWsEndpoint =
      BackendConfig.streamingProxyWsEndpoint;

  static const Duration _uploadPostTimeout = Duration(seconds: 45);
  static const Duration _uploadPutTimeout = Duration(minutes: 3);
  static const Duration _transcriptGetTimeout = Duration(seconds: 30);
  static const Duration _streamingPostTimeout = Duration(seconds: 45);

  /// Poll for presigned NBQ audio: 2s × 10 = 20s max wait before giving up.
  static const int _maxNbqAudioUrlPolls = 10;
  static const Duration _nbqAudioPollInterval = Duration(seconds: 2);

  // Progress labels (user bubble, isThinking)
  static const String _stageRequestingUploadLink = 'Requesting upload link...';
  static const String _stageSendingAudio = 'Uploading audio...';
  static const String _stageProcessingRecording = 'Processing recording...';
  static const String _stageGettingTranscript = 'Getting transcript...';
  static const String _stageLoadingFollowUp = 'Loading follow-up question...';

  // Upload-stage errors (audio never fully stored)
  static const String _errUploadFileMissing =
      'Audio upload error: recording file was not found. Please record again.';
  static const String _errUploadLinkFailed =
      'Audio upload error: could not get an upload link. Check your connection and try again.';
  static const String _errUploadLinkBadResponse =
      'Audio upload error: server could not prepare the upload. Please try again.';
  static const String _errUploadSendFailed =
      'Audio upload error: could not send your recording to storage. Check your connection and try again.';
  static const String _errUploadInvalidResponse =
      'Audio upload error: invalid server response. Please try again.';

  // Transcript-stage errors (upload succeeded)
  static const String _errTranscriptFailed =
      'Error generating transcript: your audio was uploaded, but we could not get the text back. Please try recording again.';

  static const String _errFollowUpTimeout =
      'Follow-up question error: the next question took too long to load. You can record again to continue.';
  static const String _errStreamingFailed =
      'Streaming transcription failed. Please check your connection and try again.';

  static const String _errUnexpected =
      'Something went wrong. Please try again.';

  static const String _stageStreamingTranscription = 'Transcribing recording...';

  /// Bumps each new recording turn so stale NBQ polls stop.
  int _nbqPlaybackGeneration = 0;

  final Map<String, _NbqVoiceSession> _nbqVoiceSessions = {};
  int _nbqTurnSeq = 0;
  final SarvamStreamingService _sarvamStreaming = SarvamStreamingService(
    websocketProxyUrl: _streamingProxyWsEndpoint,
  );
  StreamSubscription<String>? _livePartialSub;
  StreamSubscription<String>? _liveFinalSub;
  StreamSubscription<String>? _liveErrorSub;
  StreamSubscription<SarvamSpeechEvent>? _liveSpeechEventSub;
  StreamSubscription<Uint8List>? _liveAudioSub;
  final BytesBuilder _livePcmBuffer = BytesBuilder(copy: false);
  final BytesBuilder _activeUtterancePcmBuffer = BytesBuilder(copy: false);
  /// Rolling tail of mic PCM so saved playback includes audio before server VAD
  /// (`START_SPEECH`). Matches [_liveStreamRecordConfig] 16 kHz mono s16le.
  static const int _streamPreRollMaxBytes = (16000 * 2 * 12) ~/ 10; // ~1.2s
  final List<Uint8List> _streamPreRollChunks = [];
  int _streamPreRollTotalBytes = 0;
  Uint8List? _readyUtterancePcm;
  String _latestPartialTranscript = '';
  bool _serverSpeechActive = false;
  int? _liveTranscriptMessageIndex;
  final List<({String transcript, Uint8List pcmBytes, int? messageIndex})>
      _pendingStreamingTurns = [];
  bool _turnProcessingInFlight = false;
  bool _stopInProgress = false;
  bool _autoListenArmedByCompletedBotAudio = false;
  Timer? _silenceAutoStopTimer;
  static const Duration _silenceAutoStopDelay = Duration(milliseconds: 1500);
  final StringBuffer _debouncedTranscriptBuffer = StringBuffer();
  final BytesBuilder _debouncedPcmBuffer = BytesBuilder(copy: false);
  int? _debouncedMessageIndex;

  final RecordConfig _recordConfig = const RecordConfig(
    encoder: AudioEncoder.wav,
    numChannels: 1,
  );
  final RecordConfig _liveStreamRecordConfig = const RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
  );

  static const List<double> _volumeSteps = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];
  static const Duration _micAmplitudePollInterval = Duration(milliseconds: 200);

  double _snapVolume(double v) {
    final clamped = v.clamp(0.0, 1.0);
    double best = _volumeSteps.first;
    var bestDist = (best - clamped).abs();
    for (final step in _volumeSteps) {
      final dist = (step - clamped).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = step;
      }
    }
    return best;
  }

  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint(
        '[streaming] endpoint=$_streamingTranscribeEndpoint '
        'proxyWs=$_streamingProxyWsEndpoint',
      );
    }
    _loadUserId();
    final previousSession = ChatSessionSnapshot.current;
    if (previousSession != null && previousSession.isNotEmpty) {
      _messages.addAll(previousSession);
    }

    _userPlayerStateSub = _userAudioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _activeUserAudioPath = null;
          _isUserAudioPaused = false;
        });
      }
    });
    _botPlayerStateSub = _botAudioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _activeBotAudioPath = null;
          _isBotAudioPaused = false;
          _isBotAudioPlaying = false;
        });
        unawaited(_ensureMicOffAfterBotPlayback());
      }
    });
    _nbqPlayerStateSub = _nbqAudioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (_playingNbqTurnId == null) return;
      if (state.processingState != ProcessingState.completed) return;
      setState(() {
        _isBotAudioPlaying = false;
        _playingNbqTurnId = null;
      });
      unawaited(_ensureMicOffAfterBotPlayback());
    });
    // Best-effort: sync slider with actual system media volume.
    _syncSystemVolume();
    unawaited(_configureTts());
  }

  Future<void> _playUserAudio(ChatMessage message) async {
    final path = message.localUserAudioPath;
    if (path == null || path.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No local recording for this message')),
      );
      return;
    }
    final f = File(path);
    if (!await f.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This recording is no longer available')),
      );
      return;
    }
    try {
      if (!mounted) return;
      setState(() {
        _activeUserAudioPath = path;
        _isUserAudioPaused = false;
      });
      await _nbqAudioPlayer.stop();
      await _userAudioPlayer.stop();
      await _botAudioPlayer.stop();
      if (mounted) {
        setState(() {
          _playingNbqTurnId = null;
          _isBotAudioPlaying = false;
          _activeBotAudioPath = null;
          _isBotAudioPaused = false;
        });
      }
      await _userAudioPlayer.setFilePath(path);
      unawaited(_userAudioPlayer.play());
    } catch (_) {
      if (mounted) {
        setState(() {
          _activeUserAudioPath = null;
          _isUserAudioPaused = false;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play this recording')),
      );
    }
  }

  Future<void> _playBotAudio(ChatMessage message) async {
    await _ensureMicOffAfterBotPlayback();
    var path = message.localBotAudioPath;
    if (path == null || path.isEmpty) {
      if (message.text.trim().isEmpty) return;
      final synthesized = await _synthesizeBotSpeechToFile(message.text);
      if (synthesized != null) {
        path = synthesized;
        _attachLocalBotAudioPath(message, path);
        unawaited(_saveChatHistory());
      }
    }
    if (path == null || path.isEmpty) {
      if (message.text.trim().isEmpty) return;
      if (mounted) {
        setState(() {
          _isBotAudioPlaying = true;
        });
      }
      try {
        await _nbqAudioPlayer.stop();
        await _userAudioPlayer.stop();
        await _botAudioPlayer.stop();
        await _tts.stop();
        await _tts.speak(message.text);
      } catch (_) {
      } finally {
        if (mounted) {
          setState(() {
            _isBotAudioPlaying = false;
          });
        }
        unawaited(_ensureMicOffAfterBotPlayback());
      }
      return;
    }
    final f = File(path);
    if (!await f.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This response audio is no longer available')),
      );
      return;
    }
    try {
      if (!mounted) return;
      setState(() {
        _activeBotAudioPath = path;
        _isBotAudioPaused = false;
        _isBotAudioPlaying = true;
      });
      await _nbqAudioPlayer.stop();
      await _userAudioPlayer.stop();
      await _botAudioPlayer.stop();
      await _tts.stop();
      await _botAudioPlayer.setFilePath(path);
      unawaited(_botAudioPlayer.play());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activeBotAudioPath = null;
        _isBotAudioPaused = false;
        _isBotAudioPlaying = false;
      });
    }
  }

  Future<void> _pauseOrResumeBotAudio() async {
    if (_activeBotAudioPath == null) return;
    try {
      if (_isBotAudioPaused) {
        unawaited(_botAudioPlayer.play());
        if (!mounted) return;
        setState(() => _isBotAudioPaused = false);
      } else {
        await _botAudioPlayer.pause();
        if (!mounted) return;
        setState(() => _isBotAudioPaused = true);
      }
    } catch (_) {}
  }

  Future<void> _stopBotAudio() async {
    try {
      await _botAudioPlayer.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _activeBotAudioPath = null;
      _isBotAudioPaused = false;
      _isBotAudioPlaying = false;
    });
    unawaited(_ensureMicOffAfterBotPlayback());
  }

  Future<void> _pauseOrResumeUserAudio() async {
    if (_activeUserAudioPath == null) return;
    try {
      if (_isUserAudioPaused) {
        unawaited(_userAudioPlayer.play());
        if (!mounted) return;
        setState(() => _isUserAudioPaused = false);
      } else {
        await _userAudioPlayer.pause();
        if (!mounted) return;
        setState(() => _isUserAudioPaused = true);
      }
    } catch (_) {}
  }

  Future<void> _stopUserAudio() async {
    try {
      await _userAudioPlayer.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _activeUserAudioPath = null;
      _isUserAudioPaused = false;
    });
  }

  ChatMessage _newMessage({
    required String text,
    required bool isUser,
    required bool isThinking,
    String? localUserAudioPath,
    String? localBotAudioPath,
    bool nbqAwaitingVoice = false,
    String? nbqTurnId,
    int? nbqVoiceGeneration,
  }) {
    return ChatMessage(
      text: text,
      isUser: isUser,
      isThinking: isThinking,
      timestamp: DateTime.now(),
      localUserAudioPath: localUserAudioPath,
      localBotAudioPath: localBotAudioPath,
      nbqAwaitingVoice: nbqAwaitingVoice,
      nbqTurnId: nbqTurnId,
      nbqVoiceGeneration: nbqVoiceGeneration,
    );
  }

  Future<String?> _copyUserAudioToLocalHistory(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return null;
      final dir = await getApplicationDocumentsDirectory();
      final historyDir = Directory('${dir.path}/chat-audio-history');
      if (!await historyDir.exists()) {
        await historyDir.create(recursive: true);
      }
      final safeUserId = (_userId == null || _userId!.isEmpty)
          ? 'anonymous'
          : _userId!.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final destPath = '${historyDir.path}/${safeUserId}_$stamp.wav';
      await source.copy(destPath);
      return destPath;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveChatHistory() async {
    final existing = await ChatHistoryStorage.instance.loadMessages();
    final currentSession = _messages
        .where((m) => !m.isThinking && m.text.trim().isNotEmpty)
        .toList();
    final merged = [...existing, ...currentSession];
    final byKey = <String, ChatMessage>{};
    for (final message in merged) {
      final key = ChatHistoryStorage.messageDedupeKey(message);
      final prev = byKey[key];
      byKey[key] = prev == null
          ? message
          : ChatHistoryStorage.mergeDuplicateMessages(prev, message);
    }
    await ChatHistoryStorage.instance.saveMessages(byKey.values.toList());
  }

  Future<void> _syncSystemVolume() async {
    try {
      final current = await FlutterVolumeController.getVolume();
      final snapped = _snapVolume(current ?? AppSettings.instance.ttsVolume);
      await AppSettings.instance.setTtsVolume(snapped);
    } catch (_) {
      // If system volume can't be read on this device/platform, keep stored value.
    }
  }

  Future<void> _loadUserId() async {
    final userId = await AuthStorage.instance.currentUserId();
    final profile = await ProfileStorage.instance.loadUserProfile();
    if (!mounted) return;
    setState(() {
      _userId = userId;
      final n = profile?.name.trim();
      _userName = (n == null || n.isEmpty) ? null : n;
    });
  }

  @override
  void dispose() {
    ChatSessionSnapshot.replace(_messages);
    _userPlayerStateSub?.cancel();
    _botPlayerStateSub?.cancel();
    _nbqPlayerStateSub?.cancel();
    unawaited(_userAudioPlayer.dispose());
    unawaited(_botAudioPlayer.dispose());
    _stopMicLevelMonitoring();
    _livePartialSub?.cancel();
    _liveFinalSub?.cancel();
    _liveSpeechEventSub?.cancel();
    _liveAudioSub?.cancel();
    unawaited(_sarvamStreaming.close());
    _sarvamStreaming.dispose();
    _bargeAmpSub?.cancel();
    unawaited(_bargeInRecorder.dispose());
    unawaited(_tts.stop());
    unawaited(_nbqAudioPlayer.dispose());
    _scrollController.dispose();
    super.dispose();
  }

  void _syncBottomBarHeight() {
    final ctx = _bottomBarKey.currentContext;
    if (ctx == null) return;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox) return;
    final h = ro.size.height;
    if ((h - _bottomBarHeight).abs() < 0.5) return;
    setState(() => _bottomBarHeight = h);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncBottomBarHeight());
  }

  Future<void> _configureTts() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setVolume(AppSettings.instance.ttsVolume);
      await _tts.clearVoice();
    } catch (e) {
      debugPrint('TTS configure: $e');
    }
  }

  String? _nonEmptyTrimmedUrl(String? raw) {
    final t = raw?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  String _nextNbqTurnId() {
    _nbqTurnSeq += 1;
    return 'nbq_$_nbqTurnSeq';
  }

  void _stripStaleNbqVoiceChromeInPlace(int currentGen) {
    final removeKeys = _nbqVoiceSessions.entries
        .where((e) => e.value.generation < currentGen)
        .map((e) => e.key)
        .toList();
    for (final k in removeKeys) {
      _nbqVoiceSessions.remove(k);
    }
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.nbqAwaitingVoice &&
          m.nbqVoiceGeneration != null &&
          m.nbqVoiceGeneration! < currentGen) {
        _messages[i] = ChatMessage(
          text: m.text,
          isUser: false,
          isThinking: false,
          timestamp: m.timestamp,
          localBotAudioPath: m.localBotAudioPath,
        );
      }
    }
  }

  int? _messageIndexForNbqTurnId(String turnId) {
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].nbqTurnId == turnId) return i;
    }
    return null;
  }

  void _clearNbqAwaitingForTurnId(String turnId) {
    if (!mounted) return;
    final idx = _messageIndexForNbqTurnId(turnId);
    if (idx == null) return;
    setState(() {
      final m = _messages[idx];
      if (m.nbqTurnId != turnId) return;
      _messages[idx] = ChatMessage(
        text: m.text,
        isUser: false,
        isThinking: false,
        timestamp: m.timestamp,
        localBotAudioPath: m.localBotAudioPath,
      );
    });
  }

  Future<String?> _cacheBotAudioFromUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http
          .get(uri, headers: {'Accept': 'audio/*'})
          .timeout(const Duration(seconds: 45));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (response.bodyBytes.isEmpty) return null;
      final docs = await getApplicationDocumentsDirectory();
      final historyDir = Directory('${docs.path}/chat-audio-history');
      if (!await historyDir.exists()) {
        await historyDir.create(recursive: true);
      }
      var ext = '.mp3';
      final p = uri.path.toLowerCase();
      if (p.endsWith('.wav')) ext = '.wav';
      if (p.endsWith('.aac')) ext = '.aac';
      if (p.endsWith('.m4a')) ext = '.m4a';
      final out =
          File('${historyDir.path}/bot_${DateTime.now().microsecondsSinceEpoch}$ext');
      await out.writeAsBytes(response.bodyBytes, flush: true);
      return out.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _synthesizeBotSpeechToFile(String text) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    if (kIsWeb) return null;
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final historyDir = Directory('${docs.path}/chat-audio-history');
      if (!await historyDir.exists()) {
        await historyDir.create(recursive: true);
      }
      final out =
          '${historyDir.path}/bot_tts_${DateTime.now().microsecondsSinceEpoch}.wav';
      await _tts.awaitSynthCompletion(true);
      await _tts.synthesizeToFile(t, out, true);
      final f = File(out);
      if (await f.exists() && await f.length() > 0) return out;
    } catch (e) {
      debugPrint('TTS synthesizeToFile: $e');
    }
    return null;
  }

  void _attachLocalBotAudioPath(ChatMessage ref, String path) {
    if (!mounted) return;
    final refKey = ChatHistoryStorage.messageDedupeKey(ref);
    setState(() {
      for (var i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        if (m.isUser || m.isThinking) continue;
        if (ChatHistoryStorage.messageDedupeKey(m) != refKey) continue;
        _messages[i] = ChatMessage(
          text: m.text,
          isUser: m.isUser,
          isThinking: m.isThinking,
          timestamp: m.timestamp,
          localUserAudioPath: m.localUserAudioPath,
          localBotAudioPath: path,
          nbqAwaitingVoice: m.nbqAwaitingVoice,
          nbqTurnId: m.nbqTurnId,
          nbqVoiceGeneration: m.nbqVoiceGeneration,
        );
        return;
      }
    });
  }

  double _normalizeMicLevel(double db) {
    const floor = -55.0;
    const ceil = -12.0;
    final t = (db - floor) / (ceil - floor);
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return t;
  }

  void _stopMicLevelMonitoring() {
    _micAmpSub?.cancel();
    _micAmpSub = null;
  }

  void _startMicLevelMonitoring() {
    _stopMicLevelMonitoring();
    _micAmpSub = _audioRecorder
        .onAmplitudeChanged(_micAmplitudePollInterval)
        .listen((Amplitude amp) {
      if (!mounted || !_isRecording) return;
      setState(() => _micInputLevel = _normalizeMicLevel(amp.current));
    });
  }

  Future<void> _ensureMicOffAfterBotPlayback() async {
    _stopMicLevelMonitoring();
    if (!_isRecording) return;
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _micInputLevel = 0;
    });
  }

  /// [playerStateStream.firstWhere((s) => !s.playing)] can hang on some devices; this
  /// waits for [ProcessingState.completed] or a clean idle after playback started.
  Future<void> _awaitNbqPlaybackFinished() async {
    final done = Completer<void>();
    StreamSubscription<PlayerState>? sub;
    var heardPlaying = false;

    void finish() {
      if (done.isCompleted) return;
      done.complete();
      sub?.cancel();
      sub = null;
    }

    sub = _nbqAudioPlayer.playerStateStream.listen((s) {
      if (s.playing) heardPlaying = true;
      if (s.processingState == ProcessingState.completed) {
        finish();
        return;
      }
      if (heardPlaying &&
          !s.playing &&
          (s.processingState == ProcessingState.idle ||
              s.processingState == ProcessingState.ready)) {
        finish();
      }
    });

    try {
      await done.future.timeout(const Duration(minutes: 30));
    } on TimeoutException {
      sub?.cancel();
    } finally {
      sub?.cancel();
    }
  }

  void _attachBotAudioPathToTurn(String turnId, String localPath) {
    final idx = _messageIndexForNbqTurnId(turnId);
    if (idx == null || !mounted) return;
    setState(() {
      final m = _messages[idx];
      _messages[idx] = ChatMessage(
        text: m.text,
        isUser: m.isUser,
        isThinking: m.isThinking,
        timestamp: m.timestamp,
        localUserAudioPath: m.localUserAudioPath,
        localBotAudioPath: localPath,
        nbqAwaitingVoice: m.nbqAwaitingVoice,
        nbqTurnId: m.nbqTurnId,
        nbqVoiceGeneration: m.nbqVoiceGeneration,
      );
    });
    unawaited(_saveChatHistory());
  }

  Future<bool> _playNbqAudioUri({
    required String url,
    required String turnId,
    required int generation,
    required _NbqVoiceSession session,
  }) async {
    if (!mounted) {
      return false;
    }

    bool abandoned() =>
        !mounted ||
        generation != _nbqPlaybackGeneration ||
        session.userChoseTts ||
        session.cancelled ||
        session.finished;

    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return false;
    }

    var finishedClean = false;
    String? cachedBotPath;
    try {
      if (_isRecording) {
        _stopMicLevelMonitoring();
        try {
          await _audioRecorder.stop();
        } catch (_) {}
        if (mounted) {
          setState(() {
            _isRecording = false;
            _micInputLevel = 0;
          });
        }
      }
      await _tts.stop();
      await _nbqAudioPlayer.stop();
      if (abandoned()) {
        return false;
      }
      cachedBotPath = await _cacheBotAudioFromUrl(url);
      cachedBotPath ??= await _cacheBotAudioFromUrl(url);
      if (cachedBotPath != null) {
        _attachBotAudioPathToTurn(turnId, cachedBotPath);
        try {
          await _nbqAudioPlayer.setFilePath(cachedBotPath);
        } catch (e) {
          debugPrint('NBQ play from file failed, using URL: $e');
          await _nbqAudioPlayer.setAudioSource(AudioSource.uri(uri));
        }
      } else {
        await _nbqAudioPlayer.setAudioSource(AudioSource.uri(uri));
      }
      if (abandoned()) {
        return false;
      }
      if (mounted) {
        setState(() {
          _isBotAudioPlaying = true;
          _playingNbqTurnId = turnId;
        });
      }
      HapticFeedback.lightImpact();
      unawaited(_startBargeInMonitor());
      await _nbqAudioPlayer.play();
      await _awaitNbqPlaybackFinished();
      if (cachedBotPath == null && !abandoned()) {
        final latePath = await _cacheBotAudioFromUrl(url);
        if (latePath != null) {
          _attachBotAudioPathToTurn(turnId, latePath);
        }
      }
      finishedClean = !abandoned();
    } catch (e) {
      debugPrint('NBQ audio URL play failed: $e');
      finishedClean = false;
    } finally {
      if (mounted) {
        setState(() {
          _isBotAudioPlaying = false;
          _playingNbqTurnId = null;
        });
      }
      unawaited(_ensureMicOffAfterBotPlayback());
    }

    if (finishedClean && mounted && !abandoned()) {
      session.finished = true;
      _nbqVoiceSessions.remove(turnId);
      _clearNbqAwaitingForTurnId(turnId);
      _autoListenArmedByCompletedBotAudio = true;
      unawaited(_startAutoVoiceTurn());
      return true;
    }
    return false;
  }

  /// Poll GET for `nbq_audio_url` up to 20s; play to completion, then
  /// [_startAutoVoiceTurn] runs. If no URL in time, still clears NBQ chrome and opens mic.
  Future<void> _resolveAndPlayNbqVoice({
    required String uploadedFileName,
    required String nbqText,
    required String turnId,
    String? initialAudioUrl,
    required int generation,
  }) async {
    final nbq = nbqText.trim();
    if (nbq.isEmpty || !mounted) return;
    final session = _nbqVoiceSessions[turnId];
    if (session == null) return;

    var latestUrl = _nonEmptyTrimmedUrl(initialAudioUrl);

    bool abandoned() =>
        !mounted ||
        generation != _nbqPlaybackGeneration ||
        session.userChoseTts ||
        session.cancelled ||
        session.finished;

    Future<bool> attemptUrlPlayback(String url) async {
      if (abandoned()) {
        return false;
      }
      return _playNbqAudioUri(
        url: url,
        turnId: turnId,
        generation: generation,
        session: session,
      );
    }

    if (latestUrl != null) {
      await attemptUrlPlayback(latestUrl);
      if (session.finished) return;
    }

    for (var attempt = 0; attempt < _maxNbqAudioUrlPolls; attempt++) {
      if (abandoned()) break;
      await Future.delayed(_nbqAudioPollInterval);
      if (abandoned()) break;
      final payload = await _fetchTranscriptPayload(uploadedFileName);
      final u = _nonEmptyTrimmedUrl(payload?.nbqAudioUrl);
      if (u != null) {
        latestUrl = u;
        await attemptUrlPlayback(u);
        if (session.finished) break;
      }
    }
    if (mounted &&
        !abandoned() &&
        !session.finished &&
        generation == _nbqPlaybackGeneration) {
      session.finished = true;
      _nbqVoiceSessions.remove(turnId);
      _clearNbqAwaitingForTurnId(turnId);
      unawaited(_startAutoVoiceTurn());
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        max,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _startAutoVoiceTurn() async {
    if (!mounted) return;
    // Strict turn-taking: only auto-listen when bot audio finished cleanly.
    if (!_autoListenArmedByCompletedBotAudio) return;
    if (_isRecording || _isBotAudioPlaying) return;

    // Give UI/audio teardown a moment to settle before opening mic again.
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    if (_isRecording || _isBotAudioPlaying) return;

    // Backend follow-up polling can transiently hold processing=true even after
    // bot voice is done. Wait briefly so hands-free turn-taking feels natural.
    for (var i = 0; i < 12; i++) {
      if (!mounted) return;
      if (!_isProcessing) break;
      await Future.delayed(const Duration(milliseconds: 250));
    }

    if (!mounted) return;
    if (_isRecording || _isBotAudioPlaying) return;
    // Do not force clear processing state; it causes overlapping turns and
    // stale "Listening.../Getting transcript..." bubbles.
    if (_isProcessing) return;
    _autoListenArmedByCompletedBotAudio = false;
    await startRecording();
  }

  Future<void> _stopBargeInMonitor() async {
    _bargeAmpSub?.cancel();
    _bargeAmpSub = null;
    try {
      await _bargeInRecorder.stop();
    } catch (_) {}
    final p = _bargeInPath;
    _bargeInPath = null;
    if (p != null) {
      try {
        final f = File(p);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _startBargeInMonitor() async {
    // Disabled for stable full-length bot playback.
    return;
  }

  Future<void> _stopBotAudioPlayback() async {
    _nbqPlaybackGeneration++;
    final tid = _playingNbqTurnId;
    try {
      await _nbqAudioPlayer.stop();
    } catch (_) {}
    try {
      await _botAudioPlayer.stop();
    } catch (_) {}
    await _tts.stop();
    await _stopBargeInMonitor();
    if (!mounted) {
      return;
    }
    if (tid != null) {
      _clearNbqAwaitingForTurnId(tid);
    }
    setState(() {
      _isBotAudioPlaying = false;
      _playingNbqTurnId = null;
      _activeBotAudioPath = null;
      _isBotAudioPaused = false;
    });
    HapticFeedback.lightImpact();
    unawaited(_ensureMicOffAfterBotPlayback());
    unawaited(_startAutoVoiceTurn());
  }

  Future<void> startRecording() async {
    _autoListenArmedByCompletedBotAudio = false;
    if (_isRecording || _isBotAudioPlaying) return;

    // Request permission on first tap (and again if needed).
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required')),
      );
      return;
    }

    await _stopBargeInMonitor();
    _stopMicLevelMonitoring();
    await _tts.stop();
    await _nbqAudioPlayer.stop();
    _livePcmBuffer.clear();
    _activeUtterancePcmBuffer.clear();
    _clearStreamPreRoll();
    _readyUtterancePcm = null;
    _latestPartialTranscript = '';
    _serverSpeechActive = false;
    _liveTranscriptMessageIndex = null;
    _silenceAutoStopTimer?.cancel();
    _debouncedTranscriptBuffer.clear();
    _debouncedPcmBuffer.clear();
    _debouncedMessageIndex = null;
    _pendingStreamingTurns.clear();
    _turnProcessingInFlight = false;
    await _livePartialSub?.cancel();
    await _liveFinalSub?.cancel();
    await _liveErrorSub?.cancel();
    await _liveSpeechEventSub?.cancel();
    await _liveAudioSub?.cancel();

    try {
      await _sarvamStreaming.connect();
      _livePartialSub = _sarvamStreaming.partialTranscripts.listen((partial) {
        _latestPartialTranscript = partial;
        _upsertLivePartialTranscript(partial);
      }, onError: (error) {
        if (kDebugMode) debugPrint('[streaming] partial stream error: $error');
      });
      _liveErrorSub = _sarvamStreaming.errors.listen((message) {
        if (kDebugMode) debugPrint('[streaming] server error: $message');
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Streaming failed: $message')));
      });
      _liveSpeechEventSub = _sarvamStreaming.speechEvents.listen((event) {
        if (event == SarvamSpeechEvent.startSpeech) {
          _silenceAutoStopTimer?.cancel();
          _serverSpeechActive = true;
          _activeUtterancePcmBuffer.clear();
          final preRoll = _snapshotStreamPreRoll();
          if (preRoll.isNotEmpty) {
            _activeUtterancePcmBuffer.add(preRoll);
          }
          _ensureLivePlaceholderMessage();
          return;
        }
        _serverSpeechActive = false;
        _readyUtterancePcm = _activeUtterancePcmBuffer.takeBytes();
        _silenceAutoStopTimer?.cancel();
        _silenceAutoStopTimer = Timer(_silenceAutoStopDelay, () {
          if (!mounted || !_isRecording || _isProcessing || _isBotAudioPlaying) {
            return;
          }
          unawaited(_stopRecordingAndSend());
        });
      });
      _liveFinalSub = _sarvamStreaming.finalTranscripts.listen((finalText) {
        final t = finalText.trim();
        if (t.isEmpty) return;
        final utterancePcm = _readyUtterancePcm ?? Uint8List(0);
        _readyUtterancePcm = null;
        if (_debouncedTranscriptBuffer.isNotEmpty) {
          _debouncedTranscriptBuffer.write(' ');
        }
        _debouncedTranscriptBuffer.write(t);
        if (utterancePcm.isNotEmpty) {
          _debouncedPcmBuffer.add(utterancePcm);
        }
        _debouncedMessageIndex ??= _liveTranscriptMessageIndex;
      }, onError: (error) {
        if (kDebugMode) debugPrint('[streaming] final stream error: $error');
      });
      final stream = await _audioRecorder.startStream(_liveStreamRecordConfig);
      _liveAudioSub = stream.listen(
        (chunk) {
          _livePcmBuffer.add(chunk);
          _appendStreamPreRollChunk(chunk);
          if (_serverSpeechActive) {
            _activeUtterancePcmBuffer.add(chunk);
          }
          _sarvamStreaming.sendAudioChunk(chunk);
        },
        onError: (_) {},
      );

      if (!mounted) return;
      setState(() {
        _isRecording = true;
      });
      HapticFeedback.lightImpact();
      _startMicLevelMonitoring();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[streaming] failed to start live recording: $e');
        debugPrint('$st');
      }
      final message = e.toString().contains('Missing STREAMING_PROXY_WS_ENDPOINT')
          ? 'Live streaming is not configured. Set STREAMING_PROXY_WS_ENDPOINT.'
          : 'Could not start live streaming recording';
      if (!mounted) return;
      setState(() {
        _isRecording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<String?> stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (_stopInProgress) return;
    _stopInProgress = true;
    try {
      _stopMicLevelMonitoring();
      if (mounted) {
        setState(() => _micInputLevel = 0);
      }
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });
      _silenceAutoStopTimer?.cancel();

      await _liveAudioSub?.cancel();
      _liveAudioSub = null;
      try {
        await _audioRecorder.stop();
      } catch (_) {}
      // Ask server to finalize any buffered speech before closing socket/listeners.
      try {
        await _sarvamStreaming.requestFlush();
        await Future.delayed(const Duration(milliseconds: 900));
      } catch (_) {}
      await _liveFinalSub?.cancel();
      _liveFinalSub = null;
      await _liveErrorSub?.cancel();
      _liveErrorSub = null;
      await _liveSpeechEventSub?.cancel();
      _liveSpeechEventSub = null;
      await _livePartialSub?.cancel();
      _livePartialSub = null;
      await _sarvamStreaming.close();
      _serverSpeechActive = false;
      _readyUtterancePcm = null;
      _liveTranscriptMessageIndex = null;
      _flushDebouncedStreamingTurn();
      await _drainStreamingTurnQueue();
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    } finally {
      _stopInProgress = false;
    }
  }

  void _ensureLivePlaceholderMessage() {
    if (!mounted) return;
    if (_liveTranscriptMessageIndex != null) return;
    setState(() {
      _messages.add(
        _newMessage(
          text: 'Listening...',
          isUser: true,
          isThinking: true,
        ),
      );
      _liveTranscriptMessageIndex = _messages.length - 1;
    });
    _scrollToBottom();
  }

  void _upsertLivePartialTranscript(String partial) {
    if (!mounted) return;
    final trimmed = partial.trim();
    if (trimmed.isEmpty) return;
    _ensureLivePlaceholderMessage();
    final idx = _liveTranscriptMessageIndex;
    if (idx == null || idx < 0 || idx >= _messages.length) return;
    setState(() {
      final existing = _messages[idx];
      _messages[idx] = ChatMessage(
        text: trimmed,
        isUser: true,
        isThinking: true,
        timestamp: existing.timestamp,
        localUserAudioPath: existing.localUserAudioPath,
        localBotAudioPath: existing.localBotAudioPath,
      );
    });
  }

  void _flushDebouncedStreamingTurn() {
    final transcript = _debouncedTranscriptBuffer.toString().trim();
    if (transcript.isEmpty) return;
    final pcmBytes = _debouncedPcmBuffer.takeBytes();
    final messageIndex = _debouncedMessageIndex;
    _debouncedTranscriptBuffer.clear();
    _debouncedPcmBuffer.clear();
    _debouncedMessageIndex = null;
    _pendingStreamingTurns.add((
      transcript: transcript,
      pcmBytes: pcmBytes,
      messageIndex: messageIndex,
    ));
    unawaited(_drainStreamingTurnQueue());
  }

  Future<void> _drainStreamingTurnQueue() async {
    if (_turnProcessingInFlight) return;
    _turnProcessingInFlight = true;
    try {
      while (_pendingStreamingTurns.isNotEmpty) {
        final turn = _pendingStreamingTurns.removeAt(0);
        await _processStreamingTurn(
          transcript: turn.transcript,
          pcmBytes: turn.pcmBytes,
          messageIndex: turn.messageIndex,
        );
      }
    } finally {
      _turnProcessingInFlight = false;
      if (mounted && !_isRecording) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _processStreamingTurn({
    required String transcript,
    required Uint8List pcmBytes,
    required int? messageIndex,
  }) async {
    if (!mounted) return;
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return;
    if (mounted) {
      setState(() => _isProcessing = true);
    }
    final wavBytes = _pcm16ToWavBytes(pcmBytes);
    final tempWavPath = await _writeWavToTempFile(wavBytes);
    final localUserAudioPath = await _copyUserAudioToLocalHistory(tempWavPath);

    void setUserProgressStage(int index, String label) {
      if (!mounted) return;
      if (index < 0 || index >= _messages.length) return;
      setState(() {
        final existing = _messages[index];
        _messages[index] = ChatMessage(
          text: label,
          isUser: true,
          isThinking: true,
          timestamp: existing.timestamp,
          localUserAudioPath: existing.localUserAudioPath,
          localBotAudioPath: existing.localBotAudioPath,
        );
      });
      _scrollToBottom();
    }

    var processingMessageIndex = messageIndex ?? -1;
    if (processingMessageIndex < 0 ||
        processingMessageIndex >= _messages.length ||
        !_messages[processingMessageIndex].isUser) {
      if (mounted) {
        setState(() {
          _messages.add(
            _newMessage(
              text: _stageRequestingUploadLink,
              isUser: true,
              isThinking: true,
              localUserAudioPath: localUserAudioPath,
            ),
          );
          processingMessageIndex = _messages.length - 1;
        });
        _scrollToBottom();
      }
    } else {
      setUserProgressStage(processingMessageIndex, _stageStreamingTranscription);
    }

    try {
      setUserProgressStage(processingMessageIndex, _stageStreamingTranscription);
      final streamingResult = await _postToStreamingBackend(
        transcript: trimmed,
        wavBytes: wavBytes,
      );
      if (!mounted) return;
      final payload = _TranscriptNbqResult(transcript: streamingResult.transcript);
      setState(() {
        if (processingMessageIndex >= 0 &&
            processingMessageIndex < _messages.length) {
          final existing = _messages[processingMessageIndex];
          _messages[processingMessageIndex] = ChatMessage(
            text: payload.transcript,
            isUser: true,
            isThinking: false,
            timestamp: existing.timestamp,
            localUserAudioPath: existing.localUserAudioPath ?? localUserAudioPath,
            localBotAudioPath: existing.localBotAudioPath,
          );
        }
        _messages.add(
          _newMessage(
            text: _stageLoadingFollowUp,
            isUser: false,
            isThinking: true,
          ),
        );
      });
      _scrollToBottom();
      unawaited(_saveChatHistory());
      final uploadedFileName = streamingResult.audioKey?.trim();
      if (uploadedFileName != null && uploadedFileName.isNotEmpty) {
        final typingMessageIndex = _messages.length - 1;
        final generation = _nbqPlaybackGeneration;
        unawaited(
          _pollNextBestQuestion(uploadedFileName, typingMessageIndex, generation),
        );
      } else {
        if (mounted) {
          setState(() {
            final lastIndex = _messages.length - 1;
            if (lastIndex >= 0 &&
                !_messages[lastIndex].isUser &&
                _messages[lastIndex].isThinking) {
              final existing = _messages[lastIndex];
              _messages[lastIndex] = ChatMessage(
                text: _errFollowUpTimeout,
                isUser: false,
                isThinking: false,
                timestamp: existing.timestamp,
                localBotAudioPath: existing.localBotAudioPath,
              );
            }
          });
        }
      }
    } catch (e, st) {
      debugPrint('Upload/transcript flow failed: $e');
      debugPrint('$st');
      if (!mounted) return;
      final String userFacing;
      if (e is _UploadFlowException) {
        userFacing = e.userMessage;
      } else if (e is _TranscriptFlowException) {
        userFacing = e.userMessage;
      } else {
        userFacing = _errUnexpected;
      }
      setState(() {
        if (processingMessageIndex >= 0 &&
            processingMessageIndex < _messages.length) {
          final existing = _messages[processingMessageIndex];
          _messages[processingMessageIndex] = ChatMessage(
            text: userFacing,
            isUser: true,
            isThinking: false,
            timestamp: existing.timestamp,
            localUserAudioPath: existing.localUserAudioPath,
            localBotAudioPath: existing.localBotAudioPath,
          );
        }
      });
      unawaited(_saveChatHistory());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacing)));
    } finally {
      try {
        final temp = File(tempWavPath);
        if (await temp.exists()) {
          await temp.delete();
        }
      } catch (_) {}
      if (mounted && !_isRecording && _pendingStreamingTurns.isEmpty) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<String> _uploadRecording(
    String localAudioPath, {
    required void Function(String stageLabel) onStage,
  }) async {
    onStage(_stageRequestingUploadLink);

    final file = File(localAudioPath);
    if (!await file.exists()) {
      throw const _UploadFlowException(_errUploadFileMissing);
    }

    final userId = (_userId == null || _userId!.isEmpty)
        ? 'anonymous'
        : _userId!;
    late final http.Response createResponse;
    try {
      createResponse = await http
          .post(
            Uri.parse(_uploadAudioEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId}),
          )
          .timeout(_uploadPostTimeout);
    } on TimeoutException {
      throw const _UploadFlowException(_errUploadLinkFailed);
    } catch (e, st) {
      debugPrint('upload-audio POST error: $e\n$st');
      throw const _UploadFlowException(_errUploadLinkFailed);
    }

    if (createResponse.statusCode < 200 || createResponse.statusCode >= 300) {
      debugPrint(
        'upload-audio POST ${createResponse.statusCode} ${createResponse.body}',
      );
      throw const _UploadFlowException(_errUploadLinkBadResponse);
    }

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(createResponse.body) as Map<String, dynamic>;
    } catch (_) {
      throw const _UploadFlowException(_errUploadInvalidResponse);
    }

    final uploadUrl = payload['uploadURL'] as String?;
    final fileKey = payload['fileKey'] as String?;
    final conversationId = payload['conversation_id'];

    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw const _UploadFlowException(_errUploadInvalidResponse);
    }
    if (fileKey == null || fileKey.isEmpty) {
      throw const _UploadFlowException(_errUploadInvalidResponse);
    }

    onStage(_stageSendingAudio);

    final fileBytes = await file.readAsBytes();
    late final http.Response uploadResponse;
    try {
      uploadResponse = await http
          .put(
            Uri.parse(uploadUrl),
            headers: {'Content-Type': 'audio/wav'},
            body: fileBytes,
          )
          .timeout(_uploadPutTimeout);
    } on TimeoutException {
      throw const _UploadFlowException(_errUploadSendFailed);
    } catch (e, st) {
      debugPrint('Audio PUT error: $e\n$st');
      throw const _UploadFlowException(_errUploadSendFailed);
    }

    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      debugPrint(
        'Audio PUT ${uploadResponse.statusCode} ${uploadResponse.body}',
      );
      throw const _UploadFlowException(_errUploadSendFailed);
    }

    if (conversationId != null) {
      debugPrint('Uploaded conversation_id: $conversationId');
    }
    if (kDebugMode) {
      debugPrint('[transcript] fileKey for API (use full S3 path): $fileKey');
    }
    return fileKey;
  }

  Future<({String transcript, String? audioKey})> _postToStreamingBackend({
    required String transcript,
    required Uint8List wavBytes,
  }) async {
    if (_streamingTranscribeEndpoint.trim().isEmpty) {
      throw const _TranscriptFlowException(_errStreamingFailed);
    }
    final userId = (_userId == null || _userId!.isEmpty) ? 'anonymous' : _userId!;
    final audioBase64 = base64Encode(wavBytes);
    late final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_streamingTranscribeEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'session_date': DateTime.now().toIso8601String().substring(0, 10),
              'transcript': transcript,
              'audio_base64': audioBase64,
              'sample_rate': 16000,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(_streamingPostTimeout);
    } on TimeoutException {
      throw const _TranscriptFlowException(_errStreamingFailed);
    } catch (_) {
      throw const _TranscriptFlowException(_errStreamingFailed);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const _TranscriptFlowException(_errStreamingFailed);
    }

    final parsed = jsonDecode(response.body);
    if (parsed is! Map<String, dynamic>) {
      throw const _TranscriptFlowException(_errStreamingFailed);
    }

    final parsedTranscript = (parsed['transcript'] as String?)?.trim() ?? '';
    final saved = parsed['saved'];
    final audioKey = saved is Map<String, dynamic> ? saved['audio'] as String? : null;
    if (parsedTranscript.isEmpty) {
      throw const _TranscriptFlowException(_errStreamingFailed);
    }
    return (transcript: parsedTranscript, audioKey: audioKey);
  }

  void _appendStreamPreRollChunk(Uint8List chunk) {
    if (chunk.isEmpty) return;
    _streamPreRollChunks.add(chunk);
    _streamPreRollTotalBytes += chunk.length;
    while (_streamPreRollTotalBytes > _streamPreRollMaxBytes &&
        _streamPreRollChunks.isNotEmpty) {
      final removed = _streamPreRollChunks.removeAt(0);
      _streamPreRollTotalBytes -= removed.length;
    }
  }

  void _clearStreamPreRoll() {
    _streamPreRollChunks.clear();
    _streamPreRollTotalBytes = 0;
  }

  Uint8List _snapshotStreamPreRoll() {
    if (_streamPreRollTotalBytes == 0) return Uint8List(0);
    final out = Uint8List(_streamPreRollTotalBytes);
    var offset = 0;
    for (final c in _streamPreRollChunks) {
      out.setRange(offset, offset + c.length, c);
      offset += c.length;
    }
    return out;
  }

  Uint8List _pcm16ToWavBytes(Uint8List pcmBytes, {int sampleRate = 16000}) {
    final totalDataLen = pcmBytes.length;
    final totalLen = 44 + totalDataLen;
    final out = BytesBuilder(copy: false);
    final header = ByteData(44);
    void writeString(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    header.setUint32(4, totalLen - 8, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample
    writeString(36, 'data');
    header.setUint32(40, totalDataLen, Endian.little);
    out.add(header.buffer.asUint8List());
    out.add(pcmBytes);
    return out.toBytes();
  }

  Future<String> _writeWavToTempFile(Uint8List wavBytes) async {
    final safeUserId = (_userId == null || _userId!.isEmpty)
        ? 'anonymous'
        : _userId!.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final dir = Directory.systemTemp;
    final path = '${dir.path}/${safeUserId}_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = File(path);
    await file.writeAsBytes(wavBytes, flush: true);
    return file.path;
  }

  Future<_TranscriptNbqResult> _waitForTranscriptPayload(
    String uploadedFileName, {
    required void Function(String stageLabel) onStage,
  }) async {
    onStage(_stageProcessingRecording);
    // Backend creates transcript with delay; wait before first lookup.
    await Future.delayed(const Duration(seconds: 10));

    onStage(_stageGettingTranscript);
    for (var attempt = 0; attempt < 6; attempt++) {
      final payload = await _fetchTranscriptPayload(uploadedFileName);
      if (payload != null && payload.transcript.isNotEmpty) {
        return payload;
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    throw const _TranscriptFlowException(_errTranscriptFailed);
  }

  /// Poll every 2s until `next_best_question` is set (20 attempts → 40s max; NBQ Lambda can be slow).
  /// Audio URL may arrive later; [_resolveAndPlayNbqVoice] polls further for `nbq_audio_url`.
  Future<void> _pollNextBestQuestion(
    String uploadedFileName,
    int typingMessageIndex,
    int generation,
  ) async {
    const maxNbqPolls = 20;
    for (var attempt = 0; attempt < maxNbqPolls; attempt++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final payload = await _fetchTranscriptPayload(uploadedFileName);
      final nbq = payload?.nextBestQuestion?.trim();
      if (nbq != null && nbq.isNotEmpty) {
        if (!mounted) return;
        final audioUrl = payload!.nbqAudioUrl;
        final tid = _nextNbqTurnId();
        setState(() {
          if (typingMessageIndex >= 0 &&
              typingMessageIndex < _messages.length &&
              !_messages[typingMessageIndex].isUser &&
              _messages[typingMessageIndex].isThinking) {
            final existing = _messages[typingMessageIndex];
            _messages[typingMessageIndex] = ChatMessage(
              text: nbq,
              isUser: false,
              isThinking: false,
              timestamp: existing.timestamp,
              localBotAudioPath: existing.localBotAudioPath,
              nbqAwaitingVoice: true,
              nbqTurnId: tid,
              nbqVoiceGeneration: generation,
            );
          }
        });
        _scrollToBottom();
        unawaited(_saveChatHistory());
        _nbqVoiceSessions[tid] = _NbqVoiceSession(
          turnId: tid,
          generation: generation,
          nbqText: nbq,
          uploadedFileName: uploadedFileName,
        );
        if (mounted) {
          await _resolveAndPlayNbqVoice(
            uploadedFileName: uploadedFileName,
            nbqText: nbq,
            turnId: tid,
            initialAudioUrl: audioUrl,
            generation: generation,
          );
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      if (typingMessageIndex >= 0 &&
          typingMessageIndex < _messages.length &&
          !_messages[typingMessageIndex].isUser &&
          _messages[typingMessageIndex].isThinking) {
        final existing = _messages[typingMessageIndex];
        _messages[typingMessageIndex] = ChatMessage(
          text: _errFollowUpTimeout,
          isUser: false,
          isThinking: false,
          timestamp: existing.timestamp,
          localBotAudioPath: existing.localBotAudioPath,
        );
      }
    });
    unawaited(_saveChatHistory());
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(_errFollowUpTimeout)));
    unawaited(_startAutoVoiceTurn());
  }

  /// API Gateway / Lambda often expect `fileName=audio-input/...` with **literal** slashes.
  /// Dart's [Uri.replace](queryParameters: {fileName: path}) encodes `/` as `%2F`, which can break lookups.
  Uri _transcriptUriWithQuery(
    Uri base, {
    required Map<String, String> query,
    bool literalSlashesInFileName = false,
  }) {
    if (!literalSlashesInFileName) {
      return base.replace(queryParameters: query);
    }
    final parts = <String>[];
    for (final e in query.entries) {
      final encKey = Uri.encodeQueryComponent(e.key);
      if (e.key == 'fileName') {
        final v = e.value.split('/').map(Uri.encodeQueryComponent).join('/');
        parts.add('$encKey=$v');
      } else {
        parts.add('$encKey=${Uri.encodeQueryComponent(e.value)}');
      }
    }
    return base.replace(query: parts.join('&'));
  }

  List<Uri> _transcriptLookupUris(String uploadedFileName) {
    final messageId = _messageIdFromFileName(uploadedFileName);
    final baseUri = Uri.parse(_transcriptEndpoint);
    final baseParams = Map<String, String>.from(baseUri.queryParameters);

    final withFullPath = {...baseParams, 'fileName': uploadedFileName};
    final withIdAsFileName = {...baseParams, 'fileName': messageId};
    final withMessageIdOnly = {...baseParams, 'messageId': messageId};

    void addDistinct(List<Uri> out, Uri u) {
      if (!out.any((e) => e.toString() == u.toString())) {
        out.add(u);
      }
    }

    final out = <Uri>[];
    // 1–2: Full key `audio-input/.../id.wav` (encoded vs literal slashes for API Gateway).
    addDistinct(
      out,
      _transcriptUriWithQuery(
        baseUri,
        query: withFullPath,
        literalSlashesInFileName: false,
      ),
    );
    addDistinct(
      out,
      _transcriptUriWithQuery(
        baseUri,
        query: withFullPath,
        literalSlashesInFileName: true,
      ),
    );
    // 3: Short id as `fileName` (same logical file when backend expects basename only).
    if (messageId != uploadedFileName) {
      addDistinct(
        out,
        _transcriptUriWithQuery(
          baseUri,
          query: withIdAsFileName,
          literalSlashesInFileName: false,
        ),
      );
    }
    // 4: `messageId` query (Lambda should treat like fileName once wired).
    addDistinct(
      out,
      _transcriptUriWithQuery(
        baseUri,
        query: withMessageIdOnly,
        literalSlashesInFileName: false,
      ),
    );
    return out;
  }

  Future<_TranscriptNbqResult?> _fetchTranscriptPayload(
    String uploadedFileName,
  ) async {
    final triedUris = _transcriptLookupUris(uploadedFileName);

    for (final uri in triedUris) {
      try {
        if (kDebugMode) {
          debugPrint('[transcript] GET $uri');
        }
        final res = await http.get(uri).timeout(_transcriptGetTimeout);
        if (kDebugMode) {
          final preview = res.body.length > 400
              ? '${res.body.substring(0, 400)}…'
              : res.body;
          debugPrint('[transcript] status=${res.statusCode} body=$preview');
        }
        if (res.statusCode < 200 || res.statusCode >= 300) continue;
        if (res.body.trim().isEmpty) continue;
        final parsed = jsonDecode(res.body);
        final payload = _parseTranscriptPayload(parsed);
        if (payload != null) {
          if (kDebugMode) {
            debugPrint(
              '[transcript] parsed transcriptLen=${payload.transcript.length} '
              'nbq=${payload.nextBestQuestion != null ? "yes" : "null"} '
              'nbqAudio=${payload.nbqAudioUrl != null && payload.nbqAudioUrl!.isNotEmpty ? "yes" : "null"}',
            );
          }
          return payload;
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[transcript] request/parse error: $e');
          debugPrint('$st');
        }
        continue;
      }
    }
    return null;
  }

  _TranscriptNbqResult? _parseTranscriptPayload(dynamic parsed) {
    if (parsed is Map<String, dynamic>) {
      final transcript = _extractTranscriptValue(parsed);
      final nbq = _extractNextBestQuestion(parsed);
      final nbqAudio = _extractNbqAudioUrl(parsed);
      final hasTranscript = transcript != null && transcript.trim().isNotEmpty;
      final hasNbq = nbq != null && nbq.trim().isNotEmpty;
      final hasNbqAudio = nbqAudio != null && nbqAudio.trim().isNotEmpty;
      // get-transcript often returns only NBQ + presigned URL; still a usable payload.
      if (!hasTranscript && !hasNbq && !hasNbqAudio) return null;
      return _TranscriptNbqResult(
        transcript:
            hasTranscript ? _userFacingTranscript(transcript.trim()) : '',
        nextBestQuestion: nbq,
        nbqAudioUrl: nbqAudio,
      );
    }
    if (parsed is List) {
      for (final item in parsed) {
        final nested = _parseTranscriptPayload(item);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  /// Reads NBQ from root or nested maps (`data`, etc.) and alternate key names.
  String? _extractNextBestQuestion(dynamic data) {
    if (data is Map<String, dynamic>) {
      const keys = [
        'next_best_question',
        'nextBestQuestion',
        'nbq',
        'next_question',
      ];
      for (final key in keys) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      for (final value in data.values) {
        if (value is Map || value is List) {
          final nested = _extractNextBestQuestion(value);
          if (nested != null) return nested;
        }
      }
    } else if (data is List) {
      for (final value in data) {
        final nested = _extractNextBestQuestion(value);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  /// Reads `nbq_audio_url` from root or nested maps (snake_case / camelCase).
  String? _extractNbqAudioUrl(dynamic data) {
    if (data is Map<String, dynamic>) {
      const keys = ['nbq_audio_url', 'nbqAudioUrl'];
      for (final key in keys) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      for (final value in data.values) {
        if (value is Map || value is List) {
          final nested = _extractNbqAudioUrl(value);
          if (nested != null) return nested;
        }
      }
    } else if (data is List) {
      for (final value in data) {
        final nested = _extractNbqAudioUrl(value);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  String _messageIdFromFileName(String uploadedFileName) {
    final last = uploadedFileName.split('/').last;
    final dot = last.lastIndexOf('.');
    return dot > 0 ? last.substring(0, dot) : last;
  }

  /// Resolves the user-facing transcript. API may return `transcript` as a **stringified JSON**
  /// blob whose inner field `transcript` holds the actual speech text.
  String? _extractTranscriptValue(dynamic data) {
    if (data is Map<String, dynamic>) {
      final direct = data['transcript'];
      if (direct is String && direct.trim().isNotEmpty) {
        final t = direct.trim();
        if (t.startsWith('{') || t.startsWith('[')) {
          final nested = _tryExtractFromJsonString(t);
          if (nested != null && nested.trim().isNotEmpty) {
            return nested.trim();
          }
          return _extractPlainStringFromJsonObject(t);
        }
        return t;
      }
      for (final value in data.values) {
        final nested = _extractTranscriptValue(value);
        if (nested != null) return nested;
      }
    } else if (data is List) {
      for (final value in data) {
        final nested = _extractTranscriptValue(value);
        if (nested != null) return nested;
      }
    } else if (data is String) {
      return _tryExtractFromJsonString(data);
    }
    return null;
  }

  String? _tryExtractFromJsonString(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final nestedDecoded = jsonDecode(text);
        final fromMap = _extractTranscriptValue(nestedDecoded);
        if (fromMap != null && fromMap.trim().isNotEmpty) {
          return fromMap.trim();
        }
        return _extractPlainStringFromJsonObject(text);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Strips nested JSON / metadata so chat never shows raw API blobs.
  String _userFacingTranscript(String raw) {
    var t = raw.trim();
    if (t.isEmpty) {
      return t;
    }
    for (var i = 0; i < 4; i++) {
      if (!t.startsWith('{') && !t.startsWith('[')) {
        break;
      }
      final inner = _tryExtractFromJsonString(t);
      if (inner == null || inner.trim().isEmpty) {
        final fallback = _extractPlainStringFromJsonObject(t);
        return (fallback ?? t).trim();
      }
      t = inner.trim();
    }
    if (t.startsWith('{') || t.startsWith('[')) {
      final fallback = _extractPlainStringFromJsonObject(t);
      if (fallback != null && fallback.trim().isNotEmpty) {
        return fallback.trim();
      }
    }
    return t;
  }

  /// Picks the first human-readable string field from JSON (not another JSON blob).
  String? _extractPlainStringFromJsonObject(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map) {
        final m = Map<String, dynamic>.from(decoded);
        const keys = [
          'transcript',
          'text',
          'message',
          'speech',
          'content',
          'body',
          'utterance',
          'recognizedText',
          'recognized_text',
        ];
        for (final key in keys) {
          final v = m[key];
          if (v is String) {
            final s = v.trim();
            if (s.isEmpty) {
              continue;
            }
            if (s.startsWith('{') || s.startsWith('[')) {
              final deeper = _userFacingTranscript(s);
              if (deeper.isNotEmpty &&
                  !deeper.startsWith('{') &&
                  !deeper.startsWith('[')) {
                return deeper;
              }
              continue;
            }
            return s;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _openSettingsPage() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  Future<void> _onBottomNavTap(int index) async {
    if (index == 0) {
      setState(() => _selectedBottomTab = 0);
      return;
    }
    if (index == 1) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen()));
    } else if (index == 2) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const FamilyScreen()));
    } else if (index == 3) {
      await _openSettingsPage();
    } else if (index == 4) {
      await Navigator.pushNamed(context, '/profile');
    }
    if (!mounted) {
      return;
    }
    setState(() => _selectedBottomTab = 0);
  }

  VoiceUiPhase get _voicePhase {
    if (_isBotAudioPlaying) {
      return VoiceUiPhase.speaking;
    }
    if (_isProcessing) {
      return VoiceUiPhase.processing;
    }
    if (_isRecording) {
      return VoiceUiPhase.listening;
    }
    return VoiceUiPhase.idle;
  }

  String _bottomPhaseHint() {
    switch (_voicePhase) {
      case VoiceUiPhase.idle:
        return 'Mike daba kar boliye';
      case VoiceUiPhase.listening:
        return 'Main sun raha hoon...';
      case VoiceUiPhase.processing:
        return 'Aapki baat samajh raha hoon...';
      case VoiceUiPhase.speaking:
        return 'Jawab suna raha hoon...';
    }
  }

  String _welcomeTitle() {
    final n = _userName;
    if (n == null || n.isEmpty) {
      return 'Welcome ji';
    }
    return 'Welcome $n ji';
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}${date.year != now.year ? ' ${date.year}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final micSize = (mq.shortestSide * 0.2).clamp(56.0, 86.0);
    final chatChildren = <Widget>[];
    DateTime? lastDay;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final day = DateTime(
        m.timestamp.year,
        m.timestamp.month,
        m.timestamp.day,
      );
      if (lastDay == null ||
          day.year != lastDay.year ||
          day.month != lastDay.month ||
          day.day != lastDay.day) {
        lastDay = day;
        chatChildren.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: SaathiBeige.surfaceElevated.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: SaathiBeige.charcoal.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  _dateLabel(m.timestamp),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: SaathiBeige.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      }
      final path = m.localUserAudioPath;
      final hasPath = path != null && path.isNotEmpty;
      final botPath = m.localBotAudioPath;
      final hasBotPath = botPath != null && botPath.isNotEmpty;
      final canReplayBot =
          !m.isUser &&
          !m.isThinking &&
          m.text.trim().isNotEmpty &&
          hasBotPath;
      chatChildren.add(
        MessageBubble(
          message: m,
          onUserAudioTap: m.isUser && !m.isThinking && hasPath
              ? () => unawaited(_playUserAudio(m))
              : null,
          onUserAudioPause: m.isUser && !m.isThinking && hasPath
              ? _pauseOrResumeUserAudio
              : null,
          onUserAudioStop: m.isUser &&
                  !m.isThinking &&
                  hasPath &&
                  path == _activeUserAudioPath
              ? () => unawaited(_stopUserAudio())
              : null,
          isUserAudioActive: hasPath && path == _activeUserAudioPath,
          isUserAudioPaused:
              hasPath && path == _activeUserAudioPath && _isUserAudioPaused,
          onBotAudioTap: canReplayBot
              ? () => unawaited(_playBotAudio(m))
              : null,
          onBotAudioPause: hasBotPath && botPath == _activeBotAudioPath
              ? _pauseOrResumeBotAudio
              : null,
          onBotAudioStop: hasBotPath && botPath == _activeBotAudioPath
              ? () => unawaited(_stopBotAudio())
              : null,
          isBotAudioActive: hasBotPath && botPath == _activeBotAudioPath,
          isBotAudioPaused:
              hasBotPath && botPath == _activeBotAudioPath && _isBotAudioPaused,
        ),
      );
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Keep a fixed small gap above the actual bottom bar height,
    // so font scaling doesn't push the mic higher than needed.
    final footerReserve = (_bottomBarHeight <= 0 ? 78.0 : _bottomBarHeight) +
        6 +
        bottomInset;
    final extraScrollGap =
        AppSettings.instance.fontScale >= 1.15 ? 22.0 : 0.0;
    final chatBottomInset = footerReserve + micSize * 1.0 + extraScrollGap;

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: SaathiBeige.backgroundGradient,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SafeArea(
                    bottom: false,
                    child: PremiumVoiceHeader(
                      title: _welcomeTitle(),
                      subtitle: 'Aapki kahani, aapki zubaani',
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: _messages.isEmpty
                          ? Padding(
                              // Keep the center text within the exact usable chat area:
                              // below header and above mic/nav reserved zone.
                              padding: EdgeInsets.fromLTRB(
                                28,
                                0,
                                28,
                                chatBottomInset,
                              ),
                              child: Center(
                                child: Text(
                                  'Kaisa jaa raha aapka din?',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: SaathiBeige.muted,
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                ),
                              ),
                            )
                          : ListView(
                              controller: _scrollController,
                              padding: EdgeInsets.fromLTRB(
                                10,
                                0,
                                10,
                                chatBottomInset,
                              ),
                              children: chatChildren,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              bottom: footerReserve + 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PremiumVoiceMic(
                    phase: _voicePhase,
                    inputLevel: _micInputLevel,
                    size: micSize,
                    onTap: () async {
                      if (_isBotAudioPlaying) {
                        await _stopBotAudioPlayback();
                      }
                      if (_isRecording) {
                        HapticFeedback.mediumImpact();
                        await _stopRecordingAndSend();
                        return;
                      }
                      if (_isProcessing) {
                        // Let user interrupt long backend follow-up work
                        // and start a fresh speaking turn immediately.
                        _nbqPlaybackGeneration++;
                        _pendingStreamingTurns.clear();
                        _turnProcessingInFlight = false;
                        if (mounted) {
                          setState(() {
                            _isProcessing = false;
                          });
                        }
                      }
                      await startRecording();
                    },
                  ),
                  
                ],
              ),
            ),
            Positioned(
              left: 12,
              bottom: footerReserve + 14,
              right: micSize * 1.2 + 36,
              child: Align(
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: SaathiBeige.surfaceElevated.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: SaathiBeige.accent.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: SaathiBeige.charcoal.withValues(alpha: 0.07),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      _bottomPhaseHint(),
                      textAlign: TextAlign.left,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: SaathiBeige.accentDeep,
                        fontWeight: FontWeight.w600,
                        fontSize: 19,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            key: _bottomBarKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FloatingVoiceNavBar(
                currentIndex: _selectedBottomTab,
                onSelect: (i) => unawaited(_onBottomNavTap(i)),
              ),
              const SizedBox(height: 6),
              Text(
                'AI responses may not always be accurate.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  color: SaathiBeige.muted.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
