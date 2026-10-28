// QA de #274 / PR #548 (vista 36 «Aviso de zona»): el aviso armado con el adaptador real
// (`InscripcionesConZonaLocal` sobre la base en memoria) y los datos de la demo del 31/10.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/auth/data/datasources/inscripciones_con_zona_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/repositories/zonas_avisadas_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/aviso_zona.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/avisos_zona_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/avisos_zona_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/replica_de_campanias.dart';
import '../../../../../helpers/replica_demo_lsm_qa_548.dart';

const _campania = 'Campaña Libertador San Martín (demo)';
const _inscripcionLsm = 'dede0000-0000-7000-800b-000000000002';

const _asignadaCentro = ZonaAsignada(
  inscripcionId: _inscripcionLsm,
  campaniaNombre: _campania,
  zonaId: zonaCentroId,
  zonaNombre: 'Zona Centro',
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;
  late ZonasAvisadasEnMemoria avisadas;
  late DateTime ahora;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
    avisadas = ZonasAvisadasEnMemoria();
    ahora = DateTime.utc(2026, 10, 31, 15);
  });
  tearDown(() => db.close());

  Future<ProviderContainer> abrir() async {
    final c = ProviderContainer(
      overrides: [
        inscripcionesConZonaDataSourceProvider.overrideWith(
          (ref) => InscripcionesConZonaLocal(db, ahora: () => ahora),
        ),
        zonasAvisadasRepositoryProvider.overrideWithValue(avisadas),
      ],
    );
    addTearDown(c.dispose);
    c.listen(avisosZonaProvider(colportorDemoId), (_, _) {});
    await pumpEventQueue();
    return c;
  }

  List<AvisoZona> avisos(ProviderContainer c) => c.read(avisosZonaProvider(colportorDemoId));

  Future<void> pull(Map<String, List<Map<String, Object?>>> filas) async {
    await replica.bajar(filas);
    await replica.terminoUnPull();
    await pumpEventQueue();
  }

  Map<String, List<Map<String, Object?>>> demo({String? zona = zonaCentroId}) =>
      pullDemoLsm(usuario: colportorDemoId, inscripcion: _inscripcionLsm, zona: zona);

  test('el primer pull de la demo: «Te asignaron la zona Zona Centro en Campaña Libertador San '
      'Martín (demo)», con la app ya abierta', () async {
    final c = await abrir();
    expect(avisos(c), isEmpty);

    await pull(demo());

    expect(avisos(c), [_asignadaCentro]);
  });

  test('con la app cerrada cuando llegó el pull: el aviso está al abrirla', () async {
    await pull(demo());

    final c = await abrir();

    expect(avisos(c), [_asignadaCentro]);
  });

  test('«Entendido» lo cierra y un pull posterior con lo mismo no lo trae de vuelta', () async {
    final c = await abrir();
    await pull(demo());
    await c.read(avisosZonaProvider(colportorDemoId).notifier).cerrar(_asignadaCentro);
    expect(avisos(c), isEmpty);

    await pull({
      'ciudad': [filaCiudad(ciudadMvdId, 'Montevideo', lat: -34.9011, lon: -56.1645)],
    });
    await pull(demo());

    expect(avisos(c), isEmpty);
  });

  test(
    'el coordinador le cambia la zona (Centro a UAP) con el aviso sin cerrar: queda el último',
    () async {
      final c = await abrir();
      await pull(demo());
      await pull({
        'campania_colportor': [
          filaInscripcion(
            _inscripcionLsm,
            campania: campaniaLsmId,
            usuario: colportorDemoId,
            zona: zonaUapId,
          ),
        ],
      });

      expect(avisos(c), [
        const ZonaAsignada(
          inscripcionId: _inscripcionLsm,
          campaniaNombre: _campania,
          zonaId: zonaUapId,
          zonaNombre: 'Zona UAP',
        ),
      ]);
    },
  );

  test(
    'el coordinador le quita la zona con el aviso sin cerrar: «Ya no tenés zona en …»',
    () async {
      final c = await abrir();
      await pull(demo());
      await pull({
        'campania_colportor': [
          filaInscripcion(_inscripcionLsm, campania: campaniaLsmId, usuario: colportorDemoId),
        ],
      });

      expect(avisos(c), [
        const ZonaQuitada(inscripcionId: _inscripcionLsm, campaniaNombre: _campania),
      ]);
    },
  );

  test(
    'la inscripción de Montevideo dada de baja el mismo día (como en dev) no avisa nada',
    () async {
      final c = await abrir();
      await pull(sumarMontevideo(demo(), usuario: colportorDemoId, inscripcionDeBaja: true));

      expect(avisos(c), [_asignadaCentro]);
    },
  );

  test('una campaña que terminó ayer no avisa; la que termina hoy, sí', () async {
    final terminada = demo();
    terminada['campania'] = [
      filaCampania(campaniaLsmId, _campania, inicio: '2026-09-01', fin: '2026-10-30'),
    ];
    await pull(terminada);

    ahora = DateTime.utc(2026, 10, 31, 15);
    var c = await abrir();
    expect(avisos(c), isEmpty);

    // Con el último día a las 22:00 de Montevideo (01:00 UTC del siguiente) todavía cuenta.
    ahora = DateTime.utc(2026, 11, 1, 1);
    await pull({
      'campania': [filaCampania(campaniaLsmId, _campania, inicio: '2026-09-01', fin: '2026-10-31')],
    });
    c = await abrir();
    expect(avisos(c), [_asignadaCentro]);
  });

  test('no deja el id del colportor en el texto ni en el toString del aviso', () async {
    final c = await abrir();
    await pull(demo());

    final texto = avisos(c).single.toString();
    expect(texto, isNot(contains(colportorDemoId)));
  });
}
