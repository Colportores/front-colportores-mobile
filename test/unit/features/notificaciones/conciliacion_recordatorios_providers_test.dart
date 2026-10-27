// HU-NOT-005 / issue #416 — cuándo se guardan en el historial los recordatorios que sonaron: al
// abrir la app (cuando ya hay sesión y DB abierta) y cada vez que se vuelve a ella; de a una
// revisión por vez.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/marca_conciliacion_recordatorios_impl.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/conciliacion_recordatorios_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/campo_falsos.dart';
import '../../../helpers/logger_mudo.dart';

class _SesionFija extends SesionNotifier {
  _SesionFija(this._sesion);

  final Sesion? _sesion;

  @override
  Future<Sesion?> build() async => _sesion;
}

class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;

  /// Se abre la DB con el provider ya escuchado.
  void publicar(AppDatabase db) => state = db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late MarcaConciliacionRecordatoriosEnMemoria marca;
  late DateTime ahora;

  final sesion = Sesion(
    usuarioId: 'col-1',
    email: 'col@colportores.app',
    accessToken: 'jwt',
    expiraEn: DateTime.utc(2030),
  );

  Future<void> agendaConAviso(String id, DateTime visita) => insertarAgenda(
    db,
    Agenda(
      id: id,
      espacioId: 'esp-1',
      espacioPersonaId: 'ep-1',
      tipo: TipoAgenda.entrevista,
      fechaProgramada: visita,
      colportorId: 'col-1',
      auditoria: auditoriaDe(creada: DateTime.utc(2026, 10, 26)),
    ),
  );

  Future<int> filasDelHistorial() async =>
      (await db.select(db.notificacionesHistorial).get()).length;

  // Deja correr lo asíncrono (Drift y Riverpod usan microtareas y temporizadores).
  Future<void> asentar() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  // Sale de la app y vuelve (los ajustes del teléfono y de regreso).
  void volverALaApp() {
    for (final estado in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(estado);
    }
  }

  ProviderContainer armar({bool sinSesion = false, bool conDb = true}) {
    final c = ProviderContainer(
      overrides: [
        sesionProvider.overrideWith(() => _SesionFija(sinSesion ? null : sesion)),
        dbLocalProvider.overrideWith(() => _DbFija(conDb ? db : null)),
        marcaConciliacionRecordatoriosProvider.overrideWithValue(marca),
        relojVisitaProvider.overrideWithValue(() => ahora),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    await sembrarCasa(db);
    marca = MarcaConciliacionRecordatoriosEnMemoria(DateTime.utc(2026, 10, 27, 12));
    ahora = DateTime.utc(2026, 10, 27, 15, 10);
  });
  tearDown(() => db.close());

  test('dado un recordatorio que sonó con la app cerrada, cuando la pantalla principal '
      'aparece, queda en el historial', () async {
    await agendaConAviso('age-1', DateTime.utc(2026, 10, 27, 15));
    final c = armar();

    final lectura = c.listen(conciliacionRecordatoriosProvider, (_, _) {});
    await asentar();

    expect(await filasDelHistorial(), 1);
    expect(marca.marca, ahora);
    lectura.close();
  });

  test('dado que la app vuelve del fondo, cuando sonó otro recordatorio, también se guarda; '
      'volver otra vez no lo duplica', () async {
    await agendaConAviso('age-1', DateTime.utc(2026, 10, 27, 15));
    await agendaConAviso('age-2', DateTime.utc(2026, 10, 27, 17));
    final c = armar();
    final lectura = c.listen(conciliacionRecordatoriosProvider, (_, _) {});
    await asentar();
    expect(await filasDelHistorial(), 1);

    // Pasan las 16:30: suena el de las 17:00.
    ahora = DateTime.utc(2026, 10, 27, 16, 40);
    volverALaApp();
    await asentar();
    expect(await filasDelHistorial(), 2);

    volverALaApp();
    volverALaApp();
    await asentar();
    expect(await filasDelHistorial(), 2);
    lectura.close();
  });

  test('dado que se sale de la pantalla principal, volver a la app ya no revisa nada', () async {
    final c = armar();
    final lectura = c.listen(conciliacionRecordatoriosProvider, (_, _) {});
    await asentar();
    lectura.close();
    await asentar();
    await agendaConAviso('age-1', DateTime.utc(2026, 10, 27, 17));

    ahora = DateTime.utc(2026, 10, 27, 16, 40);
    volverALaApp();
    await asentar();

    expect(await filasDelHistorial(), 0);
  });

  test('dado que todavía no hay DB abierta, no revisa; cuando se abre, sí', () async {
    await agendaConAviso('age-1', DateTime.utc(2026, 10, 27, 15));
    final c = ProviderContainer(
      overrides: [
        sesionProvider.overrideWith(() => _SesionFija(sesion)),
        dbLocalProvider.overrideWith(() => _DbFija(null)),
        marcaConciliacionRecordatoriosProvider.overrideWithValue(marca),
        relojVisitaProvider.overrideWithValue(() => ahora),
      ],
    );
    addTearDown(c.dispose);
    final lectura = c.listen(conciliacionRecordatoriosProvider, (_, _) {});
    await asentar();
    expect(marca.marca, DateTime.utc(2026, 10, 27, 12));

    (c.read(dbLocalProvider.notifier) as _DbFija).publicar(db);
    await asentar();

    expect(await filasDelHistorial(), 1);
    lectura.close();
  });

  test('dado que no hay sesión, no revisa', () async {
    await agendaConAviso('age-1', DateTime.utc(2026, 10, 27, 15));
    final c = armar(sinSesion: true);
    final lectura = c.listen(conciliacionRecordatoriosProvider, (_, _) {});
    await asentar();

    expect(await filasDelHistorial(), 0);
    lectura.close();
  });

  group('ConciliadorSerie', () {
    test('dado un pedido mientras otra revisión corre, hace otra al terminar y nunca dos a la '
        'vez', () async {
      final puerta = Completer<void>();
      var corriendo = 0;
      var maximo = 0;
      var veces = 0;
      final serie = ConciliadorSerie(() async {
        veces++;
        corriendo++;
        if (corriendo > maximo) maximo = corriendo;
        if (veces == 1) await puerta.future;
        corriendo--;
      });

      final primera = serie.pedir();
      await serie.pedir();
      await serie.pedir();
      expect(veces, 1);

      puerta.complete();
      await primera;

      expect(veces, 2, reason: 'los pedidos juntados se atienden con una sola revisión más');
      expect(maximo, 1);
    });

    test('dado que una revisión lanza, la serie queda libre para la siguiente', () async {
      var veces = 0;
      final serie = ConciliadorSerie(() async {
        veces++;
        if (veces == 1) throw StateError('falló');
      });

      await expectLater(serie.pedir(), throwsStateError);
      await serie.pedir();

      expect(veces, 2);
    });
  });
}
