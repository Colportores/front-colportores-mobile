// Vista 19 «Borrar datos locales» (HU-AUTH-010, #228): sincronización previa, dos casillas,
// confirmación final con frase y contraseña, borrado con pasos, y cada falla. Un test por
// escenario de la HU (con su texto literal) y por artboard del canvas.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
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
import 'package:colportores_mobile/features/configuracion/presentation/pages/configuracion_page.dart';
import 'package:colportores_mobile/features/configuracion/presentation/providers/nombre_cuenta_provider.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:dartz/dartz.dart' show Either, Left, Right, Unit, unit;
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

/// Almacén de sesión que puede fallar o quedarse esperando al borrar la sesión.
final class _LocalQueNoBorra implements AuthLocalDataSource {
  SesionModel? _sesion;
  bool fallar = false;
  Completer<void>? demora;

  @override
  Future<SesionModel?> leerSesion() async => _sesion;

  @override
  Future<void> guardarSesion(SesionModel sesion) async => _sesion = sesion;

  @override
  Future<void> borrarSesion() async {
    await demora?.future;
    if (fallar) throw Exception('keystore');
    _sesion = null;
  }
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

/// Desmonta la app: la espera de intentos usa un `Timer` que el árbol cancela al irse.
Future<void> _desmontar(WidgetTester tester) => tester.pumpWidget(const SizedBox());

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

  group('A01 Resumen (casillas marcadas)', () {
    testWidgets('muestra lo que se borra, la explicación de la HU y los avisos', (tester) async {
      await _montar(tester);
      await _abrirBorrado(tester);

      expect(find.text('PRIVACIDAD Y DATOS'), findsOneWidget);
      expect(find.text('Borrar datos locales'), findsWidgets);
      expect(find.text(TextosBorrado.explicacion), findsOneWidget);
      expect(find.text('Esto se borra de este teléfono y no se puede deshacer:'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('34'), findsOneWidget);
      expect(find.text('Sí, vas a elegir si se borra'), findsOneWidget);
      expect(find.text(TextosBorrado.datosDelSistema), findsOneWidget);
      expect(
        find.text(TextosBorrado.limiteBorrado),
        findsOneWidget,
        reason: 'HU-AUTH-010, caso borde: documenta el límite del overwrite en memoria flash',
      );
      expect(find.byKey(const Key('borrar_datos_aviso_pendientes')), findsNothing);
    });

    testWidgets('con las dos casillas marcadas y sin pendientes, «Continuar» se habilita', (
      tester,
    ) async {
      await _montar(tester);
      await _abrirBorrado(tester);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isFalse);

      await _marcarCasillas(tester);

      expect(_habilitado(tester, 'borrar_datos_continuar'), isTrue);
      expect(find.text(TextosBorrado.faltanCasillas), findsNothing);
    });

    testWidgets('las dos casillas dicen lo que dice la HU', (tester) async {
      await _montar(tester);
      await _abrirBorrado(tester);

      expect(
        find.text(
          'Entiendo que solo se borran los datos de este teléfono. Mi coordinador conserva mis '
          'ventas.',
        ),
        findsOneWidget,
      );
      expect(find.text('Entiendo que no se puede deshacer.'), findsOneWidget);
    });

    testWidgets('vacío: sin personas ni visitas muestra ceros y deja continuar', (tester) async {
      _datos.respuestas[0] = Right(_res(personas: 0, visitas: 0, drive: false));
      await _montar(tester);
      await _abrirBorrado(tester);

      expect(tester.widget<Text>(_k('borrar_datos_personas')).data, '0');
      expect(tester.widget<Text>(_k('borrar_datos_visitas')).data, '0');
      expect(tester.widget<Text>(_k('borrar_datos_backup')).data, 'No hay');
      await _marcarCasillas(tester);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isTrue);
    });

    testWidgets('listas largas: con miles de personas y visitas entra sin overflow', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 740), escala: 2.0);
      _datos.respuestas[0] = Right(_res(personas: 123456, visitas: 9876543));
      await _montar(tester);
      await _abrirBorrado(tester);

