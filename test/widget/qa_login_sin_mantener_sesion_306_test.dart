// QA de #303 (PR #306): el login sin la casilla «Mantener sesión» (decisión de Cristian, 07/10:
// la sesión es siempre la de HU-AUTH-007, 30 días desde el último uso, y se cierra con «Cerrar
// sesión», o por 17-A01 / 17-A03). Complementa `qa_acceso_login_295_test.dart` y
// `sesion_vencida_vista17_qa_test.dart` con lo que el PR deja sin probar: que la sesión siga
// persistiendo de punta a punta, el orden del foco en cada pantalla (también con Shift+Tab), la
// semántica y la zona de toque del enlace de recuperación que quedó solo, las cinco pantallas del
// login (inicial y 17-A01 a A04) con las cuatro guías de accesibilidad a los tres teléfonos y al
// 200 %, y el enlace con un envío en vuelo.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart';
import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/tiles_falsos.dart';

const _recuperar = Key('login_olvidaste_clave');
const _entrar = Key('login_enviar');
const _correo = Key('login_email');
const _clave = Key('login_password');
const _cerrarAviso = Key('login_aviso_sesion_cerrar');
const _inicio = Key('inicio_principal');
const _registro = Key('login_ir_a_registro');

/// Las pantallas del login que el canvas dibuja: la inicial (1a) y las cuatro de la vista 17.
enum _Pantalla {
  inicial('1a · inicial'),
  a01('17-A01 · expiró por inactividad'),
  a02('17-A02 · vencida y sin conexión'),
  a03('17-A03 · revocada por el servidor'),
  a04('17-A04 · aviso descartado');

  const _Pantalla(this.nombre);

  final String nombre;

  /// El texto del enlace de recuperación en esa pantalla (A02 no lo dibuja).
  String? get textoDelEnlace => switch (this) {
    inicial => '¿Olvidaste tu clave?',
    a02 => null,
    _ => 'Recuperar acceso',
  };
}

SesionModel _sesionDeLucia() => SesionModel(
  usuarioId: '01920000-0000-7000-8000-000000000001',
  email: 'lucia.silva@correo.com',
  accessToken: 'jwt',
  expiraEn: DateTime.now().toUtc().add(const Duration(days: 29)),
);

/// Teléfono sin datos guardados: el cierre de sesión pide la confirmación común.
final class _SinDatosLocales implements DatosLocalesRepository {
  @override
  Future<Either<Failure, ResumenDatosLocales>> resumen() async => const Right(
    ResumenDatosLocales(
      personas: 0,
      visitas: 0,
      operacionesSinSincronizar: 0,
      hayBackupEnDrive: false,
    ),
  );

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({
    required bool incluirBackupDrive,
    bool reintento = false,
  }) async => const Right(ResultadoBorradoDatosLocales.completo);
}

class _Entorno {
  _Entorno(this.remoto, this.local, this.conexion);

  final AuthRemoteDataSourceEnMemoria remoto;
  final AuthLocalDataSourceEnMemoria local;
  final ConectividadFalsa conexion;
}

AuthRemoteDataSourceEnMemoria _remoto() => AuthRemoteDataSourceEnMemoria(
  credenciales: const {correoAna: claveAna, 'lucia.silva@correo.com': 'Secreto123'},
);

