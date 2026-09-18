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
      version: 3,
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

    // Escala real: modelo + turnos (não é mais "5 dias com hora fixa").
    // A projeção dia-a-dia completa depende de um endpoint futuro
    // (/me/agenda), ainda não implementado no backend.
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

    await db.execute('''
      CREATE TABLE metadata_sync (
        chave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');
  }

  /// Banco local é só um cache reconstruído a cada sincronização —
  /// não guarda nada que precise ser preservado entre versões. Por
  /// isso toda migração aqui é só dropar as tabelas que mudaram e
  /// recriar do zero.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // A tabela antiga 'escala_dia' (mock de 5 dias fixos) foi substituída
      // por 'escala' + 'turno', que refletem o modelo real da API.
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
      // politica_setor passou a guardar os campos reais da API em vez
      // do mock (toleranciaMinutos saiu; entraram politicaForaPerimetro
      // e ignorarLocalizacao).
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
  }

  /// Apaga TODOS os dados locais (usado no logout).
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