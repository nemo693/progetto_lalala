import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'screens/map_screen.dart';
import 'services/offline_manager.dart';

/// Global singleton for offline tile management.
/// Initialized before runApp() so it's available everywhere.
final offlineManager = OfflineManager();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  await offlineManager.initialize();
  runApp(const AlpineNavApp());
}

class AlpineNavApp extends StatelessWidget {
  const AlpineNavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlpineNav',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Muted, functional theme — no Material "floating" aesthetic
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B9DAF),
          surface: Color(0xFF1A1A2E),
        ),
        useMaterial3: true,
        fontFamily: 'monospace',
      ),
      home: const MapScreen(),
    );
  }
}
