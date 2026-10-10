// QA del PR #333 (#325, HU-AUTH-002, vista 12 «Verificación de correo»): texto del límite en
// minutos, espera de 60 s «Reenviar en Ns» contada desde el correo del alta y poda de candados.
//
// Lo que `verificacion_email_page_test.dart`, `verificacion_email_qa_249_test.dart` y
// `registro_page_test.dart` no ejercitan:
// - el texto del límite en cada borde de minuto (60 → «una hora», 2 a 59, 1) y que nunca dice
//   menos que lo que falta de verdad;
// - la cuenta regresiva y el lector de pantalla (ni un anuncio por segundo), y el aviso del límite
//   al volver de segundo plano o al cambiar la dirección escrita;
// - el teclado abierto en la pantalla con el campo del correo;
// - el flujo entero Registro → Verificación contra el almacén de verdad: reinicio de la app durante
//   la espera, reloj movido, almacén roto, «Ya verifiqué mi email», doble toque en «Continuar»;
// - que los logs del repositorio no llevan el correo;
// - las medidas (360x640 y 412x915, texto 1.0 y 2.0) de los textos del límite que el resto no mide.
//
// Las capturas van a `.dart_tool/qa_capturas/` (ignorado por git, nunca se commitean).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/bloqueo_reenvio_verificacion_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/logger_mudo.dart';

const _lucia = 'lucia.silva@correo.com';
const _ana = 'ana@correo.com';
const _unaHora = Duration(minutes: 60);

String _textoLimite(String cuanto) => 'Demasiados intentos. Probá nuevamente en $cuanto.';

final _base = DateTime(2026, 10, 9, 10);

final _aviso = find.byKey(const Key('verificacion_email_limite'));
final _botonReenviar = find.byKey(const Key('verificacion_email_reenviar'));
final _campo = find.byKey(const Key('verificacion_email_campo'));
final _volver = find.byKey(const Key('verificacion_email_volver_login'));
final _yaVerifique = find.byKey(const Key('verificacion_email_ya_verifique'));
final _mensajeReenvio = find.byKey(const Key('verificacion_email_mensaje_reenvio'));
final _errorGeneral = find.byKey(const Key('verificacion_email_error_general'));
final _progreso = find.byKey(const Key('verificacion_email_progreso'));

final _llave = GlobalKey();

/// Reloj que el test mueve a mano (adelante o atrás).
final class _Reloj {
  _Reloj(this.ahora);

  DateTime ahora;

  DateTime leer() => ahora;
}

AuthRemoteDataSourceEnMemoria _remotoSano() =>
    AuthRemoteDataSourceEnMemoria(credenciales: const {_lucia: 'Secreto123', _ana: 'Secreto123'});

AuthRemoteDataSourceEnMemoria _remotoConAltaPendiente() =>
    AuthRemoteDataSourceEnMemoria(credenciales: const {}, requiereVerificacionAlRegistrar: true);

bool _habilitado(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(_botonReenviar).onPressed != null;

bool _fuentesCargadas = false;

/// Sin las fuentes del proyecto `flutter_test` pinta cajas (Ahem) y las medidas no son las reales.
Future<void> _cargarFuentes(WidgetTester tester) async {
  if (_fuentesCargadas) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final loader = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (raiz != null && iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  });
  _fuentesCargadas = true;
}

/// La pantalla completa como PNG, fuera del repo.
Future<void> _capturar(WidgetTester tester, String nombre) => tester.runAsync(() async {
  final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_llave));
  final img = await render.toImage();
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
  File('${dir.path}/325_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
});

