import 'dart:async';

import 'package:record/record.dart';

/// Voice-activity style end-of-utterance detection using mic amplitude from
/// the `record` package (no extra native code).
///
/// For **flutter_sound** PCM frames + **Android WebRTC VAD** via a platform
/// channel, implement the same surface (`start` / `stop` / optional level
/// callback) in a new class and inject it where `_vad` is constructed in
/// `chat_screen.dart`.
class AmplitudeVadHandler {
  AmplitudeVadHandler({
    required this.recorder,
    required this.silenceThresholdDb,
    required this.silenceDuration,
    this.pollInterval = const Duration(milliseconds: 200),
  });

  final AudioRecorder recorder;
  final double silenceThresholdDb;
  final Duration silenceDuration;
  final Duration pollInterval;

  StreamSubscription<Amplitude>? _ampSub;
  Timer? _timer;
  DateTime? _lastVoiceAt;
  void Function()? _onSilenceConfirmed;
  bool _armed = false;

  /// Call after [recorder] has successfully started.
  void start({
    required void Function() onSilenceConfirmed,
    void Function(double normalizedLevel)? onLevel,
  }) {
    stop();
    _onSilenceConfirmed = onSilenceConfirmed;
    _armed = true;
    _lastVoiceAt = DateTime.now();

    _ampSub = recorder
        .onAmplitudeChanged(Duration(milliseconds: pollInterval.inMilliseconds))
        .listen((amp) {
          if (!_armed) return;
          if (amp.current > silenceThresholdDb) {
            _lastVoiceAt = DateTime.now();
          }
          onLevel?.call(_normalizeDb(amp.current));
        });

    _timer = Timer.periodic(pollInterval, (_) {
      if (!_armed) return;
      final last = _lastVoiceAt ?? DateTime.now();
      if (DateTime.now().difference(last) >= silenceDuration) {
        _armed = false;
        _onSilenceConfirmed?.call();
      }
    });
  }

  void stop() {
    _armed = false;
    _timer?.cancel();
    _timer = null;
    _ampSub?.cancel();
    _ampSub = null;
    _onSilenceConfirmed = null;
    _lastVoiceAt = null;
  }

  void dispose() {
    stop();
  }

  /// Map dBFS-style amplitude (typical range about -60..0) to 0..1.
  static double _normalizeDb(double db) {
    const floor = -55.0;
    const ceil = -12.0;
    final t = (db - floor) / (ceil - floor);
    if (t <= 0) {
      return 0;
    }
    if (t >= 1) {
      return 1;
    }
    return t;
  }
}
