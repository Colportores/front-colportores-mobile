// Reactivar una baja (HU-UBI-005, #334) contra las tablas reales: AppDatabase en memoria (sin cifrado),
// del caso de uso al repositorio y a Drift. Una baja por unión de duplicados no se reactiva, y las demás
// pasan por la regla de dirección única (D1) antes de escribir; las dos guardas viven donde se
// reactiva, así que valen también al reactivar al guardar desde Editar.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/consultor_pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/baja_ubicacion_use_cases.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/modificar_ubicacion_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../../helpers/duplicados_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/zonas_falsas.dart';

final class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

final class _SinPendientes implements ConsultorPendientesUbicacion {
  @override
  Future<Either<Failure, PendientesUbicacion>> de(String ubicacionId) async =>
      const Right(PendientesUbicacion.ninguno);
}

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 13, 45, 10, 123);
  final t1 = DateTime.utc(2026, 9, 30, 8, 0, 0, 500);
  final t2 = DateTime.utc(2026, 10, 1, 9);
  const italia = Coordenadas(lat: -34.891, lon: -56.125);

  Coordenadas alNorte(double metros) =>
      Coordenadas(lat: italia.lat + metros / 111195.08, lon: italia.lon);

  UbicacionModel ubicacion(
    String id, {
    String? calle = 'Av. Italia',
    String? numero = '1234',
    double metrosAlNorte = 0,
    String ciudadId = 'mvd',
    String colportor = 'col-1',
    DateTime? deletedAt,
  }) => UbicacionModel(
    id: id,
    tipo: TipoUbicacion.casa,
    calle: calle,
    numero: numero,
    lat: alNorte(metrosAlNorte).lat,
    lon: alNorte(metrosAlNorte).lon,
    ciudadId: ciudadId,
    zonaId: 'zona-9',
    auditoria: Auditoria(
      createdAt: t0,
      updatedAt: t0,
      createdBy: colportor,
      deletedAt: deletedAt,
      syncVersion: 4,
    ),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late EncoladorMarcarDuplicadoFalso marcador;
  late UbicacionLocalDataSourceDrift local;
  late UbicacionRepositoryImpl repositorio;
  late _SalidaEnMemoria salida;
  late ReactivarUbicacionUseCase reactivar;
  late ModificarUbicacionUseCase modificar;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    marcador = EncoladorMarcarDuplicadoFalso();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador, marcarDuplicado: marcador);
    salida = _SalidaEnMemoria();
    repositorio = UbicacionRepositoryImpl(local, logger: AppLogger(output: salida));
    reactivar = ReactivarUbicacionUseCase(repositorio, ahora: () => t2);
    modificar = ModificarUbicacionUseCase(
      repositorio,
      generarId: () => 'esp-nuevo',
      ubicador: ubicadorSinZonas(),
      ahora: () => t2,
    );
  });

  tearDown(() => db.close());

  Future<UbicacionModel> guardada(String id) async => (await local.obtener(id))!;

  Future<List<AuditLogFila>> auditoria() =>
      (db.select(db.auditLogLocal)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  Future<void> bajaConMotivo(String id, DateTime cuando, String? motivo) async {
    if (motivo == null) return;
    await db
        .into(db.auditLogLocal)
        .insert(
          AuditLogLocalCompanion.insert(
            evento: EventoAuditoriaLocal.ubicacionBaja,
            uuid: id,
            motivo: Value(motivo),
            creadoEn: cuando,
          ),
        );
  }

  ReactivarUbicacionParams params({String id = 'ub-1', DateTime? base}) =>
      ReactivarUbicacionParams(id: id, baseUpdatedAt: base ?? t0);

  Future<Failure> falla([ReactivarUbicacionParams? p]) async => (await reactivar(
    p ?? params(),
  )).swap().getOrElse(() => throw StateError('era un Right: se reactivó'));

  Future<Ubicacion> reactivada([ReactivarUbicacionParams? p]) async =>
      (await reactivar(p ?? params())).getOrElse(() => throw StateError('era un Left'));

  /// Lo que no tiene que haber cambiado después de una reactivación rechazada: la fila, el encolado y la
  /// auditoría local.
  Future<void> sinCambios(String id, UbicacionModel antes, int filasDeAuditoria) async {
    expect(await guardada(id), antes, reason: 'la fila sigue como estaba');
    expect(encolador.encolados, isEmpty, reason: 'no se encoló nada');
    expect(await auditoria(), hasLength(filasDeAuditoria), reason: 'la auditoría no cambió');
  }

  group('Una baja por unión de duplicados no se reactiva', () {
    /// A (se conserva) y B (la duplicada) unidas de verdad: B queda de baja con `duplicado_de_ub-a`.
    Future<DateTime> unirBEnA() async {
      await local.insertar(ubicacion('ub-a'));
      await local.insertar(ubicacion('ub-b', metrosAlNorte: 2));
      await local.unirDuplicada('ub-a', 'ub-b', ahora: t1);
      encolador.encolados.clear();
      return t1;
    }

    test('dado que B se unió a A, cuando intenta reactivarla, falla con FailureReactivacionDeUnion '
        'y no se escribe ni se encola nada', () async {
      final base = await unirBEnA();
      final antes = await guardada('ub-b');
      final antesA = await guardada('ub-a');

      final f = await falla(params(id: 'ub-b', base: base));

      expect(f, const FailureReactivacionDeUnion(conservadaId: 'ub-a'));
      expect(
        f.mensaje,
        'Esta ubicación se unió a otra y no se puede reactivar. Seguí usando la otra.',
      );
      await sinCambios('ub-b', antes, 1);
      expect(antes.auditoria.deletedAt, isNotNull);
      expect(await guardada('ub-a'), antesA, reason: 'la que se conserva no se toca');
    });

    test('dado que se intenta dos veces, entonces las dos fallan igual y la baja sigue', () async {
      final base = await unirBEnA();

      final fallas = [
        await falla(params(id: 'ub-b', base: base)),
        await falla(params(id: 'ub-b', base: base)),
      ];

      expect(fallas, everyElement(const FailureReactivacionDeUnion(conservadaId: 'ub-a')));
      expect((await guardada('ub-b')).auditoria.deletedAt, isNotNull);
    });

    test('dado que B se unió a A y A sigue activa, entonces la falla lleva a A para que la hoja '
        'pueda abrirla', () async {
      final base = await unirBEnA();

      final f = await falla(params(id: 'ub-b', base: base));

      expect((f as FailureReactivacionDeUnion).conservadaId, 'ub-a');
    });

    test(
      'dado que A también quedó de baja (se unió a C), entonces la falla lleva a C: es la que sigue '
      'en pie y la que la hoja puede abrir',
      () async {
        final base = await unirBEnA();
        await local.insertar(ubicacion('ub-c', metrosAlNorte: 500, numero: '9'));
        await local.unirDuplicada('ub-c', 'ub-a', ahora: t1.add(const Duration(hours: 1)));
        expect((await guardada('ub-a')).auditoria.deletedAt, isNotNull);

        final f = await falla(params(id: 'ub-b', base: base));

        expect(f, const FailureReactivacionDeUnion(conservadaId: 'ub-c'));
      },
    );

    test('dado una cadena larga (B a A, A a C, C a D), entonces la falla de B lleva a D', () async {
      final base = await unirBEnA();
      await local.insertar(ubicacion('ub-c', metrosAlNorte: 500, numero: '9'));
      await local.insertar(ubicacion('ub-d', metrosAlNorte: 900, numero: '7'));
      await local.unirDuplicada('ub-c', 'ub-a', ahora: t1.add(const Duration(hours: 1)));
      await local.unirDuplicada('ub-d', 'ub-c', ahora: t1.add(const Duration(hours: 2)));

      final f = await falla(params(id: 'ub-b', base: base));

      expect(f, const FailureReactivacionDeUnion(conservadaId: 'ub-d'));
    });

    test(
      'dado que al final de la cadena la última también está de baja pero no por una unión, '
      'entonces la falla lleva a esa (el repositorio no la ofrece) y B sigue sin reactivarse',
      () async {
        final base = await unirBEnA();
        await local.insertar(ubicacion('ub-c', metrosAlNorte: 500, numero: '9'));
        await local.unirDuplicada('ub-c', 'ub-a', ahora: t1.add(const Duration(hours: 1)));
        await local.cambiarBaja(
          'ub-c',
          baseUpdatedAt: (await guardada('ub-c')).auditoria.updatedAt,
          updatedAt: t2,
          deletedAt: t2,
          motivo: 'Ya no existe',
        );

        final f = await falla(params(id: 'ub-b', base: base));

        expect(f, const FailureReactivacionDeUnion());
        expect((await guardada('ub-b')).auditoria.deletedAt, isNotNull);
      },
    );

    test(
      'dado una cadena que da la vuelta (B a A, A a B), entonces no se cuelga: la falla no lleva '
      'a nadie',
      () async {
        await local.insertar(ubicacion('ub-a', deletedAt: t0));
        await local.insertar(ubicacion('ub-b', deletedAt: t1));
        await bajaConMotivo('ub-a', t0, 'duplicado_de_ub-b');
        await bajaConMotivo('ub-b', t1, 'duplicado_de_ub-a');

        final f = await falla(params(id: 'ub-b', base: t0));

        expect(f, const FailureReactivacionDeUnion());
      },
    );

    test('dado una cadena más larga que el tope de saltos, entonces no se sigue para siempre y la '
        'falla no lleva a nadie', () async {
      // 12 bajas encadenadas: ub-0 a ub-1, ub-1 a ub-2, … y la última, activa, queda fuera del tope.
      for (var i = 0; i < 12; i++) {
        final marca = t0.add(Duration(minutes: i));
        await local.insertar(ubicacion('ub-$i', deletedAt: marca, numero: '$i'));
        await bajaConMotivo('ub-$i', marca, 'duplicado_de_ub-${i + 1}');
      }
      await local.insertar(ubicacion('ub-12', numero: '12', metrosAlNorte: 900));

      final f = await falla(params(id: 'ub-0', base: t0));

      expect(f, const FailureReactivacionDeUnion());
    });

    test('dado que A ya no está en el teléfono, entonces la falla no lleva a nadie', () async {
      final base = await unirBEnA();
      await (db.delete(db.ubicaciones)..where((u) => u.id.equals('ub-a'))).go();

      final f = await falla(params(id: 'ub-b', base: base));

      expect(f, const FailureReactivacionDeUnion());
    });

    test('dado un motivo de unión sin uuid («duplicado_de_»), entonces no se reactiva y no lleva a '
        'nadie', () async {
      await local.insertar(ubicacion('ub-1', deletedAt: t0));
      await bajaConMotivo('ub-1', t0, 'duplicado_de_');

      final f = await falla();

      expect(f, const FailureReactivacionDeUnion());
    });

    test('dado el rechazo, entonces ni la falla ni la excepción llevan el uuid de A ni la '
        'dirección en su texto de log', () async {
      final base = await unirBEnA();

      final f = await falla(params(id: 'ub-b', base: base));

      expect(f.toString(), 'FailureReactivacionDeUnion(UBI_REACTIVAR_UNION)');
      expect(f.codigo, isNot(contains('ub-a')));
      await expectLater(
        local.cambiarBaja('ub-b', baseUpdatedAt: base, updatedAt: t2, deletedAt: null),
        throwsA(
          isA<ReactivacionDeUnionException>()
              .having((e) => e.conservadaId, 'conservadaId', 'ub-a')
              .having((e) => e.toString(), 'toString', 'ReactivacionDeUnionException'),
        ),
      );
    });

    test(
      'dado que se intenta dos veces a la vez (doble toque), entonces ninguna escribe',
      () async {
        final base = await unirBEnA();

        final r = await Future.wait([
          reactivar(params(id: 'ub-b', base: base)),
          reactivar(params(id: 'ub-b', base: base)),
        ]);

        expect(r.every((x) => x.isLeft()), isTrue);
        expect(encolador.encolados, isEmpty);
        expect((await guardada('ub-b')).auditoria.deletedAt, isNotNull);
      },
    );

    test('dado que B se unió a A, cuando la edita y confirma reactivar (Editar), tampoco se '
        'reactiva: falla con FailureReactivacionDeUnion antes de buscar duplicados', () async {
      final base = await unirBEnA();
      final antes = await guardada('ub-b');

      final r = await modificar(
        ModificarUbicacionParams(
          id: 'ub-b',
          colportorId: 'col-1',
          tipo: TipoUbicacion.casa,
          coordenadas: alNorte(2),
          baseUpdatedAt: base,
          ciudadId: 'mvd',
          calle: 'Av. Italia',
          numero: '1236',
          confirmadas: const {ConfirmacionModificacion.reactivar},
        ),
      );

      expect(
        r,
        const Left<Failure, ResultadoModificacionUbicacion>(
          FailureReactivacionDeUnion(conservadaId: 'ub-a'),
        ),
      );
      await sinCambios('ub-b', antes, 1);
    });

    test('dado que B se unió a A, cuando la edita sin reactivarla (sigue de baja), el cambio no '
        'toca la guarda', () async {
      // Editar una baja siempre pide confirmar la reactivación (S18): el guardado no llega a escribir.
      final base = await unirBEnA();

      final r = await modificar(
        ModificarUbicacionParams(
          id: 'ub-b',
          colportorId: 'col-1',
          tipo: TipoUbicacion.casa,
          coordenadas: alNorte(2),
          baseUpdatedAt: base,
          ciudadId: 'mvd',
          calle: 'Av. Italia',
          numero: '1236',
        ),
      );

      expect(
        r.getOrElse(() => throw StateError('era un Left')),
        isA<ModificacionRequiereConfirmacion>(),
      );
      expect((await guardada('ub-b')).auditoria.deletedAt, isNotNull);
    });

    test(
      'dado una baja con un motivo libre que empieza parecido («duplicado de la casa»), entonces '
      'se reactiva: solo el prefijo exacto «duplicado_de_» es una unión',
      () async {
        await local.insertar(ubicacion('ub-1', deletedAt: t0));
        await bajaConMotivo('ub-1', t0, 'duplicado de la casa de al lado');
        await bajaConMotivo('ub-1', t0, 'duplicadoXdeY');

        final r = await reactivada();

        expect(r.estaBorrada, isFalse);
        expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
      },
    );

    test(
      'dado un motivo de «Otro» escrito a mano que empieza con «duplicado_de_», entonces se guarda '
      'como texto común y la baja se puede reactivar (no se confunde con una unión)',
      () async {
        await local.insertar(ubicacion('ub-1'));
        final baja = DarDeBajaUbicacionUseCase(repositorio, _SinPendientes(), ahora: () => t1);

        await baja(
          DarDeBajaUbicacionParams(id: 'ub-1', baseUpdatedAt: t0, motivo: '  duplicado_de_vecino '),
        );

        expect((await auditoria()).single.motivo, 'duplicado de vecino');
        final r = await reactivada(params(base: t1));
        expect(r.estaBorrada, isFalse);
        expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
      },
    );

    test('dado la baja de una duplicada con la ubicación que se conserva (el motivo lo arma el '
        'sistema), entonces el prefijo se guarda tal cual y la baja no se reactiva', () async {
      await local.insertar(ubicacion('ub-a'));
      await local.insertar(ubicacion('ub-b', metrosAlNorte: 500, numero: '9'));
      final baja = DarDeBajaUbicacionUseCase(repositorio, _SinPendientes(), ahora: () => t1);

      await baja(
        DarDeBajaUbicacionParams(
          id: 'ub-b',
          baseUpdatedAt: t0,
          motivo: 'duplicado_de_ub-a',
          conservadaId: 'ub-a',
        ),
      );

      expect((await auditoria()).single.motivo, 'duplicado_de_ub-a');
      expect(
        await falla(params(id: 'ub-b', base: t1)),
        const FailureReactivacionDeUnion(conservadaId: 'ub-a'),
      );
    });

    test('dado el repositorio, cuando da de baja directo con un motivo que empieza con '
        '«duplicado_de_», entonces también lo guarda como texto común', () async {
      await local.insertar(ubicacion('ub-1'));

      final r = await repositorio.cambiarBaja(
        'ub-1',
        baja: true,
        baseUpdatedAt: t0,
        ahora: t1,
        motivo: 'duplicado_de_ub-9',
      );

      expect(r.isRight(), isTrue);
      expect((await auditoria()).single.motivo, 'duplicado de ub-9');
      expect((await reactivada(params(base: t1))).estaBorrada, isFalse);
    });

    test('dado una baja con motivo común, entonces se reactiva y se encola el update', () async {
      await local.insertar(ubicacion('ub-1', deletedAt: t0));
      await bajaConMotivo('ub-1', t0, 'Ya no existe');
      encolador.encolados.clear();

      await reactivada();

      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
      expect(encolador.encolados, hasLength(1));
    });

    test('dado una baja que llegó del servidor (sin fila en la auditoría local), entonces se '
        'reactiva: no se inventa un motivo', () async {
      await local.insertar(ubicacion('ub-1', deletedAt: t0));

      await reactivada();

      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
    });

    test('dado un evento de unión de otra baja (otra marca), entonces no cuenta para la baja '
        'vigente', () async {
      await local.insertar(ubicacion('ub-1', deletedAt: t0));
      await bajaConMotivo('ub-1', t0.subtract(const Duration(days: 3)), 'duplicado_de_ub-9');

      await reactivada();

      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
    });

    test('dado una baja por unión de OTRA ubicación, entonces esta se reactiva', () async {
      await local.insertar(ubicacion('ub-1', deletedAt: t0));
      await bajaConMotivo('ub-otra', t0, 'duplicado_de_ub-9');

      await reactivada();

      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
    });

    test('dado que el rechazo va al log, entonces solo lleva el código y los uuid', () async {
      final base = await unirBEnA();

      await falla(params(id: 'ub-b', base: base));

      final linea = salida.lineas.firstWhere((l) => l.contains('[UBICACION_REACTIVAR_UNION]'));
      expect(linea, contains('ub-b'));
      expect(linea, isNot(contains('Italia')));
      expect(linea, isNot(contains('duplicado_de_')));
    });
  });

  group('Reactivar aplica la regla de dirección única (D1)', () {
    setUp(() async {
      await local.insertar(ubicacion('ub-1', deletedAt: t0));
      encolador.encolados.clear();
    });

    test('dado otra activa con la misma dirección a menos de 100 m, cuando reactiva, falla con '
        'FailureReactivacionChocaConActiva y no escribe ni encola nada', () async {
      await local.insertar(ubicacion('ub-2', metrosAlNorte: 30));
      encolador.encolados.clear();
      final antes = await guardada('ub-1');

      final f = await falla();

      expect(
        f,
        const FailureReactivacionChocaConActiva(existenteId: 'ub-2', direccion: 'Av. Italia 1234'),
      );
      expect(
        f.mensaje,
        'No puede haber dos ubicaciones con la misma dirección a menos de 100 m, y Av. Italia 1234 '
        'ya está activa. Si es la misma, seguí usando esa; si es otra puerta, abrila y agregala '
        'como espacio.',
      );
      await sinCambios('ub-1', antes, 0);
      expect((await guardada('ub-2')).auditoria.deletedAt, isNull);
    });

    test('dado el choque, cuando pasa a 99 m, entonces choca; a 101 m ya son dos lugares y '
        'reactiva', () async {
      await local.insertar(ubicacion('ub-2', metrosAlNorte: 99));
      expect(await falla(), isA<FailureReactivacionChocaConActiva>());

      await db.delete(db.ubicaciones).go();
      await local.insertar(ubicacion('ub-1', deletedAt: t0));
      await local.insertar(ubicacion('ub-2', metrosAlNorte: 101));
      encolador.encolados.clear();

      await reactivada();

      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
    });

    test('dado que la otra la escribió con otras mayúsculas, tildes y espacios, entonces también '
        'choca (la normaliza el criterio) y la hoja nombra la dirección como la cargó quien la '
        'cargó', () async {
      await local.insertar(
        ubicacion('ub-2', calle: '  AV.  ITÁLIA ', numero: '1234 ', metrosAlNorte: 10),
      );

      final f = await falla();

      expect(
        f,
        const FailureReactivacionChocaConActiva(existenteId: 'ub-2', direccion: 'AV.  ITÁLIA 1234'),
      );
    });

    test('dado varias activas que chocan (cada una escrita a su manera), entonces la hoja nombra y '
        'abre la más cercana', () async {
      await local.insertar(ubicacion('ub-lejos', calle: 'av.  italia', metrosAlNorte: 80));
      await local.insertar(ubicacion('ub-cerca', calle: 'AV. ITALIA', metrosAlNorte: 20));
      await local.insertar(ubicacion('ub-media', calle: ' Av. Italia', metrosAlNorte: 50));

      final f = await falla() as FailureReactivacionChocaConActiva;

      expect(f.existenteId, 'ub-cerca');
      expect(f.direccion, 'AV. ITALIA 1234');
      expect(f.mensaje, contains('y AV. ITALIA 1234 ya está activa.'));
      expect(f.mensaje, isNot(contains('av.  italia')));
    });

    test('dado que la otra la cargó otro colportor, entonces también choca (D1 compara todas las '
        'del teléfono)', () async {
      await local.insertar(ubicacion('ub-2', metrosAlNorte: 30, colportor: 'col-2'));

      expect(await falla(), isA<FailureReactivacionChocaConActiva>());
    });

    test('dado que la otra es de otra ciudad, entonces reactiva (la ciudad es parte de la '
        'dirección)', () async {
      await local.insertar(ubicacion('ub-2', metrosAlNorte: 30, ciudadId: 'sal'));

      await reactivada();

      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
    });

    test('dado que la otra también está de baja, entonces reactiva', () async {
      await local.insertar(ubicacion('ub-2', metrosAlNorte: 30, deletedAt: t0));

      await reactivada();

      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
    });

    test('dado otra activa a menos de 5 m pero con otra dirección, entonces reactiva: es solo D1, '
        'el aviso de posible duplicado lo da el scan', () async {
      await local.insertar(ubicacion('ub-2', numero: '1300', metrosAlNorte: 3));

      await reactivada();

      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
    });

    test('dado otra activa con la misma dirección a 100 m o más, entonces reactiva (la mide el '
        'scan, no la reactivación)', () async {
      await local.insertar(ubicacion('ub-2', metrosAlNorte: 400));

      await reactivada();

      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
    });

    test('dado una baja sin calle ni número y otra activa a un paso, entonces reactiva: sin '
        'dirección no hay D1', () async {
      await db.delete(db.ubicaciones).go();
      await local.insertar(ubicacion('ub-1', calle: null, numero: null, deletedAt: t0));
      await local.insertar(ubicacion('ub-2', calle: null, numero: null, metrosAlNorte: 30));

      await reactivada();

      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
    });

    test('dado el choque, cuando la otra se da de baja y reintenta, entonces reactiva', () async {
      await local.insertar(ubicacion('ub-2', metrosAlNorte: 30));
      expect(await falla(), isA<FailureReactivacionChocaConActiva>());

      final baja = DarDeBajaUbicacionUseCase(repositorio, _SinPendientes(), ahora: () => t1);
      await baja(DarDeBajaUbicacionParams(id: 'ub-2', baseUpdatedAt: t0, motivo: 'Ya no existe'));
      encolador.encolados.clear();

      await reactivada();

      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
      expect(encolador.encolados, hasLength(1));
    });

    test('dado dos toques seguidos en «Reactivar» con el choque, entonces los dos fallan igual y '
        'no se escribe nada', () async {
      await local.insertar(ubicacion('ub-2', metrosAlNorte: 30));
      encolador.encolados.clear();

      final r = await Future.wait([reactivar(params()), reactivar(params())]);

      expect(r.every((x) => x.isLeft()), isTrue);
      expect(encolador.encolados, isEmpty);
      expect((await guardada('ub-1')).auditoria.deletedAt, t0);
    });

    test(
      'dado B unida a A (la misma dirección a 2 m), cuando reactiva, falla por la unión y no por D1: '
      'la guarda de la unión va antes',
      () async {
        await db.delete(db.ubicaciones).go();
        await local.insertar(ubicacion('ub-a'));
        await local.insertar(ubicacion('ub-b', metrosAlNorte: 2));
        await local.unirDuplicada('ub-a', 'ub-b', ahora: t1);

        // Sin la guarda de la unión, B chocaría con A (la misma dirección a 2 m).
        expect(
          await falla(params(id: 'ub-b', base: t1)),
          const FailureReactivacionDeUnion(conservadaId: 'ub-a'),
        );
      },
    );

    test(
      'dado el log del choque, entonces lleva el código y los uuid, nunca la dirección',
      () async {
        await local.insertar(ubicacion('ub-2', metrosAlNorte: 30));

        await falla();

        final linea = salida.lineas.firstWhere(
          (l) => l.contains('[UBICACION_REACTIVAR_MISMA_DIRECCION]'),
        );
        expect(linea, contains('ub-1'));
        expect(linea, contains('ub-2'));
        expect(linea, isNot(contains('Italia')));
        expect(linea, isNot(contains('1234')));
      },
    );

    test('dado el criterio con la regla anterior a D1 (la misma dirección se admite), entonces no '
        'se busca nada y reactiva: D1 tiene un solo punto', () async {
      final sinD1 = ReactivarUbicacionUseCase(
        repositorio,
        ahora: () => t2,
        criterio: const CriterioDuplicadoUbicacion(mismaDireccionAdmiteConservarAmbos: true),
      );
      await local.insertar(ubicacion('ub-2', metrosAlNorte: 30));

      final r = await sinD1(params());

      expect(r.isRight(), isTrue);
      expect((await guardada('ub-1')).auditoria.deletedAt, isNull);
    });

    test('dado que el choque aparece entre la lectura del caso de uso y la escritura (el sync trae '
        'la otra casa), entonces la transacción lo ve y no reactiva', () async {
      // Sin pasar por el caso de uso: lo decide la transacción de quien escribe.
      await local.insertar(ubicacion('ub-2', metrosAlNorte: 30));
      encolador.encolados.clear();

      await expectLater(
        local.cambiarBaja(
          'ub-1',
          baseUpdatedAt: t0,
          updatedAt: t2,
          deletedAt: null,
          duplicados: const CriterioDuplicadoUbicacion().alSeguirIgual,
        ),
        throwsA(
          isA<UbicacionDuplicadaException>().having(
            (e) => e.candidatas.single.ubicacion.id,
            'candidata',
            'ub-2',
          ),
        ),
      );
      expect((await guardada('ub-1')).auditoria.deletedAt, t0);
      expect(encolador.encolados, isEmpty);
    });

    test('dado la reactivación que entra, entonces D1 no se mira al DAR de baja (la regla es de '
        'reactivar)', () async {
      await local.insertar(ubicacion('ub-3', metrosAlNorte: 30));
      await local.insertar(ubicacion('ub-4', metrosAlNorte: 31));

      final r = await local.cambiarBaja(
        'ub-3',
        baseUpdatedAt: t0,
        updatedAt: t1,
        deletedAt: t1,
        duplicados: const CriterioDuplicadoUbicacion().alSeguirIgual,
      );

      expect(r.escribio, isTrue);
    });

    test(
      'dado la misma casa activa al lado, cuando se reactiva al guardar desde Editar (aunque solo '
      'cambie el tipo), también frena: la edición vuelve a buscar duplicados al reactivar y D1 no '
      'deja «Crear igual»',
      () async {
        await local.insertar(ubicacion('ub-2', metrosAlNorte: 30));
        encolador.encolados.clear();

        final r = await modificar(
          ModificarUbicacionParams(
            id: 'ub-1',
            colportorId: 'col-1',
            tipo: TipoUbicacion.negocio,
            coordenadas: italia,
            baseUpdatedAt: t0,
            ciudadId: 'mvd',
            calle: 'Av. Italia',
            numero: '1234',
            confirmadas: const {ConfirmacionModificacion.reactivar},
          ),
        );

        final con = r.getOrElse(() => throw StateError('era un Left')) as ModificacionConDuplicados;
        expect(con.candidatas.single.ubicacion.id, 'ub-2');
        expect(con.candidatas.single.admiteConservarAmbos, isFalse);
        expect((await guardada('ub-1')).auditoria.deletedAt, t0);
        expect(encolador.encolados, isEmpty);
      },
    );
  });
}
