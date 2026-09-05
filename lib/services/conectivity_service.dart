import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  /// Verifica agora se há conexão com a internet.
  Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Stream que avisa sempre que o status de conexão mudar.
  /// Útil pra atualizar o banner de "offline" em tempo real.
  Stream<bool> onConnectivityChanged() {
    return _connectivity.onConnectivityChanged.map(
          (result) => !result.contains(ConnectivityResult.none),
    );
  }
}