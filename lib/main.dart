import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

// Permite navegar (ex: forçar logout) de qualquer lugar do app,
// mesmo fora de uma tela, como dentro de um service.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const MeuPontoApp());
}

class MeuPontoApp extends StatelessWidget {
  const MeuPontoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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