// QA de #539 / PR #623 (tanda 2 de tests saltados: notificaciones y recordatorios), parte sin
// pantalla: la marca de conciliación en el futuro (tolerancia del reloj, borde exacto, dos revisiones
// seguidas, guardado que falla, log sin dirección) y «Borrar todas» por ids contra la tabla real
// (vacío, ids que no existen, bordes de los lotes de 500, ids con caracteres especiales).
//
// Los tests con hallazgo corren con `--dart-define=QA_HALLAZGOS=true`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/agendas_para_recordar_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/historial_notificaciones_local_data_source_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/historial_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/marca_conciliacion_recordatorios_impl.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/conciliar_recordatorios_use_case.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/historial_notificaciones_use_cases.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../helpers/campo_falsos.dart';

const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late MemoryOutput salidaDeLogs;
  late AppLogger logger;
  late MarcaConciliacionRecordatoriosEnMemoria marca;
  late DateTime ahora;
  late ConciliarRecordatoriosUseCase conciliar;
  late HistorialNotificacionesRepositoryImpl historial;
  late HistorialNotificacionesLocalDataSourceDrift local;

  final creada = DateTime.utc(2026, 10, 1, 9);

  Future<void> agenda(String id, DateTime visita) => insertarAgenda(
    db,
    Agenda(
      id: id,
      espacioId: 'esp-1',
      espacioPersonaId: 'ep-1',
      tipo: TipoAgenda.entrevista,
      fechaProgramada: visita,
      colportorId: 'col-1',
      auditoria: auditoriaDe(creada: creada),
    ),
  );

  Future<int> filas() async => (await db.select(db.notificacionesHistorial).get()).length;

  Notificacion nota(String id, int segundos) => Notificacion(
    id: id,
    tipo: TipoNotificacion.recordatorioVisita,
    titulo: 'Entrevista a las 15:00',
    detalle: 'Av. Italia 1234',
    destino: DestinoAgenda('ag-$id'),
    recibidaEn: ahora.subtract(Duration(seconds: segundos)),
  );

  Future<void> sembrar(int n, {String prefijo = 'n'}) async {
    for (var i = 0; i < n; i++) {
      await historial.registrar(nota('$prefijo-$i', i), ahora: ahora);
    }
  }

  setUp(() async {
    db = AppDatabase(
      NativeDatabase.memory(),
      logger: AppLogger(logger: Logger(level: Level.off)),
    );
    salidaDeLogs = MemoryOutput();
    logger = AppLogger(output: salidaDeLogs);
    local = HistorialNotificacionesLocalDataSourceDrift(db);
    historial = HistorialNotificacionesRepositoryImpl(local, logger: logger);
    marca = MarcaConciliacionRecordatoriosEnMemoria(DateTime.utc(2026, 10, 27, 12));
    ahora = DateTime.utc(2026, 10, 27, 15, 10);
    conciliar = ConciliarRecordatoriosUseCase(
      AgendasParaRecordarDrift(db),
      PreferenciasRecordatoriosRepositoryEnMemoria(),
      marca,
      RegistrarNotificacionUseCase(historial, ahora: () => ahora),
      ahora: () => ahora,
      logger: logger,
    );
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  group('la marca de conciliación en el futuro', () {
    test(
      // QA #539 — decisión del 04/11 (agente de decisiones, R2): la marca se cree hasta 5 minutos
      // por delante de «ahora»; más que eso se revisa desde los 90 días. Hoy la tolerancia es 1 h.
      'dado una marca a +6 min (reloj adelantado y corregido), se descarta: se revisa desde el '
      'tope de 90 días y la marca vuelve a «ahora»',
      () async {
        marca.marca = ahora.add(const Duration(minutes: 6));
        await agenda('age-1', DateTime.utc(2026, 10, 27, 15));

        final r = await conciliar('col-1');

        expect(r.getOrElse(() => -1), 1, reason: 'el recordatorio que sonó se guarda');
        expect(marca.marca, ahora);
      },
      skip: _conHallazgos
          ? false
          : 'QA #539: toleranciaDelReloj es 1 h; la decisión del 04/11 pide 5 min (marca a +6 min)',
    );

    test('dado una marca a +4 min (dentro de los 5 min de la decisión del 04/11), se respeta: no '
        'revisa ni mueve la marca', () async {
      marca.marca = ahora.add(const Duration(minutes: 4));
      await agenda('age-1', DateTime.utc(2026, 10, 27, 15));

      final r = await conciliar('col-1');

      expect(r.getOrElse(() => -1), 0);
      expect(marca.marca, ahora.add(const Duration(minutes: 4)));
      expect(await filas(), 0);
    });

    test(
      'borde exacto: una marca a +tolerancia se respeta y a +tolerancia+1 ms se descarta',
      () async {
        await agenda('age-1', DateTime.utc(2026, 10, 27, 15));
        const tol = ConciliarRecordatoriosUseCase.toleranciaDelReloj;

        marca.marca = ahora.add(tol);
        expect((await conciliar('col-1')).getOrElse(() => -1), 0);
        expect(marca.marca, ahora.add(tol), reason: 'a +tolerancia exacta se respeta');
        expect(await filas(), 0);

        marca.marca = ahora.add(tol + const Duration(milliseconds: 1));
        expect((await conciliar('col-1')).getOrElse(() => -1), 1);
        expect(marca.marca, ahora, reason: 'un milisegundo más y se descarta');
      },
    );

    test(
      'dos revisiones seguidas con la marca en el futuro dejan lo mismo: una vez cada aviso y la '
      'marca en «ahora»',
      () async {
        marca.marca = DateTime.utc(2027, 1, 1);
        await agenda('age-1', DateTime.utc(2026, 10, 27, 15));
        await agenda('age-2', DateTime.utc(2026, 10, 20, 11));

        final primera = await conciliar('col-1');
        final segunda = await conciliar('col-1');

        expect(primera.getOrElse(() => -1), 2);
        expect(segunda.getOrElse(() => -1), 0);
        expect(await filas(), 2);
        expect(marca.marca, ahora);
      },
    );

    test('con la marca en el futuro y el guardado de la marca roto: no lanza, los avisos quedan '
        'guardados una vez y al arreglarse el almacén la marca vuelve a «ahora»', () async {
      marca.marca = DateTime.utc(2027, 1, 1);
      marca.fallaAlGuardar = true;
      await agenda('age-1', DateTime.utc(2026, 10, 27, 15));

      await conciliar('col-1');
      expect(await filas(), 1);

      marca.fallaAlGuardar = false;
      marca.marca = DateTime.utc(2027, 1, 1);
      await conciliar('col-1');
      expect(await filas(), 1, reason: 'el id idempotente evita el repetido');
      expect(marca.marca, ahora);
    });

    test(
      'el aviso del log de la marca futura no lleva la dirección ni el id de la agenda',
      () async {
        marca.marca = DateTime.utc(2027, 1, 1);
        await agenda('age-secreta-1', DateTime.utc(2026, 10, 27, 15));
        await (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
          const UbicacionesCompanion(calle: Value('Av. Italia'), numero: Value('1234')),
        );

        await conciliar('col-1');

        final log = salidaDeLogs.buffer.map((e) => e.lines.join(' ')).join('\n');
        expect(log, contains('RECORDATORIOS_CONCILIAR_MARCA_FUTURA'));
        expect(log, isNot(contains('Italia')));
        expect(log, isNot(contains('1234')));
        expect(log, isNot(contains('age-secreta-1')));
      },
    );

    test('lo borrado con «Borrar todas» vuelve una sola vez tras la anomalía y después no '
        '(pendiente §2 del PR, caso documentado)', () async {
      marca.marca = DateTime.utc(2027, 1, 1);
      await agenda('age-1', DateTime.utc(2026, 10, 27, 15));
      await conciliar('col-1');
      await historial.borrarTodas();
      expect(await filas(), 0);

      marca.marca = DateTime.utc(2027, 1, 1);
      await conciliar('col-1');
      expect(await filas(), 1, reason: 'vuelve esa vez');

      await historial.borrarTodas();
      await conciliar('col-1');
      expect(await filas(), 0, reason: 'con la marca en «ahora» no vuelve más');
    });
  });

  group('«Borrar todas» por ids contra la tabla real', () {
    test('un conjunto vacío no borra nada y devuelve 0 (no es «todo»)', () async {
      await sembrar(5);
      final r = await local.borrarTodas(ids: <String>{});
      expect(r, 0);
      expect(await filas(), 5);
    });

    test('ids que no existen: 0 borrados y lo demás intacto', () async {
      await sembrar(5);
      expect(await local.borrarTodas(ids: {'fantasma-1', 'fantasma-2'}), 0);
      expect(await filas(), 5);
    });

    test('sin ids borra todo (la ruta de «sin conjunto» sigue viva)', () async {
      await sembrar(5);
      expect(await local.borrarTodas(), 5);
      expect(await filas(), 0);
    });

    for (final n in [499, 500, 501, 1000, 1001]) {
      test(
        '$n ids (bordes del lote de 500): borra exactamente esos y deja los de afuera',
        () async {
          await sembrar(n);
          await sembrar(3, prefijo: 'afuera');
          final ids = {for (var i = 0; i < n; i++) 'n-$i'};

          final r = await local.borrarTodas(ids: ids);

          expect(r, n);
          final quedan = (await db.select(db.notificacionesHistorial).get()).map((f) => f.id);
          expect(quedan.toSet(), {'afuera-0', 'afuera-1', 'afuera-2'});
        },
      );
    }

    test(
      'ids con comillas, porcentaje, guion bajo y emoji se comparan por igualdad exacta',
      () async {
        const raros = ["a'b", 'a%', 'a_b', 'recordatorio-x"; DROP TABLE x;--', '🏠-1'];
        for (var i = 0; i < raros.length; i++) {
          await historial.registrar(nota(raros[i], i), ahora: ahora);
        }
        await historial.registrar(nota('aXb', 9), ahora: ahora);
        await historial.registrar(nota('abc', 10), ahora: ahora);

        final r = await local.borrarTodas(ids: raros.toSet());

        expect(r, raros.length);
        final quedan = (await db.select(db.notificacionesHistorial).get()).map((f) => f.id).toSet();
        expect(quedan, {'aXb', 'abc'}, reason: 'ni «a%» ni «a_b» se comportan como comodines');
      },
    );
  });

  group('RecordatorioDeVisita', () {
    test('sin stringify, pero la igualdad por valor sigue andando', () {
      final fecha = DateTime.utc(2026, 10, 27, 15);
      RecordatorioDeVisita crear() => RecordatorioDeVisita(
        agendaId: 'x',
        tipo: TipoAgenda.cobranza,
        direccion: 'Av. Italia 1234 🏠 apto «B»',
        fechaProgramada: fecha,
      );
      expect(crear(), crear());
      expect(crear().hashCode, crear().hashCode);
      expect('${crear()}', isNot(contains('Italia')));
      expect('${crear()}', isNot(contains('1234')));
      expect([crear()].toString(), isNot(contains('Italia')));
    });
  });
}
