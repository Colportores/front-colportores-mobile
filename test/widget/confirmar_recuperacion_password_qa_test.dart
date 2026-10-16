// QA de la vista 15 «Nueva contraseña» (HU-AUTH-005, #224): casos límite que la suite de la vista
// no cubre (cierre de sesión que falla al terminar, «Listo» del teclado con el botón deshabilitado)
// y la matriz de tamaños del QA (360x640 con el texto al 200 % y 412x915) sobre cada estado.
import 'dart:async';
import 'dart:math' as math;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resultado_cierre_sesion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/confirmar_recuperacion_password_use_case.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/confirmar_recuperacion_password_page.dart'
    show TextosConfirmacionRecuperacion;
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:dartz/dartz.dart' show Either, Left, Unit;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _email = 'ana@example.com';

late RecuperacionPasswordEnMemoria _recuperacion;
late DbLocalRepositoryEnMemoria _dbLocal;
late AuthRemoteDataSourceEnMemoria _auth;

Finder _k(String k) => find.byKey(Key('confirmar_recuperacion_$k'));
Finder get _guardar => _k('guardar');
const _exito = 'Contraseña actualizada. Iniciá sesión.';

/// Repositorio real salvo que el cierre de sesión falla como se le pida.
class _RepoCierreRoto extends Fake implements AuthRepository {
  _RepoCierreRoto(this._real, this._cierre);

  final AuthRepositoryImpl _real;
  final Future<Either<Failure, ResultadoCierreSesion>> Function() _cierre;

  @override
  Future<Either<Failure, Sesion>> iniciarSesion({
    required String email,
    required String password,
  }) => _real.iniciarSesion(email: email, password: password);

  @override
  Stream<MotivoExpiracion> get expiraciones => _real.expiraciones;

  @override
  Future<Either<Failure, Sesion?>> sesionActual() => _real.sesionActual();

  @override
  Future<Either<Failure, ResultadoCierreSesion>> cerrarSesion() => _cierre();

  @override
  Future<Either<Failure, Unit>> reintentarRevocacionPendiente() =>
      _real.reintentarRevocacionPendiente();
}

