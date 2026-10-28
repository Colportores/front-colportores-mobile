// Las ciudades de la campaña del colportor leídas de las réplicas locales (HU-UBI-001 y HU-UBI-003,
// #274): sin red, con las filas entrando por el mismo `DriftLocalStore` del pull de catálogos.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/campanias_del_colportor_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/zona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/zona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/ciudades_para_alta_local.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/replica_de_campanias.dart';
import '../../../../helpers/zonas_falsas.dart';

const _colportor = 'col-1';

const _montevideo = CiudadCatalogo(id: 'ciu-mvd', nombre: 'Montevideo');
const _canelones = CiudadCatalogo(id: 'ciu-can', nombre: 'Canelones');
const _maldonado = CiudadCatalogo(id: 'ciu-mal', nombre: 'Maldonado');

/// Dentro de la zona «Centro» de Montevideo.
const _enElCentro = Coordenadas(lat: -34.90, lon: -56.17);

/// Fuera de toda zona y mucho más cerca del centro de Canelones que del de Montevideo.
const _cercaDeCanelones = Coordenadas(lat: -34.55, lon: -56.27);

/// Fuera de toda zona y más cerca de Montevideo que de las otras.
const _cercaDeMontevideo = Coordenadas(lat: -34.95, lon: -56.10);

final class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

/// Una lectura que se rompe: la base local ilegible.
final class _CampaniasQueFallan implements CampaniasDelColportorLocalDataSource {
  @override
  Future<CampaniasDelColportor?> leer(String usuarioId, {required String hoy}) async =>
      throw StateError('disco roto');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;
  late _SalidaEnMemoria salida;
  late CiudadesParaAltaLocal ciudades;

  // «Hoy» es el 27/10/2026 al mediodía en Montevideo (15:00 UTC).
  final hoy = DateTime.utc(2026, 10, 27, 15);

