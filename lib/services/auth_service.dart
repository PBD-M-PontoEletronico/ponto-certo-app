import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  ///  Colocar a url do web 1

  static const String _baseUrl = 'https://SUA-API-AQUI.com';

  /// Erro é sempre genérico, sem dizer se foi usuário ou senha

  Future<bool> login(String usuario, String senha) async {

    /// MODO SIMULADO — remover quando a API real (W01) estiver pronta

    const bool useMock = true;
    if (useMock) {
      await Future.delayed(const Duration(seconds: 1)); // simula rede
      if (usuario == 'admin' && senha == '1234') {
        await _storage.write(key: _tokenKey, value: 'token-fake-123');
        return true;
      }
      return false;
    }
    /// 🔧 FIM DO MODO SIMULADO

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'usuario': usuario, 'senha': senha}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'] as String?;
        if (token != null) {
          await _storage.write(key: _tokenKey, value: token);
          return true;
        }
      }
      return false;
    } catch (e) {
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

  /// Remove o token salvo (logout).
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
  }

  /// Chamado quando a API responde que o token expirou.
  /// Remove só o token, mantendo dados locais (fila de marcações etc).
  Future<void> clearExpiredToken() async {
    await _storage.delete(key: _tokenKey);
  }
}