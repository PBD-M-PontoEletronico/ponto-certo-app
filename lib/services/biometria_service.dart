import 'package:local_auth/local_auth.dart';

enum ResultadoBiometria { autorizado, cancelado, indisponivel, erro }

/// Desbloqueio antes de registrar a marcação (APP 06). Pede biometria do
/// aparelho (digital ou rosto); se o aparelho não tiver biometria
/// configurada, o próprio sistema operacional cai sozinho na tela de
/// desbloqueio do aparelho (PIN/padrão/senha) — é assim que o registro
/// nunca fica impossível por falta de biometria configurada.
class BiometriaService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<ResultadoBiometria> autenticar() async {
    try {
      final suportado = await _auth.isDeviceSupported();
      if (!suportado) {
        // Aparelho sem nenhum bloqueio de tela configurado: não tem como
        // pedir confirmação nenhuma. Não pode travar o registro por isso.
        return ResultadoBiometria.indisponivel;
      }

      final autorizado = await _auth.authenticate(
        localizedReason: 'Confirme para registrar a marcação',
        options: const AuthenticationOptions(
          biometricOnly: false, // permite cair no PIN/senha do aparelho
          stickyAuth: true,
        ),
      );
      return autorizado ? ResultadoBiometria.autorizado : ResultadoBiometria.cancelado;
    } catch (e) {
      return ResultadoBiometria.erro;
    }
  }
}