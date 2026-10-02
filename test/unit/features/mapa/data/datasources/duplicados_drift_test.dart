// Duplicados de ubicación (HU-UBI-006) contra las tablas reales: AppDatabase en memoria (sin
// cifrado), del caso de uso a los repositorios y a Drift. Los escenarios llevan el título de la HU.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/pares_duplicados_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/pares_duplicados_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/pares_duplicados_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_baja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/consultor_pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/baja_ubicacion_use_cases.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/duplicados_ubicacion_use_cases.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

final class _Pendientes implements ConsultorPendientesUbicacion {
  PendientesUbicacion pendientes = PendientesUbicacion.ninguno;
  var consultas = 0;

  @override
  Future<Either<Failure, PendientesUbicacion>> de(String ubicacionId) async {
    consultas++;
    return Right(pendientes);
  }
}

final class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

final class _LocalQueFalla implements ParesDuplicadosLocalDataSource {
  @override
  Future<Map<String, DateTime>> decididos() => throw StateError('disco');

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
  }) => UbicacionModel(
    id: id,
    tipo: TipoUbicacion.casa,
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
  late _Pendientes pendientes;
  late ConsultarParesDuplicadosUseCase consultar;
  late DecidirParDuplicadoUseCase decidir;
  late MarcarDuplicadoUseCase marcar;

  setUp(() {
    ahora = DateTime.utc(2026, 10, 1, 9);
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    paresLocal = ParesDuplicadosLocalDataSourceDrift(db);
    pendientes = _Pendientes();
    final repoUbicaciones = UbicacionRepositoryImpl(ubicaciones, logger: loggerMudo());
    final repoPares = ParesDuplicadosRepositoryImpl(paresLocal, logger: loggerMudo());
    consultar = ConsultarParesDuplicadosUseCase(repoUbicaciones, repoPares, ahora: () => ahora);
    decidir = DecidirParDuplicadoUseCase(repoPares, ahora: () => ahora);
    marcar = MarcarDuplicadoUseCase(
      repoUbicaciones,
      DarDeBajaUbicacionUseCase(repoUbicaciones, pendientes, ahora: () => ahora),
    );
  });

  tearDown(() => db.close());

  Future<List<ParDuplicado>> scan() async => (await consultar(
    const ConsultarParesDuplicadosParams(colportorId: 'col-1'),
  )).getOrElse(() => throw StateError('el scan falló'));

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
    test('dado que en un par candidato decido conservar A, cuando confirmo "Conservar A", B se da '
        'de baja, se encola el tombstone y el par deja de aparecer', () async {
      await sembrarPar();
      final par = (await scan()).single;

      final r = await marcar(
        MarcarDuplicadoParams(
          conservarId: par.a.id,
          duplicadaId: par.b.id,
          baseUpdatedAtDuplicada: par.b.auditoria.updatedAt,
        ),
      );

      expect(r.getOrElse(() => throw StateError('falló')), isA<UbicacionDadaDeBaja>());
      expect((await ubicaciones.obtener('ub-b'))!.auditoria.deletedAt, ahora);
      expect((await ubicaciones.obtener('ub-a'))!.auditoria.deletedAt, isNull);
      expect(encolador.encolados.map((c) => (c.entidad, c.operacion, c.payload['id'])), [
        ('ubicacion', OperacionSync.delete, 'ub-b'),
      ]);
      expect(await scan(), isEmpty);
    });

    test('dado pendientes en la duplicada, cuando confirmo "Conservar A", primero pide confirmar '
        'y no escribe nada', () async {
      await sembrarPar();
      pendientes.pendientes = const PendientesUbicacion(visitasPendientes: 2);

      final r = await marcar(
        MarcarDuplicadoParams(conservarId: 'ub-a', duplicadaId: 'ub-b', baseUpdatedAtDuplicada: t0),
      );

      expect(r.getOrElse(() => throw StateError('falló')), isA<BajaRequiereConfirmacion>());
      expect((await ubicaciones.obtener('ub-b'))!.auditoria.deletedAt, isNull);
      expect(encolador.encolados, isEmpty);
    });

    test('dado dos "marcar duplicado" concurrentes sobre pares que se cruzan (conservar C y dar de '
        'baja A; conservar A y dar de baja B), cuando terminan, no quedan A y B de baja', () async {
      await sembrarPar();
      await ubicaciones.insertar(ubicacion('ub-c', metrosAlNorte: 2));
      encolador.encolados.clear();

      final resultados = await Future.wait([
        marcar(
          MarcarDuplicadoParams(
            conservarId: 'ub-c',
            duplicadaId: 'ub-a',
            baseUpdatedAtDuplicada: t0,
          ),
        ),
        marcar(
          MarcarDuplicadoParams(
            conservarId: 'ub-a',
            duplicadaId: 'ub-b',
            baseUpdatedAtDuplicada: t0,
          ),
        ),
      ]);

      expect(pendientes.consultas, 2, reason: 'las dos pasaron el chequeo previo: hubo carrera');
      final deBaja = [
        for (final id in ['ub-a', 'ub-b', 'ub-c'])
          if ((await ubicaciones.obtener(id))!.auditoria.estaBorrada) id,
      ];
      expect(deBaja, hasLength(1));
      expect(encolador.encolados, hasLength(1));
      expect(
        resultados.where(
          (r) => r == const Left<Failure, ResultadoBajaUbicacion>(FailureConservadaDeBaja()),
        ),
        hasLength(1),
      );
      expect(deBaja.single, 'ub-a', reason: 'la primera en escribir da de baja A');
    });
  });

  group('Escenario: Ignorar par', () {
    test('dado que decido conservar ambos, cuando confirmo "Conservar ambos", el par se registra '
        'como ignored por 30 días y no reaparece dentro de esa ventana', () async {
      await sembrarPar();
      final par = (await scan()).single;

      final r = await decidir(
        DecidirParDuplicadoParams(par: par, decision: DecisionParDuplicado.conservarAmbos),
      );

      expect(r, const Right<Failure, Unit>(unit));
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
      expect(await paresLocal.decididos(), {'ub-a|ub-z': t0});
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
  });
}
