import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/dispositivo/seguridad_dispositivo_canal.dart';
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
/// - «Abrir ajustes» (29C-07) lleva a la pantalla de la app en los ajustes del sistema, donde se da
///   el permiso de la cámara, por el canal nativo `colportores/seguridad_dispositivo`
///   (`abrirAjustesApp`, `MainActivity.kt`); `image_picker` no lo hace.
final class CapturadorImagePicker implements CapturadorDeFoto {
  CapturadorImagePicker({
    ImagePicker? picker,
    AppLogger? logger,
    MethodChannel? canalDeAjustes,
    this.tiempoMaximo = const Duration(seconds: 5),
  }) : _picker = picker ?? ImagePicker(),
       _log = logger ?? AppLogger.instance,
       _canalDeAjustes = canalDeAjustes ?? const MethodChannel(SeguridadDispositivoCanal.nombre);

  final ImagePicker _picker;
  final AppLogger _log;
  final MethodChannel _canalDeAjustes;

  /// Cuánto se espera a la plataforma al abrir los ajustes antes de darlo por fallido.
  final Duration tiempoMaximo;

  /// Los códigos de `image_picker` para un permiso negado (cámara o fotos).
  static const _codigosSinPermiso = {'camera_access_denied', 'photo_access_denied'};

  @override
  Future<ResultadoDeCaptura> sacarFoto() => _capturar(ImageSource.camera);

  @override
  Future<ResultadoDeCaptura> elegirDeLaGaleria() => _capturar(ImageSource.gallery);

  /// Abre los ajustes de la app (permisos). Nunca lanza: sin la pantalla (iOS, un equipo raro) o si
  /// la plataforma no contesta, no pasa nada y la pantalla sigue diciendo qué activar.
  @override
  Future<void> abrirLosAjustes() async {
    try {
      await _canalDeAjustes.invokeMethod<bool>('abrirAjustesApp').timeout(tiempoMaximo);
    } on Exception catch (e) {
      // `PlatformException`, `MissingPluginException` (iOS) o `TimeoutException`.
      _log.info(LogModulo.db, 'TICKET_AJUSTES_FAIL', 'no se pudieron abrir los ajustes', {
        'tipo': e.runtimeType.toString(),
      });
    }
  }

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
