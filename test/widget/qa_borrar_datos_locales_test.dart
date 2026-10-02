// QA de la vista 19 «Borrar datos locales» (#228, HU-AUTH-010): lo que la suite de la vista no
// cubría — guías de accesibilidad y overflow a 360×640 y 412×915, la frase con entradas límite,
// lo tipeado tras un error y salir a mitad de una acción.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_intentos_borrado.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/intentos_borrado_repository.dart';
import 'package:colportores_mobile/features/auth/domain/services/sincronizador_manual.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/borrado_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/configuracion/presentation/pages/borrar_datos_locales_page.dart';
import 'package:colportores_mobile/features/configuracion/presentation/providers/nombre_cuenta_provider.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:dartz/dartz.dart' show Either, Left, Right, Unit;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

ResumenDatosLocales _res({
  int? pendientes = 0,
  bool drive = true,
  int personas = 12,
  int visitas = 34,
}) => ResumenDatosLocales(
  personas: personas,
  visitas: visitas,
  operacionesSinSincronizar: pendientes,
  hayBackupEnDrive: drive,
);

final class _DatosFake implements DatosLocalesRepository {
  /// Respuestas de `resumen()` en orden; la última se repite.
  final List<Either<Failure, ResumenDatosLocales>> respuestas = [Right(_res())];
  Either<Failure, ResultadoBorradoDatosLocales> respuestaBorrado = const Right(
    ResultadoBorradoDatosLocales.completo,
  );
  Completer<void>? demoraResumen;
  Completer<void>? demoraBorrado;
  int llamadasResumen = 0;
  final List<bool> borrados = [];
  final List<bool> reintentos = [];

  @override
  Future<Either<Failure, ResumenDatosLocales>> resumen() async {
    llamadasResumen++;
    final r = respuestas.length > 1 ? respuestas.removeAt(0) : respuestas.first;
    await demoraResumen?.future;
    return r;
  }

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({
    required bool incluirBackupDrive,
    bool reintento = false,
  }) async {
    borrados.add(incluirBackupDrive);
    reintentos.add(reintento);
    await demoraBorrado?.future;
    return respuestaBorrado;
  }
}

final class _SincronizadorFake implements SincronizadorManual {
  Either<Failure, Unit> respuesta = const Left(FailureSincronizacionNoDisponible());
  Completer<void>? demora;
  int llamadas = 0;

  @override
  Future<Either<Failure, Unit>> sincronizarAhora() async {
    llamadas++;
    await demora?.future;
    return respuesta;
  }
}

final class _IntentosEnMemoria implements IntentosBorradoRepository {
  EstadoIntentosBorrado estado = EstadoIntentosBorrado.limpio;

  @override
  Future<EstadoIntentosBorrado> leer() async => estado;

  @override
  Future<void> guardar(EstadoIntentosBorrado nuevo) async => estado = nuevo;

  @override
  Future<void> limpiar() async => estado = EstadoIntentosBorrado.limpio;
}

final class _MonitorFalso implements MonitorConectividad {
  TipoConexion inicial = TipoConexion.wifi;
  final controlador = StreamController<TipoConexion>.broadcast();

  @override
  Future<TipoConexion> actual() async => inicial;

  @override
  Stream<TipoConexion> get cambios => controlador.stream;
}

late AuthRemoteDataSourceEnMemoria _remote;
late _DatosFake _datos;
late _SincronizadorFake _sync;
late _IntentosEnMemoria _intentos;
late _MonitorFalso _monitor;
late DbLocalRepositoryEnMemoria _db;
late DateTime _ahora;

const _password = 'Secreto123';
const _frase = 'BORRAR-DATOS-LUCIA-SILVA';

