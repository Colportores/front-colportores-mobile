// QA de la vista 15 «Nueva contraseña» (HU-AUTH-005, #224), seguimiento del 02/10. Complementa
// `confirmar_recuperacion_password_page_test.dart` y `confirmar_recuperacion_password_qa_test.dart`:
// recorre cada artboard del canvas (A01 a A09 más los estados nuevos de las decisiones del 02/10)
// con las cuatro guías de accesibilidad en 360x640 (texto 1.0 y 2.0) y 412x915, prueba las entradas
// límite (largo en caracteres visibles, espacios, pegado largo) y los casos límite de cada flujo.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/recuperacion_password_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _email = 'ana@example.com';

late RecuperacionPasswordEnMemoria _recuperacion;
late DbLocalRepositoryEnMemoria _dbLocal;
late AuthRemoteDataSourceEnMemoria _auth;

Finder _k(String k) => find.byKey(Key('confirmar_recuperacion_$k'));
Finder get _guardar => _k('guardar');
Finder get _login => find.byKey(const Key('login_enviar'));

/// Almacén de sesión que no puede borrar la sesión: el cierre de sesión falla del lado local.
final class _LocalQueNoBorra implements AuthLocalDataSource {
  SesionModel? _sesion;

  @override
  Future<SesionModel?> leerSesion() async => _sesion;

  @override
  Future<void> guardarSesion(SesionModel sesion) async => _sesion = sesion;

  @override
  Future<void> borrarSesion() async => throw Exception('keystore');
}