Future<ProviderContainer> _montar(
  WidgetTester tester, {
  EnlaceRecuperacion enlace = EnlaceRecuperacion.valido,
  bool conSesion = false,
  Future<Either<Failure, ResultadoCierreSesion>> Function()? cierre,
}) async {
  final local = AuthLocalDataSourceEnMemoria();
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(_auth),
      authLocalDataSourceProvider.overrideWithValue(local),
      recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(_recuperacion),
      dbLocalRepositoryProvider.overrideWithValue(_dbLocal),
      if (cierre != null)
        authRepositoryProvider.overrideWithValue(
          _RepoCierreRoto(AuthRepositoryImpl(_auth, local), cierre),
        ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  if (conSesion) {
    await container
        .read(sesionProvider.notifier)
        .iniciarSesion(email: _email, password: 'Vieja1234');
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  _recuperacion.simularEnlace(enlace);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _completar(WidgetTester tester, String nueva, {String? repetida}) async {
  await tester.enterText(_k('nueva'), nueva);
  await tester.enterText(_k('repetida'), repetida ?? nueva);
  await tester.pump();
}

Future<void> _tocarGuardar(WidgetTester tester) async {
  await tester.ensureVisible(_guardar);
  await tester.tap(_guardar);
  await tester.pumpAndSettle();
}

void _pantalla(WidgetTester tester, Size tam, {double texto = 1.0}) {
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() {
    _recuperacion = RecuperacionPasswordEnMemoria(passwordActual: 'Vieja1234');
    _dbLocal = DbLocalRepositoryEnMemoria();
    _auth = AuthRemoteDataSourceEnMemoria(credenciales: const {_email: 'Vieja1234'});
  });

  group('QA #224 — al terminar, con la contraseña ya cambiada', () {
    // QA #224: si `cerrarSesion()` lanza en `_terminar`, `_guardando` queda en true: spinner eterno
    // y atrás bloqueado aunque la contraseña ya cambió (no hay try/finally ni setState).
    testWidgets('si cerrar la sesión de la app lanza, igual se ve el éxito y nada queda trabado', (
      tester,
    ) async {
      await _montar(tester, conSesion: true, cierre: () async => throw StateError('boom'));
      await _completar(tester, 'NuevaClave1');

      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.pumpAndSettle();

      expect(find.text(_exito), findsOneWidget, reason: 'la contraseña ya cambió');
      expect(_k('guardando'), findsNothing, reason: 'sin spinner eterno');
      expect(find.byKey(const Key('confirmar_recuperacion_exito_ir_al_login')), findsOneWidget);
    });

    testWidgets(
      'si la sesión local no se pudo borrar (Left), se ve el éxito con el aviso de que la sesión '
      'sigue abierta y la salida no manda a un login que no se ve',
      (tester) async {
        final container = await _montar(
          tester,
          conSesion: true,
          cierre: () async => const Left(FailureInesperado()),
        );
        await _completar(tester, 'NuevaClave1');
        await _tocarGuardar(tester);

        // Decisión de Cristian (02/10): avisa con salida en vez de decir «Iniciá sesión».
        expect(find.text(TextosConfirmacionRecuperacion.exitoSinCerrarSesion), findsOneWidget);
        expect(find.text(_exito), findsNothing);
        expect(_k('guardando'), findsNothing);
        final ir = find.byKey(const Key('confirmar_recuperacion_exito_ir_al_login'));
        expect(find.descendant(of: ir, matching: find.text('Volver al inicio')), findsOneWidget);
        await tester.ensureVisible(ir);
        await tester.tap(ir);
        await tester.pumpAndSettle();
        expect(
          find.text(TextosConfirmacionRecuperacion.exitoSinCerrarSesion),
          findsNothing,
          reason: 'no queda trabado en la pantalla de éxito',
        );
        // Documenta el estado real: la sesión local sigue.
        expect(container.read(sesionProvider).value, isNotNull);
      },
    );
  });

  group('QA #224 — «Listo» del teclado', () {
    // QA #224: con «Guardar» deshabilitado, «Listo» no hace nada ni avisa (contraseña válida y la
    // repetida vacía): el usuario no sabe por qué no pasa nada.
    testWidgets('con la repetida vacía, «Listo» avisa qué falta', (tester) async {
      await _montar(tester);
      await tester.enterText(_k('nueva'), 'NuevaClave1');
      await tester.pump();
      String textos() => tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join('|');
      final antes = textos();

      await tester.tap(_k('repetida'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(_recuperacion.actualizaciones, isEmpty);
      expect(textos(), isNot(antes), reason: 'algún aviso de qué falta');
    });

    testWidgets('«Listo» con todo válido guarda una sola vez', (tester) async {
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_recuperacion.actualizaciones, ['NuevaClave1']);
      expect(find.text(_exito), findsOneWidget);
    });
  });

  group('QA #224 — entradas', () {
    testWidgets('solo espacios (largo de sobra): no se habilita y dice qué falta', (tester) async {
      await _montar(tester);
      await _completar(tester, ' ' * 12);
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNull);
      expect(find.textContaining('✕'), findsWidgets);
    });

    testWidgets('emoji y símbolos: se acepta tal cual, sin recortar', (tester) async {
      await _montar(tester);
      await _completar(tester, 'Ñandú_2026 😀 !A');
      expect(tester.widget<FilledButton>(_guardar).onPressed, isNotNull);
      await _tocarGuardar(tester);
      expect(_recuperacion.actualizaciones, ['Ñandú_2026 😀 !A']);
    });

    testWidgets('los params no muestran la contraseña en toString (privacidad)', (tester) async {
      const p = ConfirmarRecuperacionPasswordParams(nueva: 'Secreta1x', repetida: 'Secreta1x');
      expect(p.toString(), isNot(contains('Secreta1x')));
    });
  });

  group('QA #224 — matriz de tamaños por estado', () {
    Future<void> recorrer(WidgetTester tester, {required bool grande}) async {
      final handle = tester.ensureSemantics();
      // A01: formulario vacío.
      await _montar(tester);
      await _guias(tester);
      // A03: débil, y la repetida distinta.
      await _completar(tester, 'lucia', repetida: 'otra');
      await _guias(tester);
      // A04: guardando.
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _completar(tester, 'NuevaClave1');
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.pump();
      expect(_k('guardando'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester.takeException(), isNull);
      _recuperacion.demoraAlActualizar!.complete();
      // A09: éxito.
      await tester.pumpAndSettle();
      expect(find.text(_exito), findsOneWidget);
      await _guias(tester);
      handle.dispose();
    }

    testWidgets('360x640 con el texto al 200 %: A01, A03, A04 y A09', (tester) async {
      _pantalla(tester, const Size(360, 640), texto: 2.0);
      await recorrer(tester, grande: true);
    });

    testWidgets('412x915: A01, A03, A04 y A09', (tester) async {
      _pantalla(tester, const Size(412, 915));
      await recorrer(tester, grande: false);
    });

    testWidgets('15-A04 guardando: «Guardando…» es blanco sobre el azul del botón', (tester) async {
      _pantalla(tester, const Size(412, 915));
      await _montar(tester);
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _completar(tester, 'NuevaClave1');
      await tester.tap(_guardar);
      await tester.pump();
      final texto = find.descendant(of: _guardar, matching: find.text('Guardando…'));
      final estilo = DefaultTextStyle.of(
        tester.element(texto),
      ).style.merge(tester.widget<Text>(texto).style);
      final primario = Theme.of(tester.element(texto)).colorScheme;
      expect(estilo.color, primario.onPrimary);
      expect(_contraste(estilo.color!, primario.primary), greaterThanOrEqualTo(4.5));
      _recuperacion.demoraAlActualizar!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('al 200 %: botones con radio 16 y «Mostrar contraseña» pasa a ícono con tooltip', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 640), texto: 2.0);
      await _montar(tester);
      expect(find.text('Mostrar contraseña'), findsNothing);
      expect(find.byTooltip('Mostrar contraseña'), findsNWidgets(2));
      await tester.enterText(_k('nueva'), 'NuevaClave1');
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Mostrar contraseña').first);
      await tester.tap(find.byTooltip('Mostrar contraseña').first);
      await tester.pump();
      expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
      final boton = tester.widget<FilledButton>(_guardar);
      final forma = boton.style!.shape!.resolve({}) as RoundedRectangleBorder;
      expect(forma.borderRadius, BorderRadius.circular(16));
      expect(tester.takeException(), isNull);
    });

    // 15-A04 (decisión de Cristian, 02/10): el canvas atenúa el formulario al 55 %, que da 2,4:1 en
    // las etiquetas; se sube la opacidad hasta llegar a 4,5:1.
    testWidgets('15-A04 guardando: el contraste de las etiquetas llega a 4,5:1', (tester) async {
      _pantalla(tester, const Size(412, 915));
      final handle = tester.ensureSemantics();
      await _montar(tester);
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _completar(tester, 'NuevaClave1');
      await tester.tap(_guardar);
      await tester.pump();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      _recuperacion.demoraAlActualizar!.complete();
      await tester.pumpAndSettle();
      handle.dispose();
    });

    for (final (nombre, tam, texto) in [
      ('360x640 al 200 %', const Size(360, 640), 2.0),
      ('412x915', const Size(412, 915), 1.0),
    ]) {
      testWidgets('$nombre: A05 error, A08 sin conexión, vencido y enlace sin conexión', (
        tester,
      ) async {
        _pantalla(tester, tam, texto: texto);
        final handle = tester.ensureSemantics();
        await _montar(tester);
        await _completar(tester, 'NuevaClave1');
        _recuperacion.fallaAlActualizar = const CredencialesInvalidasException();
        await _tocarGuardar(tester);
        expect(find.text('No pudimos guardar la contraseña. Probá de nuevo.'), findsOneWidget);
        await _guias(tester);

        _recuperacion.fallaAlActualizar = null;
        _recuperacion.simularSinConexion = true;
        await _tocarGuardar(tester);
        expect(find.text('Sin conexión'), findsWidgets);
        expect(find.text('No pudimos guardar la contraseña. Probá de nuevo.'), findsNothing);
        await _guias(tester);
        expect(_texto(tester, 'nueva'), 'NuevaClave1', reason: 'no pierde lo escrito');
        handle.dispose();
      });

      for (final enlace in [EnlaceRecuperacion.vencido, EnlaceRecuperacion.sinConexion]) {
        testWidgets('$nombre: enlace ${enlace.name}', (tester) async {
          _pantalla(tester, tam, texto: texto);
          final handle = tester.ensureSemantics();
          await _montar(tester, enlace: enlace);
          await _guias(tester);
          handle.dispose();
        });
      }
    }
  });
}

String _texto(WidgetTester tester, String campo) =>
    tester.widget<TextField>(_k(campo)).controller!.text;

double _luminancia(Color c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _contraste(Color a, Color b) {
  final la = _luminancia(a);
  final lb = _luminancia(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
