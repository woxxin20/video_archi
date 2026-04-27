import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../config.dart';
import '../providers/virtual_help_provider.dart';
import 'video_card_widget.dart';
import 'offline_widget.dart';

/// Main feed screen showing category tabs and video cards.
/// Implements the rendering flow from Section 14.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  String _selectedCategory = VirtualHelpConfig.validCategories.first;

  late final VirtualHelpProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<VirtualHelpProvider>();
    // Listen for connectivity changes (Section 23)
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
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (provider.currentCatalog == null) {
          return OfflineWidget(onRetry: () => provider.retry());
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(provider.currentMode == 'period'
                ? 'Period Care'
                : 'Pregnancy Care'),
            actions: [
              // Mode switch button
              IconButton(
                icon: Icon(provider.currentMode == 'period'
                    ? Icons.pregnant_woman
                    : Icons.favorite),
                tooltip: provider.currentMode == 'period'
                    ? 'Switch to Pregnancy'
                    : 'Switch to Period',
                onPressed: () {
                  final newMode = provider.currentMode == 'period'
                      ? 'pregnancy'
                      : 'period';
                  provider.switchMode(newMode);
                },
              ),
              // Language selector
              PopupMenuButton<String>(
                icon: const Icon(Icons.language),
                tooltip: 'Change Language',
                onSelected: (lang) => provider.changeLanguage(lang),
                itemBuilder: (context) {
                  return VirtualHelpConfig.supportedLanguages
                      .map((lang) => PopupMenuItem(
                            value: lang,
                            child: Text(
                              lang.toUpperCase(),
                              style: TextStyle(
                                fontWeight: lang == provider.currentLang
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ))
                      .toList();
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // ─── Category Pills ───
              _buildCategoryPills(provider),

              // ─── Video Feed ───
              Expanded(
                child: _buildVideoFeed(provider),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryPills(VirtualHelpProvider provider) {
    final categories = provider.currentCategories;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: categories.map((cat) {
          final isSelected = cat == _selectedCategory;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(cat[0].toUpperCase() + cat.substring(1)),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _selectedCategory = cat);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVideoFeed(VirtualHelpProvider provider) {
    final slots = provider.getFeedForCategory(_selectedCategory);

    if (slots.isEmpty) {
      return const Center(child: Text('No videos available.'));
    }

    return SizedBox(
      height: 320, // Height for the horizontal strip
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: slots.length,
        itemBuilder: (context, index) {
          final slot = slots[index];
          return SizedBox(
            width: 300, // Fixed width for cards in horizontal list
            child: VideoCardWidget(
              video: slot.video,
              isRewatch: slot.isRewatch,
              category: _selectedCategory,
            ),
          );
        },
      ),
    );
  }
}
