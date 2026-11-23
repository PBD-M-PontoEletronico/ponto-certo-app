import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/conectivity_service.dart';
import '../services/database_helper.dart';
import '../services/localizacao_service.dart';
import '../services/marcacao_service.dart';
import '../services/relogio_service.dart';
import '../services/selfie_service.dart';
import '../utils/uuid.dart';
import '../widgets/fila_envio_card.dart';
import '../widgets/offline_banner.dart';
import 'login_screen.dart';

/// Modo relogio (APP 08): o aparelho fixo do setor. O gestor entra com a
/// conta do setor; cada funcionario se escolhe na lista e bate com selfie.
class RelogioScreen extends StatefulWidget {
  const RelogioScreen({super.key});

  @override
  State<RelogioScreen> createState() => _RelogioScreenState();
}

class _RelogioScreenState extends State<RelogioScreen> {
  static const List<String> _sequencia = [
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

  final AuthService _auth = AuthService();
  final DatabaseHelper _db = DatabaseHelper();
  final RelogioService _relogio = RelogioService();
  final SelfieService _selfie = SelfieService();
  final LocalizacaoService _gps = LocalizacaoService();
  final MarcacaoService _marcacoes = MarcacaoService();
  final TextEditingController _buscaCtrl = TextEditingController();

  List<Map<String, dynamic>> _funcionarios = [];
  List<Map<String, dynamic>> _setores = [];
  DateTime? _atualizadoEm;
  bool _ocupado = false;
  bool _sincronizando = false;
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _carregar();
    unawaited(_atualizar(silencioso: true));
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final f = await _relogio.funcionarios();
    final s = await _relogio.setores();
    final quando = await _db.dataDoCache(RelogioService.chaveFuncionarios);
    if (!mounted) return;
    setState(() {
      _funcionarios = f;
      _setores = s;
      _atualizadoEm = quando;
    });
  }

  Future<void> _atualizar({bool silencioso = false}) async {
    setState(() => _sincronizando = true);
    final ok = await _relogio.sincronizar();
    if (!mounted) return;
    setState(() => _sincronizando = false);
    if (ok) await _carregar();
    if (!silencioso && mounted) {
      _aviso(ok
          ? 'Lista atualizada.'
          : 'Não foi possível atualizar. Usando a lista guardada no aparelho.');
    }
  }

