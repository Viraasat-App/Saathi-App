import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import '../services/auth_storage.dart';
import '../theme/saathi_beige_theme.dart';
import '../widgets/floating_voice_nav_bar.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  static const String _familyInsightsEndpoint =
      'https://d4pso873k9.execute-api.ap-south-1.amazonaws.com/getFamilyInsights';
  static const String _memoriesEndpoint =
      'https://vjn4mbb7xi.execute-api.ap-south-1.amazonaws.com/getMemories';

  bool _isLoadingInsights = true;
  String? _insightsError;
  List<String> _topEmotions = const <String>[];
  List<String> _topPeople = const <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadFamilyInsights());
  }

  Future<void> _onBottomNavTap(BuildContext context, int index) async {
    if (index == 0) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (index == 1) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
      );
      return;
    }
    if (index == 2) {
      return;
    }
    if (index == 3) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
      );
      return;
    }
    if (index == 4) {
      await Navigator.of(context).pushNamed('/profile');
      return;
    }
  }

  Future<void> _loadFamilyInsights() async {
    setState(() {
      _isLoadingInsights = true;
      _insightsError = null;
    });

    try {
      final userId = await AuthStorage.instance.currentUserId();
      if (userId == null || userId.isEmpty) {
        throw Exception('User ID not found. Please login again.');
      }

      final response = await http
          .post(
            Uri.parse(_familyInsightsEndpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Failed to load family insights (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Unexpected response format.');
      }

      final emotionsRaw = decoded['top_emotions'];
      final peopleRaw = decoded['top_people'];

      final emotions = emotionsRaw is List
          ? emotionsRaw
                .whereType<dynamic>()
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList(growable: false)
          : const <String>[];
      final people = peopleRaw is List
          ? peopleRaw
                .whereType<dynamic>()
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList(growable: false)
          : const <String>[];

      if (!mounted) return;
      setState(() {
        _topEmotions = emotions;
        _topPeople = people;
        _isLoadingInsights = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _insightsError = e.toString();
        _isLoadingInsights = false;
      });
    }
  }

  Future<void> _onPersonButtonTap(String name) async {
    final userId = await AuthStorage.instance.currentUserId();
    if (!mounted) return;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User ID not found. Please login again.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FamilyMemoriesScreen(
          endpoint: _memoriesEndpoint,
          userId: userId,
          selectedPerson: name,
          queryType: 'person',
        ),
      ),
    );
  }

  Future<void> _onEmotionButtonTap(String emotion) async {
    final userId = await AuthStorage.instance.currentUserId();
    if (!mounted) return;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User ID not found. Please login again.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FamilyMemoriesScreen(
          endpoint: _memoriesEndpoint,
          userId: userId,
          selectedPerson: emotion,
          queryType: 'emotion',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: SaathiBeige.cream,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: SaathiBeige.charcoal,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Family'),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: SaathiBeige.backgroundGradient),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: SaathiBeige.accent.withValues(alpha: 0.2),
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: SaathiBeige.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _isLoadingInsights
                    ? const Center(child: CircularProgressIndicator())
                    : _insightsError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Could not load family insights.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _insightsError!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton(
                              onPressed: _loadFamilyInsights,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InsightSection(
                              icon: Icons.people_alt_rounded,
                              title: 'People',
                              subtitle: 'Tap a person to explore memories',
                              child: _topPeople.isEmpty
                                  ? Text(
                                      'No people insights available yet.',
                                      style: Theme.of(context).textTheme.bodyMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    )
                                  : Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: _topPeople
                                          .map(
                                            (name) => _FamilyChip(
                                              label: name,
                                              onPressed: () => unawaited(
                                                _onPersonButtonTap(name),
                                              ),
                                            ),
                                          )
                                          .toList(growable: false),
                                    ),
                            ),
                            const SizedBox(height: 14),
                            _InsightSection(
                              icon: Icons.favorite_rounded,
                              title: 'Emotions',
                              subtitle: 'Tap an emotion to explore memories',
                              child: _topEmotions.isEmpty
                                  ? Text(
                                      'No emotion insights available yet.',
                                      style: Theme.of(context).textTheme.bodyMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    )
                                  : Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: _topEmotions
                                          .map(
                                            (emotion) => _FamilyChip(
                                              label: emotion,
                                              onPressed: () => unawaited(
                                                _onEmotionButtonTap(emotion),
                                              ),
                                            ),
                                          )
                                          .toList(growable: false),
                                    ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FloatingVoiceNavBar(
            currentIndex: 2,
            onSelect: (i) => unawaited(_onBottomNavTap(context, i)),
          ),
        ),
      ),
    );
  }
}

