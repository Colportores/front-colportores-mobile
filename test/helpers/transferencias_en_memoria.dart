// Arnés de las transferencias de materiales (HU-STK-005, #512): un repositorio en memoria que respeta
// las reglas del real (idempotente, solo quien la pidió y solo por autorizar), con compuertas y fallas que
// el test dispara.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/companiero_de_campania.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/transferencia.dart';
import 'package:colportores_mobile/features/transferencias/domain/repositories/companieros_de_campania_repository.dart';
import 'package:colportores_mobile/features/transferencias/domain/repositories/transferencia_repository.dart';
import 'package:dartz/dartz.dart';

/// Una transferencia de ejemplo: Juan (`juan`) le pidió 2 de «p-1» a Ana (`ana`) hoy 14:35 (17:35 UTC).
Transferencia transferenciaDeEjemplo({
  String id = 't-1',
  String origen = 'ana',
  String destino = 'juan',
  EstadoDeTransferencia estado = EstadoDeTransferencia.porAutorizar,
  String? solicitante = 'juan',
  String? creador,
  DateTime? fechaSolicitud,
  DateTime? creada,
  String? motivoRechazo,
  DateTime? decididoEn,
  List<LineaDeTransferencia>? lineas,
  int syncVersion = 1,
}) {
  final t = creada ?? DateTime.utc(2026, 10, 23, 17, 35);
  return Transferencia(
    id: id,
    origenId: origen,
    destinoId: destino,
    estado: estado,
    lineas: lineas ?? const [LineaDeTransferencia(id: 'l-1', productoId: 'p-1', cantidad: 2)],
    solicitanteId: solicitante,
    fechaSolicitud: fechaSolicitud ?? t,
    motivoRechazo: motivoRechazo,
    decididoEn: decididoEn,
    auditoria: Auditoria(
      createdAt: t,
      updatedAt: t,
      createdBy: creador ?? solicitante ?? destino,
      syncVersion: syncVersion,
    ),
  );
}

/// [TransferenciaRepository] en memoria. Cada [pedir] y [cancelar] toma la siguiente de [fallas]; con
/// [compuerta] espera a que se complete (una acción «en curso»).
class TransferenciasEnMemoria implements TransferenciaRepository {
  final _filas = <String, Transferencia>{};
  final _cambios = StreamController<void>.broadcast(sync: true);

  /// Cada transferencia nueva que se guardó, en orden.
  final pedidos = <Transferencia>[];

  /// Cuántas veces se llamó a [cancelar], también las que fallaron.
  var cancelaciones = 0;

  /// Cada acción toma la siguiente (`null` o sin más: éxito).
  final fallas = <Failure?>[];

  /// Si no es `null`, [pedir] y [cancelar] esperan a que se complete.
  Completer<void>? compuerta;

  /// Si no es `null`, [observar] emite este error en vez de la lista.
  Object? errorDeLectura;

  /// Si no es `null`, [observar] espera a que se complete antes de emitir.
  Completer<void>? compuertaDeLectura;

  void sembrar(Transferencia t) {
    _filas[t.id] = t;
    _cambios.add(null);
  }

  List<Transferencia> get todas => _filas.values.toList();

  Transferencia? operator [](String id) => _filas[id];

  @override
  Future<Either<Failure, TransferenciaPedida>> pedir(Transferencia transferencia) async {
    await compuerta?.future;
    final falla = fallas.isEmpty ? null : fallas.removeAt(0);
    if (falla != null) return Left(falla);
    final existente = _filas[transferencia.id];
    if (existente != null) {
      return Right(TransferenciaPedida(transferencia: existente, yaEstaba: true));
    }
    pedidos.add(transferencia);
    // La fila local todavía no subió: sin hora del servidor, «En cola».
    _filas[transferencia.id] = transferencia;
    _cambios.add(null);
    return Right(TransferenciaPedida(transferencia: transferencia));
  }

  @override
  Future<Either<Failure, Transferencia>> cancelar({
    required String id,
    required String colportorId,
    required DateTime ahora,
  }) async {
    cancelaciones++;
    await compuerta?.future;
    final falla = fallas.isEmpty ? null : fallas.removeAt(0);
    if (falla != null) return Left(falla);
    final actual = _filas[id];
    if (actual == null || !actual.laPidio(colportorId)) {
      return const Left(FailureTransferenciaNoCancelable());
    }
    if (actual.estado == EstadoDeTransferencia.cancelada) return Right(actual);
    if (actual.estado != EstadoDeTransferencia.porAutorizar) {
      return const Left(FailureTransferenciaNoCancelable());
    }
    final nueva = Transferencia(
      id: actual.id,
      origenId: actual.origenId,
      destinoId: actual.destinoId,
      estado: EstadoDeTransferencia.cancelada,
      lineas: actual.lineas,
      solicitanteId: actual.solicitanteId,
      fechaSolicitud: actual.fechaSolicitud,
      numero: actual.numero,
      decididoEn: actual.decididoEn,
      motivoRechazo: actual.motivoRechazo,
      auditoria: Auditoria(
        createdAt: actual.auditoria.createdAt,
        updatedAt: ahora,
        createdBy: actual.auditoria.createdBy,
        syncVersion: actual.auditoria.syncVersion,
      ),
    );
    _filas[id] = nueva;
    _cambios.add(null);
    return Right(nueva);
  }

  @override
  Stream<List<Transferencia>> observar(String colportorId) async* {
    await compuertaDeLectura?.future;
    final error = errorDeLectura;
    if (error != null) throw error;
    List<Transferencia> leer() => [
      for (final t in _filas.values)
        if (t.origenId == colportorId || t.destinoId == colportorId) t,
    ]..sort((a, b) => b.pedidaEl.compareTo(a.pedidaEl));
    yield leer();
    await for (final _ in _cambios.stream) {
      yield leer();
    }
  }
}

/// Los compañeros de campaña de a mentira: la lista que dé [resultado], con compuerta y recuento.
final class CompanierosFalsos implements CompanierosDeCampaniaRepository {
  CompanierosFalsos({this.resultado});

  /// La respuesta; `null` = [FailureCompanierosNoDisponibles].
  CompanierosDeCampania? resultado;

  /// Si no es `null`, [listar] espera a que se complete.
  Completer<void>? compuerta;

  var llamadas = 0;

  @override
  Future<Either<Failure, CompanierosDeCampania>> listar(String colportorId) async {
    llamadas++;
    await compuerta?.future;
    final r = resultado;
    return r == null ? const Left(FailureCompanierosNoDisponibles()) : Right(r);
  }
}

/// Los de la campaña del canvas: Ana, Bruno y Valentina, de «Primavera 2026».
const companierosDelCanvas = CompanierosDeCampania(
  campania: 'Primavera 2026',
  companieros: [
    CompanieroDeCampania(id: 'ana', nombre: 'Ana Pereira', lugar: 'Rivera'),
    CompanieroDeCampania(id: 'bruno', nombre: 'Bruno Techera', lugar: 'Rivera'),
    CompanieroDeCampania(id: 'vale', nombre: 'Valentina Silva', lugar: 'Tranqueras'),
  ],
);
