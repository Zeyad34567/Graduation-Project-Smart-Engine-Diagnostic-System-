import 'package:flutter/material.dart';

// Screens (تأكد إن الملفات موجودة فعلاً)
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const EngineFaultAI());
}

class EngineFaultAI extends StatelessWidget {
  const EngineFaultAI({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'Engine Fault AI',

      theme: AppTheme.darkTheme,

      home: const SplashScreen(),
    );
  }
}