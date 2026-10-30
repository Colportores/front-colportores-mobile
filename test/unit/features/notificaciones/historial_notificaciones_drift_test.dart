// El historial de avisos (HU-NOT-005, #156) contra la tabla real: AppDatabase en memoria, mismo
// esquema que en el dispositivo.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/consultor_destinos_notificacion_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/historial_notificaciones_local_data_source_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/historial_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/historial_notificaciones_repository.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../helpers/campo_falsos.dart';
import '../../../helpers/logger_mudo.dart';

final _ahora = DateTime.utc(2026, 10, 23, 19, 10);

Notificacion _aviso(
  String id, {
  Duration hace = const Duration(hours: 1),
  String titulo = 'Cobranza a las 16:00',
  String? detalle = 'Av. Italia 2810',
  DestinoNotificacion? destino,
  DateTime? leidaEn,
}) => Notificacion(
  id: id,
  tipo: TipoNotificacion.recordatorioVisita,
  titulo: titulo,
  detalle: detalle,
  destino: destino,
  recibidaEn: _ahora.subtract(hace),
  leidaEn: leidaEn,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late HistorialNotificacionesRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    repo = HistorialNotificacionesRepositoryImpl(
      HistorialNotificacionesLocalDataSourceDrift(db),
      logger: loggerMudo(),
    );
  });
  tearDown(() => db.close());

  Future<List<Notificacion>> lista({TipoNotificacion? tipo}) =>
      repo.observar(tipo: tipo, ahora: _ahora).first;
  Future<List<String>> ids() async => [for (final n in await lista()) n.id];
  Future<int> filasEnLaTabla() async => (await db.select(db.notificacionesHistorial).get()).length;

  group('registrar', () {
    test(
      'dado un aviso nuevo, cuando se registra, queda guardado con todo lo que se le mostró',
      () async {
        final r = await repo.registrar(
          _aviso('n-1', destino: const DestinoAgenda('age-1')),
          ahora: _ahora,
        );

        expect(r, const Right<Failure, bool>(true));
        final guardado = (await lista()).single;
        expect(guardado.id, 'n-1');
        expect(guardado.tipo, TipoNotificacion.recordatorioVisita);
        expect(guardado.titulo, 'Cobranza a las 16:00');
        expect(guardado.detalle, 'Av. Italia 2810');
        expect(guardado.destino, const DestinoAgenda('age-1'));
        expect(guardado.recibidaEn, _ahora.subtract(const Duration(hours: 1)));
        expect(guardado.leida, isFalse);
        final fila = (await db.select(db.notificacionesHistorial).get()).single;
        expect(fila.destino, 'agenda/age-1');
        expect(fila.tipo, 'RECORDATORIO_VISITA');
      },
    );

    test(
      'cuando se registra el mismo aviso dos veces, queda uno solo y no se pisa lo leído',
      () async {
        await repo.registrar(_aviso('n-1'), ahora: _ahora);
        await repo.marcarLeida('n-1', ahora: _ahora);

        final segunda = await repo.registrar(_aviso('n-1', titulo: 'Otro texto'), ahora: _ahora);

        expect(segunda, const Right<Failure, bool>(false));
        final guardado = (await lista()).single;
        expect(guardado.titulo, 'Cobranza a las 16:00');
        expect(guardado.leida, isTrue);
      },
    );

    test('un aviso sin segunda línea ni destino se guarda igual', () async {
      await repo.registrar(_aviso('n-1', detalle: null), ahora: _ahora);

      final guardado = (await lista()).single;
      expect(guardado.detalle, isNull);
      expect(guardado.destino, isNull);
    });

    test('al registrar, purga lo que pasó de los 90 días', () async {
      await repo.registrar(_aviso('viejo', hace: const Duration(days: 91)), ahora: _ahora);
      expect(await filasEnLaTabla(), 0, reason: 'se registró y se purgó en la misma llamada');

      await db
          .into(db.notificacionesHistorial)
          .insert(
            NotificacionesHistorialCompanion.insert(
              id: 'colado',
              tipo: 'RECORDATORIO_VISITA',
              titulo: 'x',
              recibidaEn: _ahora.subtract(const Duration(days: 120)),
            ),
          );
      await repo.registrar(_aviso('n-2'), ahora: _ahora);

      expect(await filasEnLaTabla(), 1);
      expect(await ids(), ['n-2']);
    });
  });

  group('observar', () {
    test('lista el más reciente primero, y a igual hora el id mayor primero', () async {
      await repo.registrar(_aviso('a', hace: const Duration(hours: 3)), ahora: _ahora);
      await repo.registrar(_aviso('c', hace: const Duration(hours: 1)), ahora: _ahora);
      await repo.registrar(_aviso('b', hace: const Duration(hours: 1)), ahora: _ahora);

      expect(await ids(), ['c', 'b', 'a']);
    });

    test('lee solo lo de los últimos 90 días, aunque la purga no haya corrido', () async {
      Future<void> colar(String id, Duration hace) => db
          .into(db.notificacionesHistorial)
          .insert(
            NotificacionesHistorialCompanion.insert(
              id: id,
              tipo: 'RECORDATORIO_VISITA',
              titulo: id,
              recibidaEn: _ahora.subtract(hace),
            ),
          );
      await colar('justo', const Duration(days: 90));
      await colar('pasado', const Duration(days: 90, milliseconds: 1));
      await colar('reciente', const Duration(days: 2));

      expect(await ids(), ['reciente', 'justo']);
      expect(await filasEnLaTabla(), 3);
    });

    test('filtra por tipo', () async {
      await repo.registrar(_aviso('a'), ahora: _ahora);

      expect(await lista(tipo: TipoNotificacion.recordatorioVisita), hasLength(1));
    });

    test('emite de nuevo cuando llega un aviso o se marca uno', () async {
      final emisiones = <List<String>>[];
      final suscripcion = repo
          .observar(ahora: _ahora)
          .listen((l) => emisiones.add([for (final n in l) '${n.id}${n.leida ? ':leida' : ''}']));
      addTearDown(suscripcion.cancel);
      await pumpEventQueue();

      await repo.registrar(_aviso('a'), ahora: _ahora);
      await pumpEventQueue();
      await repo.marcarLeida('a', ahora: _ahora);
      await pumpEventQueue();

      // Drift avisa de cada escritura, aunque no cambie lo que se ve: se juntan las repetidas.
      final distintas = <List<String>>[];
      for (final e in emisiones) {
        if (distintas.isEmpty || distintas.last.join(',') != e.join(',')) distintas.add(e);
      }
      expect(distintas, [
        <String>[],
        ['a'],
        ['a:leida'],
      ]);
    });
  });

  group('no leídas', () {
    test('cuenta las que no se leyeron y baja al marcarlas', () async {
      await repo.registrar(_aviso('a'), ahora: _ahora);
      await repo.registrar(_aviso('b'), ahora: _ahora);
      final cuentas = <int>[];
      final suscripcion = repo.observarNoLeidas(ahora: _ahora).listen(cuentas.add);
      addTearDown(suscripcion.cancel);
      await pumpEventQueue();

      await repo.marcarLeida('a', ahora: _ahora);
      await pumpEventQueue();
      await repo.marcarTodasLeidas(ahora: _ahora);
      await pumpEventQueue();

      expect(cuentas, [2, 1, 0]);
    });

    test('no cuenta lo que pasó de los 90 días', () async {
      await db
          .into(db.notificacionesHistorial)
          .insert(
            NotificacionesHistorialCompanion.insert(
              id: 'viejo',
              tipo: 'RECORDATORIO_VISITA',
              titulo: 'x',
              recibidaEn: _ahora.subtract(const Duration(days: 100)),
            ),
          );

      expect(await repo.observarNoLeidas(ahora: _ahora).first, 0);
    });
  });

  group('marcar como leídas', () {
    test('marcarLeida guarda el momento y no lo cambia la segunda vez', () async {
      await repo.registrar(_aviso('a'), ahora: _ahora);

      await repo.marcarLeida('a', ahora: _ahora);
      await repo.marcarLeida('a', ahora: _ahora.add(const Duration(hours: 5)));

      expect((await lista()).single.leidaEn, _ahora);
    });

    test('marcar un aviso que no existe no falla ni escribe nada', () async {
      final r = await repo.marcarLeida('no-existe', ahora: _ahora);

      expect(r, const Right<Failure, Unit>(unit));
      expect(await filasEnLaTabla(), 0);
    });

    test('marcarTodasLeidas deja todas leídas, también las que llegaron antes', () async {
      await repo.registrar(_aviso('a'), ahora: _ahora);
      await repo.registrar(_aviso('b', hace: const Duration(days: 3)), ahora: _ahora);

      await repo.marcarTodasLeidas(ahora: _ahora);

      expect((await lista()).every((n) => n.leida), isTrue);
    });
  });

  group('borrar', () {
    test('borrarTodas deja la tabla vacía (30 avisos viejos)', () async {
      for (var i = 0; i < 30; i++) {
        await repo.registrar(
          _aviso('n-$i', hace: Duration(days: i + 1)),
          ahora: _ahora,
        );
      }

      final r = await repo.borrarTodas();

      expect(r, const Right<Failure, int>(30));
      expect(await filasEnLaTabla(), 0);
    });

    test('borrarTodas también borra lo vencido que la purga no alcanzó a sacar', () async {
      await db
          .into(db.notificacionesHistorial)
          .insert(
            NotificacionesHistorialCompanion.insert(
              id: 'viejo',
              tipo: 'RECORDATORIO_VISITA',
              titulo: 'x',
              recibidaEn: _ahora.subtract(const Duration(days: 200)),
            ),
          );

      await repo.borrarTodas();

      expect(await filasEnLaTabla(), 0);
    });

    test('con hasta, lo que llegó después sobrevive', () async {
      await repo.registrar(_aviso('antes', hace: const Duration(minutes: 5)), ahora: _ahora);
      await repo.registrar(_aviso('justo', hace: Duration.zero), ahora: _ahora);
      await repo.registrar(_aviso('despues', hace: -const Duration(minutes: 1)), ahora: _ahora);

      final r = await repo.borrarTodas(hasta: _ahora);

      expect(r, const Right<Failure, int>(2));
      expect(await ids(), ['despues']);
    });

    test('purgarVencidas borra solo lo que pasó de los 90 días', () async {
      Future<void> colar(String id, Duration hace) => db
          .into(db.notificacionesHistorial)
          .insert(
            NotificacionesHistorialCompanion.insert(
              id: id,
              tipo: 'RECORDATORIO_VISITA',
              titulo: id,
              recibidaEn: _ahora.subtract(hace),
            ),
          );
      await colar('justo', const Duration(days: 90));
      await colar('pasado', const Duration(days: 91));

      final r = await repo.purgarVencidas(ahora: _ahora);

      expect(r, const Right<Failure, int>(1));
      expect(await ids(), ['justo']);
    });
  });

  group('cuando la base falla', () {
    test('cada operación devuelve Left(FailureInesperado) y nunca lanza', () async {
      // Sin la tabla, cada sentencia falla como si la base estuviera rota.
      await db.customStatement('DROP TABLE notificacion_historial');

      final resultados = <String, Either<Failure, Object?>>{
        'registrar': await repo.registrar(_aviso('a'), ahora: _ahora),
        'marcarLeida': await repo.marcarLeida('a', ahora: _ahora),
        'marcarTodasLeidas': await repo.marcarTodasLeidas(ahora: _ahora),
        'borrarTodas': await repo.borrarTodas(),
        'purgarVencidas': await repo.purgarVencidas(ahora: _ahora),
      };

      for (final MapEntry(key: nombre, value: r) in resultados.entries) {
        expect(r.isLeft(), isTrue, reason: nombre);
        r.fold((f) => expect(f, isA<FailureInesperado>(), reason: nombre), (_) {});
      }
    });

    test('un registro cuya purga falla guarda igual el aviso', () async {
      final local = _LocalConPurgaRota(db);
      final conPurgaRota = HistorialNotificacionesRepositoryImpl(local, logger: loggerMudo());

      final r = await conPurgaRota.registrar(_aviso('a'), ahora: _ahora);

      expect(r, const Right<Failure, bool>(true));
      expect(await ids(), ['a']);
    });
  });

  group('destinos de los avisos (24C·07)', () {
    late ConsultorDestinosNotificacionDrift consultor;
    setUp(() => consultor = ConsultorDestinosNotificacionDrift(db));

    test('una agenda programada existe', () async {
      await insertarAgenda(db, agendaDe('age-1'));

      expect(await consultor.existe(const DestinoAgenda('age-1')), isTrue);
    });

    test('una agenda cumplida o no cumplida sigue teniendo su detalle', () async {
      await insertarAgenda(db, agendaDe('age-1', estado: EstadoAgenda.cumplida));
      await insertarAgenda(db, agendaDe('age-2', estado: EstadoAgenda.noCumplida));

      expect(await consultor.existe(const DestinoAgenda('age-1')), isTrue);
      expect(await consultor.existe(const DestinoAgenda('age-2')), isTrue);
    });

    test('una agenda cancelada, borrada o que no está en el teléfono ya no existe', () async {
      await insertarAgenda(db, agendaDe('cancelada', estado: EstadoAgenda.cancelada));
      await insertarAgenda(db, agendaDe('borrada', borrada: t0));

      expect(await consultor.existe(const DestinoAgenda('cancelada')), isFalse);
      expect(await consultor.existe(const DestinoAgenda('borrada')), isFalse);
      expect(await consultor.existe(const DestinoAgenda('nunca-estuvo')), isFalse);
    });
  });
}

/// Un origen de datos cuya purga siempre falla.
final class _LocalConPurgaRota extends HistorialNotificacionesLocalDataSourceDrift {
  _LocalConPurgaRota(super.db);

  @override
  Future<int> purgarVencidas({required DateTime ahora}) => Future.error(StateError('purga rota'));
}
