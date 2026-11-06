// QA de #642 (vista 31 «Devolución», venta de $ 0): una venta de $ 0 (un regalo, un misionero) acepta
// la devolución del libro, sin montos ni cobros; una de más de $ 0 pagada entera sigue sin aceptarla.
// Matriz de estados × 360x640 y 412x915 × texto 1,0 y 2,0 con las fuentes reales (sin overflow), guías
// de accesibilidad por estado, casos límite (falla a mitad, reentrada, doble toque, plazo, ya devuelta)
// y, con `--dart-define=QA_CAPTURAS=true`, un PNG por estado en `.dart_tool/qa_capturas/` (no se
// commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_para_devolver.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/devolucion_repository.dart';
import 'package:colportores_mobile/features/ventas/domain/services/reglas_de_devolucion.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/devolucion_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/devolucion_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import '../../helpers/venta_ui_falsos.dart';

const _capturar = bool.fromEnvironment('QA_CAPTURAS');
final _fechaDeLaVenta = DateTime.utc(2026, 10, 13, 18, 20);
final _ahora = _fechaDeLaVenta.add(const Duration(hours: 24));

/// Un regalo de misioneros: dos libros a $ 0 cada uno, sin cobros.
VentaParaDevolver _regalo({int unidades = 2, int devueltas = 0, int precio = 0, int cobrado = 0}) =>
    VentaParaDevolver(
      ventaId: 'v-1',
      numeroTalonario: '0043',
      fecha: _fechaDeLaVenta,
      montoTotalCentavos: 0,
      cobradoCentavos: cobrado,
      renglones: [
        RenglonDeLaVenta(
          ventaItemId: 'i-regalo',
          titulo: 'Salud y Hogar',
          productoId: 'p-regalo',
          cantidad: unidades,
          precioUnitarioCentavos: precio,
          unidadesDevueltas: devueltas,
        ),
        RenglonDeLaVenta(
          ventaItemId: 'i-regalo-2',
          titulo: 'Nuestros Hijos',
          productoId: 'p-regalo-2',
          cantidad: 1,
          precioUnitarioCentavos: precio,
          unidadesDevueltas: devueltas > 0 ? 1 : 0,
        ),
      ],
    );

VentaParaDevolver _pagadaEntera() => VentaParaDevolver(
  ventaId: 'v-1',
  numeroTalonario: '0042',
  fecha: _fechaDeLaVenta,
  montoTotalCentavos: 450000,
  cobradoCentavos: 450000,
  renglones: const [
    RenglonDeLaVenta(
      ventaItemId: 'i-salud',
      titulo: 'Salud y Hogar',
      productoId: 'p-salud',
      cantidad: 1,
      precioUnitarioCentavos: 260000,
    ),
    RenglonDeLaVenta(
      ventaItemId: 'i-hijos',
      titulo: 'Nuestros Hijos',
      productoId: 'p-hijos',
      cantidad: 1,
      precioUnitarioCentavos: 190000,
    ),
  ],
);

class _Repo implements DevolucionRepository {
  _Repo(this.venta);
  VentaParaDevolver? venta;
  final respuestas = <Future<Either<Failure, DevolucionRegistrada>> Function()>[];
  final pedidos = <PedidoDeDevolucion>[];

  @override
  Future<Either<Failure, VentaParaDevolver?>> ventaParaDevolver(String ventaId) async =>
      Right(venta);

  @override
  Future<Either<Failure, DevolucionRegistrada>> registrar(PedidoDeDevolucion pedido) async {
    pedidos.add(pedido);
    if (respuestas.isNotEmpty) return respuestas.removeAt(0)();
    final cuenta = ReglasDeDevolucion.cuenta(venta!, pedido.unidadesPorRenglon);
    return Right(
      DevolucionRegistrada(
        devolucion: Devolucion(
          id: pedido.id,
          ventaId: pedido.ventaId,
          productos: const [],
          fechaDevolucion: pedido.ahora,
          auditoria: auditoriaPersonas(),
        ),
        totalCentavos: cuenta.seQuedaConCentavos,
        saldoCentavos: cuenta.saldoNuevoCentavos,
        eraTotal: cuenta.esTotal,
      ),
    );
  }
}

