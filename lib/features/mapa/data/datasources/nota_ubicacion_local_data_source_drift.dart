import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../domain/entities/motivo_rechazo_nota.dart';
import '../../domain/entities/nota_ubicacion.dart';
import 'nota_persona_local_data_source.dart' show NotaRechazadaException;
import 'nota_ubicacion_local_data_source.dart';
import 'notas_table.dart';

typedef _Motivo = MotivoRechazoNota;

/// [NotaUbicacionLocalDataSource] sobre las tablas `nota`, `ubicacion` y `espacio` de la DB cifrada.
///
/// Sirve a dos dueños de notas con la misma forma: el lugar (`target_type = UBICACION`, vista 39) y el
/// depto (`ESPACIO`, vista 11, #290). Lo elige [objetivo]; cambia a qué filas toca y qué tiene que
/// cumplir el dueño para que se pueda escribir (el lugar, no estar de baja; el depto, estar en el
/// teléfono, sin baja y en un lugar sin baja).
///
/// Cada operación es **una transacción de Drift**: leer, decidir y escribir juntos. Drift no corre dos
/// a la vez sobre la misma DB, así que dos llamadas casi simultáneas (un doble toque, dos acciones
/// seguidas) se serializan y la segunda ve lo que dejó la primera.
///
/// **local-only**: la nota no es una entidad del sync (`SyncSpec.local`), así que no hay nada que
/// encolar. Sin migración: la tabla `nota` ya admite varias filas por lugar o por depto (v9).
final class NotaUbicacionLocalDataSourceDrift implements NotaUbicacionLocalDataSource {
  NotaUbicacionLocalDataSourceDrift(this._db, {this.objetivo = TipoObjetivoNota.ubicacion})
    : assert(objetivo == TipoObjetivoNota.ubicacion || objetivo == TipoObjetivoNota.espacio);

  final AppDatabase _db;

  /// `target_type` de las notas que lee y escribe: `UBICACION` o `ESPACIO` ([TipoObjetivoNota]).
  final String objetivo;

  @override
  Future<NotaUbicacion> agregar(NotaUbicacion nota) => _db.transaction(() async {
    final existente = await _fila(nota.id);
    if (existente != null) return _aNota(existente);
    await _exigirEscribible(nota.ubicacionId);
    await _db.into(_db.notas).insert(_aFila(nota));
    return nota;
  });

  @override
  Future<NotaUbicacion> editar({
    required String id,
    required String texto,
    required DateTime ahora,
  }) => _db.transaction(() async {
    final fila = await _filaExistente(id);
    await _exigirEscribible(fila.targetId);
    if (fila.deletedAt != null) throw const NotaRechazadaException(_Motivo.notaBorrada);
    if (fila.texto == texto) return _aNota(fila);
    return _escribir(
      fila,
      NotasCompanion(texto: Value(texto), updatedAt: Value(_instante(fila, ahora))),
    );
  });

  @override
  Future<NotaUbicacion> borrar({required String id, required DateTime ahora}) =>
      _db.transaction(() async {
        final fila = await _filaExistente(id);
        if (fila.deletedAt != null) return _aNota(fila);
        await _exigirEscribible(fila.targetId);
        final cuando = _instante(fila, ahora);
        return _escribir(fila, NotasCompanion(deletedAt: Value(cuando), updatedAt: Value(cuando)));
      });

  @override
  Future<NotaUbicacion> restaurar({required String id, required DateTime ahora}) =>
      _db.transaction(() async {
        final fila = await _filaExistente(id);
        if (fila.deletedAt == null) return _aNota(fila);
        await _exigirEscribible(fila.targetId);
        return _escribir(
          fila,
          NotasCompanion(deletedAt: const Value(null), updatedAt: Value(_instante(fila, ahora))),
        );
      });

  @override
  Stream<List<NotaUbicacion>> observar(String ubicacionId) {
    final consulta = _db.select(_db.notas)
      ..where((n) => n.targetType.equals(objetivo) & n.targetId.equals(ubicacionId))
      // La más nueva primero; a igual instante, la de `id` mayor (UUID v7: crece con el tiempo).
      ..orderBy([(n) => OrderingTerm.desc(n.createdAt), (n) => OrderingTerm.desc(n.id)]);
    return consulta.watch().map((filas) => [for (final f in filas) _aNota(f)]);
  }

  Future<NotaFila?> _fila(String id) => (_db.select(
    _db.notas,
  )..where((n) => n.id.equals(id) & n.targetType.equals(objetivo))).getSingleOrNull();

  Future<NotaFila> _filaExistente(String id) async =>
      await _fila(id) ?? (throw const NotaRechazadaException(_Motivo.notaInexistente));

  /// El lugar tiene que estar en el teléfono y no estar dado de baja (la hoja de una casa dada de baja
  /// se ve en solo lectura: las notas se leen, no se tocan). Con las de un depto, el depto también: en
  /// el teléfono y sin baja, y su lugar sin baja.
  Future<void> _exigirEscribible(String duenioId) async {
    var ubicacionId = duenioId;
    if (objetivo == TipoObjetivoNota.espacio) {
      final espacio = await (_db.select(
        _db.espacios,
      )..where((e) => e.id.equals(duenioId))).getSingleOrNull();
      if (espacio == null) throw const NotaRechazadaException(_Motivo.espacioInexistente);
      if (espacio.deletedAt != null) throw const NotaRechazadaException(_Motivo.espacioDeBaja);
      ubicacionId = espacio.ubicacionId;
    }
    final ubicacion = await (_db.select(
      _db.ubicaciones,
    )..where((u) => u.id.equals(ubicacionId))).getSingleOrNull();
    if (ubicacion == null) throw const NotaRechazadaException(_Motivo.ubicacionInexistente);
    if (ubicacion.deletedAt != null) throw const NotaRechazadaException(_Motivo.ubicacionDeBaja);
  }

  /// El reloj no retrocede: un `updated_at` nunca queda antes del que ya tenía la fila.
  static DateTime _instante(NotaFila fila, DateTime ahora) =>
      ahora.isBefore(fila.updatedAt) ? fila.updatedAt : ahora;

  Future<NotaUbicacion> _escribir(NotaFila fila, NotasCompanion cambios) async {
    await (_db.update(_db.notas)..where((n) => n.id.equals(fila.id))).write(cambios);
    return _aNota((await _fila(fila.id))!);
  }

  static NotaUbicacion _aNota(NotaFila fila) => NotaUbicacion(
    id: fila.id,
    ubicacionId: fila.targetId,
    texto: fila.texto,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  NotasCompanion _aFila(NotaUbicacion n) => NotasCompanion.insert(
    id: n.id,
    targetType: objetivo,
    targetId: n.ubicacionId,
    texto: n.texto,
    createdAt: n.auditoria.createdAt,
    updatedAt: n.auditoria.updatedAt,
    createdBy: Value(n.auditoria.createdBy),
    deletedAt: Value(n.auditoria.deletedAt),
    syncVersion: Value(n.auditoria.syncVersion),
  );
}
