import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/family_insights_service.dart';
import '../theme/saathi_beige_theme.dart';

class FamilyMemoriesScreen extends StatefulWidget {
  const FamilyMemoriesScreen({
    super.key,
    required this.userId,
    required this.type,
    required this.value,
  });

  final String userId;
  final String type;
  final String value;

  @override
  State<FamilyMemoriesScreen> createState() => _FamilyMemoriesScreenState();
}

class _FamilyMemoriesScreenState extends State<FamilyMemoriesScreen> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  bool _loading = true;
  String? _error;
  List<FamilyMemory> _memories = const <FamilyMemory>[];
  int? _activeIndex;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          _position = _duration;
        }
      });
    });
    _positionSub = _player.positionStream.listen((value) {
      if (!mounted) return;
      setState(() => _position = value);
    });
    _durationSub = _player.durationStream.listen((value) {
      if (!mounted || value == null) return;
      setState(() => _duration = value);
    });
    unawaited(_loadMemories());
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadMemories() async {
    final result = await FamilyInsightsService.instance.fetchMemories(
      userId: widget.userId,
      type: widget.type,
      value: widget.value,
    );
    if (!mounted) return;
    switch (result) {
      case FamilyMemoriesSuccess(:final memories):
        setState(() {
          _loading = false;
          _error = null;
          _memories = memories;
          _activeIndex = null;
          _position = Duration.zero;
          _duration = Duration.zero;
        });
      case FamilyMemoriesFailure(:final message):
        setState(() {
          _loading = false;
          _error = message;
          _memories = const <FamilyMemory>[];
          _activeIndex = null;
          _position = Duration.zero;
          _duration = Duration.zero;
        });
    }
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _memories.length) return;
    final memory = _memories[index];
    try {
      await _player.stop();
      await _player.setUrl(memory.audioUrl);
      unawaited(_player.play());
      if (!mounted) return;
      setState(() {
        _activeIndex = index;
        _isPlaying = true;
        _position = Duration.zero;
        _duration = _player.duration ?? Duration.zero;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play this recording')),
      );
    }
  }

  Future<void> _togglePlayStopAt(int index) async {
    if (_activeIndex != index || !_isPlaying) {
      await _playAt(index);
      return;
    }
    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _activeIndex = null;
      _position = Duration.zero;
    });
  }

  String _fmt(Duration d) {
    final total = d.inSeconds.clamp(0, 359999);
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _audioTile(int index, FamilyMemory memory) {
    final isActive = _activeIndex == index;
    final currentPos = isActive ? _position : Duration.zero;
    final currentDur = isActive ? _duration : Duration.zero;
    final progress = (isActive && currentDur.inMilliseconds > 0)
        ? (currentPos.inMilliseconds / currentDur.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final timeLabel = '${_fmt(currentPos)}/${_fmt(currentDur)}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SaathiBeige.surfaceElevated.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SaathiBeige.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            memory.summary,
            style: TextStyle(
              color: SaathiBeige.charcoal,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                timeLabel,
                style: TextStyle(
                  color: SaathiBeige.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: isActive && _isPlaying ? 'Stop' : 'Play',
                onPressed: () => _togglePlayStopAt(index),
                icon: Icon(
                  isActive && _isPlaying
                      ? Icons.stop_circle_outlined
                      : Icons.play_arrow_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: progress,
              backgroundColor: SaathiBeige.accent.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation<Color>(
                SaathiBeige.accentDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final title = widget.type == 'person'
        ? 'Memories for ${widget.value}'
        : 'Memories: ${widget.value}';
    return Scaffold(
      backgroundColor: SaathiBeige.cream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: SaathiBeige.charcoal,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Family Memories'),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: SaathiBeige.backgroundGradient),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1.5),
          child: Divider(
            height: 1.5,
            thickness: 1.5,
            color: SaathiBeige.accentDeep,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: SaathiBeige.backgroundGradient,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 20),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SaathiBeige.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : _memories.isEmpty
              ? Center(
                  child: Text(
                    'No memories found',
                    style: TextStyle(
                      color: SaathiBeige.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: SaathiBeige.charcoal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'All recordings (${_memories.length})',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SaathiBeige.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _memories.length,
                        itemBuilder: (context, index) {
                          return _audioTile(index, _memories[index]);
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
