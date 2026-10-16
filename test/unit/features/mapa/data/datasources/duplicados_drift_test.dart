// Duplicados de ubicación (HU-UBI-006) contra las tablas reales: AppDatabase en memoria (sin
// cifrado), del caso de uso a los repositorios y a Drift. Los escenarios llevan el título de la HU.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/pares_duplicados_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/pares_duplicados_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/pares_duplicados_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/fuentes_sin_adaptador_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_union_duplicados.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/duplicados_ubicacion_use_cases.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../../helpers/duplicados_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

final class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

final class _LocalQueFalla implements ParesDuplicadosLocalDataSource {
  @override
  Future<Map<String, ParDecidido>> decididos() => throw StateError('disco');

  @override
  Stream<Map<String, ParDecidido>> observarDecididos() => Stream.error(StateError('disco'));

  @override
  Future<void> decidir(
    String ubicacionId1,
    String ubicacionId2,
    DecisionParDuplicado decision, {
    required DateTime decididoEn,
  }) => throw StateError('disco');
}

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 13, 45, 10, 123);
  var ahora = DateTime.utc(2026, 10, 1, 9);

  UbicacionModel ubicacion(
    String id, {
    String? calle = 'Av. Italia',
    double metrosAlNorte = 0,
    String colportor = 'col-1',
    DateTime? creada,
    TipoUbicacion tipo = TipoUbicacion.casa,
  }) => UbicacionModel(
    id: id,
    tipo: tipo,
    calle: calle,
    numero: '1234',
    lat: -34.891 + metrosAlNorte / 111195.08,
    lon: -56.125,
    ciudadId: 'mvd',
    auditoria: Auditoria(createdAt: creada ?? t0, updatedAt: t0, createdBy: colportor),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift ubicaciones;
  late ParesDuplicadosLocalDataSourceDrift paresLocal;
  late EncoladorMarcarDuplicadoFalso marcador;
  late _SalidaEnMemoria salida;
  late ConsultarParesDuplicadosUseCase consultar;
  late DecidirParDuplicadoUseCase decidir;
  late UnirDuplicadosUseCase unir;

  setUp(() {
    ahora = DateTime.utc(2026, 10, 1, 9);
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    marcador = EncoladorMarcarDuplicadoFalso();
    ubicaciones = UbicacionLocalDataSourceDrift(
      db,
      encolador: encolador,
      marcarDuplicado: marcador,
    );
    paresLocal = ParesDuplicadosLocalDataSourceDrift(db);
    salida = _SalidaEnMemoria();
    final repoUbicaciones = UbicacionRepositoryImpl(ubicaciones, logger: AppLogger(output: salida));
    final repoPares = ParesDuplicadosRepositoryImpl(paresLocal, logger: loggerMudo());
    consultar = ConsultarParesDuplicadosUseCase(repoUbicaciones, repoPares, ahora: () => ahora);
    decidir = DecidirParDuplicadoUseCase(repoPares, ahora: () => ahora);
    unir = UnirDuplicadosUseCase(repoUbicaciones, ahora: () => ahora);
  });

  tearDown(() => db.close());

  Future<List<ParDuplicado>> scan() async => (await consultar(
    const ConsultarParesDuplicadosParams(colportorId: 'col-1'),
  )).getOrElse(() => throw StateError('el scan falló'));

  Future<List<AuditLogFila>> auditoria() =>
      (db.select(db.auditLogLocal)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  EspacioModel espacio(
    String id,
    String ubicacionId, {
    String? numeroDepto,
    DateTime? creado,
    DateTime? deletedAt,
  }) => EspacioModel(
    id: id,
    ubicacionId: ubicacionId,
    numeroDepto: numeroDepto,
    auditoria: Auditoria(
      createdAt: creado ?? t0,
      updatedAt: creado ?? t0,
      createdBy: 'col-1',
      deletedAt: deletedAt,
    ),
  );

  /// Un espacio más, directo en la tabla (`insertarEspacio` no admite casas).
  Future<void> agregarEspacio(
    String id,
    String ubicacionId, {
    String? numeroDepto,
    DateTime? creado,
    DateTime? deletedAt,
  }) => db
      .into(db.espacios)
      .insert(
        EspaciosCompanion.insert(
          id: id,
          ubicacionId: ubicacionId,
          numeroDepto: Value(numeroDepto),
          createdAt: creado ?? t0,
          updatedAt: creado ?? t0,
          deletedAt: Value(deletedAt),
        ),
      );

  /// Los espacios de la DB: `id` → (a qué ubicación pertenece, si está de baja).
  Future<Map<String, (String, bool)>> espaciosDeLaDb() async => {
    for (final e in await db.select(db.espacios).get()) e.id: (e.ubicacionId, e.deletedAt != null),
  };

  Future<void> sembrarPar() async {
    await ubicaciones.insertar(ubicacion('ub-a', creada: t0));
    await ubicaciones.insertar(
      ubicacion('ub-b', metrosAlNorte: 300, creada: t0.add(const Duration(days: 2))),
    );
    encolador.encolados.clear();
  }

  group('Escenario: Scan detecta 2 candidatos', () {
    test(
      'dado que tengo dos ubicaciones que ahora cumplen la heurística de duplicado, cuando el '
      'scan corre, muestra el par (con la más vieja como A) y no toma las de otro colportor',
      () async {
        await sembrarPar();
        await ubicaciones.insertar(ubicacion('ub-ajena', metrosAlNorte: 1, colportor: 'col-2'));

        final pares = await scan();

        expect(pares, hasLength(1));
        expect((pares.single.a.id, pares.single.b.id), ('ub-a', 'ub-b'));
        expect(pares.single.motivo, MotivoDuplicado.mismaDireccion);
        expect(await db.select(db.ubicaciones).get(), hasLength(3), reason: 'el scan no escribe');
      },
    );
  });

  group('Escenario: Conservar A, baja a B', () {
    test('dado que en un par candidato decido conservar A, cuando confirmo "Conservar A y unir", '
        'B se da de baja con el motivo duplicado_de_A, se encola el trabajo y el par deja de '
        'aparecer', () async {
      await sembrarPar();
      final par = (await scan()).single;

      final r = await unir(UnirDuplicadosParams(conservarId: par.a.id, duplicadaId: par.b.id));

      expect(r.getOrElse(() => throw StateError('falló')).escribio, isTrue);
      expect((await ubicaciones.obtener('ub-b'))!.auditoria.deletedAt, ahora);
      expect((await ubicaciones.obtener('ub-a'))!.auditoria.deletedAt, isNull);
      expect(marcador.encolados, [(duplicadaId: 'ub-b', conservadaId: 'ub-a')]);
      expect(encolador.encolados, isEmpty, reason: 'A no cambió: no hay fila para subir');
      final log = await auditoria();
      expect(log, hasLength(1));
      expect(
        (log.single.evento, log.single.uuid, log.single.motivo, log.single.creadoEn),
        (EventoAuditoriaLocal.ubicacionBaja, 'ub-b', 'duplicado_de_ub-a', ahora),
        reason: 'el motivo queda en el audit_log local, con la misma marca que el deleted_at',
      );
      expect(await scan(), isEmpty);
    });

    test(
      'dado que el colportor elige conservar B, cuando une, es A la que queda de baja',
      () async {
        await sembrarPar();

        await unir(const UnirDuplicadosParams(conservarId: 'ub-b', duplicadaId: 'ub-a'));

        expect((await ubicaciones.obtener('ub-a'))!.auditoria.estaBorrada, isTrue);
        expect((await ubicaciones.obtener('ub-b'))!.auditoria.estaBorrada, isFalse);
        expect((await auditoria()).single.motivo, 'duplicado_de_ub-b');
      },
    );

    test('dado dos casas con su espacio único cada una, cuando se unen, los dos únicos se funden '
        'en uno: el de B queda de baja y A sigue siendo casa con un espacio', () async {
      await ubicaciones.insertar(ubicacion('ub-a', creada: t0), espacio: espacio('e-a', 'ub-a'));
      await ubicaciones.insertar(
        ubicacion('ub-b', metrosAlNorte: 300),
        espacio: espacio('e-b', 'ub-b', numeroDepto: '  '),
      );
      encolador.encolados.clear();

      final r = (await unir(
        const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'),
      )).getOrElse(() => throw StateError('falló'));

      expect(r.espaciosFundidos, 1);
      expect(r.espaciosPasados, 0);
      expect(r.conservadaPasoAEdificio, isFalse);
      expect(await espaciosDeLaDb(), {'e-a': ('ub-a', false), 'e-b': ('ub-b', true)});
      expect((await ubicaciones.obtener('ub-a'))!.tipo, TipoUbicacion.casa);
    });

    test('dado un edificio de B con tres deptos numerados, cuando se unen, los tres pasan a A tal '
        'cual y A (edificio) no se vuelve a subir', () async {
      await ubicaciones.insertar(
        ubicacion('ub-a', tipo: TipoUbicacion.edificio, creada: t0),
        espacio: espacio('a1', 'ub-a', numeroDepto: '1A'),
      );
      await ubicaciones.insertar(
        ubicacion('ub-b', tipo: TipoUbicacion.edificio, metrosAlNorte: 300),
      );
      for (final (id, n) in [('b1', '1A'), ('b2', '2B'), ('b3', '3C')]) {
        await agregarEspacio(id, 'ub-b', numeroDepto: n);
      }
      encolador.encolados.clear();

      final r = (await unir(
        const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'),
      )).getOrElse(() => throw StateError('falló'));

      expect(
        r.espaciosPasados,
        3,
        reason: 'el "1A" repetido no se mezcla ni se valida: pasa igual',
      );
      expect(r.espaciosFundidos, 0);
      expect(await espaciosDeLaDb(), {
        'a1': ('ub-a', false),
        'b1': ('ub-a', false),
        'b2': ('ub-a', false),
        'b3': ('ub-a', false),
      });
      expect(encolador.encolados, isEmpty);
    });

    test(
      'dado una casa A que se une con un edificio de dos deptos, cuando termina, A pasa a '
      'edificio en la misma transacción y se encola su actualización antes que el trabajo',
      () async {
        await ubicaciones.insertar(ubicacion('ub-a', creada: t0), espacio: espacio('e-a', 'ub-a'));
        await ubicaciones.insertar(
          ubicacion('ub-b', tipo: TipoUbicacion.edificio, metrosAlNorte: 300),
        );
        await agregarEspacio('b1', 'ub-b', numeroDepto: '1');
        await agregarEspacio('b2', 'ub-b', numeroDepto: '2');
        encolador.encolados.clear();

        final r = (await unir(
          const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'),
        )).getOrElse(() => throw StateError('falló'));

        expect(r.conservadaPasoAEdificio, isTrue);
        expect((await ubicaciones.obtener('ub-a'))!.tipo, TipoUbicacion.edificio);
        expect(encolador.encolados.map((c) => (c.entidad, c.operacion, c.payload['id'])), [
          ('ubicacion', OperacionSync.update, 'ub-a'),
        ]);
        expect(encolador.encolados.single.payload['tipo'], 'EDIFICIO');
        expect(marcador.encolados, [(duplicadaId: 'ub-b', conservadaId: 'ub-a')]);
      },
    );

    test('dado un negocio A y una casa B con su espacio único, cuando se unen, A sigue negocio y '
        'los únicos se funden', () async {
      await ubicaciones.insertar(
        ubicacion('ub-a', tipo: TipoUbicacion.negocio, creada: t0),
        espacio: espacio('e-a', 'ub-a'),
      );
      await ubicaciones.insertar(
        ubicacion('ub-b', metrosAlNorte: 300),
        espacio: espacio('e-b', 'ub-b'),
      );
      encolador.encolados.clear();

      final r = (await unir(
        const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'),
      )).getOrElse(() => throw StateError('falló'));

      expect((r.espaciosFundidos, r.conservadaPasoAEdificio), (1, false));
      expect((await ubicaciones.obtener('ub-a'))!.tipo, TipoUbicacion.negocio);
      expect(encolador.encolados, isEmpty);
    });

    test('dado una casa A sin ningún espacio, cuando se une con una casa B con su único, el de B '
        'pasa a ser el único de A y A sigue siendo casa', () async {
      await sembrarPar();
      await agregarEspacio('e-b', 'ub-b');

      final r = (await unir(
        const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'),
      )).getOrElse(() => throw StateError('falló'));

      expect((r.espaciosPasados, r.espaciosFundidos, r.conservadaPasoAEdificio), (1, 0, false));
      expect(await espaciosDeLaDb(), {'e-b': ('ub-a', false)});
    });

    test('dado un depto de B que ya estaba de baja, cuando se unen, se queda en B (solo pasan los '
        'activos)', () async {
      await ubicaciones.insertar(
        ubicacion('ub-a', tipo: TipoUbicacion.edificio, creada: t0),
        espacio: espacio('a1', 'ub-a', numeroDepto: '1'),
      );
      await ubicaciones.insertar(
        ubicacion('ub-b', tipo: TipoUbicacion.edificio, metrosAlNorte: 300),
      );
      await agregarEspacio('b1', 'ub-b', numeroDepto: '2');
      await agregarEspacio('b-baja', 'ub-b', numeroDepto: '3', deletedAt: t0);

      await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      expect(await espaciosDeLaDb(), {
        'a1': ('ub-a', false),
        'b1': ('ub-a', false),
        'b-baja': ('ub-b', true),
      });
    });

    test('dado que la unión ya se hizo, cuando se repite (dos toques que se pisan o el sync trajo '
        'la unión), devuelve yaUnida y no encola nada más', () async {
      await sembrarPar();
      await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));
      final bajaB = (await ubicaciones.obtener('ub-b'))!.auditoria.updatedAt;
      ahora = ahora.add(const Duration(minutes: 5));

      final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      expect(r, const Right<Failure, ResultadoUnionDuplicados>(ResultadoUnionDuplicados.yaUnida));
      expect(marcador.encolados, hasLength(1));
      expect(await auditoria(), hasLength(1));
      expect((await ubicaciones.obtener('ub-b'))!.auditoria.updatedAt, bajaB);
    });

    test('dado que B ya estaba de baja pero todavía tiene deptos activos (la baja llegó por sync), '
        'cuando se une, mueve los deptos sin pisar la baja ni repetir la auditoría', () async {
      await ubicaciones.insertar(
        ubicacion('ub-a', tipo: TipoUbicacion.edificio, creada: t0),
        espacio: espacio('a1', 'ub-a', numeroDepto: '1'),
      );
      await ubicaciones.insertar(
        ubicacion('ub-b', tipo: TipoUbicacion.edificio, metrosAlNorte: 300),
      );
      await ubicaciones.cambiarBaja('ub-b', baseUpdatedAt: t0, updatedAt: t0, deletedAt: t0);
      await agregarEspacio('b1', 'ub-b', numeroDepto: '2');

      final r = (await unir(
        const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'),
      )).getOrElse(() => throw StateError('falló'));

      expect(r.espaciosPasados, 1);
      expect((await ubicaciones.obtener('ub-b'))!.auditoria.deletedAt, t0);
      expect(await auditoria(), isEmpty);
      expect(await espaciosDeLaDb(), {'a1': ('ub-a', false), 'b1': ('ub-a', false)});
    });

    test('dado que la que se conserva está de baja, cuando une, devuelve FailureConservadaDeBaja y '
        'no escribe nada: la duplicada sigue viva', () async {
      await sembrarPar();
      await ubicaciones.cambiarBaja('ub-a', baseUpdatedAt: t0, updatedAt: ahora, deletedAt: ahora);
      encolador.encolados.clear();

      final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      expect(r, const Left<Failure, ResultadoUnionDuplicados>(FailureConservadaDeBaja()));
      expect((await ubicaciones.obtener('ub-b'))!.auditoria.estaBorrada, isFalse);
      expect(await auditoria(), isEmpty);
      expect(marcador.encolados, isEmpty);
    });

    test(
      'dado que alguna de las dos no existe, cuando une, devuelve FailureUbicacionInexistente',
      () async {
        await sembrarPar();

        final sinB = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'x'));
        final sinA = await unir(const UnirDuplicadosParams(conservarId: 'x', duplicadaId: 'ub-b'));

        expect(sinB, const Left<Failure, ResultadoUnionDuplicados>(FailureUbicacionInexistente()));
        expect(sinA, const Left<Failure, ResultadoUnionDuplicados>(FailureUbicacionInexistente()));
        expect((await ubicaciones.obtener('ub-b'))!.auditoria.estaBorrada, isFalse);
      },
    );

    test('dado que el motor de sync rechaza el trabajo, cuando se une, la transacción se revierte '
        'entera: B viva, sus deptos donde estaban, sin auditoría, y la falla no filtra el '
        'texto del error', () async {
      await ubicaciones.insertar(ubicacion('ub-a', creada: t0), espacio: espacio('e-a', 'ub-a'));
      await ubicaciones.insertar(
        ubicacion('ub-b', tipo: TipoUbicacion.edificio, metrosAlNorte: 300),
      );
      await agregarEspacio('b1', 'ub-b', numeroDepto: '1');
      await agregarEspacio('b2', 'ub-b', numeroDepto: '2');
      marcador.fallarCon = StateError('Av. Italia 1234, la casa de Doña Rosa');

      final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      expect(r.swap().getOrElse(() => throw StateError('era Right')), isA<FailureInesperado>());
      expect(await espaciosDeLaDb(), {
        'e-a': ('ub-a', false),
        'b1': ('ub-b', false),
        'b2': ('ub-b', false),
      });
      expect((await ubicaciones.obtener('ub-b'))!.auditoria.estaBorrada, isFalse);
      expect((await ubicaciones.obtener('ub-a'))!.tipo, TipoUbicacion.casa, reason: 'A no cambió');
      expect(await auditoria(), isEmpty);
      final lineas = salida.lineas.join('\n');
      expect(lineas, contains('UBICACION_UNIR_FAIL'));
      expect(lineas, contains('StateError'));
      expect(lineas, isNot(contains('Rosa')), reason: 'nunca el error en el log (puede traer PII)');
    });

    test(
      'dado que el motor rechaza la actualización de A (pasa a edificio), cuando se une, también '
      'se revierte todo y se puede volver a intentar',
      () async {
        await ubicaciones.insertar(ubicacion('ub-a', creada: t0), espacio: espacio('e-a', 'ub-a'));
        await ubicaciones.insertar(
          ubicacion('ub-b', tipo: TipoUbicacion.edificio, metrosAlNorte: 300),
        );
        await agregarEspacio('b1', 'ub-b', numeroDepto: '1');
        await agregarEspacio('b2', 'ub-b', numeroDepto: '2');
        encolador.encolados.clear();
        encolador.fallarCon = StateError('cola llena');

        final falla = await unir(
          const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'),
        );

        expect(falla.isLeft(), isTrue);
        expect((await ubicaciones.obtener('ub-a'))!.tipo, TipoUbicacion.casa);
        expect((await espaciosDeLaDb())['b1'], ('ub-b', false));
        expect(marcador.encolados, isEmpty);

        encolador.fallarCon = null;
        final reintento = await unir(
          const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'),
        );

        expect(reintento.getOrElse(() => throw StateError('falló')).escribio, isTrue);
        expect((await ubicaciones.obtener('ub-b'))!.auditoria.estaBorrada, isTrue);
      },
    );

    test('dado el encolador de producción, que todavía no tiene motor (#178), cuando se une, falla '
        'con FailureInesperado y no cambia nada: el colportor puede reintentar', () async {
      final sinMotor = UbicacionLocalDataSourceDrift(
        db,
        encolador: encolador,
        marcarDuplicado: const EncoladorMarcarDuplicadoSinMotor(),
      );
      await sembrarPar();
      final repo = UbicacionRepositoryImpl(sinMotor, logger: loggerMudo());

      final r = await UnirDuplicadosUseCase(repo, ahora: () => ahora)(
        const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'),
      );

      expect(r.swap().getOrElse(() => throw StateError('era Right')), isA<FailureInesperado>());
      expect((await ubicaciones.obtener('ub-b'))!.auditoria.estaBorrada, isFalse);
      expect(await auditoria(), isEmpty);
    });

    test('dado dos uniones que se cruzan (conservar C y unir A; conservar A y unir B), cuando '
        'terminan, no quedan A y B de baja a la vez: la segunda se rechaza', () async {
      await sembrarPar();
      await ubicaciones.insertar(ubicacion('ub-c', metrosAlNorte: 2));
      encolador.encolados.clear();

      final resultados = await Future.wait([
        unir(const UnirDuplicadosParams(conservarId: 'ub-c', duplicadaId: 'ub-a')),
        unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b')),
      ]);

      expect(
        resultados.last,
        const Left<Failure, ResultadoUnionDuplicados>(FailureConservadaDeBaja()),
      );
      final deBaja = [
        for (final id in ['ub-a', 'ub-b', 'ub-c'])
          if ((await ubicaciones.obtener(id))!.auditoria.estaBorrada) id,
      ];
      expect(deBaja, ['ub-a']);
      expect(marcador.encolados, [(duplicadaId: 'ub-a', conservadaId: 'ub-c')]);
    });

    test('dado que no hay conectividad (la unión es toda local), cuando se une, no toca la red: '
        'solo la base y la cola', () async {
      await sembrarPar();

      final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      expect(r.isRight(), isTrue);
      expect(marcador.encolados, hasLength(1), reason: 'el sync lo sube cuando haya red');
    });

    test('dado que se unió un par, cuando se loguea, el log lleva ids y cantidades sin la '
        'dirección', () async {
      await sembrarPar();

      await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      final linea = salida.lineas.firstWhere((l) => l.contains('UBICACION_UNIDA'));
      expect(linea, contains('"conservada_id":"ub-a"'));
      expect(linea, isNot(contains('Italia')));
    });
  });

  group('Escenario: Ignorar par', () {
    test('dado que decido "Son distintos", cuando confirmo, el par no vuelve a aparecer nunca, ni '
        'pasado un año', () async {
      await sembrarPar();
      final par = (await scan()).single;

      final r = await decidir(
        DecidirParDuplicadoParams(par: par, decision: DecisionParDuplicado.conservarAmbos),
      );

      expect(r, const Right<Failure, Unit>(unit));
      expect(await scan(), isEmpty);
      ahora = ahora.add(const Duration(days: 31));
      expect(await scan(), isEmpty);
      ahora = ahora.add(const Duration(days: 400));
      expect(await scan(), isEmpty);
      expect(encolador.encolados, isEmpty, reason: 'la decisión es solo local');
    });

    test('dado que decido "Ignorar", cuando confirmo, el par no reaparece dentro de 30 días y a '
        'los 30 días vuelve', () async {
      await sembrarPar();
      final par = (await scan()).single;

      await decidir(DecidirParDuplicadoParams(par: par, decision: DecisionParDuplicado.ignorar));

      expect(await scan(), isEmpty);
      ahora = ahora.add(const Duration(days: 29, hours: 23));
      expect(await scan(), isEmpty);
      ahora = ahora.add(const Duration(hours: 1));
      expect(await scan(), hasLength(1), reason: 'a los 30 días vuelve');
      expect(encolador.encolados, isEmpty, reason: 'la decisión es solo local');
    });

    test(
      'D1: dado un par de la misma dirección a menos de 100 m, cuando intento "Conservar ambos", '
      'no se guarda nada; "Ignorar" sí vale, y a 100 m o más sí se puede conservar',
      () async {
        await ubicaciones.insertar(ubicacion('ub-a', creada: t0));
        await ubicaciones.insertar(
          ubicacion('ub-b', metrosAlNorte: 40, creada: t0.add(const Duration(days: 2))),
        );
        final par = (await scan()).single;

        final conservar = await decidir(
          DecidirParDuplicadoParams(par: par, decision: DecisionParDuplicado.conservarAmbos),
        );

        expect(par.admiteConservarAmbos, isFalse);
        expect(conservar, const Left<Failure, Unit>(FailureDuplicadoMismaDireccion()));
        expect(await db.select(db.paresDecididos).get(), isEmpty);
        final ignorar = await decidir(
          DecidirParDuplicadoParams(par: par, decision: DecisionParDuplicado.ignorar),
        );
        expect(ignorar, const Right<Failure, Unit>(unit));
        expect(await db.select(db.paresDecididos).get(), hasLength(1));
      },
    );

    test('dado un par ya decidido, cuando lo ignora de nuevo más tarde, queda una sola fila con la '
        'decisión y la fecha nuevas', () async {
      await sembrarPar();
      final par = (await scan()).single;
      await decidir(
        DecidirParDuplicadoParams(par: par, decision: DecisionParDuplicado.conservarAmbos),
      );

      ahora = ahora.add(const Duration(days: 31));
      await decidir(DecidirParDuplicadoParams(par: par, decision: DecisionParDuplicado.ignorar));

      final filas = await db.select(db.paresDecididos).get();
      expect(filas, hasLength(1));
      expect((filas.single.decision, filas.single.decididoEn), ('IGNORAR', ahora));
      expect(await scan(), isEmpty);
    });

    test('dado que el par se une, cuando el scan corre otra vez, no vuelve aunque el colportor '
        'hubiera pasado antes por "Ignorar"', () async {
      await sembrarPar();
      final par = (await scan()).single;
      await decidir(DecidirParDuplicadoParams(par: par, decision: DecisionParDuplicado.ignorar));
      ahora = ahora.add(const Duration(days: 31));
      expect(await scan(), hasLength(1));

      await unir(UnirDuplicadosParams(conservarId: par.a.id, duplicadaId: par.b.id));

      expect(await scan(), isEmpty);
    });
  });

  group('Escenario: Edge - par involucra una baja', () {
    test('dado que A está activa y B fue dada de baja, cuando el scan corre, este par no se '
        'reporta', () async {
      await sembrarPar();
      await ubicaciones.cambiarBaja('ub-b', baseUpdatedAt: t0, updatedAt: ahora, deletedAt: ahora);

      expect(await scan(), isEmpty);
    });
  });

  group('ParesDuplicadosLocalDataSourceDrift', () {
    test('dado los id en cualquier orden, cuando decide, guarda el par ordenado y lo devuelve por '
        'su clave', () async {
      await paresLocal.decidir('ub-z', 'ub-a', DecisionParDuplicado.ignorar, decididoEn: t0);

      final fila = (await db.select(db.paresDecididos).get()).single;
      expect((fila.ubicacionAId, fila.ubicacionBId), ('ub-a', 'ub-z'));
      expect(await paresLocal.decididos(), {
        'ub-a|ub-z': ParDecidido(decision: DecisionParDuplicado.ignorar, decididoEn: t0),
      });
    });

    test('dado que se guarda una decisión, cuando se observan las decididas, el stream emite la '
        'lectura inicial y cada cambio', () async {
      final emisiones = <Map<String, ParDecidido>>[];
      final suscripcion = paresLocal.observarDecididos().listen(emisiones.add);
      await Future<void>.delayed(Duration.zero);

      await paresLocal.decidir('ub-b', 'ub-a', DecisionParDuplicado.conservarAmbos, decididoEn: t0);
      await Future<void>.delayed(Duration.zero);
      await suscripcion.cancel();

      expect(emisiones.first, isEmpty);
      expect(emisiones.last, {
        'ub-a|ub-b': ParDecidido(decision: DecisionParDuplicado.conservarAmbos, decididoEn: t0),
      });
    });

    test('dado una decisión o un orden que el CHECK no admite, cuando se escribe a mano, la DB la '
        'rechaza', () async {
      Future<void> insertar(String a, String b, String decision) => db.customStatement(
        'INSERT INTO ubicacion_par_decidido (ubicacion_a_id, ubicacion_b_id, decision, '
        "decidido_en) VALUES ('$a', '$b', '$decision', 0)",
      );

      await expectLater(insertar('a', 'b', 'BORRAR'), throwsA(isA<Exception>()));
      await expectLater(insertar('b', 'a', 'IGNORAR'), throwsA(isA<Exception>()));
    });
  });

  group('ParesDuplicadosRepositoryImpl', () {
    final par = ParDuplicado(
      a: ubicacion('ub-a').toEntity(),
      b: ubicacion('ub-b', metrosAlNorte: 300).toEntity(),
      motivo: MotivoDuplicado.mismaDireccion,
      distanciaMetros: 300,
      admiteConservarAmbos: true,
    );

    test('dado una decisión, cuando la guarda, loguea ids, decisión y motivo sin la '
        'dirección', () async {
      final salida = _SalidaEnMemoria();
      final repo = ParesDuplicadosRepositoryImpl(paresLocal, logger: AppLogger(output: salida));

      await repo.decidir(par, DecisionParDuplicado.conservarAmbos, ahora: t0);

      expect(salida.lineas.single, startsWith('[INFO][DB][UBICACION_PAR_DECIDIDO]'));
      expect(salida.lineas.single, contains('"decision":"conservarAmbos"'));
      expect(salida.lineas.single, contains('"motivo":"mismaDireccion"'));
      expect(salida.lineas.single, isNot(contains('Italia')));
    });

    test('dado que el almacenamiento falla, cuando lee o guarda, devuelve FailureInesperado y '
        'loguea el error', () async {
      final salida = _SalidaEnMemoria();
      final repo = ParesDuplicadosRepositoryImpl(
        _LocalQueFalla(),
        logger: AppLogger(output: salida),
      );

      expect((await repo.decididos()).fold((f) => f, (_) => null), isA<FailureInesperado>());
      expect(
        (await repo.decidir(
          par,
          DecisionParDuplicado.ignorar,
          ahora: t0,
        )).fold((f) => f, (_) => null),
        isA<FailureInesperado>(),
      );
      expect(salida.lineas.where((l) => l.startsWith('[ERROR][DB][UBICACION_PAR')), hasLength(2));
    });

    test('dado que las decisiones cambian, cuando se observan por el repositorio, llegan las del '
        'almacenamiento', () async {
      final repo = ParesDuplicadosRepositoryImpl(paresLocal, logger: loggerMudo());
      await repo.decidir(par, DecisionParDuplicado.ignorar, ahora: t0);

      final primera = await repo.observarDecididos().first;

      expect(primera.keys, ['ub-a|ub-b']);
    });
  });
}
