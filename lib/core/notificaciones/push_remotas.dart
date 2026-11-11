import 'dart:async';

/// Un mensaje de FCM tal como llegó, sin interpretar: solo el mapa `data` (HU-NOT-003, R-NO02: el
/// payload es el tipo de evento y UUIDs, nunca texto).
///
/// Quien lo recibe lo pasa por `RecibirPushRemotaUseCase`; este tipo no decide nada.
final class MensajePush {
  const MensajePush(this.datos);

  /// El `data` del mensaje. Puede traer cualquier cosa (un defecto del servidor incluido): se lee
  /// siempre como no confiable.
  final Map<String, Object?> datos;
}

/// Las push remotas que llegan al teléfono (HU-NOT-003, ADR-014).
///
/// Puerto en Dart puro. La implementación de producción es `PushRemotasFirebase`, sobre
/// `firebase_messaging` (#614); la de los tests y la de la app sin Firebase (un build sin su archivo
/// de configuración) es `PushRemotasEnMemoria`, que no recibe nada.
///
/// Un mensaje llega por **una sola** de las tres vías:
/// - [conLaAppAbierta]: la app está al frente (la UI muestra un aviso sutil, 24C·08);
/// - [tocadas]: la app estaba en segundo plano y la persona tocó la notificación del sistema;
/// - [tomarLaQueAbrioLaApp]: la app estaba cerrada y la abrió ese toque.
abstract interface class PushRemotas {
  /// Los mensajes que llegan con la app al frente. De difusión: sin oyente se pierden, como el
  /// evento de la plataforma.
  Stream<MensajePush> get conLaAppAbierta;

  /// Los toques sobre una notificación del sistema con la app en segundo plano.
  Stream<MensajePush> get tocadas;

  /// El mensaje cuyo toque abrió la app desde cerrada, **una sola vez**: la segunda llamada devuelve
  /// `null`. `null` también si la app se abrió de otra manera.
  Future<MensajePush?> tomarLaQueAbrioLaApp();
}