  CiudadesParaAltaLocal crear({AppLogger? logger}) => CiudadesParaAltaLocal(
    campanias: CampaniasDelColportorLocalDataSourceDrift(db),
    zonas: ZonaRepositoryImpl(ZonaLocalDataSourceDrift(db), logger: loggerMudo()),
    ahora: () => hoy,
    logger: logger ?? AppLogger(output: salida),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
    salida = _SalidaEnMemoria();
    ciudades = crear();
  });
  tearDown(() => db.close());

  /// El catálogo: Montevideo, Canelones y Maldonado.
  Map<String, List<Map<String, Object?>>> catalogo() => {
    'ciudad': [
      filaCiudad('ciu-mvd', 'Montevideo', lat: -34.9011, lon: -56.1645),
      filaCiudad('ciu-can', 'Canelones', lat: -34.5228, lon: -56.2778),
      filaCiudad('ciu-mal', 'Maldonado', lat: -34.9, lon: -54.95),
    ],
  };

  /// La campaña de verano, en curso, con Montevideo y Canelones y la zona «Centro» en Montevideo.
  Map<String, List<Map<String, Object?>>> verano({
    String? zonaAsignada,
    bool conCanelones = true,
  }) => {
    'campania': [filaCampania('camp-1', 'Verano 2026')],
    'campania_ciudad': [
      filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
      if (conCanelones) filaCampaniaCiudad('cc-can', campania: 'camp-1', ciudad: 'ciu-can'),
    ],
    'zona': [
      filaZona(
        'z-centro',
        'Centro',
        campaniaCiudad: 'cc-mvd',
        latSur: -34.92,
        latNorte: -34.88,
        lonOeste: -56.20,
        lonEste: -56.15,
      ),
    ],
    'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: zonaAsignada)],
  };

  Future<void> bajarTodo(Map<String, List<Map<String, Object?>>> filas) async {
    await replica.bajar({...catalogo(), ...filas});
    await replica.terminoUnPull();
  }

  Future<PropuestaCiudad> proponer({Coordenadas? punto}) async {
    final r = await ciudades.proponer(colportorId: _colportor, punto: punto);
    return r.getOrElse(() => throw StateError('falló: $r'));
  }

  CiudadPropuesta propuesta(CiudadCatalogo c, OrigenPropuesta origen) => CiudadPropuesta(c, origen);

  Future<List<CiudadCatalogo>> lista() async =>
      (await ciudades.deMiCampania(_colportor)).getOrElse(() => throw StateError('falló'));

  group('la ciudad que se propone, en el orden de la decisión del 02/10', () {
    test('1. la de la zona de sus campañas que contiene el punto, aunque tenga otra zona asignada '
        'y el centro de otra ciudad quede más cerca', () async {
      await bajarTodo(verano());

      expect(await proponer(punto: _enElCentro), propuesta(_montevideo, OrigenPropuesta.detectada));
    });

    test(
      '1. con zona asignada en otra ciudad, el punto manda: gana la zona que lo contiene',
      () async {
        final mundo = verano(zonaAsignada: 'z-norte');
        mundo['zona']!.add(
          filaZona(
            'z-norte',
            'Norte',
            campaniaCiudad: 'cc-can',
            latSur: -34.60,
            latNorte: -34.50,
            lonOeste: -56.35,
            lonEste: -56.20,
          ),
        );
        await bajarTodo(mundo);

        expect(
          await proponer(punto: _enElCentro),
          propuesta(_montevideo, OrigenPropuesta.detectada),
        );
        expect(
          await proponer(punto: const Coordenadas(lat: -34.55, lon: -56.30)),
          propuesta(_canelones, OrigenPropuesta.detectada),
        );
      },
    );

    test('2. con el punto fuera de toda zona, la de su zona asignada, aunque el centro de otra '
        'ciudad quede más cerca', () async {
      await bajarTodo(verano(zonaAsignada: 'z-centro'));

      expect(
        await proponer(punto: _cercaDeCanelones),
        propuesta(_montevideo, OrigenPropuesta.deZona),
      );
    });

    test('2. sin punto, la de su zona asignada', () async {
      await bajarTodo(verano(zonaAsignada: 'z-centro'));

      expect(await proponer(), propuesta(_montevideo, OrigenPropuesta.deZona));
    });

    test('3. sin zona asignada y con una sola ciudad, esa, con o sin punto', () async {
      await bajarTodo(verano(conCanelones: false));

      expect(await proponer(), propuesta(_montevideo, OrigenPropuesta.deCampania));
      expect(
        await proponer(punto: _cercaDeCanelones),
        propuesta(_montevideo, OrigenPropuesta.deCampania),
      );
    });

    test('4. con varias ciudades y sin zona asignada, la de centro más cercano al punto', () async {
      await bajarTodo(verano());

      expect(
        await proponer(punto: _cercaDeCanelones),
        propuesta(_canelones, OrigenPropuesta.deCampania),
      );
      expect(
        await proponer(punto: _cercaDeMontevideo),
        propuesta(_montevideo, OrigenPropuesta.deCampania),
      );
    });

    test('sin punto, con varias ciudades y sin zona asignada: falta el punto', () async {
      await bajarTodo(verano());

      expect(await proponer(), const FaltaElPunto());
    });

    test(
      'la zona de una campaña en la que no está inscripto no cuenta, aunque sea de su ciudad y cubra '
      'el punto',
      () async {
        final mundo = verano();
        mundo['campania']!.add(filaCampania('camp-ajena', 'Verano de otra'));
        mundo['campania_ciudad']!.add(
          filaCampaniaCiudad('cc-mvd-ajena', campania: 'camp-ajena', ciudad: 'ciu-mvd'),
        );
        mundo['zona']!.add(
          filaZona(
            'z-ajena',
            'Ajena',
            campaniaCiudad: 'cc-mvd-ajena',
            latSur: -34.99,
            latNorte: -34.90,
            lonOeste: -56.12,
            lonEste: -56.05,
          ),
        );
        await bajarTodo(mundo);

        expect(
          await proponer(punto: _cercaDeMontevideo),
          propuesta(_montevideo, OrigenPropuesta.deCampania),
          reason: 'la zona ajena cubre el punto, pero no es de sus campañas: no «detecta»',
        );
      },
    );

    test('una zona dada de baja no detecta nada: sigue la regla siguiente', () async {
      final mundo = verano();
      mundo['zona'] = [
        filaZona(
          'z-centro',
          'Centro',
          campaniaCiudad: 'cc-mvd',
          latSur: -34.92,
          latNorte: -34.88,
          lonOeste: -56.20,
          lonEste: -56.15,
          deBaja: true,
        ),
      ];
      await bajarTodo(mundo);

      expect(
        await proponer(punto: _enElCentro),
        propuesta(_montevideo, OrigenPropuesta.deCampania),
        reason: 'sin zona viva, la más cercana',
      );
    });

    test(
      'dos zonas de ciudades distintas cubren el punto: gana la de menor id, como en el servidor',
      () async {
        final mundo = verano();
        mundo['zona'] = [
          filaZona(
            'z-b',
            'B',
            campaniaCiudad: 'cc-can',
            latSur: -34.99,
            latNorte: -34.50,
            lonOeste: -56.50,
            lonEste: -56.10,
          ),
          filaZona(
            'z-a',
            'A',
            campaniaCiudad: 'cc-mvd',
            latSur: -34.99,
            latNorte: -34.50,
            lonOeste: -56.50,
            lonEste: -56.10,
          ),
        ];
        await bajarTodo(mundo);

        expect(
          await proponer(punto: _enElCentro),
          propuesta(_montevideo, OrigenPropuesta.detectada),
        );
      },
    );

    test(
      'una zona asignada dada de baja no vale como «su zona»: con varias ciudades pide el punto',
      () async {
        final mundo = verano(zonaAsignada: 'z-centro');
        mundo['zona'] = [
          filaZona(
            'z-centro',
            'Centro',
            campaniaCiudad: 'cc-mvd',
            latSur: -34.92,
            latNorte: -34.88,
            lonOeste: -56.20,
            lonEste: -56.15,
            deBaja: true,
          ),
        ];
        await bajarTodo(mundo);

        expect(await proponer(), const FaltaElPunto());
      },
    );
  });

  group('«Cambiar»: las ciudades de su campaña', () {
    test('lista las de su campaña, por nombre, y nunca las de otra', () async {
      final mundo = verano();
      mundo['campania']!.add(filaCampania('camp-ajena', 'Verano de otra'));
      mundo['campania_ciudad']!.add(
        filaCampaniaCiudad('cc-mal-ajena', campania: 'camp-ajena', ciudad: 'ciu-mal'),
      );
      await bajarTodo(mundo);

      expect(await lista(), [_canelones, _montevideo]);
    });

    test(
      'con dos campañas que no terminaron, en curso y por empezar, junta las ciudades de las dos',
      () async {
        final mundo = verano(conCanelones: false);
        mundo['campania']!.add(
          filaCampania('camp-2', 'Invierno 2027', inicio: '2027-06-01', fin: '2027-08-31'),
        );
        mundo['campania_ciudad']!.add(
          filaCampaniaCiudad('cc-mal', campania: 'camp-2', ciudad: 'ciu-mal'),
        );
        mundo['campania_colportor']!.add(filaInscripcion('insc-2', campania: 'camp-2'));
        await bajarTodo(mundo);

        expect(await lista(), [_maldonado, _montevideo]);
      },
    );

    test('una ciudad repetida en dos campañas se lista una vez', () async {
      final mundo = verano(conCanelones: false);
      mundo['campania']!.add(
        filaCampania('camp-2', 'Invierno 2027', inicio: '2027-06-01', fin: '2027-08-31'),
      );
      mundo['campania_ciudad']!.add(
        filaCampaniaCiudad('cc-mvd-2', campania: 'camp-2', ciudad: 'ciu-mvd'),
      );
      mundo['campania_colportor']!.add(filaInscripcion('insc-2', campania: 'camp-2'));
      await bajarTodo(mundo);

      expect(await lista(), [_montevideo]);
    });

    test('no lista la ciudad dada de baja ni la que sacaron de la campaña', () async {
      final mundo = verano();
      mundo['campania_ciudad'] = [
        filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
        filaCampaniaCiudad('cc-can', campania: 'camp-1', ciudad: 'ciu-can', deBaja: true),
        filaCampaniaCiudad('cc-mal', campania: 'camp-1', ciudad: 'ciu-mal'),
      ];
      await replica.bajar({
        'ciudad': [
          filaCiudad('ciu-mvd', 'Montevideo', lat: -34.9011, lon: -56.1645),
          filaCiudad('ciu-can', 'Canelones', lat: -34.5228, lon: -56.2778),
          filaCiudad('ciu-mal', 'Maldonado', lat: -34.9, lon: -54.95, deBaja: true),
        ],
        ...mundo,
      });
      await replica.terminoUnPull();

      expect(await lista(), [_montevideo]);
    });
  });

  group('qué campañas cuentan: con inscripción viva que no terminó', () {
    test('una campaña que termina hoy sigue contando; la que terminó ayer, no', () async {
      await bajarTodo(
        verano(conCanelones: false)
          ..['campania'] = [filaCampania('camp-1', 'V', fin: '2026-10-27')],
      );
      expect(await lista(), [_montevideo]);

      await replica.bajar({
        'campania': [filaCampania('camp-1', 'V', fin: '2026-10-26')],
      });
      expect(await lista(), isEmpty);
      expect(await proponer(), const CampaniaSinCiudades());
    });

    test('una campaña sin fecha de fin sigue contando', () async {
      await bajarTodo(
        verano(conCanelones: false)..['campania'] = [filaCampania('camp-1', 'V', fin: null)],
      );

      expect(await lista(), [_montevideo]);
    });

    test('una campaña por empezar cuenta: el mapa se baja antes del primer día', () async {
      await bajarTodo(
        verano(conCanelones: false)
          ..['campania'] = [filaCampania('camp-1', 'V', inicio: '2026-12-01')],
      );

      expect(await lista(), [_montevideo]);
    });

    test('la inscripción dada de baja y la campaña dada de baja no cuentan', () async {
      await bajarTodo(
        verano(conCanelones: false)
          ..['campania_colportor'] = [filaInscripcion('insc-1', campania: 'camp-1', deBaja: true)],
      );
      expect(await lista(), isEmpty);
      expect(await proponer(), const CampaniaSinCiudades());

      await replica.bajar({
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
        'campania': [filaCampania('camp-1', 'V', deBaja: true)],
      });
      expect(await lista(), isEmpty);
    });

    test('la inscripción de otro usuario no cuenta', () async {
      await bajarTodo(
        verano(conCanelones: false)
          ..['campania_colportor'] = [
            filaInscripcion('insc-1', campania: 'camp-1', usuario: 'col-2'),
          ],
      );

      expect(await lista(), isEmpty);
    });

    test(
      'el día es el de Montevideo: a las 22:00 del último día (01:00 UTC del siguiente) sigue, y a la medianoche ya terminó',
      () async {
        await bajarTodo(
          verano(conCanelones: false)
            ..['campania'] = [filaCampania('camp-1', 'V', fin: '2026-10-27')],
        );
        CiudadesParaAltaLocal a(DateTime ahora) => CiudadesParaAltaLocal(
          campanias: CampaniasDelColportorLocalDataSourceDrift(db),
          zonas: ZonasEnMemoria(),
          ahora: () => ahora,
          logger: loggerMudo(),
        );
        Future<List<CiudadCatalogo>> alDia(DateTime ahora) async =>
            (await a(ahora).deMiCampania(_colportor)).getOrElse(() => throw StateError('falló'));

        // 22:00 del 27/10 en Montevideo = 01:00 UTC del 28/10: para el servidor en UTC ya es mañana.
        expect(await alDia(DateTime.utc(2026, 10, 28, 1)), [_montevideo]);
        // 00:00 del 28/10 en Montevideo = 03:00 UTC.
        expect(await alDia(DateTime.utc(2026, 10, 28, 3)), isEmpty);
      },
    );
  });

  group('campaña sin ciudades contra «no sé»', () {
    test(
      'se leyó y la campaña no tiene ciudades cargadas: CampaniaSinCiudades y lista vacía',
      () async {
        final mundo = verano()..['campania_ciudad'] = [];
        await bajarTodo(mundo);

        expect(await proponer(punto: _enElCentro), const CampaniaSinCiudades());
        expect(await proponer(), const CampaniaSinCiudades());
        expect(await lista(), isEmpty);
      },
    );

    test(
      'sin ningún pull terminado la réplica vacía no es «sin ciudades»: es la falla de lectura',
      () async {
        await replica.bajar({...catalogo(), ...verano()});

        expect(
          await ciudades.proponer(colportorId: _colportor, punto: _enElCentro),
          const Left<Failure, PropuestaCiudad>(FailureCiudadesNoDisponibles()),
        );
        expect(
          await ciudades.deMiCampania(_colportor),
          const Left<Failure, List<CiudadCatalogo>>(FailureCiudadesNoDisponibles()),
        );
        expect(salida.lineas.where((l) => l.contains('CIUDADES_REPLICA_SIN_BAJAR')), hasLength(2));
      },
    );

    test(
      'el teléfono recién instalado, sin nada bajado: la falla de lectura, nunca «sin ciudades»',
      () async {
        expect(
          await ciudades.proponer(colportorId: _colportor),
          const Left<Failure, PropuestaCiudad>(FailureCiudadesNoDisponibles()),
        );
      },
    );

    test('la inscripción apunta a una campaña que todavía no llegó: no se sabe', () async {
      await replica.bajar({
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });
      await replica.terminoUnPull();

      expect(
        await ciudades.deMiCampania(_colportor),
        const Left<Failure, List<CiudadCatalogo>>(FailureCiudadesNoDisponibles()),
      );
    });

    test('la campaña apunta a una ciudad que todavía no llegó: no se sabe', () async {
      await replica.bajar({
        ...verano(),
        'ciudad': [filaCiudad('ciu-mvd', 'Montevideo', lat: -34.9011, lon: -56.1645)],
      });
      await replica.terminoUnPull();

      expect(
        await ciudades.deMiCampania(_colportor),
        const Left<Failure, List<CiudadCatalogo>>(FailureCiudadesNoDisponibles()),
      );
    });

    test('sin ninguna inscripción en un teléfono que ya bajó: se leyó y no hay campaña', () async {
      await bajarTodo({
        'campania': [filaCampania('camp-1', 'V')],
      });

      expect(await proponer(), const CampaniaSinCiudades());
      expect(await lista(), isEmpty);
    });
  });

  group('la base no se puede leer', () {
    test(
      'una lectura que se rompe es la falla de lectura, con el error en el log y sin datos',
      () async {
        final rota = CiudadesParaAltaLocal(
          campanias: _CampaniasQueFallan(),
          zonas: ZonasEnMemoria(),
          logger: AppLogger(output: salida),
        );

        expect(
          await rota.proponer(colportorId: _colportor, punto: _enElCentro),
          const Left<Failure, PropuestaCiudad>(FailureCiudadesNoDisponibles()),
        );
        expect(
          await rota.deMiCampania(_colportor),
          const Left<Failure, List<CiudadCatalogo>>(FailureCiudadesNoDisponibles()),
        );
        expect(
          salida.lineas.where((l) => l.startsWith('[ERROR][MAP][CIUDADES_LEER_FAIL]')),
          hasLength(2),
        );
      },
    );

    test('con la base cerrada también: la falla de lectura', () async {
      await bajarTodo(verano());
      await db.close();

      expect(
        await ciudades.deMiCampania(_colportor),
        const Left<Failure, List<CiudadCatalogo>>(FailureCiudadesNoDisponibles()),
      );
      // tearDown vuelve a cerrar: cerrar dos veces no lanza.
    });

    test(
      'con el punto, las zonas que no se leen no se reemplazan por otra ciudad inventada',
      () async {
        await bajarTodo(verano(zonaAsignada: 'z-centro'));
        final zonas = ZonasEnMemoria()..falla = const FailureInesperado();
        final sinZonas = CiudadesParaAltaLocal(
          campanias: CampaniasDelColportorLocalDataSourceDrift(db),
          zonas: zonas,
          ahora: () => hoy,
          logger: loggerMudo(),
        );

        expect(
          await sinZonas.proponer(colportorId: _colportor, punto: _enElCentro),
          const Left<Failure, PropuestaCiudad>(FailureCiudadesNoDisponibles()),
        );
        // Sin punto no hacen falta las zonas: la de su zona asignada sigue saliendo.
        expect(
          (await sinZonas.proponer(
            colportorId: _colportor,
          )).getOrElse(() => throw StateError('falló')),
          propuesta(_montevideo, OrigenPropuesta.deZona),
        );
      },
    );

    test('sin la base abierta (no hay sesión): la falla de lectura', () async {
      final sinBase = CiudadesParaAltaLocal.sinBaseAbierta(logger: AppLogger(output: salida));

      expect(
        await sinBase.proponer(colportorId: _colportor),
        const Left<Failure, PropuestaCiudad>(FailureCiudadesNoDisponibles()),
      );
      expect(
        await sinBase.deMiCampania(_colportor),
        const Left<Failure, List<CiudadCatalogo>>(FailureCiudadesNoDisponibles()),
      );
      expect(salida.lineas.where((l) => l.contains('CIUDADES_SIN_BASE')), hasLength(2));
    });

    test('la falla de lectura dice qué pasa y qué hacer', () {
      expect(const FailureCiudadesNoDisponibles().mensaje, contains('Probá de nuevo'));
    });
  });

  group('un pull que llega después', () {
    test(
      'la propuesta y la lista siguen a la réplica: lo que baja el pull se ve sin reiniciar',
      () async {
        await bajarTodo(verano(conCanelones: false));
        expect(await lista(), [_montevideo]);

        await replica.bajar({
          'campania_ciudad': [filaCampaniaCiudad('cc-can', campania: 'camp-1', ciudad: 'ciu-can')],
        });

        expect(await lista(), [_canelones, _montevideo]);
        expect(await proponer(), const FaltaElPunto());
      },
    );
  });
}
