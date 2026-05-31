import 'package:flutter/material.dart';

import 'home_page.dart';

void main() {
  runApp(const ChartExampleApp());
}

class ChartExampleApp extends StatelessWidget {
  const ChartExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_native_charts',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7CFFB2),
          brightness: Brightness.dark,
          surface: const Color(0xFF0B0E14),
        ),
      ),
      home: const HomePage(),
    );
  }
}
