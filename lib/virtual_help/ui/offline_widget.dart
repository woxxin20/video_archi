import 'package:flutter/material.dart';

import '../config.dart';
import 'virtual_help_theme.dart';

/// Shown when the app cannot load a catalog (offline or server unreachable).
///
/// Surfaces the *actual* failure reason from `VirtualHelpProvider.errorMessage`
/// so the user (or developer) can tell whether it's a network issue, a wrong
/// server URL, a parse error, or anything else.
class OfflineWidget extends StatelessWidget {
  final VoidCallback onRetry;
  final String? errorMessage;

  const OfflineWidget({
    super.key,
    required this.onRetry,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VirtualHelpTheme.bgWarm,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 64,
                  color: VirtualHelpTheme.brand,
                ),
                const SizedBox(height: 24),
                Text(
                  'Unable to load content',
                  textAlign: TextAlign.center,
                  style: VirtualHelpTheme.serif(
                    size: 22,
                    weight: FontWeight.w300,
                    color: VirtualHelpTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  errorMessage ?? 'Connect to internet to load your content.',
                  textAlign: TextAlign.center,
                  style: VirtualHelpTheme.sans(
                    size: 13,
                    color: VirtualHelpTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: VirtualHelpTheme.bgMuted,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server URL',
                        style: VirtualHelpTheme.sans(
                          size: 9,
                          weight: FontWeight.w700,
                          color: VirtualHelpTheme.textMuted,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        VirtualHelpConfig.serverBaseUrl,
                        style: VirtualHelpTheme.sans(
                          size: 11,
                          weight: FontWeight.w600,
                          color: VirtualHelpTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VirtualHelpTheme.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
