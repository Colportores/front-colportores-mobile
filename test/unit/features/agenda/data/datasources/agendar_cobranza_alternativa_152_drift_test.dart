// HU-VIS-006 (#152): agendar una cobranza en la ubicación alternativa de la persona, contra las tablas
// reales (AppDatabase en memoria, mismos CHECK y mismas transacciones que en el dispositivo).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/motivo_rechazo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late AgendaLocalDataSourceDrift local;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = AgendaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    // La casa de María (`ub-1` → `esp-1` → `ep-1`) y su trabajo, que es su alternativa de cobranza.
    await sembrarUbicacion(db, calle: 'Mataojo', numero: '2044');
    await sembrarEspacio(db);
    await sembrarVinculo(db, ubicacionCobranzaAltId: 'ub-alt');
    await sembrarUbicacion(db, id: 'ub-alt', tipo: 'NEGOCIO', calle: 'Av. Italia', numero: '2810');
  });
  tearDown(() => db.close());

  Future<List<AgendaFila>> agendas() => db.select(db.agendas).get();
  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];

  Matcher rechazaCon(MotivoRechazoAgenda motivo) =>
      throwsA(isA<AgendaRechazadaException>().having((e) => e.motivo, 'motivo', motivo));

  Future<void> cambiarAlternativaDeMaria(String? ubicacionId) =>
      (db.update(db.espacioPersonas)..where((v) => v.id.equals('ep-1'))).write(
        EspacioPersonasCompanion(ubicacionCobranzaAltId: Value(ubicacionId)),
      );

  Future<void> darDeBaja(String ubicacionId) => (db.update(
    db.ubicaciones,
  )..where((u) => u.id.equals(ubicacionId))).write(UbicacionesCompanion(deletedAt: Value(t0)));

  group('agendar una cobranza en la alternativa', () {
    test('dada la alternativa de María, cuando se agenda la cobranza, entonces la agenda lleva '
        '`ubicacion_alt_id` y sube con él', () async {
      final r = await local.agendar(
        agendaDe('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-alt'),
      );

      expect(r.yaEstaba, isFalse);
      expect((await agendas()).single.ubicacionAltId, 'ub-alt');
      expect(encolador.encolados.first.payload['ubicacion_alt_id'], 'ub-alt');
      expect(encolador.encolados.first.payload['tipo'], 'COBRANZA');
    });

    test('dada una cobranza sin alternativa, cuando se agenda, entonces no pide nada y va a la '
        'ubicación del espacio', () async {
      await cambiarAlternativaDeMaria(null);

      await local.agendar(agendaDe('age-1', tipo: TipoAgenda.cobranza));

      expect((await agendas()).single.ubicacionAltId, isNull);
    });

    test('dada una entrevista con alternativa, cuando se agenda, entonces la rechaza y no guarda '
        'ni encola nada', () async {
      await expectLater(
        local.agendar(agendaDe('age-1', ubicacionAlt: 'ub-alt')),
        rechazaCon(MotivoRechazoAgenda.alternativaSoloCobranza),
      );

      expect(await agendas(), isEmpty);
      expect(cola(), isEmpty);
    });

    test('dada una cobranza sin persona con alternativa, cuando se agenda, entonces la rechaza '
        '(la alternativa es de la persona)', () async {
      await expectLater(
        local.agendar(
          agendaDe('age-1', vinculo: null, tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-alt'),
        ),
        rechazaCon(MotivoRechazoAgenda.alternativaSinPersona),
      );

      expect(await agendas(), isEmpty);
    });

    test('dada la alternativa dada de baja, cuando se intenta agendar, entonces la advierte con '
        'el texto de la HU y no guarda nada', () async {
      await darDeBaja('ub-alt');

      await expectLater(
        local.agendar(agendaDe('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-alt')),
        rechazaCon(MotivoRechazoAgenda.alternativaInactiva),
      );

      expect(
        MotivoRechazoAgenda.alternativaInactiva.mensaje,
        'La ubicación alternativa ya no está activa. Elegí otra o actualizá.',
      );
      expect(await agendas(), isEmpty);
      expect(cola(), isEmpty);
    });

    test('dada una alternativa que no está en el teléfono, cuando se agenda, entonces no afirma '
        'que esté de baja', () async {
      await cambiarAlternativaDeMaria('ub-fantasma');

      await expectLater(
        local.agendar(agendaDe('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-fantasma')),
        rechazaCon(MotivoRechazoAgenda.alternativaFaltante),
      );
    });

    test('dada una alternativa que ya no es la de María, cuando se agenda, entonces la rechaza y '
        'al reintentar con la nueva sale bien', () async {
      await sembrarUbicacion(db, id: 'ub-otra', calle: 'Bvar. Artigas', numero: '10');
      await cambiarAlternativaDeMaria('ub-otra');

      await expectLater(
        local.agendar(agendaDe('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-alt')),
        rechazaCon(MotivoRechazoAgenda.alternativaCambio),
      );
      expect(await agendas(), isEmpty);

      await local.agendar(agendaDe('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-otra'));
      expect((await agendas()).single.ubicacionAltId, 'ub-otra');

      await cambiarAlternativaDeMaria(null);
      await expectLater(
        local.agendar(agendaDe('age-2', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-otra')),
        rechazaCon(MotivoRechazoAgenda.alternativaCambio),
      );
    });

    test('dado un doble toque, cuando llegan dos agendar con los mismos ids, entonces queda una '
        'sola agenda y la segunda devuelve la que ya estaba', () async {
      final a = agendaDe('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-alt');

      final (primera, segunda) = await (local.agendar(a), local.agendar(a)).wait;

      expect([primera.yaEstaba, segunda.yaEstaba], [false, true]);
      expect(await agendas(), hasLength(1));
      expect(cola().where((c) => c == 'agenda:insert'), hasLength(1));
    });

    test(
      'dada una falla a mitad del guardado, cuando se reintenta, entonces no quedó nada a medias '
      'y la segunda vez guarda',
      () async {
        final espia = HouseStatusUpdaterEspia()..fallarCon = StateError('se cortó');
        final conFalla = AgendaLocalDataSourceDrift(
          db,
          encolador: encolador,
          estadoDeLasCasas: espia,
        );
        final a = agendaDe('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-alt');

        await expectLater(conFalla.agendar(a), throwsStateError);
        expect(await agendas(), isEmpty);

        espia.fallarCon = null;
        final r = await conFalla.agendar(a);
        expect(r.yaEstaba, isFalse);
        expect((await agendas()).single.ubicacionAltId, 'ub-alt');
      },
    );

    test('dadas dos cobranzas seguidas de dos personas con alternativas distintas, cuando se '
        'agendan, entonces cada una conserva la suya', () async {
      await sembrarEspacio(db, id: 'esp-2', numeroDepto: '2B');
      await sembrarVinculo(
        db,
        id: 'ep-2',
        espacioId: 'esp-2',
        personaId: 'per-2',
        ubicacionCobranzaAltId: 'ub-2',
      );
      await sembrarUbicacion(db, id: 'ub-2', calle: 'Soca', numero: '1500');

      await Future.wait([
        local.agendar(agendaDe('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-alt')),
        local.agendar(
          agendaDe(
            'age-2',
            espacio: 'esp-2',
            vinculo: 'ep-2',
            tipo: TipoAgenda.cobranza,
            ubicacionAlt: 'ub-2',
          ),
        ),
      ]);

      final porId = {for (final a in await agendas()) a.id: a.ubicacionAltId};
      expect(porId, {'age-1': 'ub-alt', 'age-2': 'ub-2'});
    });

    test('dada una agenda ya guardada con la alternativa, cuando después se da de baja, entonces '
        'la agenda no se pierde ni se toca', () async {
      await local.agendar(agendaDe('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-alt'));
      encolador.encolados.clear();

      await darDeBaja('ub-alt');

      final fila = (await agendas()).single;
      expect([fila.ubicacionAltId, fila.estado, fila.deletedAt], ['ub-alt', 'PROGRAMADA', null]);
      expect(cola(), isEmpty);
    });
  });
}
