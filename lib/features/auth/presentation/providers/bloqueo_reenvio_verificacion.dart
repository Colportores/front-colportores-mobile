import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cuánto queda bloqueado el reenvío del email de verificación cuando Supabase lo rechaza por
/// límite (decisión de Cristian, 29/09, #221): una hora fija desde el rechazo, porque Supabase no
/// informa cuánto falta.
const Duration bloqueoReenvioVerificacion = Duration(minutes: 60);

/// Instante hasta el que el reenvío del email de verificación está bloqueado por el límite de
/// Supabase (`null` si no lo está). Vive mientras corre la app, así que el bloqueo sobrevive a
/// salir y volver a la pantalla de verificación, pero **no** a reiniciar la app: la app no tiene
/// hoy un almacén local para datos que no sean secretos (pendiente en #221).
final bloqueoReenvioVerificacionProvider =
    NotifierProvider<BloqueoReenvioVerificacionNotifier, DateTime?>(
      BloqueoReenvioVerificacionNotifier.new,
    );

class BloqueoReenvioVerificacionNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  /// Registra un rechazo por límite ocurrido en [ahora].
  void bloquearDesde(DateTime ahora) => state = ahora.add(bloqueoReenvioVerificacion);
}
