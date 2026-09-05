import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _decidirRota();
  }

  Future<void> _decidirRota() async {
    // Pequeno delay só pra dar tempo da splash aparecer (evita "flash" na tela)
    await Future.delayed(const Duration(milliseconds: 600));

    final temSessao = await _authService.hasSession();

    if (!mounted) return;

    if (temSessao) {
      // Já logado antes — pula direto pro ponto, mesmo offline
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time_filled, size: 72),
            SizedBox(height: 16),
            Text(
              'PontoCerto',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}