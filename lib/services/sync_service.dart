import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'conectivity_service.dart' show ConnectivityService;
import 'database_helper.dart';

/// Orquestra a sincronização de dados locais (APP 02).
/// Busca dados reais da API quando existem, e usa valores simbólicos
/// (mock) só para o que ainda não foi implementado no backend
/// (marcações recentes).
class SyncService {
  final AuthService _authService = AuthService();
  final ConnectivityService _connectivityService = ConnectivityService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const String _baseUrl = 'http://192.168.1.121:8080';

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
      final headers = {'Authorization': 'Bearer $token'};

      // --- 1. Buscar as alocações do próprio funcionário logado ---
      final hoje = DateTime.now();
      final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);

      List<Map<String, dynamic>> setoresMaps = [];
      final escalasPorId = <String, Map<String, dynamic>>{};
      final turnosPorId = <String, Map<String, dynamic>>{};
      Map<String, dynamic>? politicaMap;

      String funcionarioId = '';
      String matricula = ''; // ⚠️ buscado mas não persistido ainda
      String cargo = '';     // ⚠️ buscado mas não persistido ainda

      final responseAlocacoes = await http.get(
        Uri.parse('$_baseUrl/me/alocacoes'),
        headers: headers,
      );

      if (responseAlocacoes.statusCode == 200) {
        final lista = jsonDecode(responseAlocacoes.body) as List;

        if (lista.isNotEmpty) {
          final primeiraAlocacao = lista.first as Map<String, dynamic>;
          final usuarioInfo = primeiraAlocacao['usuario'] as Map<String, dynamic>;
          funcionarioId = usuarioInfo['id'] as String? ?? '';
          matricula = usuarioInfo['matricula'] as String? ?? '';
          cargo = usuarioInfo['cargo'] as String? ?? '';
        }

        for (final item in lista) {
          final dataInicioStr = item['dataInicio'] as String?;
          final dataFimStr = item['dataFim'] as String?;
          if (dataInicioStr == null || dataFimStr == null) continue;

          final dataInicio = DateTime.tryParse(dataInicioStr);
          final dataFim = DateTime.tryParse(dataFimStr);
          if (dataInicio == null || dataFim == null) continue;

          // Alocação "ativa hoje": dataInicio <= hoje <= dataFim
          // (dataFim agora é sempre obrigatória — ciclos mensais).
          final ativa = !hojeSemHora.isBefore(dataInicio) &&
              !hojeSemHora.isAfter(dataFim);
          if (!ativa) continue;

          final setor = item['setor'] as Map<String, dynamic>;
          setoresMaps.add({'id': setor['id'], 'nome': setor['nome']});

          // Política real: usa a do primeiro setor ativo encontrado.
          // Funcionário alocado em mais de um setor só guarda uma
          // política local por enquanto — revisar se isso virar
          // problema prático (ex: bater ponto em setor diferente
          // do "principal").
          politicaMap ??= {
            'setorId': setor['id'] as String,
            'raioMetros': setor['raioMetros'] as int,
            'exigirSelfie': (setor['exigirSelfie'] as bool) ? 1 : 0,
            'politicaForaPerimetro': setor['politicaForaPerimetro'] as String,
            'ignorarLocalizacao': (setor['ignorarLocalizacao'] as bool) ? 1 : 0,
          };

          final escala = item['escala'] as Map<String, dynamic>?;
          if (escala != null) {
            final escalaId = escala['id'] as String;
            escalasPorId[escalaId] = {
              'id': escalaId,
              'nome': escala['nome'] ?? '',
              'modelo': escala['modelo'] ?? '',
            };

            final turnos = escala['turnos'] as List? ?? [];
            for (final turno in turnos) {
              final turnoId = turno['id'] as String;
              turnosPorId[turnoId] = {
                'id': turnoId,
                'escalaId': escalaId,
                'horaInicio': turno['horaInicio'] ?? '',
                'horaFim': turno['horaFim'] ?? '',
                'intervaloMinutos': turno['intervaloMinutos'] ?? 0,
              };
            }
          }
        }
      }
      // Se der 401/403 aqui: algo mudou na segurança do endpoint, avisar.

      final nome = await _authService.getNome() ?? '';
      final perfil = await _authService.getPerfil() ?? '';
      final usuarioLogin = await _authService.getUsuario() ?? '';

      final setoresIds = setoresMaps.map((s) => s['id'] as String).toList();

      final funcionarioMap = {
        'id': funcionarioId,
        'nome': nome,
        'usuario': usuarioLogin,
        'perfil': perfil,
        'setoresIds': setoresIds.join(','),
      };

      // --- 2. Marcações recentes: SIMBÓLICO (endpoint não existe) ---
      final marcacoesMock = [
        {
          'dataHora': DateTime.now()
              .subtract(const Duration(hours: 8))
              .toIso8601String(),
          'tipo': 'ENTRADA',
        },
      ];

      // --- 3. Hora do servidor: pega do header HTTP de uma chamada
      // incidental ao /auth/login (gambiarra — ideal seria um GET /hora) ---
      final horaServidorResponse = await http.get(Uri.parse('$_baseUrl/auth/login'));
      final headerData = horaServidorResponse.headers['date'];
      final horaServidor =
      headerData != null ? _parseHttpDate(headerData) : DateTime.now().toIso8601String();

      // --- Grava tudo em uma única transação (tudo ou nada) ---
      await _dbHelper.salvarSincronizacaoCompleta(
        funcionario: funcionarioMap,
        setores: setoresMaps,
        politicaSetor: politicaMap,
        escalas: escalasPorId.values.toList(),
        turnos: turnosPorId.values.toList(),
        marcacoesRecentes: marcacoesMock,
        horaServidor: horaServidor,
      );

      return true;
    } catch (e, stack) {
      print('=== ERRO NA SINCRONIZAÇÃO ===');
      print(e);
      print(stack);
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