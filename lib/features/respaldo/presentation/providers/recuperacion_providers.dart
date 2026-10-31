import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/servicio_recuperacion.dart';

/// El asistente de recuperación de datos en un teléfono sin datos (HU-SYNC-006, vista 34). Lo usa la
/// pantalla del asistente (#175).
///
/// **Hasta que llegue la integración I4 (#186) no hay motor que recuperar**: este valor responde
/// «no se pudo» a todo y la pantalla lo dice, con «Reintentar» y «Empezar sin recuperar». #186 lo
/// reemplaza por `ServicioRecuperacionMotor` sobre `SyncEngine.recover()`; al integrar las dos
/// ramas, este archivo se resuelve con el de #186.
final servicioRecuperacionProvider = Provider<ServicioRecuperacion>(
  (ref) => const _ServicioRecuperacionSinMotor(),
);

final class _ServicioRecuperacionSinMotor implements ServicioRecuperacion {
  const _ServicioRecuperacionSinMotor();

  @override
  Future<BusquedaRespaldo> buscar() async => const BusquedaFallida();

  @override
  Future<ResultadoRecuperacion> recuperar({
    required RespaldoEnDrive respaldo,
    required String password,
    void Function(ProgresoRecuperacion progreso)? alAvanzar,
    CancelacionRecuperacion? cancelar,
  }) async => const RecuperacionFallida();
}
