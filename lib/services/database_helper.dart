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
      version: 5,
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
        nome TEXT NOT NULL
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

    // Marcações batidas pelo funcionário neste aparelho (APP 03/04).
    // NÃO é limpa no logout — é trabalho real ainda não enviado ao
    // servidor (a fila de envio de verdade é escopo da APP 07).
    // horaAparelhoEpochMs e desvioRelogioMs viajam junto com a marcação
    // quando o envio existir (WEB-09).
    await db.execute('''
      CREATE TABLE marcacao (
        id TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        dataHora TEXT NOT NULL,
        horaAparelhoEpochMs INTEGER,
        desvioRelogioMs INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE metadata_sync (
        chave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');
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

  /// Marcações batidas hoje, em ordem cronológica.
  Future<List<Map<String, dynamic>>> getMarcacoesHoje() async {
    final db = await database;
    final hoje = DateTime.now();
    final prefixoHoje =
        '${hoje.year.toString().padLeft(4, '0')}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
    return await db.query(
      'marcacao',
      where: 'dataHora LIKE ?',
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