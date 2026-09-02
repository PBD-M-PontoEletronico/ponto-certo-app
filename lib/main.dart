import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const MeuPontoApp());
}

class MeuPontoApp extends StatelessWidget {
  const MeuPontoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PontoCerto',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}