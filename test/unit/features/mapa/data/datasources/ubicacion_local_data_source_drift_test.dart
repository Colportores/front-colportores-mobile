// Test de la capa data contra las tablas reales: AppDatabase en memoria (sin cifrado — el cifrado
// se prueba en database_helper_test.dart), mismo esquema y mismas restricciones que en el
// dispositivo. Los últimos grupos recorren el alta entera (caso de uso → repositorio → Drift).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/registrar_ubicacion_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

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

    test('dado "Av. Italia 1234" activa a 15 m, cuando inserta otra con el criterio, lanza '
        'UbicacionDuplicadaException con la candidata y no escribe nada', () async {
      final existente = ubicacion(id: 'ub-existente', metrosAlNorte: 15);
      await local.insertar(existente);
      encolador.encolados.clear();

      final intento = local.insertar(ubicacion(), espacio: espacio(), duplicados: criterio);

      await expectLater(
        intento,
        throwsA(
          isA<UbicacionDuplicadaException>().having((e) => e.candidatas, 'candidatas', [existente]),
        ),
      );
      expect(await filas('ubicacion'), 1);
      expect(await filas('espacio'), 0);
      expect(encolador.encolados, isEmpty);
    });

    test('dado candidatas en el recuadro pero fuera del radio, de otra ciudad o dadas de baja, '
        'cuando inserta, no las toma como duplicadas', () async {
      await local.insertar(ubicacion(id: 'a-40m', metrosAlNorte: 40));
      await local.insertar(ubicacion(id: 'al-este', lon: -56.125 + 0.0004));
      await local.insertar(ubicacion(id: 'canelones', ciudadId: 'canelones'));
      await local.insertar(ubicacion(id: 'baja', deletedAt: t0));

      final r = await local.insertar(ubicacion(), duplicados: criterio);

      expect(r.yaEstaba, isFalse);
      expect(await filas('ubicacion'), 5);
    });

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
        ahora: () => t0,
      );
    });

    RegistrarUbicacionParams params({String? id, String? justificacion}) =>
        RegistrarUbicacionParams(
          colportorId: 'col-1',
          tipo: TipoUbicacion.casa,
          punto: PuntoCapturado.gps(
            const LecturaGps(
              coordenadas: Coordenadas(lat: -34.891, lon: -56.125),
              precisionMetros: 10,
            ),
          ),
          ciudadId: 'mvd',
          calle: 'Av. Italia',
          numero: '1234',
          id: id,
          justificacionDuplicado: justificacion,
        );

    test('Offline: sin red el alta se completa localmente y deja la ubicación y su espacio '
        'encolados para el sync', () async {
      final r = await registrar(params());

      final alta = r.getOrElse(() => throw StateError('falló')) as AltaRegistrada;
      expect(alta.espacio, isNotNull);
      expect(await filas('ubicacion'), 1);
      expect(encolador.encolados.map((c) => c.entidad), ['ubicacion', 'espacio']);
      expect(encolador.encolados.first.payload['id'], alta.ubicacion.id);
    });

    test('Detección de duplicado: la segunda alta de "Av. Italia 1234" no se crea y devuelve la '
        'candidata; con "Crear igual" se crea', () async {
      await registrar(params());

      final segunda = await registrar(params());
      final candidatas =
          (segunda.getOrElse(() => throw StateError('falló')) as AltaConDuplicados).candidatas;
      expect(candidatas.map((c) => c.id), ['id-1']);
      expect(await filas('ubicacion'), 1);

      final igual = await registrar(params(justificacion: 'Es otra casa en el mismo padrón'));
      expect(igual.getOrElse(() => throw StateError('falló')), isA<AltaRegistrada>());
      expect(await filas('ubicacion'), 2);
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
}
