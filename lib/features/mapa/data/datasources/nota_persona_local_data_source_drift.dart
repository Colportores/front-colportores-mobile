import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../domain/entities/contexto_notas_persona.dart';
import '../../domain/entities/motivo_rechazo_nota.dart';
import '../../domain/entities/nota_persona.dart';
import 'nota_persona_local_data_source.dart';
import 'notas_table.dart';

typedef _Motivo = MotivoRechazoNota;

/// [NotaPersonaLocalDataSource] sobre las tablas `nota`, `persona`, `espacio_persona`, `espacio` y
/// `ubicacion` de la DB cifrada.
///
/// Cada operación es **una transacción de Drift**: leer, decidir y escribir juntos. Drift no corre dos
/// a la vez sobre la misma DB, así que dos llamadas casi simultáneas (un doble toque, dos acciones
/// seguidas) se serializan y la segunda ve lo que dejó la primera.
///
/// **local-only**: la nota no es una entidad del sync (`SyncSpec.local`), así que no hay nada que
/// encolar.
final class NotaPersonaLocalDataSourceDrift implements NotaPersonaLocalDataSource {
  NotaPersonaLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  @override
  Future<NotaPersona> agregar(NotaPersona nota) => _db.transaction(() async {
    final existente = await _fila(nota.id);
    if (existente != null) return _aNota(existente);
    await _exigirEscribible(nota.personaId);
    await _db.into(_db.notas).insert(_aFila(nota));
    return nota;
  });

  @override
  Future<NotaPersona> editar({
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
  Future<NotaPersona> borrar({required String id, required DateTime ahora}) =>
      _db.transaction(() async {
        final fila = await _filaExistente(id);
        if (fila.deletedAt != null) return _aNota(fila);
        await _exigirEscribible(fila.targetId);
        final cuando = _instante(fila, ahora);
        return _escribir(fila, NotasCompanion(deletedAt: Value(cuando), updatedAt: Value(cuando)));
      });

  @override
  Future<NotaPersona> restaurar({required String id, required DateTime ahora}) =>
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
  Stream<List<NotaPersona>> observar(String personaId) {
    final consulta = _db.select(_db.notas)
      ..where((n) => n.targetType.equals(TipoObjetivoNota.persona) & n.targetId.equals(personaId))
      ..orderBy([(n) => OrderingTerm.desc(n.createdAt), (n) => OrderingTerm.desc(n.id)]);
    return consulta.watch().map((filas) => [for (final f in filas) _aNota(f)]);
  }

  @override
  Future<ContextoNotasPersona?> leerContexto(String personaId) async {
    final persona = await _persona(personaId);
    if (persona == null) return null;
    return ContextoNotasPersona(
      nombre: persona.nombre,
      soloLectura: await _estaEnSoloLectura(persona),
    );
  }

  Future<PersonaFila?> _persona(String id) =>
      (_db.select(_db.personas)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<NotaFila?> _fila(String id) =>
      (_db.select(_db.notas)
            ..where((n) => n.id.equals(id) & n.targetType.equals(TipoObjetivoNota.persona)))
          .getSingleOrNull();

  Future<NotaFila> _filaExistente(String id) async =>
      await _fila(id) ?? (throw const NotaRechazadaException(_Motivo.notaInexistente));

  /// La persona tiene que estar y no ser de solo lectura.
  Future<void> _exigirEscribible(String personaId) async {
    final persona = await _persona(personaId);
    if (persona == null) throw const NotaRechazadaException(_Motivo.personaInexistente);
    if (await _estaEnSoloLectura(persona)) {
      throw const NotaRechazadaException(_Motivo.soloLectura);
    }
  }

  /// Solo lectura (32B·04 y 32B·08): la persona está dada de baja, o ninguno de sus vínculos sigue
  /// activo con un espacio y una ubicación activos. Si la ubicación no está en el teléfono (el pull no
  /// garantiza el orden) no se la cuenta como de baja: ante una fila que falta no se inventa un motivo
  /// para frenar.
  Future<bool> _estaEnSoloLectura(PersonaFila persona) async {
    if (persona.deletedAt != null) return true;
    final consulta =
        _db.select(_db.espacioPersonas).join([
          innerJoin(_db.espacios, _db.espacios.id.equalsExp(_db.espacioPersonas.espacioId)),
          leftOuterJoin(_db.ubicaciones, _db.ubicaciones.id.equalsExp(_db.espacios.ubicacionId)),
        ])..where(
          _db.espacioPersonas.personaId.equals(persona.id) &
              _db.espacioPersonas.deletedAt.isNull() &
              _db.espacios.deletedAt.isNull() &
              _db.ubicaciones.deletedAt.isNull(),
        );
    return (await consulta.get()).isEmpty;
  }

  /// El reloj no retrocede: un `updated_at` nunca queda antes del que ya tenía la fila.
  static DateTime _instante(NotaFila fila, DateTime ahora) =>
      ahora.isBefore(fila.updatedAt) ? fila.updatedAt : ahora;

  Future<NotaPersona> _escribir(NotaFila fila, NotasCompanion cambios) async {
    await (_db.update(_db.notas)..where((n) => n.id.equals(fila.id))).write(cambios);
    return _aNota((await _fila(fila.id))!);
  }

  static NotaPersona _aNota(NotaFila fila) => NotaPersona(
    id: fila.id,
    personaId: fila.targetId,
    texto: fila.texto,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  static NotasCompanion _aFila(NotaPersona n) => NotasCompanion.insert(
    id: n.id,
    targetType: TipoObjetivoNota.persona,
    targetId: n.personaId,
    texto: n.texto,
    createdAt: n.auditoria.createdAt,
    updatedAt: n.auditoria.updatedAt,
    createdBy: Value(n.auditoria.createdBy),
    deletedAt: Value(n.auditoria.deletedAt),
    syncVersion: Value(n.auditoria.syncVersion),
  );
}
