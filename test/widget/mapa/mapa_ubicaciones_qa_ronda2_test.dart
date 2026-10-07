// QA de la vista 06 (#199, HU-UBI-003), ronda 2: lo que arregla el delta 6ce96d8..21f3f07, probado de
// modo que falle si el arreglo se rompe.
//
// Los 12 tests de la ronda 1 (`mapa_ubicaciones_qa_pantalla_principal_test.dart`) miden con un helper
// que desliza la tarjeta por código (`Scrollable.ensureVisible`): sirve para saber si hay algo
// encima, pero no prueba que un DEDO pueda llegar (una tarjeta con `NeverScrollableScrollPhysics`
// también pasaría). Acá se llega arrastrando de verdad, y después se toca y se mira qué pasó.
import 'dart:math' as math;

import 'package:colportores_mobile/features/mapa/presentation/formato_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart'
    show UbicacionReutilizada;
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_descargas_arnes.dart';
import 'mapa_ubicaciones_arnes.dart'
    show asentarLista, botonNueva, chipReferencias, montarMapaUbicaciones, tocarAsa;
import 'mapa_ubicaciones_page_test.dart' show canvas;
import 'mapa_ubicaciones_qa_pantalla_principal_test.dart'
    show PantallaPrincipal, montarEnPantallaPrincipal, motivoInaccesible;

const _telefono360 = Size(360, 640);
const _telefono412 = Size(412, 915);

Finder get _descargar => find.widgetWithText(FilledButton, 'Descargar mapa');
Finder get _activarDatos => find.widgetWithText(OutlinedButton, 'Activar datos');
Finder get _minimizar => find.byTooltip('Minimizar aviso');
Finder get _descargarConPeso =>
    find.ancestor(of: find.textContaining('Descargar mapa ·'), matching: find.byType(FilledButton));
Finder get _ahoraNo => find.widgetWithText(TextButton, 'Ahora no');
Finder get _desplazableDelAviso =>
    find.descendant(of: find.byType(AvisoMapaConectado), matching: find.byType(Scrollable)).first;

/// Una escena del aviso de conexión: cómo se monta y qué botón hace qué.
typedef _Escena = ({
  String nombre,
  Future<PantallaPrincipal> Function(WidgetTester, Size, double) montar,
  Map<String, Finder> botones,

  /// Qué tiene que pasar después de tocar cada botón.
  Map<String, void Function(WidgetTester, ArnesMapa)> efectos,
});

/// El arnés de la escena que se está montando (cada `montar` arma uno nuevo).
ArnesMapa? _ultimoArnes;

/// Arma el arnés de la escena (cada `montar` arma uno nuevo).
ArnesMapa _arnes(TipoConexion conexion) {
  final arnes = ArnesMapa(conexion: conexion, catalogo: [paqueteMontevideo]);
  return _ultimoArnes = arnes;
}

final _escenas = <_Escena>[
  (
    nombre: 'sin conexión, con la ciudad conocida',
    montar: (t, tam, e) => montarEnPantallaPrincipal(
      t,
      repo: RepoListaFalso(canvas()),
      arnes: _arnes(TipoConexion.sinConexion),
      ambito: ambitoMontevideo,
      tamano: tam,
      escala: e,
    ),
    botones: {
      '«Descargar mapa»': _descargar,
      '«Activar datos»': _activarDatos,
      '✕ «Minimizar aviso»': _minimizar,
    },
    efectos: {
      '«Descargar mapa»': (t, a) => expect(
        find.text('Se descarga sola cuando vuelva la señal.'),
        findsWidgets,
        reason: 'el pedido quedó en cola',
      ),
      '«Activar datos»': (t, a) => expect(a.ajustes.aperturasDeRed, 1),
      '✕ «Minimizar aviso»': (t, a) => expect(find.byKey(ClavesAvisoMapa.pildora), findsOneWidget),
    },
  ),
  (
    nombre: 'sin conexión, sin la ciudad',
    montar: (t, tam, e) => montarEnPantallaPrincipal(
      t,
      repo: RepoListaFalso(canvas()),
      arnes: _arnes(TipoConexion.sinConexion),
      tamano: tam,
      escala: e,
    ),
    botones: {'«Activar datos»': _activarDatos, '✕ «Minimizar aviso»': _minimizar},
    efectos: {
      '«Activar datos»': (t, a) => expect(a.ajustes.aperturasDeRed, 1),
      '✕ «Minimizar aviso»': (t, a) => expect(find.byKey(ClavesAvisoMapa.pildora), findsOneWidget),
    },
  ),
  (
    nombre: 'con datos móviles',
    montar: (t, tam, e) => montarEnPantallaPrincipal(
      t,
      repo: RepoListaFalso(canvas()),
      arnes: _arnes(TipoConexion.datosMoviles),
      ambito: ambitoMontevideo,
      tamano: tam,
      escala: e,
    ),
    botones: {'«Descargar mapa · N MB»': _descargarConPeso, '«Ahora no»': _ahoraNo},
    efectos: {
      '«Descargar mapa · N MB»': (t, a) =>
          expect(a.montevideoDescargado, isTrue, reason: 'el pedido se hizo y terminó'),
      '«Ahora no»': (t, a) => expect(find.byKey(ClavesAvisoMapa.datosMoviles), findsNothing),
    },
  ),
];

