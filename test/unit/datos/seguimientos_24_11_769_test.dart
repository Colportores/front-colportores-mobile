// Los seguimientos del 24/11 que viajan por el sync (#769; backend-supabase 0206 a 0208, migraciones de #313),
// de punta a punta con el código real de los dos lados de la frontera: el motor baja el delta de un servidor
// falso, lo que baja entra por `DriftLocalStore` a las tablas de la app y la app lo lee y lo escribe.
//
// - `ubicacion.nombre` («Nombre ubic.»): baja con la fila y la fila que sube lo lleva.
// - `preferencia_de_avisos` («Avisos s/red»): una fila por persona, push con pull. Cambiar un aviso sin señal
//   queda en el teléfono al instante y sube cuando vuelve la señal.
// - `campania_companiero` («Nombres camp.»): réplica de solo bajada de los nombres de los compañeros.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/armado_del_motor.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/preferencias_de_avisos_local_data_source_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/avisos_del_servidor_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/avisos_del_servidor.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/logger_mudo.dart';

Map<String, Object?> _auditoria([int version = 1]) => {
  'created_at': '2026-10-01T10:00:00+00:00',
  'updated_at': '2026-10-01T10:00:00+00:00',
  'created_by': null,
  'deleted_at': null,
  'sync_version': version,
};

// Las filas, como las arma `sync.pull` con las columnas de cada tabla del servidor.
Map<String, Object?> _ubicacion(String id, {String? nombre, int version = 1}) => {
  'id': id,
  'tipo': 'NEGOCIO',
  'calle': 'Av. Italia',
  'numero': '2810',
  'nombre': nombre,
  'lat': -34.891,
  'lon': -56.125,
  'ciudad_id': 'mvd',
  'zona_id': null,
  ..._auditoria(version),
  'xmin_w': '1',
};

Map<String, Object?> _preferencias(
  String usuario,
  Map<String, Object?>? notif, {
  int version = 1,
}) => {'id': usuario, 'notif_preferences': notif, ..._auditoria(version), 'xmin_w': '1'};

