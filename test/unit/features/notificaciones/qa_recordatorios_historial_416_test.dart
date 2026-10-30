// QA de #416 / PR #506 (HU-NOT-005): «cada recordatorio local se guarda en el historial al dispararse».
// La función no tiene vista propia (el centro es de #481): se prueba contra las tablas reales
// (AppDatabase en memoria) lo que la HU promete y los casos límite que el PR no cubre: ventanas
// contiguas sin huecos ni repetidos, revisiones superpuestas, muchas visitas, textos raros, la marca
// fuera de hora y que ningún log lleve la dirección.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/texto_recordatorio.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/agendas_para_recordar_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/historial_notificaciones_local_data_source_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/historial_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/marca_conciliacion_recordatorios_impl.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/conciliar_recordatorios_use_case.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/historial_notificaciones_use_cases.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../helpers/campo_falsos.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late MemoryOutput salidaDeLogs;
  late AppLogger logger;
  late MarcaConciliacionRecordatoriosEnMemoria marca;
  late PreferenciasRecordatoriosRepositoryEnMemoria preferencias;
  late DateTime ahora;
  late ConciliarRecordatoriosUseCase conciliar;
  late HistorialNotificacionesRepositoryImpl historial;

  final creada = DateTime.utc(2026, 10, 1, 9);

  Future<void> agenda(
    String id,
    DateTime visita, {
    TipoAgenda tipo = TipoAgenda.entrevista,
    DateTime? guardada,
  }) => insertarAgenda(
    db,
    Agenda(
      id: id,
      espacioId: 'esp-1',
      espacioPersonaId: 'ep-1',
      tipo: tipo,
      fechaProgramada: visita,
      colportorId: 'col-1',
      auditoria: auditoriaDe(creada: guardada ?? creada),
    ),
  );

  Future<List<Notificacion>> historialActual() =>
      historial.observar(ahora: ahora).first.timeout(const Duration(seconds: 5)).then((l) => l);

  Future<void> direccion(String? calle, String? numero) =>
      (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
        UbicacionesCompanion(calle: Value(calle), numero: Value(numero)),
      );

  setUp(() async {
    db = AppDatabase(
      NativeDatabase.memory(),
      logger: AppLogger(logger: Logger(level: Level.off)),
    );
    salidaDeLogs = MemoryOutput();
    logger = AppLogger(output: salidaDeLogs);
    historial = HistorialNotificacionesRepositoryImpl(
      HistorialNotificacionesLocalDataSourceDrift(db),
      logger: logger,
    );
    marca = MarcaConciliacionRecordatoriosEnMemoria(DateTime.utc(2026, 10, 27, 12));
    preferencias = PreferenciasRecordatoriosRepositoryEnMemoria();
    ahora = DateTime.utc(2026, 10, 27, 15, 10);
    conciliar = ConciliarRecordatoriosUseCase(
      AgendasParaRecordarDrift(db),
      preferencias,
      marca,
      RegistrarNotificacionUseCase(historial, ahora: () => ahora),
      ahora: () => ahora,
      logger: logger,
    );
    await sembrarCasa(db);
    await direccion('Av. Italia', '1234');
  });
  tearDown(() => db.close());

  group('HU-NOT-005 · el historial lo muestra como lo promete la HU', () {
    test(
      'dado que sonaron 5 recordatorios en la semana, cuando se abre la app, quedan 5 sin leer y '
      'el más reciente va primero',
      () async {
        marca.marca = DateTime.utc(2026, 10, 20);
        ahora = DateTime.utc(2026, 10, 27, 18);
        for (var d = 0; d < 5; d++) {
          await agenda('age-$d', DateTime.utc(2026, 10, 21 + d, 15));
        }

        final r = await conciliar('col-1');
        final lista = await historialActual();

        expect(r.getOrElse(() => -1), 5);
        expect(lista, hasLength(5));
        expect(lista.map((n) => n.id).first, startsWith('recordatorio-age-4-'));
        expect(
          [
            for (var i = 1; i < lista.length; i++)
              lista[i - 1].recibidaEn.isAfter(lista[i].recibidaEn),
          ],
          everyElement(isTrue),
          reason: 'cronológico, más reciente primero',
        );
        expect(lista.every((n) => !n.leida), isTrue, reason: 'las no leídas tienen indicador');
        expect(lista.every((n) => n.tipo == TipoNotificacion.recordatorioVisita), isTrue);
        expect(lista.first.titulo, TextoRecordatorio.titulo);
        expect(lista.first.detalle, contains('Av. Italia 1234'));
        expect(lista.first.destino, isA<DestinoAgenda>());
      },
    );

    test(
      'dado 30 recordatorios viejos, cuando se borran todos y se vuelve a abrir la app, la tabla '
      'queda vacía y no vuelven',
      () async {
        marca.marca = DateTime.utc(2026, 10, 1);
        ahora = DateTime.utc(2026, 10, 27, 18);
        for (var d = 0; d < 30; d++) {
          await agenda('age-$d', DateTime.utc(2026, 10, 1 + d % 25, 10 + d % 5));
        }
        await conciliar('col-1');
        expect((await db.select(db.notificacionesHistorial).get()).length, 30);

        await historial.borrarTodas();
        ahora = DateTime.utc(2026, 10, 27, 19);
        await conciliar('col-1');

        expect(await db.select(db.notificacionesHistorial).get(), isEmpty);
      },
    );
  });

  group('ventanas contiguas', () {
    test('dado revisiones a las 14:00, 14:35 y 15:20, cada aviso queda una sola vez: ni huecos ni '
        'repetidos, incluso el que cae justo en el instante de una revisión', () async {
      // Visitas (aviso 30 min antes): 14:45→14:15 · 15:05→14:35 (justo en la 2.ª) · 15:00→14:30
      // · 15:30→15:00 · 16:00→15:30 (todavía no sonó).
      marca.marca = DateTime.utc(2026, 10, 27, 14);
      await agenda('a', DateTime.utc(2026, 10, 27, 14, 45));
      await agenda('b', DateTime.utc(2026, 10, 27, 15, 5));
      await agenda('c', DateTime.utc(2026, 10, 27, 15));
      await agenda('d', DateTime.utc(2026, 10, 27, 15, 30));
      await agenda('e', DateTime.utc(2026, 10, 27, 16));

      ahora = DateTime.utc(2026, 10, 27, 14);
      final r0 = await conciliar('col-1');
      ahora = DateTime.utc(2026, 10, 27, 14, 35);
      final r1 = await conciliar('col-1');
      ahora = DateTime.utc(2026, 10, 27, 15, 20);
      final r2 = await conciliar('col-1');

      expect([r0, r1, r2].map((r) => r.getOrElse(() => -1)), [0, 3, 1]);
      final ids = [for (final f in await db.select(db.notificacionesHistorial).get()) f.id]..sort();
      expect(ids, hasLength(4));
      expect(ids.toSet(), hasLength(4));
      expect(ids.where((i) => i.startsWith('recordatorio-e-')), isEmpty);
    });

    test('dado dos revisiones a la vez (cada una con su propio caso de uso), el aviso queda una '
        'sola vez y entre las dos cuentan uno', () async {
      await agenda('age-1', DateTime.utc(2026, 10, 27, 15));
      final otra = ConciliarRecordatoriosUseCase(
        AgendasParaRecordarDrift(db),
        preferencias,
        MarcaConciliacionRecordatoriosEnMemoria(marca.marca),
        RegistrarNotificacionUseCase(historial, ahora: () => ahora),
        ahora: () => ahora,
        logger: logger,
      );

      final r = await Future.wait([conciliar('col-1'), otra('col-1')]);

      expect(r.map((e) => e.getOrElse(() => -1)).reduce((a, b) => a + b), 1);
      expect(await db.select(db.notificacionesHistorial).get(), hasLength(1));
    });
  });

  group('datos límite', () {
    test('dado 250 visitas vencidas, las guarda todas, cada una una vez, y una segunda revisión no '
        'agrega ninguna', () async {
      marca.marca = DateTime.utc(2026, 8, 1);
      ahora = DateTime.utc(2026, 10, 27, 18);
      for (var i = 0; i < 250; i++) {
        await agenda('age-$i', DateTime.utc(2026, 8, 2).add(Duration(hours: 7 * i)));
      }

      final r = await conciliar('col-1');
      ahora = DateTime.utc(2026, 10, 27, 18, 5);
      final r2 = await conciliar('col-1');

      final filas = await db.select(db.notificacionesHistorial).get();
      // Entran solo las de los últimos 90 días: ninguna fila más vieja que la retención.
      final piso = DateTime.utc(2026, 10, 27, 18).subtract(const Duration(days: 90));
      expect(filas, isNotEmpty);
      expect(filas.every((f) => !f.recibidaEn.isBefore(piso)), isTrue);
      expect(r.getOrElse(() => -1), filas.length);
      expect(r2.getOrElse(() => -1), 0);
    });

    test('dado una visita sin dirección (la ubicación no llegó), el aviso sale sin «en …» y se '
        'guarda', () async {
      await direccion(null, null);
      await agenda('age-1', DateTime.utc(2026, 10, 27, 15));

      await conciliar('col-1');
      final n = (await historialActual()).single;

      expect(n.detalle, isNotNull);
      expect(n.detalle, isNot(contains(' en ')));
      expect(n.detalle, startsWith('Entrevista a las '));
    });

    test(
      'dado una dirección con emoji, tildes, saltos de línea y 600 caracteres, se guarda entera y '
      'sin saltos',
      () async {
        final larga = 'Ñandú 🏠\n  Pasaje ${'Muy Largo ' * 60}';
        await direccion(larga, '12 "B" 202E');
        await agenda('age-1', DateTime.utc(2026, 10, 27, 15), tipo: TipoAgenda.cobranza);

        final r = await conciliar('col-1');
        final n = (await historialActual()).single;

        expect(r.isRight(), isTrue);
        expect(n.detalle, contains('Ñandú 🏠 Pasaje Muy Largo'));
        expect(n.detalle, isNot(contains('\n')));
        expect(n.detalle!.length, greaterThan(600));
        expect(n.detalle, startsWith('Cobranza en '));
      },
    );

    test('dado un id de agenda con comillas y guiones, el id del aviso se arma igual y no se pisa '
        'con otra agenda', () {
      final a = ConciliarRecordatoriosUseCase.idDeRecordatorio(
        "x'-1",
        DateTime.utc(2026, 10, 27, 14, 30),
      );
      final b = ConciliarRecordatoriosUseCase.idDeRecordatorio(
        "x'-1",
        DateTime.utc(2026, 10, 27, 14, 30, 0, 1),
      );
      expect(a, "recordatorio-x'-1-${DateTime.utc(2026, 10, 27, 14, 30).millisecondsSinceEpoch}");
      expect(b, isNot(a));
    });
  });

  group('privacidad', () {
    test(
      'dado que guardar falla (la tabla no existe), ningún log lleva la dirección ni el texto del '
      'aviso, y la revisión devuelve un error sin lanzar',
      () async {
        await agenda('age-1', DateTime.utc(2026, 10, 27, 15));
        await db.customStatement('DROP TABLE notificacion_historial');

        final r = await conciliar('col-1');

        expect(r.isRight(), isTrue, reason: 'el fallo de un aviso se cuenta, no se lanza');
        final log = salidaDeLogs.buffer
            .expand((e) => [...e.lines, '${e.origin.error}', '${e.origin.stackTrace}'])
            .join('\n');
        expect(log, isNotEmpty, reason: 'la falla queda en el log');
        expect(log, isNot(contains('Italia')));
        expect(log, isNot(contains('1234')));
        expect(log, isNot(contains('Entrevista')));
        expect(marca.marca, DateTime.utc(2026, 10, 27, 12), reason: 'la marca no avanza');
      },
    );

    test('toString del aviso del historial no lleva la dirección', () {
      final n = Notificacion(
        id: 'recordatorio-x-1',
        tipo: TipoNotificacion.recordatorioVisita,
        titulo: TextoRecordatorio.titulo,
        detalle: 'Entrevista en Av. Italia 1234 a las 15:00',
        destino: const DestinoAgenda('x'),
        recibidaEn: DateTime.utc(2026, 10, 27, 14, 30),
      );
      expect('$n', isNot(contains('Italia')));
    });

    // skip: QA #416 — RecordatorioDeVisita (la visita con su dirección que recorre la conciliación)
    // no apaga `stringify`: en debug su toString imprime la dirección (convenciones §7.5).
    test(
      'toString de la visita a recordar no lleva la dirección',
      () {
        final v = RecordatorioDeVisita(
          agendaId: 'x',
          tipo: TipoAgenda.entrevista,
          direccion: 'Av. Italia 1234',
          fechaProgramada: DateTime.utc(2026, 10, 27, 15),
        );
        expect('$v', isNot(contains('Italia')));
      },
      skip: 'QA #416: RecordatorioDeVisita.toString() imprime la dirección (stringify en debug)',
    );
  });

  group('la marca fuera de hora', () {
    // skip: QA #416 — una marca en el futuro (el reloj se adelantó una vez) congela la conciliación
    // hasta que el reloj la alcance: «el reloj fue hacia atrás» nunca la baja.
    test('dado que la marca quedó en el futuro porque el reloj del teléfono se adelantó y se '
        'corrigió, los recordatorios siguientes se guardan igual', () async {
      marca.marca = DateTime.utc(2027, 10, 27);
      await agenda('age-1', DateTime.utc(2026, 10, 27, 15));

      final r = await conciliar('col-1');

      expect(r.getOrElse(() => -1), 1);
      expect(await db.select(db.notificacionesHistorial).get(), hasLength(1));
    }, skip: 'QA #416: marca en el futuro congela la conciliación hasta que el reloj la alcance');

    test(
      'dado que el reloj va hacia atrás unos minutos, no repite ni pierde: al volver el reloj se '
      'sigue desde la marca',
      () async {
        await agenda('age-1', DateTime.utc(2026, 10, 27, 15));
        await conciliar('col-1');
        ahora = DateTime.utc(2026, 10, 27, 15, 5);
        final atras = await conciliar('col-1');
        ahora = DateTime.utc(2026, 10, 27, 15, 20);
        final delante = await conciliar('col-1');

        expect(atras.getOrElse(() => -1), 0);
        expect(delante.getOrElse(() => -1), 0);
        expect(await db.select(db.notificacionesHistorial).get(), hasLength(1));
      },
    );
  });

  group('preferencias', () {
    test('dado una anticipación de 2 horas (el máximo), el aviso sale 2 horas antes de la visita y '
        'queda una sola vez', () async {
      preferencias.preferencias = const PreferenciasRecordatorios(anticipacionMinutos: 120);
      await agenda('age-1', DateTime.utc(2026, 10, 27, 16, 30));

      await conciliar('col-1');
      ahora = DateTime.utc(2026, 10, 27, 15, 20);
      marca.marca = DateTime.utc(2026, 10, 27, 12);
      await conciliar('col-1');
      final n = (await historialActual()).single;

      expect(n.recibidaEn, DateTime.utc(2026, 10, 27, 14, 30));
      expect(
        n.id,
        'recordatorio-age-1-${DateTime.utc(2026, 10, 27, 14, 30).millisecondsSinceEpoch}',
      );
    });
  });
}
