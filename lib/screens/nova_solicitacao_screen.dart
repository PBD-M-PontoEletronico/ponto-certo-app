import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/solicitacao_service.dart';
import '../utils/formato.dart';

/// Justificativa de ocorrencia (APP 11) e pedido de ajuste (APP 12).
class NovaSolicitacaoScreen extends StatefulWidget {
  const NovaSolicitacaoScreen({
    super.key,
    required this.tipo, // JUSTIFICATIVA | AJUSTE
    required this.data,
    this.mesFechado = false,
  });

  final String tipo;
  final DateTime data;
  final bool mesFechado;

  @override
  State<NovaSolicitacaoScreen> createState() => _NovaSolicitacaoScreenState();
}

class _NovaSolicitacaoScreenState extends State<NovaSolicitacaoScreen> {
  static const int _limiteAnexoBytes = 5 * 1024 * 1024; // 5 MB, igual ao servidor

  final _formKey = GlobalKey<FormState>();
  final _motivoCtrl = TextEditingController();
  final SolicitacaoService _servico = SolicitacaoService();

  late DateTime _data;
  String _ocorrencia = 'ATRASO';
  String _tipoMarcacao = 'ENTRADA';
  TimeOfDay? _hora;
  String? _anexoPath;
  String? _anexoNome;
  bool _enviando = false;
  String? _erro;

  bool get _ehAjuste => widget.tipo == 'AJUSTE';

  @override
  void initState() {
    super.initState();
    _data = DateTime(widget.data.year, widget.data.month, widget.data.day);
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _escolherData() async {
    final h = DateTime.now();
    final hoje = DateTime(h.year, h.month, h.day);
    final d = await showDatePicker(
      context: context,
      initialDate: _data.isAfter(hoje) ? hoje : _data,
      firstDate: hoje.subtract(const Duration(days: 120)),
      lastDate: hoje,
    );
    if (d != null) setState(() => _data = d);
  }

  Future<void> _escolherHora() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _hora ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (t != null) setState(() => _hora = t);
  }

  Future<void> _anexar() async {
    try {
      final img = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (img == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final destino = '${dir.path}/anexo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final reduzida = await FlutterImageCompress.compressAndGetFile(
        img.path,
        destino,
        quality: 70,
        minWidth: 1600,
        minHeight: 1600,
      );
      final caminho = reduzida?.path ?? img.path;
      final tamanho = await File(caminho).length();
      if (tamanho > _limiteAnexoBytes) {
        setState(() => _erro = 'O anexo passa de 5 MB. Escolha uma imagem menor.');
        return;
      }
      setState(() {
        _anexoPath = caminho;
        _anexoNome = img.name;
        _erro = null;
      });
    } catch (_) {
      setState(() => _erro = 'Não foi possível abrir a imagem escolhida.');
    }
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;

    if (_ehAjuste) {
      final hora = _hora;
      if (hora == null) {
        setState(() => _erro = 'Informe o horário que deveria ter sido registrado.');
        return;
      }
      final pretendida =
          DateTime(_data.year, _data.month, _data.day, hora.hour, hora.minute);
      if (pretendida.isAfter(DateTime.now())) {
        setState(() => _erro = 'Esse horário ainda não chegou.');
        return;
      }
    }

    setState(() {
      _enviando = true;
      _erro = null;
    });

    final hora = _hora;
    final r = await _servico.criar(
      tipo: widget.tipo,
      data: dataIso(_data),
      ocorrencia: _ehAjuste ? null : _ocorrencia,
      tipoMarcacao: _ehAjuste ? _tipoMarcacao : null,
      horaPretendida: (_ehAjuste && hora != null)
          ? '${doisDigitos(hora.hour)}:${doisDigitos(hora.minute)}'
          : null,
      motivo: _motivoCtrl.text.trim(),
      anexoPath: _ehAjuste ? null : _anexoPath,
    );

    if (!mounted) return;
    setState(() => _enviando = false);

    if (r.recusado) {
      setState(() => _erro = r.mensagem ?? 'O servidor recusou o pedido.');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.enviado
            ? 'Pedido enviado ao gestor.'
            : 'Sem conexão: o pedido ficou na fila e sobe sozinho quando houver rede.'),
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final titulo = _ehAjuste ? 'Pedir ajuste de marcação' : 'Justificar ocorrência';

    if (widget.mesFechado) {
      return Scaffold(
        appBar: AppBar(title: Text(titulo)),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Este mês já foi fechado. O fechamento consolida as horas, '
              'então um dia dele não aceita pedido novo. Se algo ficou errado, '
              'fale com o RH.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_ehAjuste)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Text(
                    'O registro original nunca é apagado. Se o gestor aprovar, '
                    'a marcação nova entra ao lado da original (ou no lugar '
                    'vazio, se você esqueceu de bater), identificada como '
                    'ajuste, com quem pediu e quem aprovou.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _enviando ? null : _escolherData,
                icon: const Icon(Icons.event),
                label: Text('Dia: ${diaDaSemana(_data)} ${dataCurta(_data)}/${_data.year}'),
              ),
              const SizedBox(height: 16),
              if (!_ehAjuste)
                DropdownButtonFormField<String>(
                  initialValue: _ocorrencia,
                  decoration: const InputDecoration(
                    labelText: 'O que aconteceu',
                    border: OutlineInputBorder(),
                  ),
                  items: rotulosOcorrencia.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _ocorrencia = v ?? 'ATRASO'),
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _tipoMarcacao,
                  decoration: const InputDecoration(
                    labelText: 'Qual marcação ficou faltando',
                    border: OutlineInputBorder(),
                  ),
                  items: rotulosTipoMarcacao.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _tipoMarcacao = v ?? 'ENTRADA'),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _enviando ? null : _escolherHora,
                  icon: const Icon(Icons.schedule),
                  label: Text(_hora == null
                      ? 'Horário que deveria ter sido registrado'
                      : 'Horário: ${doisDigitos(_hora!.hour)}:${doisDigitos(_hora!.minute)}'),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _motivoCtrl,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Explique o motivo' : null,
              ),
              if (!_ehAjuste) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _enviando ? null : _anexar,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_anexoNome == null
                      ? 'Anexar atestado (foto, até 5 MB)'
                      : 'Anexo: $_anexoNome'),
                ),
                if (_anexoPath != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _anexoPath = null;
                      _anexoNome = null;
                    }),
                    child: const Text('Remover anexo'),
                  ),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!, style: TextStyle(color: Colors.red.shade700)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _enviando ? null : _enviar,
                child: _enviando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Enviar pedido'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
