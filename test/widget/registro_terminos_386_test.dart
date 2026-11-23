import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/terminos_de_uso.dart';
import 'package:colportores_mobile/features/auth/domain/services/abridor_de_pagina.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/abridor_de_pagina_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

/// #386: «términos de uso» del registro abre la página versionada en el navegador (decisión
/// «Términos» 07/10 y «Texto legal» 21/10) y el registro manda la versión aceptada.
///
/// Casos límite del toque: sin conexión, doble toque, falla de la apertura (el toque queda libre),
/// dos toques seguidos, volver atrás con la apertura en vuelo y reentrar, texto al 200 %.

/// Abridor de prueba: cuenta las aperturas, puede quedar «a mitad» ([demora]) y fallar.
final class _AbridorFalso implements AbridorDePagina {
  final List<Uri> abiertas = [];
  bool resultado = true;
  Object? falla;
  Completer<void>? demora;

  @override
  Future<bool> abrir(Uri direccion) async {
    abiertas.add(direccion);
    await demora?.future;
    if (falla case final f?) throw f;
    return resultado;
  }
}

final class _MonitorFalso implements MonitorConectividad {
  TipoConexion tipo = TipoConexion.wifi;
  bool lanza = false;

  @override
  Future<TipoConexion> actual() async {
    if (lanza) throw StateError('no se pudo leer la conexión');
    return tipo;
  }

  @override
  Stream<TipoConexion> get cambios => const Stream<TipoConexion>.empty();
}

const _sinConexion = 'Necesitás conexión para leer los términos.';
const _noSeAbrio =
    'No pudimos abrir los términos. Podés leerlos en colportores.github.io/terminos/v1';

/// El `ProviderScope` va como argumento directo de `pumpWidget` (riverpod_lint).
Future<void> _montar(
  WidgetTester tester, {
  required _AbridorFalso abridor,
  required _MonitorFalso monitor,
  AuthRemoteDataSourceEnMemoria? remote,
  double escalaTexto = 1,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(
        remote ?? AuthRemoteDataSourceEnMemoria(credenciales: const {}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      abridorDePaginaProvider.overrideWithValue(abridor),
      monitorConectividadProvider.overrideWithValue(monitor),
    ],
    child: MaterialApp(
      theme: temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escalaTexto)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('abrir_registro'),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => const RegistroPage())),
              child: const Text('abrir registro'),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _entrarAlRegistro(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('abrir_registro')));
  await tester.pumpAndSettle();
}

Future<void> _tocarTerminos(WidgetTester tester) async {
  final enlace = find.textRange.ofSubstring('términos de uso');
  await tester.ensureVisible(find.byKey(const Key('registro_terminos')));
  await tester.pump();
  await tester.tapOnText(enlace);
  await tester.pump();
}

