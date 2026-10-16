// Modificación de ubicaciones (HU-UBI-004) contra las tablas reales: AppDatabase en memoria (sin
// cifrado), del caso de uso al repositorio y a Drift, con el encolado dentro de la transacción.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/zona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/models/campania_ciudad_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/zona_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/zona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacios_activos.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ubicador_zona.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/modificar_ubicacion_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/zonas_falsas.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 13, 45, 10, 123);
  final t1 = DateTime.utc(2026, 9, 30, 8, 0, 0, 500);
  const italia = Coordenadas(lat: -34.891, lon: -56.125);

  Coordenadas alNorte(double metros) =>
      Coordenadas(lat: italia.lat + metros / 111195.08, lon: italia.lon);

  UbicacionModel ubicacion({
    String id = 'ub-1',
    TipoUbicacion tipo = TipoUbicacion.casa,
    String? calle = 'Av. Italia',
    String? numero = '1234',
    Coordenadas punto = italia,
    String ciudadId = 'mvd',
    DateTime? deletedAt,
  }) => UbicacionModel(
    id: id,
    tipo: tipo,
    calle: calle,
    numero: numero,
    lat: punto.lat,
    lon: punto.lon,
    ciudadId: ciudadId,
    zonaId: 'zona-9',
    auditoria: Auditoria(
      createdAt: t0,
      updatedAt: t0,
      createdBy: 'col-1',
      deletedAt: deletedAt,
      syncVersion: 4,
    ),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift local;
  late UbicacionRepositoryImpl repositorio;
  late ModificarUbicacionUseCase modificar;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    repositorio = UbicacionRepositoryImpl(local, logger: loggerMudo());
    modificar = ModificarUbicacionUseCase(
      repositorio,
      ubicador: ubicadorSinZonas(),
      ahora: () => t1,
    );
  });

  tearDown(() => db.close());

  ModificarUbicacionParams params({
    String id = 'ub-1',
    TipoUbicacion tipo = TipoUbicacion.casa,
    Coordenadas coordenadas = italia,
    String ciudadId = 'mvd',
    String? calle = 'Av. Italia',
    String? numero = '1234',
    Set<ConfirmacionModificacion> confirmadas = const {},
    String? justificacion,
    DateTime? base,
  }) => ModificarUbicacionParams(
    id: id,
    colportorId: 'col-1',
    tipo: tipo,
    coordenadas: coordenadas,
    baseUpdatedAt: base ?? t0,
    ciudadId: ciudadId,
    calle: calle,
    numero: numero,
    confirmadas: confirmadas,
    justificacionDuplicado: justificacion,
  );

  Future<ResultadoModificacionUbicacion> ok(ModificarUbicacionParams p) async =>
      (await modificar(p)).getOrElse(() => throw StateError('era un Left'));

  Future<Failure> falla(ModificarUbicacionParams p) async =>
      (await modificar(p)).swap().getOrElse(() => throw StateError('era un Right'));

  Future<UbicacionModel> guardada([String id = 'ub-1']) async => (await local.obtener(id))!;

  Future<void> espacioEn(
    String ubicacionId,
    String id, {
    DateTime? deletedAt,
    String? numeroDepto,
    String? piso,
    String? descripcion,
  }) => db
      .into(db.espacios)
      .insert(
        EspaciosCompanion.insert(
          id: id,
          ubicacionId: ubicacionId,
          numeroDepto: Value(numeroDepto),
          piso: Value(piso),
          descripcion: Value(descripcion),
          createdAt: t0,
          updatedAt: t0,
          createdBy: const Value('col-1'),
          deletedAt: Value(deletedAt),
          syncVersion: const Value(7),
        ),
      );

  Future<EspacioFila> espacio(String id) =>
      (db.select(db.espacios)..where((e) => e.id.equals(id))).getSingle();

  /// La primera cuenta de espacios que emite el stream de [local] para `ub-1`.
  Future<EspaciosActivos> primera() => local.observarEspaciosActivos('ub-1').first;

  /// Espera (hasta 2 s) a que [cuentas] tenga al menos [n] emisiones.
  Future<void> esperar(List<EspaciosActivos> cuentas, int n) async {
    for (var i = 0; i < 200 && cuentas.length < n; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// El `update` que el sync tiene que subir para [id] cuando se le quitó el número.
  Map<String, Object?> payloadEspacioSinNumero(String id, {String? piso, String? descripcion}) => {
    'id': id,
    'ubicacion_id': 'ub-1',
    'numero_depto': null,
    'piso': piso,
    'descripcion': descripcion,
    'created_at': t0.toIso8601String(),
    'updated_at': t1.toIso8601String(),
    'created_by': 'col-1',
    'deleted_at': null,
    'sync_version': 7,
  };

  /// Las entidades encoladas, solo por nombre (`ubicacion`, `espacio`), en orden.
  List<String> entidadesEncoladas() => [for (final c in encolador.encolados) c.entidad];

  List<Object?> cambiosEncolados() => [
    for (final c in encolador.encolados) [c.entidad, c.operacion, c.payload],
  ];

  group('Zona por posición, con las zonas en la DB', () {
    // «z-centro» cubre Italia y hasta 100 m al norte; «z-norte», de 100 a 300 m al norte.
    const confirmado = {ConfirmacionModificacion.desplazamiento};

    setUp(() async {
      final auditoria = Auditoria(createdAt: t0, updatedAt: t0);
      await db
          .into(db.campaniasCiudad)
          .insert(
            CampaniaCiudadModel(
              id: 'cc-1',
              campaniaId: 'camp-1',
              ciudadId: 'mvd',
              auditoria: auditoria,
            ).aFila(),
          );
      for (final (id, desde, hasta) in [('z-centro', -100.0, 100.0), ('z-norte', 100.0, 300.0)]) {
        await db
            .into(db.zonas)
            .insert(
              ZonaModel(
                id: id,
                nombre: id,
                campaniaCiudadId: 'cc-1',
                tipoForma: 'ESQUINAS',
                poligonoGeojson: rectanguloGeojson(
                  latSur: alNorte(desde).lat,
                  latNorte: alNorte(hasta).lat,
                  lonOeste: -56.13,
                  lonEste: -56.12,
                ),
                auditoria: auditoria,
              ).aFila(),
            );
      }
      modificar = ModificarUbicacionUseCase(
        repositorio,
        ubicador: UbicadorZona(
          ZonaRepositoryImpl(ZonaLocalDataSourceDrift(db), logger: loggerMudo()),
          InscripcionesEnMemoria([inscripcion('col-1', 'camp-1', zonaId: 'z-centro')]),
        ),
        ahora: () => t1,
      );
      await local.insertar(ubicacion());
      encolador.encolados.clear();
    });

    test('dado que mueve el pin a otra zona, guarda y encola la zona nueva', () async {
      final r = await ok(params(coordenadas: alNorte(150), confirmadas: confirmado));

      expect((r as UbicacionModificada).ubicacion.zonaId, 'z-norte');
      expect((await guardada()).zonaId, 'z-norte');
      expect(encolador.encolados.single.payload['zona_id'], 'z-norte');
    });

    test(
      'dado que mueve el pin fuera de toda zona, guarda y encola la ubicación sin zona',
      () async {
        final r = await ok(params(coordenadas: alNorte(2000), confirmadas: confirmado));

        expect((r as UbicacionModificada).ubicacion.zonaId, isNull);
        expect((await guardada()).zonaId, isNull);
        expect(encolador.encolados.single.payload['zona_id'], isNull);
      },
    );

    test('dado que no mueve el pin, conserva la zona que tenía', () async {
      await ok(params(numero: '1236'));

      expect((await guardada()).zonaId, 'zona-9');
    });
  });

  group('Edición simple de número de calle', () {
    test('dado el número "1234", cuando lo edita a "1236", se aplica local, sube la fila entera '
        'con updated_at nuevo y la misma sync_version', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();

      final r = await ok(params(numero: '1236'));

      final esperada = ubicacion(numero: '1236');
      final u = await guardada();
      expect(r, isA<UbicacionModificada>());
      expect(u.numero, '1236');
      expect(u.auditoria.updatedAt, t1);
      expect(u.auditoria.syncVersion, 4, reason: 'la sube el servidor al aceptar el update');
      expect(u.auditoria.createdAt, t0);
      expect(u.auditoria.createdBy, 'col-1');
      expect(u.zonaId, 'zona-9');
      expect(u.calle, esperada.calle);
      expect(cambiosEncolados(), [
        [
          'ubicacion',
          OperacionSync.update,
          {...esperada.toJson(), 'updated_at': t1.toIso8601String()},
        ],
      ]);
    });

    test('dado que cambia la calle, el punto y el tipo, cuando modifica, guarda todo', () async {
      await local.insertar(ubicacion());

      await ok(
        params(calle: 'Bulevar Artigas', coordenadas: alNorte(20), tipo: TipoUbicacion.negocio),
      );

      final u = await guardada();
      expect((u.calle, u.lat, u.tipo), ('Bulevar Artigas', alNorte(20).lat, TipoUbicacion.negocio));
    });

    test('dado que nada cambia, cuando modifica, no escribe ni encola', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();

      expect(await ok(params()), isA<ModificacionSinCambios>());

      expect(encolador.encolados, isEmpty);
      expect((await guardada()).auditoria.updatedAt, t0);
    });

    test('dado una ubicación que no existe, cuando modifica, falla como inexistente', () async {
      expect(await falla(params(id: 'nada')), isA<FailureUbicacionInexistente>());
    });
  });

  group('Cambio de tipo bloqueado (dos o más espacios activos)', () {
    test('dado un EDIFICIO con 3 espacios activos y uno dado de baja, cuando intenta pasarlo a '
        'CASA, se bloquea con 3 y no se escribe nada', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      for (final id in ['e1', 'e2', 'e3']) {
        await espacioEn('ub-1', id, numeroDepto: id);
      }
      await espacioEn('ub-1', 'e4-baja', deletedAt: t0);
      encolador.encolados.clear();

      final f = await falla(params(tipo: TipoUbicacion.casa));

      expect(f, const FailureUbicacionConEspacios(cantidadEspacios: 3));
      expect((await guardada()).tipo, TipoUbicacion.edificio);
      expect((await espacio('e1')).numeroDepto, 'e1');
      expect(encolador.encolados, isEmpty);
    });

    test(
      'dado un NEGOCIO con 2 espacios activos, cuando intenta pasarlo a CASA, se bloquea y no se '
      'escribe nada',
      () async {
        await local.insertar(ubicacion(tipo: TipoUbicacion.negocio));
        await espacioEn('ub-1', 'e1', numeroDepto: '1');
        await espacioEn('ub-1', 'e2', numeroDepto: '2');
        await espacioEn('ub-1', 'e3-baja', deletedAt: t0);
        encolador.encolados.clear();

        final f = await falla(params(tipo: TipoUbicacion.casa));

        expect(f, const FailureUbicacionConEspacios(cantidadEspacios: 2));
        expect((await guardada()).tipo, TipoUbicacion.negocio);
        expect([(await espacio('e1')).numeroDepto, (await espacio('e2')).numeroDepto], ['1', '2']);
        expect(encolador.encolados, isEmpty);
      },
    );

    test('dado un NEGOCIO con 2 espacios activos, cuando pasa a EDIFICIO, se permite y los '
        'espacios no se tocan', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.negocio));
      await espacioEn('ub-1', 'e1', numeroDepto: '1');
      await espacioEn('ub-1', 'e2', numeroDepto: '2');
      encolador.encolados.clear();

      await ok(params(tipo: TipoUbicacion.edificio));

      expect((await guardada()).tipo, TipoUbicacion.edificio);
      expect([(await espacio('e1')).numeroDepto, (await espacio('e2')).numeroDepto], ['1', '2']);
      expect(entidadesEncoladas(), ['ubicacion']);
    });

    test('dado un EDIFICIO con 2 espacios activos, cuando intenta pasarlo a NEGOCIO, se bloquea y '
        'ningún depto pierde su número', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'e1', numeroDepto: '3B');
      await espacioEn('ub-1', 'e2', numeroDepto: '4C');
      encolador.encolados.clear();

      final f = await falla(params(tipo: TipoUbicacion.negocio));

      expect(f, const FailureUbicacionConEspacios(cantidadEspacios: 2));
      expect((await guardada()).tipo, TipoUbicacion.edificio);
      expect([(await espacio('e1')).numeroDepto, (await espacio('e2')).numeroDepto], ['3B', '4C']);
      expect(encolador.encolados, isEmpty);
    });

    test('dado un EDIFICIO con todos los espacios dados de baja, cuando pasa a NEGOCIO, se permite '
        'y no toca los de baja', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'e1', deletedAt: t0, numeroDepto: '2A');
      encolador.encolados.clear();

      await ok(params(tipo: TipoUbicacion.negocio));

      expect((await guardada()).tipo, TipoUbicacion.negocio);
      expect((await espacio('e1')).numeroDepto, '2A');
      expect(entidadesEncoladas(), ['ubicacion']);
    });

    test('dado un espacio que aparece entre que se contó y que se escribe, cuando el repositorio '
        'escribe, vuelve a contar en la transacción: bloquea y no suelta ningún número', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'e1', numeroDepto: '3B');
      await espacioEn('ub-1', 'e2', numeroDepto: '4C');
      encolador.encolados.clear();
      final editada = UbicacionModel(
        id: 'ub-1',
        tipo: TipoUbicacion.casa,
        calle: 'Av. Italia',
        numero: '1234',
        lat: italia.lat,
        lon: italia.lon,
        ciudadId: 'mvd',
        zonaId: 'zona-9',
        auditoria: Auditoria(createdAt: t0, updatedAt: t1, createdBy: 'col-1', syncVersion: 4),
      ).toEntity();

      final r = await repositorio.modificar(editada, baseUpdatedAt: t0, reduceAUnEspacio: true);

      expect(
        r.swap().getOrElse(() => throw StateError('era un Right')),
        const FailureUbicacionConEspacios(cantidadEspacios: 2),
      );
      expect((await guardada()).tipo, TipoUbicacion.edificio);
      expect([(await espacio('e1')).numeroDepto, (await espacio('e2')).numeroDepto], ['3B', '4C']);
      expect(encolador.encolados, isEmpty);
    });

    test('dado el data source, cuando hay 2 espacios activos y deja de ser edificio, lanza la '
        'excepción tipada con la cuenta', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'e1');
      await espacioEn('ub-1', 'e2');

      await expectLater(
        local.actualizar(
          ubicacion(tipo: TipoUbicacion.casa),
          baseUpdatedAt: t0,
          reduceAUnEspacio: true,
        ),
        throwsA(isA<UbicacionConEspaciosException>().having((e) => e.cantidad, 'cantidad', 2)),
      );
    });
  });

  group('Un solo departamento: Edificio ↔ Casa/Negocio (decisión de Cristian, 07/10)', () {
    test(
      'dado un único espacio activo con número, cuando se observan los espacios, emite la cuenta '
      'y el número; con dos activos, sin número o sin espacios, la cuenta sin número',
      () async {
        await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
        expect(await primera(), (cantidad: 0, numeroDeptoUnico: null), reason: 'sin espacios');

        await espacioEn('ub-1', 'baja', numeroDepto: '9Z', deletedAt: t0);
        expect(await primera(), (
          cantidad: 0,
          numeroDeptoUnico: null,
        ), reason: 'el de baja no cuenta');

        await espacioEn('ub-1', 'e1', numeroDepto: '3B');
        expect(await primera(), (cantidad: 1, numeroDeptoUnico: '3B'));

        await espacioEn('ub-1', 'e2', numeroDepto: '4C');
        expect(await primera(), (cantidad: 2, numeroDeptoUnico: null), reason: 'dos activos');
      },
    );

    test('dado el único espacio activo sin número, cuando se observan los espacios, emite la '
        'cuenta 1 sin número', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.negocio));
      await espacioEn('ub-1', 'e1');

      expect(await primera(), (cantidad: 1, numeroDeptoUnico: null));
    });

    test(
      'dado que los espacios son de otra ubicación, cuando se observan, no los cuenta',
      () async {
        await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
        await local.insertar(ubicacion(id: 'ub-2', tipo: TipoUbicacion.edificio));
        await espacioEn('ub-2', 'otro', numeroDepto: '1A');

        expect(await primera(), (cantidad: 0, numeroDeptoUnico: null));
      },
    );

    test('dado el stream abierto, cuando llega un espacio, se da de baja o cambia de número, '
        'emite la cuenta de ahora, y no repite una escritura que no cambia nada', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'e1', numeroDepto: '3B');
      final cuentas = <EspaciosActivos>[];
      final sub = local.observarEspaciosActivos('ub-1').listen(cuentas.add);
      addTearDown(sub.cancel);
      await esperar(cuentas, 1);
      expect(cuentas, [(cantidad: 1, numeroDeptoUnico: '3B')]);

      await espacioEn('ub-1', 'e2', numeroDepto: '4C');
      await esperar(cuentas, 2);
      expect(cuentas.last, (cantidad: 2, numeroDeptoUnico: null));

      // Un cambio que no mueve ni la cuenta ni el número (la descripción del espacio): sin emisión.
      await (db.update(db.espacios)..where((e) => e.id.equals('e2'))).write(
        const EspaciosCompanion(descripcion: Value('al fondo')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(cuentas, hasLength(2), reason: 'distinct: igual a la anterior');

      await (db.update(
        db.espacios,
      )..where((e) => e.id.equals('e2'))).write(EspaciosCompanion(deletedAt: Value(t1)));
      await esperar(cuentas, 3);
      expect(cuentas.last, (cantidad: 1, numeroDeptoUnico: '3B'));

      await (db.update(
        db.espacios,
      )..where((e) => e.id.equals('e1'))).write(const EspaciosCompanion(numeroDepto: Value(null)));
      await esperar(cuentas, 4);
      expect(cuentas.last, (cantidad: 1, numeroDeptoUnico: null));
    });

    test('dado un EDIFICIO con un solo depto "3B", cuando pasa a CASA, el depto queda como el '
        'espacio de la casa, sin número, y se encolan los dos cambios', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'e1', numeroDepto: '3B', piso: '3', descripcion: 'al fondo');
      encolador.encolados.clear();

      final r = await ok(params(tipo: TipoUbicacion.casa));

      expect(r, isA<UbicacionModificada>());
      expect((await guardada()).tipo, TipoUbicacion.casa);
      final e = await espacio('e1');
      expect(e.numeroDepto, isNull);
      expect((e.piso, e.descripcion), ('3', 'al fondo'), reason: 'lo demás queda igual');
      expect(e.updatedAt, t1);
      expect((e.createdAt, e.createdBy, e.syncVersion, e.deletedAt), (t0, 'col-1', 7, null));
      expect(cambiosEncolados(), [
        [
          'ubicacion',
          OperacionSync.update,
          {...ubicacion(tipo: TipoUbicacion.casa).toJson(), 'updated_at': t1.toIso8601String()},
        ],
        [
          'espacio',
          OperacionSync.update,
          payloadEspacioSinNumero('e1', piso: '3', descripcion: 'al fondo'),
        ],
      ]);
    });

    test(
      'dado un EDIFICIO con un solo depto, cuando pasa a NEGOCIO, también queda sin número',
      () async {
        await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
        await espacioEn('ub-1', 'e1', numeroDepto: '12');

        await ok(params(tipo: TipoUbicacion.negocio));

        expect((await guardada()).tipo, TipoUbicacion.negocio);
        expect((await espacio('e1')).numeroDepto, isNull);
      },
    );

    test('dado un NEGOCIO con un solo espacio "L2", cuando pasa a CASA, el espacio queda sin '
        'número y se encolan los dos cambios', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.negocio));
      await espacioEn('ub-1', 'e1', numeroDepto: 'L2', piso: '1');
      encolador.encolados.clear();

      final r = await ok(params(tipo: TipoUbicacion.casa));

      expect(r, isA<UbicacionModificada>());
      expect((await guardada()).tipo, TipoUbicacion.casa);
      final e = await espacio('e1');
      expect((e.numeroDepto, e.piso, e.updatedAt), (null, '1', t1));
      expect(entidadesEncoladas(), ['ubicacion', 'espacio']);
    });

    test('dado un depto activo y otros dados de baja, cuando pasa a CASA, cuenta solo el activo y '
        'los de baja quedan como están', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'activo', numeroDepto: '3B');
      await espacioEn('ub-1', 'baja-1', numeroDepto: '4C', deletedAt: t0);
      await espacioEn('ub-1', 'baja-2', numeroDepto: '5D', deletedAt: t0);
      encolador.encolados.clear();

      await ok(params(tipo: TipoUbicacion.casa));

      expect((await espacio('activo')).numeroDepto, isNull);
      for (final (id, numero) in [('baja-1', '4C'), ('baja-2', '5D')]) {
        final e = await espacio(id);
        expect((e.numeroDepto, e.updatedAt, e.deletedAt), (numero, t0, t0), reason: id);
      }
      expect(entidadesEncoladas(), ['ubicacion', 'espacio']);
    });

    test('dado un depto que ya no tenía número, cuando pasa a CASA, no escribe ni encola nada del '
        'espacio', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'e1');
      encolador.encolados.clear();

      await ok(params(tipo: TipoUbicacion.casa));

      expect((await guardada()).tipo, TipoUbicacion.casa);
      expect((await espacio('e1')).updatedAt, t0);
      expect(entidadesEncoladas(), ['ubicacion']);
    });

    test('dado un EDIFICIO sin ningún espacio, cuando pasa a CASA, se permite', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      encolador.encolados.clear();

      await ok(params(tipo: TipoUbicacion.casa));

      expect((await guardada()).tipo, TipoUbicacion.casa);
      expect(entidadesEncoladas(), ['ubicacion']);
    });

    test('dado el cambio de tipo junto con otros (la calle y el número), cuando guarda, el depto '
        'también queda sin número', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'e1', numeroDepto: '3B');

      await ok(params(tipo: TipoUbicacion.casa, calle: 'Bulevar Artigas', numero: '99'));

      final u = await guardada();
      expect((u.tipo, u.calle, u.numero), (TipoUbicacion.casa, 'Bulevar Artigas', '99'));
      expect((await espacio('e1')).numeroDepto, isNull);
    });

    test('dado que el encolado del espacio falla, cuando guarda, no queda a medias: la ubicación '
        'sigue siendo edificio y el depto conserva el número', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'e1', numeroDepto: '3B');
      encolador
        ..fallarCon = StateError('motor apagado')
        ..fallarDespuesDe = encolador.encolados.length + 1;

      final f = await falla(params(tipo: TipoUbicacion.casa));

      expect(f, isA<FailureInesperado>());
      final u = await guardada();
      expect((u.tipo, u.auditoria.updatedAt), (TipoUbicacion.edificio, t0));
      final e = await espacio('e1');
      expect((e.numeroDepto, e.updatedAt), ('3B', t0));
    });

    test('dado un aviso de posible duplicado, cuando el colportor todavía no confirmó, no se toca '
        'el depto; con "seguir igual" se guardan los dos cambios', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await local.insertar(ubicacion(id: 'ub-2', numero: '1237', punto: alNorte(150)));
      await espacioEn('ub-1', 'e1', numeroDepto: '3B');
      encolador.encolados.clear();

      final frenada = await ok(params(tipo: TipoUbicacion.casa, numero: '1237'));

      expect(frenada, isA<ModificacionConDuplicados>());
      expect((await guardada()).tipo, TipoUbicacion.edificio);
      expect((await espacio('e1')).numeroDepto, '3B');
      expect(encolador.encolados, isEmpty);

      await ok(
        params(
          tipo: TipoUbicacion.casa,
          numero: '1237',
          justificacion: 'Son dos casas del mismo número',
        ),
      );

      expect((await guardada()).tipo, TipoUbicacion.casa);
      expect((await espacio('e1')).numeroDepto, isNull);
      expect(entidadesEncoladas(), ['ubicacion', 'espacio']);
    });

    test('dado un doble toque en "Guardar", cuando el segundo llega con la base vieja, no vuelve a '
        'tocar el espacio', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'e1', numeroDepto: '3B');
      encolador.encolados.clear();

      final primero = await ok(params(tipo: TipoUbicacion.casa));
      final segundo = await ok(params(tipo: TipoUbicacion.casa));

      expect(primero, isA<UbicacionModificada>());
      expect(segundo, isA<UbicacionModificada>());
      expect(entidadesEncoladas(), ['ubicacion', 'espacio']);
    });

    test('dado una CASA con su espacio sin número, cuando pasa a EDIFICIO, el espacio queda como '
        'el primer depto, sin número, y no se toca', () async {
      await local.insertar(ubicacion());
      await espacioEn('ub-1', 'e1', piso: 'PB');
      encolador.encolados.clear();

      await ok(params(tipo: TipoUbicacion.edificio));

      expect((await guardada()).tipo, TipoUbicacion.edificio);
      final e = await espacio('e1');
      expect((e.numeroDepto, e.piso, e.updatedAt, e.deletedAt), (null, 'PB', t0, null));
      expect(entidadesEncoladas(), ['ubicacion']);
    });

    test('dado un EDIFICIO con un depto "3B" que pasa a CASA y vuelve a EDIFICIO, el depto sigue '
        'ahí, ahora sin número', () async {
      await local.insertar(ubicacion(tipo: TipoUbicacion.edificio));
      await espacioEn('ub-1', 'e1', numeroDepto: '3B');
      await ok(params(tipo: TipoUbicacion.casa));
      encolador.encolados.clear();

      await ok(params(tipo: TipoUbicacion.edificio, base: t1));

      expect((await guardada()).tipo, TipoUbicacion.edificio);
      final e = await espacio('e1');
      expect((e.numeroDepto, e.deletedAt), (null, null));
      expect(entidadesEncoladas(), ['ubicacion']);
    });
  });

  group('Desplazamiento y ciudad', () {
    test(
      'dado un desplazamiento de 150 m, cuando modifica, pide confirmar y solo con la confirmación '
      'escribe',
      () async {
        await local.insertar(ubicacion());

        final r = await ok(params(coordenadas: alNorte(150)));
        expect((r as ModificacionRequiereConfirmacion).pendientes, {
          ConfirmacionModificacion.desplazamiento,
        });
        expect((await guardada()).lat, italia.lat);

        await ok(
          params(coordenadas: alNorte(150), confirmadas: {ConfirmacionModificacion.desplazamiento}),
        );
        expect((await guardada()).lat, alNorte(150).lat);
      },
    );

    test('dado un cambio de ciudad, cuando lo confirma, se guarda', () async {
      await local.insertar(ubicacion());

      await ok(params(ciudadId: 'sal', confirmadas: {ConfirmacionModificacion.cambioCiudad}));

      expect((await guardada()).ciudadId, 'sal');
    });
  });

  group('Ubicación dada de baja', () {
    test(
      'dado una baja, cuando la edita, pide reactivar; confirmado, queda activa y el payload sube '
      'deleted_at en null',
      () async {
        await local.insertar(ubicacion(deletedAt: t0));
        encolador.encolados.clear();

        final pide = await ok(params(numero: '1236'));
        expect(pide, isA<ModificacionRequiereConfirmacion>());
        expect((await guardada()).auditoria.deletedAt, t0);
        expect(encolador.encolados, isEmpty);

        final r = await ok(
          params(numero: '1236', confirmadas: {ConfirmacionModificacion.reactivar}),
        );

        expect((r as UbicacionModificada).reactivada, isTrue);
        expect((await guardada()).auditoria.deletedAt, isNull);
        expect(encolador.encolados.single.payload['deleted_at'], isNull);
        expect(encolador.encolados.single.operacion, OperacionSync.update);
      },
    );
  });

  group('Ubicación de baja con la ciudad fuera del catálogo', () {
    test(
      'dado una baja cuya ciudad ya no está en el catálogo, cuando la edita y confirma reactivar, '
      'queda activa con su ciudad y se encola el update (no se frena por la ciudad)',
      () async {
        await local.insertar(ubicacion(deletedAt: t0, ciudadId: 'ciudad-que-ya-no-esta'));
        encolador.encolados.clear();

        final r = await ok(
          params(
            numero: '1236',
            ciudadId: 'ciudad-que-ya-no-esta',
            confirmadas: {ConfirmacionModificacion.reactivar},
          ),
        );

        expect((r as UbicacionModificada).reactivada, isTrue);
        final u = await guardada();
        expect((u.auditoria.deletedAt, u.ciudadId), (null, 'ciudad-que-ya-no-esta'));
        expect(encolador.encolados.single.operacion, OperacionSync.update);
      },
    );
  });

  group('Re-chequeo de duplicados', () {
    setUp(() async {
      await local.insertar(ubicacion());
      // Otra casa a ~10 m con el número 1236: editar la primera a "1236" la deja con la misma
      // dirección (calle, número y ciudad).
      await local.insertar(ubicacion(id: 'ub-2', numero: '1236', punto: alNorte(10)));
      encolador.encolados.clear();
    });

    test('dado que la edición la deja con la misma dirección que otra, cuando modifica, devuelve '
        'la candidata (nunca ella misma) y no escribe ni encola', () async {
      final r = await ok(params(numero: '1236'));

      expect(r, isA<ModificacionConDuplicados>());
      final candidata = (r as ModificacionConDuplicados).candidatas.single;
      expect((candidata.ubicacion.id, candidata.motivo), ('ub-2', MotivoDuplicado.mismaDireccion));
      expect((await guardada()).numero, '1234');
      expect(encolador.encolados, isEmpty);
    });

    test('D1: dado "seguir igual" con motivo y la misma dirección a ~10 m, cuando modifica, no '
        'guarda: sigue devolviendo la candidata, que no admite conservar las dos', () async {
      final r = await ok(params(numero: '1236', justificacion: 'Son dos locales distintos'));

      expect(r, isA<ModificacionConDuplicados>());
      final candidata = (r as ModificacionConDuplicados).candidatas.single;
      expect((candidata.ubicacion.id, candidata.admiteConservarAmbos), ('ub-2', false));
      expect((await guardada()).numero, '1234');
      expect(encolador.encolados, isEmpty);
    });

    test(
      'D1: dado la misma dirección a 150 m, cuando modifica avisa, y con "seguir igual" y motivo '
      'guarda (dos casas con el mismo número)',
      () async {
        await local.insertar(ubicacion(id: 'ub-5', numero: '1237', punto: alNorte(150)));
        encolador.encolados.clear();

        final aviso = await ok(params(numero: '1237'));
        expect(aviso, isA<ModificacionConDuplicados>());
        expect((aviso as ModificacionConDuplicados).candidatas.single.admiteConservarAmbos, isTrue);
        expect((await guardada()).numero, '1234');

        final r = await ok(params(numero: '1237', justificacion: 'Son dos casas del mismo número'));

        expect(r, isA<UbicacionModificada>());
        expect((await guardada()).numero, '1237');
        expect(encolador.encolados, hasLength(1));
      },
    );

    test(
      'dado que la otra está dada de baja o es de otra ciudad, cuando modifica, no es candidata',
      () async {
        await (db.update(
          db.ubicaciones,
        )..where((u) => u.id.equals('ub-2'))).write(UbicacionesCompanion(deletedAt: Value(t0)));
        expect(await ok(params(numero: '1236')), isA<UbicacionModificada>());

        await local.insertar(
          ubicacion(id: 'ub-3', numero: '77', ciudadId: 'sal', punto: alNorte(300)),
        );
        expect(await ok(params(numero: '77', base: t1)), isA<UbicacionModificada>());
      },
    );

    test('dado que solo cambia el tipo, cuando modifica, no vuelve a buscar duplicados', () async {
      await local.insertar(ubicacion(id: 'ub-4', numero: '1234', punto: alNorte(5)));

      final r = await ok(params(tipo: TipoUbicacion.negocio));

      expect(r, isA<UbicacionModificada>());
    });
  });

  group('Transacción y edición concurrente', () {
    test('dado que el pull trae una corrección entre que abre la edición y guarda, cuando guarda, '
        'no la pisa: falla como cambio concurrente y no encola', () async {
      await local.insertar(ubicacion(calle: 'Av Italia'));
      encolador.encolados.clear();
      // La pantalla cargó la ubicación con updated_at = t0 y el colportor está editando el número.
      final entrante = t0.add(const Duration(minutes: 5));
      await (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
        UbicacionesCompanion(updatedAt: Value(entrante), calle: const Value('Av. Italia')),
      );

      final f = await falla(params(calle: 'Av Italia', numero: '1236', base: t0));

      expect(f, const FailureUbicacionCambio());
      final u = await guardada();
      expect((u.calle, u.numero), ('Av. Italia', '1234'));
      expect(encolador.encolados, isEmpty);
    });

    test('dado el mismo guardado con la base al día, cuando el pull ya trajo la fila, guarda '
        'sobre esa versión', () async {
      await local.insertar(ubicacion());
      final entrante = t0.add(const Duration(minutes: 5));
      await (db.update(
        db.ubicaciones,
      )..where((u) => u.id.equals('ub-1'))).write(UbicacionesCompanion(updatedAt: Value(entrante)));

      final r = await ok(params(numero: '1236', base: entrante));

      expect(r, isA<UbicacionModificada>());
      expect((await guardada()).numero, '1236');
    });

    test('dado un doble toque en "Guardar", cuando el segundo llega con la base vieja y la fila ya '
        'tiene esos valores, es un éxito idempotente y no encola de nuevo', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();

      final primero = await ok(params(numero: '1236'));
      final segundo = await ok(params(numero: '1236'));

      expect(primero, isA<UbicacionModificada>());
      expect(segundo, isA<UbicacionModificada>());
      expect((segundo as UbicacionModificada).ubicacion.numero, '1236');
      expect(encolador.encolados, hasLength(1));
      expect((await guardada()).auditoria.updatedAt, t1);
    });

    test('dado que el encolado falla, cuando modifica, la fila queda como estaba', () async {
      await local.insertar(ubicacion());
      encolador.fallarCon = StateError('motor apagado');

      final f = await falla(params(numero: '1236'));

      expect(f, isA<FailureInesperado>());
      final u = await guardada();
      expect((u.numero, u.auditoria.updatedAt), ('1234', t0));
    });

    test('dado que la fila cambió desde que se leyó (sync entrante), cuando guarda, no la pisa y '
        'devuelve el cambio concurrente', () async {
      await local.insertar(ubicacion());
      encolador.encolados.clear();
      final entrante = t0.add(const Duration(minutes: 5));
      await (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
        UbicacionesCompanion(updatedAt: Value(entrante), numero: const Value('99')),
      );

      final r = await repositorio.modificar(
        ubicacion(numero: '1236').toEntity(),
        baseUpdatedAt: t0,
      );

      expect(
        r.swap().getOrElse(() => throw StateError('era un Right')),
        isA<FailureUbicacionCambio>(),
      );
      expect((await guardada()).numero, '99');
      expect(encolador.encolados, isEmpty);
    });

    test(
      'dado el data source, cuando la fila no existe o cambió, lanza la excepción tipada',
      () async {
        await local.insertar(ubicacion());

        await expectLater(
          local.actualizar(ubicacion(id: 'nada'), baseUpdatedAt: t0),
          throwsA(isA<UbicacionInexistenteException>()),
        );
        await expectLater(
          local.actualizar(ubicacion(), baseUpdatedAt: t1),
          throwsA(isA<UbicacionCambioException>()),
        );
      },
    );
  });
}
