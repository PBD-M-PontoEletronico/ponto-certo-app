import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/espelho_service.dart';
import '../services/sync_service.dart';
import '../utils/formato.dart';
import '../widgets/offline_banner.dart';

/// Minha escala e previsto contra realizado (APP 10).
///
/// A escala vem da agenda que a abertura (GET /me/abertura) ja baixa; o
/// previsto x realizado usa os minutos que o proprio servidor calcula no
/// espelho (minutosPrevistos / minutosTrabalhados), sem conta paralela.
class EscalaScreen extends StatefulWidget {
  const EscalaScreen({super.key});

  @override
  State<EscalaScreen> createState() => _EscalaScreenState();
}

class _Totais {
  int previsto = 0;
  int trabalhado = 0;
  int get diferenca => trabalhado - previsto;
}

class _EscalaScreenState extends State<EscalaScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final EspelhoService _espelho = EspelhoService();

  List<Map<String, dynamic>> _agenda = [];
  DateTime? _agendaEm;
  EspelhoMes? _mesAtual;
  List<Map<String, dynamic>> _diasMes = [];
  bool _carregando = true;
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final h = DateTime.now();

    final cache = await _db.lerCache('agenda');
    final quando = await _db.dataDoCache('agenda');
    final agenda = cache is List
        ? cache.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    final atual = await _espelho.carregarMes(chaveMes(DateTime(h.year, h.month)));
    final dias = <Map<String, dynamic>>[...atual.dias];

    // Semana que comeca no mes anterior: junta os dois meses.
    final segunda = DateTime(h.year, h.month, h.day).subtract(Duration(days: h.weekday - 1));
    if (segunda.month != h.month) {
      final anterior =
          await _espelho.carregarMes(chaveMes(DateTime(segunda.year, segunda.month)));
      dias.addAll(anterior.dias);
    }

    if (!mounted) return;
    setState(() {
      _agenda = agenda;
      _agendaEm = quando;
      _mesAtual = atual;
      _diasMes = dias;
      _carregando = false;
    });
  }

  Future<void> _atualizar() async {
    setState(() => _sincronizando = true);
    await SyncService().sincronizar();
    if (!mounted) return;
    setState(() => _sincronizando = false);
    await _carregar();
  }

  /// Soma previsto e trabalhado dos dias entre [ini] e [fim], so ate hoje.
  /// O dia de hoje so entra quando ja tem horas calculadas (terminou).
  _Totais _somar(DateTime ini, DateTime fim) {
    final h = DateTime.now();
    final hoje = DateTime(h.year, h.month, h.day);
    final t = _Totais();
    for (final d in _diasMes) {
      final data = DateTime.tryParse(d['data'] as String? ?? '');
      if (data == null || data.isBefore(ini) || data.isAfter(fim)) continue;
      final trab = comoInt(d['minutosTrabalhados']);
      if (data.isAfter(hoje)) continue;
      if (data == hoje && trab == null) continue;
      t.previsto += comoInt(d['minutosPrevistos']) ?? 0;
      t.trabalhado += trab ?? 0;
    }
    return t;
  }

  Widget _linhaTotais(String titulo, _Totais t) {
    final dif = t.diferenca;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('Esperadas ${formatarMinutos(t.previsto)}  ·  '
              'Trabalhadas ${formatarMinutos(t.trabalhado)}'),
          Text(
            'Diferença ${formatarMinutos(dif, sinal: true)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: dif < 0 ? Colors.red.shade700 : Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardPrevistoRealizado() {
    final h = DateTime.now();
    final hoje = DateTime(h.year, h.month, h.day);
    final segunda = hoje.subtract(Duration(days: h.weekday - 1));
    final domingo = segunda.add(const Duration(days: 6));
    final inicioMes = DateTime(h.year, h.month, 1);
    final fimMes = DateTime(h.year, h.month + 1, 0);
    final semTudo = _diasMes.isEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Previsto x realizado',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (semTudo)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _mesAtual?.aviso ?? 'Ainda não há horas baixadas para este mês.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              )
            else ...[
              _linhaTotais(
                  'Esta semana (${dataCurta(segunda)} a ${dataCurta(domingo)})',
                  _somar(segunda, domingo)),
              const Divider(),
              _linhaTotais(nomeDoMes(inicioMes), _somar(inicioMes, fimMes)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardDiaAgenda(Map<String, dynamic> dia) {
    final data = DateTime.parse(dia['data'] as String);
    final situacao = (dia['situacao'] as String?) ?? 'TRABALHO';
    final descricao = dia['descricao'] as String?;
    final turnos = ((dia['turnos'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) => '${a['horaInicio']}'.compareTo('${b['horaInicio']}'));

    final rotuloSituacao = {
      'FOLGA': 'Folga',
      'FERIADO': 'Feriado',
      'AFASTAMENTO': 'Afastamento',
      'SEM_ALOCACAO': 'Sem alocação',
    }[situacao];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${diaDaSemana(data)} ${dataCurta(data)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (rotuloSituacao != null)
              Text(
                descricao == null || descricao.isEmpty
                    ? rotuloSituacao
                    : '$rotuloSituacao · $descricao',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ...turnos.map((t) {
              final atravessa = t['atravessaMeiaNoite'] == true;
              final setor = t['setorNome'] as String?;
              final escala = t['escalaNome'] as String?;
              final detalhe = [
                if (setor != null && setor.isNotEmpty) setor,
                if (escala != null && escala.isNotEmpty) escala,
              ].join(' · ');
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(atravessa ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                        size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${horaCurta(t['horaInicio'] as String?)} – '
                            '${horaCurta(t['horaFim'] as String?)}'
                            '${atravessa ? '  (termina no dia seguinte)' : ''}',
                          ),
                          if (detalhe.isNotEmpty)
                            Text(detalhe,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = DateTime.now();
    final hoje = DateTime(h.year, h.month, h.day);
    final proximos = _agenda.where((d) {
      final data = DateTime.tryParse(d['data'] as String? ?? '');
      return data != null && !data.isBefore(hoje);
    }).toList()
      ..sort((a, b) => (a['data'] as String).compareTo(b['data'] as String));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha escala'),
        actions: [
          IconButton(
            icon: _sincronizando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _sincronizando ? null : _atualizar,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          if (_carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24, top: 8),
                children: [
                  _cardPrevistoRealizado(),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('Próximos dias',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  if (_agendaEm != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Atualizado em ${dataCurta(_agendaEm!)} às ${hhmm(_agendaEm!)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                  if (proximos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'A agenda ainda não foi baixada. Conecte-se e toque em atualizar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    )
                  else
                    ...proximos.map(_cardDiaAgenda),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
