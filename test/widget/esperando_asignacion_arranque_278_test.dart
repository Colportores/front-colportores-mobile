// Vista 18, seguimiento #278 (HU-AUTH-008): el arranque mientras se consulta el estado de la cuenta
// («Revisando con el servidor…», con un tope de 15 s que pasa al aviso de sin conexión) y el aviso
// de los módulos bloqueados cuando el estado nunca se pudo consultar. Casos límite de cada flujo.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/asignacion_campania_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/estado_cuenta_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/esperando_asignacion_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/asignacion_campania_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

final _revisando = find.byKey(const Key('revisando_cuenta_pagina'));
final _textoRevisando = find.text('Revisando con el servidor…');
final _titulo = find.byKey(const Key('espera_titulo'));
final _actualizar = find.byKey(const Key('espera_actualizar'));
final _configuracion = find.byKey(const Key('espera_configuracion'));
final _principal = find.byKey(const Key('inicio_principal'));
final _login = find.byKey(const Key('login_enviar'));
final _sinConexion = find.byKey(const Key('espera_sin_conexion'));
final _error = find.byKey(const Key('espera_error'));
final _aviso = find.byKey(const Key('modulo_bloqueado_aviso'));
final _avisoReintentar = find.byKey(const Key('modulo_bloqueado_reintentar'));
final _avisoRevisando = find.byKey(const Key('modulo_bloqueado_revisando'));

/// Los 15 s del arranque (los mismos del GPS, #267).
const _tope = Duration(seconds: 15);

/// Teléfono sin nada guardado: el cierre de sesión pide la confirmación común.
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

late EstadoCuentaEnMemoria _backend;
late EstadoCuentaLocalEnMemoria _recordado;
late ProviderContainer _container;

Future<void> _montar(
  WidgetTester tester, {
  EstadoCuenta estado = EstadoCuenta.pendienteAsignacion,
}) async {
  _backend = EstadoCuentaEnMemoria(estado: estado);
  _recordado = EstadoCuentaLocalEnMemoria();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        ahoraEsperaProvider.overrideWithValue(() => DateTime(2026, 10, 7, 14, 30)),
        asignacionCampaniaDataSourceProvider.overrideWithValue(AsignacionCampaniaEnMemoria()),
        estadoCuentaRemoteDataSourceProvider.overrideWithValue(_backend),
        estadoCuentaLocalDataSourceProvider.overrideWithValue(_recordado),
        datosLocalesRepositoryProvider.overrideWithValue(_SinDatosLocales()),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  _container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// Pone el login en vuelo hasta que la consulta del estado queda esperando (sin `pumpAndSettle`: el
/// indicador del arranque no se queda quieto).
Future<void> _entrar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
  await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
  await tester.ensureVisible(_login);
  await tester.tap(_login);
  await tester.pump();
  await tester.pump();
}

/// Entra con un backend que no contesta: queda en el arranque, con la consulta colgada.
Future<Completer<void>> _entrarSinRespuesta(
  WidgetTester tester, {
  EstadoCuenta estado = EstadoCuenta.pendienteAsignacion,
}) async {
  await _montar(tester, estado: estado);
  final colgada = _backend.demora = Completer<void>();
  await _entrar(tester);
  return colgada;
}

