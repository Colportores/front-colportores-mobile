// Seguimiento de «Posibles duplicados» (HU-UBI-006, vista 10; issue #340, seguimiento de #208/#338).
//
// - QA F3 (P2): la unión que falla DESPUÉS de salir de la pantalla se avisa en la Lista con
//   «No pudimos unir <dirección> · Revisar» (con dos o más, «No pudimos unir 2 pares · Revisar»).
// - Revisión M2: unir otro par no borra el aviso rojo de la unión que falló.
// - Revisión M3: con A←B esperando, el par B–C no se muestra (la segunda unión no escribiría nada y el
//   aviso diría «quedaron unidas»).
// - QA F4: espacio sin corte entre «5» y «m» en el cuerpo del estado vacío y en la pastilla.
//
// Se monta la Lista de verdad (con su franja «N posibles duplicados · Revisar») sobre las ubicaciones
// en memoria de `DuplicadosEnMemoria`, y desde ahí se entra y se sale de «Posibles duplicados».
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/textos_posibles_duplicados.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/duplicados_falsos.dart';

const _nbsp = ' ';
const _ocho = Duration(seconds: 8);

const _parItalia = 'ub-a|ub-b';
const _parArtigas = 'ub-c|ub-d';

/// Av. Italia 1234 (A–B, a 12 m) y Bulevar Artigas 880 (C–D, a 150 m), a 1 km uno del otro.
DuplicadosEnMemoria _datosDosPares({String calleArtigas = 'Bulevar Artigas'}) {
  final vieja = DateTime.utc(2026, 8, 1, 10);
  final nueva = DateTime.utc(2026, 8, 5, 10);
  return DuplicadosEnMemoria()
    ..agregar(ubicacionDuplicable('ub-a', creada: vieja), espacios: 2)
    ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 12, creada: nueva))
    ..agregar(
      ubicacionDuplicable(
        'ub-c',
        metrosAlNorte: 1000,
        calle: calleArtigas,
        numero: '880',
        creada: vieja,
      ),
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-d',
        metrosAlNorte: 1150,
        calle: calleArtigas,
        numero: '880',
        creada: nueva,
      ),
    );
}

/// Tres registros del mismo domicilio (A, B, C): tres pares, A–B, A–C y B–C.
DuplicadosEnMemoria _datosTresIguales() => DuplicadosEnMemoria()
  ..agregar(ubicacionDuplicable('ub-a', creada: DateTime.utc(2026, 8, 1)), espacios: 2)
  ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 12, creada: DateTime.utc(2026, 8, 3)))
  ..agregar(ubicacionDuplicable('ub-c', metrosAlNorte: 24, creada: DateTime.utc(2026, 8, 5)));

/// Una ubicación sin calle ni número: solo participa de un par por distancia (HU-UBI-006).
Ubicacion _sinDireccion(String id, {double metrosAlNorte = 0, DateTime? creada}) {
  final t = creada ?? DateTime.utc(2026, 9, 1, 10);
  return Ubicacion(
    id: id,
    tipo: TipoUbicacion.casa,
    lat: -34.891 + metrosAlNorte / 111195.08,
    lon: -56.125,
    ciudadId: 'mvd',
    zonaId: 'zona-1',
    auditoria: Auditoria(createdAt: t, updatedAt: t, createdBy: 'col-1'),
  );
}

/// Ninguna palabra del texto es más ancha que su renglón: el texto no se corta a media palabra.
void _expectSinPalabrasPartidas(WidgetTester tester, Finder texto) {
  final render = tester.renderObject<RenderParagraph>(texto);
  for (final palabra in render.text.toPlainText().split(RegExp(r'\s+'))) {
    final pintor = TextPainter(
      text: TextSpan(text: palabra, style: render.text.style),
      textDirection: TextDirection.ltr,
      textScaler: render.textScaler,
    )..layout();
    expect(
      pintor.width,
      lessThanOrEqualTo(render.size.width + 0.5),
      reason: '«$palabra» no entra en un renglón de ${render.size.width} px',
    );
  }
}

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Una transición de página (800 ms) y lo que la sigue.
Future<void> _transicion(WidgetTester tester) async {
  await _asentar(tester);
  await tester.pump(const Duration(seconds: 1));
  await _asentar(tester);
}

/// Monta la Lista de ubicaciones (la pestaña «Lista») con los datos en memoria.
Future<void> _montarLista(
  WidgetTester tester,
  DuplicadosEnMemoria datos, {
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(datos.cerrar);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesDuplicados(datos, conMapa: true),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const Scaffold(body: ListaUbicacionesPage(colportorId: 'col-1')),
      ),
    ),
  );
  await _asentar(tester);
}

