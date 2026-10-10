// Arnés compartido de la QA del PR #351 (#313 y #318, vista 14 «Olvidé mi contraseña»): los fakes de
// la hora del último envío, el montaje de la pantalla sobre «pantalla de abajo» (con o sin sesión,
// en el tamaño y con el texto que pida el test) y los finders de la vista.
import 'dart:async';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/ultimo_envio_recuperacion_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'db_local_repository_en_memoria.dart';

const correoQa = 'lucia.silva@correo.com';
const claveQa = 'Secreto123';
const mensajeNeutroQa = 'Si el email está registrado, te enviamos un enlace de recuperación';
const sinConexionQa = 'Necesitás conexión para solicitar la recuperación';
const incompletoQa = 'Revisá el email: parece incompleto.';
const avisoLentaQa =
    'No pudimos comprobar si ya pediste un enlace hace poco. Esperá unos segundos y probá de '
    'nuevo.';
const topeQa = Duration(seconds: 3);

Finder llaveQa(String key) => find.byKey(Key(key));

final enviarQa = llaveQa('recuperacion_password_enviar');
final volverQa = llaveQa('recuperacion_password_volver_login');
final reenviarQa = llaveQa('recuperacion_password_reenviar');
final atrasQa = llaveQa('recuperacion_password_atras');
final exitoQa = llaveQa('recuperacion_password_exito');
final avisoGeneralQa = llaveQa('recuperacion_password_error_general');
final esperaQa = llaveQa('recuperacion_password_espera');

bool habilitadoQa(WidgetTester tester, Finder boton) {
  final w = tester.widget(boton);
  return switch (w) {
    FilledButton(:final onPressed) => onPressed != null,
    OutlinedButton(:final onPressed) => onPressed != null,
    TextButton(:final onPressed) => onPressed != null,
    IconButton(:final onPressed) => onPressed != null,
    _ => throw StateError('no es un botón: ${w.runtimeType}'),
  };
}

/// El reloj de la pantalla en los tests: la hora de ahora, que el test mueve a mano.
final class RelojQa {
  RelojQa(this.ahora);

  DateTime ahora;

  DateTime call() => ahora;
}

/// Pasa [cuanto] tiempo: el reloj de la pantalla y el del test (donde corre su timer).
Future<void> pasarQa(WidgetTester tester, RelojQa reloj, Duration cuanto) async {
  reloj.ahora = reloj.ahora.add(cuanto);
  await tester.pump(cuanto);
}

/// El repositorio de la hora del último envío con lo que el test le diga: una hora guardada, una
/// lectura que espera, una escritura que espera o que falla.
final class EnviosQa implements UltimoEnvioRecuperacionRepository {
  EnviosQa({this.hora, this.lectura, this.escritura, this.escrituraFalla = false});

  DateTime? hora;
  final Completer<DateTime?>? lectura;
  final Completer<void>? escritura;
  final bool escrituraFalla;
  final List<DateTime> guardados = [];
  int lecturas = 0;

  @override
  Future<DateTime?> leer() {
    lecturas++;
    return lectura?.future ?? Future.value(hora);
  }

  @override
  Future<void> guardar(DateTime cuando) async {
    guardados.add(cuando);
    if (escrituraFalla) throw StateError('el almacén no pudo escribir');
    hora = cuando;
    await escritura?.future;
  }
}

/// Un almacén seguro cuyas escrituras no contestan: el Keystore colgado.
final class AlmacenColgadoQa implements AlmacenSeguro {
  final Completer<void> _nunca = Completer<void>();

  @override
  Future<String?> leer(ClaveSegura clave) async => null;

  @override
  Future<void> escribir(ClaveSegura clave, String valor) => _nunca.future;

  @override
  Future<void> borrar(ClaveSegura clave) async {}

  @override
  Future<void> borrarTodo() async {}
}

/// La ruta de abajo (el login o el inicio) con «abrir», y la pantalla encima.
Widget appQa({
  required DateTime Function() ahora,
  String? emailInicial,
  ThemeData? tema,
  bool viaVencido = false,
}) => MaterialApp(
  theme: tema ?? temaClaro(),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          key: const Key('abrir_recuperacion'),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => viaVencido
                  ? const ConfirmarRecuperacionPasswordPage(enlace: EnlaceRecuperacion.vencido)
                  : RecuperacionPasswordPage(emailInicial: emailInicial, ahora: ahora),
            ),
          ),
          child: const Text('pantalla de abajo'),
        ),
      ),
    ),
  ),
);

