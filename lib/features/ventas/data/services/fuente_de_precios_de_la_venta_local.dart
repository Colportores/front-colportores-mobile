import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/dia_de_calendario.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../datos/drift_sync_meta.dart';
import '../../../catalogo/domain/entities/ciudad_consultable.dart';
import '../../domain/entities/precios_de_la_venta.dart';
import '../../domain/repositories/fuente_de_precios_de_la_venta.dart';

/// [FuenteDePreciosDeLaVenta] sobre lo que el teléfono ya tiene, sin red (HU-VEN-001, vista 27): la
/// casa del cliente (`espacio_persona` → `espacio` → `ubicacion.ciudad_id`) y las réplicas del pull de
/// catálogos (`campania_colportor`, `campania`, `campania_ciudad` y `ciudad`, las mismas que lee la
/// vista 26 «Precios», #421).
///
/// **Con qué precios** (decisión P4 de #158): los de la **ciudad de la casa** en la campaña **en
/// curso** de la colportora: una inscripción viva en una campaña que ya empezó (`fecha_inicio <= hoy`) y
/// no terminó (`fecha_fin` vacía o `>= hoy`), que tiene esa ciudad. Nunca el GPS. «Hoy» es el día de
/// Montevideo ([diaDeCalendario]), como `hoy_montevideo()` del servidor. Una campaña que todavía no
/// empezó no cuenta: el servidor rechaza una venta anterior al inicio (backend-supabase 0102).
///
/// - Si hay más de una campaña en curso con esa ciudad (no debería), gana la que empezó último.
/// - Sin ninguna en curso: [SinCampaniaVigente] (27A·10), con la última campaña **de esa ciudad** que
///   ya terminó, si hay una («Primavera 2026 terminó el 15/12»).
///
/// **Qué es «no sé».** Una `Left` ([FailurePreciosNoDisponibles], el aviso con «Reintentar») es que
/// no se pudo leer: la lectura falló, ningún pull terminó todavía, o falta en el teléfono la casa del
/// cliente o una campaña o ciudad a la que apunta una fila. Afirmar «no tenés precios» sin saberlo
/// dejaría a la colportora sin vender por un error nuestro.
final class FuenteDePreciosDeLaVentaLocal implements FuenteDePreciosDeLaVenta {
  FuenteDePreciosDeLaVentaLocal(this._db, {DateTime Function()? ahora, AppLogger? logger})
    : _ahora = ahora ?? DateTime.now,
      _log = logger ?? AppLogger.instance;

  final AppDatabase _db;
  final DateTime Function() _ahora;
  final AppLogger _log;

  @override
  Future<Either<Failure, PreciosDeLaVenta>> leer({
    required String colportorId,
    required String espacioPersonaId,
  }) async {
    try {
      final leido = await _leer(
        colportorId.trim(),
        espacioPersonaId.trim(),
        hoy: diaDeCalendario(_ahora()),
      );
      if (leido == null) {
        _log.warn(
          LogModulo.venta,
          'VENTA_PRECIOS_SIN_BAJAR',
          'el teléfono todavía no tiene la casa del cliente o las campañas y ciudades de la colportora',
        );
        return const Left(FailurePreciosNoDisponibles());
      }
      return Right(leido);
    } on Object catch (e) {
      _log.warn(
        LogModulo.venta,
        'VENTA_PRECIOS_FAIL',
        'no se pudieron leer los precios de la venta',
        {'causa': e.runtimeType.toString()},
      );
      return const Left(FailurePreciosNoDisponibles());
    }
  }

