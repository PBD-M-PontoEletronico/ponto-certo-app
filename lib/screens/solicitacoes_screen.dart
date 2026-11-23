import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/solicitacao_service.dart';
import '../utils/formato.dart';
import '../widgets/offline_banner.dart';
import 'nova_solicitacao_screen.dart';

/// Meus pedidos (APP 11/12): fila local + situacao e parecer do gestor.
class SolicitacoesScreen extends StatefulWidget {
  const SolicitacoesScreen({super.key});

  @override
  State<SolicitacoesScreen> createState() => _SolicitacoesScreenState();
}

class _SolicitacoesScreenState extends State<SolicitacoesScreen> {
  final SolicitacaoService _servico = SolicitacaoService();
  final DatabaseHelper _db = DatabaseHelper();

  List<Map<String, dynamic>> _locais = [];
  List<Map<String, dynamic>> _remotas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    SolicitacaoService.mudancas.addListener(_carregar);
    _carregar().then((_) => _atualizar());
  }

  @override
  void dispose() {
    SolicitacaoService.mudancas.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    final f = await _db.getFuncionario();
    final id = f?['id'] as String?;
    final locais = await _db.getSolicitacoesLocais((id == null || id.isEmpty) ? null : id);
    final cache = await _db.lerCache('solicitacoes');
    final remotas = cache is List
        ? cache.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    remotas.sort((a, b) => '${b['criadoEm']}'.compareTo('${a['criadoEm']}'));
    if (!mounted) return;
    setState(() {
      _locais = locais;
      _remotas = remotas;
      _carregando = false;
    });
  }

  Future<void> _atualizar() async {
    await _servico.enviarPendentes();
    await _carregar();
  }

  Future<void> _tentarDeNovo() async {
    await _servico.enviarPendentes(manual: true);
    await _carregar();
  }

  Future<void> _descartar(String id) async {
    await _db.removerSolicitacaoLocal(id);
    SolicitacaoService.mudancas.value++;
  }

  Future<void> _novo(String tipo) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NovaSolicitacaoScreen(tipo: tipo, data: DateTime.now()),
      ),
    );
    await _carregar();
  }

  String _tituloPedido(Map<String, dynamic> s) {
    final data = DateTime.tryParse('${s['data']}');
    final dia = data == null ? '' : ' — ${dataCurta(data)}';
    if (s['tipo'] == 'AJUSTE') {
      final tipo = rotulosTipoMarcacao[s['tipoMarcacao']] ?? '${s['tipoMarcacao']}';
      final hora = s['horaPretendida'] == null ? '' : ' às ${horaCurta('${s['horaPretendida']}')}';
      return 'Ajuste de $tipo$hora$dia';
    }
    final oc = rotulosOcorrencia[s['ocorrencia']] ?? '${s['ocorrencia']}';
    return 'Justificativa de ${oc.toLowerCase()}$dia';
  }

  Widget _cardLocal(Map<String, dynamic> s) {
    final falhou = (s['falhaDefinitiva'] as int? ?? 0) == 1;
    final erro = s['erroEnvio'] as String?;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_tituloPedido(s), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              falhou
                  ? 'Não foi aceito: ${erro ?? 'motivo desconhecido'}'
                  : 'Na fila: sobe sozinho quando houver rede.'
                      '${erro == null ? '' : '\n$erro'}',
              style: TextStyle(
                fontSize: 13,
                color: falhou ? Colors.red.shade700 : Colors.orange.shade800,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _descartar(s['id'] as String),
                  child: const Text('Descartar'),
                ),
                TextButton(onPressed: _tentarDeNovo, child: const Text('Tentar de novo')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardRemoto(Map<String, dynamic> s) {
    final status = s['status'] as String?;
    final cor = status == 'APROVADA'
        ? Colors.green.shade700
        : status == 'RECUSADA'
            ? Colors.red.shade700
            : Colors.orange.shade800;
    final rotulo = {
          'PENDENTE': 'Aguardando',
          'APROVADA': 'Aprovada',
          'RECUSADA': 'Recusada',
        }[status] ??
        '$status';
    final parecer = s['parecer'] as String?;
    final quem = s['analisadoPorNome'] as String?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_tituloPedido(s),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text(rotulo, style: TextStyle(color: cor, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${s['motivo'] ?? ''}', style: const TextStyle(fontSize: 13)),
            if (parecer != null && parecer.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Parecer${quem == null ? '' : ' de $quem'}: $parecer',
                style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ],
            if (s['tipo'] == 'AJUSTE' && status == 'APROVADA')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'A marcação nova aparece no histórico ao lado da original.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vazio = _locais.isEmpty && _remotas.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus pedidos'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add),
            tooltip: 'Novo pedido',
            onSelected: _novo,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'JUSTIFICATIVA', child: Text('Nova justificativa')),
              PopupMenuItem(value: 'AJUSTE', child: Text('Novo pedido de ajuste')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _atualizar,
                    child: ListView(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      children: [
                        if (vazio)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'Nenhum pedido ainda. Para justificar ou pedir ajuste de um '
                              'dia específico, abra o Histórico.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        ..._locais.map(_cardLocal),
                        ..._remotas.map(_cardRemoto),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
