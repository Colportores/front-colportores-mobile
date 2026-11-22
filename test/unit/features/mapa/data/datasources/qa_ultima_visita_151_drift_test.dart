// QA de la última visita de un espacio (vista 11·04, HU-VIS-005, #151, PR #574) contra la tabla real
// `visita`: los bordes que el PR no prueba (visitas de una
// persona dada de baja, un depto que se mira mientras otro cambia, muchas visitas).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ultima_visita_del_espacio_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ultima_visita_del_espacio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late UltimaVisitaDelEspacioDrift lector;

  Visita visita(
    String id, {
    required DateTime fecha,
    TipoResultadoVisita resultado = TipoResultadoVisita.entrevista,
    String espacioId = 'esp-1',
    String? vinculo,
  }) => Visita(
    id: id,
    espacioId: espacioId,
    espacioPersonaId: vinculo,
    fecha: fecha,
    tipoResultado: resultado,
    colportorId: 'col-1',
    auditoria: auditoriaDe(creada: fecha),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    lector = UltimaVisitaDelEspacioDrift(db);
    await sembrarEdificio(db);
  });
  tearDown(() => db.close());

  test('dado que una persona del depto se dio de baja, cuando se lee, sus visitas siguen contando '
      '(del teléfono no se borra nada)', () async {
    await insertarVisita(db, visita('v-1', fecha: DateTime.utc(2026, 9, 20), vinculo: 'ep-1'));
    await db.customStatement(
      "UPDATE espacio_persona SET deleted_at = '2026-10-01T00:00:00Z' WHERE id = 'ep-1'",
    );
    final ultima = await lector.observar('esp-1').first;
    expect(ultima?.resultado, TipoResultadoVisita.entrevista);
  });

  test('dado un depto que se mira, cuando se registra una visita en OTRO depto del edificio, el '
      'stream no emite de más ni cambia el estado', () async {
    await insertarVisita(db, visita('v-1', fecha: DateTime.utc(2026, 9, 20)));
    final eventos = <UltimaVisitaDelEspacio?>[];
    final sub = lector.observar('esp-1').listen(eventos.add);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await insertarVisita(
      db,
      visita(
        'v-2',
        fecha: DateTime.utc(2026, 9, 25),
        espacioId: 'esp-2',
        resultado: TipoResultadoVisita.venta,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(eventos.last?.resultado, TipoResultadoVisita.entrevista);
    expect(eventos.every((e) => e?.resultado == TipoResultadoVisita.entrevista), isTrue);
    await sub.cancel();
  });

  test('dado 500 visitas del depto, cuando se lee, sale la más reciente sin recorrerlas', () async {
    for (var i = 0; i < 500; i++) {
      await insertarVisita(
        db,
        visita(
          'v-$i',
          fecha: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
          resultado: i == 499 ? TipoResultadoVisita.cobranza : TipoResultadoVisita.noContesto,
        ),
      );
    }
    final ultima = await lector.observar('esp-1').first;
    expect(ultima?.resultado, TipoResultadoVisita.cobranza);
  });

  test('dado un espacio que no existe, cuando se lee, no hay última (sin error)', () async {
    expect(await lector.observar('no-existe').first, isNull);
  });
}
