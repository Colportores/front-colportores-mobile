import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/marcador_mapa.dart';
import '../../domain/services/criterio_duplicado_ubicacion.dart';
import '../../domain/value_objects/area_mapa.dart';
import '../models/espacio_model.dart';
import '../models/ubicacion_model.dart';
import 'espacios_table.dart';
import 'ubicacion_local_data_source.dart';
import 'ubicaciones_table.dart';

part 'ubicacion_local_data_source_drift.g.dart';

/// [UbicacionLocalDataSource] sobre las tablas `ubicacion` ([Ubicaciones]) y `espacio`
/// ([Espacios]) de la DB cifrada.
///
/// Es el DAO de las dos tablas (`@DriftAccessor`) y traduce modelos ↔ filas, como
/// `JornadaLocalDataSourceDrift`. El sync entra por [EncoladorSync], dentro de la misma
/// transacción que la escritura (contrato-sync-engine §3).
@DriftAccessor(tables: [Ubicaciones, Espacios])
final class UbicacionLocalDataSourceDrift extends DatabaseAccessor<AppDatabase>
    with _$UbicacionLocalDataSourceDriftMixin
    implements UbicacionLocalDataSource {
  /// [_encolador] se pasa como `encolador:` (parámetro nombrado privado, Dart ≥ 3.10).
  UbicacionLocalDataSourceDrift(super.attachedDatabase, {required this._encolador});

  final EncoladorSync _encolador;

  /// Metros por grado de latitud (y de longitud en el ecuador).
  static const _metrosPorGrado = 111320.0;

  /// Buscar, decidir y escribir van en una sola transacción: Drift no corre dos a la vez sobre la
  /// misma DB, así que dos altas casi simultáneas se serializan y la segunda ya ve la primera —como
  /// la misma ubicación (mismo `id`) o como candidata a duplicado—.
  @override
  Future<InsercionUbicacion> insertar(
    UbicacionModel ubicacion, {
    EspacioModel? espacio,
    CriterioDuplicadoUbicacion? duplicados,
  }) => transaction(() async {
    final existente = await (select(
      ubicaciones,
    )..where((u) => u.id.equals(ubicacion.id))).getSingleOrNull();
    if (existente != null) return (ubicacion: _aModelo(existente), yaEstaba: true);

    if (duplicados != null) {
      final candidatas = await _candidatas(ubicacion, duplicados);
      if (candidatas.isNotEmpty) throw UbicacionDuplicadaException(candidatas);
    }

    await into(ubicaciones).insert(_aFila(ubicacion));
    await _encolador.encolar('ubicacion', OperacionSync.insert, ubicacion.toJson());
    if (espacio != null) {
      await into(espacios).insert(_aFilaEspacio(espacio));
      await _encolador.encolar('espacio', OperacionSync.insert, espacio.toJson());
    }
    return (ubicacion: ubicacion, yaEstaba: false);
  });

  @override
  Future<UbicacionModel?> obtener(String id) async {
    final fila = await (select(ubicaciones)..where((u) => u.id.equals(id))).getSingleOrNull();
    return fila == null ? null : _aModelo(fila);
  }

  @override
  Future<int> contarEspaciosActivos(String ubicacionId) async {
    final cantidad = espacios.id.count();
    final consulta = selectOnly(espacios)
      ..addColumns([cantidad])
      ..where(espacios.ubicacionId.equals(ubicacionId) & espacios.deletedAt.isNull());
    return (await consulta.getSingle()).read(cantidad) ?? 0;
  }

  /// Leer, comparar, buscar duplicados, escribir y encolar van en una sola transacción, como el
  /// alta: una escritura concurrente (el sync entrante) se serializa y esta ve su resultado.
  @override
  Future<UbicacionModel> actualizar(
    UbicacionModel nueva, {
    required DateTime baseUpdatedAt,
    CriterioDuplicadoUbicacion? duplicados,
  }) => transaction(() async {
    final fila = await (select(ubicaciones)..where((u) => u.id.equals(nueva.id))).getSingleOrNull();
    if (fila == null) throw const UbicacionInexistenteException();
    if (fila.updatedAt != instanteMs(baseUpdatedAt)) throw const UbicacionCambioException();

    if (duplicados != null) {
      final candidatas = await _candidatas(nueva, duplicados);
      if (candidatas.isNotEmpty) throw UbicacionDuplicadaException(candidatas);
    }

    await (update(ubicaciones)..where((u) => u.id.equals(nueva.id))).write(
      UbicacionesCompanion(
        tipo: Value(UbicacionModel.codigoDeTipo(nueva.tipo)),
        calle: Value(nueva.calle),
        numero: Value(nueva.numero),
        lat: Value(nueva.lat),
        lon: Value(nueva.lon),
        ciudadId: Value(nueva.ciudadId),
        updatedAt: Value(nueva.auditoria.updatedAt),
        deletedAt: Value(nueva.auditoria.deletedAt),
      ),
    );
    final guardada = _aModelo(
      await (select(ubicaciones)..where((u) => u.id.equals(nueva.id))).getSingle(),
    );
    await _encolador.encolar('ubicacion', OperacionSync.update, guardada.toJson());
    return guardada;
  });

  @override
  Future<UbicacionModel> cambiarBaja(
    String id, {
    required DateTime baseUpdatedAt,
    required DateTime updatedAt,
    required DateTime? deletedAt,
  }) => transaction(() async {
    final fila = await (select(ubicaciones)..where((u) => u.id.equals(id))).getSingleOrNull();
    if (fila == null) throw const UbicacionInexistenteException();
    if (fila.updatedAt != instanteMs(baseUpdatedAt)) throw const UbicacionCambioException();

    await (update(ubicaciones)..where((u) => u.id.equals(id))).write(
      UbicacionesCompanion(updatedAt: Value(updatedAt), deletedAt: Value(deletedAt)),
    );
    final guardada = _aModelo(
      await (select(ubicaciones)..where((u) => u.id.equals(id))).getSingle(),
    );
    await _encolador.encolar(
      'ubicacion',
      deletedAt == null ? OperacionSync.update : OperacionSync.delete,
      guardada.toJson(),
    );
    return guardada;
  });

  @override
  Stream<List<UbicacionModel>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) {
    final consulta = select(ubicaciones)..where((u) => u.createdBy.equals(colportorId));
    if (ciudadId != null) consulta.where((u) => u.ciudadId.equals(ciudadId));
    if (!incluirBajas) consulta.where((u) => u.deletedAt.isNull());
    return consulta.watch().map((filas) => [for (final fila in filas) _aModelo(fila)]);
  }

  @override
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  }) {
    if (!area.esValida) return Stream.value(const []);
    final cantidad = espacios.id.count();
    final consulta =
        select(ubicaciones).join([
            leftOuterJoin(
              espacios,
              espacios.ubicacionId.equalsExp(ubicaciones.id) & espacios.deletedAt.isNull(),
            ),
          ])
          ..addColumns([cantidad])
          ..where(
            ubicaciones.createdBy.equals(colportorId) &
                ubicaciones.deletedAt.isNull() &
                ubicaciones.lat.isBetweenValues(area.sur, area.norte),
          )
          ..groupBy([ubicaciones.id]);
    if (area.cruzaAntimeridiano) {
      consulta.where(
        ubicaciones.lon.isBiggerOrEqualValue(area.oeste) |
            ubicaciones.lon.isSmallerOrEqualValue(area.este),
      );
    } else {
      consulta.where(ubicaciones.lon.isBetweenValues(area.oeste, area.este));
    }
    return consulta.watch().map(
      (filas) => [
        for (final fila in filas) _aMarcador(fila.readTable(ubicaciones), fila.read(cantidad) ?? 0),
      ],
    );
  }

  static MarcadorMapa _aMarcador(UbicacionFila u, int cantidadEspacios) => MarcadorMapa(
    ubicacionId: u.id,
    tipo: UbicacionModel.tipoDesdeCodigo(u.tipo),
    lat: u.lat,
    lon: u.lon,
    calle: u.calle,
    numero: u.numero,
    cantidadEspacios: cantidadEspacios,
  );

  /// Las candidatas de [criterio] para [centro] entre las ubicaciones activas del teléfono.
  ///
  /// La consulta solo acota lo que se lee; la regla exacta la aplica el criterio en Dart. Trae:
  ///
  /// - las que caen en un recuadro que contiene el círculo de `CriterioDuplicadoUbicacion.
  ///   radioMetros` alrededor de [centro] (con margen), de cualquier ciudad; y
  /// - si [centro] tiene calle y número, las de su ciudad con el mismo número (`lower(trim(…))`
  ///   de los dos lados, así que el `lower` de SQLite, que solo pasa a minúsculas el ASCII, es
  ///   parejo). Un número que difiere solo en mayúsculas no ASCII ("12 Ñ" y "12 ñ") no sale acá:
  ///   lo encuentra el scan de "Posibles duplicados", que compara en Dart.
  Future<List<CandidataDuplicado>> _candidatas(
    UbicacionModel centro,
    CriterioDuplicadoUbicacion criterio,
  ) async {
    const margen = CriterioDuplicadoUbicacion.radioMetros * 1.5;
    const dLat = margen / _metrosPorGrado;
    final cosLat = math.cos(centro.lat * math.pi / 180).abs();
    final numero = centro.numero;
    final consulta = select(ubicaciones)
      ..where((u) {
        var cerca = u.lat.isBetweenValues(centro.lat - dLat, centro.lat + dLat);
        // Cerca de los polos un grado de longitud mide casi nada: ahí no se acota por longitud.
        if (cosLat > 0.01) {
          final dLon = margen / (_metrosPorGrado * cosLat);
          cerca = cerca & u.lon.isBetweenValues(centro.lon - dLon, centro.lon + dLon);
        }
        final mismoNumero = centro.calle == null || numero == null
            ? const Constant(false)
            : u.ciudadId.equals(centro.ciudadId) &
                  u.calle.isNotNull() &
                  u.numero.trim().lower().equalsExp(Variable(numero).trim().lower());
        return u.deletedAt.isNull() & u.id.equals(centro.id).not() & (cerca | mismoNumero);
      });
    final filas = await consulta.get();
    return criterio.candidatas(centro.toEntity(), [
      for (final fila in filas) _aModelo(fila).toEntity(),
    ]);
  }

  static UbicacionesCompanion _aFila(UbicacionModel u) => UbicacionesCompanion.insert(
    id: u.id,
    tipo: UbicacionModel.codigoDeTipo(u.tipo),
    calle: Value(u.calle),
    numero: Value(u.numero),
    lat: u.lat,
    lon: u.lon,
    ciudadId: u.ciudadId,
    zonaId: Value(u.zonaId),
    createdAt: u.auditoria.createdAt,
    updatedAt: u.auditoria.updatedAt,
    createdBy: Value(u.auditoria.createdBy),
    deletedAt: Value(u.auditoria.deletedAt),
    syncVersion: Value(u.auditoria.syncVersion),
  );

  static EspaciosCompanion _aFilaEspacio(EspacioModel e) => EspaciosCompanion.insert(
    id: e.id,
    ubicacionId: e.ubicacionId,
    numeroDepto: Value(e.numeroDepto),
    piso: Value(e.piso),
    descripcion: Value(e.descripcion),
    createdAt: e.auditoria.createdAt,
    updatedAt: e.auditoria.updatedAt,
    createdBy: Value(e.auditoria.createdBy),
    deletedAt: Value(e.auditoria.deletedAt),
    syncVersion: Value(e.auditoria.syncVersion),
  );

  static UbicacionModel _aModelo(UbicacionFila fila) => UbicacionModel(
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
