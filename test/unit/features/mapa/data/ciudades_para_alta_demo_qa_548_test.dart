// QA de #274 / PR #548: la demo del 31/10 con Libertador San Martín (y Montevideo) sobre las réplicas
// locales, con los datos tal como los baja `sync_pull` del proyecto dev (helper `replica_demo_lsm_qa_548`).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/campanias_del_colportor_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/zona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/zona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/ciudades_para_alta_local.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/tiles/data/models/catalogo_tiles_model.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart'
    show AmbitoTrabajo;
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/replica_de_campanias.dart';
import '../../../../helpers/replica_demo_lsm_qa_548.dart';

final class _Salida extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;
  late CiudadesParaAltaLocal ciudades;

  // La demo es el 31/10/2026; la campaña de Libertador San Martín termina el 31/03/2027.
  final hoy = DateTime.utc(2026, 10, 31, 15);

  CiudadesParaAltaLocal crear({AppLogger? logger}) => CiudadesParaAltaLocal(
    campanias: CampaniasDelColportorLocalDataSourceDrift(db),
    zonas: ZonaRepositoryImpl(ZonaLocalDataSourceDrift(db), logger: loggerMudo()),
    ahora: () => hoy,
    logger: logger ?? loggerMudo(),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
    ciudades = crear();
  });
  tearDown(() => db.close());

  Future<void> bajar(Map<String, List<Map<String, Object?>>> filas) async {
    await replica.bajar(filas);
    await replica.terminoUnPull();
  }

  Future<PropuestaCiudad> proponer(String colportor, {Coordenadas? punto}) async =>
      (await ciudades.proponer(
        colportorId: colportor,
        punto: punto,
      )).getOrElse(() => throw StateError('falló'));

  CiudadPropuesta lsm(OrigenPropuesta origen) => CiudadPropuesta(
    const CiudadCatalogo(id: ciudadLsmId, nombre: 'Libertador San Martín'),
    origen,
  );

  Map<String, List<Map<String, Object?>>> colportorDemo() => pullDemoLsm(
    usuario: colportorDemoId,
    inscripcion: 'dede0000-0000-7000-800b-000000000002',
    zona: zonaCentroId,
  );

  group('colportor.demo en Libertador San Martín (zona asignada: Zona Centro)', () {
    test(
      'con el GPS dentro de otra zona de la campaña (Zona UAP), la ciudad es la detectada',
      () async {
        await bajar(colportorDemo());

        expect(
          await proponer(
            colportorDemoId,
            punto: const Coordenadas(lat: lat1Uap, lon: lon1Uap),
          ),
          lsm(OrigenPropuesta.detectada),
        );
      },
    );

    test('con el GPS en Zona Centro (la suya), la ciudad es la detectada', () async {
      await bajar(colportorDemo());

      expect(
        await proponer(
          colportorDemoId,
          punto: const Coordenadas(lat: lat1Centro, lon: lon1Centro),
        ),
        lsm(OrigenPropuesta.detectada),
      );
    });

    test('sin GPS (permiso denegado), la ciudad es la de su zona asignada', () async {
      await bajar(colportorDemo());

      expect(await proponer(colportorDemoId), lsm(OrigenPropuesta.deZona));
    });

    test('con el GPS fuera de toda zona pero en el pueblo, la ciudad es la de su zona', () async {
      await bajar(colportorDemo());

      expect(
        await proponer(colportorDemoId, punto: const Coordenadas(lat: -32.0736, lon: -60.4619)),
        lsm(OrigenPropuesta.deZona),
      );
    });

    test('«Cambiar» lista solo Libertador San Martín', () async {
      await bajar(colportorDemo());

      expect(
        (await ciudades.deMiCampania(colportorDemoId)).getOrElse(() => throw StateError('falló')),
        const [CiudadCatalogo(id: ciudadLsmId, nombre: 'Libertador San Martín')],
      );
    });

    test('la campaña sin fecha de fin y la que termina hoy (31/03/2027 a las 22:00 en Montevideo) '
        'siguen contando; al día siguiente, no', () async {
      await bajar(colportorDemo());
      final ultimoDia = CiudadesParaAltaLocal(
        campanias: CampaniasDelColportorLocalDataSourceDrift(db),
        zonas: ZonaRepositoryImpl(ZonaLocalDataSourceDrift(db), logger: loggerMudo()),
        ahora: () => DateTime.utc(2027, 4, 1, 1),
        logger: loggerMudo(),
      );
      final alDiaSiguiente = CiudadesParaAltaLocal(
        campanias: CampaniasDelColportorLocalDataSourceDrift(db),
        zonas: ZonaRepositoryImpl(ZonaLocalDataSourceDrift(db), logger: loggerMudo()),
        ahora: () => DateTime.utc(2027, 4, 1, 3),
        logger: loggerMudo(),
      );

      expect((await ultimoDia.proponer(colportorId: colportorDemoId)).isRight(), isTrue);
      expect(
        await alDiaSiguiente.proponer(colportorId: colportorDemoId),
        const Right<Failure, PropuestaCiudad>(CampaniaSinCiudades()),
      );
    });
  });

  group('colportor2.demo (zona asignada: Zona UAP)', () {
    test('sin GPS, la ciudad es la de su zona; con el GPS en Zona Centro, la detectada', () async {
      await bajar(
        pullDemoLsm(
          usuario: colportor2DemoId,
          inscripcion: 'dede0000-0000-7000-800b-000000000003',
          zona: zonaUapId,
        ),
      );

      expect(await proponer(colportor2DemoId), lsm(OrigenPropuesta.deZona));
      expect(
        await proponer(
          colportor2DemoId,
          punto: const Coordenadas(lat: lat1Centro, lon: lon1Centro),
        ),
        lsm(OrigenPropuesta.detectada),
      );
    });

    test('no ve la inscripción de colportor.demo (el pull solo baja las propias)', () async {
      await bajar(colportorDemo());

      expect(
        await ciudades.proponer(colportorId: colportor2DemoId),
        const Right<Failure, PropuestaCiudad>(CampaniaSinCiudades()),
      );
    });
  });

  group('Montevideo y Libertador San Martín juntas', () {
    test('la inscripción de Montevideo dada de baja (como está hoy en dev): la ciudad sigue '
        'siendo solo Libertador San Martín', () async {
      await bajar(
        sumarMontevideo(colportorDemo(), usuario: colportorDemoId, inscripcionDeBaja: true),
      );

      expect(await proponer(colportorDemoId), lsm(OrigenPropuesta.deZona));
      expect(
        (await ciudades.deMiCampania(colportorDemoId)).getOrElse(() => throw StateError('falló')),
        const [CiudadCatalogo(id: ciudadLsmId, nombre: 'Libertador San Martín')],
      );
    });

    test('inscripta en las dos campañas y con zona solo en Libertador San Martín: «Cambiar» lista '
        'las dos, por nombre', () async {
      await bajar(sumarMontevideo(colportorDemo(), usuario: colportorDemoId));

      expect(
        (await ciudades.deMiCampania(colportorDemoId)).getOrElse(() => throw StateError('falló')),
        const [
          CiudadCatalogo(id: ciudadLsmId, nombre: 'Libertador San Martín'),
          CiudadCatalogo(id: ciudadMvdId, nombre: 'Montevideo'),
        ],
      );
    });

    test('inscripta en las dos y SIN zona en ninguna: sin punto falta el punto; con el GPS en '
        'Montevideo, Montevideo; con el GPS en el pueblo, Libertador San Martín', () async {
      final sinZona = pullDemoLsm(
        usuario: colportorDemoId,
        inscripcion: 'dede0000-0000-7000-800b-000000000002',
        zona: null,
      );
      await bajar(sumarMontevideo(sinZona, usuario: colportorDemoId));

      expect(
        await ciudades.proponer(colportorId: colportorDemoId),
        const Right<Failure, PropuestaCiudad>(FaltaElPunto()),
      );
      expect(
        await proponer(
          colportorDemoId,
          punto: const Coordenadas(lat: latMvd, lon: lonMvd),
        ),
        const CiudadPropuesta(
          CiudadCatalogo(id: ciudadMvdId, nombre: 'Montevideo'),
          OrigenPropuesta.deCampania,
        ),
      );
      expect(
        await proponer(colportorDemoId, punto: const Coordenadas(lat: -32.0736, lon: -60.4619)),
        lsm(OrigenPropuesta.deCampania),
      );
    });
  });

  group('del mapa (vista 06) al paquete del catálogo real de la demo', () {
    final base = Uri.parse(
      'https://ohdsavwpasfpapbyutrv.supabase.co/storage/v1/object/public/mapas/catalogo.json',
    );

    test('la ciudad de la réplica es el `ambito_id` del paquete «ciudad-libertador-san-martin» y '
        'no el de Montevideo', () async {
      await bajar(colportorDemo());
      final paquetes = CatalogoTilesModel.desdeJson(catalogoRealDeLaDemo, base);

      final propuesta = await proponer(colportorDemoId);
      final ambito = AmbitoTrabajo(ciudadId: (propuesta as CiudadPropuesta).ciudad.id);

      expect(paquetes.where((p) => p.cubre(ambito)).map((p) => p.id), [
        'ciudad-libertador-san-martin',
      ]);
    });

    test('con Montevideo como ciudad, el paquete es el de Montevideo', () {
      final paquetes = CatalogoTilesModel.desdeJson(catalogoRealDeLaDemo, base);

      expect(
        paquetes.where((p) => p.cubre(const AmbitoTrabajo(ciudadId: ciudadMvdId))).map((p) => p.id),
        ['ciudad-montevideo'],
      );
    });
  });

  group('privacidad', () {
    test('la falla de lectura no deja el id del colportor ni sus datos en el log', () async {
      final salida = _Salida();
      final rota = crear(logger: AppLogger(output: salida));
      await bajar(colportorDemo());
      await db.close();

      expect(
        await rota.proponer(colportorId: colportorDemoId),
        const Left<Failure, PropuestaCiudad>(FailureCiudadesNoDisponibles()),
      );
      expect(salida.lineas, isNotEmpty);
      for (final linea in salida.lineas) {
        expect(linea, isNot(contains(colportorDemoId)));
        expect(linea.toLowerCase(), isNot(contains('libertador')));
      }
    });

    test('las propuestas y las fallas no muestran el id del colportor en su toString', () {
      expect(const FailureCiudadesNoDisponibles().toString(), isNot(contains('dede0000')));
      expect(lsm(OrigenPropuesta.deZona).toString(), isNot(contains(colportorDemoId)));
    });
  });
}
