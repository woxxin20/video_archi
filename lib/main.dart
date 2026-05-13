import 'package:flutter/material.dart';
import 'virtual_help/virtual_help.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure server URL (change this to your production server)
  // For Android emulator: 'http://10.0.2.2:8080'
  // For iOS simulator: 'http://localhost:8080'
  // For physical device: 'http://<your-ip>:8080'
  VirtualHelpConfig.serverBaseUrl = 'http://localhost:8080';
  // VirtualHelpConfig.serverBaseUrl = 'http://10.0.2.2:8080';

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