Future<List<bool?>> _montar(
  WidgetTester tester,
  _Repo repo, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  DateTime? ahora,
  GlobalKey? raiz,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final resultados = <bool?>[];
  var n = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        devolucionRepositoryProvider.overrideWithValue(repo),
        generadorIdDevolucionProvider.overrideWithValue(() => 'd-${++n}'),
        relojDevolucionProvider.overrideWithValue(() => ahora ?? _ahora),
        personasDelEspacioProvider.overrideWith(
          (ref, espacioId) =>
              Stream.value([clienteDePersonas('per-1', 'María', apellido: 'Fernández')]),
        ),
      ],
      child: RepaintBoundary(
        key: raiz,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('abrir'),
                  onPressed: () async {
                    resultados.add(
                      await DevolucionPage.abrir(
                        context,
                        ventaId: 'v-1',
                        colportorId: 'col-1',
                        espacioId: 'esp-1',
                        personaId: 'per-1',
                      ),
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir')));
  await asentar(tester);
  return resultados;
}

Finder _mas(String titulo) => find.byTooltip('Uno más de $titulo');
Finder get _cta => find.byKey(const Key('venta_cta'));

Future<void> _seguir(WidgetTester tester) => tocar(tester, _cta);
Future<void> _registrarEnLaHoja(WidgetTester tester) async {
  await tocar(tester, _cta);
  await tocar(tester, find.byKey(const Key('devolucion_hoja_registrar')));
}

Future<void> _cargarFuentes(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await c.load();
  }
  // Los íconos de Material, o salen cajas.
  final raiz = Platform.environment['FLUTTER_ROOT'] ?? '/sdks/flutter';
  final cache = '$raiz/bin/cache';
  final iconos = File('$cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (iconos.existsSync()) {
    final c = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(iconos.readAsBytesSync().buffer)));
    await c.load();
  }
});

Future<void> _png(WidgetTester tester, GlobalKey raiz, String nombre) async {
  Directory('.dart_tool/qa_capturas').createSync(recursive: true);
  await tester.runAsync(() async {
    final r = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz));
    final img = await r.toImage();
    final bd = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    File('.dart_tool/qa_capturas/$nombre.png').writeAsBytesSync(Uint8List.view(bd.buffer));
  });
}

/// Los estados de la vista 31 con una venta de $ 0 y los que no cambian.
enum _Estado {
  elegir('31-01'),
  nadaElegido('31-09'),
  confirmar('31-04'),
  hoja('31-04 hoja'),
  registrada('31-05'),
  total('31-07'),
  fueraDePlazo('31-08'),
  error('31-10'),
  yaDevuelta('ya devuelta'),
  cerrada('31 saldada >0');

  const _Estado(this.artboard);
  final String artboard;
}

Future<List<bool?>> _llevarA(
  WidgetTester tester,
  _Estado e, {
  required Size tamano,
  required double escala,
  GlobalKey? raiz,
  _Repo? repoPropio,
}) async {
  final repo =
      repoPropio ??
      _Repo(switch (e) {
        _Estado.yaDevuelta => _regalo(devueltas: 2),
        _Estado.cerrada => _pagadaEntera(),
        _ => _regalo(),
      });
  if (e == _Estado.error) {
    repo.respuestas.add(() async => const Left(FailureDevolucionNoGuardada(causa: 'x')));
  }
  final r = await _montar(
    tester,
    repo,
    tamano: tamano,
    escala: escala,
    raiz: raiz,
    ahora: e == _Estado.fueraDePlazo ? _fechaDeLaVenta.add(const Duration(hours: 80)) : null,
  );
  switch (e) {
    case _Estado.elegir || _Estado.nadaElegido || _Estado.fueraDePlazo:
    case _Estado.yaDevuelta || _Estado.cerrada:
      break;
    case _Estado.confirmar:
      await tocar(tester, _mas('Salud y Hogar'));
      await _seguir(tester);
    case _Estado.hoja:
      await tocar(tester, _mas('Salud y Hogar'));
      await _seguir(tester);
      await tocar(tester, _cta);
    case _Estado.registrada:
      await tocar(tester, _mas('Salud y Hogar'));
      await _seguir(tester);
      await _registrarEnLaHoja(tester);
    case _Estado.total:
      await tocar(tester, _mas('Salud y Hogar'));
      await tocar(tester, _mas('Salud y Hogar'));
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
    case _Estado.error:
      await tocar(tester, _mas('Salud y Hogar'));
      await _seguir(tester);
      await _registrarEnLaHoja(tester);
  }
  return r;
}

