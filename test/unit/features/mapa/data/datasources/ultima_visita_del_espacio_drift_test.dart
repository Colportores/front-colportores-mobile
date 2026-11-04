// La última visita de un espacio (vista 11·04, «✓ Entrevista hecha · 20/09»; HU-VIS-005, #151) contra
// la tabla real `visita`: AppDatabase en memoria.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ultima_visita_del_espacio_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ultima_visita_del_espacio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
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
    DateTime? borrada,
  }) => Visita(
    id: id,
    espacioId: espacioId,
    fecha: fecha,
    tipoResultado: resultado,
    colportorId: 'col-1',
    auditoria: auditoriaDe(creada: fecha, borrada: borrada),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    lector = UltimaVisitaDelEspacioDrift(db);
    await sembrarEdificio(db);
  });
  tearDown(() => db.close());

  test(
    'dado un depto sin visitas, cuando se lee, no hay última: no se inventa un estado',
    () async {
      expect(await lector.observar('esp-1').first, isNull);
    },
  );

  test(
    'dado varias visitas, cuando se lee, es la de fecha más reciente y no la última guardada',
    () async {
      await insertarVisita(db, visita('v1', fecha: DateTime.utc(2026, 9, 20, 15)));
      await insertarVisita(
        db,
        visita('v3', fecha: DateTime.utc(2026, 9, 1, 15), resultado: TipoResultadoVisita.rechazo),
      );
      await insertarVisita(
        db,
        visita(
          'v2',
          fecha: DateTime.utc(2026, 9, 10, 15),
          resultado: TipoResultadoVisita.noContesto,
        ),
      );

      expect(
        await lector.observar('esp-1').first,
        UltimaVisitaDelEspacio(
          resultado: TipoResultadoVisita.entrevista,
          fecha: DateTime.utc(2026, 9, 20, 15),
        ),
      );
    },
  );

  test('dado una visita dada de baja, cuando se lee, no cuenta: vale la anterior', () async {
    await insertarVisita(
      db,
      visita('v1', fecha: DateTime.utc(2026, 9, 10, 15), resultado: TipoResultadoVisita.noContesto),
    );
    await insertarVisita(
      db,
      visita('v2', fecha: DateTime.utc(2026, 9, 20, 15), borrada: DateTime.utc(2026, 9, 20, 15, 1)),
    );

    final ultima = await lector.observar('esp-1').first;
    expect(ultima?.resultado, TipoResultadoVisita.noContesto);
  });

  test('dado visitas de otro depto del mismo edificio, cuando se lee, no se mezclan', () async {
    await insertarVisita(
      db,
      visita(
        'v1',
        fecha: DateTime.utc(2026, 9, 20, 15),
        resultado: TipoResultadoVisita.rechazo,
        espacioId: 'esp-2',
      ),
    );

    expect(await lector.observar('esp-1').first, isNull);
    expect((await lector.observar('esp-2').first)?.resultado, TipoResultadoVisita.rechazo);
  });

  test('dado dos visitas en el mismo instante, cuando se lee, siempre sale la misma', () async {
    final mismoInstante = DateTime.utc(2026, 9, 20, 15);
    await insertarVisita(db, visita('v-a', fecha: mismoInstante));
    await insertarVisita(
      db,
      visita('v-b', fecha: mismoInstante, resultado: TipoResultadoVisita.venta),
    );

    final primera = await lector.observar('esp-1').first;
    final segunda = await lector.observar('esp-1').first;
    expect(primera, segunda);
    expect(primera?.resultado, TipoResultadoVisita.venta, reason: 'a igual fecha, el id mayor');
  });

  test('dado un depto que se mira, cuando se registra una visita y se la deshace, el stream emite '
      'cada cambio', () async {
    final vistas = <UltimaVisitaDelEspacio?>[];
    final alStream = lector.observar('esp-1').listen(vistas.add);
    addTearDown(alStream.cancel);
    await pumpEventQueue();
    expect(vistas, [null]);

    await insertarVisita(
      db,
      visita('v1', fecha: DateTime.utc(2026, 9, 20, 15), resultado: TipoResultadoVisita.noContesto),
    );
    await pumpEventQueue();
    expect(vistas.last?.resultado, TipoResultadoVisita.noContesto);

    await (db.update(db.visitas)..where((v) => v.id.equals('v1'))).write(
      VisitasCompanion(deletedAt: Value(DateTime.utc(2026, 9, 20, 16))),
    );
    await pumpEventQueue();
    expect(vistas.last, isNull);
  });
}
