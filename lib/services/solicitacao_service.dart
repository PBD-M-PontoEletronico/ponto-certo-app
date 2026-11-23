import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/uuid.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'database_helper.dart';

class ResultadoPedido {
  final bool enviado; // o servidor ja aceitou
  final bool recusado; // o servidor recusou de forma definitiva
  final String? mensagem;
  const ResultadoPedido({this.enviado = false, this.recusado = false, this.mensagem});
}

/// Justificativas e pedidos de ajuste (APP 11/12).
///
/// Todo pedido entra primeiro na fila local; sem rede ele sobe depois, como as
/// marcacoes. Contrato WEB-10: o anexo vai no proprio POST /solicitacoes
/// (campo `anexo`); nao existe envio separado do anexo.
class SolicitacaoService {
  final AuthService _auth = AuthService();
  final DatabaseHelper _db = DatabaseHelper();

  static const Duration _timeout = Duration(seconds: 30);
  static bool _emAndamento = false;
  static final ValueNotifier<int> mudancas = ValueNotifier<int>(0);

  Future<String?> _usuarioAtual() async {
    final f = await _db.getFuncionario();
    final id = f?['id'] as String?;
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Guarda o pedido na fila e tenta enviar agora.
  Future<ResultadoPedido> criar({
    required String tipo, // JUSTIFICATIVA | AJUSTE
    required String data, // yyyy-MM-dd
    String? ocorrencia,
    String? tipoMarcacao,
    String? horaPretendida, // HH:mm
    required String motivo,
    String? anexoPath,
  }) async {
    final id = gerarUuidV4();
    await _db.inserirSolicitacaoLocal({
      'id': id,
      'usuarioId': await _usuarioAtual(),
      'tipo': tipo,
      'data': data,
      'ocorrencia': ocorrencia,
      'tipoMarcacao': tipoMarcacao,
      'horaPretendida': horaPretendida,
      'motivo': motivo,
      'anexoPath': anexoPath,
      'criadoEm': DateTime.now().toIso8601String(),
    });
    mudancas.value++;

    await enviarPendentes();

    final restante = (await _db.getSolicitacoesLocais(await _usuarioAtual()))
        .where((s) => s['id'] == id)
        .toList();
    if (restante.isEmpty) return const ResultadoPedido(enviado: true);

    final s = restante.first;
    if ((s['falhaDefinitiva'] as int? ?? 0) == 1) {
      // O servidor disse nao (ex.: mes fechado). Nao fica na fila: o
      // funcionario le o motivo na propria tela e corrige.
      await _db.removerSolicitacaoLocal(id);
      mudancas.value++;
      return ResultadoPedido(recusado: true, mensagem: s['erroEnvio'] as String?);
    }
    return const ResultadoPedido(); // ficou na fila (sem rede)
  }

  Future<void> enviarPendentes({bool manual = false}) async {
    if (_emAndamento) return;
    _emAndamento = true;
    try {
      final token = await _auth.getToken();
      if (token == null) return;

      if (manual) await _db.reabrirSolicitacoesComFalha();
      final lista = await _db.getSolicitacoesParaEnviar(await _usuarioAtual());
      for (final s in lista) {
        final parar = await _enviar(s, token);
        if (parar) break;
      }
      await buscarMinhas();
    } finally {
      _emAndamento = false;
      mudancas.value++;
    }
  }

  /// true = parar o laco (sem rede ou sessao expirada).
  Future<bool> _enviar(Map<String, dynamic> s, String token) async {
    final id = s['id'] as String;
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$kApiBaseUrl/solicitacoes'))
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['tipo'] = s['tipo'] as String
        ..fields['data'] = s['data'] as String
        ..fields['motivo'] = s['motivo'] as String;
      if (s['ocorrencia'] != null) req.fields['ocorrencia'] = s['ocorrencia'] as String;
      if (s['tipoMarcacao'] != null) req.fields['tipoMarcacao'] = s['tipoMarcacao'] as String;
      if (s['horaPretendida'] != null) req.fields['horaPretendida'] = s['horaPretendida'] as String;

      final anexo = s['anexoPath'] as String?;
      if (anexo != null && await File(anexo).exists()) {
        req.files.add(await http.MultipartFile.fromPath('anexo', anexo));
      }

      final streamed = await req.send().timeout(_timeout);
      final resp = await http.Response.fromStream(streamed);
      final status = resp.statusCode;
      final msg = _mensagem(resp);

      // 409 "ja existe um pedido igual": o envio anterior chegou e a resposta
      // se perdeu. O servidor ja tem o pedido - sai da fila.
      final repetido = status == 409 && msg.contains('Já existe um pedido igual');
      if (status == 200 || status == 201 || repetido) {
        await _db.removerSolicitacaoLocal(id);
        if (anexo != null) {
          try {
            await File(anexo).delete();
          } catch (_) {}
        }
        return false;
      }
      if (status == 401) {
        await _db.registrarFalhaSolicitacao(id, 'Sessão expirada. Entre de novo para enviar.',
            definitiva: false);
        return true;
      }
      final definitiva = status == 400 || status == 403 || status == 409 || status == 413;
      await _db.registrarFalhaSolicitacao(id, msg, definitiva: definitiva);
      return false;
    } catch (_) {
      await _db.registrarFalhaSolicitacao(id, 'Sem conexão com o servidor. Vai tentar de novo.',
          definitiva: false);
      return true;
    }
  }

  String _mensagem(http.Response resp) {
    try {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final m = j['message'];
      if (m is String && m.isNotEmpty) return m;
    } catch (_) {}
    return 'O servidor respondeu ${resp.statusCode}.';
  }

  /// Atualiza do servidor a lista dos meus pedidos (situacao e parecer).
  Future<bool> buscarMinhas() async {
    try {
      final token = await _auth.getToken();
      if (token == null) return false;
      final resp = await http
          .get(Uri.parse('$kApiBaseUrl/solicitacoes/minhas'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(_timeout);
      if (resp.statusCode != 200) return false;
      await _db.salvarCache('solicitacoes', jsonDecode(resp.body));
      return true;
    } catch (_) {
      return false;
    }
  }
}