void _tamano(WidgetTester tester, Size tam) {
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app({required Widget home, double escala = 1}) => RepaintBoundary(
  key: _llave,
  child: MaterialApp(
    theme: temaClaro(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
      child: child!,
    ),
    home: home,
  ),
);

List<Override> _overrides(
  AuthRemoteDataSourceEnMemoria remote,
  BloqueoReenvioVerificacionRepository bloqueos,
) => [
  dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
  authRemoteDataSourceProvider.overrideWithValue(remote),
  authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
  bloqueoReenvioVerificacionRepositoryProvider.overrideWithValue(bloqueos),
];

/// [VerificacionEmailPage] sobre el tamaño [tam], con el texto a [escala].
Future<void> _montar(
  WidgetTester tester, {
  required AuthRemoteDataSourceEnMemoria remote,
  required BloqueoReenvioVerificacionRepository bloqueos,
  required DateTime Function() ahora,
  String email = _lucia,
  String? password = 'Secreto123',
  EstadoVerificacionEmail estado = EstadoVerificacionEmail.pendiente,
  DateTime? envioDelAlta,
  double escala = 1,
  Size tam = const Size(390, 844),
}) async {
  await _cargarFuentes(tester);
  _tamano(tester, tam);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(remote, bloqueos),
      child: _app(
        escala: escala,
        home: VerificacionEmailPage(
          email: email,
          password: password,
          estadoInicial: estado,
          envioDelAlta: envioDelAlta,
          ahora: ahora,
        ),
      ),
    ),
  );
}