/// Monta la pantalla encima de «pantalla de abajo», con o sin la sesión abierta, en el tamaño y con
/// el texto que diga el test (390×844 al 100 % por defecto, el tamaño de las guías de contraste).
Future<ProviderContainer> montarQa(
  WidgetTester tester, {
  required AuthRemoteDataSourceEnMemoria remote,
  bool conSesion = false,
  UltimoEnvioRecuperacionRepository? ultimoEnvio,
  DateTime Function()? ahora,
  String? emailInicial,
  Size tamano = const Size(390, 844),
  double texto = 1,
  ThemeData? tema,
  bool viaVencido = false,
}) async {
  tester.view
    ..physicalSize = tamano
    ..devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  final container = ProviderContainer(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(remote),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      if (ultimoEnvio != null)
        ultimoEnvioRecuperacionRepositoryProvider.overrideWithValue(ultimoEnvio),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  if (conSesion) {
    await container.read(sesionProvider.notifier).iniciarSesion(email: correoQa, password: claveQa);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: appQa(
        ahora: ahora ?? DateTime.now,
        emailInicial: emailInicial,
        tema: tema,
        viaVencido: viaVencido,
      ),
    ),
  );
  await tester.tap(llaveQa('abrir_recuperacion'));
  await tester.pumpAndSettle();
  return container;
}

AuthRemoteDataSourceEnMemoria remotoQa() =>
    AuthRemoteDataSourceEnMemoria(credenciales: const {correoQa: claveQa});

Future<void> escribirQa(WidgetTester tester, String email) async {
  await tester.enterText(llaveQa('recuperacion_password_email'), email);
  await tester.pump();
}

Future<void> tocarQa(WidgetTester tester, Finder boton) async {
  await tester.ensureVisible(boton);
  await tester.tap(boton);
}

/// De A01 a A05 con el reloj quieto: escribe el correo y pide el enlace.
Future<void> aA05Qa(WidgetTester tester) async {
  await escribirQa(tester, correoQa);
  await tocarQa(tester, enviarQa);
  await tester.pumpAndSettle();
}

String textoDelCampoQa(WidgetTester tester) =>
    tester.widget<TextField>(llaveQa('recuperacion_password_email')).controller!.text;

int pedidosQa(AuthRemoteDataSourceEnMemoria remote) =>
    remote.solicitudesRecuperacionPorEmail[correoQa] ?? 0;

/// El atrás del sistema; devuelve si la pantalla de recuperación sigue abierta.
Future<bool> atrasDelSistemaQa(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  return find.byType(RecuperacionPasswordPage).evaluate().isNotEmpty;
}

typedef ArmarQa = Future<void> Function(WidgetTester tester, Size tam, double texto);

/// Un estado de la vista: cómo llegar a él, qué debe verse y la acción que no puede quedar fuera.
final class EstadoQa {
  const EstadoQa(this.nombre, this.armar, this.visible, this.accion, {required this.habilitada});

  final String nombre;
  final ArmarQa armar;

  /// Lo que dice el estado (texto literal) y que tiene que verse entero.
  final String visible;
  final Finder accion;
  final bool habilitada;
}

final tamanosQa = <Size>[const Size(360, 640), const Size(412, 915)];
const textosQa = <double>[1, 2, 3];

String nombreTamQa(Size t) => '${t.width.toInt()}×${t.height.toInt()}';

