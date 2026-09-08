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
      version: 1,
      onCreate: _onCreate,
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
        toleranciaMinutos INTEGER NOT NULL,
        exigeSelfie INTEGER NOT NULL,
        raioMetros INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE escala_dia (
        data TEXT PRIMARY KEY,
        horaInicio TEXT NOT NULL,
        horaFim TEXT NOT NULL
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

  /// Apaga TODOS os dados locais (usado no logout).
  Future<void> limparTudo() async {
    final db = await database;
    await db.delete('funcionario');
    await db.delete('setor');
    await db.delete('politica_setor');
    await db.delete('escala_dia');
    await db.delete('marcacao_recente');
    await db.delete('metadata_sync');
  }

  /// Salva um snapshot completo de sincronização como uma ÚNICA
  /// transação: ou tudo é gravado, ou nada é (em caso de erro no
  /// meio do processo, a transação é revertida automaticamente).
  Future<void> salvarSincronizacaoCompleta({
    required Map<String, dynamic> funcionario,
    required Map<String, dynamic> setor,
    required Map<String, dynamic> politicaSetor,
    required List<Map<String, dynamic>> escala,
    required List<Map<String, dynamic>> marcacoesRecentes,
    required String horaServidor,
  }) async {
    final db = await database;

    await db.transaction((txn) async {
      // Limpa dados antigos antes de gravar os novos
      await txn.delete('funcionario');
      await txn.delete('setor');
      await txn.delete('politica_setor');
      await txn.delete('escala_dia');
      await txn.delete('marcacao_recente');

      await txn.insert('funcionario', funcionario);
      await txn.insert('setor', setor);
      await txn.insert('politica_setor', politicaSetor);

      for (final dia in escala) {
        await txn.insert('escala_dia', dia);
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

  /// Retorna a data/hora da última sincronização bem-sucedida, ou null
  /// se nunca sincronizou.
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

  Future<Map<String, dynamic>?> getSetor() async {
    final db = await database;
    final result = await db.query('setor', limit: 1);
    return result.isEmpty ? null : result.first;
  }

  Future<Map<String, dynamic>?> getPoliticaSetor() async {
    final db = await database;
    final result = await db.query('politica_setor', limit: 1);
    return result.isEmpty ? null : result.first;
  }

  Future<List<Map<String, dynamic>>> getEscala() async {
    final db = await database;
    return await db.query('escala_dia', orderBy: 'data ASC');
  }

  Future<List<Map<String, dynamic>>> getMarcacoesRecentes() async {
    final db = await database;
    return await db.query('marcacao_recente', orderBy: 'dataHora DESC');
  }
}