Future<ProviderContainer> _montar(
  WidgetTester tester, {
  AuthLocalDataSource? local,
  String? nombre = 'Lucía Silva',
}) async {
  final container = ProviderContainer(
    overrides: <Override>[
      dbLocalRepositoryProvider.overrideWithValue(_db),
      authRemoteDataSourceProvider.overrideWithValue(_remote),
      authLocalDataSourceProvider.overrideWithValue(local ?? AuthLocalDataSourceEnMemoria()),
      datosLocalesRepositoryProvider.overrideWithValue(_datos),
      sincronizadorManualProvider.overrideWithValue(_sync),
      intentosBorradoRepositoryProvider.overrideWithValue(_intentos),
      monitorConectividadProvider.overrideWithValue(_monitor),
      relojBorradoProvider.overrideWithValue(() => _ahora),
      nombreCuentaProvider.overrideWithValue(nombre),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await container
      .read(sesionProvider.notifier)
      .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('inicio_configuracion')));
  await tester.pumpAndSettle();
  return container;
}

void _pantalla(WidgetTester tester, Size tamanio, {double escala = 1.0}) {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (escala != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = escala;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

/// Scrollea hasta [finder] y lo toca (con texto grande el ítem puede no estar construido todavía).
Future<void> _tocar(WidgetTester tester, Finder finder, {bool settle = true}) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pump();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Finder _k(String clave) => find.byKey(Key(clave));

Future<void> _abrirBorrado(WidgetTester tester) => _tocar(tester, _k('configuracion_borrar_datos'));

Future<void> _marcarCasillas(WidgetTester tester) async {
  await _tocar(tester, _k('borrar_datos_checkbox'));
  await _tocar(tester, _k('borrar_datos_checkbox_irreversible'));
}

Future<void> _irAConfirmacion(WidgetTester tester) async {
  await _abrirBorrado(tester);
  await _marcarCasillas(tester);
  await _tocar(tester, _k('borrar_datos_continuar'));
}

Future<void> _escribir(WidgetTester tester, String clave, String texto) async {
  await tester.scrollUntilVisible(_k(clave), 200, scrollable: find.byType(Scrollable).first);
  await tester.enterText(_k(clave), texto);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Vuelve al principio de la lista (arriba está el «‹», que el scroll de los tests deja afuera).
Future<void> _alPrincipio(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
  await tester.pumpAndSettle();
}

/// Frase y contraseña correctas, sin tocar «Sí, borrar datos locales».
Future<void> _completarConfirmacion(WidgetTester tester, {bool conPassword = true}) async {
  await _escribir(tester, 'borrar_datos_frase', _frase);
  if (conPassword) await _escribir(tester, 'borrar_datos_password', _password);
}

Future<void> _confirmar(WidgetTester tester, {bool settle = true}) =>
    _tocar(tester, _k('borrar_datos_confirmar'), settle: settle);

Future<void> _borrarTodo(WidgetTester tester, {bool incluirDrive = false}) async {
  await _irAConfirmacion(tester);
  if (incluirDrive) await _tocar(tester, find.text(TextosBorrado.borrarDrive));
  await _completarConfirmacion(tester);
  await _confirmar(tester);
}

Finder get _login => _k('login_enviar');

bool _seleccionada(WidgetTester tester, String clave) => tester
    .widget<ListTile>(find.descendant(of: _k(clave), matching: find.byType(ListTile)))
    .selected;

bool _habilitado(WidgetTester tester, String clave) {
  final w = tester.widget(_k(clave));
  return switch (w) {
    FilledButton(:final onPressed) => onPressed != null,
    OutlinedButton(:final onPressed) => onPressed != null,
    TextButton(:final onPressed) => onPressed != null,
    _ => throw StateError('no es un botón: ${w.runtimeType}'),
  };
}

// --- QA --------------------------------------------------------------------------------------

const _tamanios = [Size(360, 640), Size(412, 915)];

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Las cuatro guías arriba del scroll y abajo del todo (a 360×640 la pantalla no entra entera).
Future<void> _guiasArribaYAbajo(WidgetTester tester, {bool animando = false}) async {
  // Con un indicador girando (borrando) `pumpAndSettle` no termina nunca: un cuadro alcanza.
  Future<void> asentar() => animando ? tester.pump() : tester.pumpAndSettle();
  await _guias(tester);
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
  await asentar();
  await _guias(tester);
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
  await asentar();
}

/// Llega a cada estado de la vista y llama a [alla] con su nombre (para accesibilidad y overflow).
Future<void> _recorrerEstados(
  WidgetTester tester,
  Future<void> Function(String estado) alla,
) async {
  // Resumen con las dos casillas.
  await _montar(tester);
  await _abrirBorrado(tester);
  await _marcarCasillas(tester);
  await alla('resumen');

  // Confirmación con errores (contraseña incorrecta y frase cambiada).
  await _tocar(tester, _k('borrar_datos_continuar'));
  await _escribir(tester, 'borrar_datos_frase', _frase);
  await _escribir(tester, 'borrar_datos_password', 'mala');
  await _confirmar(tester);
  await _escribir(tester, 'borrar_datos_frase', 'BORRAR-DATOS-OTRA');
  await alla('confirmacion con errores');
}

void main() {
  setUp(() {
    _remote = AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'});
    _datos = _DatosFake();
    _sync = _SincronizadorFake();
    _intentos = _IntentosEnMemoria();
    _monitor = _MonitorFalso();
    _db = dbLocalYaPreparada();
    _ahora = DateTime.utc(2026, 9, 30, 12);
  });

  for (final t in _tamanios) {
    final tam = '${t.width.toInt()}x${t.height.toInt()}';

    group('Accesibilidad a $tam', () {
      testWidgets('resumen y confirmación con errores cumplen las guías', (tester) async {
        final handle = tester.ensureSemantics();
        _pantalla(tester, t);
        await _recorrerEstados(tester, (_) => _guiasArribaYAbajo(tester));
        handle.dispose();
      });

      testWidgets('bloqueo por pendientes cumple las guías', (tester) async {
        final handle = tester.ensureSemantics();
        _pantalla(tester, t);
        _datos.respuestas[0] = Right(_res(pendientes: 3));
        await _montar(tester);
        await _abrirBorrado(tester);
        await _guiasArribaYAbajo(tester);
        handle.dispose();
      });

      testWidgets('«No se pudieron contar» cumple las guías', (tester) async {
        final handle = tester.ensureSemantics();
        _pantalla(tester, t);
        _datos.respuestas[0] = const Left(FailureDatosLocalesIlegibles());
        await _montar(tester);
        await _abrirBorrado(tester);
        await _guiasArribaYAbajo(tester);
        handle.dispose();
      });

      testWidgets('confirmación sin conexión cumple las guías', (tester) async {
        final handle = tester.ensureSemantics();
        _pantalla(tester, t);
        _monitor.inicial = TipoConexion.sinConexion;
        await _montar(tester);
        await _irAConfirmacion(tester);
        await _completarConfirmacion(tester);
        await _guiasArribaYAbajo(tester);
        handle.dispose();
      });

      testWidgets('«Borrando», falla de Drive y error al borrar cumplen las guías', (tester) async {
        final handle = tester.ensureSemantics();
        _pantalla(tester, t);
        _datos.demoraBorrado = Completer<void>();
        await _montar(tester);
        await _irAConfirmacion(tester);
        await _completarConfirmacion(tester);
        await _confirmar(tester, settle: false);
        expect(find.text('Borrando datos'), findsOneWidget);
        await _guiasArribaYAbajo(tester, animando: true);

        _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.backupDriveNoBorrado);
        _datos.demoraBorrado!.complete();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('borrar_datos_falla_drive')), findsOneWidget);
        await _guiasArribaYAbajo(tester);
        handle.dispose();
      });

      testWidgets('error al borrar cumple las guías', (tester) async {
        final handle = tester.ensureSemantics();
        _pantalla(tester, t);
        _datos.respuestaBorrado = const Left(FailureInesperado());
        await _montar(tester);
        await _borrarTodo(tester);
        expect(find.byKey(const Key('borrar_datos_error')), findsOneWidget);
        await _guiasArribaYAbajo(tester);
        handle.dispose();
      });
    });

    group('Texto grande (2.0) a $tam', () {
      testWidgets('resumen y confirmación con errores no desbordan', (tester) async {
        _pantalla(tester, t, escala: 2.0);
        await _recorrerEstados(tester, (_) async {
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _alPrincipio(tester);
          expect(tester.takeException(), isNull);
        });
      });

      testWidgets('con Drive, sin conexión y el nombre largo, la frase se ve entera', (
        tester,
      ) async {
        _pantalla(tester, t, escala: 2.0);
        _monitor.inicial = TipoConexion.sinConexion;
        await _montar(tester, nombre: 'María de los Ángeles Pérez Gómez');
        await _irAConfirmacion(tester);

        expect(
          find.text('Escribí BORRAR-DATOS-MARIA-DE-LOS-ANGELES-PEREZ-GOMEZ'),
          findsOneWidget,
          reason: 'la frase del nombre largo, tal cual hay que escribirla',
        );
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('«Borrando», falla de Drive y error no desbordan', (tester) async {
        _pantalla(tester, t, escala: 2.0);
        _datos.demoraBorrado = Completer<void>();
        await _montar(tester);
        await _irAConfirmacion(tester);
        await _completarConfirmacion(tester);
        await _confirmar(tester, settle: false);
        expect(tester.takeException(), isNull);

        _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.backupDriveNoBorrado);
        _datos.demoraBorrado!.complete();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('borrar_datos_falla_drive')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('La frase: entradas límite', () {
    Future<void> frase(WidgetTester tester, String texto) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester);
      await _irAConfirmacion(tester);
      await _escribir(tester, 'borrar_datos_password', _password);
      await _escribir(tester, 'borrar_datos_frase', texto);
    }

    testWidgets('solo espacios: no es la frase, no gasta nada y el botón sigue apagado', (
      tester,
    ) async {
      await frase(tester, '       ');
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isFalse);
      expect(find.text('✓ Coincide'), findsNothing);
      expect(_datos.borrados, isEmpty);
    });

    testWidgets('emoji y caracteres especiales: avisa que no coincide y no habilita', (
      tester,
    ) async {
      await frase(tester, 'BORRAR-DATOS-LUCÍA 😀 <script>');
      expect(find.text(TextosBorrado.fraseNoCoincide), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isFalse);
    });

    testWidgets('con tilde: LUCÍA no es LUCIA (la frase se escribe sin tildes)', (tester) async {
      await frase(tester, 'BORRAR-DATOS-LUCÍA-SILVA');
      expect(find.text(TextosBorrado.fraseNoCoincide), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isFalse);
    });

    testWidgets('texto pegado de 500 caracteres: se corta al largo permitido y no habilita', (
      tester,
    ) async {
      await frase(tester, 'A' * 500);
      final campo = tester.widget<TextField>(_k('borrar_datos_frase'));
      expect(campo.controller!.text.length, lessThan(100), reason: 'tiene tope de largo');
      expect(find.text(TextosBorrado.fraseNoCoincide), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isFalse);
    });

    testWidgets('en minúsculas y con espacios alrededor sí coincide (la HU: no distingue '
        'mayúsculas)', (tester) async {
      await frase(tester, '  borrar-datos-lucia-silva  ');
      expect(find.text('✓ Coincide'), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isTrue);
    });

    testWidgets('nombre con tilde y eñe: la frase sale normalizada y se puede escribir', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, nombre: 'José Peña');
      await _irAConfirmacion(tester);
      expect(find.text('Escribí BORRAR-DATOS-JOSE-PENA'), findsOneWidget);
      await _escribir(tester, 'borrar_datos_frase', 'borrar-datos-jose-pena');
      expect(find.text('✓ Coincide'), findsOneWidget);
    });

    testWidgets('nombre sin ninguna letra ni número: no hay frase, dice qué hacer y no ofrece '
        'borrar', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, nombre: '— · —');
      await _irAConfirmacion(tester);
      expect(find.text(TextosBorrado.sinFrase), findsOneWidget);
      expect(_k('borrar_datos_confirmar'), findsNothing);
      expect(_k('borrar_datos_cancelar'), findsOneWidget, reason: 'queda la salida');
    });
  });

  group('Después de un error no se pierde lo tipeado', () {
    testWidgets('contraseña incorrecta: la frase y la opción de Drive quedan; la contraseña se '
        'limpia y un segundo intento correcto borra', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester);
      await _irAConfirmacion(tester);
      await _tocar(tester, find.text(TextosBorrado.borrarDrive));
      await _escribir(tester, 'borrar_datos_frase', _frase);
      await _escribir(tester, 'borrar_datos_password', 'mala');
      await _confirmar(tester);

      expect(find.text('Contraseña incorrecta. Te quedan 4 intentos.'), findsOneWidget);
      expect(tester.widget<TextField>(_k('borrar_datos_frase')).controller!.text, _frase);
      expect(_seleccionada(tester, 'borrar_datos_incluir_drive'), isTrue);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isTrue);

      await _escribir(tester, 'borrar_datos_password', _password);
      await _confirmar(tester);
      expect(_datos.borrados, [true]);
      expect(_login, findsOneWidget);
    });

    testWidgets('contraseña pegada de 4000 caracteres con emoji: dice incorrecta y no se traba', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester);
      await _irAConfirmacion(tester);
      await _escribir(tester, 'borrar_datos_frase', _frase);
      await _escribir(tester, 'borrar_datos_password', '😀ñ${'x' * 4000}');
      await _confirmar(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Contraseña incorrecta. Te quedan 4 intentos.'), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isTrue);
      expect(_datos.borrados, isEmpty);
    });
  });

  group('Salir y reentrar a mitad de una acción', () {
    testWidgets('salir mientras cuenta: no queda nada colgado y al volver cuenta de nuevo', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      _datos.demoraResumen = Completer<void>();
      await _montar(tester);
      await _tocar(tester, _k('configuracion_borrar_datos'), settle: false);
      expect(find.byKey(const Key('borrar_datos_cargando')), findsOneWidget);
      expect(find.text('Revisando los datos de este teléfono…'), findsOneWidget);

      await tester.tap(_k('borrar_datos_atras'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BorrarDatosLocalesPage), findsNothing);

      _datos.demoraResumen!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      _datos.demoraResumen = null;
      await _abrirBorrado(tester);
      expect(find.byKey(const Key('borrar_datos_resumen')), findsOneWidget);
    });

    testWidgets('salir mientras sincroniza: al volver, «Sincronizar ahora» vuelve a estar '
        'disponible', (tester) async {
      _pantalla(tester, const Size(390, 844));
      _datos.respuestas[0] = Right(_res(pendientes: 2));
      _sync.demora = Completer<void>();
      await _montar(tester);
      await _abrirBorrado(tester);
      await _tocar(tester, _k('borrar_datos_sincronizar'), settle: false);
      expect(find.text('Sincronizando…'), findsOneWidget);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pump();
      await tester.tap(_k('borrar_datos_atras'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      _sync.demora!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      _sync.demora = null;
      await _abrirBorrado(tester);
      expect(find.text('Sincronizar ahora'), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_sincronizar'), isTrue);
    });
  });

  group('Visual: casillas', () {
    // skip: QA #228 — `checkboxTheme.fillColor` no distingue el estado: la casilla sin marcar se
    // ve rellena de azul (canvas A04: caja blanca con borde gris, y azul solo la marcada).
    testWidgets('la casilla sin marcar no se ve rellena como la marcada', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester);
      await _abrirBorrado(tester);

      final contexto = tester.element(_k('borrar_datos_checkbox_irreversible'));
      final tema = Theme.of(contexto);
      final relleno = tema.checkboxTheme.fillColor!;
      expect(
        relleno.resolve(<WidgetState>{}),
        isNot(relleno.resolve(<WidgetState>{WidgetState.selected})),
        reason: 'sin marcar y marcada no pueden tener el mismo relleno',
      );
    }, skip: true);
  });
}