  /// En una transacción: un pull que escribe en medio no deja una campaña a medio ver.
  Future<PreciosDeLaVenta?> _leer(
    String colportorId,
    String espacioPersonaId, {
    required String hoy,
  }) => _db.transaction(() async {
    if (colportorId.isEmpty || espacioPersonaId.isEmpty) return null;
    // Sin ningún pull terminado la réplica está vacía porque no bajó, no porque no haya nada.
    if ((await DriftSyncMeta(_db).read()).lastPullAt == null) return null;

    final ciudadId = await _ciudadDeLaCasa(espacioPersonaId);
    if (ciudadId == null) return null;

    final inscripciones = await (_db.select(
      _db.campaniasColportor,
    )..where((i) => i.usuarioId.equals(colportorId) & i.deletedAt.isNull())).get();
    if (inscripciones.isEmpty) return const SinCampaniaVigente();
    final campaniaIds = {for (final i in inscripciones) i.campaniaId};
    final campanias = {
      for (final c in await (_db.select(_db.campanias)..where((c) => c.id.isIn(campaniaIds))).get())
        c.id: c,
    };
    if (campaniaIds.any((id) => !campanias.containsKey(id))) return null;

    final vinculos =
        await (_db.select(_db.campaniasCiudad)..where(
              (v) =>
                  v.campaniaId.isIn(campaniaIds) &
                  v.ciudadId.equals(ciudadId) &
                  v.deletedAt.isNull(),
            ))
            .get();
    if (vinculos.isEmpty) return const SinCampaniaVigente();
    final ciudad = await (_db.select(
      _db.ciudades,
    )..where((c) => c.id.equals(ciudadId))).getSingleOrNull();
    if (ciudad == null) return null;
    if (ciudad.deletedAt != null) return const SinCampaniaVigente();

    CampaniaCiudadFila? enCurso;
    CampaniaFila? campaniaEnCurso;
    CampaniaTerminada? terminada;
    for (final vinculo in vinculos) {
      final campania = campanias[vinculo.campaniaId]!;
      if (campania.deletedAt != null) continue;
      final fin = campania.fechaFin;
      if (fin != null && fin.compareTo(hoy) < 0) {
        final fecha = DateTime.tryParse(fin);
        if (fecha != null && (terminada == null || fecha.isAfter(terminada.terminoEl))) {
          terminada = CampaniaTerminada(nombre: campania.nombre, terminoEl: fecha);
        }
        continue;
      }
      // Todavía no empezó: no se vende con sus precios (el servidor la rechazaría).
      if (campania.fechaInicio.compareTo(hoy) > 0) continue;
      final antes = campaniaEnCurso;
      final gana =
          antes == null ||
          campania.fechaInicio.compareTo(antes.fechaInicio) > 0 ||
          (campania.fechaInicio == antes.fechaInicio && vinculo.id.compareTo(enCurso!.id) < 0);
      if (gana) {
        enCurso = vinculo;
        campaniaEnCurso = campania;
      }
    }
    if (enCurso == null || campaniaEnCurso == null) {
      return SinCampaniaVigente(terminada: terminada);
    }
    return PreciosVigentes(
      CiudadConsultable(
        campaniaCiudadId: enCurso.id,
        ciudadId: ciudad.id,
        nombre: ciudad.nombre,
        campaniaNombre: campaniaEnCurso.nombre,
      ),
    );
  });

  /// La `ciudad_id` de la casa del vínculo [espacioPersonaId], o `null` si en el teléfono falta el
  /// vínculo, el espacio o la ubicación. Se lee aunque estén dados de baja: la venta ya se está
  /// haciendo y su ciudad no cambia por eso (la baja la frena el guardado, con su propio aviso).
  Future<String?> _ciudadDeLaCasa(String espacioPersonaId) async {
    final vinculo = await (_db.select(
      _db.espacioPersonas,
    )..where((v) => v.id.equals(espacioPersonaId))).getSingleOrNull();
    if (vinculo == null) return null;
    final espacio = await (_db.select(
      _db.espacios,
    )..where((e) => e.id.equals(vinculo.espacioId))).getSingleOrNull();
    if (espacio == null) return null;
    final ubicacion = await (_db.select(
      _db.ubicaciones,
    )..where((u) => u.id.equals(espacio.ubicacionId))).getSingleOrNull();
    return ubicacion?.ciudadId;
  }
}
