// QA de la vista 15 con la sesión abierta (HU-AUTH-005, #277). Complementa
// `confirmar_recuperacion_password_page_test.dart` (el grupo «con la sesión abierta») y
// `qa_vista15_a06_test.dart` (A06 sin sesión): A06 y el aviso de enlace sin conexión con la sesión
// abierta en los tamaños del checklist (360x640 y 412x915, texto al 100 % y al 200 %), el escenario
// de la HU con su título literal, el arranque en frío con la sesión todavía sin leer, el atrás de la
// flecha del aviso y el vencimiento de la sesión con A06 en pantalla. La app entera, con los fakes.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _email = 'ana@example.com';
const _titulo = TextosConfirmacionRecuperacion.vencido;
const _rotulo = TextosConfirmacionRecuperacion.rotuloEnlaceNoValido;

final _salida = find.byKey(const Key('confirmar_recuperacion_ir_al_login'));
final _inicio = find.byKey(const Key('inicio_principal'));
final _login = find.byKey(const Key('login_enviar'));

/// La lectura de la sesión guardada queda esperando hasta que el test la suelta: el arranque en
/// frío con el enlace, cuando el almacén seguro todavía no contestó.
final class _LocalConDemora implements AuthLocalDataSource {
  _LocalConDemora(this._real, this.lectura);

  final AuthLocalDataSource _real;
  final Completer<void> lectura;

  @override
  Future<SesionModel?> leerSesion() async {
    await lectura.future;
    return _real.leerSesion();
  }

  @override
  Future<void> guardarSesion(SesionModel sesion) => _real.guardarSesion(sesion);

  @override
  Future<void> borrarSesion() => _real.borrarSesion();
}

void _pantalla(WidgetTester tester, Size tam, double texto) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Relación de contraste de WCAG entre dos colores opacos.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// Sin las fuentes del proyecto `flutter_test` pinta cajas: se cargan para mirar las capturas.
Future<void> _cargarFuentes(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final loader = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
  // Los íconos del SDK (el reloj de arena de A06, la flecha del aviso): sin esto salen cajas.
  final raiz = Platform.environment['FLUTTER_ROOT'];
  final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (raiz != null && iconos.existsSync()) {
    final bytes = iconos.readAsBytesSync();
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
});