  void _aviso(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _busca.trim().toLowerCase();
    if (q.isEmpty) return _funcionarios;
    return _funcionarios.where((f) {
      final nome = ((f['nome'] as String?) ?? '').toLowerCase();
      final mat = ((f['matricula'] as String?) ?? '').toLowerCase();
      return nome.contains(q) || mat.contains(q);
    }).toList();
  }

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _baterPara(Map<String, dynamic> f) async {
    if (_ocupado) return;
    final usuarioId = f['id'] as String;
    final nome = (f['nome'] as String?) ?? 'Funcionario';

    final hoje = await _db.getMarcacoesHojeDoFuncionario(usuarioId);
    if (hoje.length >= _sequencia.length) {
      if (mounted) _aviso('$nome já concluiu as marcações de hoje.');
      return;
    }
    final tipo = _sequencia[hoje.length];
    if (!mounted) return;

    // Quem bate confirma que e ele mesmo; a foto abaixo e que amarra a
    // marcacao a pessoa. A confirmacao por senha de cada funcionario
    // depende de a API oferecer uma forma de conferi-la (ver relatorio).
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(nome),
        content: Text(
            'Registrar "${_rotulos[tipo]}"? Em seguida será tirada uma selfie.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    // Hora do toque.
    final agora = DateTime.now();
    setState(() => _ocupado = true);
    try {
      final setor = _setores.isNotEmpty ? _setores.first : null;
      final politica = setor?['politica'] as Map<String, dynamic>?;

      // --- Localizacao pela politica do setor (mesma regra da APP 05) ---
      double? lat;
      double? lng;
      final setorLat = (setor?['latitude'] as num?)?.toDouble();
      final setorLng = (setor?['longitude'] as num?)?.toDouble();
      final ignorar = politica?['ignorarLocalizacao'] == true;
      if (politica != null && !ignorar && setorLat != null && setorLng != null) {
        final r = await _gps.capturar();
        lat = r.latitude;
        lng = r.longitude;
        if (lat != null && lng != null) {
          final raio = (politica['raioMetros'] as num?)?.toInt() ?? 0;
          final dist =
              LocalizacaoService.distanciaMetros(setorLat, setorLng, lat, lng);
          if (dist > raio && politica['politicaForaPerimetro'] == 'BLOQUEAR') {
            if (mounted) {
              _aviso('Aparelho fora do perímetro do setor. Marcação não registrada.');
            }
            return;
          }
        }
      }

      // --- Selfie: SEMPRE obrigatoria no modo relogio ---
      final foto = await _selfie.capturarEComprimir();
      if (foto.resultado != ResultadoSelfie.capturada) {
        if (mounted) {
          _aviso(foto.mensagem ?? 'Selfie não tirada. A marcação não foi registrada.');
        }
        return;
      }

      final desvio = await _db.getDesvioRelogioMs();
      final estavaOnline = await ConnectivityService().isOnline();

      await _db.inserirMarcacao({
        'id': gerarUuidV4(),
        'tipo': tipo,
        'dataHora': agora.toIso8601String(),
        'horaAparelhoEpochMs': agora.millisecondsSinceEpoch,
        'desvioRelogioMs': desvio,
        'latitude': lat,
        'longitude': lng,
        'setorId': setor?['id'],
        'metodoConfirmacao': 'FOTO',
        'digitalConfirmada': 0,
        'selfiePath': foto.caminho,
        'offline': estavaOnline ? 0 : 1,
        'usuarioId': usuarioId, // em nome do funcionario, nao da conta do setor
      });

      if (mounted) _aviso('${_rotulos[tipo]} de $nome registrada às ${_hhmm(agora)}.');
      unawaited(_marcacoes.enviarPendentes());
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Sair do modo relogio exige a senha do gestor (a da conta do setor).
  Future<void> _sair() async {
    final pendentes = await _db.contarNaoEnviadas();
    if (!mounted) return;
    final ctrl = TextEditingController();
    final senha = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair do modo relógio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Digite a senha do gestor para sair.'),
            if (pendentes > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$pendentes marcação(ões) ainda não foram enviadas e ficam '
                'guardadas até o próximo login com internet.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Senha do gestor',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (senha == null || senha.isEmpty) return;

    final ok = await _auth.verificarSenhaDoGestor(senha);
    if (!mounted) return;
    if (!ok) {
      _aviso('Senha incorreta.');
      return;
    }
    await _db.limparTudo();
    await _auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    final nomeSetor = _setores.isNotEmpty ? (_setores.first['nome'] as String?) : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(nomeSetor == null ? 'Relógio de ponto' : 'Relógio - $nomeSetor'),
        actions: [
          IconButton(
            icon: _sincronizando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Atualizar lista',
            onPressed: _sincronizando ? null : () => _atualizar(),
          ),
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Sair do modo relógio',
            onPressed: _sair,
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _buscaCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nome ou matrícula',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _atualizadoEm == null
                    ? 'Lista ainda não baixada. Conecte-se e toque em atualizar.'
                    : 'Lista de ${_atualizadoEm!.day.toString().padLeft(2, '0')}/'
                        '${_atualizadoEm!.month.toString().padLeft(2, '0')} '
                        'às ${_hhmm(_atualizadoEm!)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ),
          Expanded(
            child: lista.isEmpty
                ? Center(
                    child: Text(
                      _funcionarios.isEmpty
                          ? 'Nenhum funcionário na lista.'
                          : 'Ninguem encontrado.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  )
                : ListView.separated(
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final f = lista[i];
                      final mat = (f['matricula'] as String?) ?? '';
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text((f['nome'] as String?) ?? ''),
                        subtitle: mat.isEmpty ? null : Text('Matrícula $mat'),
                        trailing: const Icon(Icons.fingerprint),
                        enabled: !_ocupado,
                        onTap: () => _baterPara(f),
                      );
                    },
                  ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: FilaEnvioCard(),
          ),
        ],
      ),
    );
  }
}
