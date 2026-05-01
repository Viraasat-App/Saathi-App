import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_storage.dart';
import '../services/family_insights_service.dart';
import '../theme/saathi_beige_theme.dart';
import '../widgets/floating_voice_nav_bar.dart';
import 'history_screen.dart';
import 'family_memories_screen.dart';
import 'settings_screen.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  static const String _aiAccuracyDisclaimer =
      'AI responses may not always be accurate.';
  bool _loading = true;
  String? _error;
  List<String> _topPeople = const <String>[];
  List<String> _topEmotions = const <String>[];
  String _resolvedUserId = '999990';
  String? _openingKey;

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
    final userId = (await AuthStorage.instance.currentUserId())?.trim();
    final resolvedUserId = (userId == null || userId.isEmpty)
        ? '999990'
        : userId;
    _resolvedUserId = resolvedUserId;

    final result = await FamilyInsightsService.instance.fetchInsights(
      userId: resolvedUserId,
    );
    if (!mounted) return;

    switch (result) {
      case FamilyInsightsSuccess(:final topPeople, :final topEmotions):
        setState(() {
          _loading = false;
          _error = null;
          _topPeople = topPeople;
          _topEmotions = topEmotions;
        });
      case FamilyInsightsFailure(:final message):
        setState(() {
          _loading = false;
          _error = message;
          _topPeople = const <String>[];
          _topEmotions = const <String>[];
        });
    }
  }

  static Widget _sectionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: SaathiBeige.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _insightChipWrapTyped({
    required List<String> items,
    required String type,
  }) {
    if (items.isEmpty) {
      return Text(
        'No insights available',
        style: TextStyle(
          color: SaathiBeige.muted,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item),
                  if (_openingKey == '$type::$item') ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
              selected: false,
              onSelected: (_) =>
                  unawaited(_openMemories(type: type, value: item)),
            ),
          )
          .toList(),
    );
  }

  Future<void> _openMemories({
    required String type,
    required String value,
  }) async {
    final key = '$type::$value';
    setState(() => _openingKey = key);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FamilyMemoriesScreen(
            userId: _resolvedUserId,
            type: type,
            value: value,
          ),
        ),
      );
    } finally {
      if (mounted && _openingKey == key) {
        setState(() => _openingKey = null);
      }
    }
  }

  String _countSubtitle(String noun, int count) {
    final label = count == 1 ? noun : '${noun}s';
    return '$count $label';
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: SaathiBeige.muted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              unawaited(_loadFamilyInsights());
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _insightsContent(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Family insights',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: SaathiBeige.charcoal,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Top people and emotions from recent conversations',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: SaathiBeige.muted),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            context: context,
            icon: Icons.group_rounded,
            title: 'People',
            subtitle: _countSubtitle('person', _topPeople.length),
            child: _insightChipWrapTyped(items: _topPeople, type: 'person'),
          ),
          _sectionCard(
            context: context,
            icon: Icons.sentiment_satisfied_alt_rounded,
            title: 'Emotions',
            subtitle: _countSubtitle('emotion', _topEmotions.length),
            child: _insightChipWrapTyped(items: _topEmotions, type: 'emotion'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaathiBeige.cream,
      extendBody: true,
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
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1.5),
          child: Divider(
            height: 1.5,
            thickness: 1.5,
            color: SaathiBeige.accentDeep,
          ),
        ),
      ),
      body: ColoredBox(
        color: SaathiBeige.cream,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _errorView()
              : _insightsContent(context),
        ),
      ),
      bottomNavigationBar: ColoredBox(
        color: SaathiBeige.cream,
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FloatingVoiceNavBar(
                  currentIndex: 2,
                  onSelect: (i) => unawaited(_onBottomNavTap(context, i)),
                ),
                const SizedBox(height: 6),
                Text(
                  _aiAccuracyDisclaimer,
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
      ),
    );
  }
}
