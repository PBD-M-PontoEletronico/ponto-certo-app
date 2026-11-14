import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'database_helper.dart';

/// Envio das marcações batidas no aparelho — fatia mínima da APP 07,
/// construída aqui porque a APP 06 (biometria/selfie) só é testável de
/// ponta a ponta com algo realmente enviando pro servidor.
///
/// Selfie é enviada separada da marcação (POST /marcacoes/{id}/selfie) e
/// tentada de novo sozinha se falhar — nunca reenvia a marcação.
class MarcacaoService {
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const String _baseUrl = 'http://192.168.1.108:8080';
  static const Duration _timeout = Duration(seconds: 15);

  Future<void> enviarPendentes() async {
    final token = await _authService.getToken();
    if (token == null) return;

    final funcionario = await _dbHelper.getFuncionario();
    if (funcionario == null) return;
    final usuarioId = funcionario['id'] as String;

    final identificadorDispositivo =
    await _authService.getIdentificadorDispositivo();
    final pendentes = await _dbHelper.getMarcacoesNaoEnviadas();

    for (final m in pendentes) {
      final enviou = await _enviarMarcacao(
        m, usuarioId, identificadorDispositivo, token,
      );
      if (!enviou) continue; // tenta de novo na próxima chamada

      final selfiePath = m['selfiePath'] as String?;
      final selfieJaEnviada = (m['selfieEnviada'] as int? ?? 0) == 1;
      if (selfiePath != null && !selfieJaEnviada) {
        await _enviarSelfie(m['id'] as String, selfiePath, token);
      }
    }
  }

  Future<bool> _enviarMarcacao(
      Map<String, dynamic> m,
      String usuarioId,
      String identificadorDispositivo,
      String token,
      ) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/marcacoes'))
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['id'] = m['id'] as String
        ..fields['usuarioId'] = usuarioId
        ..fields['tipo'] = m['tipo'] as String
        ..fields['horaAparelhoEpochMs'] = (m['horaAparelhoEpochMs'] as int).toString()
        ..fields['offline'] = 'true'
        ..fields['identificadorDispositivo'] = identificadorDispositivo
        ..fields['metodoConfirmacao'] = (m['metodoConfirmacao'] as String? ?? 'DIGITAL');

      if (m['setorId'] != null) {
        request.fields['setorId'] = m['setorId'] as String;
      }
      if (m['desvioRelogioMs'] != null) {
        request.fields['desvioRelogioMs'] = (m['desvioRelogioMs'] as int).toString();
      }
      if (m['latitude'] != null) {
        request.fields['latitude'] = (m['latitude'] as num).toString();
      }
      if (m['longitude'] != null) {
        request.fields['longitude'] = (m['longitude'] as num).toString();
      }
      if (m['digitalConfirmada'] != null) {
        request.fields['digitalConfirmada'] =
            ((m['digitalConfirmada'] as int) == 1).toString();
      }

      final streamed = await request.send().timeout(_timeout);
      if (streamed.statusCode == 200 || streamed.statusCode == 201) {
        await _dbHelper.marcarComoEnviada(m['id'] as String);
        return true;
      }
      return false;
    } catch (e) {
      return false; // sem rede, timeout, etc. — tenta de novo depois
    }
  }

  Future<void> _enviarSelfie(
      String marcacaoId,
      String selfiePath,
      String token,
      ) async {
    try {
      final arquivo = File(selfiePath);
      if (!await arquivo.exists()) return;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/marcacoes/$marcacaoId/selfie'),
      )
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath('foto', selfiePath));

      final streamed = await request.send().timeout(_timeout);
      if (streamed.statusCode == 200) {
        await _dbHelper.marcarSelfieComoEnviada(marcacaoId);
      }
      // Falhou: não mexe em nada. Na próxima chamada tenta de novo —
      // sem reenviar a marcação, que já foi enviada e marcada.
    } catch (e) {
      // idem — tenta de novo depois
    }
  }
}