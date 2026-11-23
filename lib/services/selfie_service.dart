import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

enum ResultadoSelfie { capturada, permissaoNegada, cancelada, falhaCamera }

class SelfieCapturada {
  final String? caminho;
  final ResultadoSelfie resultado;
  final String? mensagem;

  SelfieCapturada.ok(this.caminho)
      : resultado = ResultadoSelfie.capturada,
        mensagem = null;

  SelfieCapturada.falha(this.resultado, this.mensagem) : caminho = null;
}

/// Tira a selfie exigida pela política do setor (APP 06): abre a câmera
/// frontal, comprime a imagem e grava no aparelho. O envio pro servidor é
/// separado (ver MarcacaoService) — se falhar, só a selfie é tentada de
/// novo, sem reenviar a marcação.
class SelfieService {
  final ImagePicker _picker = ImagePicker();

  Future<SelfieCapturada> capturarEComprimir() async {
    XFile? foto;
    try {
      foto = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
      );
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied') {
        return SelfieCapturada.falha(
          ResultadoSelfie.permissaoNegada,
          'Permissão da câmera negada. Ative o acesso à câmera nas '
              'configurações do aparelho para registrar a marcação neste setor.',
        );
      }
      return SelfieCapturada.falha(
        ResultadoSelfie.falhaCamera,
        'Não foi possível abrir a câmera agora. Tente de novo.',
      );
    } catch (e) {
      return SelfieCapturada.falha(
        ResultadoSelfie.falhaCamera,
        'Não foi possível abrir a câmera agora. Tente de novo.',
      );
    }

    if (foto == null) {
      return SelfieCapturada.falha(ResultadoSelfie.cancelada, null);
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final destino =
          '${dir.path}/selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final comprimido = await FlutterImageCompress.compressAndGetFile(
        foto.path,
        destino,
        quality: 60,
        minWidth: 720,
        minHeight: 720,
      );

      return SelfieCapturada.ok(comprimido?.path ?? foto.path);
    } catch (e) {
      // Não conseguiu comprimir: melhor guardar a original do que perder
      // a evidência da marcação.
      return SelfieCapturada.ok(foto.path);
    }
  }
}