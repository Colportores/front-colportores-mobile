import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../domain/entities/color_house_status.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/espacio.dart';
import '../../domain/entities/espacio_persona.dart';
import '../../domain/entities/espacios_activos.dart';
import '../../domain/entities/marcador_mapa.dart';
import '../../domain/entities/motivo_baja.dart';
import '../../domain/entities/motivo_rechazo_espacio.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/services/criterio_duplicado_ubicacion.dart';
import '../../domain/services/encolador_marcar_duplicado.dart';
import '../../domain/services/house_status_updater.dart';
import '../../domain/value_objects/area_mapa.dart';
import '../models/espacio_model.dart';
import '../models/espacio_persona_model.dart';
import '../models/ubicacion_model.dart';
import '../services/fuentes_sin_adaptador_ubicaciones.dart' show EncoladorMarcarDuplicadoSinMotor;
import '../services/house_status_updater_drift.dart';
import 'audit_log_table.dart';
import 'espacio_local_data_source.dart';
import 'espacios_table.dart';
import 'house_status_table.dart';
import 'notas_table.dart' show TipoObjetivoNota;
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
@DriftAccessor(tables: [Ubicaciones, Espacios, AuditLogLocal, HouseStatuses])
final class UbicacionLocalDataSourceDrift extends DatabaseAccessor<AppDatabase>
    with _$UbicacionLocalDataSourceDriftMixin
    implements UbicacionLocalDataSource, EspacioLocalDataSource {
  /// [_encolador] se pasa como `encolador:` (parámetro nombrado privado, Dart ≥ 3.10). El trabajo
  /// «marcar como duplicado» entra por [_marcarDuplicado]: sin motor de sync (#178), falla.
  /// [estadoDeLasCasas] recalcula el color de las dos casas al unirlas (R-UB08); sin él se usa el
  /// de siempre (`HouseStatusUpdaterDrift`, con este mismo encolador).
  UbicacionLocalDataSourceDrift(
    super.attachedDatabase, {
    required this._encolador,
    this._marcarDuplicado = const EncoladorMarcarDuplicadoSinMotor(),
    HouseStatusUpdater? estadoDeLasCasas,
  }) : _estadoInyectado = estadoDeLasCasas;

  final EncoladorSync _encolador;
  final EncoladorMarcarDuplicado _marcarDuplicado;
  final HouseStatusUpdater? _estadoInyectado;

  late final HouseStatusUpdater _estadoDeLasCasas =
      _estadoInyectado ?? HouseStatusUpdaterDrift(attachedDatabase, encolador: _encolador);

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
    EspacioModel? espacioSiNoTiene,
  }) => transaction(() async {
    final fila = await (select(ubicaciones)..where((u) => u.id.equals(nueva.id))).getSingleOrNull();
    if (fila == null) throw const UbicacionInexistenteException();
    if (fila.updatedAt != instanteMs(baseUpdatedAt)) throw const UbicacionCambioException();
    // Reactivar al guardar: una baja por unión de duplicados no se reactiva (HU-UBI-005).
    if (nueva.auditoria.deletedAt == null) {
      final union = await _unionDe(fila);
      if (union != null) throw union;
    }

    // S17: para quedar con un solo espacio (de edificio a casa o negocio, de negocio a casa) tiene
    // que haber un depto como mucho; ese depto pasa a ser el espacio de la casa o del negocio y
    // pierde el número. Los de baja no cuentan. Sin ninguno, una casa recibe su espacio default
    // (S13, decisión de Cristian 21/10 «Casa vacía»).
    EspacioFila? deptoConNumero;
    var creaEspacio = false;
    if (reduceAUnEspacio) {
      final activos = await (select(
        espacios,
      )..where((e) => e.ubicacionId.equals(nueva.id) & e.deletedAt.isNull())).get();
      if (activos.length > 1) throw UbicacionConEspaciosException(activos.length);
      deptoConNumero = activos.where((e) => e.numeroDepto != null).firstOrNull;
      creaEspacio = activos.isEmpty && espacioSiNoTiene != null;
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
    if (creaEspacio) {
      await into(espacios).insert(_aFilaEspacio(espacioSiNoTiene!));
      await _encolador.encolar('espacio', OperacionSync.insert, espacioSiNoTiene.toJson());
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
    CriterioDuplicadoUbicacion? duplicados,
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
    if (deletedAt == null) await _exigirReactivable(fila, duplicados);

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

  /// El motivo `duplicado_de_<A>` de la baja vigente de [fila] si nació de unir duplicados
  /// (HU-UBI-006), o `null` si no: su evento `ubicacion_baja` en la auditoría local, con la misma marca
  /// que `deleted_at`. Una baja que llegó del servidor, sin fila local, no se reconoce (no se inventa
  /// un motivo). El prefijo se compara en Dart y no con `LIKE`: el `_` del patrón es un comodín y
  /// «duplicado de la casa» (texto libre de «Otro») pasaría por una unión.
  Future<String?> _motivoDeUnion(UbicacionFila fila) async {
    final marca = fila.deletedAt;
    if (marca == null) return null;
    final motivos =
        await (select(auditLogLocal)..where(
              (a) =>
                  a.evento.equals(EventoAuditoriaLocal.ubicacionBaja) &
                  a.uuid.equals(fila.id) &
                  a.creadoEn.equalsValue(marca),
            ))
            .map((a) => a.motivo)
            .get();
    return motivos.where(MotivosBaja.esUnion).firstOrNull;
  }

  /// La excepción a lanzar si la baja vigente de [fila] nació de unir duplicados (HU-UBI-006), o
  /// `null` si no (la excepción lleva la `A` de `duplicado_de_<A>`, ver [_conservadaFinal]).
  Future<ReactivacionDeUnionException?> _unionDe(UbicacionFila fila) async {
    final union = await _motivoDeUnion(fila);
    if (union == null) return null;
    return ReactivacionDeUnionException(
      conservadaId: await _conservadaFinal(MotivosBaja.conservadaDe(union)),
    );
  }

  /// Hasta cuántas uniones seguidas se siguen para dar con la ubicación que quedó (B se unió a A y A
  /// a C: B termina en C). Más allá, o con un ciclo, no se ofrece ninguna.
  static const _maximoSaltosDeUnion = 8;

  /// La ubicación a la que apunta la cadena de uniones que empieza en [primera]: la primera activa
  /// que encuentra siguiendo el `duplicado_de_<A>` de cada baja por unión. Si la cadena se corta (la
  /// ubicación no existe o está de baja por otro motivo), se pasa de largo, o se cierra en un ciclo,
  /// devuelve la última que alcanzó (de baja o inexistente): el repositorio solo ofrece abrir una
  /// activa. `null` si [primera] es `null`.
  Future<String?> _conservadaFinal(String? primera) async {
    var actual = primera;
    final vistas = <String>{};
    while (actual != null && vistas.length < _maximoSaltosDeUnion && vistas.add(actual)) {
      final fila = await _ubicacionPorId(actual);
      if (fila == null || fila.deletedAt == null) return actual;
      final siguiente = MotivosBaja.conservadaDe(await _motivoDeUnion(fila));
      if (siguiente == null) return actual;
      actual = siguiente;
    }
    return actual;
  }

  /// Lo que se exige antes de reactivar la baja [fila] (HU-UBI-005, «Reactivar»), dentro de la
  /// transacción: que no sea una unión de duplicados ([ReactivacionDeUnionException]) y, si llega
  /// [duplicados], que ninguna activa choque con ella ([UbicacionDuplicadaException]; con el criterio
  /// de `alSeguirIgual`, solo D1: la misma dirección a menos de 100 m).
  Future<void> _exigirReactivable(
    UbicacionFila fila,
    CriterioDuplicadoUbicacion? duplicados,
  ) async {
    final union = await _unionDe(fila);
    if (union != null) throw union;
    if (duplicados == null) return;
    final candidatas = await _candidatas(_aModelo(fila), duplicados);
    if (candidatas.isNotEmpty) throw UbicacionDuplicadaException(candidatas);
  }

  /// Los espacios sin baja de [ubicacionId], del más viejo al más nuevo (el orden de la RPC 0026).
  Future<List<EspacioFila>> _espaciosActivosEnOrden(String ubicacionId) =>
      (select(espacios)
            ..where((e) => e.ubicacionId.equals(ubicacionId) & e.deletedAt.isNull())
            ..orderBy([(e) => OrderingTerm.asc(e.createdAt), (e) => OrderingTerm.asc(e.id)]))
          .get();

  /// La ubicación alternativa de cobranza en una unión (HU-UBI-013, `espacio_persona`): lo que nombra
  /// a B ([duplicadaId]) pasa a nombrar a A ([conservadaId]), como hace el servidor al aplicar la
  /// unión, para que la persona no quede con una alternativa «dada de baja» que en realidad es la
  /// conservada. Si la alternativa queda siendo la ubicación de su propio espacio (la persona estaba
  /// en una y cobraba en la otra, que ahora son una sola), se quita: la HU no admite la propia
  /// ubicación como alternativa y no se pierde nada, porque la cobranza va ahí igual.
  ///
  /// Devuelve los vínculos que quedaron **sin** alternativa, que son los únicos que el servidor no
  /// produce solo y por eso se encolan; el reapuntado lo aplica él.
  Future<List<EspacioPersona>> _reapuntarCobranzaAlternativa({
    required String duplicadaId,
    required String conservadaId,
    required DateTime instante,
  }) async {
    final vinculos = attachedDatabase.espacioPersonas;
    final nombranA = await (attachedDatabase.select(
      vinculos,
    )..where((v) => v.ubicacionCobranzaAltId.equals(duplicadaId))).get();
    for (final vinculo in nombranA) {
      await (attachedDatabase.update(vinculos)..where((v) => v.id.equals(vinculo.id))).write(
        EspacioPersonasCompanion(
          ubicacionCobranzaAltId: Value(conservadaId),
          updatedAt: Value(_noRetrocede(instante, vinculo.updatedAt)),
        ),
      );
    }

    final espaciosDeA = selectOnly(espacios)
      ..addColumns([espacios.id])
      ..where(espacios.ubicacionId.equals(conservadaId));
    final propias =
        await (attachedDatabase.select(vinculos)..where(
              (v) =>
                  v.ubicacionCobranzaAltId.equals(conservadaId) &
                  v.espacioId.isInQuery(espaciosDeA),
            ))
            .get();
    final sinAlternativa = <EspacioPersona>[];
    for (final vinculo in propias) {
      final cuando = _noRetrocede(instante, vinculo.updatedAt);
      await (attachedDatabase.update(vinculos)..where((v) => v.id.equals(vinculo.id))).write(
        EspacioPersonasCompanion(
          ubicacionCobranzaAltId: const Value(null),
          updatedAt: Value(cuando),
        ),
      );
      sinAlternativa.add(
        EspacioPersona(
          id: vinculo.id,
          espacioId: vinculo.espacioId,
          personaId: vinculo.personaId,
          auditoria: Auditoria(
            createdAt: vinculo.createdAt,
            updatedAt: cuando,
            createdBy: vinculo.createdBy,
            deletedAt: vinculo.deletedAt,
            syncVersion: vinculo.syncVersion,
          ),
        ),
      );
    }
    return sinAlternativa;
  }

  /// El reloj no retrocede: un `updated_at` nunca queda antes del que ya tenía la fila.
  static DateTime _noRetrocede(DateTime instante, DateTime actual) =>
      instante.isBefore(actual) ? actual : instante;

  /// La unión de un par de duplicados (HU-UBI-006), espejo local de la RPC `marcar_como_duplicado`
  /// (backend-supabase 0026), en una sola transacción:
  ///
  /// - **Espacios de B** (los activos; los de baja se quedan en B): pasan a A tal cual (cambia
  ///   `ubicacion_id`, sin mezclarse ni validar `numero_depto` repetido), salvo el espacio único
  ///   (`numero_depto` nulo o en blanco) cuando A y B son casa o negocio: se funde en el único vivo
  ///   más viejo de A (el de B queda de baja) o, si A no tiene, pasa a serlo.
  /// - **A casa con más de un espacio** pasa a edificio ("Unir tipos"); un negocio sigue negocio.
  /// - **B** queda de baja con `duplicado_de_<A>` en el `audit_log` local (no se sincroniza).
  /// - **Cobranza alternativa**: los vínculos que nombraban a B pasan a nombrar a A (ver
  ///   [_reapuntarCobranzaAlternativa]); los que quedan sin alternativa se encolan como `update`.
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
        // Lo que colgaba del espacio de B (sus personas, visitas y agendas) pasa al único de A
        // antes de dar de baja el de B: no se borra ni se deja huérfano nada.
        await _pasarLoQueCuelgaDe(e.id, a: unicoDeA, instante: instante);
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

    // Quien cobraba en B ahora cobra en A (el servidor hace lo mismo al aplicar la unión).
    final vinculosSinAlternativa = await _reapuntarCobranzaAlternativa(
      duplicadaId: duplicadaId,
      conservadaId: conservadaId,
      instante: instante,
    );

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

    // Quien hace la unión es el dueño de las casas: el `created_by` de una fila de `house_status`
    // nueva. Las casas del par son suyas (el scan compara solo las propias).
    final colportorId = conservada.createdBy ?? duplicada.createdBy ?? '';
    await _reapuntarAlternativas(duplicadaId, a: conservadaId, instante: instante);
    await _pasarNotasDelLugar(duplicadaId, a: conservadaId, instante: instante);
    if (duplicada.deletedAt == null) {
      // Ya sin espacios activos ni nada colgado: su fila de `house_status` se da de baja con B
      // (el recálculo de una ubicación viva sin eventos), antes de marcar la baja.
      await _estadoDeLasCasas.recalcular(duplicadaId, ahora: ahora, colportorId: colportorId);
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
    // El color de A se recalcula con todo lo que ahora cuelga de ella (lo suyo y lo de B), con la
    // prioridad de siempre y en la misma transacción (R-UB08, ADR-003).
    await _estadoDeLasCasas.recalcular(conservadaId, ahora: ahora, colportorId: colportorId);
    for (final vinculo in vinculosSinAlternativa) {
      await _encolador.encolar(
        'espacio_persona',
        OperacionSync.update,
        EspacioPersonaModel.fromEntity(vinculo).toJson(),
      );
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

  /// Las notas del lugar de [deB] (`nota` con `target_type = UBICACION`) pasan al lugar [a], también
  /// las dadas de baja: la hoja de A muestra las de las dos y nada se pierde. Cuelgan de la
  /// ubicación y no del espacio, así que pasan aunque el único de B no se funda. Son solo locales
  /// (`SyncSpec.local`): no hay nada que encolar.
  Future<void> _pasarNotasDelLugar(
    String deB, {
    required String a,
    required DateTime instante,
  }) async {
    final db = attachedDatabase;
    await (db.update(db.notas)
          ..where((x) => x.targetType.equals(TipoObjetivoNota.ubicacion) & x.targetId.equals(deB)))
        .write(NotasCompanion(targetId: Value(a), updatedAt: Value(instante)));
  }

  /// Lo que nombraba a la ubicación [deB] como casa alternativa (`agenda.ubicacion_alt_id` y
  /// `espacio_persona.ubicacion_cobranza_alt_id`) pasa a nombrar a [a]: B queda de baja y una
  /// referencia a ella no llevaría a ningún lado (HU-UBI-006, «Venta ajena»: el servidor hace lo
  /// mismo con las suyas). Sin encolar por fila, como el resto de la unión.
  Future<void> _reapuntarAlternativas(
    String deB, {
    required String a,
    required DateTime instante,
  }) async {
    final db = attachedDatabase;
    await (db.update(db.agendas)..where((x) => x.ubicacionAltId.equals(deB))).write(
      AgendasCompanion(ubicacionAltId: Value(a), updatedAt: Value(instante)),
    );
    await (db.update(db.espacioPersonas)..where((x) => x.ubicacionCobranzaAltId.equals(deB))).write(
      EspacioPersonasCompanion(ubicacionCobranzaAltId: Value(a), updatedAt: Value(instante)),
    );
  }

  /// Repunta al espacio [a] lo que colgaba del espacio fundido [deB]: los vínculos con sus
  /// personas, las visitas y las agendas (también las dadas de baja: el historial se conserva).
  /// Las filas siguen con su vínculo y su persona; solo cambia el espacio al que pertenecen. No se
  /// encola nada por fila: el servidor repite la unión cuando le llega el trabajo «marcar como
  /// duplicado» (HU-UBI-006), como con los espacios que pasan enteros. Las ventas, entregas y
  /// cobranzas todavía no están en el teléfono.
  Future<void> _pasarLoQueCuelgaDe(
    String deB, {
    required String a,
    required DateTime instante,
  }) async {
    final db = attachedDatabase;
    await (db.update(db.espacioPersonas)..where((x) => x.espacioId.equals(deB))).write(
      EspacioPersonasCompanion(espacioId: Value(a), updatedAt: Value(instante)),
    );
    await (db.update(db.visitas)..where((x) => x.espacioId.equals(deB))).write(
      VisitasCompanion(espacioId: Value(a), updatedAt: Value(instante)),
    );
    await (db.update(db.agendas)..where((x) => x.espacioId.equals(deB))).write(
      AgendasCompanion(espacioId: Value(a), updatedAt: Value(instante)),
    );
  }

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
            // El color vigente de la casa: una fila por ubicación, y la dada de baja (la casa volvió
            // a «Sin visita») no cuenta. Al estar en la consulta, un cambio de `house_status` hace
            // que el stream emita de nuevo.
            leftOuterJoin(
              houseStatuses,
              houseStatuses.ubicacionId.equalsExp(ubicaciones.id) &
                  houseStatuses.deletedAt.isNull(),
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
            color: _colorDe(fila.readTableOrNull(houseStatuses)),
            motivoBaja: fila.read(motivo),
          ),
      ],
    );
  }

  /// El color de la fila de `house_status`, o `null` si la ubicación no tiene (es «Sin visita»).
  static ColorHouseStatus? _colorDe(HouseStatusFila? fila) =>
      fila == null ? null : ColorHouseStatus.desdeCodigo(fila.color);

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
  Future<EspacioModel> actualizarEspacio(
    String id, {
    required String numeroDepto,
    String? piso,
    required DateTime ahora,
  }) => transaction(() async {
    final fila = await _espacioActivoOLanzar(id);
    await _exigirUbicacionGestionable(fila.ubicacionId, exigirActiva: false);
    if (fila.numeroDepto == numeroDepto && fila.piso == piso) return _aModeloEspacio(fila);

    // Solo un número nuevo se compara con los demás: cambiar el piso de un depto que ya estaba no
    // tiene que fallar por un repetido que venía de antes (por ejemplo, de otro teléfono).
    if (_claveDepto(fila.numeroDepto) != _claveDepto(numeroDepto)) {
      await _exigirSinDuplicado(fila.ubicacionId, numeroDepto, excluirId: id);
    }
    return _escribirEspacio(
      id,
      EspaciosCompanion(
        numeroDepto: Value(numeroDepto),
        piso: Value(piso),
        updatedAt: Value(instanteMs(ahora)),
      ),
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

  /// Lanza si otro espacio activo de la ubicación tiene el mismo número (sin espacios ni distinción
  /// de mayúsculas: «3B» y «3 b» son el mismo). Un número `null` no se compara.
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

  static String? _claveDepto(String? numeroDepto) => Espacio.claveDeNumero(numeroDepto);

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
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );
}
