import 'package:flutter/material.dart';
import '../services/espelho_service.dart';
import '../utils/formato.dart';
import '../widgets/offline_banner.dart';
import 'nova_solicitacao_screen.dart';

/// Historico dia a dia (APP 09): marcacoes, horas, atraso, saldo, feriado e
/// afastamento, com o que foi baixado na ultima atualizacao.
class EspelhoScreen extends StatefulWidget {
  const EspelhoScreen({super.key});

  @override
  State<EspelhoScreen> createState() => _EspelhoScreenState();
}

class _EspelhoScreenState extends State<EspelhoScreen> {
  final EspelhoService _servico = EspelhoService();
  late DateTime _mes;
  EspelhoMes? _dados;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    final h = DateTime.now();
    _mes = DateTime(h.year, h.month);
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final d = await _servico.carregarMes(chaveMes(_mes));
    if (!mounted) return;
    setState(() {
      _dados = d;
      _carregando = false;
    });
  }

  bool get _ehMesAtual {
    final h = DateTime.now();
    return _mes.year == h.year && _mes.month == h.month;
  }

  void _mudarMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta));
    _carregar();
  }

  Future<void> _abrirPedido(String tipo, DateTime data, bool fechado) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NovaSolicitacaoScreen(
          tipo: tipo,
          data: data,
          mesFechado: fechado,
        ),
      ),
    );
  }

  String _textoMarcacao(Map<String, dynamic> m) {
    final tipo = rotulosTipoMarcacao[m['tipo']] ?? '${m['tipo']}';
    final partes = <String>[];
    if (m['ajuste'] == true) {
      final quem = m['aprovadoPorNome'];
      partes.add(quem == null ? 'ajuste aprovado' : 'ajuste aprovado por $quem');
    }
    final status = m['status'];
    if (status == 'PENDENTE_ANALISE') {
      final motivo = m['motivo'] ?? m['motivoRecusa'];
      partes.add(motivo == null
          ? 'pendente de análise'
          : 'pendente de análise: $motivo');
    } else if (status == 'RECUSADA') {
      final motivo = m['motivoRecusa'];
      partes.add(motivo == null ? 'recusada' : 'recusada: $motivo');
    }
    if (m['offline'] == true) partes.add('batida offline');
    final extra = partes.isEmpty ? '' : '  (${partes.join(' · ')})';
    return '$tipo ${hhmmDeIso(m['hora'] as String?)}$extra';
  }

  Color? _corMarcacao(Map<String, dynamic> m) {
    if (m['status'] == 'PENDENTE_ANALISE') return Colors.orange.shade800;
    if (m['status'] == 'RECUSADA') return Colors.red.shade700;
    if (m['ajuste'] == true) return Colors.blue.shade700;
    return null;
  }

  Widget _cardDia(Map<String, dynamic> dia, bool fechado) {
    final data = DateTime.parse(dia['data'] as String);
    final situacao = (dia['situacao'] as String?) ?? 'TRABALHO';
    final marcacoes = ((dia['marcacoes'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final justificativas = ((dia['justificativas'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final trabalhados = comoInt(dia['minutosTrabalhados']);
    final atraso = comoInt(dia['minutosAtraso']);
    final saldoDia = comoInt(dia['saldoDoDiaMinutos']);
    final previstos = comoInt(dia['minutosPrevistos']) ?? 0;
    final descricao = dia['descricao'] as String?;

    String subtitulo;
    switch (situacao) {
      case 'FERIADO':
        subtitulo = descricao == null || descricao.isEmpty ? 'Feriado' : 'Feriado · $descricao';
        break;
      case 'AFASTAMENTO':
        subtitulo = descricao == null || descricao.isEmpty ? 'Afastamento' : 'Afastamento · $descricao';
        break;
      case 'FOLGA':
        subtitulo = 'Folga';
        break;
      case 'SEM_ALOCACAO':
        subtitulo = 'Sem alocação';
        break;
      default:
        if (trabalhados != null) {
          subtitulo =
              'Trabalhado ${formatarMinutos(trabalhados)} · Atraso ${formatarMinutos(atraso)}';
        } else {
          subtitulo = marcacoes.isEmpty ? 'Sem marcações' : 'Em andamento';
        }
    }

    final podePedir = !fechado && situacao != 'SEM_ALOCACAO';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        title: Text('${diaDaSemana(data)} ${dataCurta(data)}'),
        subtitle: Text(subtitulo),
        trailing: saldoDia == null
            ? null
            : Text(
                formatarMinutos(saldoDia, sinal: true),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: saldoDia < 0 ? Colors.red.shade700 : Colors.green.shade700,
                ),
              ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Previsto: ${formatarMinutos(previstos)}',
              style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          if (marcacoes.isEmpty)
            const Text('Nenhuma marcação neste dia.')
          else
            ...marcacoes.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(_textoMarcacao(m),
                      style: TextStyle(color: _corMarcacao(m))),
                )),
          ...justificativas.map((j) {
            final oc = rotulosOcorrencia[j['ocorrencia']] ?? '${j['ocorrencia']}';
            final st = {
                  'PENDENTE': 'aguardando',
                  'APROVADA': 'aprovada',
                  'RECUSADA': 'recusada',
                }[j['status']] ??
                '${j['status']}';
            final parecer = j['parecer'] as String?;
            final quem = j['analisadoPorNome'] as String?;
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Justificativa ($oc): $st'
                '${parecer == null ? '' : ' — "$parecer"'}'
                '${quem == null ? '' : ' (por $quem)'}',
                style: const TextStyle(fontSize: 13),
              ),
            );
          }),
          const SizedBox(height: 8),
          if (fechado)
            Text('Mês fechado: não aceita pedido novo.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12))
          else if (podePedir)
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _abrirPedido('JUSTIFICATIVA', data, fechado),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Justificar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _abrirPedido('AJUSTE', data, fechado),
                  icon: const Icon(Icons.schedule),
                  label: const Text('Pedir ajuste'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dados = _dados;
    final hoje = DateTime.now();
    final hojeData = DateTime(hoje.year, hoje.month, hoje.day);

    final dias = (dados?.dias ?? []).where((d) {
      final data = DateTime.tryParse(d['data'] as String? ?? '');
      return data != null && !data.isAfter(hojeData);
    }).toList()
      ..sort((a, b) => (a['data'] as String).compareTo(b['data'] as String));

    var totalTrabalhado = 0;
    var totalAtraso = 0;
    for (final d in dias) {
      totalTrabalhado += comoInt(d['minutosTrabalhados']) ?? 0;
      totalAtraso += comoInt(d['minutosAtraso']) ?? 0;
    }
    final saldoAcumulado =
        dias.isEmpty ? null : comoInt(dias.last['saldoAcumuladoMinutos']);

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: Column(
        children: [
          const OfflineBanner(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _mudarMes(-1),
              ),
              Text(nomeDoMes(_mes),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _ehMesAtual ? null : () => _mudarMes(1),
              ),
            ],
          ),
          if (_carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (dados?.aviso != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border: Border.all(color: Colors.orange.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(dados!.aviso!, style: const TextStyle(fontSize: 12)),
                    ),
                  if (dados?.fechado == true)
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_outline, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Mês fechado. Não aceita pedido de justificativa nem de ajuste.'),
                          ),
                        ],
                      ),
                    ),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _resumo('Saldo acumulado',
                              saldoAcumulado == null ? '—' : formatarMinutos(saldoAcumulado, sinal: true),
                              destaque: true),
                          _resumo('Trabalhadas', formatarMinutos(totalTrabalhado)),
                          _resumo('Atraso', formatarMinutos(totalAtraso)),
                        ],
                      ),
                    ),
                  ),
                  if (dias.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Nenhum dia para mostrar neste mês.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    )
                  else
                    ...dias.reversed.map((d) => _cardDia(d, dados?.fechado == true)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _resumo(String rotulo, String valor, {bool destaque = false}) {
    return Column(
      children: [
        Text(valor,
            style: TextStyle(
                fontSize: destaque ? 20 : 16, fontWeight: FontWeight.bold)),
        Text(rotulo, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }
}