/// «Sin conexión» con la ciudad conocida, en un teléfono de [tamano].
Future<PantallaPrincipal> escenaSinConexion(
  WidgetTester tester,
  Size tamano, {
  double escala = 1,
}) => _escenas.first.montar(tester, tamano, escala);

/// Arrastra la tarjeta con el dedo (un paso de 30 dp por vez, primero hacia abajo y después hacia
/// arriba) hasta que [objetivo] se pueda tocar. Devuelve por qué no se llegó, o `null`.
Future<String?> _llegarConElDedo(WidgetTester tester, Finder objetivo) async {
  // Con el texto a 2x la tarjeta mide casi dos pantallas: el paso es lo que se ve de ella, y hay
  // margen de sobra para recorrerla entera hacia cada lado.
  for (final sentido in [-1.0, 1.0]) {
    for (var paso = 0; paso < 40; paso++) {
      if (motivoInaccesible(tester, objetivo) == null) return null;
      final zona = _desplazableDelAviso;
      final centro = tester.getCenter(zona);
      final bajoElDedo = tester.hitTestOnBinding(centro).path.map((e) => e.target);
      if (!bajoElDedo.contains(tester.renderObject(zona))) {
        return 'el dedo en $centro no cae sobre la tarjeta: ${bajoElDedo.firstOrNull.runtimeType}';
      }
      await tester.drag(
        zona,
        Offset(0, sentido * math.max(40.0, tester.getRect(zona).height * .5)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
  return motivoInaccesible(tester, objetivo);
}

/// Lo que se ve del aviso: la tarjeta (su zona deslizable) o, con la píldora, la píldora.
Rect _zonaDelAviso(WidgetTester tester) {
  final pildora = find.byKey(ClavesAvisoMapa.pildora);
  return tester.getRect(pildora.evaluate().isNotEmpty ? pildora : _desplazableDelAviso);
}

/// ¿«Sin conexión» pasa a la píldora por falta de lugar? Con la hoja a 1/2 en 360x640 quedan menos de
/// 100 dp libres (decisión del 07/10 sobre P2 del #294): ahí no hay tarjeta con botones que tocar.
bool _sinConexionConPildora(_Escena escena, Size tamano, int altura) =>
    escena.nombre.startsWith('sin conexión') && tamano == _telefono360 && altura == 2;

void main() {
  group('QA #199 r2 · B1/M1: a los botones del aviso se llega con el DEDO y hacen lo suyo', () {
    // Las combinaciones donde la ronda 1 encontró los botones tapados.
    final casos = <({String nombre, Size tamano, double escala, int altura})>[
      (nombre: '360x640 texto 2.0 hoja minimizada', tamano: _telefono360, escala: 2, altura: 0),
      (nombre: '360x640 texto 2.0 hoja a 1/2', tamano: _telefono360, escala: 2, altura: 2),
      (nombre: '360x640 texto 1.0 hoja a 1/3', tamano: _telefono360, escala: 1, altura: 1),
      (nombre: '360x640 texto 1.0 hoja a 1/2', tamano: _telefono360, escala: 1, altura: 2),
      (nombre: '412x915 texto 2.0 hoja minimizada', tamano: _telefono412, escala: 2, altura: 0),
      (nombre: '412x915 texto 2.0 hoja a 1/2', tamano: _telefono412, escala: 2, altura: 2),
    ];
    for (final caso in casos) {
      for (final escena in _escenas) {
        // Con la píldora no hay tarjeta ni sus botones: eso lo prueba el grupo M1, de más abajo.
        if (_sinConexionConPildora(escena, caso.tamano, caso.altura)) continue;
        for (final boton in escena.botones.keys) {
          testWidgets('«${escena.nombre}» · $boton · ${caso.nombre}', (tester) async {
            await escena.montar(tester, caso.tamano, caso.escala);
            if (caso.altura > 0) await tocarAsa(tester, caso.altura);
            expect(tester.takeException(), isNull);

            final motivo = await _llegarConElDedo(tester, escena.botones[boton]!);
            expect(motivo, isNull, reason: '$boton: $motivo');

            // Se toca de verdad y pasa lo que dice el botón.
            await tester.tap(escena.botones[boton]!);
            await asentarLista(tester);
            expect(tester.takeException(), isNull);
            escena.efectos[boton]!(tester, _ultimoArnes!);
          });
        }
      }
    }
  });

  group('QA #199 r2 · B1: la tarjeta no pasa de la zona libre sobre la hoja y los botones', () {
    for (final tamano in [_telefono360, _telefono412]) {
      for (final escala in [1.0, 2.0]) {
        for (final altura in [0, 1, 2]) {
          for (final escena in _escenas) {
            testWidgets(
              '«${escena.nombre}» · ${tamano.width.toInt()}x${tamano.height.toInt()} · texto $escala '
              '· hoja $altura: lo que se ve de la tarjeta termina arriba de «Mi ubicación»',
              (tester) async {
                await escena.montar(tester, tamano, escala);
                if (altura > 0) await tocarAsa(tester, altura);

                final tarjeta = _zonaDelAviso(tester);
                final miUbicacion = tester.getRect(find.byKey(ClavesMapaUbicaciones.miUbicacion));
                final hoja = tester.getRect(find.byKey(ClavesMapaUbicaciones.hoja));
                expect(
                  tarjeta.bottom,
                  lessThanOrEqualTo(miUbicacion.top + 0.01),
                  reason: 'la tarjeta $tarjeta llega a «Mi ubicación» $miUbicacion',
                );
                expect(tarjeta.bottom, lessThanOrEqualTo(hoja.top + 0.01));
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    }
  });

  group('QA #199 r2 · M1: con la hoja a 1/2 en 360x640 «Sin conexión» pasa a la píldora', () {
    // Decisión del 07/10 sobre P2 (#294): con menos de 100 dp libres la tarjeta solo deja ver el
    // título, así que se muestra la píldora, que descarga de un toque. La hoja no se toca, y las
    // tarjetas de datos móviles y de error siguen deslizables.
    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'con la ciudad: la píldora está a la vista y el toque pide la descarga · texto $escala',
        (tester) async {
          await escenaSinConexion(tester, _telefono360, escala: escala);
          await tocarAsa(tester, 2);

          expect(tester.takeException(), isNull);
          final pildora = find.byKey(ClavesAvisoMapa.pildora);
          expect(
            find.byKey(ClavesAvisoMapa.sinConexion),
            findsNothing,
            reason: 'sin lugar: no hay tarjeta',
          );
          expect(pildora, findsOneWidget);
          expect(motivoInaccesible(tester, pildora), isNull);
          expect(
            _zonaDelAviso(tester).bottom,
            lessThanOrEqualTo(tester.getRect(find.byKey(ClavesMapaUbicaciones.hoja)).top + 0.01),
          );

          await tester.tap(pildora);
          await asentarLista(tester);

          expect(tester.takeException(), isNull);
          expect(find.text('Se descarga sola cuando vuelva la señal.'), findsWidgets);
          expect(find.byKey(ClavesAvisoMapa.pildora), findsOneWidget);
        },
      );

      testWidgets('sin la ciudad: la píldora solo avisa (no ofrece descargar) · texto $escala', (
        tester,
      ) async {
        await _escenas[1].montar(tester, _telefono360, escala);
        await tocarAsa(tester, 2);

        expect(tester.takeException(), isNull);
        expect(find.byKey(ClavesAvisoMapa.sinConexion), findsNothing);
        expect(find.byKey(ClavesAvisoMapa.pildora), findsOneWidget);
        expect(find.text('Sin conexión'), findsOneWidget);
        expect(find.textContaining('Descargar'), findsNothing);
      });

      testWidgets(
        'con datos móviles la tarjeta se queda (deslizable), no hay píldora · texto $escala',
        (tester) async {
          await _escenas[2].montar(tester, _telefono360, escala);
          await tocarAsa(tester, 2);

          expect(tester.takeException(), isNull);
          expect(find.byKey(ClavesAvisoMapa.datosMoviles), findsOneWidget);
          expect(find.byKey(ClavesAvisoMapa.pildora), findsNothing);
          expect(_desplazableDelAviso, findsOneWidget);
        },
      );
    }

    testWidgets(
      'la tarjeta vuelve cuando vuelve el lugar (la hoja baja), sin haber guardado nada',
      (tester) async {
        await escenaSinConexion(tester, _telefono360);
        await tocarAsa(tester, 2);
        expect(find.byKey(ClavesAvisoMapa.pildora), findsOneWidget);

        await tocarAsa(tester); // 1/2 → minimizada: vuelve el lugar.

        expect(tester.takeException(), isNull);
        expect(find.byKey(ClavesAvisoMapa.sinConexion), findsOneWidget);
        expect(find.byKey(ClavesAvisoMapa.pildora), findsNothing);
      },
    );

    testWidgets('si se la minimizó con la ✕, la píldora sigue aunque vuelva el lugar', (
      tester,
    ) async {
      await escenaSinConexion(tester, _telefono360);
      await tester.tap(_minimizar);
      await asentarLista(tester);
      await tocarAsa(tester, 2);
      await tocarAsa(tester);

      expect(find.byKey(ClavesAvisoMapa.pildora), findsOneWidget);
      expect(find.byKey(ClavesAvisoMapa.sinConexion), findsNothing);
    });
  });

  group('QA #199 r2 · M2: «Referencias» y «Mi ubicación» no se pisan en teléfonos más chicos', () {
    final variantes = <({String nombre, Size tamano, double escala, double barraAbajo})>[
      (nombre: '320x568 texto 1.0', tamano: const Size(320, 568), escala: 1, barraAbajo: 0),
      (nombre: '360x640 texto 1.5', tamano: _telefono360, escala: 1.5, barraAbajo: 0),
      (
        nombre: '360x640 texto 1.0 con barra de gestos',
        tamano: _telefono360,
        escala: 1,
        barraAbajo: 24,
      ),
      (nombre: '412x915 texto 2.0', tamano: _telefono412, escala: 2, barraAbajo: 0),
    ];
    for (final variante in variantes) {
      for (final altura in [0, 1, 2]) {
        testWidgets('${variante.nombre} · hoja $altura', (tester) async {
          await montarEnPantallaPrincipal(
            tester,
            repo: RepoListaFalso(canvas()),
            tamano: variante.tamano,
            escala: variante.escala,
          );
          if (variante.barraAbajo > 0) {
            tester.view.padding = FakeViewPadding(top: 24, bottom: variante.barraAbajo);
            tester.view.viewPadding = FakeViewPadding(top: 24, bottom: variante.barraAbajo);
            await asentarLista(tester);
          }
          if (altura > 0) await tocarAsa(tester, altura);

          expect(tester.takeException(), isNull);
          for (final (nombre, clave) in [
            ('«Mi ubicación»', find.byKey(ClavesMapaUbicaciones.miUbicacion)),
            ('«Nueva»', find.byKey(ClavesMapaUbicaciones.nueva)),
            ('el asa', find.byKey(ClavesMapaUbicaciones.asa)),
          ]) {
            expect(motivoInaccesible(tester, clave), isNull, reason: nombre);
          }
          // «Referencias» se toca por el centro Y por las dos puntas de abajo (el `Stack` que lo
          // contiene recorta lo que sobra de su zona).
          final chip = tester.getRect(chipReferencias);
          for (final punto in [
            chip.center,
            chip.bottomLeft + const Offset(24, -4),
            chip.bottomRight - const Offset(24, 4),
          ]) {
            final camino = tester.hitTestOnBinding(punto).path.map((e) => e.target);
            expect(
              camino.contains(tester.renderObject(chipReferencias)),
              isTrue,
              reason: '«Referencias» $chip no se toca en $punto',
            );
          }
          expect(
            chip.overlaps(tester.getRect(find.byKey(ClavesMapaUbicaciones.miUbicacion))),
            isFalse,
          );
        });
      }
    }
  });

  group('QA #199 r2 · la hoja a 1/2 solo se achica cuando hace falta', () {
    testWidgets('en 412x915 la hoja a 1/2 mide la mitad de la pantalla (no se achicó de más)', (
      tester,
    ) async {
      await montarEnPantallaPrincipal(tester, repo: RepoListaFalso(canvas()), tamano: _telefono412);
      await tocarAsa(tester, 2);

      expect(tester.getSize(find.byKey(ClavesMapaUbicaciones.hoja)).height, closeTo(915 / 2, 0.5));
    });

    testWidgets('en 360x640 la hoja a 1/2 sigue siendo más alta que a 1/3', (tester) async {
      await montarEnPantallaPrincipal(tester, repo: RepoListaFalso(canvas()), tamano: _telefono360);
      await tocarAsa(tester, 1);
      final tercio = tester.getSize(find.byKey(ClavesMapaUbicaciones.hoja)).height;
      await tocarAsa(tester, 1);
      final mitad = tester.getSize(find.byKey(ClavesMapaUbicaciones.hoja)).height;

      expect(mitad, greaterThanOrEqualTo(tercio), reason: 'a 1/2 no puede ser más baja que a 1/3');
      expect(mitad, lessThanOrEqualTo(640 / 2 + 0.5));
    });

    test('AlturaHoja.alto: la reserva nunca deja la hoja más baja que la minimizada', () {
      for (final escala in [1.0, 2.0]) {
        final minimizada = AlturaHoja.altoMinimizada(TextScaler.linear(escala));
        for (final altura in AlturaHoja.values) {
          for (final disponible in [100.0, 200.0, 300.0, 480.0, 800.0]) {
            final alto = altura.alto(
              pantalla: 640,
              disponible: disponible,
              escala: TextScaler.linear(escala),
              reserva: 192,
            );
            expect(alto, greaterThanOrEqualTo(minimizada), reason: '$altura $disponible $escala');
          }
        }
      }
    });
  });

  group('QA #199 r2 · casos límite del aviso en horizontal (la app no fija la orientación)', () {
    // skip: pregunta «Horizontal» (`mobile-294-p1-horizontal`, para Cristian: fijar la app en
    // vertical o diseñar el horizontal) — en horizontal (640x360) «Referencias» queda tapado: la zona
    // del aviso mide 0 dp (`libre = max(0, …)`) y el chip, que vive ahí, no se toca.
    testWidgets('en 640x360 «Referencias» y «Mi ubicación» se pueden tocar', (tester) async {
      await montarEnPantallaPrincipal(
        tester,
        repo: RepoListaFalso(canvas()),
        tamano: const Size(640, 360),
      );

      expect(tester.takeException(), isNull);
      expect(motivoInaccesible(tester, chipReferencias), isNull, reason: '«Referencias»');
      expect(
        motivoInaccesible(tester, find.byKey(ClavesMapaUbicaciones.miUbicacion)),
        isNull,
        reason: '«Mi ubicación»',
      );
    }, skip: true);

    // skip: pregunta «Horizontal» (`mobile-294-p1-horizontal`) — en horizontal (640x360) la tarjeta
    // «Sin conexión» queda en una zona de 0 dp: el colportor no ve el aviso ni puede tocar «Activar
    // datos» / «Descargar mapa».
    testWidgets(
      'en 640x360 sin conexión el aviso sigue a la vista y «Activar datos» se puede tocar',
      (tester) async {
        await escenaSinConexion(tester, const Size(640, 360));

        expect(tester.takeException(), isNull);
        expect(find.byKey(ClavesAvisoMapa.sinConexion), findsOneWidget);
        expect(await _llegarConElDedo(tester, _activarDatos), isNull);
      },
      skip: true,
    );
  });

  group('QA #199 r2 · M2: el aviso de «ya la registró otro colportor»', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('se anuncia (liveRegion), entra entero y no desborda · 360x640 · texto $escala', (
        tester,
      ) async {
        await montarMapaUbicaciones(
          tester,
          repo: RepoListaFalso(canvas()),
          tamano: _telefono360,
          escala: escala,
          salidaAlta: const UbicacionReutilizada('de-otro'),
        );

        await tester.tap(botonNueva);
        await asentarLista(tester);

        final texto = find.text(TextosMapaUbicaciones.ubicacionDeOtroColportor);
        expect(texto, findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          find.ancestor(
            of: texto,
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true,
            ),
          ),
          findsWidgets,
          reason: 'el aviso se anuncia con el lector de pantalla',
        );
        final snack = tester.getRect(find.byType(SnackBar));
        expect(snack.left, greaterThanOrEqualTo(0));
        expect(snack.right, lessThanOrEqualTo(360));
        expect(snack.bottom, lessThanOrEqualTo(640));
        // Se va solo (no deja nada colgado sobre «Nueva»).
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      });
    }
  });
}
