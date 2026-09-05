import 'package:flutter/material.dart';
import '../services/conectivity_service.dart';

/// Banner fixo no topo da tela avisando que o app está sem internet.
/// Não bloqueia o uso — é só um indicador visual.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  final ConnectivityService _connectivityService = ConnectivityService();
  bool _online = true;

  @override
  void initState() {
    super.initState();
    _verificarStatusInicial();
    _connectivityService.onConnectivityChanged().listen((online) {
      if (mounted) {
        setState(() => _online = online);
      }
    });
  }

  Future<void> _verificarStatusInicial() async {
    final online = await _connectivityService.isOnline();
    if (mounted) {
      setState(() => _online = online);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_online) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Colors.orange.shade700,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            'Você está offline. Os dados serão sincronizados quando a conexão voltar.',
            style: TextStyle(color: Colors.white, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}