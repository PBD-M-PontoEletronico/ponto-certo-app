import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'dart:io';
import 'conectivity_service.dart' show ConnectivityService;
import 'database_helper.dart';

/// Orquestra a sincronização de dados locais (APP 02).
/// Busca dados reais da API quando existem, e usa valores simbólicos
/// (mock) para o que ainda não foi implementado no backend
/// (política completa, escala, marcações recentes).
class SyncService {
  final AuthService _authService = AuthService();
  final ConnectivityService _connectivityService = ConnectivityService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // 🔧 Mesma URL base usada no auth_service.dart
  static const String _baseUrl = 'http://192.168.1.121:8080';

  /// Executa a sincronização completa. Retorna true se conseguiu
  /// atualizar os dados, false se não tinha conexão (nesse caso o
  /// app segue usando o que já está salvo localmente, sem erro).
  Future<bool> sincronizar() async {
    final online = await _connectivityService.isOnline();
    if (!online) {
      return false;
    }

    final token = await _authService.getToken();
    if (token == null) {
      return false;
    }

    try {
      // --- 1. Funcionário: já vem salvo do login (auth_service) ---
      final nome = await _authService.getNome() ?? '';
      final usuario = await _authService.getUsuario() ?? '';
      final perfil = await _authService.getPerfil() ?? '';
      final setoresIds = await _authService.getSetoresIds();

      final funcionarioMap = {
        'id': usuario, // provisório: API ainda não expõe o id do usuário no login
        'nome': nome,
        'usuario': usuario,
        'perfil': perfil,
        'setoresIds': setoresIds.join(','),
      };

      // --- 2. Setor: REAL, busca o primeiro setor da lista via API ---
      Map<String, dynamic> setorMap = {'id': '', 'nome': 'Sem setor'};
      if (setoresIds.isNotEmpty) {
        final response = await http.get(
          Uri.parse('$_baseUrl/setores/${setoresIds.first}'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setorMap = {'id': data['id'], 'nome': data['nome']};
        }
      }

      // --- 3. Política do setor: SIMBÓLICO (API não tem endpoint ainda) ---
      final politicaMap = {
        'setorId': setorMap['id'],
        'toleranciaMinutos': 10,
        'exigeSelfie': 1,
        'raioMetros': 100,
      };

      // --- 4. Escala: SIMBÓLICO ---
      final hoje = DateTime.now();
      final escalaMock = List.generate(5, (i) {
        final dia = hoje.add(Duration(days: i));
        final dataStr =
            '${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}';
        return {
          'data': dataStr,
          'horaInicio': '08:00',
          'horaFim': '17:00',
        };
      });

      // --- 5. Marcações recentes: SIMBÓLICO ---
      final marcacoesMock = [
        {
          'dataHora': DateTime.now()
              .subtract(const Duration(hours: 8))
              .toIso8601String(),
          'tipo': 'ENTRADA',
        },
      ];

      // --- 6. Hora do servidor: REAL, pega do header HTTP da última resposta ---
      final horaServidorResponse = await http.get(Uri.parse('$_baseUrl/auth/login'));
      final headerData = horaServidorResponse.headers['date'];
      final horaServidor =
      headerData != null ? _parseHttpDate(headerData) : DateTime.now().toIso8601String();

      // --- Grava tudo em uma única transação (tudo ou nada) ---
      await _dbHelper.salvarSincronizacaoCompleta(
        funcionario: funcionarioMap,
        setor: setorMap,
        politicaSetor: politicaMap,
        escala: escalaMock,
        marcacoesRecentes: marcacoesMock,
        horaServidor: horaServidor,
      );

      return true;
    } catch (e) {
      // Qualquer erro no meio do processo: NÃO grava nada (a transação
      // do database_helper já garante isso), e retorna false.
      return false;
    }
  }

  String _parseHttpDate(String httpDate) {
    try {
      return HttpDate.parse(httpDate).toIso8601String();
    } catch (_) {
      return DateTime.now().toIso8601String();
    }
  }
}