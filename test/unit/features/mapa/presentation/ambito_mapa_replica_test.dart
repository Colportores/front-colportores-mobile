// Vista 06 (HU-UBI-003, #274): la ciudad del mapa se vuelve a averiguar cuando el pull escribe las
// réplicas de las campañas. Quien abre el mapa antes de que termine la primera bajada no se queda sin
// calles hasta salir y volver a la pestaña.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/campanias_del_colportor_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/zona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/zona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/ciudades_para_alta_local.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_ubicaciones_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart'
    show AmbitoTrabajo;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/lista_ubicaciones_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/replica_de_campanias.dart';

/// Una DB que ya está «abierta»: los providers solo necesitan el `AppDatabase`.
final class _DbAbierta extends DbLocalNotifier {
  _DbAbierta(this._base);

  final AppDatabase _base;

  @override
  AppDatabase? build() => _base;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;
  late ProviderContainer contenedor;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
    contenedor = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbAbierta(db)),
        ...overridesLista(
          repo: RepoListaFalso(),
          ciudades: CiudadesParaAltaLocal(
            campanias: CampaniasDelColportorLocalDataSourceDrift(db),
            zonas: ZonaRepositoryImpl(ZonaLocalDataSourceDrift(db), logger: loggerMudo()),
            ahora: () => DateTime.utc(2026, 10, 27, 15),
            logger: loggerMudo(),
          ),
        ),
      ],
    );
    addTearDown(() async {
      contenedor.dispose();
      await db.close();
    });
  });

  test('dado el mapa abierto antes de la primera bajada, cuando el pull trae la campaña y la '
      'ciudad, el ámbito pasa a ser esa ciudad sin que el colportor haga nada', () async {
    final proveedor = ambitoMapaUbicacionesProvider('col-1');
    contenedor.listen(proveedor, (_, _) {});
    await pumpEventQueue();
    expect(contenedor.read(proveedor), const AmbitoTrabajo());

    await replica.bajar({
      'ciudad': [filaCiudad('ciu-lsm', 'Libertador San Martín', lat: -32.07, lon: -60.47)],
      'campania': [filaCampania('camp-1', 'Verano 2026')],
      'campania_ciudad': [filaCampaniaCiudad('cc-1', campania: 'camp-1', ciudad: 'ciu-lsm')],
      'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
    });
    await replica.terminoUnPull();
    await pumpEventQueue();

    expect(contenedor.read(proveedor), const AmbitoTrabajo(ciudadId: 'ciu-lsm'));
  });

  test('dado la ciudad ya conocida, cuando el pull escribe otras filas y la respuesta pasa a ser '
      '«no sé», el ámbito no se pierde', () async {
    await replica.bajar({
      'ciudad': [filaCiudad('ciu-lsm', 'Libertador San Martín', lat: -32.07, lon: -60.47)],
      'campania': [filaCampania('camp-1', 'Verano 2026')],
      'campania_ciudad': [filaCampaniaCiudad('cc-1', campania: 'camp-1', ciudad: 'ciu-lsm')],
      'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
    });
    await replica.terminoUnPull();
    final proveedor = ambitoMapaUbicacionesProvider('col-1');
    contenedor.listen(proveedor, (_, _) {});
    await pumpEventQueue();
    expect(contenedor.read(proveedor), const AmbitoTrabajo(ciudadId: 'ciu-lsm'));

    // Una inscripción nueva que apunta a una campaña que todavía no bajó: la lectura dice «no sé».
    await replica.bajar({
      'campania_colportor': [filaInscripcion('insc-2', campania: 'camp-que-no-bajo')],
    });
    await pumpEventQueue();

    expect(contenedor.read(proveedor), const AmbitoTrabajo(ciudadId: 'ciu-lsm'));
  });
}
