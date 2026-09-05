import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _senhaController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _carregando = false;
  String? _erro;
  bool _senhaVisivel = false;

  @override
  void dispose() {
    _usuarioController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _fazerLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _carregando = true;
      _erro = null;
    });

    final sucesso = await _authService.login(
      _usuarioController.text.trim(),
      _senhaController.text,
    );

    if (!mounted) return;

    setState(() => _carregando = false);

    if (sucesso) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
      );
    } else {
      // Mensagem sempre genérica — não revela se foi usuário ou senha,
      // nem se foi problema de conexão com a API.
      setState(() {
        _erro = 'Usuário ou senha inválidos. Verifique e tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.access_time_filled, size: 64),
                  const SizedBox(height: 8),
                  const Text(
                    'PontoCerto',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _usuarioController,
                    decoration: const InputDecoration(
                      labelText: 'Usuário',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o usuário';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _senhaController,
                    obscureText: !_senhaVisivel,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _senhaVisivel
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() => _senhaVisivel = !_senhaVisivel);
                        },
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _fazerLogin(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Informe a senha';
                      }
                      return null;
                    },
                  ),
                  if (_erro != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _erro!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _carregando ? null : _fazerLogin,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _carregando
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Text('Entrar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}