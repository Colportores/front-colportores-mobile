import '../../../../core/error/failure.dart';

/// Puerto: el atajo de la vista 03 «Activar GPS».
///
/// Según [MotivoSinGps]: pide el permiso de ubicación si todavía se puede pedir, y si no (negado
/// para siempre, o la ubicación del teléfono está apagada) abre el ajuste del sistema donde se
/// activa. La pantalla vuelve a leer el GPS cuando el colportor regresa a la app.
abstract interface class ActivadorGps {
  Future<void> activar(MotivoSinGps motivo);
}
