import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_service.dart';
import 'conectivity_service.dart' show ConnectivityService;
import 'database_helper.dart';
import 'marcacao_service.dart';

/// Sincronizacao do aparelho em modo relogio (APP 08): baixa de
/// GET /me/abertura a lista de funcionarios do setor e a politica do setor,
/// e guarda tudo no aparelho para o totem funcionar offline.
class RelogioService {
  static const String chaveFuncionarios = 'relogio_funcionarios';
  static const String chaveSetores = 'relogio_setores';
  static const Duration _timeout = Duration(seconds: 15);

  final AuthService _auth = AuthService();
  final DatabaseHelper _db = DatabaseHelper();
  final ConnectivityService _conectividade = ConnectivityService();

  Future<bool> sincronizar() async {
    if (!await _conectividade.isOnline()) return false;
    final token = await _auth.getToken();
    if (token == null) return false;

    try {
      final id = await _auth.getIdentificadorDispositivo();
      final t0 = DateTime.now().millisecondsSinceEpoch;
      final resp = await http
          .get(
            Uri.parse('$kApiBaseUrl/me/abertura')
                .replace(queryParameters: {'identificadorDispositivo': id}),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
      final t1 = DateTime.now().millisecondsSinceEpoch;

      if (resp.statusCode != 200) {
        // ignore: avoid_print
        print('=== RELOGIO: /me/abertura respondeu ${resp.statusCode} ===');
        return false;
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (json['modo'] != 'RELOGIO_SETOR') {
        // ignore: avoid_print
        print('=== RELOGIO: modo recebido = ${json['modo']} ===');
        return false;
      }

      final servidorMs = (json['horaServidorEpochMs'] as num).toInt();
      await _db.salvarDesvioRelogio(((t0 + t1) ~/ 2) - servidorMs);
      await _db.salvarCache(chaveFuncionarios, json['funcionarios'] ?? []);
      await _db.salvarCache(chaveSetores, json['setores'] ?? []);

      await MarcacaoService().enviarPendentes();
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('=== RELOGIO: falha na sincronizacao: $e ===');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> funcionarios() async {
    final c = await _db.lerCache(chaveFuncionarios);
    if (c is! List) return [];
    return c.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> setores() async {
    final c = await _db.lerCache(chaveSetores);
    if (c is! List) return [];
    return c.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
