// Los escenarios de HU-UBI-007 con personas que se cierran con HU-UBI-008 (#140), de punta a punta
// sobre la DB real en memoria: una persona creada con el alta de verdad, y la baja del depto que la
// tiene, con `PersonaLocalDataSourceDrift` como el `ContadorPersonasEspacio` de producción.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/espacio_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/persona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_baja_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/dar_de_baja_espacio_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/registrar_persona_use_case.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 13);
  late AppDatabase db;
  late UbicacionLocalDataSourceDrift ubicaciones;
  late PersonaLocalDataSourceDrift personasLocal;
  late RegistrarPersonaUseCase registrar;
  late DarDeBajaEspacioUseCase darDeBaja;
  var contador = 0;

  Auditoria auditoria() => Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1');

  Future<void> sembrar({required List<String> espacios}) async {
    await ubicaciones.insertar(
      UbicacionModel(
        id: 'ub-1',
        tipo: TipoUbicacion.edificio,
        calle: 'Mataojo',
        numero: '2044',
        lat: -34.89,
        lon: -56.16,
        ciudadId: 'mvd',
        auditoria: auditoria(),
      ),
    );
    for (final id in espacios) {
      await ubicaciones.insertarEspacio(
        EspacioModel(id: id, ubicacionId: 'ub-1', numeroDepto: id, auditoria: auditoria()),
      );
    }
  }

  Future<void> altaEn(String espacioId, String nombre) async {
    final resultado = await registrar(
      RegistrarPersonaParams(
        ids: registrar.nuevosIds(),
        espacioId: espacioId,
        colportorId: 'col-1',
        nombre: nombre,
        nota: 'primera nota',
      ),
    );
    expect(resultado.isRight(), isTrue);
  }

  setUp(() {
    contador = 0;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    final encolador = EncoladorSyncEnMemoria();
    ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    personasLocal = PersonaLocalDataSourceDrift(db, encolador: encolador);
    registrar = RegistrarPersonaUseCase(
      PersonaRepositoryImpl(personasLocal, logger: loggerMudo()),
      generarId: () => 'id-${++contador}',
      ahora: () => t0,
    );
    darDeBaja = DarDeBajaEspacioUseCase(
      EspacioRepositoryImpl(ubicaciones, logger: loggerMudo()),
      personasLocal,
      ahora: () => t0.add(const Duration(days: 1)),
    );
  });

  tearDown(() => db.close());

  test('dado un depto con una persona creada desde el alta y otro depto activo, cuando se da de '
      'baja sin confirmar, pide confirmación y cuenta a la persona', () async {
    await sembrar(espacios: ['101', '102']);
    await altaEn('101', 'Ana');

    final r = await darDeBaja(const DarDeBajaEspacioParams(id: '101'));

    expect(r.getOrElse(() => throw StateError('falló')), isA<BajaRequiereConfirmacion>());
    expect((r.getOrElse(() => throw StateError('falló')) as BajaRequiereConfirmacion).personas, 1);
  });

  test('dado que confirma, cuando se da de baja el depto, la persona sigue en el teléfono y se '
      'puede leer', () async {
    await sembrar(espacios: ['101', '102']);
    await altaEn('101', 'Ana');

    final r = await darDeBaja(const DarDeBajaEspacioParams(id: '101', confirmaConPersonas: true));

    expect(r.getOrElse(() => throw StateError('falló')), isA<BajaRealizada>());
    final filas = (await db.customSelect('SELECT nombre FROM persona').get()).map(
      (f) => f.read<String>('nombre'),
    );
    expect(filas, ['Ana']);
    final lista = await personasLocal.observarDelEspacio('101').first;
    expect(lista.map((c) => c.persona.nombre), ['Ana']);
  });

  test(
    'dado el único espacio activo con una persona, cuando se intenta dar de baja, no se puede',
    () async {
      await sembrar(espacios: ['101']);
      await altaEn('101', 'Ana');

      final r = await darDeBaja(const DarDeBajaEspacioParams(id: '101', confirmaConPersonas: true));

      expect(r.fold((f) => f, (_) => null), isA<FailureUltimoEspacioConPersonas>());
    },
  );

  test('dado un depto dado de baja, cuando se intenta agregar una persona, el alta se rechaza y '
      'no queda nada', () async {
    await sembrar(espacios: ['101', '102']);
    await darDeBaja(const DarDeBajaEspacioParams(id: '101'));

    final r = await registrar(
      RegistrarPersonaParams(
        ids: registrar.nuevosIds(),
        espacioId: '101',
        colportorId: 'col-1',
        nombre: 'Ana',
      ),
    );

    final falla = r.fold((f) => f, (_) => null);
    expect(falla, isA<FailureValidacion>());
    expect((falla! as FailureValidacion).campos, contains('espacio'));
    expect(await personasLocal.activasEn('101'), 0);
  });

  test(
    'dado un depto sin personas, cuando se da de baja, procede sin pedir confirmación',
    () async {
      await sembrar(espacios: ['101', '102']);

      final r = await darDeBaja(const DarDeBajaEspacioParams(id: '101'));

      expect(r.getOrElse(() => throw StateError('falló')), isA<BajaRealizada>());
    },
  );
}
