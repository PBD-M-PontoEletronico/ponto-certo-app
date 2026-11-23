import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'relogio_screen.dart';

/// Decide a primeira tela depois do login: conta de setor vira relogio de
/// ponto (APP 08); as demais vao para a Home do funcionario.
class PortaDeEntrada extends StatefulWidget {
  const PortaDeEntrada({super.key});

  @override
  State<PortaDeEntrada> createState() => _PortaDeEntradaState();
}

class _PortaDeEntradaState extends State<PortaDeEntrada> {
  bool? _relogio;

  @override
  void initState() {
    super.initState();
    AuthService().ehRelogio().then((v) {
      if (mounted) setState(() => _relogio = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final relogio = _relogio;
    if (relogio == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return relogio ? const RelogioScreen() : const HomeScreen();
  }
}
