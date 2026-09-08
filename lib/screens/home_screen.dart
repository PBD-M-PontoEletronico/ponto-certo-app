import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../services/database_helper.dart';
import 'login_screen.dart';
import '../widgets/offline_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final SyncService _syncService = SyncService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  String? _nome;
  String? _setorNome;
  DateTime? _ultimaSincronizacao;
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _carregarDadosLocais();
  }

  Future<void> _carregarDadosLocais() async {
    final nome = await _authService.getNome();
    final setor = await _dbHelper.getSetor();
    final ultimaSync = await _dbHelper.getUltimaSincronizacao();

    if (mounted) {
      setState(() {
        _nome = nome;
        _setorNome = setor != null ? setor['nome'] as String : null;
        _ultimaSincronizacao = ultimaSync;
      });
    }
  }

  Future<void> _atualizarAgora() async {
    setState(() => _sincronizando = true);

    final sucesso = await _syncService.sincronizar();

    if (!mounted) return;

    setState(() => _sincronizando = false);

    if (sucesso) {
      await _carregarDadosLocais();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados atualizados com sucesso.')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível atualizar. Verifique sua conexão.'),
          ),
        );
      }
    }
  }

  String _formatarDataHora(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');
    return '$dia/$mes às $hora:$minuto';
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
      // Apaga todos os dados locais (funcionário, setor, escala,
      // marcações, política) junto com a sessão, conforme exigido
      // pela APP 02.
      await _dbHelper.limparTudo();
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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _nome != null ? 'Olá, $_nome!' : 'Olá!',
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 4),
                    if (_setorNome != null)
                      Text(
                        'Setor: $_setorNome',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tela de ponto — em construção (APP 03)',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _ultimaSincronizacao != null
                          ? 'Última atualização: ${_formatarDataHora(_ultimaSincronizacao!)}'
                          : 'Nunca sincronizado',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _sincronizando ? null : _atualizarAgora,
                      icon: _sincronizando
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.refresh),
                      label: Text(
                        _sincronizando ? 'Atualizando...' : 'Atualizar agora',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}