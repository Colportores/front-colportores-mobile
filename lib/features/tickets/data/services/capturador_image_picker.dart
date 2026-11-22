import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/services/captura_de_foto.dart';

/// [CapturadorDeFoto] sobre `image_picker` (decisión de Cristian del 03/11 en #169: `image_picker` +
/// `flutter_image_compress`): la cámara nativa y la galería del teléfono, con los permisos del
/// sistema.
///
/// - Pide la foto **sin achicar**: la achica la `PoliticaDeCompresion` con el compresor, que decide
///   cuánto según la legibilidad del ticket (S42).
/// - Nunca lanza: un permiso negado es [CapturaSinPermiso]; cerrar sin elegir, [CapturaCancelada];
///   cualquier otra falla, [CapturaFallida]. Al log va solo el código de la falla, nunca la ruta ni
///   la foto (convenciones §7.5).
final class CapturadorImagePicker implements CapturadorDeFoto {
  CapturadorImagePicker({ImagePicker? picker, AppLogger? logger})
    : _picker = picker ?? ImagePicker(),
      _log = logger ?? AppLogger.instance;

  final ImagePicker _picker;
  final AppLogger _log;

  /// Los códigos de `image_picker` para un permiso negado (cámara o fotos).
  static const _codigosSinPermiso = {'camera_access_denied', 'photo_access_denied'};

  @override
  Future<ResultadoDeCaptura> sacarFoto() => _capturar(ImageSource.camera);

  @override
  Future<ResultadoDeCaptura> elegirDeLaGaleria() => _capturar(ImageSource.gallery);

  /// `image_picker` no abre los ajustes del sistema: la pantalla del depósito no ofrece «Abrir
  /// ajustes» y dice qué activar. Queda por el contrato del puerto (la vista 29 C lo usa con otro
  /// adaptador).
  @override
  Future<void> abrirLosAjustes() async {}

  Future<ResultadoDeCaptura> _capturar(ImageSource origen) async {
    try {
      final archivo = await _picker.pickImage(source: origen, requestFullMetadata: false);
      if (archivo == null) return const CapturaCancelada();
      final bytes = await archivo.readAsBytes();
      if (bytes.isEmpty) return const CapturaFallida();
      return FotoCapturada(bytes);
    } on PlatformException catch (e) {
      _log.info(LogModulo.db, 'TICKET_CAPTURA_FAIL', 'no se pudo conseguir la foto', {
        'codigo': e.code,
      });
      return _codigosSinPermiso.contains(e.code)
          ? const CapturaSinPermiso()
          : const CapturaFallida();
    } on Object catch (e) {
      _log.info(LogModulo.db, 'TICKET_CAPTURA_FAIL', 'no se pudo conseguir la foto', {
        'tipo': e.runtimeType.toString(),
      });
      return const CapturaFallida();
    }
  }
}