/// La ruta de la contraseña nueva a pantalla completa, fuera del repo (`.dart_tool` es de git).
Future<void> _capturar(WidgetTester tester, String nombre) => tester.runAsync(() async {
  final render = tester.renderObject<RenderRepaintBoundary>(
    find
        .ancestor(
          of: find.byType(ConfirmarRecuperacionPasswordPage),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  final img = await render.toImage();
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
  File('${dir.path}/277_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
});

late RecuperacionPasswordEnMemoria _recuperacion;
late AuthRemoteDataSourceEnMemoria _auth;

List<Override> _overrides(AuthLocalDataSource local) => [
  authRemoteDataSourceProvider.overrideWithValue(_auth),
  authLocalDataSourceProvider.overrideWithValue(local),
  recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(_recuperacion),
  dbLocalRepositoryProvider.overrideWithValue(_baseLista()),
];

/// La base local ya preparada, con el envoltorio de la contraseña de la cuenta.
DbLocalRepositoryEnMemoria _baseLista() {
  final base = dbLocalYaPreparada();
  base.envoltorio = (dek: base.dekEnAlmacen!, password: 'Vieja1234');
  return base;
}

/// La app con la sesión abierta (o sin ella) y [enlace] llegando del correo.
Future<ProviderContainer> _montar(
  WidgetTester tester, {
  required EnlaceRecuperacion enlace,
  bool conSesion = true,
}) async {
  final container = ProviderContainer(overrides: _overrides(AuthLocalDataSourceEnMemoria()));
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

void main() {
  setUp(() {
    _recuperacion = RecuperacionPasswordEnMemoria(passwordActual: 'Vieja1234');
    _auth = AuthRemoteDataSourceEnMemoria(credenciales: const {_email: 'Vieja1234'});
  });

  group('QA #277 — con la sesión abierta, en los tamaños del checklist', () {
    for (final enlace in [EnlaceRecuperacion.vencido, EnlaceRecuperacion.sinConexion]) {
      for (final (tam, texto) in const [
        (Size(360, 640), 1.0),
        (Size(360, 640), 2.0),
        (Size(412, 915), 1.0),
        (Size(412, 915), 2.0),
      ]) {
        testWidgets('${enlace.name} a ${tam.width.toInt()}x${tam.height.toInt()} con el texto al '
            '${(texto * 100).toInt()} %: «Ir a mi inicio» entero y alcanzable, sin overflow y '
            'accesible', (tester) async {
          _pantalla(tester, tam, texto);
          final semantica = tester.ensureSemantics();
          await _cargarFuentes(tester);
          await _montar(tester, enlace: enlace);

          expect(tester.takeException(), isNull);
          if (enlace == EnlaceRecuperacion.vencido) {
            expect(find.text(_rotulo), findsOneWidget);
            expect(find.text(_titulo), findsOneWidget);
            expect(find.text('Solicitar un enlace nuevo'), findsOneWidget);
          } else {
            expect(find.byKey(const Key('confirmar_recuperacion_sin_conexion')), findsOneWidget);
          }
          expect(
            find.descendant(of: _salida, matching: find.text('Ir a mi inicio')),
            findsOneWidget,
          );
          expect(find.text('Volver al login'), findsNothing);

          final nombre =
              '${enlace.name}_con_sesion_${tam.width.toInt()}x${tam.height.toInt()}_$texto';
          await _capturar(tester, '${nombre}_arriba');
          await tester.ensureVisible(_salida);
          await tester.pumpAndSettle();
          final rect = tester.getRect(_salida);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(tam.width));
          expect(rect.bottom, lessThanOrEqualTo(tam.height));
          expect(rect.height, greaterThanOrEqualTo(48));
          // El texto de la salida cabe en el botón (sin cortarse con el texto al 200 %).
          final texto0 = tester.getRect(find.text('Ir a mi inicio'));
          expect(texto0.left, greaterThanOrEqualTo(rect.left));
          expect(texto0.right, lessThanOrEqualTo(rect.right));

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          if (texto >= 2 || enlace == EnlaceRecuperacion.sinConexion) {
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          } else {
            // A 10 px la guía de Flutter mide el borde suavizado de las letras y da ~1,4 aunque el
            // color cumple: el rótulo se mide por sus colores (igual que en `qa_vista15_a06_test`).
            final fondo = Theme.of(
              tester.element(find.byType(Scaffold).last),
            ).scaffoldBackgroundColor;
            for (final t in [_rotulo, _titulo]) {
              final color = tester.widget<Text>(find.text(t)).style!.color!;
              expect(_contraste(color, fondo), greaterThanOrEqualTo(4.5), reason: t);
            }
          }

          await _capturar(tester, '${nombre}_abajo');
          semantica.dispose();
        });
      }
    }

    testWidgets('sin sesión, A06 a 360x640: la captura de comparación con «Volver al login»', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 640), 1.0);
      await _cargarFuentes(tester);
      await _montar(tester, enlace: EnlaceRecuperacion.vencido, conSesion: false);

      expect(find.text('Volver al login'), findsOneWidget);
      expect(find.text('Ir a mi inicio'), findsNothing);
      await _capturar(tester, 'vencido_sin_sesion_360x640_1.0');
    });
  });

  group('QA #277 — escenarios de la HU-AUTH-005', () {
    testWidgets('Escenario: Edge -enlace no válido con la sesión abierta. Dado que tengo la sesión '
        'abierta en este teléfono, cuando abro un enlace de recuperación que ya no sirve, entonces '
        'la UI muestra la misma pantalla única «ENLACE NO VÁLIDO» y ofrece «Solicitar un enlace '
        'nuevo» e «Ir a mi inicio», en lugar de «Volver al login»', (tester) async {
      final container = await _montar(tester, enlace: EnlaceRecuperacion.vencido);
      expect(container.read(sesionProvider).value, isNotNull, reason: 'la sesión está abierta');

      expect(find.text('ENLACE NO VÁLIDO'), findsOneWidget);
      expect(
        find.text('Este enlace ya no sirve: venció o ya se usó. Solicitá uno nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Solicitar un enlace nuevo'), findsOneWidget);
      expect(find.text('Ir a mi inicio'), findsOneWidget);
      expect(find.text('Volver al login'), findsNothing);
      // La misma pantalla única: ni «venció» solo ni «ya fue utilizado».
      expect(find.textContaining('expiró'), findsNothing);
      expect(find.textContaining('ya fue utilizado'), findsNothing);
    });

    testWidgets('Escenario: Error -token reutilizado, con la sesión abierta. Dado que ya usé este '
        'enlace, cuando vuelvo a abrirlo, entonces la misma pantalla única, sin marca de un cambio '
        'anterior, y la salida dice «Ir a mi inicio»', (tester) async {
      await _montar(tester, enlace: EnlaceRecuperacion.vencido);

      // «Volver al login» solo si no hay sesión: acá hay una y la salida lleva al inicio.
      expect(find.descendant(of: _salida, matching: find.text('Ir a mi inicio')), findsOneWidget);
      // El teléfono no guarda ninguna marca: no hay sesión de recuperación que soltar.
      expect(_recuperacion.haySesionDeRecuperacion, isFalse);
      await tester.tap(_salida);
      await tester.pumpAndSettle();
      expect(_inicio, findsOneWidget);
      expect(_recuperacion.abandonos, 0);
    });
  });

  group('QA #277 — casos límite', () {
    testWidgets('dado el aviso de enlace sin conexión con la sesión abierta, cuando se toca la '
        'flecha de atrás o el atrás del sistema, entonces vuelve al inicio con la sesión intacta '
        'y sin soltar nada', (tester) async {
      final container = await _montar(tester, enlace: EnlaceRecuperacion.sinConexion);
      expect(find.byTooltip('Volver'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirmar_recuperacion_atras')));
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
      expect(_inicio, findsOneWidget);
      expect(container.read(sesionProvider).value, isNotNull);
      expect(_recuperacion.abandonos, 0);

      // Se vuelve a abrir el enlace desde el correo (sigue sirviendo) y el atrás del sistema sale
      // igual.
      _recuperacion.simularEnlace(EnlaceRecuperacion.sinConexion);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirmar_recuperacion_sin_conexion')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
      expect(_inicio, findsOneWidget);
      expect(container.read(sesionProvider).value, isNotNull);
      expect(_recuperacion.abandonos, 0);
    });

    testWidgets(
      'dado A06 con la sesión abierta, cuando el servidor revoca la sesión con la pantalla '
      'a la vista, entonces queda el login con el aviso, sin excepciones ni pantalla trabada',
      (tester) async {
        await _montar(tester, enlace: EnlaceRecuperacion.vencido);
        expect(find.text('Ir a mi inicio'), findsOneWidget);

        _auth.simularExpiracion(MotivoExpiracion.revocada);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
        expect(_login, findsOneWidget);
        expect(find.text(const FailureSesionRevocada().mensaje), findsOneWidget);
        expect(_inicio, findsNothing);
      },
    );

    testWidgets('dado el arranque en frío con el enlace y la sesión guardada, cuando el almacén '
        'todavía no la leyó, entonces A06 ya se ve y, al leerla, la salida pasa a «Ir a mi inicio» '
        'y lleva al inicio', (tester) async {
      final guardada = AuthLocalDataSourceEnMemoria();
      // Una primera vida de la app deja la sesión guardada.
      final previo = ProviderContainer(overrides: _overrides(guardada));
      await previo.read(sesionProvider.future);
      await previo
          .read(sesionProvider.notifier)
          .iniciarSesion(email: _email, password: 'Vieja1234');
      expect(await guardada.leerSesion(), isNotNull);
      previo.dispose();

      final lectura = Completer<void>();
      final container = ProviderContainer(
        overrides: _overrides(_LocalConDemora(guardada, lectura)),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const ColportoresApp()),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'sesión sin leer');

      _recuperacion.simularEnlace(EnlaceRecuperacion.vencido);
      await tester.pump();
      await tester.pump();
      expect(find.text(_titulo), findsOneWidget, reason: 'A06 no espera a la sesión');
      // Mientras la sesión no se leyó no se sabe que hay una: la salida todavía dice el texto sin
      // sesión (el rótulo se rehace con `ref.watch` cuando llega).
      expect(find.text('Volver al login'), findsOneWidget);

      lectura.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(_titulo), findsOneWidget);
      expect(find.descendant(of: _salida, matching: find.text('Ir a mi inicio')), findsOneWidget);
      expect(find.text('Volver al login'), findsNothing);

      await tester.tap(_salida);
      await tester.pumpAndSettle();
      expect(_inicio, findsOneWidget);
      expect(container.read(sesionProvider).value, isNotNull);
    });

    testWidgets('dado el arranque en frío con el enlace y sin sesión guardada, cuando termina de '
        'leer, entonces la salida sigue diciendo «Volver al login» y lleva al login', (
      tester,
    ) async {
      final lectura = Completer<void>();
      final container = ProviderContainer(
        overrides: _overrides(_LocalConDemora(AuthLocalDataSourceEnMemoria(), lectura)),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const ColportoresApp()),
      );
      await tester.pump();
      _recuperacion.simularEnlace(EnlaceRecuperacion.vencido);
      await tester.pump();
      await tester.pump();
      expect(find.text(_titulo), findsOneWidget);

      lectura.complete();
      await tester.pumpAndSettle();
      expect(find.descendant(of: _salida, matching: find.text('Volver al login')), findsOneWidget);
      expect(find.text('Ir a mi inicio'), findsNothing);

      await tester.tap(_salida);
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
    });

    testWidgets('dado A06 con la sesión abierta, cuando se toca «Solicitar un enlace nuevo», '
        'entonces abre el pedido sin tocar la sesión y sin soltar nada', (tester) async {
      final container = await _montar(tester, enlace: EnlaceRecuperacion.vencido);

      await tester.tap(find.byKey(const Key('confirmar_recuperacion_pedir_otro')));
      await tester.pumpAndSettle();

      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
      expect(container.read(sesionProvider).value, isNotNull);
      expect(_recuperacion.abandonos, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