Future<ProviderContainer> _montar(
  WidgetTester tester, {
  EnlaceRecuperacion enlace = EnlaceRecuperacion.valido,
  bool conSesion = false,
  AuthLocalDataSource? local,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(_auth),
      authLocalDataSourceProvider.overrideWithValue(local ?? AuthLocalDataSourceEnMemoria()),
      recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(_recuperacion),
      dbLocalRepositoryProvider.overrideWithValue(_dbLocal),
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

void _conBaseLocal() {
  final dek = Uint8List.fromList(List<int>.filled(32, 77));
  _dbLocal
    ..marca = MarcaDbLocal.puesta
    ..archivo = true
    ..claveDelArchivo = dek
    ..dekEnAlmacen = dek
    ..envoltorio = (dek: dek, password: 'Vieja1234');
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

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(_guardar).onPressed != null;

String _texto(WidgetTester tester, String campo) =>
    tester.widget<TextField>(_k(campo)).controller!.text;

void _pantalla(WidgetTester tester, Size tam, {double texto = 1.0}) {
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _guias(WidgetTester tester) async {
  // El botón anima del gris al azul al habilitarse (200 ms): se mide con los colores finales.
  await tester.pump(const Duration(milliseconds: 400));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  expect(tester.takeException(), isNull);
}

/// Cada estado del canvas 15 (y los de las decisiones del 02/10) con la forma de llegar a él.
enum _Estado {
  vacio('formulario vacío'),
  a01('A01 sin base local, requisitos cumplidos'),
  a02('A02 con base local'),
  a03('A03 débil, faltan 3'),
  a03b('A03 las dos contraseñas no coinciden'),
  a04('A04 guardando'),
  a05('A05 error genérico'),
  a06('A06 enlace vencido'),
  a08('A08 sin conexión al guardar'),
  a09('A09 éxito'),
  a09b('A09 éxito con el cierre de sesión fallido'),
  enlaceSinConexion('el enlace llegó sin conexión');

  const _Estado(this.rotulo);
  final String rotulo;
}

Future<void> _llegarA(WidgetTester tester, _Estado e) async {
  switch (e) {
    case _Estado.vacio:
      await _montar(tester);
    case _Estado.a01:
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
    case _Estado.a02:
      _conBaseLocal();
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
    case _Estado.a03:
      await _montar(tester);
      await tester.enterText(_k('nueva'), 'lucia');
      await tester.pump();
    case _Estado.a03b:
      await _montar(tester);
      await _completar(tester, 'NuevaClave1', repetida: 'NuevaClave2');
    case _Estado.a04:
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.pump();
      expect(_k('guardando'), findsOneWidget);
    case _Estado.a05:
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      _recuperacion.fallaAlActualizar = const CredencialesInvalidasException();
      await _tocarGuardar(tester);
      expect(_k('error'), findsOneWidget);
    case _Estado.a06:
      await _montar(tester, enlace: EnlaceRecuperacion.vencido);
    case _Estado.a08:
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      _recuperacion.simularSinConexion = true;
      await _tocarGuardar(tester);
      expect(_k('sin_conexion_guardar'), findsOneWidget);
    case _Estado.a09:
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);
      expect(_k('exito'), findsOneWidget);
    case _Estado.a09b:
      await _montar(tester, conSesion: true, local: _LocalQueNoBorra());
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);
      expect(_k('exito'), findsOneWidget);
    case _Estado.enlaceSinConexion:
      await _montar(tester, enlace: EnlaceRecuperacion.sinConexion);
  }
}

/// Para recorrer varios estados en un mismo test: desmonta la app y vuelve a armar los fakes.
Future<void> _reiniciar(WidgetTester tester) async {
  await _soltar(tester);
  await tester.pumpWidget(const SizedBox());
  _recuperacion = RecuperacionPasswordEnMemoria(passwordActual: 'Vieja1234');
  _dbLocal = DbLocalRepositoryEnMemoria();
  _auth = AuthRemoteDataSourceEnMemoria(credenciales: const {_email: 'Vieja1234'});
}

/// Deja la pantalla sin operaciones colgadas (A04).
Future<void> _soltar(WidgetTester tester) async {
  final demora = _recuperacion.demoraAlActualizar;
  if (demora != null && !demora.isCompleted) demora.complete();
  await tester.pumpAndSettle();
}

class _Captura extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  setUp(() {
    _recuperacion = RecuperacionPasswordEnMemoria(passwordActual: 'Vieja1234');
    _dbLocal = DbLocalRepositoryEnMemoria();
    _auth = AuthRemoteDataSourceEnMemoria(credenciales: const {_email: 'Vieja1234'});
  });

  group('QA vista 15 — accesibilidad y tamaños por estado', () {
    final tamanios = <(String, Size, double)>[
      ('360x640', const Size(360, 640), 1.0),
      ('360x640 con el texto al 200 %', const Size(360, 640), 2.0),
      ('412x915', const Size(412, 915), 1.0),
    ];
    for (final (nombre, tam, texto) in tamanios) {
      for (final estado in _Estado.values) {
        testWidgets('$nombre — ${estado.rotulo}: toque, etiquetas, contraste y sin overflow', (
          tester,
        ) async {
          _pantalla(tester, tam, texto: texto);
          final handle = tester.ensureSemantics();
          try {
            await _llegarA(tester, estado);
            await _guias(tester);
            await _soltar(tester);
          } finally {
            handle.dispose();
          }
        });
      }
    }
  });

  group('QA vista 15 — criterios de aceptación con el texto literal', () {
    testWidgets(
      'sin DB local: cambia la contraseña, revoca los JWT y dice «Contraseña actualizada. '
      'Iniciá sesión.» con la salida al login',
      (tester) async {
        await _montar(tester);
        expect(find.textContaining('Tus datos guardados en este teléfono'), findsNothing);
        await _completar(tester, 'NuevaClave1');
        await _tocarGuardar(tester);

        expect(_recuperacion.actualizaciones, ['NuevaClave1']);
        expect(_recuperacion.sesionesCerradas, 1);
        expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
        expect(
          _dbLocal.llamadas,
          isNot(contains('envolver')),
          reason: 'no había DB que re-envolver',
        );
        await tester.ensureVisible(_k('exito_ir_al_login'));
        await tester.tap(_k('exito_ir_al_login'));
        await tester.pumpAndSettle();
        expect(_login, findsOneWidget);
      },
    );

    testWidgets(
      'con DB local: agrega «Tus datos guardados en este teléfono se conservan.», no pide '
      'elegir nada y re-envuelve la DEK',
      (tester) async {
        _conBaseLocal();
        final dek = _dbLocal.dekEnAlmacen;
        await _montar(tester);

        expect(
          find.text('Tus datos guardados en este teléfono se conservan.'),
          findsOneWidget,
          reason: 'A02',
        );
        expect(find.textContaining('Restaurar'), findsNothing);
        expect(find.textContaining('Borrar'), findsNothing);
        expect(find.byType(RadioListTile<dynamic>), findsNothing);
        await _completar(tester, 'NuevaClave1');
        expect(_habilitado(tester), isTrue, reason: 'funciona directo, sin elegir qué hacer');

        await _tocarGuardar(tester);
        expect(_dbLocal.envoltorio!.password, 'NuevaClave1');
        expect(_dbLocal.envoltorio!.dek, dek);
        expect(_dbLocal.archivo, isTrue, reason: 'la DB local queda intacta');
        expect(_recuperacion.sesionesCerradas, 1);
        expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      },
    );

    testWidgets('si falla el cierre de sesión, muestra el literal de la decisión del 02/10 y no '
        '«Iniciá sesión» con la sesión local abierta', (tester) async {
      final container = await _montar(tester, conSesion: true, local: _LocalQueNoBorra());
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);

      expect(
        find.text(
          'Cambiaste la contraseña, pero no pudimos cerrar la sesión en este teléfono. Cerrala '
          'desde Configuración.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Iniciá sesión'), findsNothing);
      expect(find.text('Ir al login'), findsNothing);
      expect(find.text('Volver al inicio'), findsOneWidget);
      expect(container.read(sesionProvider).value, isNotNull);
    });

    testWidgets('el enlace vencido ofrece pedir otro (HU-AUTH-004) y volver al login', (
      tester,
    ) async {
      await _montar(tester, enlace: EnlaceRecuperacion.vencido);
      expect(find.text('ENLACE VENCIDO'), findsOneWidget);
      expect(find.text('Solicitar un enlace nuevo'), findsOneWidget);
      expect(find.text('Volver al login'), findsOneWidget);
      expect(_guardar, findsNothing);
    });
  });

  group('QA vista 15 — los cinco estados', () {
    testWidgets('vacío: requisitos neutros, botón deshabilitado y el aviso de las sesiones', (
      tester,
    ) async {
      await _montar(tester);
      expect(find.text('○'), findsNWidgets(3));
      expect(_habilitado(tester), isFalse);
      expect(
        find.text(
          'Al guardarla se cierran tus sesiones en todos tus teléfonos: vas a entrar de nuevo con '
          'la contraseña nueva.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('cargando: «Guardando…» con progreso en el botón, no un spinner suelto', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.a04);
      expect(find.descendant(of: _guardar, matching: find.text('Guardando…')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_texto(tester, 'nueva'), 'NuevaClave1', reason: 'lo escrito sigue ahí');
      await _soltar(tester);
    });

    testWidgets('error: dice qué pasó y qué hacer, y el botón sigue habilitado', (tester) async {
      await _llegarA(tester, _Estado.a05);
      expect(find.text('No pudimos guardar la contraseña. Probá de nuevo.'), findsOneWidget);
      expect(_habilitado(tester), isTrue);
      expect(_texto(tester, 'nueva'), 'NuevaClave1');
      expect(_texto(tester, 'repetida'), 'NuevaClave1');
    });

    testWidgets('sin conexión: «Sin conexión» con lo que hacer y lo escrito a salvo', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.a08);
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(
        find.text('Conectate para guardar la contraseña. No perdés lo que escribiste.'),
        findsOneWidget,
      );
      expect(_habilitado(tester), isTrue);
      expect(_texto(tester, 'nueva'), 'NuevaClave1');
    });

    testWidgets('éxito: el texto de la HU y un botón que lleva al login', (tester) async {
      await _llegarA(tester, _Estado.a09);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      expect(find.text('Ir al login'), findsOneWidget);
    });

    testWidgets('los avisos se anuncian (liveRegion): error, sin conexión, éxito, vencido y enlace '
        'sin conexión', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await _llegarA(tester, _Estado.a05);
        expect(tester.getSemantics(_k('error')), isSemantics(isLiveRegion: true));

        await _reiniciar(tester);
        await _llegarA(tester, _Estado.a08);
        expect(
          tester.getSemantics(
            find.text('Conectate para guardar la contraseña. No perdés lo que escribiste.'),
          ),
          isSemantics(isLiveRegion: true),
        );

        await _reiniciar(tester);
        await _llegarA(tester, _Estado.a09);
        expect(tester.getSemantics(_k('exito')), isSemantics(isLiveRegion: true));

        await _reiniciar(tester);
        await _llegarA(tester, _Estado.a06);
        expect(tester.getSemantics(_k('vencido')), isSemantics(isLiveRegion: true));

        await _reiniciar(tester);
        await _llegarA(tester, _Estado.enlaceSinConexion);
        expect(tester.getSemantics(_k('sin_conexion')), isSemantics(isLiveRegion: true));
      } finally {
        handle.dispose();
      }
    });
  });

  group('QA vista 15 — validación de la contraseña nueva', () {
    testWidgets('el borde de los 8 caracteres: 7 no alcanza, 8 sí', (tester) async {
      await _montar(tester);
      await _completar(tester, 'Abcdef1');
      expect(find.textContaining('faltan 1', findRichText: true), findsOneWidget);
      expect(_habilitado(tester), isFalse);

      await _completar(tester, 'Abcdefg1');
      expect(find.textContaining('faltan', findRichText: true), findsNothing);
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('el largo cuenta caracteres visibles: banderas, familias y letras con tilde '
        'descompuesta valen 1', (tester) async {
      await _montar(tester);
      const bandera = '\u{1F1E6}\u{1F1F7}';
      const familia = '\u{1F468}‍\u{1F469}‍\u{1F467}';
      const eDescompuesta = 'é';
      for (final (nombre, unidad) in [
        ('bandera', bandera),
        ('familia', familia),
        ('e con tilde descompuesta', eDescompuesta),
      ]) {
        await _completar(tester, 'A1${unidad * 5}');
        expect(
          find.textContaining('faltan 1', findRichText: true),
          findsOneWidget,
          reason: '$nombre: 7 caracteres visibles',
        );
        expect(_habilitado(tester), isFalse, reason: nombre);

        await _completar(tester, 'A1${unidad * 6}');
        expect(find.textContaining('faltan', findRichText: true), findsNothing, reason: nombre);
        expect(_habilitado(tester), isTrue, reason: '$nombre: 8 caracteres visibles');
      }
    });

    testWidgets('cada requisito por separado: sin mayúscula, sin número y solo espacios', (
      tester,
    ) async {
      await _montar(tester);
      await _completar(tester, 'nuevaclave1');
      expect(find.descendant(of: _k('req_mayuscula'), matching: find.text('✕')), findsOneWidget);
      expect(find.descendant(of: _k('req_numero'), matching: find.text('✓')), findsOneWidget);
      expect(_habilitado(tester), isFalse);

      await _completar(tester, 'NuevaClave');
      expect(find.descendant(of: _k('req_numero'), matching: find.text('✕')), findsOneWidget);
      expect(find.descendant(of: _k('req_mayuscula'), matching: find.text('✓')), findsOneWidget);
      expect(_habilitado(tester), isFalse);

      await _completar(tester, ' ' * 10);
      expect(_habilitado(tester), isFalse);
    });

    testWidgets('un dígito que no es 0-9 (árabe-índico) no cuenta como número', (tester) async {
      await _montar(tester);
      await _completar(tester, 'NuevaClave١٢');
      expect(find.descendant(of: _k('req_numero'), matching: find.text('✕')), findsOneWidget);
      expect(_habilitado(tester), isFalse);
    });

    testWidgets('los espacios al principio y al final son parte de la contraseña: no se recortan', (
      tester,
    ) async {
      await _montar(tester);
      await _completar(tester, ' NuevaClave1 ');
      expect(_habilitado(tester), isTrue);
      await _tocarGuardar(tester);
      expect(_recuperacion.actualizaciones, [' NuevaClave1 ']);
    });

    testWidgets('una repetida con un espacio de más o con otras mayúsculas no coincide', (
      tester,
    ) async {
      await _montar(tester);
      await _completar(tester, 'NuevaClave1', repetida: 'NuevaClave1 ');
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(_habilitado(tester), isFalse);

      await _completar(tester, 'NuevaClave1', repetida: 'nuevaclave1');
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(_habilitado(tester), isFalse);
    });

    testWidgets('con la nueva válida y la repetida vacía, el botón sigue deshabilitado y no hay '
        'error hasta que escribe', (tester) async {
      await _montar(tester);
      await tester.enterText(_k('nueva'), 'NuevaClave1');
      await tester.pump();
      expect(_habilitado(tester), isFalse);
      expect(find.text('Las contraseñas no coinciden'), findsNothing);
      expect(find.textContaining('✓ COINCIDEN'), findsNothing);
    });

    testWidgets('si cambia la nueva después de repetirla, deja de coincidir y el botón se apaga', (
      tester,
    ) async {
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      expect(_habilitado(tester), isTrue);
      expect(find.text('REPETIR CONTRASEÑA · ✓ COINCIDEN'), findsOneWidget);

      await tester.enterText(_k('nueva'), 'NuevaClave12');
      await tester.pump();
      expect(_habilitado(tester), isFalse);
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(find.text('REPETIR CONTRASEÑA · ✓ COINCIDEN'), findsNothing);
    });

    testWidgets('texto pegado muy largo (5000 caracteres): se acepta tal cual, sin overflow', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 640), texto: 2.0);
      await _montar(tester);
      final larga = 'Aa1${'x' * 4997}';
      await _completar(tester, larga);
      expect(_habilitado(tester), isTrue);
      expect(tester.takeException(), isNull);
      await _tocarGuardar(tester);
      expect(_recuperacion.actualizaciones, [larga]);
    });

    testWidgets('un salto de línea pegado se descarta y la contraseña queda en una línea', (
      tester,
    ) async {
      await _montar(tester);
      await tester.enterText(_k('nueva'), 'Nueva\nClave1');
      await tester.enterText(_k('repetida'), 'NuevaClave1');
      await tester.pump();
      expect(_texto(tester, 'nueva'), isNot(contains('\n')));
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('«Listo» sin nada escrito dice qué falta en vez de no hacer nada', (tester) async {
      await _montar(tester);
      await tester.tap(_k('repetida'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Escribí la contraseña nueva.'), findsOneWidget);
      expect(_recuperacion.actualizaciones, isEmpty);

      await tester.enterText(_k('nueva'), 'corta');
      await tester.pump();
      await tester.tap(_k('repetida'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Todavía no cumple los requisitos de abajo.'), findsOneWidget);
    });

    testWidgets('la contraseña viaja oculta, con la sugerencia de contraseña nueva y sin copiar el '
        'texto por defecto', (tester) async {
      await _montar(tester);
      for (final campo in ['nueva', 'repetida']) {
        final f = tester.widget<TextField>(_k(campo));
        expect(f.obscureText, isTrue, reason: campo);
        expect(f.autofillHints, contains(AutofillHints.newPassword), reason: campo);
      }
    });

    testWidgets(
      'el servidor rechaza una contraseña que el teléfono aceptó: lo dice en el campo, no '
      'pierde lo escrito y editar lo limpia',
      (tester) async {
        await _montar(tester);
        _recuperacion.fallaAlActualizar = const PasswordDebilException();
        await _completar(tester, 'NuevaClave1');
        await _tocarGuardar(tester);

        expect(find.text('Usá al menos 8 caracteres, una mayúscula y un número.'), findsOneWidget);
        expect(_texto(tester, 'nueva'), 'NuevaClave1');
        expect(_texto(tester, 'repetida'), 'NuevaClave1');
        expect(_habilitado(tester), isTrue);

        await tester.enterText(_k('nueva'), 'NuevaClave12');
        await tester.pump();
        expect(find.text('Usá al menos 8 caracteres, una mayúscula y un número.'), findsNothing);
      },
    );
  });

  group('QA vista 15 — navegación', () {
    testWidgets('atrás en cada estado del formulario: sale al login y suelta la sesión una vez', (
      tester,
    ) async {
      for (final estado in [_Estado.vacio, _Estado.a03, _Estado.a05, _Estado.a08]) {
        await _llegarA(tester, estado);
        await tester.tap(_k('atras'));
        await tester.pumpAndSettle();
        expect(_login, findsOneWidget, reason: estado.rotulo);
        expect(_recuperacion.abandonos, 1, reason: estado.rotulo);
        await _reiniciar(tester);
      }
    });

    testWidgets('atrás del sistema y «Volver» durante «Guardando…» no sacan al usuario; cuando '
        'termina, queda el éxito', (tester) async {
      await _llegarA(tester, _Estado.a04);
      expect(tester.widget<IconButton>(_k('atras')).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsOneWidget);
      expect(_recuperacion.abandonos, 0, reason: 'no se suelta la sesión con el cambio en vuelo');

      _recuperacion.demoraAlActualizar!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      expect(_recuperacion.actualizaciones, ['NuevaClave1']);
    });

    testWidgets('enlace vencido y enlace sin conexión: atrás lleva al login sin soltar ninguna '
        'sesión', (tester) async {
      for (final estado in [_Estado.a06, _Estado.enlaceSinConexion]) {
        await _llegarA(tester, estado);
        await tester.tap(_k('atras'));
        await tester.pumpAndSettle();
        expect(_login, findsOneWidget, reason: estado.rotulo);
        expect(_recuperacion.abandonos, 0, reason: estado.rotulo);
        await _reiniciar(tester);
      }
    });

    testWidgets(
      '«Solicitar un enlace nuevo» abre HU-AUTH-004 y el atrás de ahí vuelve al login, no '
      'al aviso de vencido',
      (tester) async {
        await _llegarA(tester, _Estado.a06);
        await tester.tap(_k('pedir_otro'));
        await tester.pumpAndSettle();
        expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
        expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);

        await tester.tap(find.byKey(const Key('recuperacion_password_atras')));
        await tester.pumpAndSettle();
        expect(_login, findsOneWidget);
        expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
      },
    );

    testWidgets('dos toques seguidos en «Solicitar un enlace nuevo» abren una sola pantalla', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.a06);
      await tester.tap(_k('pedir_otro'));
      await tester.tap(_k('pedir_otro'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('recuperacion_password_atras')));
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget, reason: 'un solo atrás alcanza para volver al login');
    });

    testWidgets('«Ir al login» del éxito saca la pantalla de la pila: no se puede volver al '
        'formulario', (tester) async {
      await _llegarA(tester, _Estado.a09);
      await tester.ensureVisible(_k('exito_ir_al_login'));
      await tester.tap(_k('exito_ir_al_login'));
      await tester.tap(_k('exito_ir_al_login'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
      expect(_guardar, findsNothing);
    });

    testWidgets(
      'con la sesión de la app abierta y el cierre fallido, «Volver al inicio» lleva a la '
      'pantalla principal, desde donde se llega a Configuración',
      (tester) async {
        await _llegarA(tester, _Estado.a09b);
        await tester.ensureVisible(_k('exito_ir_al_login'));
        await tester.tap(_k('exito_ir_al_login'));
        await tester.pumpAndSettle();
        expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
        expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
      },
    );
  });

  group('QA vista 15 — casos límite del guardado', () {
    testWidgets(
      'dos fallas seguidas distintas y después el éxito: cada aviso reemplaza al anterior '
      'y el botón nunca queda trabado',
      (tester) async {
        await _montar(tester);
        await _completar(tester, 'NuevaClave1');

        _recuperacion.simularSinConexion = true;
        await _tocarGuardar(tester);
        expect(find.text('Sin conexión'), findsOneWidget);
        expect(_habilitado(tester), isTrue);

        _recuperacion
          ..simularSinConexion = false
          ..fallaAlActualizar = const CredencialesInvalidasException();
        await _tocarGuardar(tester);
        expect(find.text('Sin conexión'), findsNothing);
        expect(_k('error'), findsOneWidget);
        expect(_habilitado(tester), isTrue);

        _recuperacion.fallaAlActualizar = const PasswordDebilException();
        await _tocarGuardar(tester);
        expect(_k('error'), findsNothing, reason: 'el aviso general se limpia al guardar de nuevo');
        expect(find.text('Usá al menos 8 caracteres, una mayúscula y un número.'), findsOneWidget);

        _recuperacion.fallaAlActualizar = null;
        await _tocarGuardar(tester);
        expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
        expect(_recuperacion.actualizaciones, ['NuevaClave1']);
      },
    );

    testWidgets('mientras guarda los campos no se pueden editar ni mostrar; si falla se habilitan '
        'con lo escrito intacto', (tester) async {
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.pump();

      expect(tester.widget<TextField>(_k('nueva')).enabled, isFalse);
      expect(tester.widget<TextField>(_k('repetida')).enabled, isFalse);

      _recuperacion.fallaAlActualizar = const CredencialesInvalidasException();
      _recuperacion.demoraAlActualizar!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_k('nueva')).enabled, isTrue);
      expect(tester.widget<TextField>(_k('repetida')).enabled, isTrue);
      expect(_texto(tester, 'nueva'), 'NuevaClave1');
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('un segundo toque en «Guardar» con la primera respuesta en vuelo no pisa nada: una '
        'sola actualización y una sola revocación', (tester) async {
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.pump();
      await tester.tap(_guardar, warnIfMissed: false);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      _recuperacion.demoraAlActualizar!.complete();
      await tester.pumpAndSettle();

      expect(_recuperacion.actualizaciones, ['NuevaClave1']);
      expect(_recuperacion.sesionesCerradas, 1);
    });

    testWidgets('el enlace vence mientras guarda: pasa al aviso de vencido con las salidas, sin '
        'dejar «Guardando…»', (tester) async {
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.pump();

      _recuperacion.vencerSesionDeRecuperacion();
      _recuperacion.demoraAlActualizar!.complete();
      await tester.pumpAndSettle();

      expect(_k('guardando'), findsNothing);
      expect(_k('pedir_otro'), findsOneWidget);
      expect(_k('ir_al_login'), findsOneWidget);
      expect(_recuperacion.actualizaciones, isEmpty);
    });

    testWidgets('si Supabase aceptó el cambio y la respuesta se perdió, reintentar con la misma '
        'contraseña termina bien y revoca las sesiones una vez', (tester) async {
      await _montar(tester);
      _recuperacion.pierdeLaRespuestaAlActualizar = true;
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);
      expect(find.text('Sin conexión'), findsOneWidget);

      await _tocarGuardar(tester);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      expect(_recuperacion.sesionesCerradas, 1);
    });

    testWidgets('si el servidor aceptó el cambio y el usuario escribe otra contraseña, el intento '
        'siguiente no se confunde con el cortado', (tester) async {
      await _montar(tester);
      _recuperacion.pierdeLaRespuestaAlActualizar = true;
      await _completar(tester, 'NuevaClave1');
      await _tocarGuardar(tester);
      expect(find.text('Sin conexión'), findsOneWidget);

      await _completar(tester, 'OtraClave22');
      await _tocarGuardar(tester);
      expect(find.text('Contraseña actualizada. Iniciá sesión.'), findsOneWidget);
      expect(_recuperacion.passwordActual, 'OtraClave22');
    });
  });

  group('QA vista 15 — errores del servidor', () {
    // QA #224: un error del servidor sin traducción propia llega a la pantalla con el texto del
    // `Failure` tal cual: «No se pudo completar la operación (<código>).» (lo arma
    // `AuthRemoteDataSourceSupabase._traducir`) o «El servidor no pudo procesar la solicitud»: ni
    // dicen qué hacer ni son el aviso del canvas 15-A05 («No pudimos guardar la contraseña. Probá de
    // nuevo.»); el primero muestra además un código técnico.
    testWidgets(
      'un error del servidor sin texto propio dice qué hacer y no muestra un código',
      (tester) async {
        await _montar(tester);
        await _completar(tester, 'NuevaClave1');
        _recuperacion.fallaAlActualizar = const ServidorException(
          status: 500,
          mensaje: 'No se pudo completar la operación (unexpected_failure).',
        );
        await _tocarGuardar(tester);

        expect(find.textContaining('unexpected_failure'), findsNothing);
        expect(find.textContaining('Probá de nuevo'), findsOneWidget);
      },
      skip: true,
    ); // skip: QA #224 — error del servidor sin traducción: sin «qué hacer» y con código.

    testWidgets('un 429 conserva su texto con qué hacer y deja reintentar', (tester) async {
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      _recuperacion.fallaAlActualizar = const ServidorException(
        status: 429,
        mensaje: 'Demasiados intentos. Esperá unos minutos y volvé a probar.',
      );
      await _tocarGuardar(tester);
      expect(find.textContaining('Esperá unos minutos'), findsOneWidget);
      expect(_habilitado(tester), isTrue);
    });

    // QA #224: sin timeout, si la respuesta nunca llega (señal que se corta a mitad, portal cautivo)
    // «Guardando…» no termina nunca y el atrás queda bloqueado (la pantalla lo deshabilita mientras
    // guarda): el usuario solo puede matar la app. Esperado: pasado un tiempo razonable, un aviso
    // de sin conexión con el botón habilitado (el caso «se cortó sin respuesta» ya está resuelto
    // con `_enDuda`).
    testWidgets('si la respuesta nunca llega, «Guardando…» no deja al usuario sin salida', (
      tester,
    ) async {
      _recuperacion.demoraAlActualizar = Completer<void>();
      await _montar(tester);
      await _completar(tester, 'NuevaClave1');
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.pump();

      await tester.pump(const Duration(minutes: 3));
      expect(_k('guardando'), findsNothing);
      expect(_habilitado(tester), isTrue);
    }, skip: true); // skip: QA #224 — sin timeout: «Guardando…» eterno y atrás bloqueado.
  });

  group('QA vista 15 — privacidad', () {
    test('los parámetros y los fallos no llevan la contraseña en toString', () {
      const clave = 'Secreta1xyz';
      _recuperacion = RecuperacionPasswordEnMemoria(passwordActual: 'Vieja1234');
      expect(
        const ServidorException(status: 500, mensaje: 'algo').toString(),
        isNot(contains(clave)),
      );
      expect(const PasswordDebilException().toString(), isNot(contains(clave)));
    });

    test(
      'el repositorio no deja la contraseña en el log, ni en el éxito ni en las fallas',
      () async {
        const clave = 'Secreta1xyz';
        final captura = _Captura();
        final repo = RecuperacionPasswordRepositoryImpl(
          _recuperacion,
          logger: AppLogger(output: captura),
        );
        _recuperacion.simularEnlace(EnlaceRecuperacion.valido);

        _recuperacion.fallaAlActualizar = const ServidorException(status: 500, mensaje: 'x');
        await repo.actualizarPassword(clave);
        _recuperacion.fallaAlActualizar = const CredencialesInvalidasException();
        await repo.actualizarPassword(clave);
        _recuperacion.fallaAlActualizar = null;
        _recuperacion.simularSinConexion = true;
        await repo.actualizarPassword(clave);
        _recuperacion.simularSinConexion = false;
        final resultado = await repo.actualizarPassword(clave);

        expect(resultado.isRight(), isTrue);
        expect(captura.lineas.join('\n'), isNot(contains(clave)));
        expect(captura.lineas.join('\n'), contains('password_reset_completed'));
      },
    );
  });
}
