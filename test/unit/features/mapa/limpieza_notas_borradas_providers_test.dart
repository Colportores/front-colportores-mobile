// HU-UBI-012 / issue #509 — cuándo se limpian las notas de persona borradas hace más de 90 días: al
// abrir la app (con la DB abierta) y cada vez que se vuelve a ella; de a una limpieza por vez y con el
// reloj que no retrocede.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/hora_del_servidor.dart';
import 'package:colportores_mobile/features/auth/data/datasources/reloj_sesion_en_almacen.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_table.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/limpieza_notas_borradas_providers.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DateTime sistema;
  late RelojSesionEnMemoria reloj;

  Future<void> sembrar(String id, {DateTime? borrada, String tipo = TipoObjetivoNota.persona}) => db
      .into(db.notas)
      .insert(
        NotasCompanion.insert(
          id: id,
          targetType: tipo,
          targetId: 'objetivo-1',
          texto: 'Texto de $id',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          deletedAt: Value(borrada),
        ),
      );

  Future<List<String>> ids() async =>
      [for (final f in await db.select(db.notas).get()) f.id]..sort();

  /// La última hora que dijo el servidor en un push o un pull.
  Future<void> servidorDijo(DateTime hora) => HoraDelServidorEnDb(() => db).registrar(hora);

  Future<void> asentar() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

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

  ProviderContainer armar({bool conDb = true}) {
    final c = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(conDb ? db : null)),
        relojSesionProvider.overrideWithValue(reloj),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    sistema = DateTime.utc(2027, 1, 25, 9);
    reloj = RelojSesionEnMemoria(sistema: () => sistema);
  });
  tearDown(() => db.close());

  group('limpiezaNotasBorradasProvider', () {
    test('dada una nota borrada hace más de 90 días, cuando se abre la app, se borra', () async {
      await sembrar('vieja', borrada: DateTime.utc(2026, 10, 26, 14, 20));
      await sembrar('reciente', borrada: DateTime.utc(2026, 12, 1));
      await sembrar('activa');
      await servidorDijo(sistema);
      final c = armar();

      final lectura = c.listen(limpiezaNotasBorradasProvider, (_, _) {});
      await asentar();

      expect(await ids(), ['activa', 'reciente']);
      lectura.close();
    });

    test(
      'dado que la app vuelve del fondo, limpia otra vez lo que venció mientras tanto',
      () async {
        await sembrar('a', borrada: DateTime.utc(2026, 11, 1));
        await servidorDijo(sistema);
        final c = armar();
        final lectura = c.listen(limpiezaNotasBorradasProvider, (_, _) {});
        await asentar();
        expect(await ids(), ['a']);

        // Pasan los días con el teléfono en el bolsillo: la nota cumple sus 90 días.
        sistema = DateTime.utc(2027, 2, 5);
        await servidorDijo(sistema);
        volverALaApp();
        await asentar();

        expect(await ids(), isEmpty);
        lectura.close();
      },
    );

    test('dado que se vuelve a la app tras cerrar la pantalla principal, ya no limpia', () async {
      final c = armar();
      final lectura = c.listen(limpiezaNotasBorradasProvider, (_, _) {});
      await asentar();
      lectura.close();
      await asentar();

      await sembrar('vieja', borrada: DateTime.utc(2025, 1, 1));
      volverALaApp();
      await asentar();

      expect(await ids(), ['vieja']);
    });

    test('dada una hora del teléfono que retrocede, usa la más alta que ya vio', () async {
      await sembrar('n1', borrada: DateTime.utc(2026, 10, 26, 14, 20));
      // La app ya vio el 25/01/2027 (otra apertura); la colportora atrasa el reloj al 01/12/2026.
      await reloj.ahora();
      await servidorDijo(DateTime.utc(2027, 1, 25, 9));
      sistema = DateTime.utc(2026, 12, 1);
      final c = armar();

      final lectura = c.listen(limpiezaNotasBorradasProvider, (_, _) {});
      await asentar();

      expect(await ids(), isEmpty);
      lectura.close();
    });

    test(
      'dada una fecha del teléfono adelantada, no borra lo que el servidor dice que no venció',
      () async {
        await sembrar('n1', borrada: DateTime.utc(2026, 10, 26, 14, 20));
        // El servidor habló por última vez el 15/11/2026; la colportora adelanta el teléfono a 2028.
        await servidorDijo(DateTime.utc(2026, 11, 15));
        sistema = DateTime.utc(2028, 6, 1);
        final c = armar();

        final lectura = c.listen(limpiezaNotasBorradasProvider, (_, _) {});
        await asentar();

        expect(await ids(), ['n1']);
        lectura.close();
      },
    );

    test('dado un teléfono que nunca habló con el servidor, no borra nada', () async {
      await sembrar('vieja', borrada: DateTime.utc(2025, 1, 1));
      final c = armar();

      final lectura = c.listen(limpiezaNotasBorradasProvider, (_, _) {});
      await asentar();

      expect(await ids(), ['vieja']);
      lectura.close();
    });

    test('dada una DB todavía sin abrir, no hace nada y no lanza', () async {
      await sembrar('vieja', borrada: DateTime.utc(2025, 1, 1));
      final c = armar(conDb: false);

      final lectura = c.listen(limpiezaNotasBorradasProvider, (_, _) {});
      await asentar();

      expect(await ids(), ['vieja']);
      lectura.close();
    });

    test('dada una limpieza que falla, la app sigue y no lanza', () async {
      await sembrar('vieja', borrada: DateTime.utc(2025, 1, 1));
      final c = armar();
      await db.close();

      final lectura = c.listen(limpiezaNotasBorradasProvider, (_, _) {});
      await asentar();

      // Sin excepción sin atrapar: el test no falla.
      lectura.close();
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    });
  });

  group('LimpiadorSerie', () {
    test('dados varios pedidos mientras una limpieza corre, hace una más al terminar y no dos a la '
        'vez', () async {
      var enCurso = 0;
      var maximo = 0;
      var corridas = 0;
      final compuerta = Completer<void>();
      final serie = LimpiadorSerie(() async {
        corridas++;
        enCurso++;
        if (enCurso > maximo) maximo = enCurso;
        if (corridas == 1) await compuerta.future;
        enCurso--;
      });

      final primero = serie.pedir();
      await serie.pedir();
      await serie.pedir();
      compuerta.complete();
      await primero;

      expect(corridas, 2);
      expect(maximo, 1);
    });

    test('dada una limpieza que lanza, el pedido siguiente corre igual', () async {
      var corridas = 0;
      final serie = LimpiadorSerie(() async {
        corridas++;
        if (corridas == 1) throw StateError('falla');
      });

      await expectLater(serie.pedir(), throwsStateError);
      await serie.pedir();

      expect(corridas, 2);
    });
  });
}