Map<String, Object?> _companiero(
  String id,
  String usuario,
  String nombre,
  String apellido, {
  String campania = 'camp-1',
  String? ciudad = 'mvd',
  bool deBaja = false,
}) => {
  'id': id,
  'campania_id': campania,
  'usuario_id': usuario,
  'nombre': nombre,
  'apellido': apellido,
  'ciudad_id': ciudad,
  ..._auditoria(),
  if (deBaja) 'deleted_at': '2026-11-01T10:00:00+00:00',
  'xmin_w': '1',
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeSyncTransport servidor;
  late FakeConnectivityPort red;
  late SyncEngine motor;
  late AvisosDelServidorLocal avisos;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport();
    red = FakeConnectivityPort();
    motor = armarMotorDeSync(
      db: db,
      leerDek: () async => null,
      tokenDrive: () async => null,
      transporte: servidor,
      conectividad: red,
      archivo: FakeArchive(),
    );
    avisos = AvisosDelServidorLocal(
      PreferenciasDeAvisosLocalDataSourceDrift(
        db,
        encolador: EncoladorSyncMotor(motor),
        usuarioId: () => 'col-1',
        ahora: () => DateTime.utc(2026, 11, 26, 15),
      ),
    );
  });
  tearDown(() async {
    await motor.dispose();
    await red.dispose();
    await db.close();
  });

  Future<List<String>> cola() async => [
    for (final j in await db.select(db.syncQueue).get()) '${j.entity}:${j.op}:${j.state}',
  ];

  group('el catálogo del motor', () {
    test('las preferencias de avisos son push con pull de lo propio y entran al backup', () {
      final spec = specsDeLaApp.singleWhere((s) => s.entity == 'preferencia_de_avisos');

      expect(spec.policy, SyncPolicy.push);
      expect(spec.alsoPull, isTrue);
      expect(spec.critical, isFalse);
      expect(entidadesQueEscribeElMotor, contains('preferencia_de_avisos'));
      expect(entidadesDelBackup, contains('preferencia_de_avisos'));
    });

    test('los compañeros de campaña son una réplica de solo lectura, sin Realtime', () {
      final spec = specsDeLaApp.singleWhere((s) => s.entity == 'campania_companiero');

      expect(spec.policy, SyncPolicy.pull);
      expect(spec.realtime, isFalse);
      expect(entidadesQueEscribeElMotor, contains('campania_companiero'));
      expect(
        entidadesDelBackup,
        isNot(contains('campania_companiero')),
        reason: 'el pull la reconstruye',
      );
    });

    test(
      'las tablas tienen la forma del cloud: toda columna local viene en la fila del servidor',
      () {
        final filas = {
          'ubicacion': _ubicacion('ub-1'),
          'preferencia_de_avisos': _preferencias('col-1', null),
          'campania_companiero': _companiero('cc-1', 'col-2', 'Ana', 'Pérez'),
        };
        for (final e in filas.entries) {
          final tabla = db.allTables.singleWhere((t) => t.actualTableName == e.key);
          final locales = tabla.$columns.map((c) => c.name).toSet();
          expect(e.value.keys.toSet().containsAll(locales), isTrue, reason: 'faltan en ${e.key}');
          expect(e.value.keys.toSet().difference(locales), {'xmin_w'}, reason: e.key);
        }
      },
    );
  });

  group('el nombre de la ubicación («Nombre ubic.»)', () {
    test('baja con la ubicación y se lee; una ubicación sin nombre lo deja vacío', () async {
      servidor.seed('ubicacion', [
        _ubicacion('ub-1', nombre: 'Farmacia Italia'),
        _ubicacion('ub-2'),
      ]);

      await motor.syncNow();

      final local = UbicacionLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());
      expect((await local.obtener('ub-1'))!.nombre, 'Farmacia Italia');
      expect((await local.obtener('ub-2'))!.nombre, isNull);
    });

    test('el servidor cambia el nombre y el teléfono lo trae en el pull siguiente', () async {
      servidor.seed('ubicacion', [_ubicacion('ub-1', nombre: 'Farmacia Italia')]);
      await motor.syncNow();

      servidor.seed('ubicacion', [_ubicacion('ub-1', nombre: 'Farmacia Italia 2', version: 2)]);
      await motor.syncNow();

      final local = UbicacionLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());
      expect((await local.obtener('ub-1'))!.nombre, 'Farmacia Italia 2');
    });
  });

  group('los compañeros de campaña («Nombres camp.»)', () {
    test(
      'bajan con su nombre, apellido y ciudad, y una persona dada de baja llega con la marca',
      () async {
        servidor.seed('campania_companiero', [
          _companiero('cc-1', 'col-2', 'Ana', 'Pérez'),
          _companiero('cc-2', 'col-3', 'Luis', 'Gómez', ciudad: null),
          _companiero('cc-3', 'col-4', 'Eva', 'Díaz', deBaja: true),
        ]);

        await motor.syncNow();

        final filas = await db.select(db.campaniaCompanieros).get();
        final porId = {for (final f in filas) f.id: f};
        expect(porId.keys, {'cc-1', 'cc-2', 'cc-3'});
        expect(
          (porId['cc-1']!.nombre, porId['cc-1']!.apellido, porId['cc-1']!.ciudadId),
          ('Ana', 'Pérez', 'mvd'),
        );
        expect(porId['cc-1']!.usuarioId, 'col-2');
        expect(porId['cc-2']!.ciudadId, isNull);
        expect(porId['cc-3']!.deletedAt, isNotNull);
        expect(porId['cc-1']!.deletedAt, isNull);
      },
    );

    test('el mismo pull repetido no duplica y un nombre corregido se actualiza', () async {
      servidor.seed('campania_companiero', [_companiero('cc-1', 'col-2', 'Ana', 'Pérez')]);
      await motor.syncNow();
      await motor.syncNow();
      expect(await db.select(db.campaniaCompanieros).get(), hasLength(1));

      servidor.seed('campania_companiero', [
        {..._companiero('cc-1', 'col-2', 'Ana María', 'Pérez'), ..._auditoria(2)},
      ]);
      await motor.syncNow();

      final filas = await db.select(db.campaniaCompanieros).get();
      expect(filas.single.nombre, 'Ana María');
    });

    test('la app nunca sube un compañero: no hay nada encolado', () async {
      servidor.seed('campania_companiero', [_companiero('cc-1', 'col-2', 'Ana', 'Pérez')]);
      await motor.syncNow();

      expect(await cola(), isEmpty);
      expect(servidor.batches, isEmpty);
    });
  });

  group('las preferencias de avisos sin señal («Avisos s/red»)', () {
    test(
      'lo que bajó del servidor es lo que lee la pantalla (el objeto entero, con lo que no se ve)',
      () async {
        servidor.seed('preferencia_de_avisos', [
          _preferencias('col-1', {'tickets': false, 'hora_cuota': '07:30', 'otra': 'x'}),
        ]);

        await motor.syncNow();

        final leidos = await avisos.leer();
        expect(leidos.tickets, isFalse);
        expect(leidos.pedidos, isTrue);
        expect(leidos.horaCuota, const HoraDelAviso(7, 30));
        expect(leidos.otras, {'otra': 'x'});
      },
    );

    test('sin fila todavía (el teléfono no sincronizó) se leen los valores de siempre', () async {
      expect(await avisos.leer(), const AvisosDelServidor());
    });

    test(
      'sin señal el cambio queda guardado al instante, en la cola, y sube cuando vuelve la señal',
      () async {
        servidor.seed('preferencia_de_avisos', [
          _preferencias('col-1', {'tickets': true}),
        ]);
        await motor.syncNow();
        red.goOffline();
        servidor.offline();

        await avisos.guardar(
          (await avisos.leer()).copyWith(tickets: false, horaCuota: const HoraDelAviso(7, 30)),
        );

        // Ya está en el teléfono: la pantalla lo lee, y nada salió todavía.
        final guardado = await avisos.leer();
        expect(guardado.tickets, isFalse);
        expect(guardado.horaCuota, const HoraDelAviso(7, 30));
        expect(await cola(), ['preferencia_de_avisos:update:PENDING']);
        expect(servidor.batches, isEmpty);

        servidor.online();
        red.goOnline();
        await motor.syncNow();

        expect(await cola(), [
          'preferencia_de_avisos:update:DONE',
        ], reason: 'el servidor lo recibió');
        final enElServidor = servidor.rowsOf('preferencia_de_avisos').single;
        expect(enElServidor['id'], 'col-1');
        expect((enElServidor['notif_preferences']! as Map)['tickets'], isFalse);
        expect((enElServidor['notif_preferences']! as Map)['hora_cuota'], '07:30');
      },
    );

    test(
      'dos cambios seguidos sin señal quedan en un solo trabajo con el último valor y el servidor termina con él',
      () async {
        servidor.seed('preferencia_de_avisos', [_preferencias('col-1', {})]);
        await motor.syncNow();
        red.goOffline();
        servidor.offline();

        await avisos.guardar((await avisos.leer()).copyWith(pedidos: false));
        await avisos.guardar((await avisos.leer()).copyWith(cuotas: false));
        await avisos.guardar((await avisos.leer()).copyWith(pedidos: true));

        final local = await avisos.leer();
        expect((local.pedidos, local.cuotas), (true, false));
        // El motor junta los cambios de la misma fila que todavía no subieron: sube uno solo, con todo.
        expect(await cola(), ['preferencia_de_avisos:update:PENDING']);

        servidor.online();
        red.goOnline();
        await motor.syncNow();

        expect(await cola(), ['preferencia_de_avisos:update:DONE']);
        final fila = (servidor.rowsOf('preferencia_de_avisos').single['notif_preferences']! as Map);
        expect((fila['pedidos'], fila['cuotas']), (true, false));
      },
    );

    test(
      'un cambio que el servidor rechaza no se pierde en silencio: la cola lo marca y lo local sigue',
      () async {
        servidor.seed('preferencia_de_avisos', [_preferencias('col-1', {})]);
        await motor.syncNow();
        await avisos.guardar((await avisos.leer()).copyWith(tickets: false));
        final trabajo = (await db.select(db.syncQueue).get()).single;
        servidor.rejectJob(trabajo.clientOpId, 'invalid');

        await motor.syncNow();

        expect(
          (await avisos.leer()).tickets,
          isFalse,
          reason: 'lo que la persona eligió sigue en el teléfono',
        );
        expect((await db.select(db.syncQueue).get()).single.state, 'INVALID');
      },
    );

    test(
      'antes del primer pull no hay versión del servidor sobre la que guardar: falla sin escribir ni encolar '
      'nada (el cambio no se pierde en silencio) y, cuando la fila baja, el cambio se puede hacer',
      () async {
        red.goOffline();
        servidor.offline();

        await expectLater(
          avisos.guardar(const AvisosDelServidor(tickets: false)),
          throwsA(isA<PreferenciasSinBajarException>()),
        );

        expect(await db.select(db.preferenciasDeAvisos).get(), isEmpty);
        expect(await cola(), isEmpty);
        expect((await avisos.leer()).tickets, isTrue, reason: 'lo que se ve es lo que hay');

        servidor
          ..seed('preferencia_de_avisos', [
            _preferencias('col-1', {'hora_cuota': '07:30'}, version: 3),
          ])
          ..online();
        red.goOnline();
        await motor.syncNow();
        await avisos.guardar((await avisos.leer()).copyWith(tickets: false));

        final guardado = await avisos.leer();
        expect((guardado.tickets, guardado.horaCuota), (false, const HoraDelAviso(7, 30)));
        final trabajo = (await db.select(db.syncQueue).get()).single;
        expect((trabajo.op, trabajo.state), ('update', 'PENDING'));
        expect(trabajo.payload, contains('"sync_version":3'));
      },
    );

    test(
      'sin una persona con sesión y sin fila tampoco hay de quién guardar: falla, sin escribir nada',
      () async {
        final sinSesion = AvisosDelServidorLocal(
          PreferenciasDeAvisosLocalDataSourceDrift(
            db,
            encolador: EncoladorSyncEnMemoria(),
            usuarioId: () => null,
          ),
        );

        await expectLater(
          sinSesion.guardar(const AvisosDelServidor()),
          throwsA(isA<PreferenciasSinBajarException>()),
        );

        expect(await db.select(db.preferenciasDeAvisos).get(), isEmpty);
        expect(await cola(), isEmpty);
      },
    );

    test('si el encolado falla la fila tampoco queda (todo o nada)', () async {
      servidor.seed('preferencia_de_avisos', [
        _preferencias('col-1', {'tickets': true}),
      ]);
      await motor.syncNow();
      final conFalla = AvisosDelServidorLocal(
        PreferenciasDeAvisosLocalDataSourceDrift(
          db,
          encolador: EncoladorSyncEnMemoria(fallarCon: StateError('motor apagado')),
          usuarioId: () => 'col-1',
        ),
      );

      await expectLater(
        conFalla.guardar(const AvisosDelServidor(tickets: false)),
        throwsStateError,
      );

      expect((await avisos.leer()).tickets, isTrue, reason: 'volvió a como estaba');
    });

    test(
      'la fila se escribe una vez por cambio con la hora del cambio y la versión que ya tenía',
      () async {
        servidor.seed('preferencia_de_avisos', [_preferencias('col-1', {}, version: 5)]);
        await motor.syncNow();
        final registro = EncoladorSyncEnMemoria();
        final conRegistro = AvisosDelServidorLocal(
          PreferenciasDeAvisosLocalDataSourceDrift(
            db,
            encolador: registro,
            usuarioId: () => 'col-1',
            ahora: () => DateTime.utc(2026, 11, 26, 15),
          ),
        );

        await conRegistro.guardar(const AvisosDelServidor(tickets: false));

        final cambio = registro.encolados.single;
        expect(cambio.entidad, 'preferencia_de_avisos');
        expect(cambio.operacion.name, 'update');
        expect(cambio.payload['id'], 'col-1');
        expect(cambio.payload['sync_version'], 5);
        expect(cambio.payload['updated_at'], '2026-11-26T15:00:00.000Z');
        expect((cambio.payload['notif_preferences']! as Map)['tickets'], isFalse);
        expect(cambio.payload.keys.toSet(), {
          'id',
          'notif_preferences',
          'created_at',
          'updated_at',
          'created_by',
          'deleted_at',
          'sync_version',
        });
      },
    );
  });
}
