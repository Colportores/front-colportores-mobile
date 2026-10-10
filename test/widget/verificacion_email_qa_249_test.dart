// QA del PR #323 (#249, HU-AUTH-002, vista 12 «Verificación de correo», artboard A06 «Límite»).
//
// Lo que `verificacion_email_page_test.dart` no ejercita: el A06 con las cuatro guías de
// accesibilidad en los tres tamaños de teléfono y con el texto al 200 %, la semántica del aviso y
// del botón bloqueado, el candado contra el almacén de verdad entre reinicios (dos direcciones,
// mayúsculas y espacios), el reloj movido hacia atrás, el candado junto a la cuenta regresiva y los
// ocho artboards de la vista a 360x640 y 412x915 (sin regresión).
//
// Con el seguimiento #325: el aviso cuenta en minutos y se anuncia una sola vez, el reloj atrasado se
// recorta con la pantalla abierta, y el aviso de éxito de una dirección no queda junto al límite de
// otra (tests que estaban en `skip`).
//
// Las capturas van a `.dart_tool/qa_capturas/` (ignorado por git, nunca se commitean).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/bloqueo_reenvio_verificacion_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/logger_mudo.dart';

const _lucia = 'lucia.silva@correo.com';
const _ana = 'ana@correo.com';
String _textoLimite(String cuanto) => 'Demasiados intentos. Probá nuevamente en $cuanto.';
const _unaHora = Duration(minutes: 60);

final _base = DateTime(2026, 10, 8, 10);

final _aviso = find.byKey(const Key('verificacion_email_limite'));
final _botonReenviar = find.byKey(const Key('verificacion_email_reenviar'));
final _campo = find.byKey(const Key('verificacion_email_campo'));
final _volver = find.byKey(const Key('verificacion_email_volver_login'));
final _mensajeReenvio = find.byKey(const Key('verificacion_email_mensaje_reenvio'));
final _errorGeneral = find.byKey(const Key('verificacion_email_error_general'));

final _llave = GlobalKey();

/// Reloj que el test mueve a mano (adelante o atrás).
final class _Reloj {
  _Reloj(this.ahora);

  DateTime ahora;

  DateTime leer() => ahora;
}

AuthRemoteDataSourceEnMemoria _remotoSano() =>
    AuthRemoteDataSourceEnMemoria(credenciales: const {_lucia: 'Secreto123'});

AuthRemoteDataSourceEnMemoria _remotoConLimite() => _remotoSano()
  ..fallaAlReenviar = const ServidorException(
    status: 429,
    mensaje: 'Demasiados intentos. Esperá unos minutos y volvé a probar.',
  );

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
  File('${dir.path}/249_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
});

/// [VerificacionEmailPage] sobre el tamaño de teléfono [tam], con el texto a [escala].
///
/// El `ProviderScope` va como argumento directo de `pumpWidget` (riverpod_lint).
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
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remote),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        bloqueoReenvioVerificacionRepositoryProvider.overrideWithValue(bloqueos),
      ],
      child: RepaintBoundary(
        key: _llave,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: VerificacionEmailPage(
            email: email,
            password: password,
            estadoInicial: estado,
            envioDelAlta: envioDelAlta,
            ahora: ahora,
          ),
        ),
      ),
    ),
  );
}

/// Saca la pantalla del árbol (como cerrar la app) para volver a montarla desde cero.
Future<void> _cerrarApp(WidgetTester tester) => tester.pumpWidget(const SizedBox());

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Toca «Reenviar» aunque con el texto grande haya quedado debajo de la pantalla.
Future<void> _tocarReenviar(WidgetTester tester) async {
  await tester.ensureVisible(_botonReenviar);
  await tester.pump();
  await tester.tap(_botonReenviar);
}

/// Captura y mide la parte de arriba y la de abajo de la pantalla (con el texto grande no entra
/// todo): tamaño de toque, etiquetas y contraste de lo que se ve en cada una.
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

