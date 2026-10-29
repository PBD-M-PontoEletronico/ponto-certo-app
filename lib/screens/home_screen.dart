import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../services/database_helper.dart';
import '../utils/uuid.dart';
import 'login_screen.dart';
import '../widgets/offline_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Sequência fixa de marcações do dia (card A03).
  static const List<String> _sequenciaTipos = [
    'ENTRADA',
    'SAIDA_INTERVALO',
    'RETORNO_INTERVALO',
    'SAIDA',
  ];

  static const Map<String, String> _rotulos = {
    'ENTRADA': 'Entrada',
    'SAIDA_INTERVALO': 'Saída (intervalo)',
    'RETORNO_INTERVALO': 'Retorno (intervalo)',
    'SAIDA': 'Saída',
  };

  final AuthService _authService = AuthService();
  final SyncService _syncService = SyncService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _escalas = [];
  List<Map<String, dynamic>> _turnos = [];
  List<Map<String, dynamic>> _marcacoesHoje = [];

  String? _nome;
  List<String> _setoresNomes = [];
  DateTime? _ultimaSincronizacao;
  bool _sincronizando = false;
  bool _batendoPonto = false;

  // Desvio do relógio (APP 04). null = nunca conferiu com o servidor.
  int? _desvioMs;
  // Acima disso o app avisa. O card não define o número: combinar com o grupo.
  static const int _limiteDesvioMs = 5 * 60 * 1000; // 5 min

  @override
  void initState() {
    super.initState();
    _carregarDadosLocais();
  }

  Future<void> _carregarDadosLocais() async {
    final nome = await _authService.getNome();
    final setores = await _dbHelper.getSetores();
    final escalas = await _dbHelper.getEscalas();
    final turnos = await _dbHelper.getTurnos();
    final marcacoesHoje = await _dbHelper.getMarcacoesHoje();
    final ultimaSync = await _dbHelper.getUltimaSincronizacao();
    final desvio = await _dbHelper.getDesvioRelogioMs();

    if (mounted) {
      setState(() {
        _nome = nome;
        _setoresNomes = setores.map((s) => s['nome'] as String).toList();
        _escalas = escalas;
        _turnos = turnos;
        _marcacoesHoje = marcacoesHoje;
        _ultimaSincronizacao = ultimaSync;
        _desvioMs = desvio;
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

  String? get _proximoTipo {
    if (_marcacoesHoje.length >= _sequenciaTipos.length) return null;
    return _sequenciaTipos[_marcacoesHoje.length];
  }

  Future<void> _baterPonto() async {
    final tipo = _proximoTipo;
    if (tipo == null) return;

    // Instante do toque: é ESTE horário que é mostrado e gravado.
    final agora = DateTime.now();
    final desvio = _desvioMs;
    final aviso = _textoAvisoRelogio(desvio);

    // Evita bater duas vezes seguidas por engano — exige confirmação.
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar marcação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Registrar "${_rotulos[tipo]}"?'),
            const SizedBox(height: 8),
            Text(
              'Hora que será registrada: ${_formatarHorarioCompleto(agora)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (aviso != null) ...[
              const SizedBox(height: 8),
              Text(aviso, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    setState(() => _batendoPonto = true);

    // Grava no banco local ANTES de qualquer outra coisa. O envio ao
    // servidor é escopo da APP 07.
    final marcacao = {
      'id': gerarUuidV4(),
      'tipo': tipo,
      'dataHora': agora.toIso8601String(),
      'horaAparelhoEpochMs': agora.millisecondsSinceEpoch,
      'desvioRelogioMs': desvio,
    };

    await _dbHelper.inserirMarcacao(marcacao);
    await _carregarDadosLocais();

    if (mounted) {
      setState(() => _batendoPonto = false);
      final horario =
          '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_rotulos[tipo]} registrada às $horario.')),
      );
    }
  }

  String _formatarHorarioCompleto(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}:'
          '${d.second.toString().padLeft(2, '0')}';

  /// null = relógio em hora, nada a avisar.
  String? _textoAvisoRelogio(int? desvio) {
    if (desvio == null) {
      return 'Desvio do relógio desconhecido: o app ainda não conferiu a '
          'hora com o servidor. A marcação será registrada e pode ir para análise.';
    }
    if (desvio.abs() > _limiteDesvioMs) {
      final min = (desvio.abs() / 60000).round();
      final sentido = desvio > 0 ? 'adiantado' : 'atrasado';
      return 'O relógio do aparelho está ~$min min $sentido em relação ao '
          'servidor. A marcação será registrada e vai para análise.';
    }
    return null;
  }

  Widget _buildAvisoRelogio() {
    final aviso = _textoAvisoRelogio(_desvioMs);
    if (aviso == null) {
      return Text(
        'Relógio do aparelho conferido com o servidor ✓',
        style: TextStyle(fontSize: 12, color: Colors.green.shade700),
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(aviso, style: const TextStyle(fontSize: 12)),
    );
  }

  String _formatarHorario(String dataHoraIso) {
    final data = DateTime.tryParse(dataHoraIso);
    if (data == null) return '--:--';
    return '${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildSecaoPonto() {
    final proximo = _proximoTipo;

    return Column(
      children: [
        _buildAvisoRelogio(),
        if (_marcacoesHoje.isEmpty)
          Text(
            'Nenhuma marcação hoje ainda',
            style: TextStyle(color: Colors.grey.shade700),
          )
        else
          ..._marcacoesHoje.map((m) {
            final tipo = m['tipo'] as String;
            final horario = _formatarHorario(m['dataHora'] as String);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_rotulos[tipo] ?? tipo}: $horario',
                style: const TextStyle(fontSize: 15),
              ),
            );
          }),
        const SizedBox(height: 16),
        if (proximo != null)
          ElevatedButton.icon(
            onPressed: _batendoPonto ? null : _baterPonto,
            icon: _batendoPonto
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.fingerprint),
            label: Text(
              _batendoPonto
                  ? 'Registrando...'
                  : 'Bater ${_rotulos[proximo]}',
            ),
          )
        else
          Text(
            'Marcações do dia concluídas',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  String _formatarModelo(String modelo) {
    switch (modelo) {
      case 'JORNADA_24X72':
        return '24x72';
      case 'JORNADA_12X36':
        return '12x36';
      case 'TURNO_DIURNO':
        return 'Turno diurno';
      case 'COMERCIAL_5X2':
        return 'Comercial 5x2';
      default:
        return modelo;
    }
  }

  List<Widget> _buildEscalasWidgets() {
    if (_escalas.isEmpty) {
      return [
        Text(
          'Sem escala cadastrada',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ];
    }

    return _escalas.map((escala) {
      final turnosDaEscala =
      _turnos.where((t) => t['escalaId'] == escala['id']).toList();
      final turnosTexto = turnosDaEscala
          .map((t) => '${t['horaInicio']}–${t['horaFim']}')
          .join(', ');

      final nome = (escala['nome'] as String?)?.isNotEmpty == true
          ? escala['nome']
          : 'Escala';
      final modelo = _formatarModelo(escala['modelo'] as String? ?? '');

      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '$nome ($modelo)${turnosTexto.isNotEmpty ? " — $turnosTexto" : ""}',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }).toList();
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
    // de envio de marcações (APP 07) existir. Por enquanto simula
    // que existem 2 marcações pendentes de envio, sem olhar a
    // tabela `marcacao` de verdade.
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
      // Apaga o cache local (funcionário, setor, escala, política).
      // As marcações batidas (`marcacao`) NÃO são apagadas aqui —
      // ver comentário em database_helper.dart.
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
            child: SingleChildScrollView(
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
                      if (_setoresNomes.isNotEmpty)
                        Text(
                          _setoresNomes.length == 1
                              ? 'Setor: ${_setoresNomes.first}'
                              : 'Setores: ${_setoresNomes.join(', ')}',
                          style: TextStyle(color: Colors.grey.shade700),
                        )
                      else
                        Text(
                          'Sem setor alocado',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      const SizedBox(height: 4),
                      ..._buildEscalasWidgets(),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 8),
                      _buildSecaoPonto(),
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
          ),
        ],
      ),
    );
  }
}