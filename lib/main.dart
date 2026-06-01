import 'package:flutter/material.dart';
import 'virtual_help/virtual_help.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Production server (LAN host running the Dart catalog server).
  // CDN (videos / HLS segments) is hosted separately at http://192.168.1.57/videos/.
  // Override per environment:
  //   const String.fromEnvironment('VH_SERVER_URL') → --dart-define=VH_SERVER_URL=...
  const overrideUrl = String.fromEnvironment('VH_SERVER_URL');
  VirtualHelpConfig.serverBaseUrl =
      overrideUrl.isNotEmpty ? overrideUrl : 'http://192.168.1.57:8080';

  // Initialize database
  await VirtualHelp.ensureInitialized();

  runApp(VirtualHelp.wrapWithProviders(child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Virtual Help',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const FeedScreen(),
    );
  }
}