/// [RegistroPage] sola, como la deja la app antes de que la persona toque «Continuar».
Future<void> _montarRegistro(
  WidgetTester tester, {
  required AuthRemoteDataSourceEnMemoria remote,
  required BloqueoReenvioVerificacionRepository bloqueos,
  Size tam = const Size(390, 844),
}) async {
  await _cargarFuentes(tester);
  _tamano(tester, tam);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(remote, bloqueos),
      child: _app(home: const RegistroPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _completarYContinuar(WidgetTester tester, {String email = _lucia}) async {
  await tester.enterText(find.byKey(const Key('registro_nombre')), 'Lucía');
  await tester.enterText(find.byKey(const Key('registro_apellido')), 'Silva');
  await tester.enterText(find.byKey(const Key('registro_cedula')), '4812309-2');
  await tester.enterText(find.byKey(const Key('registro_email')), email);
  await tester.enterText(find.byKey(const Key('registro_password')), 'Secreto123');
  await tester.tap(find.byKey(const Key('registro_terminos')));
  await tester.ensureVisible(find.byKey(const Key('registro_trade_off')));
  await tester.tap(find.byKey(const Key('registro_trade_off')));
  await tester.pump();
  await tester.ensureVisible(find.byKey(const Key('registro_continuar')));
  await tester.tap(find.byKey(const Key('registro_continuar')));
}

/// Saca la pantalla del árbol (como cerrar la app) para volver a montarla desde cero.
Future<void> _cerrarApp(WidgetTester tester) => tester.pumpWidget(const SizedBox());

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Captura y mide la parte de arriba y la de abajo (con el texto grande no entra todo).
Future<void> _recorrer(WidgetTester tester, String nombre) async {
  final pagina = find.byType(Scrollable).first;
  await tester.drag(pagina, const Offset(0, 5000));
  await tester.pumpAndSettle();
  await _capturar(tester, '${nombre}_arriba');
  await _guias(tester);
  await tester.drag(pagina, const Offset(0, -5000));
  await tester.pumpAndSettle();
  await _capturar(tester, '${nombre}_abajo');
  await _guias(tester);
}

/// El almacén seguro con la clave de los reenvíos, decodificada (o `null` si no hay clave).
Map<String, dynamic>? _guardado(AlmacenSeguroEnMemoria almacen) {
  final crudo = almacen.contenido[ClaveSegura.bloqueoReenvioVerificacion];
  return crudo == null ? null : jsonDecode(crudo) as Map<String, dynamic>;
}

/// Un almacén seguro cuyas operaciones fallan con una excepción que lleva el correo en su mensaje
/// (el peor caso para un log que interpolara el error).
final class _AlmacenQueDelataElCorreo implements AlmacenSeguro {
  @override
  Future<String?> leer(ClaveSegura clave) => throw Exception('no se pudo leer $_lucia');

  @override
  Future<void> escribir(ClaveSegura clave, String valor) =>
      throw Exception('no se pudo escribir $_lucia');

  @override
  Future<void> borrar(ClaveSegura clave) => throw Exception('no se pudo borrar $_lucia');

  @override
  Future<void> borrarTodo() => throw Exception('no se pudo borrar todo $_lucia');
}

final class _Recolector extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

/// Lo que dice el aviso para lo que falta [restanteMs]: el techo en minutos, tope una hora. Es la
/// regla de la HU escrita con aritmética entera, no la fórmula del código.
String _cuantoEsperado(int restanteMs) {
  final minutos = (restanteMs + 59999) ~/ 60000;
  if (minutos >= 60) return 'una hora';
  return minutos == 1 ? '1 minuto' : '$minutos minutos';
}

void main() {
  group('el texto del límite en cada borde de minuto (HU: redondeo hacia arriba)', () {
    testWidgets('barrido de 60 minutos: en cada borde dice el techo de lo que falta, nunca menos '
        'que lo real, con el singular y el plural correctos', (tester) async {
      final reloj = _Reloj(_base);
      final vence = _base.add(_unaHora);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria({_lucia: vence}),
        ahora: reloj.leer,
      );
      await tester.pumpAndSettle();

      // Lo que falta, de mayor a menor (el reloj solo avanza): cada minuto justo, un milisegundo
      // antes y un milisegundo después.
      final puntos = <int>{
        for (var m = 1; m <= 60; m++) ...[m * 60000, m * 60000 - 1, (m - 1) * 60000 + 1],
      }.where((r) => r > 0 && r <= 3600000).toList()..sort((a, b) => b.compareTo(a));

      for (final restante in puntos) {
        reloj.ahora = vence.subtract(Duration(milliseconds: restante));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pump();
        final esperado = _textoLimite(_cuantoEsperado(restante));
        expect(
          find.text(esperado),
          findsOneWidget,
          reason: 'faltan $restante ms: debía decir «$esperado»',
        );
        // Nunca un tiempo menor al real.
        final numero = RegExp(r'en (\d+) minutos?\.').firstMatch(esperado);
        if (numero != null) {
          expect(int.parse(numero.group(1)!) * 60000, greaterThanOrEqualTo(restante));
        }
      }
      // Una vez vencido, se va el aviso y el botón vuelve.
      reloj.ahora = vence;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(_aviso, findsNothing);
      expect(_habilitado(tester), isTrue);
      await _cerrarApp(tester);
    });
  });

  group('la cuenta regresiva y el lector de pantalla', () {
    testWidgets(
      '«Reenviar en Ns» no se anuncia segundo a segundo: ni región viva ni anuncios en los '
      '60 s, y el botón se lee deshabilitado con su cuenta',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final reloj = _Reloj(_base);
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: reloj.leer,
          envioDelAlta: _base,
        );
        await tester.pumpAndSettle();
        tester.takeAnnouncements();

        expect(find.text('Reenviar en 60s'), findsOneWidget);
        for (var s = 1; s < 60; s++) {
          reloj.ahora = _base.add(Duration(seconds: s));
          await tester.pump(const Duration(seconds: 1));
          expect(find.text('Reenviar en ${60 - s}s'), findsOneWidget);
          if (s % 15 == 0) {
            expect(
              tester.getSemantics(_botonReenviar),
              isSemantics(
                isButton: true,
                hasEnabledState: true,
                isEnabled: false,
                isLiveRegion: false,
                label: 'Reenviar en ${60 - s}s',
              ),
            );
          }
        }
        reloj.ahora = _base.add(const Duration(seconds: 60));
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeAnnouncements(), isEmpty, reason: 'ni un anuncio en toda la cuenta');
        expect(_progreso, findsNothing, reason: 'la barra se va con la cuenta');
        expect(_habilitado(tester), isTrue);
        expect(find.text('Reenviar email'), findsOneWidget);
        semantica.dispose();
        await _cerrarApp(tester);
      },
    );

    testWidgets('la barra de avance de la cuenta no entra en el árbol de accesibilidad', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: () => _base,
        envioDelAlta: _base.subtract(const Duration(seconds: 12)),
      );
      await tester.pumpAndSettle();

      expect(_progreso, findsOneWidget);
      expect(
        find.semantics.byLabel(RegExp('%|progress|avance', caseSensitive: false)),
        findsNothing,
        reason: 'el progreso es decorativo: la cuenta ya está en el botón',
      );
      semantica.dispose();
      await _cerrarApp(tester);
    });

    testWidgets('el aviso del límite no se vuelve a anunciar al volver de segundo plano ni cada '
        'minuto; sí al pasar a otra dirección bloqueada y volver', (tester) async {
      final semantica = tester.ensureSemantics();
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria({
          _lucia: _base.add(const Duration(minutes: 30)),
        }),
        ahora: reloj.leer,
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await tester.pumpAndSettle();
      tester.takeAnnouncements();

      await tester.enterText(_campo, _lucia);
      await tester.pump();
      await tester.pump();
      expect(tester.takeAnnouncements().map((a) => a.message), [_textoLimite('30 minutos')]);

      // Vuelve de segundo plano 10 minutos después: el texto se actualiza, no se re-anuncia.
      reloj.ahora = _base.add(const Duration(minutes: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(find.text(_textoLimite('20 minutos')), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(tester.takeAnnouncements(), isEmpty);

      // Otra dirección (libre): sin aviso y sin anuncio. De vuelta a la bloqueada: se anuncia otra vez.
      await tester.enterText(_campo, _ana);
      await tester.pump();
      expect(_aviso, findsNothing);
      expect(tester.takeAnnouncements(), isEmpty);
      await tester.enterText(_campo, '  ${_lucia.toUpperCase()} ');
      await tester.pump();
      await tester.pump();
      expect(tester.takeAnnouncements().map((a) => a.message), hasLength(1));
      semantica.dispose();
      await _cerrarApp(tester);
    });
  });

  group('teclado abierto en la pantalla con el campo del correo (enlace expirado, sin correo)', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('360x640 con el teclado (280 px) y texto ${escala}x: sin overflow, el campo y el '
          'aviso del límite se alcanzan, «Reenviar» y «Volver al login» se tocan', (tester) async {
        final semantica = tester.ensureSemantics();
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria({_lucia: _base.add(_unaHora)}),
          ahora: () => _base.add(const Duration(minutes: 4)),
          email: '',
          password: null,
          estado: EstadoVerificacionEmail.expirado,
          tam: const Size(360, 640),
          escala: escala,
        );
        await tester.pumpAndSettle();

        // Primero toca el campo (todavía sin teclado) y recién después sube el teclado.
        await tester.ensureVisible(_campo);
        await tester.tap(_campo);
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.enterText(_campo, _lucia);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Sobre el teclado hay 640 - 280 = 360 px: lo que la persona escribe se ve ahí, sin que
        // tenga que desplazar a mano (el campo con foco sube solo).
        expect(tester.getRect(_campo).bottom, lessThanOrEqualTo(360));
        expect(tester.getRect(_campo).top, greaterThanOrEqualTo(0));
        await _capturar(tester, 'teclado_campo_x$escala');

        await tester.ensureVisible(_aviso);
        await tester.pumpAndSettle();
        expect(find.text(_textoLimite('56 minutos')), findsOneWidget);
        expect(tester.getRect(_aviso).bottom, lessThanOrEqualTo(360));
        expect(tester.getRect(_aviso).top, greaterThanOrEqualTo(0));
        await _capturar(tester, 'teclado_aviso_x$escala');

        await tester.ensureVisible(_volver);
        await tester.pumpAndSettle();
        expect(tester.getSize(_volver).height, greaterThanOrEqualTo(48));
        expect(tester.getRect(_volver).bottom, lessThanOrEqualTo(360));
        await _guias(tester);

        // Lo tipeado no se pierde.
        expect(tester.widget<TextField>(_campo).controller!.text, _lucia);
        semantica.dispose();
        await _cerrarApp(tester);
      });
    }

    testWidgets('con el teclado abierto, escribir una dirección libre tras la espera del alta '
        'habilita «Reenviar» y se manda', (tester) async {
      final remote = _remotoSano();
      await _montar(
        tester,
        remote: remote,
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: () => _base,
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.expirado,
        tam: const Size(360, 640),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(_campo);
      await tester.tap(_campo);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(_campo, _ana);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_botonReenviar);
      await tester.pumpAndSettle();
      await tester.tap(_botonReenviar);
      await tester.pumpAndSettle();

      expect(remote.reenviosPorEmail[_ana], 1);
      expect(tester.takeException(), isNull);
      await _cerrarApp(tester);
    });
  });

  group('la espera de 60 s es por dirección en la pantalla con el campo del correo', () {
    testWidgets(
      'con una espera guardada para una dirección: al escribirla cuenta lo que falta, con '
      'otra queda libre, y al volver a la primera sigue la cuenta con el reloj',
      (tester) async {
        final reloj = _Reloj(_base);
        final remote = _remotoSano();
        await _montar(
          tester,
          remote: remote,
          bloqueos: BloqueoReenvioVerificacionEnMemoria.con(
            esperas: {_lucia: _base.add(const Duration(seconds: 30))},
          ),
          ahora: reloj.leer,
          email: '',
          password: null,
          estado: EstadoVerificacionEmail.expirado,
        );
        await tester.pumpAndSettle();
        // Sin dirección el botón se toca y la validación dice qué falta: no sale ningún correo.
        await tester.tap(_botonReenviar);
        await tester.pumpAndSettle();
        expect(remote.reenviosPorEmail, isEmpty);
        expect(tester.widget<TextField>(_campo).decoration!.errorText, isNotNull);

        await tester.enterText(_campo, _lucia);
        await tester.pump();
        await tester.pump();
        expect(find.text('Reenviar en 30s'), findsOneWidget);
        expect(_habilitado(tester), isFalse);
        expect(_aviso, findsNothing, reason: 'una espera no es un límite: sin aviso de «intentos»');

        await tester.enterText(_campo, _ana);
        await tester.pump();
        expect(find.text('Reenviar email de verificación'), findsOneWidget);
        expect(_habilitado(tester), isTrue);

        reloj.ahora = _base.add(const Duration(seconds: 12));
        await tester.enterText(_campo, '  ${_lucia.toUpperCase()}  ');
        await tester.pump();
        await tester.pump();
        expect(find.text('Reenviar en 18s'), findsOneWidget);
        expect(_habilitado(tester), isFalse);

        // Se cumple la espera: se libera sola, sin tocar nada.
        for (var s = 0; s < 18; s++) {
          reloj.ahora = reloj.ahora.add(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
        }
        expect(_habilitado(tester), isTrue);
        await tester.tap(_botonReenviar);
        await tester.pumpAndSettle();
        expect(remote.reenviosPorEmail[_lucia], 1);
        await _cerrarApp(tester);
      },
    );
  });

  group('Registro → Verificación contra el almacén de verdad', () {
    testWidgets('el alta guarda la espera con el correo normalizado; cerrar la app y volver a '
        'abrir la verificación 25 s después retoma la cuenta (35 s) y a los 60 s se puede '
        'reenviar', (tester) async {
      final almacen = AlmacenSeguroEnMemoria();
      BloqueoReenvioVerificacionRepository repo() =>
          BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo());
      final remote = _remotoConAltaPendiente();
      await _montarRegistro(tester, remote: remote, bloqueos: repo());

      await _completarYContinuar(tester, email: '  Lucia.Silva@Correo.COM ');
      await tester.pumpAndSettle();

      final pagina = tester.widget<VerificacionEmailPage>(find.byType(VerificacionEmailPage));
      final delAlta = pagina.envioDelAlta!;
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      expect(_mensajeReenvio, findsNothing);
      final guardado = _guardado(almacen)!;
      expect(guardado.keys, [_lucia], reason: 'el correo se guarda normalizado');
      expect((guardado[_lucia] as Map<String, dynamic>).keys, ['espera'], reason: 'sin candado');
      expect(
        DateTime.parse((guardado[_lucia] as Map)['espera'] as String),
        delAlta.add(const Duration(seconds: 60)).toUtc(),
      );

      // «Se cierra la app»: la espera estaba en el teléfono, no en la pantalla.
      await _cerrarApp(tester);
      final reloj = _Reloj(delAlta.add(const Duration(seconds: 25)));
      await _montar(
        tester,
        remote: remote,
        bloqueos: repo(),
        ahora: reloj.leer,
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await tester.pumpAndSettle();
      expect(find.text('Reenviar en 35s'), findsOneWidget);
      expect(_habilitado(tester), isFalse);

      // Pasan los 35 s: se libera y reenviar manda un solo correo.
      for (var s = 1; s <= 35; s++) {
        reloj.ahora = reloj.ahora.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(_habilitado(tester), isTrue);
      await tester.tap(_botonReenviar);
      await tester.pumpAndSettle();
      expect(remote.reenviosPorEmail[_lucia], 1);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      await _cerrarApp(tester);
    });

    testWidgets('reinicio con el reloj atrasado 3 h: la espera del alta no pasa de 60 s', (
      tester,
    ) async {
      final almacen = AlmacenSeguroEnMemoria();
      BloqueoReenvioVerificacionRepository repo() =>
          BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo());
      final remote = _remotoConAltaPendiente();
      await _montarRegistro(tester, remote: remote, bloqueos: repo());
      await _completarYContinuar(tester);
      await tester.pumpAndSettle();
      final delAlta = tester
          .widget<VerificacionEmailPage>(find.byType(VerificacionEmailPage))
          .envioDelAlta!;
      await _cerrarApp(tester);

      final reloj = _Reloj(delAlta.subtract(const Duration(hours: 3)));
      await _montar(
        tester,
        remote: remote,
        bloqueos: repo(),
        ahora: reloj.leer,
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await tester.pumpAndSettle();
      expect(find.text('Reenviar en 60s'), findsOneWidget);

      reloj.ahora = reloj.ahora.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 61));
      expect(_habilitado(tester), isTrue, reason: 'a los 61 s reales ya se puede reenviar');
      await _cerrarApp(tester);
    });

    testWidgets('con el alta, «Ya verifiqué mi email» sin haber verificado: sigue la cuenta y la '
        'espera queda guardada; ya verificado: entra y el teléfono olvida la espera', (
      tester,
    ) async {
      final almacen = AlmacenSeguroEnMemoria();
      final remote = _remotoConAltaPendiente();
      await _montarRegistro(
        tester,
        remote: remote,
        bloqueos: BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo()),
      );
      await _completarYContinuar(tester);
      await tester.pumpAndSettle();
      expect(find.text('Reenviar en 60s'), findsOneWidget);

      // Todavía sin verificar: el intento falla, la espera sigue y sigue guardada.
      await tester.tap(_yaVerifique);
      await tester.pumpAndSettle();
      // El reloj de la cuenta es el de pantalla (avanzó con las animaciones): sigue contando.
      expect(find.textContaining('Reenviar en '), findsOneWidget);
      expect(_habilitado(tester), isFalse);
      expect(_errorGeneral, findsOneWidget, reason: 'sin verificar el intento avisa que falta');
      expect(_guardado(almacen)?.keys, [_lucia]);

      // Verificó desde el correo: ahora sí entra y el teléfono ya no guarda nada de esa dirección.
      remote.confirmarEmail(_lucia);
      await tester.tap(_yaVerifique);
      await tester.pumpAndSettle();
      expect(find.text('Email verificado'), findsOneWidget);
      expect(_guardado(almacen), isNull, reason: 'la clave se borra: nada vigente que guardar');
      await _cerrarApp(tester);
    });

    testWidgets('con el almacén roto, el alta igual cuenta los 60 s en pantalla y pasados los 60 s '
        'se puede reenviar (sin excepciones)', (tester) async {
      final almacen = AlmacenSeguroEnMemoria()..simularFalla = true;
      final remote = _remotoConAltaPendiente();
      await _montarRegistro(
        tester,
        remote: remote,
        bloqueos: BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo()),
      );
      await _completarYContinuar(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
      expect(_habilitado(tester), isTrue);
      await tester.tap(_botonReenviar);
      await tester.pumpAndSettle();
      expect(remote.reenviosPorEmail[_lucia], 1);
      expect(tester.takeException(), isNull);
      await _cerrarApp(tester);
    });

    testWidgets('doble toque en «Continuar» con el alta en vuelo: una sola cuenta, una sola '
        'pantalla de verificación y una sola espera guardada', (tester) async {
      final almacen = AlmacenSeguroEnMemoria();
      final remote = _remotoConAltaPendiente()..demoraRegistrar = Completer<void>();
      await _montarRegistro(
        tester,
        remote: remote,
        bloqueos: BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo()),
      );
      await _completarYContinuar(tester);
      await tester.pump();
      await tester.tap(find.byKey(const Key('registro_continuar')), warnIfMissed: false);
      await tester.pump();

      remote.demoraRegistrar!.complete();
      await tester.pumpAndSettle();

      expect(remote.llamadasRegistrar, 1);
      expect(find.byType(VerificacionEmailPage), findsOneWidget);
      expect(_guardado(almacen)?.keys, [_lucia]);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      await _cerrarApp(tester);
    });
  });

  group('privacidad: los logs del repositorio no llevan el correo', () {
    test(
      'con un almacén que falla diciendo el correo, ninguna operación lo escribe en el log',
      () async {
        final salida = _Recolector();
        final repo = BloqueoReenvioVerificacionRepositoryImpl(
          _AlmacenQueDelataElCorreo(),
          logger: AppLogger(output: salida),
        );
        final ahora = DateTime.utc(2026, 10, 9, 10);

        await repo.leer(ahora: ahora);
        await repo.guardar(_lucia, ahora.add(_unaHora), ahora: ahora);
        await repo.guardarEspera(_lucia, ahora.add(const Duration(seconds: 60)), ahora: ahora);
        await repo.olvidar(_lucia);
        await repo.olvidarTodo();

        expect(salida.lineas, isNotEmpty, reason: 'las fallas se avisan (con código y tipo)');
        final todo = salida.lineas.join('\n').toLowerCase();
        expect(todo, isNot(contains('lucia')));
        expect(todo, isNot(contains('correo.com')));
        expect(todo, isNot(contains('@')));
      },
    );
  });

  group('medidas de los textos del límite que el resto no mide (A06)', () {
    final casos = <String, ({Duration falta, String cuanto, bool recienRechazado})>{
      'una_hora': (falta: _unaHora, cuanto: 'una hora', recienRechazado: true),
      'cincuenta_y_nueve_minutos': (
        falta: const Duration(minutes: 59),
        cuanto: '59 minutos',
        recienRechazado: false,
      ),
      'un_minuto': (falta: const Duration(seconds: 30), cuanto: '1 minuto', recienRechazado: false),
    };
    for (final MapEntry(key: nombre, value: caso) in casos.entries) {
      for (final tam in const [Size(360, 640), Size(412, 915)]) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('«${caso.cuanto}» en ${tam.width.toInt()}x${tam.height.toInt()} · texto '
              '${escala}x: sin overflow, aviso completo y dentro de la pantalla, cuatro guías', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            await _montar(
              tester,
              remote: _remotoSano(),
              bloqueos: BloqueoReenvioVerificacionEnMemoria({_lucia: _base.add(caso.falta)}),
              ahora: () => _base,
              tam: tam,
              escala: escala,
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text(_textoLimite(caso.cuanto)), findsOneWidget);
            final r = tester.getRect(find.text(_textoLimite(caso.cuanto)));
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(tam.width));
            expect(caso.recienRechazado, caso.cuanto == 'una hora');
            await _recorrer(
              tester,
              'a06_${nombre}_${tam.width.toInt()}x${tam.height.toInt()}_x$escala',
            );
            semantica.dispose();
            await _cerrarApp(tester);
          });
        }
      }
    }

    testWidgets('«Reenviar en 60s» tras el alta en 360x640 con texto 2.0: el botón y la cuenta '
        'entran sin cortarse', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: () => _base,
        envioDelAlta: _base,
        tam: const Size(360, 640),
        escala: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_botonReenviar);
      await tester.pumpAndSettle();
      final r = tester.getRect(find.text('Reenviar en 60s'));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));
      expect(tester.getSize(_botonReenviar).height, greaterThanOrEqualTo(48));
      await _recorrer(tester, 'a01b_360x640_x2');
      semantica.dispose();
      await _cerrarApp(tester);
    });
  });
}
