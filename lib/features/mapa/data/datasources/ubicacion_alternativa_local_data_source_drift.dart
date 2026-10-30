import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../domain/entities/espacio_persona.dart';
import '../../domain/entities/estado_ubicacion_alternativa.dart';
import '../../domain/entities/motivo_rechazo_ubicacion_alternativa.dart';
import '../../domain/entities/ubicacion.dart';
import '../models/espacio_persona_model.dart';
import '../models/ubicacion_model.dart';
import 'ubicacion_alternativa_local_data_source.dart';

typedef _Motivo = MotivoRechazoUbicacionAlternativa;

/// [UbicacionAlternativaLocalDataSource] sobre las tablas `espacio_persona`, `espacio`, `persona` y
/// `ubicacion` de la DB cifrada.
///
/// Es una clase plana sobre la [AppDatabase] (sin `@DriftAccessor`: no hace falta generar nada). Cada
/// escritura va en una transacción con su encolado: Drift no corre dos a la vez, así que dos toques
/// seguidos se serializan y el segundo ya ve lo del primero (devuelve el vínculo sin escribir).
final class UbicacionAlternativaLocalDataSourceDrift
    implements UbicacionAlternativaLocalDataSource {
  /// [_encolador] se pasa como `encolador:` (parámetro nombrado privado, Dart ≥ 3.10).
  UbicacionAlternativaLocalDataSourceDrift(this._db, {required this._encolador});

  final AppDatabase _db;
  final EncoladorSync _encolador;

  @override
  Stream<EstadoUbicacionAlternativa> observar({
    required String personaId,
    required String espacioId,
  }) {
    final vinculos = _db.espacioPersonas;
    final ubicaciones = _db.ubicaciones;
    final consulta =
        _db.select(vinculos).join([
          leftOuterJoin(ubicaciones, ubicaciones.id.equalsExp(vinculos.ubicacionCobranzaAltId)),
        ])..where(
          vinculos.personaId.equals(personaId) &
              vinculos.espacioId.equals(espacioId) &
              vinculos.deletedAt.isNull(),
        );
    return consulta.watch().map((filas) {
      if (filas.isEmpty) return const SinUbicacionAlternativa();
      final fila = filas.first;
      final altId = fila.readTable(vinculos).ubicacionCobranzaAltId;
      if (altId == null) return const SinUbicacionAlternativa();
      final ubicacion = fila.readTableOrNull(ubicaciones);
      if (ubicacion == null) return UbicacionAlternativaFaltante(altId);
      if (ubicacion.deletedAt != null) return UbicacionAlternativaDeBaja(altId);
      return UbicacionAlternativaVigente(_aUbicacion(ubicacion));
    });
  }

  @override
  Stream<List<Ubicacion>> observarCandidatas({
    required String colportorId,
    required String espacioId,
  }) {
    final ubicaciones = _db.ubicaciones;
    final espacios = _db.espacios;
    final delEspacio = _db.selectOnly(espacios)
      ..addColumns([espacios.ubicacionId])
      ..where(espacios.id.equals(espacioId));
    final consulta = _db.select(ubicaciones)
      ..where(
        (u) =>
            u.createdBy.equals(colportorId) & u.deletedAt.isNull() & u.id.isNotInQuery(delEspacio),
      )
      ..orderBy([
        (u) => OrderingTerm.asc(u.calle),
        (u) => OrderingTerm.asc(u.numero),
        (u) => OrderingTerm.asc(u.id),
      ]);
    return consulta.watch().map((filas) => [for (final fila in filas) _aUbicacion(fila)]);
  }

  @override
  Future<EspacioPersona> establecer({
    required String personaId,
    required String espacioId,
    required String ubicacionId,
    required String colportorId,
    required DateTime ahora,
  }) => _db.transaction(() async {
    final vinculo = await _vinculoEscribible(personaId, espacioId);
    final espacio = await _espacio(espacioId);
    final elegida = await (_db.select(
      _db.ubicaciones,
    )..where((u) => u.id.equals(ubicacionId))).getSingleOrNull();
    if (elegida == null) {
      throw const UbicacionAlternativaRechazadaException(_Motivo.ubicacionInexistente);
    }
    if (elegida.createdBy != colportorId) {
      throw const UbicacionAlternativaRechazadaException(_Motivo.ubicacionAjena);
    }
    if (elegida.deletedAt != null) {
      throw const UbicacionAlternativaRechazadaException(_Motivo.ubicacionDeBaja);
    }
    if (elegida.id == espacio.ubicacionId) {
      throw const UbicacionAlternativaRechazadaException(_Motivo.esLaDelEspacio);
    }
    if (vinculo.ubicacionCobranzaAltId == ubicacionId) return _aVinculo(vinculo);
    return _escribir(vinculo, ubicacionId, ahora);
  });

  @override
  Future<EspacioPersona> quitar({
    required String personaId,
    required String espacioId,
    required DateTime ahora,
  }) => _db.transaction(() async {
    final vinculo = await _vinculoEscribible(personaId, espacioId);
    if (vinculo.ubicacionCobranzaAltId == null) return _aVinculo(vinculo);
    return _escribir(vinculo, null, ahora);
  });

  /// El vínculo activo de la persona con el espacio, si la persona, el espacio y su ubicación se
  /// pueden modificar; si no, es de solo lectura y se rechaza. Si la ubicación del espacio no está en
  /// el teléfono (el pull no garantiza el orden) no se bloquea: ante una fila que falta no se
  /// inventa un motivo para frenar.
  Future<EspacioPersonaFila> _vinculoEscribible(String personaId, String espacioId) async {
    final vinculo =
        await (_db.select(_db.espacioPersonas)..where(
              (v) =>
                  v.personaId.equals(personaId) &
                  v.espacioId.equals(espacioId) &
                  v.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (vinculo == null) {
      throw const UbicacionAlternativaRechazadaException(_Motivo.vinculoInexistente);
    }

    final persona = await (_db.select(
      _db.personas,
    )..where((p) => p.id.equals(personaId))).getSingleOrNull();
    if (persona == null) {
      throw const UbicacionAlternativaRechazadaException(_Motivo.vinculoInexistente);
    }
    if (persona.deletedAt != null) {
      throw const UbicacionAlternativaRechazadaException(_Motivo.personaDeBaja);
    }

    final espacio = await _espacio(espacioId);
    if (espacio.deletedAt != null) {
      throw const UbicacionAlternativaRechazadaException(_Motivo.espacioDeBaja);
    }
    final ubicacion = await (_db.select(
      _db.ubicaciones,
    )..where((u) => u.id.equals(espacio.ubicacionId))).getSingleOrNull();
    if (ubicacion != null && ubicacion.deletedAt != null) {
      throw const UbicacionAlternativaRechazadaException(_Motivo.ubicacionDelEspacioDeBaja);
    }
    return vinculo;
  }

  Future<EspacioFila> _espacio(String espacioId) async {
    final espacio = await (_db.select(
      _db.espacios,
    )..where((e) => e.id.equals(espacioId))).getSingleOrNull();
    return espacio ??
        (throw const UbicacionAlternativaRechazadaException(_Motivo.vinculoInexistente));
  }

  /// Escribe [alternativa] (`null` = quitarla) y encola el `update` del vínculo entero. El reloj no
  /// retrocede: un `updated_at` nunca queda antes del que ya tenía la fila.
  Future<EspacioPersona> _escribir(
    EspacioPersonaFila vinculo,
    String? alternativa,
    DateTime ahora,
  ) async {
    final instante = instanteMs(ahora);
    final cuando = instante.isBefore(vinculo.updatedAt) ? vinculo.updatedAt : instante;
    await (_db.update(_db.espacioPersonas)..where((v) => v.id.equals(vinculo.id))).write(
      EspacioPersonasCompanion(
        ubicacionCobranzaAltId: Value(alternativa),
        updatedAt: Value(cuando),
      ),
    );
    final guardado = _aVinculo(
      await (_db.select(_db.espacioPersonas)..where((v) => v.id.equals(vinculo.id))).getSingle(),
    );
    await _encolador.encolar(
      'espacio_persona',
      OperacionSync.update,
      EspacioPersonaModel.fromEntity(guardado).toJson(),
    );
    return guardado;
  }

  static EspacioPersona _aVinculo(EspacioPersonaFila fila) => EspacioPersona(
    id: fila.id,
    espacioId: fila.espacioId,
    personaId: fila.personaId,
    ubicacionCobranzaAltId: fila.ubicacionCobranzaAltId,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  static Ubicacion _aUbicacion(UbicacionFila fila) => UbicacionModel(
    id: fila.id,
    tipo: UbicacionModel.tipoDesdeCodigo(fila.tipo),
    calle: fila.calle,
    numero: fila.numero,
    lat: fila.lat,
    lon: fila.lon,
    ciudadId: fila.ciudadId,
    zonaId: fila.zonaId,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );
}