      expect(find.text('123456'), findsOneWidget);
      expect(find.text('9876543'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('A02 Bloqueado por operaciones sin sincronizar', () {
    setUp(() => _datos.respuestas[0] = Right(_res(pendientes: 3)));

    testWidgets('avisa cuántas, ofrece sincronizar y deja «Continuar» deshabilitado', (
      tester,
    ) async {
      await _montar(tester);
      await _abrirBorrado(tester);

      expect(
        find.text(
          'Tenés 3 operaciones sin sincronizar. Sincronizalas antes de borrar los datos de este '
          'teléfono.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<Text>(_k('borrar_datos_pendientes')).data, '3');
      expect(find.text('Sincronizar ahora'), findsOneWidget);
      expect(
        find.text('“Continuar” se habilita cuando no quedan operaciones pendientes.'),
        findsOneWidget,
      );

      // Ni siquiera con las dos casillas marcadas.
      await _marcarCasillas(tester);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isFalse);
      expect(find.text(TextosBorrado.faltanCasillas), findsNothing);
    });

    testWidgets('con una sola operación lo dice en singular', (tester) async {
      _datos.respuestas[0] = Right(_res(pendientes: 1));
      await _montar(tester);
      await _abrirBorrado(tester);

      expect(
        find.text(
          'Tenés 1 operación sin sincronizar. Sincronizala antes de borrar los datos de este '
          'teléfono.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('«Sincronizar ahora» sube todo: vuelve a contar y se habilita «Continuar»', (
      tester,
    ) async {
      _datos.respuestas.add(Right(_res()));
      _sync.respuesta = const Right(unit);
      await _montar(tester);
      await _abrirBorrado(tester);
      await _marcarCasillas(tester);

      await _tocar(tester, _k('borrar_datos_sincronizar'));

      expect(_sync.llamadas, 1);
      expect(find.byKey(const Key('borrar_datos_aviso_pendientes')), findsNothing);
      expect(tester.widget<Text>(_k('borrar_datos_pendientes')).data, '0');
      expect(_habilitado(tester, 'borrar_datos_continuar'), isTrue);
    });

    testWidgets('si sincroniza y quedan operaciones, manda a corregir las que no suben', (
      tester,
    ) async {
      _datos.respuestas.add(Right(_res(pendientes: 2)));
      _sync.respuesta = const Right(unit);
      await _montar(tester);
      await _abrirBorrado(tester);

      await _tocar(tester, _k('borrar_datos_sincronizar'));

      expect(find.text(TextosBorrado.quedanSinSubir), findsOneWidget);
      expect(find.text(TextosBorrado.pendientes(2)), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_sincronizar'), isTrue);
    });

    testWidgets('falla a mitad: dice qué pasó y el botón vuelve a habilitarse', (tester) async {
      await _montar(tester);
      await _abrirBorrado(tester);

      await _tocar(tester, _k('borrar_datos_sincronizar'));

      expect(find.text(const FailureSincronizacionNoDisponible().mensaje), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_sincronizar'), isTrue);
      expect(find.byKey(const Key('borrar_datos_sincronizando')), findsNothing);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isFalse);

      // Reintentar anda: se pide de nuevo (y el aviso viejo se reemplaza).
      _sync.respuesta = const Right(unit);
      _datos.respuestas.add(Right(_res()));
      await _tocar(tester, _k('borrar_datos_sincronizar'));
      expect(_sync.llamadas, 2);
      expect(find.text(const FailureSincronizacionNoDisponible().mensaje), findsNothing);
    });

    testWidgets('doble toque: mientras sincroniza no se pide otra vez', (tester) async {
      _sync.demora = Completer<void>();
      _sync.respuesta = const Right(unit);
      _datos.respuestas.add(Right(_res()));
      await _montar(tester);
      await _abrirBorrado(tester);

      await _tocar(tester, _k('borrar_datos_sincronizar'), settle: false);
      expect(find.text('Sincronizando…'), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_sincronizar'), isFalse);
      await tester.tap(_k('borrar_datos_sincronizar'), warnIfMissed: false);
      await tester.pump();

      _sync.demora!.complete();
      await tester.pumpAndSettle();
      expect(_sync.llamadas, 1);
    });

    testWidgets('si al volver a contar falla, no deja a la vista un conteo viejo', (tester) async {
      _sync.respuesta = const Right(unit);
      _datos.respuestas.add(const Left(FailureDatosLocalesIlegibles()));
      await _montar(tester);
      await _abrirBorrado(tester);

      await _tocar(tester, _k('borrar_datos_sincronizar'));

      expect(find.byKey(const Key('borrar_datos_error_resumen')), findsOneWidget);
      expect(find.byKey(const Key('borrar_datos_continuar')), findsNothing);
    });
  });

  group('A03 No se pudieron contar', () {
    setUp(() => _datos.respuestas[0] = Right(_res(pendientes: null)));

    testWidgets('también bloquea (decisión de Cristian, 29/09) y dice qué hacer', (tester) async {
      await _montar(tester);
      await _abrirBorrado(tester);

      expect(find.text('— No se pudieron contar'), findsOneWidget);
      expect(tester.widget<Text>(_k('borrar_datos_personas')).data, '—');
      expect(tester.widget<Text>(_k('borrar_datos_visitas')).data, '—');
      expect(find.textContaining(TextosBorrado.reintentarConteo), findsOneWidget);
      expect(find.textContaining('Podés seguir igual'), findsNothing);
      await _marcarCasillas(tester);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isFalse);
    });

    testWidgets('«Reintentar» vuelve a contar y, si ya se puede, destraba', (tester) async {
      _datos.respuestas.add(Right(_res()));
      await _montar(tester);
      await _abrirBorrado(tester);
      await _marcarCasillas(tester);

      await _tocar(tester, _k('borrar_datos_reintentar_conteo'));

      expect(find.byKey(const Key('borrar_datos_sin_conteo')), findsNothing);
      expect(tester.widget<Text>(_k('borrar_datos_pendientes')).data, '0');
      expect(_habilitado(tester, 'borrar_datos_continuar'), isTrue);
    });

    testWidgets('si reintentar sigue sin poder contar, sigue bloqueado y se puede reintentar', (
      tester,
    ) async {
      await _montar(tester);
      await _abrirBorrado(tester);

      await _tocar(tester, _k('borrar_datos_reintentar_conteo'));

      expect(find.byKey(const Key('borrar_datos_sin_conteo')), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_reintentar_conteo'), isTrue);
      expect(_datos.llamadasResumen, 2);
    });
  });

  group('A04 Falta una casilla', () {
    testWidgets('con una sola marcada avisa «Marcá las dos casillas para continuar.»', (
      tester,
    ) async {
      await _montar(tester);
      await _abrirBorrado(tester);

      await _tocar(tester, _k('borrar_datos_checkbox'));

      expect(find.text('Marcá las dos casillas para continuar.'), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isFalse);

      await _tocar(tester, _k('borrar_datos_checkbox_irreversible'));
      expect(find.text('Marcá las dos casillas para continuar.'), findsNothing);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isTrue);
    });

    testWidgets('desmarcar una casilla vuelve a bloquear', (tester) async {
      await _montar(tester);
      await _abrirBorrado(tester);
      await _marcarCasillas(tester);

      await _tocar(tester, _k('borrar_datos_checkbox_irreversible'));

      expect(find.text('Marcá las dos casillas para continuar.'), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isFalse);
    });
  });

  group('A05 Confirmación final (frase y contraseña)', () {
    testWidgets('pantalla completa, sin barra inferior, con la frase del nombre', (tester) async {
      await _montar(tester);
      await _irAConfirmacion(tester);

      expect(find.text('PRIVACIDAD Y DATOS · CONFIRMACIÓN FINAL'), findsOneWidget);
      expect(find.text('Confirmá el borrado'), findsOneWidget);
      expect(find.text('Se cierra tu sesión y no se puede deshacer.'), findsOneWidget);
      expect(find.text('TU BACKUP EN DRIVE'), findsOneWidget);
      expect(find.text('Escribí $_frase'), findsOneWidget);
      expect(find.text('TU CONTRASEÑA'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('«✓ Coincide» aparece al escribir la frase, sin distinguir mayúsculas', (
      tester,
    ) async {
      await _montar(tester);
      await _irAConfirmacion(tester);
      expect(find.text('✓ Coincide'), findsNothing);

      await _escribir(tester, 'borrar_datos_frase', 'borrar-datos-lucia-silva');

      expect(find.text('✓ Coincide'), findsOneWidget);
    });

    testWidgets('no se puede pegar la frase: sin menú de selección ni de portapapeles', (
      tester,
    ) async {
      await _montar(tester);
      await _irAConfirmacion(tester);

      final campo = tester.widget<TextField>(_k('borrar_datos_frase'));
      expect(campo.enableInteractiveSelection, isFalse);
      expect(campo.contextMenuBuilder, isNotNull);
      expect(
        campo.contextMenuBuilder!(
          tester.element(_k('borrar_datos_frase')),
          _estadoDelCampo(tester),
        ),
        isA<SizedBox>(),
      );
      expect(campo.autocorrect, isFalse);
    });

    testWidgets('«Mostrar contraseña» muestra y oculta lo escrito', (tester) async {
      await _montar(tester);
      await _irAConfirmacion(tester);
      expect(tester.widget<TextField>(_k('borrar_datos_password')).obscureText, isTrue);

      await _tocar(tester, _k('borrar_datos_mostrar_password'));
      expect(tester.widget<TextField>(_k('borrar_datos_password')).obscureText, isFalse);

      await _tocar(tester, _k('borrar_datos_mostrar_password'));
      expect(tester.widget<TextField>(_k('borrar_datos_password')).obscureText, isTrue);
    });

    testWidgets('sin backup en Drive no pregunta por Drive', (tester) async {
      _datos.respuestas[0] = Right(_res(drive: false));
      await _montar(tester);
      await _irAConfirmacion(tester);

      expect(find.text('TU BACKUP EN DRIVE'), findsNothing);
      expect(find.text(TextosBorrado.conservarDrive), findsNothing);
      expect(find.text(TextosBorrado.borrarDrive), findsNothing);
    });

    testWidgets('Google sin backup (sin envoltorio): se pide solo la frase, sin contraseña', (
      tester,
    ) async {
      await _montar(tester);
      // Después del login: preparar la DB con contraseña arma el envoltorio.
      _db.envoltorio = null;
      await _irAConfirmacion(tester);

      expect(find.byKey(const Key('borrar_datos_password')), findsNothing);
      expect(find.text('TU CONTRASEÑA'), findsNothing);
      expect(find.text(TextosBorrado.sinPassword), findsOneWidget);

      await _completarConfirmacion(tester, conPassword: false);
      await _confirmar(tester);

      expect(_datos.borrados, [false]);
      expect(_login, findsOneWidget);
    });

    testWidgets('sin nombre de cuenta no se puede armar la frase: avisa y no ofrece borrar', (
      tester,
    ) async {
      await _montar(tester, nombre: null);
      await _irAConfirmacion(tester);

      expect(find.text(TextosBorrado.sinNombre), findsOneWidget);
      expect(find.byKey(const Key('borrar_datos_confirmar')), findsNothing);
      expect(_datos.borrados, isEmpty);
    });
  });

  group('A05b Frase o contraseña incorrectas', () {
    testWidgets('frase distinta: «El texto no coincide. Copialo tal cual.» y no borra', (
      tester,
    ) async {
      await _montar(tester);
      await _irAConfirmacion(tester);

      await _escribir(tester, 'borrar_datos_frase', 'BORRAR-DATOS-LUCIA');
      await _escribir(tester, 'borrar_datos_password', _password);
      await _confirmar(tester);

      expect(find.text('El texto no coincide. Copialo tal cual.'), findsOneWidget);
      expect(_datos.borrados, isEmpty);
      expect(_db.llamadas, isNot(contains('desenvolver')), reason: 'no gasta un intento');
      expect(_intentos.estado.fallidos, 0);

      // Al corregirla, el error se va.
      await _escribir(tester, 'borrar_datos_frase', _frase);
      expect(find.text('El texto no coincide. Copialo tal cual.'), findsNothing);
    });

    testWidgets('contraseña incorrecta: «Contraseña incorrecta. Te quedan 4 intentos.»', (
      tester,
    ) async {
      await _montar(tester);
      await _irAConfirmacion(tester);

      await _escribir(tester, 'borrar_datos_frase', _frase);
      await _escribir(tester, 'borrar_datos_password', 'otra');
      await _confirmar(tester);

      expect(find.text('Contraseña incorrecta. Te quedan 4 intentos.'), findsOneWidget);
      expect(_datos.borrados, isEmpty);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isTrue, reason: 'se puede reintentar');
      expect(find.byKey(const Key('borrar_datos_verificando')), findsNothing);
    });

    testWidgets('contraseña vacía: pide que la ingrese, sin gastar un intento', (tester) async {
      await _montar(tester);
      await _irAConfirmacion(tester);

      await _escribir(tester, 'borrar_datos_frase', _frase);
      await _confirmar(tester);

      expect(find.text('Ingresá tu contraseña'), findsOneWidget);
      expect(_intentos.estado.fallidos, 0);
    });

    testWidgets('cinco intentos fallidos: espera de 5 minutos y el botón queda deshabilitado', (
      tester,
    ) async {
      await _montar(tester);
      await _irAConfirmacion(tester);
      await _escribir(tester, 'borrar_datos_frase', _frase);

      for (var i = 4; i >= 1; i--) {
        await _escribir(tester, 'borrar_datos_password', 'otra');
        await _confirmar(tester);
        expect(
          find.text(
            i == 1
                ? 'Contraseña incorrecta. Te queda 1 intento.'
                : 'Contraseña incorrecta. Te quedan $i intentos.',
          ),
          findsOneWidget,
        );
      }
      await _escribir(tester, 'borrar_datos_password', 'otra');
      await _confirmar(tester);

      expect(find.text('Demasiados intentos. Probá nuevamente en 5 minutos.'), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isFalse);
      expect(tester.widget<TextField>(_k('borrar_datos_password')).enabled, isFalse);
      expect(_intentos.estado.bloqueadoHasta, _ahora.add(const Duration(minutes: 5)));
      expect(_datos.borrados, isEmpty);

      await _desmontar(tester);
    });

    testWidgets('al terminar la espera vuelve a habilitarse y se puede borrar', (tester) async {
      _intentos.estado = EstadoIntentosBorrado(
        bloqueadoHasta: _ahora.add(const Duration(minutes: 5)),
      );
      await _montar(tester);
      await _irAConfirmacion(tester);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isFalse);

      _ahora = _ahora.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();

      expect(find.textContaining('Demasiados intentos'), findsNothing);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isTrue);
      await _completarConfirmacion(tester);
      await _confirmar(tester);
      expect(_datos.borrados, [false]);
    });

    testWidgets(
      'cerrar la app no reinicia la espera: al volver a entrar sigue y dice cuánto falta',
      (tester) async {
        _intentos.estado = EstadoIntentosBorrado(
          bloqueadoHasta: _ahora.add(const Duration(minutes: 5)),
        );
        _ahora = _ahora.add(const Duration(minutes: 2));
        await _montar(tester);
        await _irAConfirmacion(tester);

        expect(find.text('Demasiados intentos. Probá nuevamente en 3 minutos.'), findsOneWidget);
        expect(_habilitado(tester, 'borrar_datos_confirmar'), isFalse);

        await _desmontar(tester);
      },
    );

    testWidgets('una contraseña buena limpia los intentos anteriores', (tester) async {
      _intentos.estado = EstadoIntentosBorrado(fallidos: 3);
      await _montar(tester);

      await _borrarTodo(tester);

      expect(_intentos.estado, EstadoIntentosBorrado.limpio);
      expect(_datos.borrados, [false]);
    });

    testWidgets('falla del almacén al validar: lo dice, no gasta intentos y se puede reintentar', (
      tester,
    ) async {
      await _montar(tester);
      await _irAConfirmacion(tester);
      _db.fallas['desenvolver'] = const FailureAlmacenSeguro();

      await _completarConfirmacion(tester);
      await _confirmar(tester);

      expect(find.byKey(const Key('borrar_datos_error_confirmacion')), findsOneWidget);
      expect(_intentos.estado.fallidos, 0);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isTrue);
      expect(find.byKey(const Key('borrar_datos_verificando')), findsNothing);

      _db.fallas.remove('desenvolver');
      await _confirmar(tester);
      expect(_datos.borrados, [false]);
    });

    testWidgets('los avisos que aparecen tras una acción se anuncian (liveRegion): error general, '
        'sin conexión y error de requisitos', (tester) async {
      Finder anunciado(String clave) => find.descendant(
        of: _k(clave),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
      );
      _monitor.inicial = TipoConexion.sinConexion;
      await _montar(tester);
      await _irAConfirmacion(tester);
      expect(anunciado('borrar_datos_sin_conexion'), findsOneWidget);

      _db.fallas['desenvolver'] = const FailureAlmacenSeguro();
      await _completarConfirmacion(tester);
      await _confirmar(tester);

      expect(anunciado('borrar_datos_error_confirmacion'), findsOneWidget);
    });

    testWidgets('el aviso de requisitos ilegibles también se anuncia', (tester) async {
      _intentos.estado = const EstadoIntentosBorrado.ilegible();
      await _montar(tester);
      await _irAConfirmacion(tester);

      expect(
        find.descendant(
          of: _k('borrar_datos_error_requisitos'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('el contador de intentos ilegible: falla cerrado, lo dice y deja reintentar', (
      tester,
    ) async {
      _intentos.estado = const EstadoIntentosBorrado.ilegible();
      await _montar(tester);
      await _irAConfirmacion(tester);

      expect(find.byKey(const Key('borrar_datos_error_requisitos')), findsOneWidget);
      expect(find.text(const FailureIntentosBorradoIlegibles().mensaje), findsOneWidget);
      expect(find.byKey(const Key('borrar_datos_confirmar')), findsNothing);
      expect(_datos.borrados, isEmpty);

      _intentos.estado = EstadoIntentosBorrado.limpio;
      await _tocar(tester, _k('borrar_datos_reintentar_requisitos'));

      expect(find.byKey(const Key('borrar_datos_error_requisitos')), findsNothing);
      expect(find.byKey(const Key('borrar_datos_confirmar')), findsOneWidget);
    });

    testWidgets('doble toque: mientras valida la contraseña no se entra de nuevo', (tester) async {
      await _montar(tester);
      await _irAConfirmacion(tester);
      await _completarConfirmacion(tester);
      _db.argon2idPendiente = Completer<void>();

      await _confirmar(tester, settle: false);
      expect(find.byKey(const Key('borrar_datos_verificando')), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_confirmar'), isFalse);
      expect(tester.widget<TextField>(_k('borrar_datos_password')).enabled, isFalse);
      await tester.tap(_k('borrar_datos_confirmar'), warnIfMissed: false);
      await tester.pump();

      _db.argon2idPendiente!.complete();
      await tester.pumpAndSettle();
      expect(_db.llamadas.where((l) => l == 'desenvolver'), hasLength(1));
      expect(_datos.borrados, [false], reason: 'un solo borrado');
    });

    testWidgets('se sale de la confirmación mientras valida: no borra nada', (tester) async {
      await _montar(tester);
      await _irAConfirmacion(tester);
      await _completarConfirmacion(tester);
      _db.argon2idPendiente = Completer<void>();
      await _confirmar(tester, settle: false);

      await tester.binding.handlePopRoute();
      await tester.pump();
      _db.argon2idPendiente!.complete();
      await tester.pumpAndSettle();

      expect(_datos.borrados, isEmpty);
      expect(find.byKey(const Key('borrar_datos_resumen')), findsOneWidget);
    });
  });

  group('Escenarios de la HU (con la vista 19)', () {
    testWidgets('Escenario: Borrado exitoso (sin tocar backup en Drive)', (tester) async {
      final container = await _montar(tester);
      await _irAConfirmacion(tester);

      await _tocar(tester, find.text('No, conservar mi backup en Drive'));
      await _completarConfirmacion(tester);
      await _tocar(tester, find.text('Sí, borrar datos locales'));

      expect(_datos.borrados, [false]);
      expect(_remote.llamadasCerrarSesion, 1, reason: 'revoca el JWT en Supabase');
      expect(container.read(sesionProvider).value, isNull);
      expect(_login, findsOneWidget, reason: 'la UI navega al login');
      expect(find.byType(BorrarDatosLocalesPage), findsNothing);
    });

    testWidgets('Escenario: Borrado exitoso (incluyendo backup en Drive)', (tester) async {
      await _montar(tester);

      await _borrarTodo(tester, incluirDrive: true);

      expect(_datos.borrados, [true]);
      expect(_login, findsOneWidget);
    });

    testWidgets('Escenario: Edge -usuario cancela en la confirmación final', (tester) async {
      final container = await _montar(tester);
      await _irAConfirmacion(tester);
      await _completarConfirmacion(tester);

      await _tocar(tester, _k('borrar_datos_cancelar'));

      expect(_datos.borrados, isEmpty, reason: 'no se borra absolutamente nada');
      expect(container.read(sesionProvider).value, isNotNull);
      expect(find.byType(ConfiguracionPage), findsOneWidget, reason: 'vuelvo a Configuración');
      expect(find.byType(BorrarDatosLocalesPage), findsNothing);
    });

    testWidgets('Escenario: Edge -sin sesión válida (caso raro)', (tester) async {
      final container = await _montar(tester);
      _remote.simularSinConexion = true; // la revocación no puede llegar al servidor

      await _borrarTodo(tester);

      expect(_datos.borrados, [false], reason: 'el borrado local procede igual');
      expect(container.read(sesionProvider).value, isNull);
      expect(_login, findsOneWidget);
    });
  });

  group('A06 Borrando', () {
    testWidgets('muestra los pasos y «No cierres la app.»; no se puede salir', (tester) async {
      final handle = tester.ensureSemantics();
      _datos.demoraBorrado = Completer<void>();
      await _montar(tester);
      await _irAConfirmacion(tester);
      await _completarConfirmacion(tester);

      await _confirmar(tester, settle: false);

      expect(find.text('Borrando datos'), findsOneWidget);
      expect(find.bySemanticsLabel('Pisando el archivo con ceros, en curso'), findsOneWidget);
      expect(find.bySemanticsLabel('Eliminando la base local, pendiente'), findsOneWidget);
      expect(find.bySemanticsLabel('Cerrando tu sesión, pendiente'), findsOneWidget);
      expect(find.text('No cierres la app.'), findsOneWidget);
      expect(find.byKey(const Key('borrar_datos_atras')), findsNothing);
      final popScope = tester.widget<PopScope>(
        find.descendant(
          of: find.byType(BorrarDatosLocalesPage),
          matching: find.byWidgetPredicate((w) => w is PopScope),
          skipOffstage: false,
        ),
      );
      expect(popScope.canPop, isFalse, reason: 'el atrás del sistema no saca mientras borra');

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(BorrarDatosLocalesPage), findsOneWidget);

      _datos.demoraBorrado!.complete();
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
      handle.dispose();
    });

    testWidgets('al llegar a cerrar la sesión, los dos primeros pasos ya están hechos', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final local = _LocalQueNoBorra()..demora = Completer<void>();
      await _montar(tester, local: local);
      await _irAConfirmacion(tester);
      await _completarConfirmacion(tester);

      await _confirmar(tester, settle: false);

      expect(find.bySemanticsLabel('Pisando el archivo con ceros, hecho'), findsOneWidget);
      expect(find.bySemanticsLabel('Eliminando la base local, hecho'), findsOneWidget);
      expect(find.bySemanticsLabel('Cerrando tu sesión, en curso'), findsOneWidget);

      local.demora!.complete();
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
      handle.dispose();
    });
  });

  group('A07 Falla al borrar el backup en Drive', () {
    testWidgets('los datos locales se borraron: lo dice con el texto de la HU y no los restaura', (
      tester,
    ) async {
      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.backupDriveNoBorrado);
      final container = await _montar(tester);

      await _borrarTodo(tester, incluirDrive: true);

      expect(find.text('Datos de este teléfono borrados'), findsOneWidget);
      expect(find.text('Backup en Drive sin borrar'), findsOneWidget);
      expect(
        find.text(
          'Tus datos locales se eliminaron. No pudimos borrar el backup en Drive; eliminalo '
          'manualmente desde drive.google.com o reintentá.',
        ),
        findsOneWidget,
      );
      expect(_datos.borrados, [true], reason: 'los datos locales sí se borran (no se revierte)');
      expect(container.read(sesionProvider).value, isNull);
    });

    testWidgets('por falta de red usa «No pudimos borrar el backup remoto; intentalo más tarde…»', (
      tester,
    ) async {
      _datos.respuestaBorrado = const Right(
        ResultadoBorradoDatosLocales.backupDriveNoBorradoSinConexion,
      );
      await _montar(tester);

      await _borrarTodo(tester, incluirDrive: true);

      expect(
        find.text('No pudimos borrar el backup remoto; intentalo más tarde desde Drive.'),
        findsOneWidget,
      );
    });

    testWidgets('«Reintentar» vuelve a probar con Drive y, si sale bien, va al login', (
      tester,
    ) async {
      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.backupDriveNoBorrado);
      await _montar(tester);
      await _borrarTodo(tester, incluirDrive: true);

      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.completo);
      await _tocar(tester, _k('borrar_datos_drive_reintentar'));

      expect(_datos.borrados, [true, true]);
      expect(_login, findsOneWidget);
    });

    testWidgets('si el reintento vuelve a fallar, queda la misma pantalla y se puede reintentar', (
      tester,
    ) async {
      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.backupDriveNoBorrado);
      await _montar(tester);
      await _borrarTodo(tester, incluirDrive: true);

      await _tocar(tester, _k('borrar_datos_drive_reintentar'));

      expect(find.byKey(const Key('borrar_datos_falla_drive')), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_drive_reintentar'), isTrue);
      expect(_datos.borrados, [true, true]);
    });

    testWidgets('«Ir al login» saca la pantalla', (tester) async {
      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.backupDriveNoBorrado);
      await _montar(tester);
      await _borrarTodo(tester, incluirDrive: true);
      await _tocar(tester, _k('borrar_datos_ir_al_login'));
      expect(_login, findsOneWidget);
      expect(find.byType(BorrarDatosLocalesPage), findsNothing);
    });

    testWidgets('el atrás del sistema no vuelve a una pantalla sin datos: va al login', (
      tester,
    ) async {
      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.backupDriveNoBorrado);
      await _montar(tester);
      await _borrarTodo(tester, incluirDrive: true);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_login, findsOneWidget);
      expect(find.byType(BorrarDatosLocalesPage), findsNothing);
    });
  });

  group('A08 Error al borrar', () {
    testWidgets('si el borrado falla a mitad, no promete que no se borró nada y deja reintentar', (
      tester,
    ) async {
      _datos.respuestaBorrado = const Left(FailureInesperado());
      final container = await _montar(tester);

      await _borrarTodo(tester);

      expect(find.text('No pudimos borrar tus datos'), findsOneWidget);
      expect(find.text(TextosBorrado.errorBorrado), findsOneWidget);
      expect(find.textContaining('No se borró nada'), findsNothing);
      expect(container.read(sesionProvider).value, isNotNull);

      // El reintento no vuelve a contar pendientes (podría no poder: la DB ya está a medias).
      final resumenesAntes = _datos.llamadasResumen;
      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.completo);
      await _tocar(tester, _k('borrar_datos_reintentar'));

      expect(_datos.borrados, [false, false]);
      expect(_datos.llamadasResumen, resumenesAntes);
      expect(_login, findsOneWidget);
    });

    testWidgets('falla a mitad + «Volver» + reentrar: sigue en terminar el borrado, sin trabarse '
        'en «No se pudieron contar»', (tester) async {
      _datos.respuestaBorrado = const Left(FailureInesperado());
      final container = await _montar(tester);
      await _borrarTodo(tester);
      await _tocar(tester, _k('borrar_datos_volver_configuracion'));
      expect(find.byType(ConfiguracionPage), findsOneWidget);

      // Con la DB ya cerrada y el archivo sin borrar, contar daría «no se pudo»: no se vuelve a contar.
      _datos.respuestas
        ..clear()
        ..add(Right(_res(pendientes: null)));
      final resumenesAntes = _datos.llamadasResumen;
      await _abrirBorrado(tester);

      expect(find.byKey(const Key('borrar_datos_error')), findsOneWidget);
      expect(find.text(TextosBorrado.errorBorrado), findsOneWidget);
      expect(_datos.llamadasResumen, resumenesAntes);
      expect(find.byKey(const Key('borrar_datos_error_resumen')), findsNothing);

      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.completo);
      await _tocar(tester, _k('borrar_datos_reintentar'));

      expect(_datos.reintentos.last, isTrue, reason: 'es un reintento: termina lo que empezó');
      expect(_login, findsOneWidget);
      expect(container.read(borradoEmpezadoProvider), isNull, reason: 'ya no hay nada a medias');
    });

    testWidgets('si no pudo empezar, volver y reentrar vuelve a contar (no hay nada a medias)', (
      tester,
    ) async {
      _datos.respuestas
        ..clear()
        ..addAll([Right(_res()), const Left(FailureDatosLocalesIlegibles()), Right(_res())]);
      final container = await _montar(tester);
      await _borrarTodo(tester);
      expect(container.read(borradoEmpezadoProvider), isNull);
      await _tocar(tester, _k('borrar_datos_volver_configuracion'));

      await _abrirBorrado(tester);

      expect(find.byKey(const Key('borrar_datos_resumen')), findsOneWidget);
    });

    testWidgets('la carrera: el borrado se niega por una fila nueva y vuelve al bloqueo con '
        'su aviso', (tester) async {
      // El resumen y el control del caso de uso dan 0; la guarda del repositorio, pegada al cierre
      // de la DB, ve la fila que entró en el medio.
      _datos.respuestaBorrado = const Left(FailureBorradoConPendientes(pendientes: 1));
      _datos.respuestas
        ..clear()
        ..addAll([Right(_res()), Right(_res()), Right(_res(pendientes: 1))]);
      final container = await _montar(tester);

      await _borrarTodo(tester);

      expect(_datos.borrados, [false], reason: 'el repositorio fue el que se negó');
      expect(container.read(sesionProvider).value, isNotNull);
      expect(find.byKey(const Key('borrar_datos_resumen')), findsOneWidget);
      expect(find.text(TextosBorrado.pendientes(1)), findsOneWidget);
      expect(find.text(const FailureBorradoConPendientes(pendientes: 1).mensaje), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isFalse);
      expect(container.read(borradoEmpezadoProvider), isNull);
    });

    testWidgets('«No se borró nada y tu sesión sigue abierta» solo cuando es cierto', (
      tester,
    ) async {
      // La carga de la pantalla anda; el control del caso de uso, justo antes de borrar, no.
      _datos.respuestas
        ..clear()
        ..addAll([Right(_res()), const Left(FailureDatosLocalesIlegibles()), Right(_res())]);
      final container = await _montar(tester);

      await _borrarTodo(tester);

      expect(
        find.text('No se borró nada y tu sesión sigue abierta. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(_datos.borrados, isEmpty);
      expect(container.read(sesionProvider).value, isNotNull);

      await _tocar(tester, _k('borrar_datos_reintentar'));
      expect(_datos.borrados, [false]);
      expect(_login, findsOneWidget);
    });

    testWidgets('si borra pero no puede cerrar la sesión, no muestra el login y deja reintentar', (
      tester,
    ) async {
      final local = _LocalQueNoBorra();
      final container = await _montar(tester, local: local);
      local.fallar = true;

      await _borrarTodo(tester);

      expect(find.text(TextosBorrado.errorBorrado), findsOneWidget);
      expect(container.read(sesionProvider).value, isNotNull);
      expect(_login, findsNothing);

      local.fallar = false;
      await _tocar(tester, _k('borrar_datos_reintentar'));
      expect(_login, findsOneWidget);
    });

    testWidgets('«Volver a Configuración» no borra nada y deja la sesión abierta', (tester) async {
      _datos.respuestaBorrado = const Left(FailureInesperado());
      final container = await _montar(tester);
      await _borrarTodo(tester);

      await _tocar(tester, _k('borrar_datos_volver_configuracion'));

      expect(find.byType(ConfiguracionPage), findsOneWidget);
      expect(find.byType(BorrarDatosLocalesPage), findsNothing);
      expect(container.read(sesionProvider).value, isNotNull);
    });

    testWidgets('«Reintentar» no se puede tocar dos veces: mientras borra, el botón no está', (
      tester,
    ) async {
      _datos.respuestaBorrado = const Left(FailureInesperado());
      await _montar(tester);
      await _borrarTodo(tester);

      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.completo);
      _datos.demoraBorrado = Completer<void>();
      await _tocar(tester, _k('borrar_datos_reintentar'), settle: false);
      expect(find.byKey(const Key('borrar_datos_reintentar')), findsNothing);
      expect(find.byKey(const Key('borrar_datos_borrando')), findsOneWidget);
      _datos.demoraBorrado!.complete();
      await tester.pumpAndSettle();

      expect(_datos.borrados, [false, false], reason: 'el original y un solo reintento');
      expect(_login, findsOneWidget);
    });

    testWidgets('si entre el resumen y la confirmación aparece una operación, no borra nada y '
        'vuelve al resumen bloqueado', (tester) async {
      _datos.respuestas
        ..clear()
        ..addAll([Right(_res()), Right(_res(pendientes: 2)), Right(_res(pendientes: 2))]);
      final container = await _montar(tester);

      await _borrarTodo(tester);

      expect(_datos.borrados, isEmpty);
      expect(container.read(sesionProvider).value, isNotNull);
      expect(find.byKey(const Key('borrar_datos_resumen')), findsOneWidget);
      expect(find.text(TextosBorrado.pendientes(2)), findsOneWidget);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isFalse);
    });
  });

  group('A09 Sin conexión (igual procede)', () {
    testWidgets('la opción de borrar el backup queda deshabilitada con «requiere conexión»', (
      tester,
    ) async {
      _monitor.inicial = TipoConexion.sinConexion;
      await _montar(tester);
      await _irAConfirmacion(tester);

      expect(
        find.text('Sí, borrar también mi backup en Drive · requiere conexión'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Sin conexión. La contraseña se valida en este teléfono y los datos se borran igual.',
        ),
        findsOneWidget,
      );
      await tester.tap(_k('borrar_datos_incluir_drive'), warnIfMissed: false);
      await tester.pump();
      expect(
        _seleccionada(tester, 'borrar_datos_conservar_drive'),
        isTrue,
        reason: 'sigue en «conservar»',
      );
    });

    testWidgets('sin conexión los datos se borran igual (la contraseña se valida en el teléfono)', (
      tester,
    ) async {
      _monitor.inicial = TipoConexion.sinConexion;
      await _montar(tester);

      await _borrarTodo(tester);

      expect(_datos.borrados, [false]);
      expect(_login, findsOneWidget);
    });

    testWidgets(
      'si se corta la conexión después de elegir borrar el backup, vuelve a «conservar»',
      (tester) async {
        await _montar(tester);
        await _irAConfirmacion(tester);
        await _tocar(tester, find.text(TextosBorrado.borrarDrive));
        expect(_seleccionada(tester, 'borrar_datos_incluir_drive'), isTrue);

        _monitor.controlador.add(TipoConexion.sinConexion);
        await tester.pumpAndSettle();

        expect(_seleccionada(tester, 'borrar_datos_conservar_drive'), isTrue);
        expect(find.byKey(const Key('borrar_datos_sin_conexion')), findsOneWidget);

        _monitor.controlador.add(TipoConexion.wifi);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('borrar_datos_sin_conexion')), findsNothing);
        expect(find.text(TextosBorrado.borrarDrive), findsOneWidget);
      },
    );
  });