class _InsightSection extends StatelessWidget {
  const _InsightSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: SaathiBeige.surfaceElevated.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SaathiBeige.accent.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: SaathiBeige.charcoal.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SaathiBeige.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: SaathiBeige.accentDeep, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: SaathiBeige.charcoal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaathiBeige.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'SELECT',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: SaathiBeige.muted,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _FamilyChip extends StatelessWidget {
  const _FamilyChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      label: Text(label),
      onPressed: onPressed,
      backgroundColor: scheme.surface,
      side: BorderSide(color: Colors.black.withValues(alpha: 0.65), width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class FamilyMemoriesScreen extends StatefulWidget {
  const FamilyMemoriesScreen({
    super.key,
    required this.endpoint,
    required this.userId,
    required this.selectedPerson,
    required this.queryType,
  });

  final String endpoint;
  final String userId;
  final String selectedPerson;
  final String queryType;

  @override
  State<FamilyMemoriesScreen> createState() => _FamilyMemoriesScreenState();
}

class _FamilyMemoriesScreenState extends State<FamilyMemoriesScreen> {
  final AudioPlayer _player = AudioPlayer();
  final Map<String, Duration> _memoryDurations = <String, Duration>{};

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool _isLoading = true;
  String? _error;
  List<_MemoryItem> _memories = const <_MemoryItem>[];
  String? _activeMemoryId;
  Duration _activePosition = Duration.zero;
  Duration _activeDuration = Duration.zero;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.positionStream.listen((position) {
      if (!mounted || _activeMemoryId == null) return;
      setState(() => _activePosition = position);
    });
    _stateSub = _player.playerStateStream.listen((state) async {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        await _player.stop();
        if (!mounted) return;
        setState(() {
          _activeMemoryId = null;
          _activePosition = Duration.zero;
          _activeDuration = Duration.zero;
          _isPaused = false;
        });
      }
    });
    unawaited(_loadMemories());
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadMemories() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse(widget.endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': widget.userId,
              'type': widget.queryType,
              'value': widget.selectedPerson,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Request failed (${response.statusCode}).');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Unexpected response format.');
      }
      final rawMemories = decoded['memories'];
      if (rawMemories is! List) {
        throw Exception('No memories found.');
      }

      final memories = rawMemories
          .whereType<Map>()
          .map((m) => _MemoryItem.fromMap(Map<String, dynamic>.from(m)))
          .where((m) => m.memoryId.isNotEmpty && m.audioUrl.isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _memories = memories;
        _isLoading = false;
      });
      unawaited(_probeDurations(memories));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _probeDurations(List<_MemoryItem> memories) async {
    for (final memory in memories) {
      if (_memoryDurations.containsKey(memory.memoryId)) continue;
      try {
        final probe = AudioPlayer();
        await probe.setUrl(memory.audioUrl);
        final d = probe.duration;
        await probe.dispose();
        if (d == null || !mounted) continue;
        setState(() {
          _memoryDurations[memory.memoryId] = d;
        });
      } catch (_) {}
    }
  }

  Future<void> _togglePlayback(_MemoryItem memory) async {
    final isActive = _activeMemoryId == memory.memoryId;
    if (isActive) {
      if (_isPaused) {
        await _player.play();
        if (!mounted) return;
        setState(() => _isPaused = false);
      } else {
        await _player.pause();
        if (!mounted) return;
        setState(() => _isPaused = true);
      }
      return;
    }

    try {
      await _player.stop();
      await _player.setUrl(memory.audioUrl);
      final d = _player.duration ?? Duration.zero;
      if (!mounted) return;
      setState(() {
        _activeMemoryId = memory.memoryId;
        _activePosition = Duration.zero;
        _activeDuration = d;
        _isPaused = false;
        if (d > Duration.zero) {
          _memoryDurations[memory.memoryId] = d;
        }
      });
      await _player.play();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to play this memory audio.')),
      );
    }
  }

  double _progressFor(String memoryId) {
    if (_activeMemoryId != memoryId || _activeDuration.inMilliseconds <= 0) {
      return 0;
    }
    final ratio =
        _activePosition.inMilliseconds / _activeDuration.inMilliseconds;
    return ratio.clamp(0, 1).toDouble();
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _currentAndTotalFor(String memoryId, Duration totalDuration) {
    if (totalDuration <= Duration.zero) return '--:-- / --:--';
    if (_activeMemoryId != memoryId) {
      return '0:00 / ${_formatDuration(totalDuration)}';
    }
    return '${_formatDuration(_activePosition)} / ${_formatDuration(totalDuration)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: SaathiBeige.cream,
      appBar: AppBar(
        title: Text(widget.selectedPerson),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: SaathiBeige.charcoal,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: SaathiBeige.backgroundGradient),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: SaathiBeige.backgroundGradient),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Unable to load memories',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadMemories,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _memories.isEmpty
            ? Center(
                child: Text(
                  'No memories found for ${widget.selectedPerson}.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: SaathiBeige.muted),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                itemCount: _memories.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final memory = _memories[index];
                  final isActive = _activeMemoryId == memory.memoryId;
                  final duration = isActive
                      ? _activeDuration
                      : (_memoryDurations[memory.memoryId] ?? Duration.zero);
                  return Card(
                    elevation: 0,
                    color: scheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memory.summary,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: _progressFor(memory.memoryId),
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(99),
                            backgroundColor: scheme.outline.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => unawaited(
                                  _togglePlayback(memory),
                                ),
                                icon: Icon(
                                  isActive && !_isPaused
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                ),
                                iconSize: 36,
                              ),
                              const Spacer(),
                              Text(
                                _currentAndTotalFor(memory.memoryId, duration),
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _MemoryItem {
  const _MemoryItem({
    required this.memoryId,
    required this.summary,
    required this.audioUrl,
  });

  final String memoryId;
  final String summary;
  final String audioUrl;

  factory _MemoryItem.fromMap(Map<String, dynamic> map) {
    return _MemoryItem(
      memoryId: (map['memory_id'] ?? '').toString(),
      summary: (map['summary'] ?? '').toString(),
      audioUrl: (map['audio_url'] ?? '').toString(),
    );
  }
}