/// «Posibles duplicados» sola, abierta desde un botón: en los teléfonos más chicos con el texto muy
/// grande la Lista de abajo ya no entra (su encabezado mide más que la pantalla) y no se puede usar
/// para entrar.
Future<void> _montarPantalla(
  WidgetTester tester,
  DuplicadosEnMemoria datos, {
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(datos.cerrar);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesDuplicados(datos, conMapa: true),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('abrir'),
                onPressed: () =>
                    unawaited(PosiblesDuplicadosPage.abrir(context, colportorId: 'col-1')),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _asentar(tester);
  await tester.tap(find.byKey(const Key('abrir')));
  await _transicion(tester);
  expect(find.byType(PosiblesDuplicadosPage), findsOneWidget);
}

Future<void> _desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void _prueba(String descripcion, Future<void> Function(WidgetTester tester) cuerpo) {
  testWidgets(descripcion, (tester) async {
    final semantica = tester.ensureSemantics();
    await cuerpo(tester);
    await _desmontar(tester);
    semantica.dispose();
  });
}

final _franja = find.byKey(const Key('lista_aviso_duplicados'));
final _franjaFalla = find.byKey(const Key('lista_aviso_union_fallida'));
final _conservarYUnir = find.byKey(const Key('comparar_conservar_y_unir'));
final _avisoRojo = find.byKey(const Key('duplicados_falla_union'));
final _deshacer = find.text('Deshacer');
final _pagina = find.byType(PosiblesDuplicadosPage);
Finder _revisar(String clave) => find.byKey(Key('revisar_$clave'));
Finder _par(String clave) => find.byKey(Key('par_$clave'));
Finder _texto(String texto) => find.textContaining(texto, findRichText: true);

Future<void> _tocar(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _asentar(tester);
}

/// Desde la Lista: toca la franja (la de siempre o la de la falla) y entra a «Posibles duplicados».
Future<void> _entrar(WidgetTester tester) async {
  final franja = _franja.evaluate().isNotEmpty ? _franja : _franjaFalla;
  await tester.tap(franja);
  await _transicion(tester);
  expect(_pagina, findsOneWidget);
}

Future<void> _salir(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('duplicados_volver')));
  await _transicion(tester);
  expect(_pagina, findsNothing);
}

