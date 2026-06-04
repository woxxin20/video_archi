import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../config.dart';
import '../models/feed_entry.dart';
import '../providers/virtual_help_provider.dart';
import 'video_card_widget.dart';
import 'video_player_screen.dart';
import 'offline_widget.dart';
import 'virtual_help_theme.dart';

/// Virtual Help feed — section header, category pills, horizontal video strip.
/// Matches the Virtual Help.html design pixel-precisely.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  /// 'all' or one of [VirtualHelpConfig.validCategories].
  String _selectedCategory = 'all';

  late final VirtualHelpProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<VirtualHelpProvider>();
    Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) _provider.updateConnectivity(results);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VirtualHelpProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Scaffold(
            backgroundColor: VirtualHelpTheme.bgWarm,
            body: Center(
              child: CircularProgressIndicator(color: VirtualHelpTheme.brand),
            ),
          );
        }

        if (provider.currentCatalog == null) {
          return OfflineWidget(
            onRetry: () => provider.retry(),
            errorMessage: provider.errorMessage,
          );
        }

        return Scaffold(
          backgroundColor: VirtualHelpTheme.bgWarm,
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // ── Greeting ────────────────────────────────────────────
                    _GreetingHeader(provider: provider),

                    const SizedBox(height: 12),

                    // ── Hero card ────────────────────────────────────────────
                    _HeroCard(provider: provider),

                    const SizedBox(height: 6),

                    // ── Virtual Help section ─────────────────────────────────
                    _VirtualHelpSection(
                      provider: provider,
                      selectedCategory: _selectedCategory,
                      onCategoryChanged: (cat) =>
                          setState(() => _selectedCategory = cat),
                    ),

                    const SizedBox(height: 36),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Greeting header ──────────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  final VirtualHelpProvider provider;
  const _GreetingHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    final modeLabel = provider.currentMode == 'pregnancy'
        ? 'Pregnancy'
        : 'Period';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Good morning',
          style: VirtualHelpTheme.sans(
            size: 11.5,
            weight: FontWeight.w500,
            color: VirtualHelpTheme.textMuted,
            letterSpacing: 0.08,
          ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: modeLabel,
                style: VirtualHelpTheme.serif(
                  size: 24,
                  weight: FontWeight.w200,
                  color: VirtualHelpTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: ' Care',
                style: VirtualHelpTheme.serif(
                  size: 24,
                  weight: FontWeight.w200,
                  color: VirtualHelpTheme.brand,
                  italic: true,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Hero card ────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final VirtualHelpProvider provider;
  const _HeroCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final mode = provider.currentMode;
    final modeLabel = mode == 'pregnancy' ? 'Pregnancy' : 'Period';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.7, -1),
          end: Alignment(0.7, 1),
          colors: [Color(0xFFFF9F5A), Color(0xFFE87A2E)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  modeLabel,
                  style: VirtualHelpTheme.sans(
                    size: 10,
                    weight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.92),
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'Virtual Help',
                    style: VirtualHelpTheme.serif(
                      size: 24,
                      weight: FontWeight.w200,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'videos',
                    style: VirtualHelpTheme.sans(
                      size: 9.5,
                      weight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.62),
                      letterSpacing: 0.06,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Body row
          Row(
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Opacity(
                  opacity: 0.45,
                  child: Icon(
                    mode == 'pregnancy' ? Icons.child_care : Icons.favorite,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modeLabel,
                      style: VirtualHelpTheme.serif(
                        size: 48,
                        weight: FontWeight.w200,
                        color: Colors.white,
                        letterSpacing: -3,
                      ),
                    ),
                    Text(
                      'CARE',
                      style: VirtualHelpTheme.sans(
                        size: 8,
                        weight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.58),
                        letterSpacing: 0.22,
                      ),
                    ),
                    Container(
                      width: 32,
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 7),
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    Text(
                      'Personalized video guidance',
                      style: VirtualHelpTheme.serif(
                        size: 13,
                        weight: FontWeight.w300,
                        color: Colors.white.withValues(alpha: 0.92),
                        italic: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${VirtualHelpConfig.validCategories.length} categories',
                      style: VirtualHelpTheme.sans(
                        size: 8.5,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Virtual Help section (header + pills + video strip) ───────────────

class _VirtualHelpSection extends StatelessWidget {
  final VirtualHelpProvider provider;
  final String selectedCategory;
  final ValueChanged<String> onCategoryChanged;

  const _VirtualHelpSection({
    required this.provider,
    required this.selectedCategory,
    required this.onCategoryChanged,
  });

  List<_CategoryOption> get _options {
    final serverCats = provider.currentCategories;
    return [
      _CategoryOption('all', 'All', Colors.transparent),
      ...serverCats.map(
        (cat) => _CategoryOption(
          cat,
          VirtualHelpTheme.categoryLabel[cat] ?? cat,
          VirtualHelpTheme.categoryAccent[cat] ?? VirtualHelpTheme.brand,
        ),
      ),
    ];
  }

  /// Flat list of EVERY video shown today across every category.
  /// Order: by category in catalog order, slot-by-slot.
  /// Used when the user taps any card — the player shows them all and
  /// opens on the tapped one (Instagram-Reels style).
  List<_SlottedVideo> _allTodayVideos() {
    final result = <_SlottedVideo>[];
    for (final cat in provider.currentCategories) {
      final slots = provider.getFeedForCategory(cat);
      for (int i = 0; i < slots.length; i++) {
        result.add(_SlottedVideo(
          slot: slots[i],
          category: cat,
          isToday: i == 0 && !slots[i].isRewatch,
        ));
      }
    }
    return result;
  }

  /// What the horizontal strip in the feed actually renders.
  /// Subset of [_allTodayVideos] filtered by the selected category pill.
  List<_SlottedVideo> _visibleSlots() {
    final all = _allTodayVideos();
    if (selectedCategory == 'all') return all;
    return all.where((sv) => sv.category == selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    final slots = _visibleSlots();
    final allToday = _allTodayVideos();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: VirtualHelpTheme.brandXs,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: VirtualHelpTheme.brand,
                      size: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  'Virtual Help',
                  style: VirtualHelpTheme.sans(
                    size: 13,
                    weight: FontWeight.w700,
                    color: VirtualHelpTheme.textPrimary,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: VirtualHelpTheme.brand,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'TODAY',
                    style: VirtualHelpTheme.sans(
                      size: 8,
                      weight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.06,
                    ),
                  ),
                ),
              ],
            ),
            // Mode + language switcher
            Row(
              children: [
                _HeaderAction(
                  icon: Icons.language,
                  onTap: () => _showLanguagePicker(context, provider),
                ),
                const SizedBox(width: 8),
                _HeaderAction(
                  icon: provider.currentMode == 'period'
                      ? Icons.pregnant_woman
                      : Icons.favorite_border,
                  onTap: () {
                    final newMode = provider.currentMode == 'period'
                        ? 'pregnancy'
                        : 'period';
                    provider.switchMode(newMode);
                  },
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Category pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: _options.map((opt) {
              final isSelected = selectedCategory == opt.key;
              return Padding(
                padding: const EdgeInsets.only(right: 7),
                child: GestureDetector(
                  onTap: () => onCategoryChanged(opt.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? VirtualHelpTheme.brand
                          : VirtualHelpTheme.bgMuted,
                      border: Border.all(
                        color: isSelected
                            ? VirtualHelpTheme.brand
                            : VirtualHelpTheme.border,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      opt.label,
                      style: VirtualHelpTheme.sans(
                        size: 10,
                        weight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : VirtualHelpTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),

        // Video strip
        if (slots.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No videos available.',
                style: VirtualHelpTheme.sans(color: VirtualHelpTheme.textMuted),
              ),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: slots.map((sv) {
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: VideoCardWidget(
                    video: sv.slot.video,
                    isRewatch: sv.slot.isRewatch,
                    category: sv.category,
                    isToday: sv.isToday,
                    onTap: () => _openReels(context, allToday, sv),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  /// Push the full-screen reels player with EVERY today's video, opening on
  /// the one the user tapped — Instagram-Reels style cross-category swipe.
  void _openReels(
    BuildContext context,
    List<_SlottedVideo> allToday,
    _SlottedVideo tapped,
  ) {
    if (allToday.isEmpty) return;
    final entries = [
      for (final sv in allToday)
        FeedEntry(
          video: sv.slot.video,
          category: sv.category,
          isRewatch: sv.slot.isRewatch,
        ),
    ];
    var initialIndex = allToday.indexWhere(
      (sv) =>
          sv.slot.video.id == tapped.slot.video.id &&
          sv.category == tapped.category,
    );
    if (initialIndex < 0) initialIndex = 0;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          entries: entries,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, VirtualHelpProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: VirtualHelpConfig.supportedLanguages.map((lang) {
          final isCurrent = lang == provider.currentLang;
          return ListTile(
            title: Text(lang.toUpperCase()),
            trailing: isCurrent
                ? const Icon(Icons.check, color: VirtualHelpTheme.brand)
                : null,
            onTap: () {
              provider.changeLanguage(lang);
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }
}

class _CategoryOption {
  final String key;
  final String label;
  final Color accent;
  const _CategoryOption(this.key, this.label, this.accent);
}

class _SlottedVideo {
  final FeedSlot slot;
  final String category;
  final bool isToday;
  const _SlottedVideo({
    required this.slot,
    required this.category,
    required this.isToday,
  });
}

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: VirtualHelpTheme.bgMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: VirtualHelpTheme.border),
        ),
        child: Icon(icon, size: 15, color: VirtualHelpTheme.textSecondary),
      ),
    );
  }
}
