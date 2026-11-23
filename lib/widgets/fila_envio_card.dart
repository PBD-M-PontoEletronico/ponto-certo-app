import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/marcacao_service.dart';

/// Mostra quantas marcacoes ainda nao subiram, o motivo das que falharam e
/// o botao "Enviar agora" (APP 07).
class FilaEnvioCard extends StatefulWidget {
  const FilaEnvioCard({super.key});

  @override
  State<FilaEnvioCard> createState() => _FilaEnvioCardState();
}

class _FilaEnvioCardState extends State<FilaEnvioCard> {
  static const Map<String, String> _rotulos = {
    'ENTRADA': 'Entrada',
    'SAIDA_INTERVALO': 'Saída (intervalo)',
    'RETORNO_INTERVALO': 'Retorno (intervalo)',
    'SAIDA': 'Saída',
  };

  final DatabaseHelper _db = DatabaseHelper();
  int _pendentes = 0;
  List<Map<String, dynamic>> _falhas = [];
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
    MarcacaoService.mudancas.addListener(_carregar);
  }

  @override
  void dispose() {
    MarcacaoService.mudancas.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    final n = await _db.contarNaoEnviadas();
    final falhas = await _db.getMarcacoesComFalha();
    if (!mounted) return;
    setState(() {
      _pendentes = n;
      _falhas = falhas;
    });
  }

  Future<void> _enviarAgora() async {
    setState(() => _enviando = true);
    final r = await MarcacaoService().enviarPendentes(manual: true);
    if (!mounted) return;
    setState(() => _enviando = false);
    final msg = r.restantes == 0
        ? 'Tudo enviado.'
        : '${r.enviadas} enviada(s). Ainda faltam ${r.restantes}.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _hora(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '--:--';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tudoEnviado = _pendentes == 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  tudoEnviado ? Icons.cloud_done : Icons.cloud_upload_outlined,
                  color: tudoEnviado ? Colors.green.shade700 : Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tudoEnviado
                        ? 'Todas as marcações foram enviadas'
                        : '$_pendentes marcação(ões) ainda não subiram',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (_falhas.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._falhas.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${_rotulos[m['tipo']] ?? m['tipo']} ${_hora(m['dataHora'] as String)}: '
                      '${m['erroEnvio']}',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                    ),
                  )),
            ],
            if (!tudoEnviado) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: _enviando ? null : _enviarAgora,
                  icon: _enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_falhas.isEmpty ? 'Enviar agora' : 'Tentar de novo'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
