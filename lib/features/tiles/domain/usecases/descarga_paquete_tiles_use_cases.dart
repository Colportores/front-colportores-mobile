import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/paquete_tiles.dart';
import '../services/descargador_paquetes_tiles.dart';

/// Parámetros de [DescargarPaqueteTilesUseCase].
final class DescargarPaqueteTilesParams extends Equatable {
  const DescargarPaqueteTilesParams({
    required this.paquete,
    this.permitirDatosMoviles = false,
    this.esperarConexion = false,
  });

  final PaqueteTiles paquete;

  /// El override manual de HU-SYNC-010: descargar aunque no haya Wi-Fi.
  final bool permitirDatosMoviles;

  /// Sin conexión permitida en este momento, la descarga queda en cola y arranca sola con la
  /// primera conexión que sirva, en vez de fallar. «Descargar mapa» lo pide junto con
  /// [permitirDatosMoviles] (arranca con la primera conexión que vuelva, aunque sea de datos
  /// móviles); lo que la app baja sola lo pide sin [permitirDatosMoviles] (espera el Wi-Fi).
  final bool esperarConexion;

  @override
  List<Object?> get props => [paquete, permitirDatosMoviles, esperarConexion];
}

/// HU-SYNC-010 — arranca o reanuda la descarga de un paquete. Las reglas (Wi-Fi, espacio, Range,
/// checksum) están en [DescargadorPaquetesTiles.descargar]; el progreso llega por
/// [DescargadorPaquetesTiles.cambios].
final class DescargarPaqueteTilesUseCase implements UseCase<Unit, DescargarPaqueteTilesParams> {
  DescargarPaqueteTilesUseCase(this._descargador);

  final DescargadorPaquetesTiles _descargador;

  @override
  Future<Either<Failure, Unit>> call(DescargarPaqueteTilesParams params) {
    final paquete = params.paquete;
    return _descargador.descargar(
      paquete,
      permitirDatosMoviles: params.permitirDatosMoviles,
      esperarConexion: params.esperarConexion,
    );
  }
}

/// HU-SYNC-010 — pausa la descarga del paquete con ese id; se reanuda con
/// [DescargarPaqueteTilesUseCase] desde donde quedó.
final class PausarDescargaTilesUseCase implements UseCase<Unit, String> {
  PausarDescargaTilesUseCase(this._descargador);

  final DescargadorPaquetesTiles _descargador;

  @override
  Future<Either<Failure, Unit>> call(String paqueteId) async {
    await _descargador.pausar(paqueteId);
    return const Right(unit);
  }
}

/// HU-SYNC-010 — elimina el paquete con ese id para liberar espacio (de a uno). El mapa deja de
/// usarlo y cae al online.
final class EliminarPaqueteTilesUseCase implements UseCase<Unit, String> {
  EliminarPaqueteTilesUseCase(this._descargador);

  final DescargadorPaquetesTiles _descargador;

  @override
  Future<Either<Failure, Unit>> call(String paqueteId) => _descargador.eliminar(paqueteId);
}