final estadosQa = <EstadoQa>[
  EstadoQa(
    'A01 principal',
    (tester, tam, texto) async {
      await montarQa(tester, remote: remotoQa(), tamano: tam, texto: texto);
    },
    '¿Olvidaste tu contraseña?',
    enviarQa,
    habilitada: true,
  ),
  EstadoQa(
    'A03 email inválido',
    (tester, tam, texto) async {
      await montarQa(tester, remote: remotoQa(), tamano: tam, texto: texto);
      await escribirQa(tester, 'lucia@');
      await tocarQa(tester, enviarQa);
      await tester.pumpAndSettle();
    },
    incompletoQa,
    enviarQa,
    habilitada: true,
  ),
  EstadoQa(
    'A04 enviando',
    (tester, tam, texto) async {
      final remote = remotoQa()..demoraRecuperacion = Completer<void>();
      addTearDown(() => remote.demoraRecuperacion?.complete());
      await montarQa(tester, remote: remote, tamano: tam, texto: texto);
      await escribirQa(tester, correoQa);
      await tocarQa(tester, enviarQa);
      await tester.pump();
    },
    'Enviando…',
    atrasQa,
    habilitada: false,
  ),
  EstadoQa(
    'A05 éxito sin sesión',
    (tester, tam, texto) async {
      await montarQa(tester, remote: remotoQa(), tamano: tam, texto: texto);
      await aA05Qa(tester);
    },
    mensajeNeutroQa,
    volverQa,
    habilitada: true,
  ),
  EstadoQa(
    'A05 éxito con la sesión abierta',
    (tester, tam, texto) async {
      await montarQa(tester, remote: remotoQa(), conSesion: true, tamano: tam, texto: texto);
      await aA05Qa(tester);
    },
    mensajeNeutroQa,
    volverQa,
    habilitada: true,
  ),
  EstadoQa(
    'A05 con el reenvío en vuelo',
    (tester, tam, texto) async {
      final remote = remotoQa();
      final reloj = RelojQa(DateTime(2026, 10, 10, 10));
      await montarQa(
        tester,
        remote: remote,
        conSesion: true,
        ahora: reloj.call,
        tamano: tam,
        texto: texto,
      );
      await aA05Qa(tester);
      await pasarQa(tester, reloj, const Duration(seconds: 60));
      remote.demoraRecuperacion = Completer<void>();
      addTearDown(() => remote.demoraRecuperacion?.complete());
      await tester.tap(reenviarQa);
      await tester.pump();
    },
    'Enviando…',
    volverQa,
    habilitada: false,
  ),
  EstadoQa(
    'A05 con el reenvío sin conexión',
    (tester, tam, texto) async {
      final remote = remotoQa();
      final reloj = RelojQa(DateTime(2026, 10, 10, 10));
      await montarQa(tester, remote: remote, ahora: reloj.call, tamano: tam, texto: texto);
      await aA05Qa(tester);
      await pasarQa(tester, reloj, const Duration(seconds: 60));
      remote.simularSinConexion = true;
      await tester.tap(reenviarQa);
      await tester.pumpAndSettle();
    },
    sinConexionQa,
    volverQa,
    habilitada: true,
  ),
  EstadoQa(
    'A06 sin conexión',
    (tester, tam, texto) async {
      final remote = remotoQa()..simularSinConexion = true;
      await montarQa(tester, remote: remote, tamano: tam, texto: texto);
      await escribirQa(tester, correoQa);
      await tocarQa(tester, enviarQa);
      await tester.pumpAndSettle();
    },
    sinConexionQa,
    enviarQa,
    habilitada: true,
  ),
  EstadoQa(
    'A01 con la espera vigente',
    (tester, tam, texto) async {
      final reloj = RelojQa(DateTime(2026, 10, 10, 10));
      final envios = EnviosQa(hora: reloj.ahora.subtract(const Duration(seconds: 20)));
      await montarQa(
        tester,
        remote: remotoQa(),
        ultimoEnvio: envios,
        ahora: reloj.call,
        tamano: tam,
        texto: texto,
      );
    },
    'Podés pedir otro enlace en 40s.',
    enviarQa,
    habilitada: false,
  ),
  EstadoQa(
    'A01 con el aviso de lectura lenta',
    (tester, tam, texto) async {
      final envios = EnviosQa(lectura: Completer<DateTime?>());
      await montarQa(tester, remote: remotoQa(), ultimoEnvio: envios, tamano: tam, texto: texto);
      await escribirQa(tester, correoQa);
      await tocarQa(tester, enviarQa);
      await tester.pump(topeQa + const Duration(milliseconds: 100));
    },
    avisoLentaQa,
    enviarQa,
    habilitada: true,
  ),
];
