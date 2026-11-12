// El cableado de la ubicación alternativa de cobranza (HU-UBI-013): sin DB abierta lanza, con DB
// escribe en ella, encola por el encolador que cablea `encoladorSyncProvider` y las lecturas siguen
// los cambios.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/ubicacion_alternativa_use_cases.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_alternativa_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';

/// La DB «abierta» sin cifrado ni helper: los providers solo necesitan el `AppDatabase`.
class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final t0 = DateTime.utc(2026, 10, 22, 13);
  final ahora = DateTime.utc(2026, 10, 26, 9);
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;

  Auditoria auditoria() => Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1');

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
  });
  tearDown(() => db.close());

  ProviderContainer armar({bool conDb = true}) {
    final c = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(conDb ? db : null)),
        encoladorSyncProvider.overrideWithValue(encolador),
        relojPersonaProvider.overrideWithValue(() => ahora),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> sembrar() async {
    final ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    for (final (id, tipo) in [('ub-1', TipoUbicacion.edificio), ('ub-2', TipoUbicacion.negocio)]) {
      await ubicaciones.insertar(
        UbicacionModel(
          id: id,
          tipo: tipo,
          calle: 'Calle $id',
          lat: -34.89,
          lon: -56.16,
          ciudadId: 'mvd',
          auditoria: auditoria(),
        ),
      );
    }
    await ubicaciones.insertarEspacio(
      EspacioModel(id: 'esp-1', ubicacionId: 'ub-1', auditoria: auditoria()),
    );
    await PersonaLocalDataSourceDrift(db, encolador: encolador).registrar(
      persona: Persona(id: 'per-1', nombre: 'Ana', apellido: 'Martínez', auditoria: auditoria()),
      vinculo: EspacioPersona(
        id: 'ep-1',
        espacioId: 'esp-1',
        personaId: 'per-1',
        auditoria: auditoria(),
      ),
    );
    encolador.encolados.clear();
  }

  test('sin la DB abierta, el repositorio de la ubicación alternativa lanza', () {
    final c = armar(conDb: false);

    expect(
      () => c.read(ubicacionAlternativaRepositoryProvider),
      throwsA(isA<ProviderException>().having((e) => e.exception, 'exception', isA<StateError>())),
    );
  });

  test('con la DB abierta, establecer guarda con el reloj del provider, encola y las lecturas lo '
      'siguen; quitar lo deshace', () async {
    await sembrar();
    final c = armar();
    const clave = (personaId: 'per-1', espacioId: 'esp-1');
    const candidatas = (colportorId: 'col-1', espacioId: 'esp-1');
    final estados = <EstadoUbicacionAlternativa>[];
    c.listen(ubicacionAlternativaProvider(clave), (_, siguiente) {
      final valor = siguiente.value;
      if (valor != null) estados.add(valor);
    }, fireImmediately: true);

    // Un provider que se libera solo necesita a alguien que lo escuche mientras se espera su valor.
    c.listen(candidatasAlternativaProvider(candidatas), (_, _) {});
    final elegibles = await c.read(candidatasAlternativaProvider(candidatas).future);
    expect(elegibles.map((u) => u.id), ['ub-2']);

    final r = await c.read(establecerUbicacionAlternativaUseCaseProvider)(
      const EstablecerUbicacionAlternativaParams(
        personaId: 'per-1',
        espacioId: 'esp-1',
        ubicacionId: 'ub-2',
        colportorId: 'col-1',
      ),
    );

    expect(r.isRight(), isTrue);
    expect(encolador.encolados.single.payload['ubicacion_cobranza_alt_id'], 'ub-2');
    expect(encolador.encolados.single.payload['updated_at'], ahora.toIso8601String());
    await _hasta(() => estados.any((e) => e is UbicacionAlternativaVigente));
    expect(estados.last.sugerida?.id, 'ub-2');

    final q = await c.read(quitarUbicacionAlternativaUseCaseProvider)(
      const QuitarUbicacionAlternativaParams(personaId: 'per-1', espacioId: 'esp-1'),
    );

    expect(q.isRight(), isTrue);
    await _hasta(() => estados.last is SinUbicacionAlternativa && estados.length >= 3);
    expect(encolador.encolados.last.payload['ubicacion_cobranza_alt_id'], isNull);
  });
}

Future<void> _hasta(bool Function() condicion) async {
  for (var i = 0; i < 200 && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condicion(), isTrue);
}
