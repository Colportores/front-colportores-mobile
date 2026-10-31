// HU-SYNC-006 + HU-JOR-002 (#175) — La app entera: después de preparar el espacio seguro y antes del
// permiso de notificaciones, un teléfono sin datos ve el asistente de recuperación; y si la
// recuperación deja jornadas abiertas con otra después, cada una pasa por «¿A qué hora
// terminaste?» antes de llegar a Hoy.
import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/db_local_repository_en_memoria.dart';
import '../../helpers/notificaciones_arnes.dart' as notif;
import '../../helpers/qa_jornada_sin_cerrar_250_arnes.dart' show elegirHoraQa;
import '../../helpers/recuperacion_arnes.dart';

final class _BackupMudo implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

/// El id que el login en memoria le da a `ana@example.com`.
String get _usuarioDeAna =>
    '01920000-0000-7000-8000-0000${'ana@example.com'.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0')}';

DateTime _hoy(int h, [int m = 0]) => DateTime(2026, 10, 22, h, m);

JornadaModel _abierta(String id, DateTime inicio) => JornadaModel.fromEntity(
  Jornada(
    id: id,
    colportorId: _usuarioDeAna,
    inicio: inicio,
    auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: _usuarioDeAna),
  ),
);

final _asistente = find.byKey(const Key('recuperacion_pagina'));
final _jornadasPagina = find.byKey(const Key('jornadas_por_cerrar_pagina'));
final _cerrarJornada = find.byKey(const Key('corregir_jornada_cerrar'));