/// La app entera, con [local] como almacén de sesión (para reabrirla con lo que quedó guardado).
Future<_Entorno> _montarApp(
  WidgetTester tester, {
  AuthRemoteDataSourceEnMemoria? remoto,
  AuthLocalDataSourceEnMemoria? local,
  TipoConexion tipo = TipoConexion.wifi,
}) async {
  final entorno = _Entorno(
    remoto ?? _remoto(),
    local ?? AuthLocalDataSourceEnMemoria(),
    ConectividadFalsa()..tipo = tipo,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(entorno.remoto),
        authLocalDataSourceProvider.overrideWithValue(entorno.local),
        datosLocalesRepositoryProvider.overrideWithValue(_SinDatosLocales()),
        monitorConectividadProvider.overrideWithValue(entorno.conexion),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  return entorno;
}

void _pantallaDe(WidgetTester tester, Size tam, {double texto = 1}) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Lleva la app a [pantalla]: la inicial sin sesión; las de la vista 17 con la sesión de Lucía que
/// vence (por inactividad o revocada, con o sin señal).
Future<_Entorno> _llegarA(WidgetTester tester, _Pantalla pantalla) async {
  if (pantalla == _Pantalla.inicial) return _montarApp(tester);
  final local = AuthLocalDataSourceEnMemoria();
  await local.guardarSesion(_sesionDeLucia());
  final e = await _montarApp(
    tester,
    local: local,
    tipo: pantalla == _Pantalla.a02 ? TipoConexion.sinConexion : TipoConexion.wifi,
  );
  e.remoto.simularExpiracion(
    pantalla == _Pantalla.a03 ? MotivoExpiracion.revocada : MotivoExpiracion.inactividad,
  );
  await tester.pumpAndSettle();
  if (pantalla == _Pantalla.a04) {
    await tester.tap(find.byKey(_cerrarAviso));
    await tester.pumpAndSettle();
  }
  return e;
}

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  expect(tester.takeException(), isNull);
}

/// Dónde está el foco del teclado, en el vocabulario del login (o `null` si no hay).
String? _dondeEstaElFoco(WidgetTester tester) {
  final contexto = FocusManager.instance.primaryFocus?.context;
  if (contexto == null) return null;
  bool dentroDe(Finder f) {
    if (f.evaluate().isEmpty) return false;
    final objetivo = tester.element(f.first);
    if (contexto == objetivo) return true;
    var halla = false;
    contexto.visitAncestorElements((a) {
      if (a == objetivo) halla = true;
      return !halla;
    });
    return halla;
  }

  if (dentroDe(find.byTooltip('Cerrar aviso'))) return 'cerrar aviso';
  if (dentroDe(find.byTooltip('Mostrar contraseña'))) return 'ojo';
  if (dentroDe(find.byKey(_correo))) return 'correo';
  if (dentroDe(find.byKey(_clave))) return 'contraseña';
  if (dentroDe(find.widgetWithText(FilledButton, 'Reintentar'))) return 'reintentar';
  if (dentroDe(find.byKey(_recuperar))) return 'recuperar';
  if (dentroDe(find.byKey(_entrar))) return 'entrar';
  if (dentroDe(find.byKey(const Key('login_ir_a_registro')))) return 'registro';
  return 'otro';
}