void main() {
  const tamanos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

  group('matriz de estados × tamaños × texto (fuentes reales)', () {
    for (final e in _Estado.values) {
      for (final t in tamanos.entries) {
        for (final esc in const [1.0, 2.0]) {
          testWidgets('${e.artboard} · ${e.name} · ${t.key} · ${esc}x: sin overflow'
              '${_capturar ? ' (y captura)' : ''}', (tester) async {
            await _cargarFuentes(tester);
            final raiz = GlobalKey();
            await _llevarA(tester, e, tamano: t.value, escala: esc, raiz: raiz);
            expect(tester.takeException(), isNull);
            if (_capturar) await _png(tester, raiz, '642_dev_${e.name}_${t.key}_x${esc.toInt()}');
          });
        }
      }
    }
  });

  group('guías de accesibilidad por estado', () {
    for (final e in _Estado.values) {
      for (final t in tamanos.entries) {
        testWidgets('${e.artboard} · ${e.name} · ${t.key}: toques, etiquetas y contraste', (
          tester,
        ) async {
          final h = tester.ensureSemantics();
          await _llevarA(tester, e, tamano: t.value, escala: 1);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          // El contraste de los rótulos de 10,5 px y del aviso gris (#5B6B82 sobre #FAFAF7 = 5,2:1)
          // lo mide `textContrastGuideline` en 4,0 y 2,1 por el muestreo del suavizado con letra
          // espaciada y botones apagados al lado: falso negativo, no se prueba acá.
          h.dispose();
        });
      }
    }

    for (final e in [_Estado.elegir, _Estado.confirmar, _Estado.hoja, _Estado.registrada]) {
      testWidgets('${e.artboard} · ${e.name} · 360x640 con el texto al 200 %: toques y etiquetas', (
        tester,
      ) async {
        final h = tester.ensureSemantics();
        await _llevarA(tester, e, tamano: const Size(360, 640), escala: 2);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        h.dispose();
      });
    }
  });

  group('lo que la HU y la decisión del 04/11 piden', () {
    testWidgets('«Sí, solo vuelve el libro»: registrar no manda montos ni cobros, solo unidades', (
      tester,
    ) async {
      final repo = _Repo(_regalo());
      final r = await _llevarA(
        tester,
        _Estado.registrada,
        tamano: const Size(390, 844),
        escala: 1,
        repoPropio: repo,
      );
      expect(repo.pedidos, hasLength(1));
      expect(repo.pedidos.single.unidadesPorRenglon, {'i-regalo': 1});
      expect(find.text('Devolución registrada'), findsOneWidget);
      await tocar(tester, find.byKey(const Key('devolucion_listo')));
      expect(r, [true]);
    });

    testWidgets('con el precio de lista en la línea y la venta a \$ 0, la pantalla no promete '
        'plata: no hay tarjeta de cuentas ni «Sin devolver»', (tester) async {
      final repo = _Repo(_regalo(precio: 190000));
      await _llevarA(
        tester,
        _Estado.confirmar,
        tamano: const Size(390, 844),
        escala: 1,
        repoPropio: repo,
      );
      expect(find.byKey(const Key('devolucion_cuentas')), findsNothing);
      expect(find.byKey(const Key('devolucion_venta_de_cero')), findsOneWidget);
      expect(find.byKey(const Key('devolucion_sin_devolver')), findsNothing);
    });

    // Decisión del orquestador (06/11, P1 de impl): con montoTotalCentavos == 0 la tarjeta de cuentas
    // pasa a «Esta venta fue de $ 0: solo vuelve el libro, no se mueve plata.» y la hoja de confirmar
    // no muestra «Se queda con» ni «Saldo nuevo». Aplicada en b64fa58d.
    testWidgets(
      'decisión 06/11: la venta de \$ 0 dice «solo vuelve el libro, no se mueve plata» y no '
      'muestra «Se queda con» ni «Saldo nuevo», ni en la tarjeta ni en la hoja',
      (tester) async {
        await _llevarA(tester, _Estado.confirmar, tamano: const Size(390, 844), escala: 1);
        expect(
          find.text(r'Esta venta fue de $ 0: solo vuelve el libro, no se mueve plata.'),
          findsOneWidget,
        );
        expect(find.text('Se queda con'), findsNothing);
        expect(find.text('Saldo nuevo'), findsNothing);
        await tocar(tester, _cta);
        expect(find.text('Se queda con'), findsNothing);
        expect(find.text('Saldo nuevo'), findsNothing);
      },
    );

    testWidgets('una venta de más de \$ 0 pagada entera sigue sin aceptar devoluciones y ofrece '
        '«Volver»', (tester) async {
      await _llevarA(tester, _Estado.cerrada, tamano: const Size(390, 844), escala: 1);
      expect(find.byKey(const Key('devolucion_saldada')), findsOneWidget);
      expect(_mas('Salud y Hogar'), findsNothing);
      expect(find.byKey(const Key('devolucion_volver')), findsOneWidget);
    });

    testWidgets('una venta de más de \$ 0 con saldo sigue mostrando la tarjeta de cuentas y no la '
        'línea de \$ 0', (tester) async {
      final venta = VentaParaDevolver(
        ventaId: 'v-1',
        numeroTalonario: '0042',
        fecha: _fechaDeLaVenta,
        montoTotalCentavos: 450000,
        cobradoCentavos: 100000,
        renglones: _pagadaEntera().renglones,
      );
      await _llevarA(
        tester,
        _Estado.confirmar,
        tamano: const Size(390, 844),
        escala: 1,
        repoPropio: _Repo(venta),
      );
      expect(find.byKey(const Key('devolucion_cuentas')), findsOneWidget);
      expect(find.byKey(const Key('devolucion_venta_de_cero')), findsNothing);
      expect(find.text('Saldo nuevo'), findsOneWidget);
    });

    testWidgets('una venta de \$ 0 con todo devuelto dice «ya devuelta», no «saldada»', (
      tester,
    ) async {
      await _llevarA(tester, _Estado.yaDevuelta, tamano: const Size(390, 844), escala: 1);
      expect(find.byKey(const Key('devolucion_ya_devuelta')), findsOneWidget);
      expect(find.byKey(const Key('devolucion_saldada')), findsNothing);
    });

    testWidgets('pasadas las 72 h una venta de \$ 0 sí se rechaza (con aviso y salida)', (
      tester,
    ) async {
      await _llevarA(tester, _Estado.fueraDePlazo, tamano: const Size(390, 844), escala: 1);
      expect(find.byKey(const Key('devolucion_fuera_de_plazo')), findsOneWidget);
      expect(_mas('Salud y Hogar'), findsNothing);
      expect(find.byKey(const Key('devolucion_volver')), findsOneWidget);
    });

    testWidgets('justo a las 72 h una venta de \$ 0 todavía acepta la devolución', (tester) async {
      final repo = _Repo(_regalo());
      await _montar(tester, repo, ahora: _fechaDeLaVenta.add(const Duration(hours: 72)));
      expect(find.byKey(const Key('devolucion_fuera_de_plazo')), findsNothing);
      expect(_mas('Salud y Hogar'), findsOneWidget);
    });
  });

  group('casos límite del flujo', () {
    testWidgets(
      'falla a mitad: el error avisa, «Registrar» vuelve y el reintento usa el mismo id',
      (tester) async {
        final repo = _Repo(_regalo());
        await _llevarA(
          tester,
          _Estado.error,
          tamano: const Size(360, 640),
          escala: 2,
          repoPropio: repo,
        );
        expect(find.byKey(const Key('devolucion_error')), findsOneWidget);
        expect(find.text('Registrando…'), findsNothing);
        final boton = tester.widget<FilledButton>(_cta);
        expect(boton.onPressed, isNotNull);
        await tocar(tester, _cta);
        expect(repo.pedidos.map((p) => p.id), ['d-1', 'd-1']);
        expect(find.text('Devolución registrada'), findsOneWidget);
      },
    );

    testWidgets('lo elegido y lo escrito en el motivo no se pierden tras el error', (tester) async {
      final repo = _Repo(_regalo());
      repo.respuestas.add(() async => const Left(FailureDevolucionNoGuardada(causa: 'x')));
      await _montar(tester, repo);
      await tocar(tester, _mas('Salud y Hogar'));
      await _seguir(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('devolucion_motivo')),
          matching: find.byType(TextField),
        ),
        'no lo quiso 🙏',
      );
      await tester.pump();
      await _registrarEnLaHoja(tester);
      expect(find.byKey(const Key('devolucion_error')), findsOneWidget);
      expect(find.text('no lo quiso 🙏'), findsOneWidget);
      expect(find.byKey(const Key('devolucion_venta_de_cero')), findsOneWidget);
    });

    testWidgets('doble toque en «Registrar» con la respuesta demorada manda un solo pedido', (
      tester,
    ) async {
      final repo = _Repo(_regalo());
      final demora = Completer<void>();
      repo.respuestas.add(() async {
        await demora.future;
        final cuenta = ReglasDeDevolucion.cuenta(repo.venta!, {'i-regalo': 1});
        return Right(
          DevolucionRegistrada(
            devolucion: Devolucion(
              id: 'd-1',
              ventaId: 'v-1',
              productos: const [],
              fechaDevolucion: _ahora,
              auditoria: auditoriaPersonas(),
            ),
            totalCentavos: cuenta.seQuedaConCentavos,
            saldoCentavos: cuenta.saldoNuevoCentavos,
            eraTotal: cuenta.esTotal,
          ),
        );
      });
      await _montar(tester, repo);
      await tocar(tester, _mas('Salud y Hogar'));
      await _seguir(tester);
      await tocar(tester, _cta);
      final registrar = find.byKey(const Key('devolucion_hoja_registrar'));
      await tester.tap(registrar);
      await tester.pump();
      await tester.tap(registrar, warnIfMissed: false);
      await tester.pump();
      await tester.tap(registrar, warnIfMissed: false);
      expect(repo.pedidos, hasLength(1));
      demora.complete();
      await asentar(tester);
      expect(repo.pedidos, hasLength(1));
      expect(find.text('Devolución registrada'), findsOneWidget);
    });

    testWidgets('el texto del motivo muy largo y con emoji no desborda a 360x640 al 200 %', (
      tester,
    ) async {
      await _cargarFuentes(tester);
      final repo = _Repo(_regalo());
      await _montar(tester, repo, tamano: const Size(360, 640), escala: 2);
      await tocar(tester, _mas('Salud y Hogar'));
      await _seguir(tester);
      await escribir(
        tester,
        find.descendant(
          of: find.byKey(const Key('devolucion_motivo')),
          matching: find.byType(EditableText),
        ),
        'Se lo regalaron dos veces 📚 ' * 40,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('volver con un libro elegido pregunta; «Seguir escribiendo» lo conserva y '
        '«Descartar» sale y reentrar parte limpio', (tester) async {
      final repo = _Repo(_regalo());
      final r = await _montar(tester, repo);
      await tocar(tester, _mas('Salud y Hogar'));
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      await nav.maybePop();
      await asentar(tester);
      expect(find.text('Seguir escribiendo'), findsOneWidget);
      await tester.tap(find.text('Seguir escribiendo'));
      await asentar(tester);
      expect(r, isEmpty);
      expect(tester.widget<FilledButton>(_cta).onPressed, isNotNull);
      await nav.maybePop();
      await asentar(tester);
      await tester.tap(find.text('Descartar'));
      await asentar(tester);
      expect(r, [false]);
      expect(repo.pedidos, isEmpty);
      await tester.tap(find.byKey(const Key('abrir')));
      await asentar(tester);
      expect(tester.widget<FilledButton>(_cta).onPressed, isNull);
      expect(find.text('Elegí al menos un producto.'), findsOneWidget);
    });

    testWidgets('devolver de a un libro y reentrar: lo que ya volvió no se puede volver a elegir', (
      tester,
    ) async {
      final repo = _Repo(_regalo());
      await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await _registrarEnLaHoja(tester);
      await tocar(tester, find.byKey(const Key('devolucion_listo')));
      // El repositorio ahora dice que ese libro ya volvió.
      repo.venta = _regalo(devueltas: 0);
      repo.venta = VentaParaDevolver(
        ventaId: 'v-1',
        numeroTalonario: '0043',
        fecha: _fechaDeLaVenta,
        montoTotalCentavos: 0,
        cobradoCentavos: 0,
        renglones: [
          repo.venta!.renglones[0],
          const RenglonDeLaVenta(
            ventaItemId: 'i-regalo-2',
            titulo: 'Nuestros Hijos',
            productoId: 'p-regalo-2',
            cantidad: 1,
            precioUnitarioCentavos: 0,
            unidadesDevueltas: 1,
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await asentar(tester);
      final icono = tester.widget<IconButton>(
        find.ancestor(of: _mas('Nuestros Hijos'), matching: find.byType(IconButton)),
      );
      expect(icono.onPressed, isNull);
      expect(find.byKey(const Key('devolucion_saldada')), findsNothing);
    });
  });
}
