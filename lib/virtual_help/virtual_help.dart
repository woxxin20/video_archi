/// Virtual Help — Independent Video Architecture Module
///
/// A completely self-contained module implementing the Virtual Help
/// video catalog architecture. Can be dropped into any Flutter project.
///
/// ## Quick Start
/// ```dart
/// import 'package:your_app/virtual_help/virtual_help.dart';
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   VirtualHelpConfig.serverBaseUrl = 'http://your-server.com';
///   await VirtualHelp.ensureInitialized();
///   runApp(VirtualHelp.wrapWithProviders(child: YourApp()));
/// }
/// ```


import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import 'database/database_service.dart';
import 'providers/virtual_help_provider.dart';

// ─── Public exports ───
export 'config.dart';
export 'models/video_item.dart';
export 'models/catalog_response.dart';
export 'models/category_state.dart';
export 'providers/virtual_help_provider.dart';
export 'ui/feed_screen.dart';
export 'ui/video_card_widget.dart';
export 'ui/video_player_screen.dart';
export 'ui/offline_widget.dart';
export 'services/shuffle_service.dart';
export 'services/api_service.dart';

/// Entry point for the Virtual Help module.
class VirtualHelp {
  VirtualHelp._();

  /// Initialize the database layer. Call once before using providers.
  static Future<void> ensureInitialized() async {
    await DatabaseService.instance.initialize();
  }

  /// Wraps a widget tree with the required VirtualHelp providers.
  /// Use this at the top of your widget tree.
  static Widget wrapWithProviders({required Widget child}) {
    return ChangeNotifierProvider<VirtualHelpProvider>(
      create: (_) => VirtualHelpProvider()..initialize(),
      child: child,
    );
  }
}
