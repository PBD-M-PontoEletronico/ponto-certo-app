import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();
  final SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    _decidirRota();
  }

  Future<void> _decidirRota() async {
    final temSessao = await _authService.hasSession();

    if (temSessao) {
      // Já logado antes: tenta sincronizar (se tiver internet), mas
      // segue para a Home de qualquer forma, mesmo offline ou se
      // a sincronização falhar — usando os dados já salvos localmente.
      await _syncService.sincronizar();
    } else {
      // Delay só pra dar tempo da splash aparecer antes do login
      await Future.delayed(const Duration(milliseconds: 600));
    }

    if (!mounted) return;

    if (temSessao) {
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