/// El botón o el texto quedan dentro de la pantalla (sin cortarse a los lados).
void _entraEnLaPantalla(WidgetTester tester, Finder f, Size tam) {
  final r = tester.getRect(f);
  expect(r.left, greaterThanOrEqualTo(0), reason: 'se corta a la izquierda');
  expect(r.right, lessThanOrEqualTo(tam.width), reason: 'se corta a la derecha');
}

void main() {
  const tamanos = [Size(360, 640), Size(390, 844), Size(412, 915)];

  group('A06 · límite — accesibilidad y tamaños', () {
    for (final tam in tamanos) {
      for (final escala in [1.0, 2.0]) {
        final etiqueta = '${tam.width.toInt()}x${tam.height.toInt()} · texto ${escala}x';

        testWidgets('con el candado vigente, en $etiqueta: sin overflow, aviso completo, toques, '
            'etiquetas y contraste', (tester) async {
          final semantica = tester.ensureSemantics();
          await _montar(
            tester,
            remote: _remotoSano(),
            bloqueos: BloqueoReenvioVerificacionEnMemoria({_lucia: _base.add(_unaHora)}),
            ahora: () => _base.add(const Duration(minutes: 4)),
            tam: tam,
            escala: escala,
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(_aviso, findsOneWidget);
          expect(find.text(_textoLimite('56 minutos')), findsOneWidget);
          expect(_habilitado(tester), isFalse);
          _entraEnLaPantalla(tester, find.text(_textoLimite('56 minutos')), tam);
          await _capturar(tester, 'a06_${tam.width.toInt()}x${tam.height.toInt()}_x$escala');
          await _guias(tester);

          // Lo de abajo (botón bloqueado y «Volver al login») se alcanza y se toca bien.
          await tester.ensureVisible(_volver);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getSize(_volver).height, greaterThanOrEqualTo(48));
          _entraEnLaPantalla(tester, _botonReenviar, tam);
          await _capturar(tester, 'a06_abajo_${tam.width.toInt()}x${tam.height.toInt()}_x$escala');
          await _guias(tester);
          semantica.dispose();
        });
      }
    }

    testWidgets('el aviso del límite se lee con su texto (sin región viva: se anuncia aparte, una '
        'sola vez) y el botón bloqueado se lee como botón deshabilitado', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria({_lucia: _base.add(_unaHora)}),
        ahora: () => _base.add(const Duration(minutes: 4)),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(_aviso),
        isSemantics(isLiveRegion: false, label: _textoLimite('56 minutos')),
      );
      expect(
        tester.getSemantics(_botonReenviar),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          label: 'Reenviar email',
        ),
      );
      semantica.dispose();
    });

    testWidgets('dado un 429 en pantalla, cuando aparece el aviso, se anuncia al lector de '
        'pantalla una sola vez y el foco no se pierde', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(
        tester,
        remote: _remotoConLimite(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: () => _base,
      );
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);
      tester.takeAnnouncements();

      await tester.tap(_botonReenviar);
      await tester.pumpAndSettle();

      expect(_aviso, findsOneWidget);
      expect(tester.takeAnnouncements().map((a) => a.message), [_textoLimite('una hora')]);
      expect(
        tester.getSemantics(_aviso),
        isSemantics(isLiveRegion: false, label: _textoLimite('una hora')),
      );
      // Sigue habiendo una salida a mano: «Volver al login» (y «Ya verifiqué mi email»).
      expect(_volver, findsOneWidget);
      expect(find.byKey(const Key('verificacion_email_ya_verifique')), findsOneWidget);
      semantica.dispose();
    });
  });

  group('el candado contra el almacén de verdad, entre reinicios', () {
    testWidgets(
      'dos direcciones, mayúsculas y espacios: cada candado es de su dirección, sobrevive '
      'al reinicio y vence a su hora',
      (tester) async {
        final almacen = AlmacenSeguroEnMemoria();
        BloqueoReenvioVerificacionRepository repo() =>
            BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo());
        final reloj = _Reloj(_base);

        // 1) Lucía recibe el 429 de Supabase.
        await _montar(tester, remote: _remotoConLimite(), bloqueos: repo(), ahora: reloj.leer);
        await tester.pumpAndSettle();
        await tester.tap(_botonReenviar);
        await tester.pumpAndSettle();
        expect(_aviso, findsOneWidget);

        // 2) Se cierra la app y la abre Ana (otra cuenta en el mismo teléfono): libre, y reenvía.
        await _cerrarApp(tester);
        reloj.ahora = _base.add(const Duration(minutes: 10));
        final remotoAna = AuthRemoteDataSourceEnMemoria(credenciales: const {_ana: 'Secreto123'});
        await _montar(tester, remote: remotoAna, bloqueos: repo(), ahora: reloj.leer, email: _ana);
        await tester.pumpAndSettle();
        expect(_aviso, findsNothing, reason: 'el candado de Lucía no bloquea a Ana');
        expect(_habilitado(tester), isTrue);
        await tester.tap(_botonReenviar);
        await tester.pumpAndSettle();
        expect(remotoAna.reenviosPorEmail[_ana], 1);
        expect(_mensajeReenvio, findsOneWidget);

        // 3) Vuelve Lucía, ahora escrita con mayúsculas y espacios: sigue bloqueada.
        await _cerrarApp(tester);
        reloj.ahora = _base.add(const Duration(minutes: 20));
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: repo(),
          ahora: reloj.leer,
          email: '  Lucia.SILVA@Correo.COM ',
        );
        await tester.pumpAndSettle();
        expect(_aviso, findsOneWidget);
        expect(_habilitado(tester), isFalse);

        // 4) Ana también recibe un 429 (a las 10:20).
        await _cerrarApp(tester);
        await _montar(
          tester,
          remote: AuthRemoteDataSourceEnMemoria(credenciales: const {_ana: 'Secreto123'})
            ..fallaAlReenviar = const ServidorException(status: 429),
          bloqueos: repo(),
          ahora: reloj.leer,
          email: _ana,
        );
        await tester.pumpAndSettle();
        await tester.tap(_botonReenviar);
        await tester.pumpAndSettle();
        expect(_aviso, findsOneWidget);

        // El almacén tiene un candado por dirección, con la clave normalizada.
        final guardado = jsonDecode(almacen.contenido[ClaveSegura.bloqueoReenvioVerificacion]!);
        expect((guardado as Map<String, dynamic>).keys.toSet(), {_lucia, _ana});

        // 5) A las 11:10 (70 min después de Lucía, 50 de Ana): Lucía libre, Ana todavía no.
        await _cerrarApp(tester);
        reloj.ahora = _base.add(const Duration(minutes: 70));
        await _montar(tester, remote: _remotoSano(), bloqueos: repo(), ahora: reloj.leer);
        await tester.pumpAndSettle();
        expect(_aviso, findsNothing);
        expect(_habilitado(tester), isTrue);

        await _cerrarApp(tester);
        await _montar(
          tester,
          remote: AuthRemoteDataSourceEnMemoria(credenciales: const {_ana: 'Secreto123'}),
          bloqueos: repo(),
          ahora: reloj.leer,
          email: _ana,
        );
        await tester.pumpAndSettle();
        expect(_aviso, findsOneWidget);
        expect(_habilitado(tester), isFalse);

        // 6) Pasada la hora de Ana, con la pantalla abierta, se libera sola.
        reloj.ahora = _base.add(const Duration(minutes: 81));
        await tester.pump(const Duration(minutes: 11));
        expect(_aviso, findsNothing);
        expect(_habilitado(tester), isTrue);
        await _cerrarApp(tester);
      },
    );

    testWidgets('sin correo conocido (A04 con el campo), el candado guardado de una dirección '
        'sobrevive al reinicio y el de otra no estorba', (tester) async {
      final almacen = AlmacenSeguroEnMemoria();
      final guardador = BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo());
      await guardador.guardar(_ana, _base.add(_unaHora), ahora: _base);

      await _montar(
        tester,
        remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}),
        bloqueos: BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo()),
        ahora: () => _base.add(const Duration(minutes: 30)),
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);

      await tester.enterText(_campo, ' ANA@correo.com ');
      await tester.pump();
      expect(_aviso, findsOneWidget);
      expect(_habilitado(tester), isFalse);

      await tester.enterText(_campo, 'luis@correo.com');
      await tester.pump();
      expect(_aviso, findsNothing);
      expect(_habilitado(tester), isTrue);
      await _cerrarApp(tester);
    });
  });

  group('cambiar el reloj del teléfono', () {
    testWidgets('con la app reiniciada y el reloj atrasado 3 h, el candado no pasa de una hora '
        'desde que se lo lee', (tester) async {
      final almacen = AlmacenSeguroEnMemoria();
      await BloqueoReenvioVerificacionRepositoryImpl(
        almacen,
        logger: loggerMudo(),
      ).guardar(_lucia, _base.add(_unaHora), ahora: _base);
      final reloj = _Reloj(_base.subtract(const Duration(hours: 3)));

      await _montar(
        tester,
        remote: _remotoSano(),
        bloqueos: BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo()),
        ahora: reloj.leer,
      );
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget);

      reloj.ahora = reloj.ahora.add(const Duration(minutes: 61));
      await tester.pump(const Duration(minutes: 61));

      expect(_aviso, findsNothing);
      expect(_habilitado(tester), isTrue);
      await _cerrarApp(tester);
    });

    // QA #249, arreglado en #325: con el reloj atrasado y la pantalla abierta, al volver a la app el
    // candado se recorta a ahora+60 min (antes duraba hasta que el reloj movido llegaba al
    // vencimiento viejo).
    testWidgets('con la pantalla abierta y el reloj atrasado 3 h, el candado sigue venciendo una '
        'hora después del rechazo', (tester) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoConLimite(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await tester.pumpAndSettle();
      await tester.tap(_botonReenviar);
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget);

      // La persona atrasa el reloj 3 h y vuelve a la app.
      reloj.ahora = _base.subtract(const Duration(hours: 3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_aviso, findsOneWidget);

      // Pasa una hora real (el reloj, movido, avanza lo mismo).
      reloj.ahora = reloj.ahora.add(const Duration(minutes: 61));
      await tester.pump(const Duration(minutes: 61));

      expect(_aviso, findsNothing, reason: 'pasó más de una hora desde el rechazo');
      expect(_habilitado(tester), isTrue);
      await _cerrarApp(tester);
    });

    testWidgets('con el reloj adelantado 2 h al volver a la app, el candado ya no está', (
      tester,
    ) async {
      final reloj = _Reloj(_base);
      await _montar(
        tester,
        remote: _remotoConLimite(),
        bloqueos: BloqueoReenvioVerificacionEnMemoria(),
        ahora: reloj.leer,
      );
      await tester.pumpAndSettle();
      await tester.tap(_botonReenviar);
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget);

      reloj.ahora = _base.add(const Duration(hours: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(_aviso, findsNothing);
      expect(_habilitado(tester), isTrue);
      await _cerrarApp(tester);
    });
  });

  group('el candado y la cuenta regresiva de 60 s son de cada dirección (sin correo conocido)', () {
    testWidgets('reenviar a una dirección libre y pasar a una bloqueada: se ve el aviso del límite '
        'y el botón con candado, sin la cuenta regresiva de la otra; al volver a la primera sigue '
        'su cuenta; sin overflow a 360x640 y texto 2x', (tester) async {
      final semantica = tester.ensureSemantics();
      const tam = Size(360, 640);
      final reloj = _Reloj(_base.add(const Duration(minutes: 5)));
      await _montar(
        tester,
        remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}),
        bloqueos: BloqueoReenvioVerificacionEnMemoria({_ana: _base.add(_unaHora)}),
        ahora: reloj.leer,
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.expirado,
        tam: tam,
        escala: 2,
      );
      await tester.pumpAndSettle();

      await tester.enterText(_campo, 'luis@correo.com');
      await _tocarReenviar(tester);
      await tester.pumpAndSettle();
      expect(_mensajeReenvio, findsOneWidget);
      expect(find.text('Reenviar en 60s'), findsOneWidget);

      reloj.ahora = reloj.ahora.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(_campo, _ana);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_aviso, findsOneWidget);
      expect(_habilitado(tester), isFalse);
      expect(_mensajeReenvio, findsNothing);
      expect(find.text('Reenviar email de verificación'), findsOneWidget);
      expect(find.textContaining('Reenviar en'), findsNothing, reason: 'la espera es de Luis');
      await _recorrer(tester, 'a06_tras_reenviar_a_otra_360x640_x2');
      expect(tester.takeException(), isNull);

      // Vuelve a la dirección a la que salió el correo: su cuenta sigue donde iba.
      await tester.enterText(_campo, 'luis@correo.com');
      await tester.pump();
      expect(_aviso, findsNothing);
      expect(find.text('Reenviar en 59s'), findsOneWidget);
      expect(_habilitado(tester), isFalse);
      semantica.dispose();
      await _cerrarApp(tester);
    });

    // QA #249, arreglado en #325: en el modo sin correo, «Te reenviamos el correo…» (de la dirección
    // enviada) ya no queda junto al aviso del límite de la otra dirección que se ve ahora.
    testWidgets('el aviso «Te reenviamos el correo» es de la dirección a la que se envió: al pasar '
        'a otra dirección bloqueada no queda junto al aviso del límite', (tester) async {
      await _montar(
        tester,
        remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}),
        bloqueos: BloqueoReenvioVerificacionEnMemoria({_ana: _base.add(_unaHora)}),
        ahora: () => _base.add(const Duration(minutes: 5)),
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await tester.pumpAndSettle();
      await tester.enterText(_campo, 'luis@correo.com');
      await _tocarReenviar(tester);
      await tester.pumpAndSettle();
      expect(_mensajeReenvio, findsOneWidget);

      await tester.enterText(_campo, _ana);
      await tester.pump();

      expect(_aviso, findsOneWidget);
      expect(
        _mensajeReenvio,
        findsNothing,
        reason: 'dice «te reenviamos el correo» mientras se ve una dirección bloqueada',
      );
      await _cerrarApp(tester);
    });
  });

  group('sin regresión — los artboards de la vista 12 a 360x640 y 412x915', () {
    final artboards = <String, Future<void> Function(WidgetTester, Size, double)>{
      'a01_pendiente': (tester, tam, escala) async {
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: () => _base,
          tam: tam,
          escala: escala,
        );
        await tester.pumpAndSettle();
        expect(find.text('Verificá tu cuenta'), findsOneWidget);
        expect(_aviso, findsNothing);
        expect(_habilitado(tester), isTrue);
      },
      'a01b_tras_el_alta': (tester, tam, escala) async {
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: () => _base,
          envioDelAlta: _base.subtract(const Duration(seconds: 12)),
          tam: tam,
          escala: escala,
        );
        await tester.pumpAndSettle();
        expect(find.text('Verificá tu cuenta'), findsOneWidget);
        expect(find.text('Te enviamos un correo a'), findsOneWidget);
        expect(find.text('Reenviar en 48s'), findsOneWidget);
        expect(find.byKey(const Key('verificacion_email_progreso')), findsOneWidget);
        expect(_mensajeReenvio, findsNothing, reason: 'no hubo reenvío: el correo salió del alta');
        expect(_aviso, findsNothing);
      },
      'a02_reenviado': (tester, tam, escala) async {
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: () => _base,
          tam: tam,
          escala: escala,
        );
        await tester.pumpAndSettle();
        await _tocarReenviar(tester);
        await tester.pumpAndSettle();
        expect(_mensajeReenvio, findsOneWidget);
        expect(find.text('Te reenviamos el correo. Puede tardar unos minutos.'), findsOneWidget);
        expect(find.text('Reenviar en 60s'), findsOneWidget);
        expect(_aviso, findsNothing);
      },
      'a03_cuenta_regresiva': (tester, tam, escala) async {
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: () => _base,
          tam: tam,
          escala: escala,
        );
        await tester.pumpAndSettle();
        await _tocarReenviar(tester);
        await tester.pump();
        await tester.pump(const Duration(seconds: 18));
        expect(find.text('Reenviar en 42s'), findsOneWidget);
        expect(find.byKey(const Key('verificacion_email_progreso')), findsOneWidget);
      },
      'a04_expirado': (tester, tam, escala) async {
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: () => _base,
          password: null,
          estado: EstadoVerificacionEmail.expirado,
          tam: tam,
          escala: escala,
        );
        await tester.pumpAndSettle();
        expect(find.text('El enlace expiró'), findsOneWidget);
        expect(find.text('Reenviar email de verificación'), findsOneWidget);
      },
      'a04b_expirado_sin_correo': (tester, tam, escala) async {
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: () => _base,
          email: '',
          password: null,
          estado: EstadoVerificacionEmail.expirado,
          tam: tam,
          escala: escala,
        );
        await tester.pumpAndSettle();
        expect(_campo, findsOneWidget);
      },
      'a05_ya_verificado': (tester, tam, escala) async {
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: () => _base,
          estado: EstadoVerificacionEmail.yaVerificado,
          tam: tam,
          escala: escala,
        );
        await tester.pumpAndSettle();
        expect(find.text('Tu email ya está verificado'), findsOneWidget);
      },
      'a07_verificado': (tester, tam, escala) async {
        await _montar(
          tester,
          remote: _remotoSano(),
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: () => _base,
          estado: EstadoVerificacionEmail.verificado,
          tam: tam,
          escala: escala,
        );
        await tester.pumpAndSettle();
        expect(find.text('Email verificado'), findsOneWidget);
        expect(find.text('Continuar'), findsOneWidget);
      },
      'a08_sin_conexion': (tester, tam, escala) async {
        await _montar(
          tester,
          remote: _remotoSano()..simularSinConexion = true,
          bloqueos: BloqueoReenvioVerificacionEnMemoria(),
          ahora: () => _base,
          tam: tam,
          escala: escala,
        );
        await tester.pumpAndSettle();
        await _tocarReenviar(tester);
        await tester.pumpAndSettle();
        expect(_errorGeneral, findsOneWidget);
        expect(
          find.text('Necesitás conexión para reenviar el email. Conectate y probá de nuevo.'),
          findsOneWidget,
        );
        expect(_habilitado(tester), isTrue, reason: 'el botón vuelve a quedar a mano');
        expect(_aviso, findsNothing, reason: 'un corte de red no es un límite: no bloquea');
      },
    };

    for (final MapEntry(key: nombre, value: preparar) in artboards.entries) {
      for (final tam in const [Size(360, 640), Size(412, 915)]) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('$nombre en ${tam.width.toInt()}x${tam.height.toInt()} · texto ${escala}x: '
              'sin overflow, toques, etiquetas y contraste', (tester) async {
            final semantica = tester.ensureSemantics();
            await preparar(tester, tam, escala);

            expect(tester.takeException(), isNull);
            await _recorrer(
              tester,
              '${nombre}_${tam.width.toInt()}x${tam.height.toInt()}_x$escala',
            );
            semantica.dispose();
            await _cerrarApp(tester);
          });
        }
      }
    }
  });
}
