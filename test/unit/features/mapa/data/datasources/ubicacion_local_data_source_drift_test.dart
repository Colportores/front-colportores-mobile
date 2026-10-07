// Test de la capa data contra las tablas reales: AppDatabase en memoria (sin cifrado — el cifrado
// se prueba en database_helper_test.dart), mismo esquema y mismas restricciones que en el
// dispositivo. Los últimos grupos recorren el alta entera (caso de uso → repositorio → Drift).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/registrar_ubicacion_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/zonas_falsas.dart';

/// Metros → grados de latitud con el radio de la Tierra de `Coordenadas`.
double _grados(double metros) => metros / 111195.08;

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 13, 45, 10, 123);
  const criterio = CriterioDuplicadoUbicacion();

  UbicacionModel ubicacion({
    String id = 'ub-1',
    String? calle = 'Av. Italia',
    String? numero = '1234',
    double metrosAlNorte = 0,
    double lon = -56.125,
    String ciudadId = 'mvd',
    DateTime? deletedAt,
  }) => UbicacionModel(
    id: id,
    tipo: TipoUbicacion.casa,
    calle: calle,
    numero: numero,
    lat: -34.891 + _grados(metrosAlNorte),
    lon: lon,
    ciudadId: ciudadId,
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1', deletedAt: deletedAt),
  );

  EspacioModel espacio({String id = 'esp-1', String ubicacionId = 'ub-1'}) => EspacioModel(
    id: id,
    ubicacionId: ubicacionId,
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador);
  });

  tearDown(() => db.close());

  Future<int> filas(String tabla) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $tabla').getSingle()).read<int>('n');

  group('UbicacionLocalDataSourceDrift.insertar', () {
    test('dado una ubicación con su espacio, cuando inserta, guarda las dos filas tal cual y '
        'encola primero la ubicación y después el espacio, con la fila entera', () async {
      final u = ubicacion();
      final e = espacio();

      final r = await local.insertar(u, espacio: e, duplicados: criterio);

      expect(r.yaEstaba, isFalse);
      expect(r.ubicacion, u);
      expect(await filas('ubicacion'), 1);
      expect(await filas('espacio'), 1);
      // Listas y no records: un record compara el Map por identidad, `equals` lo compara por dentro.
      expect(encolador.encolados.map((c) => [c.entidad, c.operacion, c.payload]).toList(), [
        ['ubicacion', OperacionSync.insert, u.toJson()],
        ['espacio', OperacionSync.insert, e.toJson()],
      ]);
      final fila = await db.customSelect('SELECT tipo, created_at FROM ubicacion').getSingle();
      expect(fila.read<String>('tipo'), 'CASA');
      expect(fila.read<int>('created_at'), t0.millisecondsSinceEpoch);
    });

    test('dado una ubicación sin espacio, cuando inserta, encola solo la ubicación', () async {
      await local.insertar(ubicacion(calle: null, numero: null));

      expect(await filas('espacio'), 0);
      expect(encolador.encolados.map((c) => c.entidad), ['ubicacion']);
    });

    test('dado que ya existe una ubicación con ese id, cuando inserta de nuevo (doble toque), no '
        'escribe ni encola nada y devuelve la que estaba', () async {
      await local.insertar(ubicacion(), espacio: espacio(), duplicados: criterio);

      final r = await local.insertar(
        ubicacion(calle: 'Otra'),
        espacio: espacio(id: 'esp-2'),
        duplicados: criterio,
      );

      expect(r.yaEstaba, isTrue);
      expect(r.ubicacion.calle, 'Av. Italia');
      expect(await filas('ubicacion'), 1);
      expect(await filas('espacio'), 1);
      expect(encolador.encolados, hasLength(2));
    });

    test('dado dos inserciones simultáneas con el mismo id, cuando terminan, hay una sola '
        'ubicación', () async {
      final resultados = await Future.wait([
        local.insertar(ubicacion(), espacio: espacio(), duplicados: criterio),
        local.insertar(
          ubicacion(),
          espacio: espacio(id: 'esp-2'),
          duplicados: criterio,
        ),
      ]);

      expect(resultados.where((r) => r.yaEstaba), hasLength(1));
      expect(await filas('ubicacion'), 1);
      expect(await filas('espacio'), 1);
    });

    /// Las candidatas de una [UbicacionDuplicadaException] como `[id, motivo]`.
    Matcher lanzaCandidatas(List<List<Object>> esperadas) => throwsA(
      isA<UbicacionDuplicadaException>().having(
        (e) => [
          for (final c in e.candidatas) [c.ubicacion.id, c.motivo],
        ],
        'candidatas',
        esperadas,
      ),
    );

    test('dado "Av. Italia 1234" activa a 300 m, cuando inserta otra en la misma dirección con el '
        'criterio, lanza UbicacionDuplicadaException con la candidata y no escribe nada', () async {
      final existente = ubicacion(id: 'ub-existente', metrosAlNorte: 300);
      await local.insertar(existente);
      encolador.encolados.clear();

      final intento = local.insertar(ubicacion(), espacio: espacio(), duplicados: criterio);

      await expectLater(
        intento,
        throwsA(
          isA<UbicacionDuplicadaException>().having(
            (e) => e.candidatas.single.ubicacion,
            'candidata',
            existente.toEntity(),
          ),
        ),
      );
      expect(await filas('ubicacion'), 1);
      expect(await filas('espacio'), 0);
      expect(encolador.encolados, isEmpty);
    });

    test(
      'dado la misma dirección con el número en otras mayúsculas y otra dirección a 3 m en otra '
      'ciudad, cuando inserta, las dos son candidatas, de la más cercana a la más lejana',
      () async {
        await local.insertar(ubicacion(id: 'mayusculas', numero: ' 1234 BIS', metrosAlNorte: 300));
        await local.insertar(
          ubicacion(id: 'cerca', calle: 'Comercio', ciudadId: 'canelones', metrosAlNorte: 3),
        );

        await expectLater(
          local.insertar(ubicacion(numero: '1234 bis'), duplicados: criterio),
          lanzaCandidatas([
            ['cerca', MotivoDuplicado.cercania],
            ['mayusculas', MotivoDuplicado.mismaDireccion],
          ]),
        );
      },
    );

    test('dado otra dirección a 6 m, otro número, la misma dirección en otra ciudad o una baja, '
        'cuando inserta, no las toma como duplicadas', () async {
      await local.insertar(ubicacion(id: 'a-6m', calle: 'Comercio', metrosAlNorte: 6));
      await local.insertar(ubicacion(id: 'al-este', calle: 'Comercio', lon: -56.125 + 0.0004));
      await local.insertar(ubicacion(id: 'otro-numero', numero: '1236', metrosAlNorte: 300));
      await local.insertar(ubicacion(id: 'canelones', ciudadId: 'canelones', metrosAlNorte: 300));
      await local.insertar(ubicacion(id: 'baja', metrosAlNorte: 1, deletedAt: t0));

      final r = await local.insertar(ubicacion(), duplicados: criterio);

      expect(r.yaEstaba, isFalse);
      expect(await filas('ubicacion'), 6);
    });

    test(
      'dado D1, cuando "Crear igual" inserta junto a la misma dirección a menos de 100 m, la frena; '
      'junto a la misma dirección a 100 m o más o a una solo cercana, la guarda',
      () async {
        final alSeguirIgual = criterio.alSeguirIgual;
        await local.insertar(ubicacion(id: 'misma', metrosAlNorte: 15));
        await local.insertar(ubicacion(id: 'lejana', metrosAlNorte: 300));
        await local.insertar(ubicacion(id: 'cerca', calle: 'Comercio', metrosAlNorte: 3));

        await expectLater(
          local.insertar(ubicacion(), duplicados: alSeguirIgual),
          lanzaCandidatas([
            ['misma', MotivoDuplicado.mismaDireccion],
          ]),
        );
        // Otra dirección: la cercana (3 m) admite conservar ambos y la lejana ni es candidata.
        final r = await local.insertar(ubicacion(calle: 'Otra'), duplicados: alSeguirIgual);
        expect(r.yaEstaba, isFalse);
        // La misma dirección a 100 m o más de cada una de las que ya están: las dos casas quedan.
        final lejos = await local.insertar(
          ubicacion(id: 'otra-cuadra', metrosAlNorte: 600),
          duplicados: alSeguirIgual,
        );
        expect(lejos.yaEstaba, isFalse);
      },
    );

    test(
      'dado "Crear igual" (sin criterio), cuando inserta junto a un duplicado, la guarda',
      () async {
        await local.insertar(ubicacion(id: 'ub-existente', metrosAlNorte: 15));

        final r = await local.insertar(ubicacion());

        expect(r.yaEstaba, isFalse);
        expect(await filas('ubicacion'), 2);
      },
    );

    test('dado que encolar el sync falla, cuando inserta, se revierte todo: ni ubicación ni '
        'espacio quedan guardados', () async {
      encolador.fallarCon = StateError('motor apagado');

      await expectLater(
        local.insertar(ubicacion(), espacio: espacio(), duplicados: criterio),
        throwsStateError,
      );

      expect(await filas('ubicacion'), 0);
      expect(await filas('espacio'), 0);
    });

    test('dado que falla el segundo encolado (el del espacio), con la ubicación ya insertada y '
        'encolada, cuando inserta, se revierte todo', () async {
      encolador
        ..fallarCon = StateError('motor apagado')
        ..fallarDespuesDe = 1;

      await expectLater(
        local.insertar(ubicacion(), espacio: espacio(), duplicados: criterio),
        throwsStateError,
      );

      expect(await filas('ubicacion'), 0);
      expect(await filas('espacio'), 0);
      // El fake no es transaccional: el job de la ubicación le quedó anotado. Con el motor real,
      // `stage()` escribe en `sync_queue` dentro de la misma transacción y se revierte con todo.
      expect(encolador.encolados.map((c) => c.entidad), ['ubicacion']);
    });

    test(
      'dado un tipo que el CHECK no admite, cuando se escribe a mano, la DB lo rechaza',
      () async {
        await expectLater(
          db.customStatement(
            'INSERT INTO ubicacion (id, tipo, lat, lon, ciudad_id, created_at, updated_at) '
            "VALUES ('x', 'CARPA', 0, 0, 'mvd', 0, 0)",
          ),
          throwsA(isA<Exception>()),
        );
      },
    );
  });

  group('Alta de ubicación de punta a punta (caso de uso → repositorio → Drift)', () {
    late RegistrarUbicacionUseCase registrar;
    late int ids;

    setUp(() {
      ids = 0;
      registrar = RegistrarUbicacionUseCase(
        UbicacionRepositoryImpl(local, logger: loggerMudo()),
        generarId: () => 'id-${++ids}',
        ubicador: ubicadorSinZonas(),
        ahora: () => t0,
      );
    });

    RegistrarUbicacionParams params({
      String? id,
      String? justificacion,
      String calle = 'Av. Italia',
      String numero = '1234',
      double metrosAlNorte = 0,
    }) => RegistrarUbicacionParams(
      colportorId: 'col-1',
      tipo: TipoUbicacion.casa,
      punto: PuntoCapturado.gps(
        LecturaGps(
          coordenadas: Coordenadas(lat: -34.891 + _grados(metrosAlNorte), lon: -56.125),
          precisionMetros: 10,
        ),
      ),
      ciudadId: 'mvd',
      calle: calle,
      numero: numero,
      id: id ?? registrar.nuevoId(),
      justificacionDuplicado: justificacion,
    );

    /// Lo que devolvió un alta que no se creó: las candidatas que la frenaron.
    List<CandidataDuplicado> frenada(Either<Failure, ResultadoAltaUbicacion> r) =>
        (r.getOrElse(() => throw StateError('falló')) as AltaConDuplicados).candidatas;

    test('Offline: sin red el alta se completa localmente y deja la ubicación y su espacio '
        'encolados para el sync', () async {
      final r = await registrar(params());

      final alta = r.getOrElse(() => throw StateError('falló')) as AltaRegistrada;
      expect(alta.espacio, isNotNull);
      expect(await filas('ubicacion'), 1);
      expect(encolador.encolados.map((c) => c.entidad), ['ubicacion', 'espacio']);
      expect(encolador.encolados.first.payload['id'], alta.ubicacion.id);
    });

    test(
      'Detección de duplicado: la segunda alta de "Av. Italia 1234" a 15 m no se crea y devuelve '
      'la candidata, que no admite conservar ambos (D1); con "Crear igual" tampoco se crea',
      () async {
        await registrar(params());

        final segunda = await registrar(params(metrosAlNorte: 15));
        expect(frenada(segunda).map((c) => c.ubicacion.id), ['id-1']);
        expect(frenada(segunda).single.admiteConservarAmbos, isFalse);
        expect(await filas('ubicacion'), 1);

        final igual = await registrar(
          params(metrosAlNorte: 15, justificacion: 'Es otra casa en el mismo padrón'),
        );
        expect(frenada(igual).map((c) => c.ubicacion.id), ['id-1']);
        expect(await filas('ubicacion'), 1);
      },
    );

    test('D1, el caso del revisor de #267: «av.  itália» 1234 a 15 m de «Av. Italia» 1234 no crea '
        'el alta en silencio, ni con "Crear igual"', () async {
      await registrar(params());

      final sinCrear = await registrar(params(calle: 'av.  itália', metrosAlNorte: 15));
      final conCrearIgual = await registrar(
        params(calle: 'av.  itália', metrosAlNorte: 15, justificacion: 'Es otra casa'),
      );

      for (final r in [sinCrear, conCrearIgual]) {
        expect(frenada(r).map((c) => c.ubicacion.id), ['id-1']);
        expect(frenada(r).single.motivo, MotivoDuplicado.mismaDireccion);
        expect(frenada(r).single.admiteConservarAmbos, isFalse);
      }
      expect(await filas('ubicacion'), 1);
    });

    test('D1, la misma dirección con otro número de espacios o tildes en el número (12 bís contra '
        '12  BIS) a 15 m también choca', () async {
      await registrar(params(numero: '12 bís'));

      final r = await registrar(params(numero: '12  BIS', metrosAlNorte: 15));

      expect(frenada(r).single.admiteConservarAmbos, isFalse);
      expect(await filas('ubicacion'), 1);
    });

    test('D1, control: la misma dirección a 150 m avisa pero admite las dos; con "Crear igual" se '
        'crea', () async {
      await registrar(params());

      final aviso = await registrar(params(metrosAlNorte: 150));
      expect(frenada(aviso).map((c) => c.ubicacion.id), ['id-1']);
      expect(frenada(aviso).single.admiteConservarAmbos, isTrue);
      expect(await filas('ubicacion'), 1);

      final igual = await registrar(
        params(metrosAlNorte: 150, justificacion: 'Es otra casa en la misma calle'),
      );
      expect(igual.getOrElse(() => throw StateError('falló')), isA<AltaRegistrada>());
      expect(await filas('ubicacion'), 2);
    });

    test(
      'D1, otra dirección a menos de 5 m avisa (cercanía) y admite las dos: con "Crear igual" se '
      'crea',
      () async {
        await registrar(params());

        final aviso = await registrar(params(calle: 'Comercio', numero: '10', metrosAlNorte: 3));
        expect(frenada(aviso).single.motivo, MotivoDuplicado.cercania);
        expect(frenada(aviso).single.admiteConservarAmbos, isTrue);

        final igual = await registrar(
          params(
            calle: 'Comercio',
            numero: '10',
            metrosAlNorte: 3,
            justificacion: 'Local en planta',
          ),
        );
        expect(igual.getOrElse(() => throw StateError('falló')), isA<AltaRegistrada>());
        expect(await filas('ubicacion'), 2);
      },
    );

    test('D1, con candidatas que admiten y una que choca, "Crear igual" no crea: frena solo la que '
        'choca', () async {
      await local.insertar(ubicacion(id: 'lejana', metrosAlNorte: 300));
      await local.insertar(ubicacion(id: 'choca', metrosAlNorte: 40));
      await local.insertar(
        ubicacion(id: 'cercana', calle: 'Comercio', numero: '10', metrosAlNorte: 1),
      );

      final aviso = await registrar(params());
      final conCrearIgual = await registrar(params(justificacion: 'Es otra casa'));

      expect(frenada(aviso).map((c) => (c.ubicacion.id, c.admiteConservarAmbos)), [
        ('cercana', true),
        ('choca', false),
        ('lejana', true),
      ]);
      expect(frenada(conCrearIgual).map((c) => c.ubicacion.id), ['choca']);
      expect(await filas('ubicacion'), 3);
    });

    test('Doble toque: el mismo id del formulario no crea dos ubicaciones ni la marca como '
        'duplicada de sí misma', () async {
      final id = registrar.nuevoId();

      final primera = await registrar(params(id: id));
      final segunda = await registrar(params(id: id));

      expect(
        segunda,
        primera.map((a) => AltaRegistrada(ubicacion: (a as AltaRegistrada).ubicacion)),
      );
      expect(await filas('ubicacion'), 1);
      expect(await filas('espacio'), 1);
    });
  });

  group('UbicacionLocalDataSourceDrift.observarDelColportor', () {
    Future<List<String>> ids({String? ciudadId, bool incluirBajas = false}) async => [
      for (final u
          in await local
              .observarDelColportor(
                colportorId: 'col-1',
                ciudadId: ciudadId,
                incluirBajas: incluirBajas,
              )
              .first)
        u.id,
    ]..sort();

    test('dado ubicaciones de dos colportores, de dos ciudades y una baja, trae solo las del '
        'colportor y sin la baja; con incluirBajas la suma; con ciudad, la acota', () async {
      await local.insertar(ubicacion(id: 'mia'));
      await local.insertar(ubicacion(id: 'sal', ciudadId: 'sal', lon: -57));
      await local.insertar(ubicacion(id: 'baja', lon: -58, deletedAt: t0));
      final ajena = ubicacion(id: 'ajena', lon: -59);
      await local.insertar(
        UbicacionModel(
          id: ajena.id,
          tipo: ajena.tipo,
          calle: ajena.calle,
          numero: ajena.numero,
          lat: ajena.lat,
          lon: ajena.lon,
          ciudadId: ajena.ciudadId,
          auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-2'),
        ),
      );

      expect(await ids(), ['mia', 'sal']);
      expect(await ids(incluirBajas: true), ['baja', 'mia', 'sal']);
      expect(await ids(ciudadId: 'sal'), ['sal']);
    });

    test('es reactivo: un alta posterior vuelve a emitir sin pedir nada', () async {
      final emisiones = <List<String>>[];
      final sub = local
          .observarDelColportor(colportorId: 'col-1')
          .listen((l) => emisiones.add([for (final u in l) u.id]));
      await pumpEventQueue();

      await local.insertar(ubicacion(id: 'nueva'));
      await pumpEventQueue();

      expect(emisiones.first, isEmpty);
      expect(emisiones.last, ['nueva']);
      await sub.cancel();
    });

    test('es reactivo ante un update: la baja sale de la emisión siguiente y la edición se '
        'refleja', () async {
      await local.insertar(ubicacion(id: 'a'));
      await local.insertar(ubicacion(id: 'b', lon: -58));
      final emisiones = <List<({String id, String? calle})>>[];
      final sub = local
          .observarDelColportor(colportorId: 'col-1')
          .listen((l) => emisiones.add([for (final u in l) (id: u.id, calle: u.calle)]));
      await pumpEventQueue();
      expect(emisiones.last.map((u) => u.id), unorderedEquals(['a', 'b']));

      await (db.update(
        db.ubicaciones,
      )..where((u) => u.id.equals('a'))).write(UbicacionesCompanion(deletedAt: Value(t0)));
      await pumpEventQueue();
      expect(emisiones.last.map((u) => u.id), ['b']);

      await (db.update(db.ubicaciones)..where((u) => u.id.equals('b'))).write(
        const UbicacionesCompanion(calle: Value('Otra calle')),
      );
      await pumpEventQueue();
      expect(emisiones.last, [(id: 'b', calle: 'Otra calle')]);
      await sub.cancel();
    });
  });

  group('UbicacionLocalDataSourceDrift.observarListaDelColportor', () {
    Future<Map<String, int>> espaciosPorId({bool incluirBajas = false}) async => {
      for (final f
          in await local
              .observarListaDelColportor(colportorId: 'col-1', incluirBajas: incluirBajas)
              .first)
        f.ubicacion.id: f.cantidadEspacios,
    };

    Future<void> espacioSuelto(String id, String ubicacionId, {DateTime? baja}) => db
        .into(db.espacios)
        .insert(
          EspaciosCompanion.insert(
            id: id,
            ubicacionId: ubicacionId,
            createdAt: t0,
            updatedAt: t0,
            deletedAt: Value(baja),
          ),
        );

    test('dado ubicaciones de dos colportores y una baja, trae las del colportor sin la baja; con '
        'incluirBajas la suma', () async {
      await local.insertar(ubicacion(id: 'mia'));
      await local.insertar(ubicacion(id: 'baja', lon: -58, deletedAt: t0));
      await local.insertar(
        UbicacionModel(
          id: 'ajena',
          tipo: TipoUbicacion.casa,
          lat: -34.891,
          lon: -59,
          ciudadId: 'mvd',
          auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-2'),
        ),
      );

      expect((await espaciosPorId()).keys, ['mia']);
      expect((await espaciosPorId(incluirBajas: true)).keys, unorderedEquals(['mia', 'baja']));
    });

    test('cuenta los espacios sin baja de cada ubicación (0 si no tiene)', () async {
      await local.insertar(
        ubicacion(id: 'u1'),
        espacio: espacio(id: 'e1', ubicacionId: 'u1'),
      );
      await local.insertar(ubicacion(id: 'u2', lon: -56.13));
      await local.insertar(ubicacion(id: 'u3', lon: -56.14));
      await espacioSuelto('e2', 'u1');
      await espacioSuelto('e3-baja', 'u1', baja: t0);
      await espacioSuelto('e4-baja', 'u3', baja: t0);

      expect(await espaciosPorId(), {'u1': 2, 'u2': 0, 'u3': 0});
    });

    test('una ubicación de baja con espacios trae su cantidad y no duplica filas', () async {
      await local.insertar(
        ubicacion(id: 'u1', deletedAt: t0),
        espacio: espacio(id: 'e1', ubicacionId: 'u1'),
      );
      await espacioSuelto('e2', 'u1');

      final lista = await local
          .observarListaDelColportor(colportorId: 'col-1', incluirBajas: true)
          .first;
      expect(lista, hasLength(1));
      expect(lista.single.cantidadEspacios, 2);
      expect(lista.single.ubicacion.estaBorrada, isTrue);
    });

    test('es reactivo: un espacio nuevo, una baja y una reactivación vuelven a emitir', () async {
      await local.insertar(
        ubicacion(id: 'u1'),
        espacio: espacio(id: 'e1', ubicacionId: 'u1'),
      );
      final emisiones = <Map<String, int>>[];
      final sub = local
          .observarListaDelColportor(colportorId: 'col-1')
          .listen((l) => emisiones.add({for (final f in l) f.ubicacion.id: f.cantidadEspacios}));
      await pumpEventQueue();
      expect(emisiones.last, {'u1': 1});

      await espacioSuelto('e2', 'u1');
      await pumpEventQueue();
      expect(emisiones.last, {'u1': 2});

      await (db.update(
        db.ubicaciones,
      )..where((u) => u.id.equals('u1'))).write(UbicacionesCompanion(deletedAt: Value(t0)));
      await pumpEventQueue();
      expect(emisiones.last, isEmpty);

      await (db.update(
        db.ubicaciones,
      )..where((u) => u.id.equals('u1'))).write(const UbicacionesCompanion(deletedAt: Value(null)));
      await pumpEventQueue();
      expect(emisiones.last, {'u1': 2});
      await sub.cancel();
    });
  });

  group('UbicacionLocalDataSourceDrift.observarMarcadoresEnArea', () {
    // Alrededor de (-34.891, -56.125): el helper `ubicacion` fija la latitud base y la longitud.
    const area = AreaMapa(sur: -34.9, oeste: -56.2, norte: -34.88, este: -56.1);

    Future<List<String>> ids([AreaMapa a = area]) async => [
      for (final mk in await local.observarMarcadoresEnArea(colportorId: 'col-1', area: a).first)
        mk.ubicacionId,
    ]..sort();

    test(
      'trae solo las activas del colportor dentro del área, con su calle, número y tipo',
      () async {
        await local.insertar(ubicacion(id: 'adentro'));
        await local.insertar(ubicacion(id: 'baja', lon: -56.13, deletedAt: t0));
        await local.insertar(ubicacion(id: 'afuera-lon', lon: -56.0));
        await local.insertar(ubicacion(id: 'afuera-lat', metrosAlNorte: 5000, lon: -56.14));
        await local.insertar(
          UbicacionModel(
            id: 'ajena',
            tipo: TipoUbicacion.negocio,
            lat: -34.891,
            lon: -56.15,
            ciudadId: 'mvd',
            auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-2'),
          ),
        );

        expect(await ids(), ['adentro']);
        final marcador =
            (await local.observarMarcadoresEnArea(colportorId: 'col-1', area: area).first).single;
        expect(marcador.calle, 'Av. Italia');
        expect(marcador.numero, '1234');
        expect(marcador.tipo, TipoUbicacion.casa);
        expect(marcador.cantidadEspacios, 0);
      },
    );

    test('cuenta los espacios sin baja de cada ubicación', () async {
      await local.insertar(
        ubicacion(id: 'u1'),
        espacio: espacio(id: 'e1', ubicacionId: 'u1'),
      );
      await local.insertar(ubicacion(id: 'u2', lon: -56.13));
      await db
          .into(db.espacios)
          .insert(
            EspaciosCompanion.insert(id: 'e2', ubicacionId: 'u1', createdAt: t0, updatedAt: t0),
          );
      await db
          .into(db.espacios)
          .insert(
            EspaciosCompanion.insert(
              id: 'e3-baja',
              ubicacionId: 'u1',
              createdAt: t0,
              updatedAt: t0,
              deletedAt: Value(t0),
            ),
          );

      final porId = {
        for (final mk
            in await local.observarMarcadoresEnArea(colportorId: 'col-1', area: area).first)
          mk.ubicacionId: mk.cantidadEspacios,
      };
      expect(porId, {'u1': 2, 'u2': 0});
    });

    test('un área que cruza el antimeridiano y una no válida', () async {
      await local.insertar(ubicacion(id: 'a', lon: 179.5));
      await local.insertar(ubicacion(id: 'b', lon: -179.5));
      await local.insertar(ubicacion(id: 'c', lon: 0));
      const cruza = AreaMapa(sur: -35, oeste: 179, norte: -34, este: -179);
      expect(await ids(cruza), ['a', 'b']);
      const invalida = AreaMapa(sur: 10, oeste: 0, norte: -10, este: 1);
      expect(await ids(invalida), isEmpty);
    });

    test('en el antimeridiano, el OR de longitud respeta baja, dueño y latitud', () async {
      await local.insertar(ubicacion(id: 'viva', lon: 179.5));
      await local.insertar(ubicacion(id: 'baja', lon: 179.5, deletedAt: t0));
      await local.insertar(ubicacion(id: 'fuera-de-lat', lon: 179.5, metrosAlNorte: 200000));
      final ajena = ubicacion(id: 'ajena', lon: 179.5);
      await local.insertar(
        UbicacionModel(
          id: ajena.id,
          tipo: ajena.tipo,
          calle: ajena.calle,
          numero: ajena.numero,
          lat: ajena.lat,
          lon: ajena.lon,
          ciudadId: ajena.ciudadId,
          auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-2'),
        ),
      );
      const cruza = AreaMapa(sur: -35, oeste: 179, norte: -34, este: -179);
      expect(await ids(cruza), ['viva']);
    });

    test('es reactivo: un alta, una baja y un espacio nuevo vuelven a emitir', () async {
      final emisiones = <List<({String id, int espacios})>>[];
      final sub = local
          .observarMarcadoresEnArea(colportorId: 'col-1', area: area)
          .listen(
            (l) => emisiones.add([
              for (final mk in l) (id: mk.ubicacionId, espacios: mk.cantidadEspacios),
            ]),
          );
      await pumpEventQueue();
      expect(emisiones.last, isEmpty);

      await local.insertar(ubicacion(id: 'nueva'));
      await pumpEventQueue();
      expect(emisiones.last, [(id: 'nueva', espacios: 0)]);

      await db
          .into(db.espacios)
          .insert(
            EspaciosCompanion.insert(id: 'e', ubicacionId: 'nueva', createdAt: t0, updatedAt: t0),
          );
      await pumpEventQueue();
      expect(emisiones.last, [(id: 'nueva', espacios: 1)]);

      await (db.update(
        db.ubicaciones,
      )..where((u) => u.id.equals('nueva'))).write(UbicacionesCompanion(deletedAt: Value(t0)));
      await pumpEventQueue();
      expect(emisiones.last, isEmpty);
      await sub.cancel();
    });
  });
}
