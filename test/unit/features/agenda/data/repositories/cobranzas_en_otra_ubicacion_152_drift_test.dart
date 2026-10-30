// HU-VIS-006 (#152): el marcador de la alternativa lleva el indicador «cobranza pendiente proveniente
// de otra ubicación». Acá, el dato que lo alimenta, contra las tablas reales, y el provider del destino
// de la cobranza que sigue los cambios de la alternativa.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/cobranzas_en_otra_ubicacion_repository_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/destino_de_cobranza.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/cobranza_alternativa_providers.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase _db;

  @override
  AppDatabase? build() => _db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late CobranzasEnOtraUbicacionRepositoryDrift repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    repo = CobranzasEnOtraUbicacionRepositoryDrift(db);
    await sembrarUbicacion(db, calle: 'Mataojo', numero: '2044');
    await sembrarEspacio(db);
    await sembrarVinculo(db, ubicacionCobranzaAltId: 'ub-alt');
    await sembrarUbicacion(db, id: 'ub-alt', tipo: 'NEGOCIO', calle: 'Av. Italia', numero: '2810');
  });
  tearDown(() => db.close());

  Future<Set<String>> leer([String colportor = 'col-1']) =>
      repo.observarUbicaciones(colportorId: colportor).first;

  Future<void> cobranza(
    String id, {
    String? alternativa = 'ub-alt',
    EstadoAgenda estado = EstadoAgenda.programada,
    TipoAgenda tipo = TipoAgenda.cobranza,
    String espacio = 'esp-1',
    DateTime? borrada,
  }) => insertarAgenda(
    db,
    agendaDe(
      id,
      tipo: tipo,
      estado: estado,
      espacio: espacio,
      ubicacionAlt: alternativa,
      borrada: borrada,
    ),
  );

  group('ubicaciones con una cobranza que viene de otra', () {
    test('dada una cobranza programada en la alternativa, entonces la marca', () async {
      await cobranza('age-1');

      expect(await leer(), {'ub-alt'});
    });

    test(
      'dadas varias cobranzas hacia la misma alternativa, entonces aparece una sola vez',
      () async {
        await cobranza('age-1');
        await cobranza('age-2');

        expect(await leer(), {'ub-alt'});
      },
    );

    test('dada una cobranza que se cobra en la ubicación del propio espacio, entonces no cuenta '
        '(no viene de otra)', () async {
      await cobranza('age-1', alternativa: 'ub-1');

      expect(await leer(), isEmpty);
    });

    test('dada una cobranza sin alternativa, una entrevista o una cobranza cerrada, cancelada o '
        'dada de baja, entonces no marca nada', () async {
      await cobranza('age-1', alternativa: null);
      await cobranza('age-2', tipo: TipoAgenda.entrevista);
      await cobranza('age-3', estado: EstadoAgenda.cumplida);
      await cobranza('age-4', estado: EstadoAgenda.cancelada);
      await cobranza('age-5', estado: EstadoAgenda.noCumplida);
      await cobranza('age-6', borrada: t0);

      expect(await leer(), isEmpty);
    });

    test('dada la cobranza de otro colportor, entonces no se mezcla con la mía', () async {
      await cobranza('age-1');

      expect(await leer('col-2'), isEmpty);
    });

    test(
      'dada una cobranza cuyo espacio todavía no llegó, entonces igual marca la alternativa',
      () async {
        await cobranza('age-1', espacio: 'esp-que-no-llego');

        expect(await leer(), {'ub-alt'});
      },
    );

    test(
      'al agendar, cumplir y volver a agendar, el marcador sigue los cambios (reactivo)',
      () async {
        final emitidos = <Set<String>>[];
        final sub = repo.observarUbicaciones(colportorId: 'col-1').listen(emitidos.add);
        addTearDown(sub.cancel);
        await _hasta(() => emitidos.isNotEmpty);
        expect(emitidos.last, isEmpty);

        await cobranza('age-1');
        await _hasta(() => emitidos.last.isNotEmpty);
        expect(emitidos.last, {'ub-alt'});

        await (db.update(db.agendas)..where((a) => a.id.equals('age-1'))).write(
          AgendasCompanion(estado: Value(EstadoAgenda.cumplida.codigo)),
        );
        await _hasta(() => emitidos.last.isEmpty);

        await cobranza('age-2');
        await _hasta(() => emitidos.last.isNotEmpty);
        expect(emitidos.last, {'ub-alt'});
      },
    );
  });

  group('destinoDeCobranzaProvider', () {
    ProviderContainer armar() {
      final c = ProviderContainer(
        overrides: [
          dbLocalProvider.overrideWith(() => _DbFija(db)),
          encoladorSyncProvider.overrideWithValue(EncoladorSyncEnMemoria()),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('sigue a la alternativa: vigente, dada de baja, y de nuevo sin ninguna', () async {
      final c = armar();
      const clave = (personaId: 'per-1', espacioId: 'esp-1');
      final destinos = <DestinoDeCobranza>[];
      c.listen(destinoDeCobranzaProvider(clave), (_, siguiente) {
        final valor = siguiente.value;
        if (valor != null) destinos.add(valor);
      }, fireImmediately: true);

      await _hasta(() => destinos.isNotEmpty);
      expect(destinos.last, isA<CobranzaEnLaAlternativa>());
      expect(destinos.last.ubicacionAltId, 'ub-alt');
      expect(destinos.last.direccionDelAviso, 'Av. Italia 2810');

      await (db.update(
        db.ubicaciones,
      )..where((u) => u.id.equals('ub-alt'))).write(UbicacionesCompanion(deletedAt: Value(t0)));
      await _hasta(() => destinos.last.advierteQueNoSirve);

      await (db.update(db.espacioPersonas)..where((v) => v.id.equals('ep-1'))).write(
        const EspacioPersonasCompanion(ubicacionCobranzaAltId: Value(null)),
      );
      await _hasta(() => destinos.last is CobranzaEnLaUbicacionDelEspacio);
    });

    test('ubicacionesConCobranzaDeOtraProvider entrega los ids de la DB abierta', () async {
      await cobranza('age-1');
      final c = armar();
      c.listen(ubicacionesConCobranzaDeOtraProvider('col-1'), (_, _) {});

      expect(await c.read(ubicacionesConCobranzaDeOtraProvider('col-1').future), {'ub-alt'});
    });
  });
}

Future<void> _hasta(bool Function() condicion) async {
  for (var i = 0; i < 200 && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condicion(), isTrue);
}