/// Abre la app entera y entra con `ana@example.com`. Un `ProviderScope` nuevo cada vez: «cerrar y
/// volver a abrir la app» con el mismo [telefono] y el mismo [arnes].
Future<void> _abrirApp(
  WidgetTester tester,
  notif.Telefono telefono,
  ArnesRecuperacion arnes, {
  JornadaLocalDataSourceEnMemoria? jornadas,
  bool iniciarSesion = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(telefono.sesionGuardada),
        ...telefono.overrides,
        ...arnes.overridesDelAsistente,
        if (jornadas != null) ...[
          jornadaLocalDataSourceProvider.overrideWithValue(jornadas),
          disparadorBackupProvider.overrideWithValue(_BackupMudo()),
          relojJornadaProvider.overrideWithValue(() => _hoy(18)),
        ],
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (iniciarSesion && find.byKey(const Key('login_enviar')).evaluate().isNotEmpty) {
    await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
    await tester.ensureVisible(find.byKey(const Key('login_enviar')));
    await tester.tap(find.byKey(const Key('login_enviar')));
    // Con el asistente en pantalla hay un círculo girando: no se puede esperar a que «se asiente».
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await _asentar(tester);
}

/// Recupera con la contraseña y llega a «Tus datos están de vuelta».
Future<void> _recuperar(WidgetTester tester) async {
  await _tocar(tester, cta);
  await tester.enterText(campoContrasena, 'la-de-antes');
  await _asentar(tester);
  await _tocar(tester, cta);
  expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
}

void main() {
  late notif.Telefono telefono;
  late ArnesRecuperacion arnes;

  setUp(() {
    telefono = notif.Telefono();
    arnes = ArnesRecuperacion();
  });

  testWidgets('un teléfono sin datos ve el asistente antes que el permiso de notificaciones; '
      '«Empezar sin recuperar» sigue a la pantalla siguiente', (tester) async {
    await _abrirApp(tester, telefono, arnes);

    expect(_asistente, findsOneWidget);
    expect(notif.pedidoPagina, findsNothing);
    expect(notif.principal, findsNothing);
    expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');

    await _tocar(tester, cta2);

    expect(_asistente, findsNothing);
    expect(notif.pedidoPagina, findsOneWidget, reason: 'vista 24 va después de la 34');
    await _tocar(tester, notif.pedidoAhoraNo);
    await tester.pumpAndSettle();
    expect(notif.principal, findsOneWidget);
    expect(arnes.resuelta.usuarios, {_usuarioDeAna});
  });

  testWidgets('recuperar todo termina en «Ir a mi inicio» y sigue a la pantalla siguiente', (
    tester,
  ) async {
    await _abrirApp(tester, telefono, arnes);

    await _recuperar(tester);
    expect(_asistente, findsOneWidget);
    await _tocar(tester, cta);

    expect(_asistente, findsNothing);
    expect(notif.pedidoPagina, findsOneWidget);
    expect(arnes.resuelta.usuarios, {_usuarioDeAna});
  });

  testWidgets('cerrar y volver a abrir la app después de resolverlo: no se vuelve a ofrecer', (
    tester,
  ) async {
    await _abrirApp(tester, telefono, arnes);
    await _tocar(tester, cta2);
    await _tocar(tester, notif.pedidoAhoraNo);
    await tester.pumpAndSettle();

    await _abrirApp(tester, telefono, arnes, iniciarSesion: false);
    await tester.pumpAndSettle();

    expect(_asistente, findsNothing);
    expect(notif.principal, findsOneWidget);
  });

  testWidgets(
    'si se cierra la app a mitad de camino, sin resolver, el asistente vuelve a aparecer',
    (tester) async {
      await _abrirApp(tester, telefono, arnes);
      expect(_asistente, findsOneWidget);

      await _abrirApp(tester, telefono, arnes, iniciarSesion: false);
      await _asentar(tester);

      expect(_asistente, findsOneWidget);
      expect(arnes.resuelta.usuarios, isEmpty);
    },
  );

  testWidgets('con datos en el teléfono no se ofrece y queda anotado', (tester) async {
    arnes.lector.sinDatos = false;

    await _abrirApp(tester, telefono, arnes);
    await tester.pumpAndSettle();

    expect(_asistente, findsNothing);
    expect(notif.pedidoPagina, findsOneWidget);
    expect(arnes.resuelta.usuarios, {_usuarioDeAna});
  });

  testWidgets('si no se pudo mirar la base, la app sigue su camino sin ofrecer nada', (
    tester,
  ) async {
    arnes.lector.errorAlMirar = StateError('base ilegible');

    await _abrirApp(tester, telefono, arnes);
    await tester.pumpAndSettle();

    expect(_asistente, findsNothing);
    expect(notif.pedidoPagina, findsOneWidget);
  });

  group('HU-JOR-002: jornadas que quedaron abiertas al terminar la recuperación', () {
    testWidgets('dos abiertas el mismo día: la de las 08:00 se cierra con la hora que elige, tope '
        'las 09:00; la de las 09:00 sigue abierta y no se cierra con la hora de ahora', (
      tester,
    ) async {
      final jornadas = JornadaLocalDataSourceEnMemoria(
        iniciales: [_abierta('a', _hoy(8)), _abierta('b', _hoy(9))],
      );
      await _abrirApp(tester, telefono, arnes, jornadas: jornadas);
      await _recuperar(tester);

      await _tocar(tester, cta);

      expect(_cerrarJornada, findsOneWidget, reason: '«¿A qué hora terminaste?» (vista 21A)');
      expect(find.text('¿A qué hora terminaste?'), findsWidgets);
      expect(jornadas.jornadas.every((j) => j.fin == null), isTrue, reason: 'nada se cierra solo');

      await elegirHoraQa(tester, '08:30');
      await _tocar(tester, _cerrarJornada);
      await tester.pumpAndSettle();

      final guardadas = {for (final j in jornadas.jornadas) j.id: j};
      expect(guardadas['a']!.fin!.toLocal(), _hoy(8, 30));
      expect(guardadas['b']!.fin, isNull);
      expect(notif.pedidoPagina, findsOneWidget, reason: 'sigue la pantalla siguiente');
    });

    testWidgets('tres abiertas: se preguntan una detrás de la otra, la más vieja primero', (
      tester,
    ) async {
      final jornadas = JornadaLocalDataSourceEnMemoria(
        iniciales: [_abierta('a', _hoy(8)), _abierta('b', _hoy(9)), _abierta('c', _hoy(10))],
      );
      await _abrirApp(tester, telefono, arnes, jornadas: jornadas);
      await _recuperar(tester);
      await _tocar(tester, cta);

      expect(_cerrarJornada, findsOneWidget);
      await elegirHoraQa(tester, '08:40');
      await _tocar(tester, _cerrarJornada);
      await _asentar(tester);

      // Sigue la de las 09:00, con su propio tope.
      expect(_cerrarJornada, findsOneWidget);
      await elegirHoraQa(tester, '09:50');
      await _tocar(tester, _cerrarJornada);
      await tester.pumpAndSettle();

      final guardadas = {for (final j in jornadas.jornadas) j.id: j};
      expect(guardadas['a']!.fin!.toLocal(), _hoy(8, 40));
      expect(guardadas['b']!.fin!.toLocal(), _hoy(9, 50));
      expect(guardadas['c']!.fin, isNull);
      expect(notif.pedidoPagina, findsOneWidget);
    });

    testWidgets('una sola abierta: no se pregunta nada', (tester) async {
      final jornadas = JornadaLocalDataSourceEnMemoria(iniciales: [_abierta('a', _hoy(8))]);
      await _abrirApp(tester, telefono, arnes, jornadas: jornadas);
      await _recuperar(tester);

      await _tocar(tester, cta);
      await tester.pumpAndSettle();

      expect(_jornadasPagina, findsNothing);
      expect(_cerrarJornada, findsNothing);
      expect(notif.pedidoPagina, findsOneWidget);
    });

    testWidgets(
      'con «Empezar sin recuperar» también se revisan las abiertas, sin cerrar nada solo',
      (tester) async {
        final jornadas = JornadaLocalDataSourceEnMemoria(
          iniciales: [_abierta('a', _hoy(8)), _abierta('b', _hoy(9))],
        );
        await _abrirApp(tester, telefono, arnes, jornadas: jornadas);

        await _tocar(tester, cta2);

        expect(_cerrarJornada, findsOneWidget);
        expect(jornadas.jornadas.every((j) => j.fin == null), isTrue);
      },
    );
  });
}