Future<List<String?>> _tabular(WidgetTester tester, int veces, {bool conShift = false}) async {
  final visitados = <String?>[];
  for (var i = 0; i < veces; i++) {
    if (conShift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (conShift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    visitados.add(_dondeEstaElFoco(tester));
  }
  return visitados;
}

/// Escribe una contraseña que el servidor va a rechazar (con el correo de Ana en la inicial; en la
/// vista 17 el correo ya viene puesto).
Future<void> _escribirClaveIncorrecta(WidgetTester tester, _Pantalla pantalla) async {
  if (pantalla == _Pantalla.inicial) await tester.enterText(find.byKey(_correo), correoAna);
  await tester.enterText(find.byKey(_clave), 'incorrecta1');
}

/// Toca «Entrar» y deja el intento «a mitad»: el servidor contesta cuando el test completa lo que
/// devuelve esto.
Future<Completer<void>> _entrarYQuedarEnVuelo(
  WidgetTester tester,
  _Entorno entorno,
  _Pantalla pantalla,
) async {
  final demora = Completer<void>();
  entorno.remoto.demoraIniciarSesion = demora;
  await _escribirClaveIncorrecta(tester, pantalla);
  await tester.ensureVisible(find.byKey(_entrar));
  await tester.tap(find.byKey(_entrar));
  await tester.pump();
  return demora;
}

/// El color con que se pinta el texto del botón [boton] (el `Text` lleva su color propio).
Color? _colorDelTexto(WidgetTester tester, Key boton) => tester
    .widget<Text>(find.descendant(of: find.byKey(boton), matching: find.byType(Text)))
    .style
    ?.color;

void main() {
  group('Sin «Mantener sesión» la sesión persiste igual (HU-AUTH-007, decisión del 07/10)', () {
    testWidgets('dado que entró sin elegir nada, cuando cierra y reabre la app, sigue adentro con '
        'la misma sesión guardada', (tester) async {
      final local = AuthLocalDataSourceEnMemoria();
      await _montarApp(tester, local: local);
      expect(find.byType(Checkbox), findsNothing);

      await tester.enterText(find.byKey(_correo), correoAna);
      await tester.enterText(find.byKey(_clave), claveAna);
      await tester.tap(find.byKey(_entrar));
      await tester.pumpAndSettle();
      expect(find.byKey(_inicio), findsOneWidget);
      final guardada = await local.leerSesion();
      expect(guardada, isNotNull, reason: 'la sesión quedó en el almacén seguro');
      expect(guardada!.email, correoAna);

      // «Se cierra la app» y se vuelve a abrir con el mismo almacén.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _montarApp(tester, local: local);

      expect(find.byKey(_inicio), findsOneWidget, reason: 'entra directo, sin pasar por el login');
      expect(find.byKey(_entrar), findsNothing);
    });

    testWidgets('dado que está adentro, cuando toca «Cerrar sesión», la sesión se borra del '
        'almacén y el login que vuelve no ofrece la casilla', (tester) async {
      final local = AuthLocalDataSourceEnMemoria();
      await _montarApp(tester, local: local);
      await tester.enterText(find.byKey(_correo), correoAna);
      await tester.enterText(find.byKey(_clave), claveAna);
      await tester.tap(find.byKey(_entrar));
      await tester.pumpAndSettle();
      expect(await local.leerSesion(), isNotNull);

      await tester.tap(find.byKey(const Key('inicio_configuracion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
      await tester.pumpAndSettle();

      expect(find.byKey(_entrar), findsOneWidget);
      expect(await local.leerSesion(), isNull);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Mantener sesión'), findsNothing);
    });

    for (final pantalla in _Pantalla.values) {
      testWidgets('${pantalla.nombre}: ni casilla ni texto «Mantener sesión», ni para el lector de '
          'pantalla', (tester) async {
        final semantica = tester.ensureSemantics();
        await _llegarA(tester, pantalla);

        expect(find.byKey(_entrar), findsOneWidget);
        expect(find.byType(Checkbox), findsNothing);
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.textContaining('antener'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('antener')), findsNothing);
        semantica.dispose();
      });
    }
  });

  group('Orden del foco con el teclado (Tab y Shift+Tab)', () {
    testWidgets('1a · inicial: Shift+Tab recorre al revés, desde «Registrate» hasta el correo y '
        'da la vuelta', (tester) async {
      _pantallaDe(tester, const Size(412, 915));
      await _llegarA(tester, _Pantalla.inicial);

      final visitados = await _tabular(tester, 7, conShift: true);

      expect(visitados, [
        'registro',
        'entrar',
        'recuperar',
        'ojo',
        'contraseña',
        'correo',
        'registro',
      ]);
    });

    testWidgets('17-A01: el foco pasa primero por «Cerrar aviso» y después por correo, contraseña, '
        'ojo, «Recuperar acceso», «Entrar» y «Registrate», y da la vuelta', (tester) async {
      _pantallaDe(tester, const Size(412, 915));
      await _llegarA(tester, _Pantalla.a01);

      final visitados = await _tabular(tester, 8);

      expect(visitados, [
        'cerrar aviso',
        'correo',
        'contraseña',
        'ojo',
        'recuperar',
        'entrar',
        'registro',
        'cerrar aviso',
      ]);
    });

    testWidgets('17-A03: mismo recorrido que A01, con «Recuperar acceso» entre el ojo y «Entrar»', (
      tester,
    ) async {
      _pantallaDe(tester, const Size(412, 915));
      await _llegarA(tester, _Pantalla.a03);

      final visitados = await _tabular(tester, 7);

      expect(visitados, [
        'cerrar aviso',
        'correo',
        'contraseña',
        'ojo',
        'recuperar',
        'entrar',
        'registro',
      ]);
    });

    testWidgets('17-A04 (aviso descartado): el recorrido vuelve al de la inicial, sin «Cerrar '
        'aviso»', (tester) async {
      _pantallaDe(tester, const Size(412, 915));
      await _llegarA(tester, _Pantalla.a04);

      final visitados = await _tabular(tester, 7);

      expect(visitados, [
        'correo',
        'contraseña',
        'ojo',
        'recuperar',
        'entrar',
        'registro',
        'correo',
      ]);
    });

    testWidgets(
      'con el aviso del servidor caído (5xx), «Reintentar» queda entre el ojo y el enlace '
      'de recuperación, en el orden en que se ve',
      (tester) async {
        _pantallaDe(tester, const Size(412, 915));
        final remoto = RemotoQueFalla();
        await montarAcceso(tester, home: const LoginPage(), remoto: remoto);
        await tester.pumpAndSettle();
        remoto.falla = const ServidorException(status: 503);
        await tester.enterText(find.byKey(_correo), correoAna);
        await tester.enterText(find.byKey(_clave), claveAna);
        await tester.tap(find.byKey(_entrar));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        final visitados = await _tabular(tester, 8);

        expect(visitados, [
          'correo',
          'contraseña',
          'ojo',
          'reintentar',
          'recuperar',
          'entrar',
          'registro',
          'correo',
        ]);
      },
    );

    testWidgets(
      'con el envío en vuelo «Entrar», el enlace de recuperación y «Registrate» no reciben '
      'foco (#309) y el recorrido sigue sin trampas',
      (tester) async {
        _pantallaDe(tester, const Size(412, 915));
        final remoto = RemotoQueFalla()..demora = Completer<void>();
        await montarAcceso(tester, home: const LoginPage(), remoto: remoto);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(_correo), correoAna);
        await tester.enterText(find.byKey(_clave), claveAna);
        await tester.tap(find.byKey(_entrar));
        await tester.pump();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        final visitados = await _tabular(tester, 6);

        expect(visitados, ['correo', 'contraseña', 'ojo', 'correo', 'contraseña', 'ojo']);
        remoto.demora!.complete();
        await tester.pumpAndSettle();
      },
    );
  });

  group('El enlace de recuperación, solo y a la derecha', () {
    for (final pantalla in _Pantalla.values) {
      final queDebePasar = pantalla.textoDelEnlace == null
          ? 'no se dibuja el enlace, ni para el lector de pantalla'
          : 'es un botón con nombre, habilitado y con acción de tocar';
      testWidgets('${pantalla.nombre}: $queDebePasar', (tester) async {
        final semantica = tester.ensureSemantics();
        await _llegarA(tester, pantalla);

        final texto = pantalla.textoDelEnlace;
        if (texto == null) {
          expect(find.byKey(_recuperar), findsNothing);
          expect(find.bySemanticsLabel('Recuperar acceso'), findsNothing);
          expect(find.bySemanticsLabel('¿Olvidaste tu clave?'), findsNothing);
        } else {
          expect(
            tester.getSemantics(find.byKey(_recuperar)),
            isSemantics(label: texto, isButton: true, isEnabled: true, hasTapAction: true),
          );
          // Un solo enlace de recuperación en el árbol de semántica.
          expect(find.bySemanticsLabel(texto), findsOneWidget);
        }
        semantica.dispose();
      });
    }

    for (final (tam, escala) in [
      (const Size(360, 640), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(412, 915), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(412, 915), 2.0),
    ]) {
      testWidgets('la zona de toque mide al menos 48x48 y se activa en sus cuatro esquinas, a '
          '${tam.width.toInt()}x${tam.height.toInt()} con el texto ×$escala', (tester) async {
        _pantallaDe(tester, tam, texto: escala);
        await _llegarA(tester, _Pantalla.inicial);
        await tester.ensureVisible(find.byKey(_recuperar));
        await tester.pumpAndSettle();

        final r = tester.getRect(find.byKey(_recuperar));
        expect(r.width, greaterThanOrEqualTo(48));
        expect(r.height, greaterThanOrEqualTo(48));
        // La zona de toque no se pisa con la de «Entrar» ni con la del ojo.
        expect(r.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(_entrar)).top));
        expect(r.top, greaterThanOrEqualTo(tester.getRect(find.byKey(_clave)).bottom));

        for (final punto in [
          r.topLeft + const Offset(2, 2),
          r.topRight + const Offset(-2, 2),
          r.bottomLeft + const Offset(2, -2),
          r.bottomRight + const Offset(-2, -2),
        ]) {
          await tester.tapAt(punto);
          await tester.pumpAndSettle();
          expect(
            find.byType(RecuperacionPasswordPage),
            findsOneWidget,
            reason: 'tocar en $punto dentro de $r tiene que abrir la recuperación',
          );
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(RecuperacionPasswordPage), findsNothing);
        }
      });
    }

    testWidgets('con el correo en blanco («   ») abre la recuperación sin correo cargado', (
      tester,
    ) async {
      await _llegarA(tester, _Pantalla.inicial);
      await tester.enterText(find.byKey(_correo), '   ');

      await tester.tap(find.byKey(_recuperar));
      await tester.pumpAndSettle();

      final campo = tester.widget<TextField>(find.byKey(const Key('recuperacion_password_email')));
      expect(campo.controller!.text, isEmpty);
    });

    testWidgets('17-A01: trae el correo de la cuenta que estaba adentro y, al volver, el login '
        'sigue con el aviso', (tester) async {
      await _llegarA(tester, _Pantalla.a01);

      await tester.tap(find.byKey(_recuperar));
      await tester.pumpAndSettle();
      final campo = tester.widget<TextField>(find.byKey(const Key('recuperacion_password_email')));
      expect(campo.controller!.text, 'lucia.silva@correo.com');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login_aviso_sesion')), findsOneWidget);
      expect(find.byKey(_recuperar), findsOneWidget);
    });

    testWidgets('17-A02 → vuelve la señal: el enlace aparece sin perder lo escrito', (
      tester,
    ) async {
      final e = await _llegarA(tester, _Pantalla.a02);
      expect(find.byKey(_recuperar), findsNothing);
      await tester.enterText(find.byKey(_clave), 'Secreto');

      e.conexion.cambiarA(TipoConexion.wifi);
      await tester.pumpAndSettle();

      expect(find.byKey(_recuperar), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(_clave)).controller!.text, 'Secreto');
    });

    // Era el hallazgo 1 de la QA de #303 (con `skip`); #309 lo arregla: el enlace se apaga mientras
    // «Entrar» está en vuelo, así que no hay con qué apilar la recuperación sobre el inicio.
    testWidgets(
      'con «Entrar» en vuelo el enlace está apagado, y si el servidor contesta que sí, la '
      'recuperación no queda tapando el inicio',
      (tester) async {
        final remoto = _remoto()..demoraIniciarSesion = Completer<void>();
        await _montarApp(tester, remoto: remoto);
        await tester.enterText(find.byKey(_correo), correoAna);
        await tester.enterText(find.byKey(_clave), claveAna);
        await tester.tap(find.byKey(_entrar));
        await tester.pump();

        expect(tester.widget<TextButton>(find.byKey(_recuperar)).onPressed, isNull);
        await tester.tap(find.byKey(_recuperar), warnIfMissed: false);
        // Con el spinner girando `pumpAndSettle` no termina: se avanza un rato.
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(RecuperacionPasswordPage), findsNothing);

        remoto.demoraIniciarSesion!.complete();
        await tester.pumpAndSettle();

        expect(find.byKey(_inicio), findsOneWidget);
        expect(
          find.byType(RecuperacionPasswordPage),
          findsNothing,
          reason: 'ya entró: la pantalla de recuperación no debería quedar encima del inicio',
        );
      },
    );
  });

  group('El enlace de recuperación con «Entrar» en vuelo y al ras de los campos (#309)', () {
    for (final pantalla in _Pantalla.values.where((p) => p.textoDelEnlace != null)) {
      testWidgets('${pantalla.nombre}: en vuelo el enlace y «Registrate» quedan apagados, con su '
          'nombre y su zona de 48x48; si el login falla, vuelven a andar', (tester) async {
        final semantica = tester.ensureSemantics();
        final e = await _llegarA(tester, pantalla);
        final texto = pantalla.textoDelEnlace!;
        // A 800x600 la vista 17 se desplaza: se deja la página donde la va a dejar «Entrar».
        await tester.ensureVisible(find.byKey(_entrar));
        await tester.pumpAndSettle();
        final antes = tester.getRect(find.byKey(_recuperar));
        final esquema = Theme.of(tester.element(find.byKey(_recuperar))).colorScheme;
        final apagado = esquema.onSurface.withValues(alpha: .38);
        expect(tester.widget<TextButton>(find.byKey(_recuperar)).onPressed, isNotNull);
        expect(tester.widget<TextButton>(find.byKey(_registro)).onPressed, isNotNull);
        expect(_colorDelTexto(tester, _recuperar), esquema.secondary);
        expect(_colorDelTexto(tester, _registro), esquema.secondary);

        final demora = await _entrarYQuedarEnVuelo(tester, e, pantalla);

        // Apagado, pero en su lugar, con la misma zona y el mismo nombre para el lector de pantalla.
        expect(tester.getRect(find.byKey(_recuperar)), antes);
        expect(antes.width, greaterThanOrEqualTo(48));
        expect(antes.height, greaterThanOrEqualTo(48));
        expect(tester.widget<TextButton>(find.byKey(_recuperar)).onPressed, isNull);
        expect(tester.widget<TextButton>(find.byKey(_registro)).onPressed, isNull);
        // Apagados se pintan al 38 % de Material (el texto lleva color propio y no se atenúa solo).
        expect(_colorDelTexto(tester, _recuperar), apagado);
        expect(_colorDelTexto(tester, _registro), apagado);
        expect(
          tester.getSemantics(find.byKey(_recuperar)),
          isSemantics(
            label: texto,
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hasTapAction: false,
          ),
        );
        expect(find.bySemanticsLabel(texto), findsOneWidget);
        await tester.tap(find.byKey(_recuperar), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(RecuperacionPasswordPage), findsNothing);

        // La acción falla a mitad: nada queda trabado.
        demora.complete();
        await tester.pumpAndSettle();
        expect(tester.widget<TextButton>(find.byKey(_recuperar)).onPressed, isNotNull);
        expect(tester.widget<TextButton>(find.byKey(_registro)).onPressed, isNotNull);
        expect(_colorDelTexto(tester, _recuperar), esquema.secondary);
        expect(_colorDelTexto(tester, _registro), esquema.secondary);
        await tester.ensureVisible(find.byKey(_recuperar));
        await tester.tap(find.byKey(_recuperar));
        await tester.pumpAndSettle();
        expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
        semantica.dispose();
      });
    }

    testWidgets(
      'doble toque: tocar dos veces el enlace apagado y «Entrar» otra vez no abre nada ni '
      'manda otro intento',
      (tester) async {
        final e = await _llegarA(tester, _Pantalla.inicial);
        final demora = await _entrarYQuedarEnVuelo(tester, e, _Pantalla.inicial);

        await tester.tap(find.byKey(_recuperar), warnIfMissed: false);
        await tester.tap(find.byKey(_recuperar), warnIfMissed: false);
        await tester.tap(find.byKey(_entrar), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(RecuperacionPasswordPage), findsNothing);
        expect(e.remoto.llamadasIniciarSesion, 1);
        demora.complete();
        await tester.pumpAndSettle();
        expect(e.remoto.llamadasIniciarSesion, 1);
      },
    );

    // Cierre de un cuadro: «Entrar» y el enlace se sueltan sin cuadro de por medio, así que el botón
    // todavía tiene el cierre de antes (no se reconstruyó apagado). `_abrirRecuperacion` y
    // `_abrirRegistro` vuelven a mirar `_enviando`. Pantalla alta: nada se desplaza entre los dos toques.
    for (final pantalla in _Pantalla.values.where((p) => p.textoDelEnlace != null)) {
      testWidgets('${pantalla.nombre}: «Entrar» y el enlace de recuperación soltados en el mismo '
          'cuadro: la recuperación no se abre', (tester) async {
        _pantallaDe(tester, const Size(412, 1400));
        final e = await _llegarA(tester, pantalla);
        e.remoto.demoraIniciarSesion = Completer<void>();
        await _escribirClaveIncorrecta(tester, pantalla);

        await tester.tap(find.byKey(_entrar));
        await tester.tap(find.byKey(_recuperar));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(RecuperacionPasswordPage), findsNothing);
        expect(e.remoto.llamadasIniciarSesion, 1);
        e.remoto.demoraIniciarSesion!.complete();
        await tester.pumpAndSettle();
        expect(find.byType(RecuperacionPasswordPage), findsNothing);
      });

      testWidgets('${pantalla.nombre}: «Entrar» y «Registrate» soltados en el mismo cuadro: el '
          'registro no se abre', (tester) async {
        _pantallaDe(tester, const Size(412, 1400));
        final e = await _llegarA(tester, pantalla);
        e.remoto.demoraIniciarSesion = Completer<void>();
        await _escribirClaveIncorrecta(tester, pantalla);

        await tester.tap(find.byKey(_entrar));
        await tester.tap(find.byKey(_registro));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(RegistroPage), findsNothing);
        expect(e.remoto.llamadasIniciarSesion, 1);
        e.remoto.demoraIniciarSesion!.complete();
        await tester.pumpAndSettle();
        expect(find.byType(RegistroPage), findsNothing);
      });
    }

    testWidgets(
      'Enter (acción «listo» del teclado) con el intento en vuelo no manda otro intento ni '
      'abre la recuperación o el registro, y al terminar todo vuelve a andar',
      (tester) async {
        final e = await _llegarA(tester, _Pantalla.inicial);
        final demora = await _entrarYQuedarEnVuelo(tester, e, _Pantalla.inicial);

        await tester.tap(find.byKey(_clave));
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump(const Duration(milliseconds: 400));

        expect(e.remoto.llamadasIniciarSesion, 1);
        expect(find.byType(RecuperacionPasswordPage), findsNothing);
        expect(find.byType(RegistroPage), findsNothing);
        expect(tester.widget<TextButton>(find.byKey(_recuperar)).onPressed, isNull);
        expect(tester.widget<TextButton>(find.byKey(_registro)).onPressed, isNull);

        demora.complete();
        await tester.pumpAndSettle();
        expect(e.remoto.llamadasIniciarSesion, 1);
        expect(tester.widget<TextButton>(find.byKey(_recuperar)).onPressed, isNotNull);
        expect(tester.widget<TextButton>(find.byKey(_registro)).onPressed, isNotNull);
      },
    );

    // De derecha a izquierda el enlace va en el borde final (izquierdo) de los campos.
    for (final escala in const [1.0, 2.0]) {
      testWidgets('RTL a 360x640, texto ×$escala: el texto del enlace va al ras del borde de los '
          'campos y de «Entrar», con 48 de alto, y en vuelo enlace y «Registrate» se apagan', (
        tester,
      ) async {
        _pantallaDe(tester, const Size(360, 640), texto: escala);
        final remoto = _remoto()..demoraIniciarSesion = Completer<void>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
              authRemoteDataSourceProvider.overrideWithValue(remoto),
              authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
            ],
            child: MaterialApp(
              theme: temaClaro(),
              builder: (_, hijo) => Directionality(textDirection: TextDirection.rtl, child: hijo!),
              home: const LoginPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(_recuperar));
        await tester.pumpAndSettle();

        final texto = tester.getRect(
          find.descendant(of: find.byKey(_recuperar), matching: find.text('¿Olvidaste tu clave?')),
        );
        final campo = tester.getRect(find.byKey(_clave));
        final entrar = tester.getRect(find.byKey(_entrar));
        expect(texto.left, closeTo(campo.left, 0.5), reason: '$texto contra $campo');
        expect(texto.left, closeTo(entrar.left, 0.5), reason: '$texto contra $entrar');
        expect(tester.getRect(find.byKey(_recuperar)).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);

        await tester.enterText(find.byKey(_correo), correoAna);
        await tester.enterText(find.byKey(_clave), 'incorrecta1');
        await tester.ensureVisible(find.byKey(_entrar));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_entrar));
        await tester.pump();
        expect(tester.widget<TextButton>(find.byKey(_recuperar)).onPressed, isNull);
        expect(tester.widget<TextButton>(find.byKey(_registro)).onPressed, isNull);
        expect(tester.takeException(), isNull);

        remoto.demoraIniciarSesion!.complete();
        await tester.pumpAndSettle();
        expect(tester.widget<TextButton>(find.byKey(_recuperar)).onPressed, isNotNull);
        expect(tester.widget<TextButton>(find.byKey(_registro)).onPressed, isNotNull);
      });
    }

    testWidgets('volver atrás y reentrar: abre la recuperación, vuelve, deja «Entrar» en vuelo y, '
        'al fallar, la abre otra vez una sola vez', (tester) async {
      final e = await _llegarA(tester, _Pantalla.inicial);
      await tester.tap(find.byKey(_recuperar));
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsNothing);

      final demora = await _entrarYQuedarEnVuelo(tester, e, _Pantalla.inicial);
      await tester.tap(find.byKey(_recuperar), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RecuperacionPasswordPage), findsNothing);

      demora.complete();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_recuperar));
      await tester.tap(find.byKey(_recuperar));
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsNothing);
    });

    for (final tam in const [Size(360, 640), Size(412, 915)]) {
      testWidgets('texto ×2 a ${tam.width.toInt()}x${tam.height.toInt()}: en vuelo el enlace sigue '
          'con 48 de alto y las guías no se rompen', (tester) async {
        _pantallaDe(tester, tam, texto: 2);
        final e = await _llegarA(tester, _Pantalla.inicial);
        final demora = await _entrarYQuedarEnVuelo(tester, e, _Pantalla.inicial);

        await tester.ensureVisible(find.byKey(_recuperar));
        await tester.pump();
        final r = tester.getRect(find.byKey(_recuperar));
        expect(r.width, greaterThanOrEqualTo(48));
        expect(r.height, greaterThanOrEqualTo(48));
        expect(tester.widget<TextButton>(find.byKey(_recuperar)).onPressed, isNull);
        expect(tester.takeException(), isNull);
        await _guias(tester);

        demora.complete();
        await tester.pumpAndSettle();
        expect(tester.widget<TextButton>(find.byKey(_recuperar)).onPressed, isNotNull);
      });
    }

    // El texto (no solo el botón) termina donde terminan los campos y «Entrar»: canvas 1a, 1b y 17.
    for (final pantalla in _Pantalla.values.where((p) => p.textoDelEnlace != null)) {
      for (final (tam, escala) in [
        (const Size(390, 844), 1.0),
        (const Size(360, 640), 1.0),
        (const Size(412, 915), 1.0),
        (const Size(360, 640), 2.0),
        (const Size(412, 915), 2.0),
      ]) {
        testWidgets('${pantalla.nombre} a ${tam.width.toInt()}x${tam.height.toInt()}, texto '
            '×$escala: el texto del enlace va al ras del borde de los campos y de «Entrar»', (
          tester,
        ) async {
          _pantallaDe(tester, tam, texto: escala);
          await _llegarA(tester, pantalla);
          await tester.ensureVisible(find.byKey(_recuperar));
          await tester.pumpAndSettle();

          final texto = tester.getRect(
            find.descendant(
              of: find.byKey(_recuperar),
              matching: find.text(pantalla.textoDelEnlace!),
            ),
          );
          final campo = tester.getRect(find.byKey(_clave));
          final entrar = tester.getRect(find.byKey(_entrar));
          expect(texto.right, closeTo(campo.right, 0.5), reason: '$texto contra $campo');
          expect(texto.right, closeTo(entrar.right, 0.5), reason: '$texto contra $entrar');
          // Y la zona de toque no se achicó.
          final zona = tester.getRect(find.byKey(_recuperar));
          expect(zona.height, greaterThanOrEqualTo(48));
          expect(zona.width, greaterThanOrEqualTo(48));
        });
      }
    }
  });

  group('Las cinco pantallas del login: guías de accesibilidad y tamaños', () {
    for (final pantalla in _Pantalla.values) {
      for (final tam in const [Size(360, 640), Size(390, 844), Size(412, 915)]) {
        for (final escala in const [1.0, 2.0]) {
          testWidgets('${pantalla.nombre} a ${tam.width.toInt()}x${tam.height.toInt()}, texto '
              '×$escala: sin overflow y con las cuatro guías', (tester) async {
            _pantallaDe(tester, tam, texto: escala);
            await _llegarA(tester, pantalla);

            await _guias(tester);
            // «Entrar» y el enlace se alcanzan desplazando.
            await tester.ensureVisible(find.byKey(_entrar));
            expect(find.byKey(_entrar), findsOneWidget);
            if (pantalla.textoDelEnlace != null) {
              await tester.ensureVisible(find.byKey(_recuperar));
              expect(find.byKey(_recuperar), findsOneWidget);
            }
          });
        }
      }
    }
  });
}
