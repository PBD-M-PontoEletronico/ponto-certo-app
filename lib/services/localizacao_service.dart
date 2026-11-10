import 'package:geolocator/geolocator.dart';

enum AcaoConfiguracao { nenhuma, localizacao, app }

class ResultadoLocalizacao {
  final double? latitude;
  final double? longitude;
  final String? problema; // o que fazer, quando falha
  final AcaoConfiguracao acao;

  ResultadoLocalizacao.ok(this.latitude, this.longitude)
      : problema = null,
        acao = AcaoConfiguracao.nenhuma;

  ResultadoLocalizacao.falha(this.problema,
      [this.acao = AcaoConfiguracao.nenhuma])
      : latitude = null,
        longitude = null;
}

/// GPS não depende de internet. O servidor recalcula a distância na
/// WEB-09: o app só usa o número para avisar o funcionário.
class LocalizacaoService {
  Future<ResultadoLocalizacao> capturar() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return ResultadoLocalizacao.falha(
          'O GPS está desligado. Ligue a localização do aparelho para '
              'conferir o perímetro.',
          AcaoConfiguracao.localizacao,
        );
      }

      var permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }
      if (permissao == LocationPermission.denied) {
        return ResultadoLocalizacao.falha(
          'Permissão de localização negada. Permita o acesso à localização '
              'para conferir o perímetro.',
        );
      }
      if (permissao == LocationPermission.deniedForever) {
        return ResultadoLocalizacao.falha(
          'A permissão de localização está bloqueada. Libere em '
              'Configurações do app.',
          AcaoConfiguracao.app,
        );
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return ResultadoLocalizacao.ok(pos.latitude, pos.longitude);
    } catch (e) {
      // Inclui timeout. Nunca derruba o app por causa do GPS.
      return ResultadoLocalizacao.falha(
        'Não foi possível obter a posição agora. Tente em um local aberto.',
      );
    }
  }

  static double distanciaMetros(
      double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

  Future<void> abrirConfiguracoes(AcaoConfiguracao acao) async {
    if (acao == AcaoConfiguracao.localizacao) {
      await Geolocator.openLocationSettings();
    } else if (acao == AcaoConfiguracao.app) {
      await Geolocator.openAppSettings();
    }
  }
}