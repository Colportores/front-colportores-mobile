import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/espacios_activos.dart';
import '../../domain/entities/marcador_mapa.dart';
import '../../domain/entities/motivo_baja.dart';
import '../../domain/entities/motivo_rechazo_espacio.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/services/criterio_duplicado_ubicacion.dart';
import '../../domain/services/encolador_marcar_duplicado.dart';
import '../../domain/value_objects/area_mapa.dart';
import '../models/espacio_model.dart';
import '../models/ubicacion_model.dart';
import '../services/fuentes_sin_adaptador_ubicaciones.dart' show EncoladorMarcarDuplicadoSinMotor;
import 'audit_log_table.dart';
import 'espacio_local_data_source.dart';
import 'espacios_table.dart';
import 'ubicacion_local_data_source.dart';
import 'ubicaciones_table.dart';

part 'ubicacion_local_data_source_drift.g.dart';

typedef _Motivo = MotivoRechazoEspacio;

/// [UbicacionLocalDataSource] sobre las tablas `ubicacion` ([Ubicaciones]) y `espacio`
/// ([Espacios]) de la DB cifrada.
///
/// Es el DAO de las dos tablas (`@DriftAccessor`) y traduce modelos ↔ filas, como
/// `JornadaLocalDataSourceDrift`. El sync entra por [EncoladorSync], dentro de la misma
/// transacción que la escritura (contrato-sync-engine §3).
@DriftAccessor(tables: [Ubicaciones, Espacios, AuditLogLocal])
final class UbicacionLocalDataSourceDrift extends DatabaseAccessor<AppDatabase>
    with _$UbicacionLocalDataSourceDriftMixin
    implements UbicacionLocalDataSource, EspacioLocalDataSource {
  /// [_encolador] se pasa como `encolador:` (parámetro nombrado privado, Dart ≥ 3.10). El trabajo
  /// «marcar como duplicado» entra por [_marcarDuplicado]: sin motor de sync (#178), falla.
  UbicacionLocalDataSourceDrift(
    super.attachedDatabase, {
    required this._encolador,
    this._marcarDuplicado = const EncoladorMarcarDuplicadoSinMotor(),
  });

  final EncoladorSync _encolador;
  final EncoladorMarcarDuplicado _marcarDuplicado;

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

  @override
  Stream<EspaciosActivos> observarEspaciosActivos(String ubicacionId) {
    // Con un solo espacio activo, el mínimo de `numero_depto` es el de ese espacio (y `null` si no
    // tiene): una fila agregada alcanza para las dos cosas, sin traer los espacios.
    final cantidad = espacios.id.count();
    final primero = espacios.numeroDepto.min();
    final consulta = selectOnly(espacios)
      ..addColumns([cantidad, primero])
      ..where(espacios.ubicacionId.equals(ubicacionId) & espacios.deletedAt.isNull());
    return consulta.watchSingle().map((fila) {
      final n = fila.read(cantidad) ?? 0;
      return (cantidad: n, numeroDeptoUnico: n == 1 ? fila.read(primero) : null);
    }).distinct();
  }

  /// Leer, comparar, contar espacios, buscar duplicados, escribir y encolar van en una sola
  /// transacción, como el alta: una escritura concurrente (el sync entrante, un espacio que se
  /// agrega) se serializa y esta ve su resultado.
  @override
  Future<UbicacionModel> actualizar(
    UbicacionModel nueva, {
    required DateTime baseUpdatedAt,
    CriterioDuplicadoUbicacion? duplicados,
    bool reduceAUnEspacio = false,
  }) => transaction(() async {
    final fila = await (select(ubicaciones)..where((u) => u.id.equals(nueva.id))).getSingleOrNull();
    if (fila == null) throw const UbicacionInexistenteException();
    if (fila.updatedAt != instanteMs(baseUpdatedAt)) throw const UbicacionCambioException();

    // S17: para quedar con un solo espacio (de edificio a casa o negocio, de negocio a casa) tiene
    // que haber un depto como mucho; ese depto pasa a ser el espacio de la casa o del negocio y
    // pierde el número. Los de baja no cuentan.
    EspacioFila? deptoConNumero;
    if (reduceAUnEspacio) {
      final activos = await (select(
        espacios,
      )..where((e) => e.ubicacionId.equals(nueva.id) & e.deletedAt.isNull())).get();
      if (activos.length > 1) throw UbicacionConEspaciosException(activos.length);
      deptoConNumero = activos.where((e) => e.numeroDepto != null).firstOrNull;
    }

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
        zonaId: Value(nueva.zonaId),
        updatedAt: Value(nueva.auditoria.updatedAt),
        deletedAt: Value(nueva.auditoria.deletedAt),
      ),
    );
    final guardada = _aModelo(
      await (select(ubicaciones)..where((u) => u.id.equals(nueva.id))).getSingle(),
    );
    await _encolador.encolar('ubicacion', OperacionSync.update, guardada.toJson());
    if (deptoConNumero != null) {
      await _escribirEspacio(
        deptoConNumero.id,
        EspaciosCompanion(
          numeroDepto: const Value(null),
          updatedAt: Value(guardada.auditoria.updatedAt),
        ),
      );
    }
    return guardada;
  });

  @override
  Future<({UbicacionModel ubicacion, bool escribio})> cambiarBaja(
    String id, {
    required DateTime baseUpdatedAt,
    required DateTime updatedAt,
    required DateTime? deletedAt,
    String? motivo,
    String? conservadaId,
  }) => transaction(() async {
    final fila = await (select(ubicaciones)..where((u) => u.id.equals(id))).getSingleOrNull();
    if (fila == null) throw const UbicacionInexistenteException();
    if (conservadaId != null) {
      final conservada = await (select(
        ubicaciones,
      )..where((u) => u.id.equals(conservadaId))).getSingleOrNull();
      if (conservada == null) throw const UbicacionInexistenteException();
      if (conservada.deletedAt != null) throw const ConservadaDeBajaException();
    }
    // Ya está como se pide (dos toques que se pisaron: el primero ganó la transacción). Antes del
    // CAS, porque el primero ya cambió `updated_at`.
    if ((fila.deletedAt != null) == (deletedAt != null)) {
      return (ubicacion: _aModelo(fila), escribio: false);
    }
    if (fila.updatedAt != instanteMs(baseUpdatedAt)) throw const UbicacionCambioException();

    await (update(ubicaciones)..where((u) => u.id.equals(id))).write(
      UbicacionesCompanion(updatedAt: Value(updatedAt), deletedAt: Value(deletedAt)),
    );
    final guardada = _aModelo(
      await (select(ubicaciones)..where((u) => u.id.equals(id))).getSingle(),
    );
    // La auditoría local (R-UB09): solo la baja, solo con motivo, y en la misma transacción.
    if (deletedAt != null && motivo != null && motivo.trim().isNotEmpty) {
      await into(auditLogLocal).insert(
        AuditLogLocalCompanion.insert(
          evento: EventoAuditoriaLocal.ubicacionBaja,
          uuid: id,
          motivo: Value(motivo.trim()),
          creadoEn: deletedAt,
        ),
      );
    }
    await _encolador.encolar(
      'ubicacion',
      deletedAt == null ? OperacionSync.update : OperacionSync.delete,
      guardada.toJson(),
    );
    return (ubicacion: guardada, escribio: true);
  });

  /// Los espacios sin baja de [ubicacionId], del más viejo al más nuevo (el orden de la RPC 0026).
  Future<List<EspacioFila>> _espaciosActivosEnOrden(String ubicacionId) =>
      (select(espacios)
            ..where((e) => e.ubicacionId.equals(ubicacionId) & e.deletedAt.isNull())
            ..orderBy([(e) => OrderingTerm.asc(e.createdAt), (e) => OrderingTerm.asc(e.id)]))
          .get();

  /// La unión de un par de duplicados (HU-UBI-006), espejo local de la RPC `marcar_como_duplicado`
  /// (backend-supabase 0026), en una sola transacción:
  ///
  /// - **Espacios de B** (los activos; los de baja se quedan en B): pasan a A tal cual (cambia
  ///   `ubicacion_id`, sin mezclarse ni validar `numero_depto` repetido), salvo el espacio único
  ///   (`numero_depto` nulo o en blanco) cuando A y B son casa o negocio: se funde en el único vivo
  ///   más viejo de A (el de B queda de baja) o, si A no tiene, pasa a serlo.
  /// - **A casa con más de un espacio** pasa a edificio ("Unir tipos"); un negocio sigue negocio.
  /// - **B** queda de baja con `duplicado_de_<A>` en el `audit_log` local (no se sincroniza).
  /// - **Encolado**: la actualización de A solo si cambió de tipo (es una fila común, que sale antes
  ///   que el trabajo) y el trabajo «marcar como duplicado». No se encolan los espacios movidos ni
  ///   el tombstone de B: los aplica el servidor al correr el trabajo (su forma y qué más viaja es
  ///   del motor de sync).
  ///
  /// B ya de baja y sin espacios activos: no hace nada ([UnionLocal.escribio] `false`).
  @override
  Future<UnionLocal> unirDuplicada(
    String conservadaId,
    String duplicadaId, {
    required DateTime ahora,
  }) => transaction(() async {
    final conservada = await _ubicacionPorId(conservadaId);
    final duplicada = await _ubicacionPorId(duplicadaId);
    if (conservada == null || duplicada == null) throw const UbicacionInexistenteException();
    if (conservada.deletedAt != null) throw const ConservadaDeBajaException();

    final deB = await _espaciosActivosEnOrden(duplicadaId);
    if (duplicada.deletedAt != null && deB.isEmpty) {
      return (
        escribio: false,
        espaciosPasados: 0,
        espaciosFundidos: 0,
        conservadaPasoAEdificio: false,
      );
    }

    final instante = instanteMs(ahora);
    final tipoA = UbicacionModel.tipoDesdeCodigo(conservada.tipo);
    final tipoB = UbicacionModel.tipoDesdeCodigo(duplicada.tipo);
    final deA = await _espaciosActivosEnOrden(conservadaId);

    // Solo se funden los únicos si las dos son casa o negocio (un edificio no tiene espacio único).
    final unePorUnico = tipoA != TipoUbicacion.edificio && tipoB != TipoUbicacion.edificio;
    bool esUnico(EspacioFila e) => e.numeroDepto == null || e.numeroDepto!.trim().isEmpty;
    String? unicoDeA;
    if (unePorUnico) {
      for (final e in deA) {
        if (esUnico(e)) {
          unicoDeA = e.id;
          break;
        }
      }
    }

    var pasados = 0;
    var fundidos = 0;
    for (final e in deB) {
      if (unePorUnico && esUnico(e) && unicoDeA != null) {
        await (update(espacios)..where((x) => x.id.equals(e.id))).write(
          EspaciosCompanion(deletedAt: Value(instante), updatedAt: Value(instante)),
        );
        fundidos++;
      } else {
        await (update(espacios)..where((x) => x.id.equals(e.id))).write(
          EspaciosCompanion(ubicacionId: Value(conservadaId), updatedAt: Value(instante)),
        );
        pasados++;
        if (unePorUnico && unicoDeA == null && esUnico(e)) unicoDeA = e.id;
      }
    }

    // "Unir tipos": una casa que queda con más de un espacio pasa a edificio sola.
    final pasoAEdificio = tipoA == TipoUbicacion.casa && deA.length + pasados > 1;
    if (pasoAEdificio) {
      await (update(ubicaciones)..where((u) => u.id.equals(conservadaId))).write(
        UbicacionesCompanion(
          tipo: Value(UbicacionModel.codigoDeTipo(TipoUbicacion.edificio)),
          updatedAt: Value(instante),
        ),
      );
    }

    if (duplicada.deletedAt == null) {
      await (update(ubicaciones)..where((u) => u.id.equals(duplicadaId))).write(
        UbicacionesCompanion(updatedAt: Value(instante), deletedAt: Value(instante)),
      );
      // Misma marca que el `deleted_at`: así la Lista encuentra el motivo de esta baja (y no lo
      // muestra: `MotivosBaja.paraMostrar` oculta los `duplicado_de_*`).
      await into(auditLogLocal).insert(
        AuditLogLocalCompanion.insert(
          evento: EventoAuditoriaLocal.ubicacionBaja,
          uuid: duplicadaId,
          motivo: Value('${MotivosBaja.prefijoDuplicado}$conservadaId'),
          creadoEn: instante,
        ),
      );
    }

    if (pasoAEdificio) {
      final guardada = await _ubicacionPorId(conservadaId);
      await _encolador.encolar('ubicacion', OperacionSync.update, _aModelo(guardada!).toJson());
    }
    await _marcarDuplicado.encolarMarcarDuplicado(
      duplicadaId: duplicadaId,
      conservadaId: conservadaId,
    );
    return (
      escribio: true,
      espaciosPasados: pasados,
      espaciosFundidos: fundidos,
      conservadaPasoAEdificio: pasoAEdificio,
    );
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
  Stream<List<UbicacionConEspacios>> observarListaDelColportor({
    required String colportorId,
    bool incluirBajas = false,
  }) {
    // `distinct`: el segundo JOIN (la auditoría) puede repetir la fila de cada espacio.
    final cantidad = espacios.id.count(distinct: true);
    // El motivo de la baja vigente: el evento de esta ubicación con la misma marca que su `deleted_at`.
    // Una baja anterior ya reactivada, o una que vino del sync, no tiene la misma marca: sin motivo.
    final motivo = auditLogLocal.motivo.max();
    final consulta =
        select(ubicaciones).join([
            leftOuterJoin(
              espacios,
              espacios.ubicacionId.equalsExp(ubicaciones.id) & espacios.deletedAt.isNull(),
            ),
            leftOuterJoin(
              auditLogLocal,
              auditLogLocal.evento.equals(EventoAuditoriaLocal.ubicacionBaja) &
                  auditLogLocal.uuid.equalsExp(ubicaciones.id) &
                  auditLogLocal.creadoEn.equalsExp(ubicaciones.deletedAt),
            ),
          ])
          ..addColumns([cantidad, motivo])
          ..where(ubicaciones.createdBy.equals(colportorId))
          ..groupBy([ubicaciones.id]);
    if (!incluirBajas) consulta.where(ubicaciones.deletedAt.isNull());
    return consulta.watch().map(
      (filas) => [
        for (final fila in filas)
          (
            ubicacion: _aModelo(fila.readTable(ubicaciones)),
            cantidadEspacios: fila.read(cantidad) ?? 0,
            motivoBaja: fila.read(motivo),
          ),
      ],
    );
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
  ///   radioMetros` alrededor de [centro] (con margen), de cualquier ciudad;
  /// - si [centro] tiene calle y número, las de su ciudad dentro de un recuadro que contiene el
  ///   círculo de `CriterioDuplicadoUbicacion.radioMismaDireccionMetros` (con margen), escritas
  ///   como estén: así la regla de D1 (la misma dirección a menos de 100 m choca) la decide la
  ///   normalización del criterio y no esta consulta («av.  itália» y «Av. Italia» chocan); y
  /// - si [centro] tiene calle y número, las de su ciudad con el mismo número a cualquier
  ///   distancia (`lower(trim(…))` de los dos lados, así que el `lower` de SQLite, que solo pasa a
  ///   minúsculas el ASCII, es parejo). Para el aviso de «misma dirección» lejos: un número que
  ///   difiere a más de 100 m solo en tildes, espacios de más o mayúsculas no ASCII ("12 bís" y
  ///   "12 BIS") no sale acá: lo encuentra el scan de "Posibles duplicados", que compara en Dart.
  Future<List<CandidataDuplicado>> _candidatas(
    UbicacionModel centro,
    CriterioDuplicadoUbicacion criterio,
  ) async {
    const margen = CriterioDuplicadoUbicacion.radioMetros * 1.5;
    const margenMismaDireccion = CriterioDuplicadoUbicacion.radioMismaDireccionMetros * 1.5;
    final cosLat = math.cos(centro.lat * math.pi / 180).abs();
    final numero = centro.numero;
    final consulta = select(ubicaciones)
      ..where((u) {
        // Cerca de los polos un grado de longitud mide casi nada: ahí no se acota por longitud.
        Expression<bool> recuadro(double metros) {
          final dLat = metros / _metrosPorGrado;
          final enLatitud = u.lat.isBetweenValues(centro.lat - dLat, centro.lat + dLat);
          if (cosLat <= 0.01) return enLatitud;
          final dLon = metros / (_metrosPorGrado * cosLat);
          return enLatitud & u.lon.isBetweenValues(centro.lon - dLon, centro.lon + dLon);
        }

        final cerca = recuadro(margen);
        final Expression<bool> mismaDireccion;
        if (centro.calle == null || numero == null) {
          mismaDireccion = const Constant(false);
        } else {
          final mismaCiudad = u.ciudadId.equals(centro.ciudadId) & u.calle.isNotNull();
          mismaDireccion =
              mismaCiudad &
              (recuadro(margenMismaDireccion) |
                  u.numero.trim().lower().equalsExp(Variable(numero).trim().lower()));
        }
        return u.deletedAt.isNull() & u.id.equals(centro.id).not() & (cerca | mismaDireccion);
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

  // ---- EspacioLocalDataSource (HU-UBI-007): métodos nuevos al final para no chocar con #201. ----

  @override
  Future<InsercionEspacio> insertarEspacio(EspacioModel espacio) => transaction(() async {
    final existente = await _espacioPorId(espacio.id);
    if (existente != null) return (espacio: _aModeloEspacio(existente), yaEstaba: true);

    await _exigirUbicacionGestionable(espacio.ubicacionId, exigirActiva: true);
    await _exigirSinDuplicado(espacio.ubicacionId, espacio.numeroDepto);
    await into(espacios).insert(_aFilaEspacio(espacio));
    await _encolador.encolar('espacio', OperacionSync.insert, espacio.toJson());
    return (espacio: espacio, yaEstaba: false);
  });

  @override
  Future<EspacioModel> actualizarNumeroDepto(
    String id, {
    required String numeroDepto,
    required DateTime ahora,
  }) => transaction(() async {
    final fila = await _espacioActivoOLanzar(id);
    await _exigirUbicacionGestionable(fila.ubicacionId, exigirActiva: false);
    if (fila.numeroDepto == numeroDepto) return _aModeloEspacio(fila);

    await _exigirSinDuplicado(fila.ubicacionId, numeroDepto, excluirId: id);
    return _escribirEspacio(
      id,
      EspaciosCompanion(numeroDepto: Value(numeroDepto), updatedAt: Value(instanteMs(ahora))),
    );
  });

  @override
  Future<EspacioModel> darDeBajaEspacio(String id, {required DateTime ahora}) async {
    return transaction(() async {
      final fila = await _espacioPorId(id);
      if (fila == null) throw const EspacioRechazadoException(_Motivo.espacioInexistente);
      await _exigirUbicacionGestionable(fila.ubicacionId, exigirActiva: false);
      if (fila.deletedAt != null) return _aModeloEspacio(fila);

      final instante = instanteMs(ahora);
      return _escribirEspacio(
        id,
        EspaciosCompanion(deletedAt: Value(instante), updatedAt: Value(instante)),
      );
    });
  }

  @override
  Future<EspacioModel> restaurarEspacio(String id, {required DateTime ahora}) async {
    return transaction(() async {
      final fila = await _espacioPorId(id);
      if (fila == null) throw const EspacioRechazadoException(_Motivo.espacioInexistente);
      if (fila.deletedAt == null) return _aModeloEspacio(fila);

      await _exigirUbicacionGestionable(fila.ubicacionId, exigirActiva: true);
      await _exigirSinDuplicado(fila.ubicacionId, fila.numeroDepto, excluirId: id);
      return _escribirEspacio(
        id,
        EspaciosCompanion(deletedAt: const Value(null), updatedAt: Value(instanteMs(ahora))),
      );
    });
  }

  @override
  Future<({EspacioModel espacio, UbicacionModel ubicacion})?> buscarEspacio(String id) async {
    final fila = await _espacioPorId(id);
    if (fila == null) return null;
    final ubicacion = await _ubicacionPorId(fila.ubicacionId);
    // Sin FK (el pull no garantiza el orden): un espacio huérfano se trata como inexistente.
    if (ubicacion == null) return null;
    return (espacio: _aModeloEspacio(fila), ubicacion: _aModelo(ubicacion));
  }

  @override
  Future<List<EspacioModel>> listarEspacios(String ubicacionId, {bool incluirBajas = false}) async {
    final consulta = select(espacios)
      ..where((e) => e.ubicacionId.equals(ubicacionId))
      ..orderBy([(e) => OrderingTerm.asc(e.numeroDepto), (e) => OrderingTerm.asc(e.createdAt)]);
    if (!incluirBajas) consulta.where((e) => e.deletedAt.isNull());
    return [for (final fila in await consulta.get()) _aModeloEspacio(fila)];
  }

  // `contarEspaciosActivos` de EspacioLocalDataSource lo cumple el de UbicacionLocalDataSource
  // (misma firma, HU-UBI-004), más arriba.

  Future<EspacioFila?> _espacioPorId(String id) =>
      (select(espacios)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<UbicacionFila?> _ubicacionPorId(String id) =>
      (select(ubicaciones)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<EspacioFila> _espacioActivoOLanzar(String id) async {
    final fila = await _espacioPorId(id);
    if (fila == null) throw const EspacioRechazadoException(_Motivo.espacioInexistente);
    if (fila.deletedAt != null) throw const EspacioRechazadoException(_Motivo.espacioDeBaja);
    return fila;
  }

  /// La ubicación tiene que existir y no ser `CASA` (su espacio default no se gestiona); con
  /// [exigirActiva], además no puede estar dada de baja.
  Future<void> _exigirUbicacionGestionable(String ubicacionId, {required bool exigirActiva}) async {
    final ubicacion = await _ubicacionPorId(ubicacionId);
    if (ubicacion == null) throw const EspacioRechazadoException(_Motivo.ubicacionInexistente);
    if (UbicacionModel.tipoDesdeCodigo(ubicacion.tipo) == TipoUbicacion.casa) {
      throw const EspacioRechazadoException(_Motivo.ubicacionCasa);
    }
    if (exigirActiva && ubicacion.deletedAt != null) {
      throw const EspacioRechazadoException(_Motivo.ubicacionDeBaja);
    }
  }

  /// Lanza si otro espacio activo de la ubicación tiene el mismo número (sin espacios en los
  /// bordes ni distinción de mayúsculas). Un número `null` no se compara.
  Future<void> _exigirSinDuplicado(
    String ubicacionId,
    String? numeroDepto, {
    String? excluirId,
  }) async {
    final clave = _claveDepto(numeroDepto);
    if (clave == null) return;
    final activos = await (select(
      espacios,
    )..where((e) => e.ubicacionId.equals(ubicacionId) & e.deletedAt.isNull())).get();
    if (activos.any((e) => e.id != excluirId && _claveDepto(e.numeroDepto) == clave)) {
      throw const EspacioRechazadoException(_Motivo.deptoDuplicado);
    }
  }

  static String? _claveDepto(String? numeroDepto) {
    final limpio = numeroDepto?.trim().toLowerCase();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }

  /// Aplica [cambios] a [id], lee la fila resultante y encola su `update` con la fila entera.
  Future<EspacioModel> _escribirEspacio(String id, EspaciosCompanion cambios) async {
    await (update(espacios)..where((e) => e.id.equals(id))).write(cambios);
    final modelo = _aModeloEspacio((await _espacioPorId(id))!);
    await _encolador.encolar('espacio', OperacionSync.update, modelo.toJson());
    return modelo;
  }

  static EspacioModel _aModeloEspacio(EspacioFila fila) => EspacioModel(
    id: fila.id,
    ubicacionId: fila.ubicacionId,
    numeroDepto: fila.numeroDepto,
    piso: fila.piso,
    descripcion: fila.descripcion,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );
}
