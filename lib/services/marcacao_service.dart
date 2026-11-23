import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_service.dart';
import 'database_helper.dart';

class ResumoEnvio {
  final int enviadas;
  final int falhas;
  final int restantes;
  const ResumoEnvio(this.enviadas, this.falhas, this.restantes);
}

enum _Resultado { ok, falha, parar }

/// Fila de envio das marcacoes (APP 07).
///
/// Toda marcacao nasce no banco local e so sai da fila quando o servidor a
/// aceita. Contrato WEB-09: a selfie viaja no proprio POST /marcacoes, e o
/// mesmo id em reenvio nunca duplica - por isso reenviar e sempre seguro.
class MarcacaoService {
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const String _baseUrl = kApiBaseUrl;
  static const Duration _timeout = Duration(seconds: 20);

  // Evita dois envios em paralelo (tela + sincronizacao) da mesma fila.
  static bool _emAndamento = false;

  /// Sobe a cada mudanca na fila; as telas escutam para se atualizar.
  static final ValueNotifier<int> mudancas = ValueNotifier<int>(0);

  /// [manual] = botao "Enviar agora" / "Tentar de novo": devolve para a
  /// fila tambem as marcacoes que o servidor recusou antes.
  Future<ResumoEnvio> enviarPendentes({bool manual = false}) async {
    if (_emAndamento) return const ResumoEnvio(0, 0, 0);
    _emAndamento = true;
    var enviadas = 0;
    var falhas = 0;
    try {
      final token = await _authService.getToken();
      if (token == null) return const ResumoEnvio(0, 0, 0);

      if (manual) await _dbHelper.reabrirFalhas();

      final funcionario = await _dbHelper.getFuncionario();
      final usuarioPadrao = funcionario?['id'] as String?;
      final idDispositivo = await _authService.getIdentificadorDispositivo();
      final pendentes = await _dbHelper.getMarcacoesNaoEnviadas();

      for (final m in pendentes) {
        final usuarioId = (m['usuarioId'] as String?) ?? usuarioPadrao;
        if (usuarioId == null || usuarioId.isEmpty) {
          await _dbHelper.registrarFalhaEnvio(
            m['id'] as String,
            'Funcionário da marcação não identificado.',
            definitiva: true,
          );
          falhas++;
          continue;
        }
        final r = await _enviarMarcacao(m, usuarioId, idDispositivo, token);
        if (r == _Resultado.ok) enviadas++;
        if (r == _Resultado.falha) falhas++;
        if (r == _Resultado.parar) break;
      }
    } finally {
      _emAndamento = false;
      mudancas.value++;
    }
    final restantes = await _dbHelper.contarNaoEnviadas();
    return ResumoEnvio(enviadas, falhas, restantes);
  }

  Future<_Resultado> _enviarMarcacao(
    Map<String, dynamic> m,
    String usuarioId,
    String identificadorDispositivo,
    String token,
  ) async {
    final id = m['id'] as String;
    try {
      final metodo = (m['metodoConfirmacao'] as String?) ?? 'DIGITAL';
      final request =
          http.MultipartRequest('POST', Uri.parse('$_baseUrl/marcacoes'))
            ..headers['Authorization'] = 'Bearer $token'
            ..fields['id'] = id
            ..fields['usuarioId'] = usuarioId
            ..fields['tipo'] = m['tipo'] as String
            ..fields['horaAparelhoEpochMs'] =
                (m['horaAparelhoEpochMs'] as int).toString()
            ..fields['offline'] = ((m['offline'] as int? ?? 0) == 1).toString()
            ..fields['identificadorDispositivo'] = identificadorDispositivo
            ..fields['metodoConfirmacao'] = metodo;

      if (m['setorId'] != null) {
        request.fields['setorId'] = m['setorId'] as String;
      }
      if (m['desvioRelogioMs'] != null) {
        request.fields['desvioRelogioMs'] =
            (m['desvioRelogioMs'] as int).toString();
      }
      if (m['latitude'] != null) {
        request.fields['latitude'] = (m['latitude'] as num).toString();
      }
      if (m['longitude'] != null) {
        request.fields['longitude'] = (m['longitude'] as num).toString();
      }
      if (metodo == 'DIGITAL' && m['digitalConfirmada'] != null) {
        request.fields['digitalConfirmada'] =
            ((m['digitalConfirmada'] as int) == 1).toString();
      }

      final selfiePath = m['selfiePath'] as String?;
      var anexouFoto = false;
      if (metodo == 'FOTO' && selfiePath != null) {
        if (await File(selfiePath).exists()) {
          request.files.add(await http.MultipartFile.fromPath('foto', selfiePath));
          anexouFoto = true;
        }
      }

      final streamed = await request.send().timeout(_timeout);
      final resp = await http.Response.fromStream(streamed);
      final status = resp.statusCode;

      if (status == 200 || status == 201) {
        String? situacao;
        String? motivo;
        try {
          final j = jsonDecode(resp.body) as Map<String, dynamic>;
          situacao = j['status'] as String?;
          motivo = j['motivoRecusa'] as String?;
        } catch (_) {}
        await _dbHelper.registrarEnvioOk(
          id,
          statusServidor: situacao,
          motivoRecusa: motivo,
          comSelfie: anexouFoto,
        );
        if (anexouFoto) {
          try {
            await File(selfiePath!).delete(); // ja esta no servidor
          } catch (_) {}
        }
        return _Resultado.ok;
      }

      if (status == 401) {
        await _dbHelper.registrarFalhaEnvio(
            id, 'Sessão expirada. Entre de novo para enviar.',
            definitiva: false);
        return _Resultado.parar;
      }

      // 400/403/409/413: o servidor entendeu e recusou - nao adianta repetir
      // sozinho (contrato WEB-09). 5xx pode ser passageiro: continua na fila.
      final definitiva = status == 400 || status == 403 || status == 409 || status == 413;
      await _dbHelper.registrarFalhaEnvio(
        id,
        'Servidor respondeu $status: ${_mensagemDeErro(resp)}',
        definitiva: definitiva,
      );
      return _Resultado.falha;
    } catch (e) {
      await _dbHelper.registrarFalhaEnvio(
        id,
        'Sem conexão com o servidor. Vai tentar de novo.',
        definitiva: false,
      );
      return _Resultado.parar; // sem rede: nao adianta tentar as demais agora
    }
  }

  String _mensagemDeErro(http.Response resp) {
    try {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final msg = j['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    } catch (_) {}
    final corpo = resp.body;
    return corpo.length > 120 ? corpo.substring(0, 120) : corpo;
  }
}