void main() {
  late _AbridorFalso abridor;
  late _MonitorFalso monitor;

  setUp(() {
    abridor = _AbridorFalso();
    monitor = _MonitorFalso();
  });

  void pantallaChica(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('«términos de uso» abre la página versionada', () {
    test('la dirección es la de la v1 en GitHub Pages', () {
      expect(TerminosDeUso.versionVigente, 'v1');
      expect(TerminosDeUso.direccion.toString(), 'https://colportores.github.io/terminos/v1/');
    });

    testWidgets('con conexión abre la dirección de la v1, una vez y sin aviso', (tester) async {
      pantallaChica(tester);
      await _montar(tester, abridor: abridor, monitor: monitor);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);
      await tester.pump();

      expect(abridor.abiertas, [TerminosDeUso.direccion]);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Disponible próximamente'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con datos móviles también abre', (tester) async {
      pantallaChica(tester);
      monitor.tipo = TipoConexion.datosMoviles;
      await _montar(tester, abridor: abridor, monitor: monitor);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);

      expect(abridor.abiertas, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('sin conexión avisa con el texto del issue y no abre; al volver la red abre', (
      tester,
    ) async {
      pantallaChica(tester);
      monitor.tipo = TipoConexion.sinConexion;
      await _montar(tester, abridor: abridor, monitor: monitor);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);
      await tester.pump();

      expect(find.text(_sinConexion), findsOneWidget);
      expect(abridor.abiertas, isEmpty);

      // El toque quedó libre: con red vuelve a abrir.
      monitor.tipo = TipoConexion.wifi;
      await _tocarTerminos(tester);
      await tester.pump();

      expect(abridor.abiertas, hasLength(1));
    });

    testWidgets('si no se puede leer la conexión no afirma que falta: intenta abrir', (
      tester,
    ) async {
      pantallaChica(tester);
      monitor.lanza = true;
      await _montar(tester, abridor: abridor, monitor: monitor);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);

      expect(abridor.abiertas, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('casos límite del toque', () {
    testWidgets('doble toque: mientras la primera apertura está en vuelo no se abre otra', (
      tester,
    ) async {
      pantallaChica(tester);
      abridor.demora = Completer<void>();
      await _montar(tester, abridor: abridor, monitor: monitor);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);
      await _tocarTerminos(tester);
      await _tocarTerminos(tester);

      expect(abridor.abiertas, hasLength(1));

      // Termina la primera: el toque queda libre.
      abridor.demora!.complete();
      await tester.pump();
      abridor.demora = null;
      await _tocarTerminos(tester);

      expect(abridor.abiertas, hasLength(2));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('si el teléfono no puede abrirla avisa qué pasó y el toque queda libre', (
      tester,
    ) async {
      pantallaChica(tester);
      abridor.resultado = false;
      await _montar(tester, abridor: abridor, monitor: monitor);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);
      await tester.pump();

      expect(find.text(_noSeAbrio), findsOneWidget);

      abridor.resultado = true;
      await _tocarTerminos(tester);
      await tester.pumpAndSettle();

      expect(abridor.abiertas, hasLength(2));
      expect(find.text(_noSeAbrio), findsNothing, reason: 'el aviso viejo no queda a la vista');
    });

    testWidgets('el aviso lleva la dirección seleccionable y «Copiar» la copia entera', (
      tester,
    ) async {
      pantallaChica(tester);
      abridor.resultado = false;
      final copiado = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        llamada,
      ) async {
        if (llamada.method == 'Clipboard.setData') {
          copiado.add((llamada.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _montar(tester, abridor: abridor, monitor: monitor);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text(_noSeAbrio), findsOneWidget);

      await tester.tap(find.text('Copiar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(copiado, ['https://colportores.github.io/terminos/v1/']);
      expect(find.text('Dirección copiada.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el aviso largo con el texto al 200 % se lee entero y sin desborde', (
      tester,
    ) async {
      pantallaChica(tester);
      abridor.resultado = false;
      await _montar(tester, abridor: abridor, monitor: monitor, escalaTexto: 2);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(_noSeAbrio), findsOneWidget);
      expect(find.text('Copiar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una excepción de la plataforma avisa igual y no deja el toque trabado', (
      tester,
    ) async {
      pantallaChica(tester);
      abridor.falla = StateError('plataforma');
      await _montar(tester, abridor: abridor, monitor: monitor);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);
      await tester.pump();

      expect(find.text(_noSeAbrio), findsOneWidget);
      expect(tester.takeException(), isNull);

      abridor.falla = null;
      await _tocarTerminos(tester);

      expect(abridor.abiertas, hasLength(2));
    });

    testWidgets('dos fallas seguidas muestran un solo aviso, no se apilan', (tester) async {
      pantallaChica(tester);
      abridor.resultado = false;
      await _montar(tester, abridor: abridor, monitor: monitor);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);
      await tester.pump();
      await _tocarTerminos(tester);
      await tester.pump();

      expect(find.text(_noSeAbrio), findsOneWidget);
    });

    testWidgets('volver atrás con la apertura en vuelo no rompe, y al reentrar el toque anda', (
      tester,
    ) async {
      pantallaChica(tester);
      abridor
        ..resultado = false
        ..demora = Completer<void>();
      await _montar(tester, abridor: abridor, monitor: monitor);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RegistroPage), findsNothing);

      // La apertura termina (con falla) cuando la pantalla ya no está: no hay aviso ni excepción.
      abridor.demora!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);

      // Reentrar: el toque es de la pantalla nueva y anda.
      abridor
        ..demora = null
        ..resultado = true;
      await _entrarAlRegistro(tester);
      await _tocarTerminos(tester);

      expect(abridor.abiertas, hasLength(2));
    });

    testWidgets('con el texto al 200 % el enlace anda y el aviso se lee entero, sin desborde', (
      tester,
    ) async {
      pantallaChica(tester);
      monitor.tipo = TipoConexion.sinConexion;
      await _montar(tester, abridor: abridor, monitor: monitor, escalaTexto: 2);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);
      await tester.pump();

      expect(find.text(_sinConexion), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el texto al 200 % y conexión abre sin aviso', (tester) async {
      pantallaChica(tester);
      await _montar(tester, abridor: abridor, monitor: monitor, escalaTexto: 2);
      await _entrarAlRegistro(tester);

      await _tocarTerminos(tester);

      expect(abridor.abiertas, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('el registro manda la versión aceptada', () {
    testWidgets('con los datos completos, el alta lleva terminos_version v1', (tester) async {
      pantallaChica(tester);
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montar(tester, abridor: abridor, monitor: monitor, remote: remote);
      await _entrarAlRegistro(tester);

      await tester.enterText(find.byKey(const Key('registro_nombre')), 'Lucía');
      await tester.enterText(find.byKey(const Key('registro_apellido')), 'Silva');
      await tester.enterText(find.byKey(const Key('registro_cedula')), '4812309-2');
      await tester.enterText(find.byKey(const Key('registro_email')), 'lucia.silva@correo.com');
      await tester.enterText(find.byKey(const Key('registro_password')), 'Secreto123');
      await tester.ensureVisible(find.byKey(const Key('registro_terminos')));
      await tester.tap(find.byKey(const Key('registro_terminos')));
      await tester.ensureVisible(find.byKey(const Key('registro_trade_off')));
      await tester.tap(find.byKey(const Key('registro_trade_off')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('registro_continuar')));
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      expect(remote.terminosVersionesRegistradas, ['v1']);
    });

    testWidgets('sin aceptar los términos no se registra: no viaja ninguna versión', (
      tester,
    ) async {
      pantallaChica(tester);
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montar(tester, abridor: abridor, monitor: monitor, remote: remote);
      await _entrarAlRegistro(tester);

      await tester.ensureVisible(find.byKey(const Key('registro_continuar')));
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      expect(remote.terminosVersionesRegistradas, isEmpty);
      expect(remote.llamadasRegistrar, 0);
    });
  });
}