/// Unos cuadros cortos (50 ms en total): menos que la primera espera del reintento automático de
/// Riverpod (200 ms), así que lo que se vea ahí es lo que ve la persona sin que corra más reloj.
Future<void> _unosCuadros(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// Deja pasar el tope del arranque y dibuja el aviso que sigue.
Future<void> _vencerElTope(WidgetTester tester) async {
  await tester.pump(_tope);
  await _unosCuadros(tester);
  await tester.pumpAndSettle();
}

/// Cierra el aviso de módulo bloqueado que esté a la vista, como lo haría la persona: con su ✕ (el
/// que ofrece «Reintentar» no se va solo) o esperando a que se vaya (4 s).
Future<void> _cerrarAviso(WidgetTester tester) async {
  if (find.byType(SnackBar).evaluate().isEmpty) return;
  final cerrar = find.descendant(of: find.byType(SnackBar), matching: find.byIcon(Icons.close));
  if (cerrar.evaluate().isNotEmpty) {
    await tester.tap(cerrar);
  } else {
    await tester.pump(const Duration(seconds: 5));
  }
  await tester.pumpAndSettle();
}

/// Toca el botón «Reintentar» de la pantalla. Un aviso de módulo bloqueado a la vista lo tapa en
/// pantalla chica: antes se lo cierra.
Future<void> _reintentar(WidgetTester tester) async {
  await _cerrarAviso(tester);
  await tester.ensureVisible(_actualizar);
  await tester.tap(_actualizar);
  await tester.pumpAndSettle();
}

/// Toca un módulo de la barra. Por defecto espera a que termine el aviso anterior de irse y el nuevo
/// de entrar; con [esperar] `false` solo da un cuadro (dos toques antes de que el primero termine).
Future<void> _tocarModulo(WidgetTester tester, String modulo, {bool esperar = true}) async {
  await tester.tap(find.byKey(Key('inicio_pestana_$modulo')));
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Activa el botón «Actualizar» / «Reintentar» de la pantalla con el aviso del módulo a la vista.
/// El aviso (al pie) tapa el botón, que también está al pie: no se lo puede tocar, pero sí
/// activarlo (teclado, TalkBack) sin cerrar el aviso antes.
void _tocarActualizarBajoElAviso(WidgetTester tester) {
  tester.widget<FilledButton>(_actualizar).onPressed!();
}

Future<void> _cerrarSesionDesdeConfiguracion(WidgetTester tester) async {
  await tester.tap(_configuracion);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
  await tester.pumpAndSettle();
}

void _tamano(WidgetTester tester, Size tam, {double texto = 1}) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Finder _textoDelAviso(String texto) => find.descendant(of: _aviso, matching: find.text(texto));

void main() {
  group('TextosModuloBloqueado.para', () {
    test('con la cuenta pendiente o suspendida, los textos de siempre', () {
      expect(
        TextosModuloBloqueado.para(EstadoCuenta.pendienteAsignacion),
        'Disponible cuando tu coordinador te asigne a una campaña.',
      );
      expect(
        TextosModuloBloqueado.para(EstadoCuenta.suspendida),
        'Tu cuenta está suspendida. Contactá al administrador.',
      );
    });

    test('sin estado conocido, nunca dice que la cuenta espera asignación', () {
      for (final sinConexion in [true, false]) {
        expect(
          TextosModuloBloqueado.para(null, sinConexion: sinConexion),
          isNot(TextosModuloBloqueado.pendiente),
        );
      }
    });

    test('sin estado conocido y sin conexión, el texto de la pantalla', () {
      expect(
        TextosModuloBloqueado.para(null, sinConexion: true),
        'No hay conexión para revisar tu cuenta. Conectate a internet y tocá Reintentar.',
      );
    });

    test('sin estado conocido y con el servidor caído, el texto de la pantalla sin estado', () {
      expect(TextosModuloBloqueado.para(null), TextosEsperaAsignacion.sinEstado);
    });

    test('el texto sin estado nombra el botón que hay: «Reintentar», no «Actualizar»', () {
      expect(
        TextosEsperaAsignacion.sinEstado,
        'No pudimos consultar el estado de tu cuenta. Tocá Reintentar para probar de nuevo; si '
        'sigue pasando, avisale a tu coordinador.',
      );
    });
  });

  group('18A·02 — arranque con contexto y tope de 15 s', () {
    testWidgets('mientras consulta al entrar: indicador con «Revisando con el servidor…»', (
      tester,
    ) async {
      final colgada = await _entrarSinRespuesta(tester);

      expect(_revisando, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_textoRevisando, findsOneWidget);
      expect(_principal, findsNothing);
      expect(_titulo, findsNothing);

      colgada.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a los 14 s sigue esperando; a los 15 s pasa al aviso de sin conexión sin estado '
        'conocido, con «Reintentar» y Configuración a mano', (tester) async {
      await _entrarSinRespuesta(tester);

      await tester.pump(const Duration(seconds: 14));
      expect(_revisando, findsOneWidget);
      expect(_sinConexion, findsNothing);
      expect(_backend.consultas, 1);

      // A los 15 s la pantalla ya es el aviso, en el primer cuadro: sin esperas de por medio ni
      // consultas de más (el reintento automático de Riverpod lo demoraba más de 3 minutos).
      await tester.pump(const Duration(seconds: 1));
      await _unosCuadros(tester);
      expect(_revisando, findsNothing);
      expect(_sinConexion, findsOneWidget);
      expect(_backend.consultas, 1);
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión'), findsOneWidget);
      expect(
        find.text(
          'No hay conexión para revisar tu cuenta. Conectate a internet y tocá Reintentar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);
      expect(_configuracion, findsOneWidget);
      // No afirma nada de la cuenta (HU-AUTH-008).
      expect(find.textContaining('Esperando asignación'), findsNothing);
      expect(find.textContaining('CUENTA PENDIENTE'), findsNothing);
      expect(_principal, findsNothing);
    });

    testWidgets('si la respuesta llega antes del tope, entra normal y el tope no vuelve a saltar', (
      tester,
    ) async {
      final colgada = await _entrarSinRespuesta(tester);
      await tester.pump(const Duration(seconds: 10));

      colgada.complete();
      await tester.pumpAndSettle();
      expect(find.text('Esperando asignación'), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(_sinConexion, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con un estado recordado en el teléfono, al vencer el tope rige ese estado', (
      tester,
    ) async {
      await _entrarSinRespuesta(tester);
      final usuarioId = _container.read(sesionProvider).value!.usuarioId;
      await _recordado.guardar(usuarioId, EstadoCuenta.suspendida);

      await _vencerElTope(tester);

      expect(find.text('Cuenta suspendida'), findsOneWidget);
      expect(_sinConexion, findsNothing);
    });

    testWidgets('con la cuenta activa recordada, al vencer el tope entra a la principal', (
      tester,
    ) async {
      await _entrarSinRespuesta(tester);
      final usuarioId = _container.read(sesionProvider).value!.usuarioId;
      await _recordado.guardar(usuarioId, EstadoCuenta.activa);

      await _vencerElTope(tester);

      expect(_principal, findsOneWidget);
      expect(_titulo, findsNothing);
    });

    testWidgets('el tope no se cumple si el servidor contesta con un error: ese aviso enseguida, '
        'con una sola consulta', (tester) async {
      await _montar(tester);
      _backend.falla = const ServidorException(status: 503);

      await _entrar(tester);
      await _unosCuadros(tester);

      expect(_error, findsOneWidget);
      expect(_revisando, findsNothing);
      expect(_backend.consultas, 1);

      // Y no vuelve a consultar solo: a los 15 s sigue siendo una consulta.
      await tester.pump(_tope);
      await tester.pumpAndSettle();
      expect(_error, findsOneWidget);
      expect(_backend.consultas, 1);
    });

    testWidgets('la respuesta que llega después del tope, sin estado conocido: la pantalla pasa '
        'sola a lo que contestó y queda recordada', (tester) async {
      final colgada = await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);
      expect(_sinConexion, findsOneWidget);

      colgada.complete();
      await tester.pumpAndSettle();

      expect(_sinConexion, findsNothing);
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final usuarioId = _container.read(sesionProvider).value!.usuarioId;
      expect(await _recordado.leer(usuarioId), EstadoCuenta.pendienteAsignacion);

      // El próximo arranque sin red entra con lo que había contestado.
      _backend.simularSinConexion = true;
      _container.invalidate(estadoCuentaProvider);
      await tester.pumpAndSettle();
      expect(find.text('Esperando asignación'), findsOneWidget);
    });

    testWidgets('la respuesta tardía que dice «suspendida» también cambia la pantalla', (
      tester,
    ) async {
      final colgada = await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);
      _backend.estado = EstadoCuenta.suspendida;

      colgada.complete();
      await tester.pumpAndSettle();

      expect(find.text('Cuenta suspendida'), findsOneWidget);
      expect(_sinConexion, findsNothing);
    });

    testWidgets('la respuesta tardía que dice «activa» lleva a la principal', (tester) async {
      final colgada = await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);
      _backend.estado = EstadoCuenta.activa;

      colgada.complete();
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_sinConexion, findsNothing);
    });

    testWidgets('la respuesta tardía que es un error no cambia la pantalla', (tester) async {
      final colgada = await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);
      _backend.falla = const ServidorException(status: 503);

      colgada.complete();
      await tester.pumpAndSettle();

      expect(_sinConexion, findsOneWidget);
      expect(_error, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con la cuenta pendiente recordada, la respuesta tardía «activa» le abre «Ya te '
        'asignaron»', (tester) async {
      final colgada = await _entrarSinRespuesta(tester);
      final usuarioId = _container.read(sesionProvider).value!.usuarioId;
      await _recordado.guardar(usuarioId, EstadoCuenta.pendienteAsignacion);
      await _vencerElTope(tester);
      expect(find.text('Esperando asignación'), findsOneWidget);
      _backend.estado = EstadoCuenta.activa;

      colgada.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('cuenta_asignada')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(_principal, findsOneWidget);
    });

    testWidgets('si ya entró a su inicio con el último estado conocido, la respuesta tardía no la '
        'saca de ahí: queda guardada para el próximo arranque', (tester) async {
      final colgada = await _entrarSinRespuesta(tester);
      final usuarioId = _container.read(sesionProvider).value!.usuarioId;
      await _recordado.guardar(usuarioId, EstadoCuenta.activa);
      await _vencerElTope(tester);
      expect(_principal, findsOneWidget);
      _backend.estado = EstadoCuenta.pendienteAsignacion;

      colgada.complete();
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_titulo, findsNothing);
      expect(tester.takeException(), isNull);
      expect(await _recordado.leer(usuarioId), EstadoCuenta.pendienteAsignacion);
    });

    testWidgets('con un «Reintentar» consultando, la respuesta tardía se aplica, pero manda la del '
        'botón, que se pidió más tarde', (tester) async {
      final colgada = await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);
      final lenta = _backend.demora = Completer<void>();
      final antes = _backend.consultas;

      await tester.ensureVisible(_actualizar);
      await tester.tap(_actualizar);
      await tester.pump();
      expect(find.text('Consultando…'), findsOneWidget);

      // Ninguna consulta pedida después contestó todavía: la tardía cambia lo que se ve.
      colgada.complete();
      await tester.pump();
      expect(_container.read(estadoCuentaProvider).value, EstadoCuenta.pendienteAsignacion);
      expect(find.text('Consultando…'), findsOneWidget);

      _backend.estado = EstadoCuenta.suspendida;
      lenta.complete();
      await tester.pumpAndSettle();
      expect(_backend.consultas, antes + 1);
      expect(find.text('Cuenta suspendida'), findsOneWidget);
    });

    testWidgets('la respuesta tardía de un arranque anterior no pisa el arranque nuevo', (
      tester,
    ) async {
      final colgada = await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);
      await _cerrarSesionDesdeConfiguracion(tester);
      _backend.demora = Completer<void>();
      await _entrar(tester);
      expect(_revisando, findsOneWidget);

      colgada.complete();
      await tester.pump();
      await _unosCuadros(tester);

      expect(_revisando, findsOneWidget);
      expect(_container.read(estadoCuentaProvider).isLoading, isTrue);
      expect(tester.takeException(), isNull);
      _backend.demora!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('doble toque en «Reintentar» después del tope: una sola consulta', (tester) async {
      await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);
      final antes = _backend.consultas;
      final lenta = _backend.demora = Completer<void>();

      await tester.ensureVisible(_actualizar);
      await tester.tap(_actualizar);
      await tester.pump();
      await tester.tap(_actualizar, warnIfMissed: false);
      await tester.pump();
      expect(find.text('Consultando…'), findsOneWidget);
      lenta.complete();
      await tester.pumpAndSettle();

      expect(_backend.consultas, antes + 1);
      expect(find.text('Esperando asignación'), findsOneWidget);
    });

    testWidgets('falla a mitad del «Reintentar» después del tope: el botón vuelve a andar y se '
        'puede probar de nuevo', (tester) async {
      await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);
      final lenta = _backend.demora = Completer<void>();
      _backend.falla = const ServidorException(status: 503);

      await tester.ensureVisible(_actualizar);
      await tester.tap(_actualizar);
      await tester.pump();
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNull);
      lenta.complete();
      await tester.pumpAndSettle();

      expect(_error, findsOneWidget);
      expect(find.text('Consultando…'), findsNothing);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);

      _backend
        ..demora = null
        ..falla = null;
      await _reintentar(tester);
      expect(find.text('Esperando asignación'), findsOneWidget);
    });

    testWidgets('volver atrás y reentrar: Configuración y de vuelta deja el mismo aviso, sin un '
        'segundo arranque', (tester) async {
      await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);

      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('configuracion_pagina')), findsOneWidget);
      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();

      expect(_sinConexion, findsOneWidget);
      expect(_revisando, findsNothing);
      await tester.pump(const Duration(seconds: 30));
      expect(_sinConexion, findsOneWidget);
    });

    testWidgets('el botón atrás del sistema en el aviso no deja a la persona sin pantalla', (
      tester,
    ) async {
      await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_sinConexion, findsOneWidget);
      expect(_actualizar, findsOneWidget);
    });

    testWidgets('salir y volver a entrar: el nuevo arranque tiene su propio tope de 15 s', (
      tester,
    ) async {
      await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);

      await _cerrarSesionDesdeConfiguracion(tester);
      expect(_login, findsOneWidget);

      final otra = _backend.demora = Completer<void>();
      final antes = _backend.consultas;
      await _entrar(tester);
      expect(_revisando, findsOneWidget);

      await tester.pump(const Duration(seconds: 14));
      expect(_revisando, findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await _unosCuadros(tester);
      expect(_sinConexion, findsOneWidget);
      expect(_backend.consultas, antes + 1);
      otra.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('salir con la respuesta de la primera consulta todavía colgada: al llegar tarde no '
        'pisa el login', (tester) async {
      final colgada = await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);
      await _cerrarSesionDesdeConfiguracion(tester);

      colgada.complete();
      await tester.pumpAndSettle();

      expect(_login, findsOneWidget);
      expect(_revisando, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('18A·02 — datos límite del arranque: tamaños y accesibilidad', () {
    for (final (tam, texto, nombre) in const [
      (Size(360, 640), 1.0, '360x640'),
      (Size(360, 640), 2.0, '360x640 con texto 2.0'),
      (Size(412, 915), 1.0, '412x915'),
    ]) {
      testWidgets('el arranque a $nombre: texto visible, sin overflow y con contraste', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        try {
          final colgada = await _entrarSinRespuesta(tester);
          _tamano(tester, tam, texto: texto);
          await tester.pump(const Duration(milliseconds: 500));

          expect(tester.takeException(), isNull);
          expect(_textoRevisando, findsOneWidget);
          final caja = tester.getRect(_textoRevisando);
          expect(caja.left, greaterThanOrEqualTo(0));
          expect(caja.right, lessThanOrEqualTo(tam.width));
          expect(caja.bottom, lessThanOrEqualTo(tam.height));
          await expectLater(tester, meetsGuideline(textContrastGuideline));

          colgada.complete();
          await tester.pumpAndSettle();
        } finally {
          semantica.dispose();
        }
      });

      testWidgets('el aviso que sigue al tope a $nombre: «Reintentar» alcanzable y Configuración '
          'con nombre', (tester) async {
        final semantica = tester.ensureSemantics();
        try {
          await _entrarSinRespuesta(tester);
          _tamano(tester, tam, texto: texto);
          await _vencerElTope(tester);

          expect(tester.takeException(), isNull);
          await tester.ensureVisible(_actualizar);
          await tester.pump();
          expect(_actualizar, findsOneWidget);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        } finally {
          semantica.dispose();
        }
      });
    }

    testWidgets('el texto del arranque se anuncia a quien usa un lector de pantalla', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      try {
        final colgada = await _entrarSinRespuesta(tester);

        expect(tester.getSemantics(_textoRevisando), isSemantics(isLiveRegion: true));
        expect(find.bySemanticsLabel('Revisando con el servidor…'), findsOneWidget);

        colgada.complete();
        await tester.pumpAndSettle();
      } finally {
        semantica.dispose();
      }
    });
  });

  group('módulo bloqueado sin estado conocido — mismo aviso que la pantalla', () {
    const modulos = ['mapa', 'lista', 'agenda', 'ventas'];

    testWidgets('sin conexión: cada uno de los cuatro módulos dice lo de la pantalla', (
      tester,
    ) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();

      for (final modulo in modulos) {
        await _tocarModulo(tester, modulo);
        expect(
          _textoDelAviso(TextosEsperaAsignacion.sinConexionSinEstado),
          findsOneWidget,
          reason: modulo,
        );
        expect(find.text(TextosModuloBloqueado.pendiente), findsNothing, reason: modulo);
      }
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('error del servidor: cada uno de los cuatro módulos dice el texto de la pantalla '
        'sin estado', (tester) async {
      await _montar(tester);
      _backend.falla = const ServidorException(status: 503);
      await _entrar(tester);
      await tester.pumpAndSettle();

      for (final modulo in modulos) {
        await _tocarModulo(tester, modulo);
        expect(_textoDelAviso(TextosEsperaAsignacion.sinEstado), findsOneWidget, reason: modulo);
        expect(find.text(TextosModuloBloqueado.pendiente), findsNothing, reason: modulo);
      }
      await tester.pumpAndSettle();
    });

    testWidgets('después del tope del arranque, el aviso del módulo es el de sin conexión', (
      tester,
    ) async {
      await _entrarSinRespuesta(tester);
      await _vencerElTope(tester);

      await _tocarModulo(tester, 'agenda');

      expect(_textoDelAviso(TextosEsperaAsignacion.sinConexionSinEstado), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('si la causa cambia (sin conexión y después el servidor caído), el módulo dice lo '
        'de la pantalla en cada momento', (tester) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'mapa');
      expect(_textoDelAviso(TextosEsperaAsignacion.sinConexionSinEstado), findsOneWidget);

      _backend
        ..simularSinConexion = false
        ..falla = const ServidorException(status: 500);
      await _reintentar(tester);
      expect(_error, findsOneWidget);
      await _tocarModulo(tester, 'mapa');
      expect(_textoDelAviso(TextosEsperaAsignacion.sinEstado), findsOneWidget);

      _backend
        ..falla = null
        ..simularSinConexion = true;
      await _reintentar(tester);
      expect(_sinConexion, findsOneWidget);
      await _tocarModulo(tester, 'mapa');
      expect(_textoDelAviso(TextosEsperaAsignacion.sinConexionSinEstado), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('al saberse el estado, el módulo vuelve a decir lo de la cuenta pendiente', (
      tester,
    ) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      _backend.simularSinConexion = false;
      await _reintentar(tester);

      await _tocarModulo(tester, 'lista');

      expect(_textoDelAviso(TextosModuloBloqueado.pendiente), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('desde Configuración, sin conexión: la barra bloqueada avisa lo de la pantalla', (
      tester,
    ) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();

      await _tocarModulo(tester, 'ventas');

      expect(_textoDelAviso(TextosEsperaAsignacion.sinConexionSinEstado), findsOneWidget);
      expect(find.text(TextosModuloBloqueado.pendiente), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('desde Configuración, con el servidor caído: el texto de la pantalla sin estado', (
      tester,
    ) async {
      await _montar(tester);
      _backend.falla = const ServidorException(status: 503);
      await _entrar(tester);
      await tester.pumpAndSettle();
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();

      await _tocarModulo(tester, 'mapa');

      expect(_textoDelAviso(TextosEsperaAsignacion.sinEstado), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('desde Configuración, si la causa cambió en la pantalla de espera: dice la '
        'última', (tester) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      _backend
        ..simularSinConexion = false
        ..falla = const ServidorException(status: 500);
      await _reintentar(tester);

      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'lista');

      expect(_textoDelAviso(TextosEsperaAsignacion.sinEstado), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('dos toques seguidos en módulos distintos: un solo aviso, el último', (
      tester,
    ) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();

      await _tocarModulo(tester, 'mapa', esperar: false);
      await _tocarModulo(tester, 'ventas', esperar: false);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(_textoDelAviso(TextosEsperaAsignacion.sinConexionSinEstado), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('después de cerrar el aviso, el botón «Reintentar» de la pantalla sigue '
        'funcionando', (tester) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'mapa');
      expect(find.byType(SnackBar), findsOneWidget);
      _backend.simularSinConexion = false;

      await _reintentar(tester);

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Esperando asignación'), findsOneWidget);
    });

    testWidgets('sin estado conocido el aviso lleva «Reintentar» y su ✕, y no se va solo', (
      tester,
    ) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();

      await _tocarModulo(tester, 'mapa');
      expect(_avisoReintentar, findsOneWidget);
      expect(find.descendant(of: _aviso, matching: find.text('Reintentar')), findsOneWidget);
      expect(find.descendant(of: _aviso, matching: find.byIcon(Icons.close)), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget);

      await tester.tap(find.descendant(of: _aviso, matching: find.byIcon(Icons.close)));
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);
    });

    testWidgets('con el estado conocido el aviso no lleva «Reintentar» y se va solo a los 4 s', (
      tester,
    ) async {
      await _montar(tester);
      await _entrar(tester);
      await tester.pumpAndSettle();

      await _tocarModulo(tester, 'mapa');
      expect(_textoDelAviso(TextosModuloBloqueado.pendiente), findsOneWidget);
      expect(_avisoReintentar, findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);
    });

    testWidgets('«Reintentar» del aviso consulta como el botón de la pantalla y la deja sin '
        'avisos', (tester) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'mapa');
      final antes = _backend.consultas;
      _backend.simularSinConexion = false;

      await tester.tap(_avisoReintentar);
      await tester.pumpAndSettle();

      expect(_backend.consultas, antes + 1);
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('doble toque en «Reintentar» del aviso: una sola consulta, con «Consultando…»', (
      tester,
    ) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'ventas');
      final antes = _backend.consultas;
      final lenta = _backend.demora = Completer<void>();
      _backend.simularSinConexion = false;

      await tester.tap(_avisoReintentar);
      await tester.pump();
      await tester.tap(_avisoReintentar, warnIfMissed: false);
      await tester.pump();
      expect(find.text('Consultando…'), findsOneWidget);
      lenta.complete();
      await tester.pumpAndSettle();

      expect(_backend.consultas, antes + 1);
      expect(find.text('Esperando asignación'), findsOneWidget);
    });

    testWidgets('falla a mitad de la consulta del aviso: la pantalla muestra el error y el módulo '
        'vuelve a ofrecer «Reintentar»', (tester) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'agenda');
      final lenta = _backend.demora = Completer<void>();
      _backend
        ..simularSinConexion = false
        ..falla = const ServidorException(status: 503);

      await tester.tap(_avisoReintentar);
      await tester.pump();
      lenta.complete();
      await tester.pumpAndSettle();

      expect(_error, findsOneWidget);
      expect(find.text('Consultando…'), findsNothing);
      await _tocarModulo(tester, 'agenda');
      expect(_textoDelAviso(TextosEsperaAsignacion.sinEstado), findsOneWidget);
      expect(_avisoReintentar, findsOneWidget);
    });
  });

  group('módulo bloqueado sin estado conocido — «Reintentar» desde Configuración', () {
    Future<void> irAConfiguracionSinConexion(WidgetTester tester) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
    }

    testWidgets('consulta con «Revisando con el servidor…» y avisa lo que contestó', (
      tester,
    ) async {
      await irAConfiguracionSinConexion(tester);
      await _tocarModulo(tester, 'ventas');
      final antes = _backend.consultas;
      final lenta = _backend.demora = Completer<void>();
      _backend.simularSinConexion = false;

      await tester.tap(_avisoReintentar);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _avisoRevisando, matching: find.text('Revisando con el servidor…')),
        findsOneWidget,
      );
      expect(_aviso, findsNothing);
      lenta.complete();
      await tester.pumpAndSettle();

      expect(_backend.consultas, antes + 1);
      expect(_avisoRevisando, findsNothing);
      expect(_textoDelAviso(TextosModuloBloqueado.pendiente), findsOneWidget);
      expect(_avisoReintentar, findsNothing);
    });

    testWidgets('si sigue sin conexión, vuelve el aviso de la causa con «Reintentar»', (
      tester,
    ) async {
      await irAConfiguracionSinConexion(tester);
      await _tocarModulo(tester, 'mapa');

      await tester.tap(_avisoReintentar);
      await tester.pumpAndSettle();

      expect(_avisoRevisando, findsNothing);
      expect(_textoDelAviso(TextosEsperaAsignacion.sinConexionSinEstado), findsOneWidget);
      expect(_avisoReintentar, findsOneWidget);
    });

    testWidgets('si ahora el servidor falla, avisa el texto del servidor y sigue ofreciendo '
        '«Reintentar»', (tester) async {
      await irAConfiguracionSinConexion(tester);
      await _tocarModulo(tester, 'lista');
      _backend
        ..simularSinConexion = false
        ..falla = const ServidorException(status: 503);

      await tester.tap(_avisoReintentar);
      await tester.pumpAndSettle();

      expect(_textoDelAviso(TextosEsperaAsignacion.sinEstado), findsOneWidget);
      expect(_avisoReintentar, findsOneWidget);
    });

    testWidgets('si la cuenta ya accede, no avisa nada', (tester) async {
      await irAConfiguracionSinConexion(tester);
      await _tocarModulo(tester, 'mapa');
      _backend
        ..simularSinConexion = false
        ..estado = EstadoCuenta.activa;

      await tester.tap(_avisoReintentar);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(_container.read(estadoCuentaProvider).value, EstadoCuenta.activa);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un módulo tocado mientras consulta: una sola consulta y sigue «Revisando…»', (
      tester,
    ) async {
      await irAConfiguracionSinConexion(tester);
      await _tocarModulo(tester, 'mapa');
      final antes = _backend.consultas;
      final lenta = _backend.demora = Completer<void>();
      _backend.simularSinConexion = false;

      await tester.tap(_avisoReintentar);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'agenda');
      expect(_avisoRevisando, findsOneWidget);
      expect(_aviso, findsNothing);
      lenta.complete();
      await tester.pumpAndSettle();

      expect(_backend.consultas, antes + 1);
      expect(_textoDelAviso(TextosModuloBloqueado.pendiente), findsOneWidget);
    });

    testWidgets('si se vuelve a la pantalla de espera mientras consulta, no se rompe nada y se '
        've lo que contestó', (tester) async {
      await irAConfiguracionSinConexion(tester);
      await _tocarModulo(tester, 'mapa');
      final lenta = _backend.demora = Completer<void>();
      _backend.simularSinConexion = false;

      await tester.tap(_avisoReintentar);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();
      lenta.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(_avisoRevisando, findsNothing);
    });
  });

  group('el aviso del módulo no sobrevive a su pantalla ni a lo que dejó de ser cierto', () {
    /// Sin conexión al abrir: la pantalla de espera con el aviso del módulo a la vista.
    Future<void> conAvisoDelMapa(WidgetTester tester) async {
      // Alto de sobra: el aviso no tapa el botón «Reintentar» de la pantalla (ni Configuración).
      _tamano(tester, const Size(700, 1000));
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'mapa');
      expect(_aviso, findsOneWidget);
      expect(_avisoReintentar, findsOneWidget);
    }

    /// «Cerrar sesión» de Configuración con el aviso a la vista. El aviso (sobre la barra de
    /// pestañas) puede tapar el botón, que está al pie: se lo activa sin pasar por el toque.
    Future<void> cerrarSesionConAviso(WidgetTester tester) async {
      final boton = tester.widget<OutlinedButton>(
        find.byKey(const Key('configuracion_cerrar_sesion')),
      );
      boton.onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
      await tester.pumpAndSettle();
    }

    /// El tope vencido (sin respuesta del servidor) y el aviso del módulo a la vista.
    Future<Completer<void>> colgadaConAvisoDelMapa(
      WidgetTester tester, {
      required EstadoCuenta contestara,
    }) async {
      _tamano(tester, const Size(700, 1000));
      final colgada = await _entrarSinRespuesta(tester, estado: contestara);
      await _vencerElTope(tester);
      await _tocarModulo(tester, 'mapa');
      expect(_aviso, findsOneWidget);
      return colgada;
    }

    testWidgets('el botón «Reintentar» de la pantalla encuentra la cuenta activa: el inicio queda '
        'sin el aviso', (tester) async {
      await conAvisoDelMapa(tester);
      _backend
        ..simularSinConexion = false
        ..estado = EstadoCuenta.activa;

      _tocarActualizarBajoElAviso(tester);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_aviso, findsNothing);
      expect(_avisoReintentar, findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el botón «Reintentar» de la pantalla encuentra la cuenta pendiente: ya no '
        'queda un aviso que habla de la conexión', (tester) async {
      await conAvisoDelMapa(tester);
      _backend.simularSinConexion = false;

      _tocarActualizarBajoElAviso(tester);
      await tester.pumpAndSettle();

      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si el botón «Reintentar» falla de nuevo, el aviso tampoco queda: la pantalla '
        'dice la causa', (tester) async {
      await conAvisoDelMapa(tester);
      final lenta = _backend.demora = Completer<void>();

      _tocarActualizarBajoElAviso(tester);
      await tester.pump();
      expect(_aviso, findsOneWidget, reason: 'mientras consulta sigue siendo cierto');
      lenta.complete();
      await tester.pumpAndSettle();

      expect(_sinConexion, findsOneWidget);
      expect(_aviso, findsNothing);
    });

    testWidgets('deslizar para refrescar con la cuenta activa también saca el aviso', (
      tester,
    ) async {
      await conAvisoDelMapa(tester);
      _backend
        ..simularSinConexion = false
        ..estado = EstadoCuenta.activa;

      await tester.fling(find.byType(Scrollable).first, const Offset(0, 400), 1500);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el aviso a la vista, Configuración y «Cerrar sesión»: el login no hereda el '
        'aviso ni su «Reintentar»', (tester) async {
      await conAvisoDelMapa(tester);
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget, reason: 'el aviso sigue a la vista sobre Configuración');

      await cerrarSesionConAviso(tester);

      expect(_login, findsOneWidget);
      expect(_aviso, findsNothing);
      expect(_avisoReintentar, findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el aviso que se tocó desde Configuración, «Cerrar sesión» tampoco deja '
        'nada sobre el login', (tester) async {
      _tamano(tester, const Size(700, 1000));
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'agenda');
      expect(_avisoReintentar, findsOneWidget);

      await cerrarSesionConAviso(tester);

      expect(_login, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Volver» desde Configuración se lleva el aviso que se tocó ahí: su «Reintentar» '
        'es de esa pantalla', (tester) async {
      _tamano(tester, const Size(700, 1000));
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'ventas');
      expect(_avisoReintentar, findsOneWidget);

      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();

      expect(_actualizar, findsOneWidget);
      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la respuesta tardía que dice «activa» con el aviso a la vista: el inicio queda '
        'sin el aviso', (tester) async {
      final colgada = await colgadaConAvisoDelMapa(tester, contestara: EstadoCuenta.activa);

      colgada.complete();
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_aviso, findsNothing);
      expect(_avisoReintentar, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la respuesta tardía que dice «pendiente» con el aviso a la vista: ya no queda '
        'un aviso que dice sin conexión', (tester) async {
      final colgada = await colgadaConAvisoDelMapa(
        tester,
        contestara: EstadoCuenta.pendienteAsignacion,
      );

      colgada.complete();
      await tester.pumpAndSettle();

      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
      // Y ahora el módulo dice lo de la cuenta pendiente, sin «Reintentar».
      await _tocarModulo(tester, 'mapa');
      expect(_textoDelAviso(TextosModuloBloqueado.pendiente), findsOneWidget);
      expect(_avisoReintentar, findsNothing);
    });

    testWidgets('la respuesta tardía con el aviso tocado desde Configuración: el aviso no queda '
        'diciendo lo viejo', (tester) async {
      _tamano(tester, const Size(700, 1000));
      final colgada = await _entrarSinRespuesta(tester, estado: EstadoCuenta.activa);
      await _vencerElTope(tester);
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'mapa');
      expect(_avisoReintentar, findsOneWidget);

      colgada.complete();
      await tester.pumpAndSettle();

      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Reintentar» del aviso que encuentra la cuenta activa: no queda ningún aviso '
        'sobre el inicio', (tester) async {
      await conAvisoDelMapa(tester);
      _backend
        ..simularSinConexion = false
        ..estado = EstadoCuenta.activa;

      await tester.tap(_avisoReintentar);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el aviso que se muestra después de cerrar uno viejo sigue a la vista: cerrar es '
        'solo por lo que dejó de ser cierto', (tester) async {
      await conAvisoDelMapa(tester);
      _backend.simularSinConexion = true;

      _tocarActualizarBajoElAviso(tester);
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);

      await _tocarModulo(tester, 'lista');
      expect(_aviso, findsOneWidget);
      expect(_avisoReintentar, findsOneWidget);
    });
  });

  group('módulo bloqueado — «Reintentar» a mano con tope de 15 s (QA #278)', () {
    testWidgets('desde Configuración: si el servidor no contesta, a los 15 s vuelve el aviso de '
        'la causa con «Reintentar»', (tester) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await tester.tap(_configuracion);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'mapa');
      _backend.demora = Completer<void>();
      _backend.simularSinConexion = false;

      await tester.tap(_avisoReintentar);
      await tester.pumpAndSettle();
      expect(_avisoRevisando, findsOneWidget);
      await tester.pump(const Duration(seconds: 13));
      expect(_avisoRevisando, findsOneWidget, reason: 'a los 14 s todavía espera');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(_avisoRevisando, findsNothing);
      expect(_textoDelAviso(TextosEsperaAsignacion.sinConexionSinEstado), findsOneWidget);
      expect(_avisoReintentar, findsOneWidget);
      _backend.demora!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('desde la pantalla de espera: «Reintentar» del aviso tampoco queda colgado', (
      tester,
    ) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await _entrar(tester);
      await tester.pumpAndSettle();
      await _tocarModulo(tester, 'mapa');
      _backend.demora = Completer<void>();
      _backend.simularSinConexion = false;

      await tester.tap(_avisoReintentar);
      await tester.pump();
      expect(find.text('Consultando…'), findsOneWidget);
      await tester.pump(_tope + const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('Consultando…'), findsNothing);
      expect(_sinConexion, findsOneWidget);
      _backend.demora!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('módulo bloqueado sin estado conocido — tamaños y accesibilidad del aviso', () {
    // La fuente de los tests (Ahem) ocupa el doble de ancho que Inter. El aviso lleva «Reintentar»
    // y su ✕ en una fila: con Ahem a texto 2.0 esa fila no entra en 360 de ancho, aunque sí en un
    // teléfono de 360 con Inter (unos 250 de 314). Por eso el caso de texto 2.0 se mide en un
    // ancho doble (700), que para Ahem equivale a esos 360 con Inter, y alto para el aviso largo
    // del servidor caído. El caso de 360x640 a 1.0 (Ahem) es el de Inter a 2.0 en ancho.
    for (final (tam, texto, nombre) in const [
      (Size(360, 640), 1.0, '360x640'),
      (Size(700, 1000), 2.0, '700x1000 con texto 2.0 (equivale a 360 con Inter)'),
      (Size(412, 915), 1.0, '412x915'),
    ]) {
      for (final servidor in [false, true]) {
        final causa = servidor ? 'con el servidor caído' : 'sin conexión';
        testWidgets('$causa a $nombre: el aviso entero se ve, sin overflow y con contraste', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          try {
            await _montar(tester);
            if (servidor) {
              _backend.falla = const ServidorException(status: 503);
            } else {
              _backend.simularSinConexion = true;
            }
            await _entrar(tester);
            await tester.pumpAndSettle();
            _tamano(tester, tam, texto: texto);
            await tester.pump(const Duration(milliseconds: 500));

            await _tocarModulo(tester, 'mapa');

            expect(tester.takeException(), isNull);
            expect(_aviso, findsOneWidget);
            final caja = tester.getRect(_aviso);
            expect(caja.left, greaterThanOrEqualTo(0));
            expect(caja.right, lessThanOrEqualTo(tam.width));
            expect(caja.top, greaterThanOrEqualTo(0));
            expect(caja.bottom, lessThanOrEqualTo(tam.height));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          } finally {
            semantica.dispose();
          }
        });
      }
    }
  });
}