/// Revisa el par [clave], deja "Conservar A y unir" y queda con la hoja cerrada y el aviso a la vista.
Future<void> _unir(WidgetTester tester, String clave, {bool conservarLaSegunda = false}) async {
  await _tocar(tester, _revisar(clave));
  if (conservarLaSegunda) await _tocar(tester, find.byKey(const Key('comparar_opcion_segunda')));
  await _tocar(tester, _conservarYUnir);
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(cargarFuentesReales);

  // ----------------------------------------------------------------------------------------------
  // QA F3 / P2 · la unión falla después de salir de la pantalla
  // ----------------------------------------------------------------------------------------------
  group('QA F3 · «No pudimos unir …» en la Lista', () {
    _prueba('dado que salí de la pantalla y la unión falló, la Lista dice "No pudimos unir Av. '
        'Italia 1234 · Revisar", el par sigue y "Revisar" lo muestra', (tester) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      expect(_texto('2 posibles duplicados · Revisar'), findsOneWidget);

      await _entrar(tester);
      await _unir(tester, _parItalia);
      expect(_texto('Las dos Av. Italia 1234 quedaron unidas en una.'), findsOneWidget);
      datos.falloAlUnir = const FailureInesperado();
      await _salir(tester);

      expect(datos.uniones, hasLength(1), reason: 'al salir la unión se intentó');
      expect(_franja, findsNothing);
      expect(_franjaFalla, findsOneWidget);
      expect(_texto('No pudimos unir Av. Italia 1234 · Revisar'), findsOneWidget);
      expect(
        _texto('posibles duplicados'),
        findsNothing,
        reason: 'el aviso ocupa el lugar de la franja',
      );

      datos.falloAlUnir = null;
      await _entrar(tester);

      expect(_par(_parItalia), findsOneWidget, reason: 'la unión no se hizo: el par sigue');
      expect(find.text('2 para revisar'), findsOneWidget);
      expect(_avisoRojo, findsNothing, reason: 'la pantalla nueva no repite el aviso de la Lista');

      // Y se puede unir de nuevo: ahora anda.
      await _unir(tester, _parItalia);
      await tester.pump(_ocho);
      await _asentar(tester);
      expect(datos.uniones, hasLength(2));
      expect(find.text('1 para revisar'), findsOneWidget);
    });

    _prueba('dado que salí de la pantalla y la unión anda, la Lista dice lo de siempre', (
      tester,
    ) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      await _entrar(tester);
      await _unir(tester, _parItalia);
      await _salir(tester);

      expect(datos.uniones, hasLength(1));
      expect(_franjaFalla, findsNothing);
      expect(_texto('1 posible duplicado · Revisar'), findsOneWidget);
    });

    _prueba(
      'dado que la unión falla con la pantalla abierta, el aviso rojo se queda en la pantalla '
      'y la Lista dice lo de siempre',
      (tester) async {
        final datos = _datosDosPares();
        await _montarLista(tester, datos);
        await _entrar(tester);
        datos.falloAlUnir = const FailureInesperado();
        await _unir(tester, _parItalia);
        await tester.pump(_ocho);
        await _asentar(tester);

        expect(_avisoRojo, findsOneWidget);

        await _salir(tester);

        expect(_franjaFalla, findsNothing, reason: 'ya lo vio en la pantalla');
        expect(_texto('2 posibles duplicados · Revisar'), findsOneWidget);
      },
    );

    _prueba('dado el aviso de la Lista, cuando toco "Revisar" y vuelvo sin hacer nada, el aviso se '
        'dio por leído y no reaparece', (tester) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      await _entrar(tester);
      await _unir(tester, _parItalia);
      datos.falloAlUnir = const FailureInesperado();
      await _salir(tester);
      expect(_franjaFalla, findsOneWidget);

      await _entrar(tester);
      await _salir(tester);

      expect(_franjaFalla, findsNothing);
      expect(_texto('2 posibles duplicados · Revisar'), findsOneWidget);
      expect(datos.uniones, hasLength(1), reason: 'entrar y salir no une nada');
    });

    _prueba(
      'dado el aviso de la Lista, si el par ya no existe (una pasó a baja), no se muestra: no '
      'hay nada que revisar',
      (tester) async {
        final datos = _datosDosPares();
        await _montarLista(tester, datos);
        await _entrar(tester);
        await _unir(tester, _parItalia);
        datos.falloAlUnir = const FailureConservadaDeBaja();
        await _salir(tester);
        expect(_franjaFalla, findsOneWidget);

        datos.darDeBaja('ub-a');
        await _asentar(tester);

        expect(_franjaFalla, findsNothing);
        expect(_texto('1 posible duplicado · Revisar'), findsOneWidget);
      },
    );

    _prueba('dado que dos uniones fallan fuera de la pantalla, la Lista dice "No pudimos unir 2 '
        'pares" y "Revisar" da por leídas las dos', (tester) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      await _entrar(tester);
      final retenida = Completer<void>();
      datos.retenerUniones = retenida;
      await _unir(tester, _parItalia);
      await _unir(tester, _parArtigas); // la primera se confirma ya y queda esperando la base
      await _salir(tester);
      datos.falloAlUnir = const FailureInesperado();
      retenida.complete();
      await _asentar(tester);

      expect(datos.uniones, hasLength(2), reason: 'corrieron de a una, en orden');
      expect(_texto('No pudimos unir 2 pares · Revisar'), findsOneWidget);
      expect(
        find.descendant(of: _franjaFalla, matching: _texto('Italia')),
        findsNothing,
        reason: 'con dos no se nombra una sola',
      );
      expect(find.descendant(of: _franjaFalla, matching: _texto('Artigas')), findsNothing);
      expect(find.bySemanticsLabel('No pudimos unir 2 pares. Revisar'), findsOneWidget);

      datos.falloAlUnir = null;
      await _entrar(tester);
      expect(find.text('2 para revisar'), findsOneWidget);
      await _salir(tester);

      expect(_franjaFalla, findsNothing);
      expect(_texto('2 posibles duplicados · Revisar'), findsOneWidget);
    });

    _prueba('dado que dos uniones fallaron y de uno de los pares ya no hay nada que revisar, la '
        'Lista cuenta solo el que sigue y vuelve a nombrar su dirección', (tester) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      await _entrar(tester);
      final retenida = Completer<void>();
      datos.retenerUniones = retenida;
      await _unir(tester, _parItalia);
      await _unir(tester, _parArtigas);
      await _salir(tester);
      datos.falloAlUnir = const FailureInesperado();
      retenida.complete();
      await _asentar(tester);
      expect(_texto('No pudimos unir 2 pares · Revisar'), findsOneWidget);

      datos.darDeBaja('ub-c');
      await _asentar(tester);

      expect(_texto('No pudimos unir Av. Italia 1234 · Revisar'), findsOneWidget);
      expect(find.descendant(of: _franjaFalla, matching: _texto('2 pares')), findsNothing);

      datos.darDeBaja('ub-a');
      await _asentar(tester);

      expect(_franjaFalla, findsNothing, reason: 'ya no queda ningún par para revisar');
      expect(_franja, findsNothing);
    });

    test('los textos del aviso: una dirección, o la cantidad de pares', () {
      expect(
        TextosPosiblesDuplicados.avisoUnionesFallidas(['Av. Italia 1234']),
        'No pudimos unir Av. Italia 1234',
      );
      expect(
        TextosPosiblesDuplicados.avisoUnionesFallidas(['Av. Italia 1234', 'Bulevar Artigas 880']),
        'No pudimos unir 2 pares',
      );
      expect(
        TextosPosiblesDuplicados.avisoUnionesFallidas(['a 1', 'b 2', 'c 3']),
        'No pudimos unir 3 pares',
      );
    });

    test('los textos sin dirección (ninguna de las dos tiene calle ni número) no dicen «Sin '
        'dirección»', () {
      expect(
        TextosPosiblesDuplicados.unidas('Av. Italia 1234'),
        'Las dos Av. Italia 1234 quedaron unidas en una.',
      );
      expect(TextosPosiblesDuplicados.unidas(''), 'Las dos ubicaciones quedaron unidas en una.');
      expect(
        TextosPosiblesDuplicados.noPudimosUnir(''),
        'No pudimos unir dos ubicaciones sin dirección',
      );
      expect(
        TextosPosiblesDuplicados.avisoUnionesFallidas(['']),
        'No pudimos unir dos ubicaciones sin dirección',
      );
      expect(TextosPosiblesDuplicados.avisoUnionesFallidas(['', '']), 'No pudimos unir 2 pares');
    });

    test('los textos del aviso rojo: la razón con una falla, la cuenta con dos o más', () {
      expect(
        TextosPosiblesDuplicados.falloUniones(const [FailureInesperado()]),
        'No se pudo marcar como duplicado. Probá de nuevo.',
      );
      expect(
        TextosPosiblesDuplicados.falloUniones(const [FailureConservadaDeBaja()]),
        const FailureConservadaDeBaja().mensaje,
      );
      expect(
        TextosPosiblesDuplicados.falloUniones(const [
          FailureInesperado(),
          FailureConservadaDeBaja(),
        ]),
        'No se pudieron marcar 2 pares como duplicados. Probá de nuevo.',
      );
      expect(
        TextosPosiblesDuplicados.noSePudieronUnir(3),
        'No se pudieron marcar 3 pares como duplicados. Probá de nuevo.',
      );
    });

    _prueba(
      'dado el aviso de la Lista, cuando lo toco dos veces seguidas, abre una sola pantalla',
      (tester) async {
        final datos = _datosDosPares();
        await _montarLista(tester, datos);
        await _entrar(tester);
        await _unir(tester, _parItalia);
        datos.falloAlUnir = const FailureInesperado();
        await _salir(tester);

        await tester.tap(_franjaFalla);
        await tester.tap(_franjaFalla, warnIfMissed: false);
        await _transicion(tester);

        expect(_pagina, findsOneWidget);
        await _salir(tester);
        expect(tester.takeException(), isNull);
        expect(_pagina, findsNothing);
      },
    );

    _prueba('dado el aviso de la Lista, un lector de pantalla lo anuncia como botón, lo avisa al '
        'aparecer y se toca con 48 dp', (tester) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      await _entrar(tester);
      await _unir(tester, _parItalia);
      datos.falloAlUnir = const FailureInesperado();
      await _salir(tester);

      expect(find.bySemanticsLabel('No pudimos unir Av. Italia 1234. Revisar'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('No pudimos unir Av. Italia 1234. Revisar')),
        isSemantics(isButton: true, isLiveRegion: true),
      );
      expect(tester.getSize(_franjaFalla).height, greaterThanOrEqualTo(48));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    _prueba(
      'dado el texto al 200 % en un teléfono chico y una dirección larga, el aviso de la Lista '
      'no se desborda ni tapa nada',
      (tester) async {
        final datos = _datosDosPares(
          calleArtigas: 'Avenida Doctor José Gervasio Artigas y Presidente Tomás Berreta',
        );
        await _montarLista(tester, datos, escala: 2, tamano: const Size(360, 640));
        await _entrar(tester);
        await _unir(tester, _parArtigas);
        datos.falloAlUnir = const FailureInesperado();
        await _salir(tester);

        expect(tester.takeException(), isNull);
        expect(_franjaFalla, findsOneWidget);
        final caja = tester.getRect(_franjaFalla);
        expect(caja.left, greaterThanOrEqualTo(0));
        expect(caja.right, lessThanOrEqualTo(360));
        expect(caja.height, greaterThanOrEqualTo(48));
        expect(
          _texto(
            'No pudimos unir Avenida Doctor José Gervasio Artigas y Presidente Tomás Berreta 880',
          ),
          findsOneWidget,
        );
      },
    );

    _prueba(
      'dado que la unión falla fuera de la pantalla y vuelvo a entrar ANTES de que termine, el '
      'aviso llega a la Lista cuando salgo otra vez',
      (tester) async {
        final datos = _datosDosPares();
        await _montarLista(tester, datos);
        await _entrar(tester);
        await _unir(tester, _parItalia);
        final retenida = Completer<void>();
        datos.retenerUniones = retenida;
        await _salir(tester); // la unión queda corriendo, retenida
        await _entrar(tester);
        expect(_par(_parItalia), findsOneWidget);

        datos.falloAlUnir = const FailureInesperado();
        retenida.complete();
        await _asentar(tester);
        expect(_avisoRojo, findsNothing, reason: 'es de la pantalla anterior');
        await _salir(tester);

        expect(_franjaFalla, findsOneWidget);
      },
    );
  });

  // ----------------------------------------------------------------------------------------------
  // Revisión M2 · unir otro par no borra el aviso rojo
  // ----------------------------------------------------------------------------------------------
  group('Revisión M2 · el aviso rojo se queda al unir otro par', () {
    _prueba('dado el aviso rojo de la unión de Italia, cuando uno Artigas, el aviso sigue a la '
        'vista con "Reintentar" hasta que lo toco', (tester) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      await _entrar(tester);
      datos.falloAlUnir = const FailureInesperado();
      await _unir(tester, _parItalia);
      await tester.pump(_ocho);
      await _asentar(tester);
      expect(_avisoRojo, findsOneWidget);
      datos.falloAlUnir = null;

      await _unir(tester, _parArtigas);

      expect(_avisoRojo, findsOneWidget, reason: 'nadie lo leyó ni lo descartó');
      expect(_deshacer, findsOneWidget, reason: 'y la otra unión espera sus 8 s');

      await tester.pump(_ocho);
      await _asentar(tester);
      expect(datos.uniones.map((u) => u.conservadaId), ['ub-a', 'ub-c']);
      expect(_avisoRojo, findsOneWidget);

      await _tocar(tester, find.byKey(const Key('duplicados_reintentar_union')));

      expect(_avisoRojo, findsNothing);
      expect(datos.uniones.map((u) => u.conservadaId), ['ub-a', 'ub-c', 'ub-a']);
      expect(tester.takeException(), isNull);
    });

    _prueba('dado el aviso rojo, cuando lo descarto con "Entendido" mientras otra unión espera, el '
        'aviso se va y la otra sigue con su "Deshacer"', (tester) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      await _entrar(tester);
      datos.falloAlUnir = const FailureInesperado();
      await _unir(tester, _parItalia);
      await tester.pump(_ocho);
      await _asentar(tester);
      datos.falloAlUnir = null;
      await _unir(tester, _parArtigas);

      await _tocar(tester, find.byKey(const Key('duplicados_descartar_falla')));

      expect(_avisoRojo, findsNothing);
      expect(_deshacer, findsOneWidget);
    });
  });

  // ----------------------------------------------------------------------------------------------
  // Revisión M3 · los pares con la duplicada pendiente se esconden
  // ----------------------------------------------------------------------------------------------
  group('Revisión M3 · el par B–C se esconde mientras A←B espera', () {
    _prueba('dado A, B y C del mismo domicilio, cuando uno A←B, B–C no se ve mientras espera y la '
        'segunda unión no existe: al terminar queda una sola unión escrita', (tester) async {
      final datos = _datosTresIguales();
      await _montarLista(tester, datos);
      await _entrar(tester);
      expect(find.text('3 para revisar'), findsOneWidget);

      await _unir(tester, 'ub-a|ub-b');

      expect(find.text('1 para revisar'), findsOneWidget);
      expect(_par('ub-a|ub-b'), findsNothing);
      expect(_par('ub-b|ub-c'), findsNothing, reason: 'B va a quedar de baja');
      expect(_par('ub-a|ub-c'), findsOneWidget, reason: 'A se queda: ese par sigue siendo real');
      expect(datos.uniones, isEmpty, reason: 'durante los 8 s no se escribe nada');

      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
      expect(find.text('1 para revisar'), findsOneWidget);
      expect(_par('ub-b|ub-c'), findsNothing);
      expect(_par('ub-a|ub-c'), findsOneWidget);
      expect(_avisoRojo, findsNothing);
    });

    _prueba('dado A←B esperando, cuando toco "Deshacer", los tres pares vuelven', (tester) async {
      final datos = _datosTresIguales();
      await _montarLista(tester, datos);
      await _entrar(tester);
      await _unir(tester, 'ub-a|ub-b');
      expect(find.text('1 para revisar'), findsOneWidget);

      await tester.tap(_deshacer);
      await _asentar(tester);

      expect(find.text('3 para revisar'), findsOneWidget);
      expect(_par('ub-b|ub-c'), findsOneWidget);
      expect(datos.uniones, isEmpty);
    });

    _prueba('dado A←B que falla, los tres pares vuelven junto con el aviso rojo', (tester) async {
      final datos = _datosTresIguales();
      await _montarLista(tester, datos);
      await _entrar(tester);
      datos.falloAlUnir = const FailureInesperado();
      await _unir(tester, 'ub-a|ub-b');

      await tester.pump(_ocho);
      await _asentar(tester);

      expect(find.text('3 para revisar'), findsOneWidget);
      expect(_par('ub-b|ub-c'), findsOneWidget);
      expect(_avisoRojo, findsOneWidget);
    });

    _prueba('dado que elijo conservar B, se esconden los pares con A (la duplicada) y queda B–C', (
      tester,
    ) async {
      final datos = _datosTresIguales();
      await _montarLista(tester, datos);
      await _entrar(tester);

      await _unir(tester, 'ub-a|ub-b', conservarLaSegunda: true);

      expect(find.text('1 para revisar'), findsOneWidget);
      expect(_par('ub-a|ub-c'), findsNothing, reason: 'A va a quedar de baja');
      expect(_par('ub-b|ub-c'), findsOneWidget);
      await tester.pump(_ocho);
      await _asentar(tester);
      expect(datos.uniones, [(conservadaId: 'ub-b', duplicadaId: 'ub-a')]);
    });

    _prueba(
      'dado A←B esperando, cuando uno también A←C (el par que sigue), las tres quedan en una, '
      'de a una y en orden, sin avisos de más',
      (tester) async {
        final datos = _datosTresIguales();
        await _montarLista(tester, datos);
        await _entrar(tester);
        await _unir(tester, 'ub-a|ub-b');

        await _unir(tester, 'ub-a|ub-c');
        expect(datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
        expect(_texto('Las dos Av. Italia 1234 quedaron unidas en una.'), findsOneWidget);

        await tester.pump(_ocho);
        await _asentar(tester);

        expect(datos.uniones, [
          (conservadaId: 'ub-a', duplicadaId: 'ub-b'),
          (conservadaId: 'ub-a', duplicadaId: 'ub-c'),
        ]);
        expect(find.byKey(const Key('duplicados_vacio')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    _prueba('dado A←B ya hecha y la pantalla abierta, B–C no reaparece mientras la base se pone al '
        'día', (tester) async {
      final datos = _datosTresIguales();
      await _montarLista(tester, datos);
      await _entrar(tester);
      await _unir(tester, 'ub-a|ub-b');
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.ubicacion('ub-b').auditoria.estaBorrada, isTrue);
      expect(_par('ub-b|ub-c'), findsNothing);
      expect(find.text('1 para revisar'), findsOneWidget);
    });
  });

  // ----------------------------------------------------------------------------------------------
  // QA F4 · espacio sin corte en todos los textos con «5 m»
  // ----------------------------------------------------------------------------------------------
  group('QA F4 · «5 m» no se parte', () {
    final cincoYM = RegExp('5[$_nbsp ]m');

    Finder empiezaCon(String prefijo) => find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').startsWith(prefijo),
      description: 'Text que empieza con "$prefijo"',
    );

    /// Que "5" y "m" caigan en el mismo renglón: la caja de cada uno empieza a la misma altura.
    void expectSinCorte(WidgetTester tester, Finder texto, double ancho) {
      final render = tester.renderObject<RenderParagraph>(texto);
      final plano = render.text.toPlainText();
      final i = plano.indexOf(cincoYM);
      expect(i, greaterThanOrEqualTo(0), reason: 'el texto lleva "5" y "m"');
      double alto(int desde) => render
          .getBoxesForSelection(TextSelection(baseOffset: desde, extentOffset: desde + 1))
          .first
          .top;
      expect(alto(i), alto(i + 2), reason: '"5" y "m" en el mismo renglón a $ancho px');
    }

    /// Recorre anchos de pantalla de 280 a 400 px de a 2: alguno tiene que caer justo en el borde.
    Future<void> recorrerAnchos(WidgetTester tester, void Function(double ancho) comprobar) async {
      for (var ancho = 280.0; ancho <= 400; ancho += 2) {
        tester.view.physicalSize = Size(ancho, 640);
        await tester.pump();
        comprobar(ancho);
      }
    }

    _prueba(
      'dado el texto al 200 % y cualquier ancho de teléfono, la pastilla "A menos de 5 m" y el '
      'subtítulo no dejan la "m" sola',
      (tester) async {
        final datos = DuplicadosEnMemoria()
          ..agregar(ubicacionDuplicable('ub-a', calle: 'Michigan', numero: '1540'))
          ..agregar(
            ubicacionDuplicable('ub-b', metrosAlNorte: 3, calle: 'Michigan', numero: '1540 bis'),
          );
        await _montarLista(tester, datos, escala: 2, tamano: const Size(360, 640));
        await _entrar(tester);

        await recorrerAnchos(tester, (ancho) {
          expectSinCorte(tester, empiezaCon('A menos de 5'), ancho);
          expectSinCorte(tester, empiezaCon('Son ubicaciones tuyas'), ancho);
        });
        expect(tester.takeException(), isNull);
      },
    );

    _prueba(
      'dado que no hay pares, el cuerpo del estado vacío no deja la "m" sola a ningún ancho',
      (tester) async {
        final vacio = DuplicadosEnMemoria()
          ..agregar(ubicacionDuplicable('ub-a'))
          ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 500, calle: 'Otra', numero: '9'))
          ..agregar(ubicacionDuplicable('ub-c', metrosAlNorte: 1000, calle: 'Otra', numero: '10'));
        await _montarLista(tester, vacio, escala: 2, tamano: const Size(360, 640));
        // La Lista no ofrece "Revisar" sin pares: se entra a la pantalla directamente.
        final contexto = tester.element(find.byType(ListaUbicacionesPage));
        unawaited(PosiblesDuplicadosPage.abrir(contexto, colportorId: 'col-1'));
        await _transicion(tester);

        final cuerpo = empiezaCon('Cuando dos de tus ubicaciones');
        expect(cuerpo, findsOneWidget);
        expect(
          tester.widget<Text>(cuerpo).data,
          'Cuando dos de tus ubicaciones tengan la misma calle y número, o estén a menos de '
          '5${_nbsp}m, aparecen acá.',
        );
        await recorrerAnchos(tester, (ancho) => expectSinCorte(tester, cuerpo, ancho));
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ----------------------------------------------------------------------------------------------
  // QA de #357 · P1: el aviso rojo queda fijo y cuenta todas las fallas
  // ----------------------------------------------------------------------------------------------
  group('QA #357 P1 · el aviso rojo queda fijo debajo de la barra y no pierde ninguna falla', () {
    /// Italia y Artigas fallan con la pantalla abierta, una detrás de la otra. [sola] abre la pantalla
    /// sin la Lista debajo (a 320×568 con el texto muy grande la Lista no entra).
    Future<DuplicadosEnMemoria> dosFallas(
      WidgetTester tester, {
      double escala = 1,
      Size tamano = const Size(390, 844),
      bool sola = false,
    }) async {
      final datos = _datosDosPares();
      if (sola) {
        await _montarPantalla(tester, datos, escala: escala, tamano: tamano);
      } else {
        await _montarLista(tester, datos, escala: escala, tamano: tamano);
        await _entrar(tester);
      }
      datos.falloAlUnir = const FailureInesperado();
      await _unir(tester, _parItalia);
      await tester.pump(_ocho);
      await _asentar(tester);
      await _unir(tester, _parArtigas);
      await tester.pump(_ocho);
      await _asentar(tester);
      return datos;
    }

    const unaFalla = 'No se pudo marcar como duplicado. Probá de nuevo.';
    const dos = 'No se pudieron marcar 2 pares como duplicados. Probá de nuevo.';

    _prueba('dado una sola falla, el aviso rojo dice por qué y no cuenta pares', (tester) async {
      final datos = _datosDosPares();
      await _montarLista(tester, datos);
      await _entrar(tester);
      datos.falloAlUnir = const FailureInesperado();
      await _unir(tester, _parItalia);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(_avisoRojo, findsOneWidget);
      expect(_texto(unaFalla), findsOneWidget);
    });

    _prueba('dado que dos uniones fallan con la pantalla abierta, el aviso rojo cuenta los dos '
        'pares y los dos vuelven a la lista', (tester) async {
      await dosFallas(tester);

      expect(_avisoRojo, findsOneWidget);
      expect(_texto(dos), findsOneWidget);
      expect(_texto(unaFalla), findsNothing, reason: 'la segunda no pisa a la primera');
      expect(_par(_parItalia), findsOneWidget);
      expect(_par(_parArtigas), findsOneWidget);
      expect(find.byKey(const Key('duplicados_reintentar_union')), findsOneWidget);
      expect(find.byKey(const Key('duplicados_descartar_falla')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _prueba('dado el aviso rojo, no es parte de la lista: queda debajo de la barra y arriba del '
        'encabezado de la lista', (tester) async {
      await dosFallas(tester);

      expect(find.descendant(of: find.byType(ListView), matching: _avisoRojo), findsNothing);
      final barra = tester.getBottomLeft(find.byKey(const Key('duplicados_volver'))).dy;
      expect(tester.getTopLeft(_avisoRojo).dy, greaterThanOrEqualTo(barra - 0.5));
      expect(tester.getBottomLeft(_avisoRojo).dy, lessThan(tester.getTopLeft(_par(_parItalia)).dy));
    });

    _prueba('dado el aviso rojo y una lista larga que se baja, el aviso no se mueve', (
      tester,
    ) async {
      await dosFallas(tester, escala: 2, tamano: const Size(360, 640));
      final antes = tester.getRect(_avisoRojo);

      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await _asentar(tester);

      expect(_avisoRojo.hitTestable(), findsOneWidget, reason: 'sigue a la vista');
      expect(tester.getRect(_avisoRojo), antes);
    });

    _prueba('dado dos fallas, cuando toco "Reintentar", las dos uniones corren y no queda ningún '
        'aviso', (tester) async {
      final datos = await dosFallas(tester);
      datos.falloAlUnir = null;

      await _tocar(tester, find.byKey(const Key('duplicados_reintentar_union')));
      await _asentar(tester);

      expect(_avisoRojo, findsNothing);
      expect(
        datos.uniones.map((u) => u.conservadaId),
        ['ub-a', 'ub-c', 'ub-a', 'ub-c'],
        reason: 'los dos intentos que fallaron y los dos reintentos',
      );
      expect(tester.takeException(), isNull);
    });

    _prueba('dado dos fallas, cuando reintento y vuelven a fallar, el aviso sigue con su cuenta y '
        'los dos pares están en la lista', (tester) async {
      await dosFallas(tester);

      await _tocar(tester, find.byKey(const Key('duplicados_reintentar_union')));
      await _asentar(tester);

      expect(_texto(dos), findsOneWidget);
      expect(_par(_parItalia), findsOneWidget);
      expect(_par(_parArtigas), findsOneWidget);
    });

    _prueba('dado dos fallas, cuando toco "Entendido", se van las dos y el aviso no vuelve', (
      tester,
    ) async {
      await dosFallas(tester);

      await _tocar(tester, find.byKey(const Key('duplicados_descartar_falla')));

      expect(_avisoRojo, findsNothing);
      expect(_par(_parItalia), findsOneWidget);
    });

    _prueba('dado 320×568 con el texto al 200 %, la franja de la Lista no desborda: está arriba de '
        'lo que se desplaza y baja con las filas', (tester) async {
      await _montarLista(tester, _datosDosPares(), escala: 2, tamano: const Size(320, 568));

      expect(tester.takeException(), isNull);
      expect(_franja, findsOneWidget);
      final arriba = tester.getTopLeft(_franja).dy;
      expect(arriba, lessThan(568), reason: 'se ve el comienzo');

      await tester.dragFrom(Offset(4, arriba + 8), const Offset(0, -24));
      await _asentar(tester);

      expect(tester.getTopLeft(_franja).dy, lessThan(arriba), reason: 'baja con las filas');
      expect(tester.takeException(), isNull);
    });

    for (final escala in [2.0, 3.0]) {
      _prueba('dado dos fallas a 320×568 con el texto al ${(escala * 100).toInt()} %, no se corta '
          'ninguna palabra, no desborda y la lista conserva lugar', (tester) async {
        await dosFallas(tester, escala: escala, tamano: const Size(320, 568), sola: true);

        expect(tester.takeException(), isNull);
        final texto = _texto(dos);
        expect(texto, findsOneWidget);
        _expectSinPalabrasPartidas(tester, texto);
        // El aviso no se come la pantalla: la lista conserva por lo menos un tercio.
        final lista = tester.getRect(find.byType(ListView).first);
        expect(lista.height, greaterThanOrEqualTo(568 / 3), reason: 'lista en $lista');
        expect(tester.getRect(_par(_parItalia)).top, lessThan(568));
        // Los dos botones del aviso se alcanzan.
        await tester.ensureVisible(find.byKey(const Key('duplicados_reintentar_union')));
        await tester.pump();
        expect(find.byKey(const Key('duplicados_reintentar_union')).hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('duplicados_descartar_falla')));
        await tester.pump();
        expect(find.byKey(const Key('duplicados_descartar_falla')).hitTestable(), findsOneWidget);
      });
    }

    _prueba('dado una falla a 320×568 con el texto al 200 %, el aviso rojo se ve entero con sus '
        'dos botones', (tester) async {
      final datos = _datosDosPares();
      await _montarPantalla(tester, datos, escala: 2, tamano: const Size(320, 568));
      datos.falloAlUnir = const FailureInesperado();
      await _unir(tester, _parItalia);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      _expectSinPalabrasPartidas(tester, _texto(unaFalla));
      expect(tester.getRect(_avisoRojo).bottom, lessThanOrEqualTo(568));
      expect(find.byKey(const Key('duplicados_reintentar_union')).hitTestable(), findsOneWidget);
      expect(find.byKey(const Key('duplicados_descartar_falla')).hitTestable(), findsOneWidget);
    });

    _prueba('dado el texto al 300 %, el aviso rojo no crece más que al 200 % (se limita a lo que '
        'entra)', (tester) async {
      await dosFallas(tester, escala: 2, tamano: const Size(412, 915));
      final conDos = tester.getSize(_texto(dos));
      await _desmontar(tester);

      await dosFallas(tester, escala: 3, tamano: const Size(412, 915));
      final conTres = tester.getSize(_texto(dos));

      expect(conTres, conDos, reason: 'el texto del aviso no pasa del 200 %');
    });
  });

  // ----------------------------------------------------------------------------------------------
  // QA de #357 · P2: sin calle ni número no se dice «Sin dirección» en una frase
  // ----------------------------------------------------------------------------------------------
  group('QA #357 P2 · la dirección de los avisos de unión', () {
    _prueba(
      'dado un par por distancia donde ninguna tiene calle ni número, el aviso de la pantalla '
      'dice "Las dos ubicaciones quedaron unidas en una."',
      (tester) async {
        final datos = DuplicadosEnMemoria()
          ..agregar(_sinDireccion('ub-a', creada: DateTime.utc(2026, 8, 1)))
          ..agregar(_sinDireccion('ub-b', metrosAlNorte: 3, creada: DateTime.utc(2026, 8, 5)));
        await _montarLista(tester, datos);
        await _entrar(tester);

        await _unir(tester, _parItalia);

        expect(_texto('Las dos ubicaciones quedaron unidas en una.'), findsOneWidget);
        expect(_texto('Sin dirección'), findsNothing);
      },
    );

    _prueba('dado un par donde la que se conserva no tiene dirección pero la otra sí, el aviso '
        'usa la de la otra', (tester) async {
      final datos = DuplicadosEnMemoria()
        ..agregar(_sinDireccion('ub-a', creada: DateTime.utc(2026, 8, 1)))
        ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 3, creada: DateTime.utc(2026, 8, 5)));
      await _montarLista(tester, datos);
      await _entrar(tester);

      await _unir(tester, _parItalia);

      expect(_texto('Las dos Av. Italia 1234 quedaron unidas en una.'), findsOneWidget);
    });

    _prueba('dado un par donde la que se conserva tiene dirección, el aviso usa la suya aunque la '
        'otra no tenga', (tester) async {
      final datos = DuplicadosEnMemoria()
        ..agregar(ubicacionDuplicable('ub-a', creada: DateTime.utc(2026, 8, 1)))
        ..agregar(_sinDireccion('ub-b', metrosAlNorte: 3, creada: DateTime.utc(2026, 8, 5)));
      await _montarLista(tester, datos);
      await _entrar(tester);

      await _unir(tester, _parItalia);

      expect(_texto('Las dos Av. Italia 1234 quedaron unidas en una.'), findsOneWidget);
    });

    _prueba(
      'dado que la unión sin dirección falla fuera de la pantalla, la franja dice "No pudimos '
      'unir dos ubicaciones sin dirección · Revisar"',
      (tester) async {
        final datos = DuplicadosEnMemoria()
          ..agregar(_sinDireccion('ub-a', creada: DateTime.utc(2026, 8, 1)))
          ..agregar(_sinDireccion('ub-b', metrosAlNorte: 3, creada: DateTime.utc(2026, 8, 5)));
        await _montarLista(tester, datos);
        await _entrar(tester);
        await _unir(tester, _parItalia);
        datos.falloAlUnir = const FailureInesperado();
        await _salir(tester);

        expect(_texto('No pudimos unir dos ubicaciones sin dirección · Revisar'), findsOneWidget);
        expect(_texto('unir Sin dirección'), findsNothing);
      },
    );
  });
}
