import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_service.dart';
import 'conectivity_service.dart' show ConnectivityService;
import 'database_helper.dart';

/// Um mes do espelho do funcionario (APP 09/10).
class EspelhoMes {
  final String mes; // yyyy-MM
  final List<Map<String, dynamic>> dias;
  final bool fechado;
  final bool doCache;
  final DateTime? atualizadoEm;
  final String? aviso; // por que nao veio direto do servidor

  const EspelhoMes({
    required this.mes,
    required this.dias,
    required this.fechado,
    required this.doCache,
    this.atualizadoEm,
    this.aviso,
  });
}

/// Busca o espelho do proprio funcionario e guarda no aparelho, para o
/// historico funcionar offline com o que foi baixado na ultima atualizacao.
///
/// ATENCAO: GET /usuarios/{id}/espelho e restrito ao RH na API. Este servico
/// usa GET /me/espelho?mes=yyyy-MM, que PRECISA ser criado no backend (ver
/// pedido ao grupo). Enquanto nao existir, a tela mostra o que estiver no
/// cache e avisa.
class EspelhoService {
  final AuthService _auth = AuthService();
  final DatabaseHelper _db = DatabaseHelper();
  final ConnectivityService _conectividade = ConnectivityService();

  static const Duration _timeout = Duration(seconds: 15);

  Future<EspelhoMes> carregarMes(String mes) async {
    final chave = 'espelho:$mes';
    String? aviso;

    if (await _conectividade.isOnline()) {
      final token = await _auth.getToken();
      if (token != null) {
        try {
          final resp = await http
              .get(
                Uri.parse('$kApiBaseUrl/me/espelho')
                    .replace(queryParameters: {'mes': mes}),
                headers: {'Authorization': 'Bearer $token'},
              )
              .timeout(_timeout);
          if (resp.statusCode == 200) {
            final dados = _normalizar(jsonDecode(resp.body));
            await _db.salvarCache(chave, dados);
            return EspelhoMes(
              mes: mes,
              dias: _listaDeDias(dados),
              fechado: dados['fechado'] == true,
              doCache: false,
              atualizadoEm: DateTime.now(),
            );
          }
          aviso = (resp.statusCode == 404 || resp.statusCode == 403)
              ? 'A API ainda não oferece o espelho do funcionário '
                  '(GET /me/espelho). Mostrando o que está guardado no aparelho.'
              : 'O servidor respondeu ${resp.statusCode}. Mostrando o que está guardado.';
        } catch (_) {
          aviso = 'Não foi possível falar com o servidor. Mostrando o que está guardado.';
        }
      }
    } else {
      aviso = 'Sem conexão: mostrando o que foi baixado na última atualização.';
    }

    final cache = await _db.lerCache(chave);
    final quando = await _db.dataDoCache(chave);
    if (cache is Map) {
      final dados = Map<String, dynamic>.from(cache);
      return EspelhoMes(
        mes: mes,
        dias: _listaDeDias(dados),
        fechado: dados['fechado'] == true,
        doCache: true,
        atualizadoEm: quando,
        aviso: aviso,
      );
    }
    return EspelhoMes(
      mes: mes,
      dias: const [],
      fechado: false,
      doCache: true,
      aviso: aviso ?? 'Este mês ainda não foi baixado.',
    );
  }

  /// Aceita uma lista pura de dias ou {fechado, dias}.
  Map<String, dynamic> _normalizar(dynamic body) {
    if (body is List) return {'fechado': false, 'dias': body};
    if (body is Map) {
      return {
        'fechado': body['fechado'] == true,
        'dias': body['dias'] ?? [],
      };
    }
    return {'fechado': false, 'dias': []};
  }

  List<Map<String, dynamic>> _listaDeDias(Map<String, dynamic> dados) {
    final lista = dados['dias'];
    if (lista is! List) return [];
    return lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
