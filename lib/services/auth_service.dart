import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _nomeKey = 'auth_nome';
  static const _perfilKey = 'auth_perfil';
  static const _empresaIdKey = 'auth_empresa_id';


  static const String _baseUrl = 'http://192.168.1.121:8080';

  //  Enquanto a API não estiver rodando, deixar true pra testar o fluxo.
  // Quando a API  estiver funcionando , mudar para false.
  static const bool useMock = false;

  /// Tenta fazer login. Retorna true se deu certo, false se falhou.
  /// Erro é sempre genérico, sem dizer se foi usuário ou senha.
  Future<bool> login(String usuario, String senha) async {
    if (useMock) {
      await Future.delayed(const Duration(seconds: 1));
      if (usuario == 'admin' && senha == '1234') {
        await _storage.write(key: _tokenKey, value: 'token-fake-123');
        await _storage.write(key: _nomeKey, value: 'Usuário Teste');
        await _storage.write(key: _perfilKey, value: 'SUPERADMIN');
        return true;
      }
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'usuario': usuario, 'senha': senha}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'] as String?;
        if (token != null) {
          await _storage.write(key: _tokenKey, value: token);
          await _storage.write(key: _nomeKey, value: data['nome'] ?? '');
          await _storage.write(key: _perfilKey, value: data['perfil'] ?? '');
          if (data['empresaId'] != null) {
            await _storage.write(
              key: _empresaIdKey,
              value: data['empresaId'].toString(),
            );
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      // Falha de rede, timeout, API fora do ar etc. — erro genérico
      return false;
    }
  }

  /// Verifica se já existe um token salvo (sessão ativa offline).
  Future<bool> hasSession() async {
    final token = await _storage.read(key: _tokenKey);
    return token != null && token.isNotEmpty;
  }

  /// Retorna o token salvo, ou null se não houver.
  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Retorna o nome salvo do usuário logado.
  Future<String?> getNome() async {
    return await _storage.read(key: _nomeKey);
  }

  /// Retorna o perfil salvo (SUPERADMIN, RH_ADMIN, etc).
  Future<String?> getPerfil() async {
    return await _storage.read(key: _perfilKey);
  }

  /// Remove todos os dados de sessão salvos (logout).
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _nomeKey);
    await _storage.delete(key: _perfilKey);
    await _storage.delete(key: _empresaIdKey);
  }

  /// Chamado quando a API responde que o token expirou (401/403).
  /// Remove só o token, mantendo dados locais (fila de marcações etc).
  Future<void> clearExpiredToken() async {
    await _storage.delete(key: _tokenKey);
  }
}