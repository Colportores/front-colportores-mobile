// Dónde trabaja la colportora, leído de las réplicas locales para «Mapas offline» (HU-SYNC-010, #619):
// su zona, su ciudad y el departamento de esa ciudad, con la ciudad que resuelve el mismo
// `CiudadesParaAlta` del mapa de la vista 06 y de «Nueva ubicación».
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/campanias_del_colportor_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/lugar_de_trabajo_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/zona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/zona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/ciudades_para_alta_local.dart';
import 'package:colportores_mobile/features/mapa/data/services/fuente_lugar_de_trabajo_local.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/lugar_de_trabajo.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/replica_de_campanias.dart';

const _colportor = 'col-1';

/// «Hoy» es el 27/10/2026 al mediodía en Montevideo (15:00 UTC).
final _hoy = DateTime.utc(2026, 10, 27, 15);

/// Un acceso a la base que se rompe: el disco ilegible.
final class _LugaresQueFallan implements LugarDeTrabajoLocalDataSource {
  @override
  Future<DatosDelLugar> leer({required Set<String> zonaIds, required String ciudadId}) async =>
      throw StateError('disco roto');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
  });
  tearDown(() => db.close());

  FuenteLugarDeTrabajoLocal crear({LugarDeTrabajoLocalDataSource? lugares, String? colportor}) =>
      FuenteLugarDeTrabajoLocal(
        colportorId: colportor ?? _colportor,
        ciudades: CiudadesParaAltaLocal(
          campanias: CampaniasDelColportorLocalDataSourceDrift(db),
          zonas: ZonaRepositoryImpl(ZonaLocalDataSourceDrift(db), logger: loggerMudo()),
          ahora: () => _hoy,
          logger: loggerMudo(),
        ),
        campanias: CampaniasDelColportorLocalDataSourceDrift(db),
        lugares: lugares ?? LugarDeTrabajoLocalDataSourceDrift(db),
        ahora: () => _hoy,
        logger: loggerMudo(),
      );

  Map<String, Object?> zona(
    String id,
    String nombre,
    String campaniaCiudad, {
    bool deBaja = false,
  }) => filaZona(
    id,
    nombre,
    campaniaCiudad: campaniaCiudad,
    latSur: -34.92,
    latNorte: -34.88,
    lonOeste: -56.20,
    lonEste: -56.15,
    deBaja: deBaja,
  );

  /// El catálogo con los departamentos que carga el Admin.
  Map<String, List<Map<String, Object?>>> catalogo({
    String? deMontevideo = 'Montevideo',
    String? deCanelones = 'Canelones',
  }) => {
    'ciudad': [
      filaCiudad('ciu-mvd', 'Montevideo', lat: -34.9011, lon: -56.1645, departamento: deMontevideo),
      filaCiudad('ciu-can', 'Canelones', lat: -34.5228, lon: -56.2778, departamento: deCanelones),
    ],
  };

  /// La campaña de verano con Montevideo (zona «Centro») y, si [conCanelones], Canelones (zona «Norte»).
  Map<String, List<Map<String, Object?>>> verano({
    String? zonaAsignada,
    bool conCanelones = true,
    bool zonaDeBaja = false,
  }) => {
    'campania': [filaCampania('camp-1', 'Verano 2026')],
    'campania_ciudad': [
      filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
      if (conCanelones) filaCampaniaCiudad('cc-can', campania: 'camp-1', ciudad: 'ciu-can'),
    ],
    'zona': [
      zona('z-centro', 'Centro', 'cc-mvd', deBaja: zonaDeBaja),
      if (conCanelones) zona('z-norte', 'Norte', 'cc-can'),
    ],
    'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: zonaAsignada)],
  };

  Future<void> bajar(
    Map<String, List<Map<String, Object?>>> filas, {
    Map<String, List<Map<String, Object?>>>? ciudades,
  }) async {
    await replica.bajar({...(ciudades ?? catalogo()), ...filas});
    await replica.terminoUnPull();
  }

  Future<LugarDeTrabajo> leer([FuenteLugarDeTrabajoLocal? fuente]) async {
    final r = await (fuente ?? crear()).leer();
    return r.getOrElse(() => throw StateError('falló: $r'));
  }

  Future<void> esFalla<T extends Failure>([FuenteLugarDeTrabajoLocal? fuente]) async {
    final r = await (fuente ?? crear()).leer();
    expect(r.swap().getOrElse(() => throw StateError('debía fallar: $r')), isA<T>());
  }

  Future<void> esNoSe([FuenteLugarDeTrabajoLocal? fuente]) async {
    final r = await (fuente ?? crear()).leer();
    expect(
      r.swap().getOrElse(() => throw StateError('debía fallar: $r')),
      isA<FailureLugarDeTrabajoNoDisponible>(),
    );
  }

  group('con zona asignada', () {
    test(
      'dado una zona en Montevideo, cuando lee, ofrece su zona, su ciudad y su departamento',
      () async {
        await bajar(verano(zonaAsignada: 'z-centro'));

        final lugar = await leer();

        expect(
          lugar,
          const LugarDeTrabajo(
            ambito: AmbitoTrabajo(
              zonaId: 'z-centro',
              ciudadId: 'ciu-mvd',
              departamentoId: 'montevideo',
            ),
            zonaNombre: 'Centro',
            ciudadNombre: 'Montevideo',
          ),
        );
      },
    );

    test(
      'dado una zona en Canelones y Montevideo en la campaña, gana la ciudad de su zona',
      () async {
        // «Zona lejos» (Cristian, 03/11): siempre la de su zona, sin mirar el GPS ni el orden por nombre.
        await bajar(verano(zonaAsignada: 'z-norte'));

        final lugar = await leer();

        expect(lugar.ambito.ciudadId, 'ciu-can');
        expect(lugar.ciudadNombre, 'Canelones');
        expect(lugar.zonaNombre, 'Norte');
        expect(lugar.ambito.departamentoId, 'canelones');
      },
    );

    test('dado dos campañas, una con zona y otra sin, gana la ciudad de la zona', () async {
      final base = verano(zonaAsignada: 'z-norte');
      await bajar({
        ...base,
        'campania': [...base['campania']!, filaCampania('camp-2', 'Pascua')],
        'campania_ciudad': [
          ...base['campania_ciudad']!,
          filaCampaniaCiudad('cc-mvd-2', campania: 'camp-2', ciudad: 'ciu-mvd'),
        ],
        'campania_colportor': [
          ...base['campania_colportor']!,
          filaInscripcion('insc-2', campania: 'camp-2'),
        ],
      });

      final lugar = await leer();

      expect(lugar.ambito.ciudadId, 'ciu-can');
      expect(lugar.ambito.zonaId, 'z-norte');
    });

    test('dado dos zonas en la misma ciudad, elige la de menor id', () async {
      final base = verano(zonaAsignada: 'z-centro', conCanelones: false);
      await bajar({
        ...base,
        'campania': [...base['campania']!, filaCampania('camp-2', 'Pascua')],
        'campania_ciudad': [
          ...base['campania_ciudad']!,
          filaCampaniaCiudad('cc-mvd-2', campania: 'camp-2', ciudad: 'ciu-mvd'),
        ],
        'zona': [...base['zona']!, zona('z-a-puerto', 'Puerto', 'cc-mvd-2')],
        'campania_colportor': [
          ...base['campania_colportor']!,
          filaInscripcion('insc-2', campania: 'camp-2', zona: 'z-a-puerto'),
        ],
      });

      final lugar = await leer();

      expect(lugar.ambito.zonaId, 'z-a-puerto');
      expect(lugar.zonaNombre, 'Puerto');
    });

    test('dado su zona dada de baja, la ciudad sale igual y la zona queda sin asignar', () async {
      await bajar(verano(zonaAsignada: 'z-centro', conCanelones: false, zonaDeBaja: true));

      final lugar = await leer();

      expect(lugar.ambito.zonaId, isNull);
      expect(lugar.zonaNombre, isNull);
      expect(lugar.ambito.ciudadId, 'ciu-mvd');
    });
  });

  group('sin zona asignada', () {
    test(
      'dado una campaña con una sola ciudad, ofrece la ciudad y el departamento, sin zona',
      () async {
        await bajar(verano(conCanelones: false));

        final lugar = await leer();

        expect(lugar.ambito.zonaId, isNull);
        expect(lugar.zonaNombre, isNull);
        expect(lugar.ambito.ciudadId, 'ciu-mvd');
        expect(lugar.ambito.departamentoId, 'montevideo');
      },
    );

    test('dado varias ciudades y sin zona, dice que falta la zona: no se adivina', () async {
      await bajar(verano());

      await esFalla<FailureLugarSinZonaConVariasCiudades>();
    });

    test(
      'dado varias ciudades y su única zona dada de baja, también dice que falta la zona',
      () async {
        await bajar(verano(zonaAsignada: 'z-centro', zonaDeBaja: true));

        await esFalla<FailureLugarSinZonaConVariasCiudades>();
      },
    );

    test('dado zonas en dos ciudades, no dice que le falta la zona: tiene en más de una', () async {
      final base = verano(zonaAsignada: 'z-centro');
      await bajar({
        ...base,
        'campania': [...base['campania']!, filaCampania('camp-2', 'Pascua')],
        'campania_ciudad': [
          ...base['campania_ciudad']!,
          filaCampaniaCiudad('cc-can-2', campania: 'camp-2', ciudad: 'ciu-can'),
        ],
        'zona': [...base['zona']!, zona('z-norte-2', 'Norte 2', 'cc-can-2')],
        'campania_colportor': [
          ...base['campania_colportor']!,
          filaInscripcion('insc-2', campania: 'camp-2', zona: 'z-norte-2'),
        ],
      });

      await esFalla<FailureLugarZonasEnVariasCiudades>();
    });

    test('el texto sin zona dice la causa, qué hacer y que puede bajar Uruguay', () {
      const falla = FailureLugarSinZonaConVariasCiudades();

      expect(
        falla.mensaje,
        'Todavía no tenés zona y tu campaña tiene varias ciudades, así que no sabemos cuál bajar. '
        'Cuando la coordinación te asigne una zona, vas a poder bajar tu ciudad. Mientras tanto '
        'podés bajar el mapa de todo Uruguay.',
      );
    });

    test('dado una campaña sin ciudades, no se sabe', () async {
      await bajar({
        'campania': [filaCampania('camp-1', 'Verano 2026')],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });

      await esNoSe();
    });

    test('dado que no está inscripta en ninguna campaña, no se sabe', () async {
      await bajar(verano(conCanelones: false));

      await esNoSe(crear(colportor: 'otra-persona'));
    });
  });

  group('el departamento', () {
    test('dado un nombre con tilde y mayúsculas, el ambito_id es el normalizado', () async {
      await bajar(verano(conCanelones: false), ciudades: catalogo(deMontevideo: 'San José'));

      expect((await leer()).ambito.departamentoId, 'san jose');
    });

    test(
      'dado que la ciudad no tiene departamento cargado, no se ofrece el departamento',
      () async {
        await bajar(verano(conCanelones: false), ciudades: catalogo(deMontevideo: null));

        final lugar = await leer();

        expect(lugar.ambito.departamentoId, isNull);
        expect(lugar.ambito.ciudadId, 'ciu-mvd');
      },
    );

    test('dado un departamento en blanco, tampoco se ofrece', () async {
      await bajar(verano(conCanelones: false), ciudades: catalogo(deMontevideo: '   '));

      expect((await leer()).ambito.departamentoId, isNull);
    });
  });

  group('cuando no se puede saber', () {
    test('dado que el teléfono todavía no bajó el catálogo, no se sabe', () async {
      await esNoSe();
    });

    test('dado que un pull no terminó nunca, no se sabe aunque haya filas', () async {
      await replica.bajar({...catalogo(), ...verano(conCanelones: false)});

      await esNoSe();
    });

    test('dado que el disco se rompe al leer, no se sabe y no lanza', () async {
      await bajar(verano(zonaAsignada: 'z-centro', conCanelones: false));

      await esNoSe(crear(lugares: _LugaresQueFallan()));
    });

    test('dado que no hay sesión o base abierta, no se sabe', () async {
      await esNoSe(FuenteLugarDeTrabajoLocal.sinFuente(logger: loggerMudo()));
    });

    test(
      'dado que el catálogo llega después, la misma fuente lo sabe en la siguiente lectura',
      () async {
        final fuente = crear();
        await esNoSe(fuente);

        await bajar(verano(zonaAsignada: 'z-centro', conCanelones: false));

        expect((await leer(fuente)).ambito.zonaId, 'z-centro');
      },
    );
  });
}
