import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import '../widgets/offline_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  String? _nome;

  @override
  void initState() {
    super.initState();
    _carregarNome();
  }

  Future<void> _carregarNome() async {
    final nome = await _authService.getNome();
    if (mounted) {
      setState(() => _nome = nome);
    }
  }

  Future<void> _confirmarLogout() async {
    // 🔧 TAPA-BURACO PARA DEMONSTRAÇÃO — remover quando a fila real
    // de marcações (APP 07 / sqflite) existir. Por enquanto simula
    // que existem 2 marcações pendentes de envio.
    const int marcacoesPendentesMock = 2;

    final temPendencias = marcacoesPendentesMock > 0;
    final mensagem = temPendencias
        ? 'Você tem $marcacoesPendentesMock marcação(ões) que ainda não foram '
        'enviadas ao servidor. Elas serão enviadas assim que você logar '
        'novamente com internet. Deseja mesmo sair?'
        : 'Tem certeza que deseja sair da sua conta?';

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair'),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirmou == true) {
      await _authService.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PontoCerto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _confirmarLogout,
            tooltip: 'Sair',
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _nome != null ? 'Olá, $_nome!' : 'Olá!',
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tela de ponto — em construção (APP 03)',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}