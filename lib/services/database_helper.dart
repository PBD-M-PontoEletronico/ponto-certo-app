import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Gerencia o banco de dados local (SQLite). Responsável por criar
/// as tabelas e fazer a gravação em transação (tudo ou nada) durante
/// a sincronização com a API.
class DatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'ponto_certo.db');
    return await openDatabase(
      path,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE funcionario (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        usuario TEXT NOT NULL,
        perfil TEXT NOT NULL,
        setoresIds TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE setor (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        latitude REAL,
        longitude REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE politica_setor (
        setorId TEXT PRIMARY KEY,
        raioMetros INTEGER NOT NULL,
        exigirSelfie INTEGER NOT NULL,
        politicaForaPerimetro TEXT NOT NULL,
        ignorarLocalizacao INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE escala (
        id TEXT PRIMARY KEY,
        nome TEXT,
        modelo TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE turno (
        id TEXT PRIMARY KEY,
        escalaId TEXT NOT NULL,
        horaInicio TEXT NOT NULL,
        horaFim TEXT NOT NULL,
        intervaloMinutos INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE marcacao_recente (
        dataHora TEXT PRIMARY KEY,
        tipo TEXT NOT NULL
      )
    ''');

    // Marcações batidas pelo funcionário neste aparelho (APP 03/04/05).
    // NÃO é limpa no logout — é trabalho real ainda não enviado ao
    // servidor (a fila de envio de verdade é escopo da APP 07).
    // horaAparelhoEpochMs, desvioRelogioMs, latitude e longitude viajam
    // junto com a marcação quando o envio existir (WEB-09).
    await db.execute('''
      CREATE TABLE metadata_sync (
        chave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE marcacao (
        id TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        dataHora TEXT NOT NULL,
        horaAparelhoEpochMs INTEGER,
        desvioRelogioMs INTEGER,
        latitude REAL,
        longitude REAL,
        setorId TEXT,
        metodoConfirmacao TEXT,
        digitalConfirmada INTEGER,
        selfiePath TEXT,
        selfieEnviada INTEGER NOT NULL DEFAULT 0,
        enviada INTEGER NOT NULL DEFAULT 0,
        usuarioId TEXT,
        offline INTEGER NOT NULL DEFAULT 0,
        statusServidor TEXT,
        motivoRecusa TEXT,
        erroEnvio TEXT,
        falhaDefinitiva INTEGER NOT NULL DEFAULT 0,
        tentativas INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _criarTabelasV8(db);
  }

  /// Banco local é só um cache reconstruído a cada sincronização —
  /// não guarda nada que precise ser preservado entre versões (com
  /// exceção da tabela `marcacao`, que só recebe ALTER, nunca DROP).
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS escala_dia');
      await db.execute('''
        CREATE TABLE escala (
          id TEXT PRIMARY KEY,
          nome TEXT,
          modelo TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE turno (
          id TEXT PRIMARY KEY,
          escalaId TEXT NOT NULL,
          horaInicio TEXT NOT NULL,
          horaFim TEXT NOT NULL,
          intervaloMinutos INTEGER NOT NULL
        )
      ''');
    }

    if (oldVersion < 3) {
      await db.execute('DROP TABLE IF EXISTS politica_setor');
      await db.execute('''
        CREATE TABLE politica_setor (
          setorId TEXT PRIMARY KEY,
          raioMetros INTEGER NOT NULL,
          exigirSelfie INTEGER NOT NULL,
          politicaForaPerimetro TEXT NOT NULL,
          ignorarLocalizacao INTEGER NOT NULL
        )
      ''');
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS marcacao (
          id TEXT PRIMARY KEY,
          tipo TEXT NOT NULL,
          dataHora TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 5) {
      // marcacao guarda trabalho real do funcionário: ALTER, nunca DROP.
      await db.execute(
          'ALTER TABLE marcacao ADD COLUMN horaAparelhoEpochMs INTEGER');
      await db.execute(
          'ALTER TABLE marcacao ADD COLUMN desvioRelogioMs INTEGER');
    }

    if (oldVersion < 6) {
      // setor é cache: só ganha as colunas (preenchidas na próxima
      // sincronização). marcacao é trabalho real: ALTER, nunca DROP.
      await db.execute('ALTER TABLE setor ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE setor ADD COLUMN longitude REAL');
      await db.execute('ALTER TABLE marcacao ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE marcacao ADD COLUMN longitude REAL');
    }

    if (oldVersion < 7) {
      await db.execute('ALTER TABLE marcacao ADD COLUMN setorId TEXT');
      await db.execute('ALTER TABLE marcacao ADD COLUMN metodoConfirmacao TEXT');
      await db.execute('ALTER TABLE marcacao ADD COLUMN digitalConfirmada INTEGER');
      await db.execute('ALTER TABLE marcacao ADD COLUMN selfiePath TEXT');
      await db.execute(
          'ALTER TABLE marcacao ADD COLUMN selfieEnviada INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE marcacao ADD COLUMN enviada INTEGER NOT NULL DEFAULT 0');
    }

    if (oldVersion < 8) {
      // APP 07 a 12. marcacao e trabalho real: so ALTER, nunca DROP.
      await db.execute('ALTER TABLE marcacao ADD COLUMN usuarioId TEXT');
      await db.execute(
          'ALTER TABLE marcacao ADD COLUMN offline INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE marcacao ADD COLUMN statusServidor TEXT');
      await db.execute('ALTER TABLE marcacao ADD COLUMN motivoRecusa TEXT');
      await db.execute('ALTER TABLE marcacao ADD COLUMN erroEnvio TEXT');
      await db.execute(
          'ALTER TABLE marcacao ADD COLUMN falhaDefinitiva INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE marcacao ADD COLUMN tentativas INTEGER NOT NULL DEFAULT 0');
      await _criarTabelasV8(db);
    }
  }

  /// cache_json guarda respostas da API para funcionar offline (agenda,
  /// espelho, pedidos, lista do modo relogio). solicitacao_local e a fila de
  /// justificativas/ajustes feitos sem rede (APP 11/12).
  Future<void> _criarTabelasV8(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cache_json (
        chave TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        atualizadoEm TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS solicitacao_local (
        id TEXT PRIMARY KEY,
        usuarioId TEXT,
        tipo TEXT NOT NULL,
        data TEXT NOT NULL,
        ocorrencia TEXT,
        tipoMarcacao TEXT,
        horaPretendida TEXT,
        motivo TEXT NOT NULL,
        anexoPath TEXT,
        criadoEm TEXT NOT NULL,
        enviada INTEGER NOT NULL DEFAULT 0,
        erroEnvio TEXT,
        falhaDefinitiva INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Apaga os dados de CACHE locais (usado no logout). A tabela
  /// `marcacao` é preservada de propósito — são marcações reais
  /// ainda não enviadas ao servidor.
  Future<void> limparTudo() async {
    final db = await database;
    await db.delete('funcionario');
    await db.delete('setor');
    await db.delete('politica_setor');
    await db.delete('escala');
    await db.delete('turno');
    await db.delete('marcacao_recente');
    await db.delete('metadata_sync');
    await db.delete('cache_json');
  }

  /// Salva um snapshot completo de sincronização como uma ÚNICA
  /// transação: ou tudo é gravado, ou nada é.
  /// [politicaSetor] pode ser null quando o funcionário não tem
  /// nenhum setor ativo no momento — nesse caso, nada é gravado
  /// nessa tabela.
  Future<void> salvarSincronizacaoCompleta({
    required Map<String, dynamic> funcionario,
    required List<Map<String, dynamic>> setores,
    required Map<String, dynamic>? politicaSetor,
    required List<Map<String, dynamic>> escalas,
    required List<Map<String, dynamic>> turnos,
    required List<Map<String, dynamic>> marcacoesRecentes,
    required String horaServidor,
  }) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('funcionario');
      await txn.delete('setor');
      await txn.delete('politica_setor');
      await txn.delete('escala');
      await txn.delete('turno');
      await txn.delete('marcacao_recente');

      await txn.insert('funcionario', funcionario);

      for (final setor in setores) {
        await txn.insert('setor', setor);
      }

      if (politicaSetor != null) {
        await txn.insert('politica_setor', politicaSetor);
      }

      for (final escala in escalas) {
        await txn.insert('escala', escala);
      }

      for (final turno in turnos) {
        await txn.insert('turno', turno);
      }

      for (final marcacao in marcacoesRecentes) {
        await txn.insert('marcacao_recente', marcacao);
      }

      await txn.insert(
        'metadata_sync',
        {'chave': 'ultima_sincronizacao', 'valor': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.insert(
        'metadata_sync',
        {'chave': 'hora_servidor', 'valor': horaServidor},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Grava uma marcação de ponto batida agora pelo funcionário.
  Future<void> inserirMarcacao(Map<String, dynamic> marcacao) async {
    final db = await database;
    await db.insert('marcacao', marcacao);
  }

  // ---------------------------------------------------------------
  // Fila de envio das marcacoes (APP 07)
  // ---------------------------------------------------------------

  /// Marcacoes que ainda nao subiram. Por padrao nao inclui as que o
  /// servidor recusou de forma definitiva (403/409/400): essas so voltam
  /// para a fila quando o funcionario pede "tentar de novo".
  Future<List<Map<String, dynamic>>> getMarcacoesNaoEnviadas(
      {bool incluirFalhas = false}) async {
    final db = await database;
    return await db.query(
      'marcacao',
      where: incluirFalhas ? 'enviada = 0' : 'enviada = 0 AND falhaDefinitiva = 0',
      orderBy: 'dataHora ASC',
    );
  }

  /// Quantas marcacoes ainda nao foram aceitas pelo servidor.
  Future<int> contarNaoEnviadas() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM marcacao WHERE enviada = 0');
    return (r.first['n'] as int?) ?? 0;
  }

  /// Marcacoes que falharam e guardam o motivo.
  Future<List<Map<String, dynamic>>> getMarcacoesComFalha() async {
    final db = await database;
    return await db.query(
      'marcacao',
      where: 'enviada = 0 AND erroEnvio IS NOT NULL',
      orderBy: 'dataHora ASC',
    );
  }

  /// O servidor aceitou: sai da fila e guarda a situacao que ele deu.
  Future<void> registrarEnvioOk(
    String id, {
    String? statusServidor,
    String? motivoRecusa,
    bool comSelfie = false,
  }) async {
    final db = await database;
    await db.update(
      'marcacao',
      {
        'enviada': 1,
        'statusServidor': statusServidor,
        'motivoRecusa': motivoRecusa,
        'erroEnvio': null,
        'falhaDefinitiva': 0,
        if (comSelfie) 'selfieEnviada': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Falha de envio: guarda o motivo e conta a tentativa. [definitiva]
  /// (erro real, nao de rede) tira da fila automatica.
  Future<void> registrarFalhaEnvio(String id, String motivo,
      {required bool definitiva}) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE marcacao SET erroEnvio = ?, falhaDefinitiva = ?, '
      'tentativas = tentativas + 1 WHERE id = ?',
      [motivo, definitiva ? 1 : 0, id],
    );
  }

  /// "Tentar de novo": devolve as falhas definitivas para a fila.
  Future<void> reabrirFalhas() async {
    final db = await database;
    await db.update('marcacao', {'falhaDefinitiva': 0},
        where: 'enviada = 0 AND falhaDefinitiva = 1');
  }

  /// Marcacoes de hoje de um funcionario especifico (modo relogio).
  Future<List<Map<String, dynamic>>> getMarcacoesHojeDoFuncionario(
      String usuarioId) async {
    final db = await database;
    final h = DateTime.now();
    final prefixo =
        '${h.year.toString().padLeft(4, '0')}-${h.month.toString().padLeft(2, '0')}-${h.day.toString().padLeft(2, '0')}';
    return await db.query(
      'marcacao',
      where: 'dataHora LIKE ? AND usuarioId = ?',
      whereArgs: ['$prefixo%', usuarioId],
      orderBy: 'dataHora ASC',
    );
  }

  // ---------------------------------------------------------------
  // Cache de respostas da API (funciona offline)
  // ---------------------------------------------------------------

  Future<void> salvarCache(String chave, Object json) async {
    final db = await database;
    await db.insert(
      'cache_json',
      {
        'chave': chave,
        'json': jsonEncode(json),
        'atualizadoEm': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// null = nada guardado para essa chave.
  Future<dynamic> lerCache(String chave) async {
    final db = await database;
    final r = await db.query('cache_json', where: 'chave = ?', whereArgs: [chave]);
    if (r.isEmpty) return null;
    try {
      return jsonDecode(r.first['json'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> dataDoCache(String chave) async {
    final db = await database;
    final r = await db.query('cache_json', where: 'chave = ?', whereArgs: [chave]);
    if (r.isEmpty) return null;
    return DateTime.tryParse(r.first['atualizadoEm'] as String);
  }

  // ---------------------------------------------------------------
  // Fila de justificativas e ajustes (APP 11/12)
  // ---------------------------------------------------------------

  Future<void> inserirSolicitacaoLocal(Map<String, dynamic> s) async {
    final db = await database;
    await db.insert('solicitacao_local', s);
  }

  /// Pedidos ainda na fila deste funcionario (nunca de outro usuario que
  /// tenha usado o aparelho antes).
  Future<List<Map<String, dynamic>>> getSolicitacoesLocais(String? usuarioId) async {
    final db = await database;
    return await db.query(
      'solicitacao_local',
      where: usuarioId == null ? 'enviada = 0' : 'enviada = 0 AND usuarioId = ?',
      whereArgs: usuarioId == null ? null : [usuarioId],
      orderBy: 'criadoEm ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getSolicitacoesParaEnviar(String? usuarioId) async {
    final db = await database;
    return await db.query(
      'solicitacao_local',
      where: usuarioId == null
          ? 'enviada = 0 AND falhaDefinitiva = 0'
          : 'enviada = 0 AND falhaDefinitiva = 0 AND usuarioId = ?',
      whereArgs: usuarioId == null ? null : [usuarioId],
      orderBy: 'criadoEm ASC',
    );
  }

  Future<void> removerSolicitacaoLocal(String id) async {
    final db = await database;
    await db.delete('solicitacao_local', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> registrarFalhaSolicitacao(String id, String motivo,
      {required bool definitiva}) async {
    final db = await database;
    await db.update(
      'solicitacao_local',
      {'erroEnvio': motivo, 'falhaDefinitiva': definitiva ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reabrirSolicitacoesComFalha() async {
    final db = await database;
    await db.update('solicitacao_local', {'falhaDefinitiva': 0},
        where: 'enviada = 0 AND falhaDefinitiva = 1');
  }

  /// Marcações batidas hoje, em ordem cronológica.
  Future<List<Map<String, dynamic>>> getMarcacoesHoje() async {
    final db = await database;
    final hoje = DateTime.now();
    final prefixoHoje =
        '${hoje.year.toString().padLeft(4, '0')}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
    return await db.query(
      'marcacao',
      where: 'dataHora LIKE ? AND (usuarioId IS NULL OR usuarioId = (SELECT id FROM funcionario LIMIT 1))',
      whereArgs: ['$prefixoHoje%'],
      orderBy: 'dataHora ASC',
    );
  }

  /// Guarda o último desvio medido (aparelho - servidor, em ms).
  /// Fica em metadata_sync, que é limpa no logout: o desvio é
  /// remedido a cada login.
  Future<void> salvarDesvioRelogio(int desvioMs) async {
    final db = await database;
    await db.insert(
      'metadata_sync',
      {'chave': 'desvio_relogio_ms', 'valor': desvioMs.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// null = nunca conversou com o servidor (desvio desconhecido).
  Future<int?> getDesvioRelogioMs() async {
    final db = await database;
    final r = await db.query(
      'metadata_sync',
      where: 'chave = ?',
      whereArgs: ['desvio_relogio_ms'],
    );
    if (r.isEmpty) return null;
    return int.tryParse(r.first['valor'] as String);
  }

  Future<DateTime?> getUltimaSincronizacao() async {
    final db = await database;
    final result = await db.query(
      'metadata_sync',
      where: 'chave = ?',
      whereArgs: ['ultima_sincronizacao'],
    );
    if (result.isEmpty) return null;
    return DateTime.tryParse(result.first['valor'] as String);
  }

  Future<Map<String, dynamic>?> getFuncionario() async {
    final db = await database;
    final result = await db.query('funcionario', limit: 1);
    return result.isEmpty ? null : result.first;
  }

  Future<List<Map<String, dynamic>>> getSetores() async {
    final db = await database;
    return await db.query('setor');
  }

  Future<Map<String, dynamic>?> getPoliticaSetor() async {
    final db = await database;
    final result = await db.query('politica_setor', limit: 1);
    return result.isEmpty ? null : result.first;
  }

  Future<List<Map<String, dynamic>>> getEscalas() async {
    final db = await database;
    return await db.query('escala');
  }

  Future<List<Map<String, dynamic>>> getTurnos() async {
    final db = await database;
    return await db.query('turno');
  }

  Future<List<Map<String, dynamic>>> getMarcacoesRecentes() async {
    final db = await database;
    return await db.query('marcacao_recente', orderBy: 'dataHora DESC');
  }
}