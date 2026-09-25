import 'package:flutter/material.dart';

import 'voice_screen.dart';

void main() {
  runApp(const ThinkShiftApp());
}

class ThinkShiftApp extends StatelessWidget {
  const ThinkShiftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThinkShift',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const VoiceScreen(),
    );
  }
}
