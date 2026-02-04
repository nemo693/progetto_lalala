import 'package:flutter/material.dart';
import 'screens/map_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