  group('Estados de la vista', () {
    testWidgets('cargando: mientras cuenta, lo dice', (tester) async {
      await _montar(tester);
      _datos.demoraResumen = Completer<void>();

      await tester.tap(_k('configuracion_borrar_datos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Revisando los datos de este teléfono…'), findsOneWidget);
      _datos.demoraResumen!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('borrar_datos_resumen')), findsOneWidget);
    });

    testWidgets('error: si no puede revisar los datos, no ofrece borrar y deja reintentar', (
      tester,
    ) async {
      _datos.respuestas
        ..clear()
        ..addAll([const Left(FailureDatosLocalesIlegibles()), Right(_res())]);
      await _montar(tester);
      await _abrirBorrado(tester);

      expect(find.text(const FailureDatosLocalesIlegibles().mensaje), findsOneWidget);
      expect(find.byKey(const Key('borrar_datos_continuar')), findsNothing);
      expect(_datos.borrados, isEmpty);

      await _tocar(tester, _k('borrar_datos_reintentar_resumen'));
      expect(find.byKey(const Key('borrar_datos_resumen')), findsOneWidget);
    });

    testWidgets('volver atrás y reentrar: arranca de cero y vuelve a contar', (tester) async {
      await _montar(tester);
      await _abrirBorrado(tester);
      await _marcarCasillas(tester);

      await _alPrincipio(tester);
      await _tocar(tester, _k('borrar_datos_atras'));
      expect(find.byType(ConfiguracionPage), findsOneWidget);
      await _abrirBorrado(tester);

      expect(_datos.llamadasResumen, 2);
      expect(tester.widget<CheckboxListTile>(_k('borrar_datos_checkbox')).value, isFalse);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isFalse);
    });

    testWidgets('el atrás de la confirmación vuelve al resumen con las casillas como estaban', (
      tester,
    ) async {
      await _montar(tester);
      await _irAConfirmacion(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('borrar_datos_resumen')), findsOneWidget);
      expect(find.byKey(const Key('borrar_datos_confirmacion')), findsNothing);
      expect(tester.widget<CheckboxListTile>(_k('borrar_datos_checkbox')).value, isTrue);
      expect(_habilitado(tester, 'borrar_datos_continuar'), isTrue);
      expect(_datos.borrados, isEmpty);
    });

    testWidgets('el «‹» de la confirmación también vuelve al resumen', (tester) async {
      await _montar(tester);
      await _irAConfirmacion(tester);

      await _alPrincipio(tester);
      await _tocar(tester, _k('borrar_datos_atras'));

      expect(find.byKey(const Key('borrar_datos_resumen')), findsOneWidget);
    });

    testWidgets('en reposo, el PopScope deja salir y «atrás» está habilitado', (tester) async {
      await _montar(tester);
      await _abrirBorrado(tester);

      expect(tester.widget<IconButton>(_k('borrar_datos_atras')).onPressed, isNotNull);
      final popScope = tester.widget<PopScope>(
        find.descendant(
          of: find.byType(BorrarDatosLocalesPage),
          matching: find.byWidgetPredicate((w) => w is PopScope),
          skipOffstage: false,
        ),
      );
      expect(popScope.canPop, isTrue);
    });
  });

  group('Accesibilidad', () {
    Future<void> guias(WidgetTester tester) async {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }

    testWidgets('el resumen (con y sin pendientes, sin conteo) cumple las guías', (tester) async {
      final handle = tester.ensureSemantics();
      _pantalla(tester, const Size(390, 844));
      await _montar(tester);
      await _abrirBorrado(tester);
      await guias(tester);

      await _marcarCasillas(tester);
      await guias(tester);
      handle.dispose();
    });

    testWidgets('el bloqueo por pendientes cumple las guías', (tester) async {
      final handle = tester.ensureSemantics();
      _pantalla(tester, const Size(390, 844));
      _datos.respuestas[0] = Right(_res(pendientes: 7));
      await _montar(tester);
      await _abrirBorrado(tester);
      await guias(tester);
      handle.dispose();
    });

    testWidgets('«No se pudieron contar» cumple las guías', (tester) async {
      final handle = tester.ensureSemantics();
      _pantalla(tester, const Size(390, 844));
      _datos.respuestas[0] = Right(_res(pendientes: null));
      await _montar(tester);
      await _abrirBorrado(tester);
      await guias(tester);
      handle.dispose();
    });

    testWidgets('la confirmación final (con errores y sin conexión) cumple las guías', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      _pantalla(tester, const Size(390, 844));
      _monitor.inicial = TipoConexion.sinConexion;
      await _montar(tester);
      await _irAConfirmacion(tester);
      await guias(tester);

      await _escribir(tester, 'borrar_datos_frase', 'mal');
      await _escribir(tester, 'borrar_datos_password', 'otra');
      await _confirmar(tester);
      await guias(tester);

      await _escribir(tester, 'borrar_datos_frase', _frase);
      await _confirmar(tester);
      expect(find.textContaining('Contraseña incorrecta'), findsOneWidget);
      await guias(tester);
      handle.dispose();
    });

    testWidgets('«Borrando», la falla de Drive y el error al borrar cumplen las guías', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      _pantalla(tester, const Size(390, 844));
      _datos.demoraBorrado = Completer<void>();
      await _montar(tester);
      await _irAConfirmacion(tester);
      await _completarConfirmacion(tester);
      await _confirmar(tester, settle: false);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.backupDriveNoBorrado);
      _datos.demoraBorrado!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('borrar_datos_falla_drive')), findsOneWidget);
      await guias(tester);

      _datos.respuestaBorrado = const Left(FailureInesperado());
      await _tocar(tester, _k('borrar_datos_drive_reintentar'));
      expect(find.byKey(const Key('borrar_datos_error')), findsOneWidget);
      await guias(tester);
      handle.dispose();
    });

    testWidgets('con textScaler 2.0 no hay overflow en ningún estado del flujo', (tester) async {
      _pantalla(tester, const Size(360, 740), escala: 2.0);
      _datos.respuestas
        ..clear()
        ..addAll([
          Right(_res(pendientes: 12345, personas: 123456, visitas: 987654)),
          Right(_res(pendientes: null)),
          Right(_res()),
        ]);
      await _montar(tester, nombre: 'María de los Ángeles Fernández de la Vega y Rodríguez-Silva');
      await _abrirBorrado(tester);
      expect(find.byKey(const Key('borrar_datos_aviso_pendientes')), findsOneWidget);
      expect(tester.takeException(), isNull);

      _sync.respuesta = const Right(unit);
      await _tocar(tester, _k('borrar_datos_sincronizar'));
      expect(find.byKey(const Key('borrar_datos_sin_conteo')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _tocar(tester, _k('borrar_datos_reintentar_conteo'));
      await _marcarCasillas(tester);
      await _tocar(tester, _k('borrar_datos_continuar'));
      expect(find.byKey(const Key('borrar_datos_confirmacion')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _escribir(tester, 'borrar_datos_frase', 'mal');
      await _escribir(tester, 'borrar_datos_password', 'otra');
      await _confirmar(tester);
      expect(find.byKey(const Key('borrar_datos_confirmar')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _desmontar(tester);
    });

    testWidgets('con textScaler 2.0 no hay overflow en «Borrando», Drive y error', (tester) async {
      _pantalla(tester, const Size(360, 740), escala: 2.0);
      _datos.demoraBorrado = Completer<void>();
      await _montar(tester);
      await _irAConfirmacion(tester);
      await _completarConfirmacion(tester);
      await _confirmar(tester, settle: false);
      expect(find.byKey(const Key('borrar_datos_borrando')), findsOneWidget);
      expect(tester.takeException(), isNull);

      _datos.respuestaBorrado = const Right(ResultadoBorradoDatosLocales.backupDriveNoBorrado);
      _datos.demoraBorrado!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('borrar_datos_falla_drive')), findsOneWidget);
      expect(tester.takeException(), isNull);

      _datos.respuestaBorrado = const Left(FailureInesperado());
      await _tocar(tester, _k('borrar_datos_drive_reintentar'));
      expect(find.byKey(const Key('borrar_datos_error')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Un `EditableTextState` cualquiera, para invocar el `contextMenuBuilder` del campo.
EditableTextState _estadoDelCampo(WidgetTester tester) => tester.state<EditableTextState>(
  find.descendant(of: _k('borrar_datos_frase'), matching: find.byType(EditableText)),
);
