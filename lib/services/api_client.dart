import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import '../screens/login_screen.dart';
import 'auth_service.dart';

/// Wrapper em torno do http para chamadas que exigem autenticação.
/// Centraliza o envio do token e o tratamento de sessão expirada,
/// para não repetir essa lógica em cada tela/service que chamar a API.
class ApiClient {
  final AuthService _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> get(Uri url) async {
    final response = await http.get(url, headers: await _authHeaders());
    await _tratarRespostaExpirada(response);
    return response;
  }

  Future<http.Response> post(Uri url, {Object? body}) async {
    final response = await http.post(
      url,
      headers: await _authHeaders(),
      body: body,
    );
    await _tratarRespostaExpirada(response);
    return response;
  }

  /// Se a API responder 401 (não autenticado) ou 403 (sem permissão
  /// por token inválido/expirado), limpa o token local e força
  /// o usuário de volta pro login — sem apagar dados locais como
  /// a fila de marcações pendentes.
  Future<void> _tratarRespostaExpirada(http.Response response) async {
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _authService.clearExpiredToken();

      final context = navigatorKey.currentState?.overlay?.context;
      if (context != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
        );
      }
    }
  }
}