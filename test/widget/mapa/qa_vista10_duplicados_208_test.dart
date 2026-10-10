// QA de la vista 10 «Posibles duplicados» (HU-UBI-006, #208). Complementa los tests del implementador
// (`posibles_duplicados_page_test.dart`, que cubre los criterios y los casos límite de cada acción)
// con lo que ellos no miden:
//
// - el canvas completo con SUS datos (Italia, Michigan «bis» y Mataojo edificio + casa), literal;
// - la matriz 360×640 y 412×915 × texto 1.0 y 2.0 × cada estado de la pantalla: sin overflow, sin
//   texto fuera de los costados, tamaño de toque (Android 48 dp, iOS 44 dp), etiquetas y capturas
//   PNG con las fuentes reales (`.dart_tool/qa_capturas/`, nunca se commitean);
// - contraste de los pares de colores de la pantalla (AA);
// - lector de pantalla (anuncios, `accessibleNavigation`), reentrada y casos límite de datos.
//
// Un test que documenta un hallazgo va con `skip` y el comentario `// skip: issue #208 — <motivo>`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/duplicados_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_comparar_duplicado.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart'
    show ColoresAlta;
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart'
    show ColoresLista;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show situacionSinConexion;
import '../../helpers/duplicados_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/qa_vista10_arnes.dart';

const _nbsp = ' ';
const _ocho = Duration(seconds: 8);

// ------------------------------------------------------------------------------------------------
// Los datos del canvas, tal cual los dibuja `10 Posibles Duplicados.dc.html`.
// ------------------------------------------------------------------------------------------------
const _parItalia = 'ub-a|ub-b';
const _parMichigan = 'ub-c|ub-d';
const _parMataojo = 'ub-e|ub-f';

/// Los tres pares del canvas 10·01:
///
/// - Av. Italia 1234 (A: Casa · 2 espacios, B: Casa · 1 espacio), «Misma calle y número a 12 m»;
/// - Michigan 1540 y «Michigan 1540 bis» (Casa · 1 espacio cada una), «A menos de 5 m a 3 m»;
/// - Mataojo 2044 (A: Edificio · 6 deptos, B: Casa · 1 espacio), «Misma calle y número a 3 m».
DuplicadosEnMemoria _datosCanvas() {
  final datos = DuplicadosEnMemoria();
  final vieja = DateTime.utc(2026, 8, 1, 10);
  final nueva = DateTime.utc(2026, 8, 5, 10);
  datos
    ..agregar(ubicacionDuplicable('ub-a', creada: vieja), espacios: 2)
    ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 12, creada: nueva))
    ..agregar(
      ubicacionDuplicable(
        'ub-c',
        metrosAlNorte: 1000,
        calle: 'Michigan',
        numero: '1540',
        creada: vieja,
      ),
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-d',
        metrosAlNorte: 1003,
        calle: 'Michigan',
        numero: '1540 bis',
        creada: nueva,
      ),
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-e',
        metrosAlNorte: 2000,
        calle: 'Mataojo',
        numero: '2044',
        tipo: TipoUbicacion.edificio,
        creada: vieja,
      ),
      espacios: 6,
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-f',
        metrosAlNorte: 2003,
        calle: 'Mataojo',
        numero: '2044',
        creada: nueva,
      ),
    );
  datos.estados['ub-a'] = EstadoCasa.entrevistaAgendada;
  datos.estados['ub-b'] = EstadoCasa.sinVisita;
  datos.estados['ub-c'] = EstadoCasa.noContesto;
  datos.estados['ub-d'] = EstadoCasa.noContesto;
  datos.estados['ub-e'] = EstadoCasa.entrevistaHecha;
  datos.estados['ub-f'] = EstadoCasa.sinVisita;
  return datos;
}

/// Un solo par con textos largos, emoji y un edificio de muchos deptos.
DuplicadosEnMemoria _datosExtremos() {
  const calle = 'Avenida Doctor José Gervasio Artigas y Presidente Tomás Berreta 🙂';
  return DuplicadosEnMemoria()
    ..agregar(
      ubicacionDuplicable(
        'ub-a',
        calle: calle,
        numero: '12345 bis apto 1204',
        tipo: TipoUbicacion.edificio,
      ),
      espacios: 128,
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-b',
        metrosAlNorte: 3,
        calle: calle,
        numero: '12345 bis apto 1204',
        creada: DateTime.utc(2026, 9, 2),
      ),
    );
}

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Monta la app con un botón «abrir» que lleva a «Posibles duplicados», y la abre.
Future<void> _montar(
  WidgetTester tester,
  DuplicadosEnMemoria datos, {
  double escala = 1,
  Size tamano = telefonoChico208,
  SituacionMapa? situacion,
  bool lector = false,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(datos.cerrar);
  await cargarFuentes208(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesDuplicados(datos, conMapa: true, situacion: situacion),
      child: RepaintBoundary(
        key: raizCaptura208,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(escala), accessibleNavigation: lector),
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
    ),
  );
  await _abrirPantalla(tester);
}

Future<void> _transicion(WidgetTester tester) async {
  await _asentar(tester);
  await tester.pump(const Duration(seconds: 1));
  await _asentar(tester);
}

Future<void> _abrirPantalla(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('abrir')));
  await _transicion(tester);
}

Future<void> _volver(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('duplicados_volver')));
  await _transicion(tester);
}

Future<void> _desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void _prueba(String descripcion, Future<void> Function(WidgetTester tester) cuerpo, {bool? skip}) {
  testWidgets(descripcion, (tester) async {
    final semantica = tester.ensureSemantics();
    await cuerpo(tester);
    await _desmontar(tester);
    semantica.dispose();
  }, skip: skip);
}

Finder _revisar(String clave) => find.byKey(Key('revisar_$clave'));
Finder _par(String clave) => find.byKey(Key('par_$clave'));
final _conservarYUnir = find.byKey(const Key('comparar_conservar_y_unir'));
final _sonDistintos = find.byKey(const Key('comparar_son_distintos'));
final _despues = find.byKey(const Key('comparar_despues'));
final _hoja = find.byType(HojaCompararDuplicado);
final _deshacer = find.text('Deshacer');

Future<void> _tocar(WidgetTester tester, Finder f) async {
  // La lista se arma de a poco: con texto grande lo de más abajo todavía no existe y hay que bajar.
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _asentar(tester);
}

Future<void> _revisarPar(WidgetTester tester, String clave) => _tocar(tester, _revisar(clave));

// ------------------------------------------------------------------------------------------------
// Los estados de la matriz.
// ------------------------------------------------------------------------------------------------
class _Estado {
  const _Estado(this.nombre, this.datos, this.llegar, {this.situacion, this.lector = false});

  final String nombre;
  final DuplicadosEnMemoria Function() datos;
  final Future<void> Function(WidgetTester tester, DuplicadosEnMemoria datos) llegar;
  final SituacionMapa? situacion;
  final bool lector;
}

Future<void> _nada(WidgetTester tester, DuplicadosEnMemoria datos) async {}

final _estados = <_Estado>[
  const _Estado('10-01-lista-3-pares', _datosCanvas, _nada),
  const _Estado('10-01-lista-sin-conexion', _datosCanvas, _nada, situacion: situacionSinConexion),
  _Estado('estado-cargando', () => _datosCanvas()..lecturaColgada = true, _nada),
  const _Estado('estado-vacio', DuplicadosEnMemoria.new, _nada),
  _Estado(
    'estado-error-lectura',
    () => _datosCanvas()..errorDeLectura = StateError('disco'),
    _nada,
  ),
  const _Estado('10-01-extremos', _datosExtremos, _nada),
  _Estado('10-02-hoja-italia-D1', _datosCanvas, (t, d) => _revisarPar(t, _parItalia)),
  _Estado('10-02-hoja-michigan-cercania', _datosCanvas, (t, d) => _revisarPar(t, _parMichigan)),
  _Estado('10-02-hoja-mataojo-edificio-casa', _datosCanvas, (t, d) => _revisarPar(t, _parMataojo)),
  _Estado('10-02-hoja-extremos', _datosExtremos, (t, d) => _revisarPar(t, 'ub-a|ub-b')),
  _Estado('10-02-hoja-editar-uno', _datosCanvas, (t, d) async {
    await _revisarPar(t, _parMichigan);
    await _tocar(t, find.byKey(const Key('comparar_editar_uno')));
  }),
  _Estado(
    '10-02-hoja-falla-al-decidir',
    () => _datosCanvas()..falloAlDecidir = const FailureInesperado(),
    (t, d) async {
      await _revisarPar(t, _parMichigan);
      await _tocar(t, _sonDistintos);
    },
  ),
  _Estado('10-03-par-resuelto-deshacer', _datosCanvas, (t, d) async {
    await _revisarPar(t, _parItalia);
    await _tocar(t, _conservarYUnir);
  }),
  _Estado('10-03-par-resuelto-lector', _datosCanvas, (t, d) async {
    await _revisarPar(t, _parItalia);
    await _tocar(t, _conservarYUnir);
  }, lector: true),
  _Estado('10-03-falla-de-union', () => _datosCanvas()..falloAlUnir = const FailureInesperado(), (
    t,
    d,
  ) async {
    await _revisarPar(t, _parItalia);
    await _tocar(t, _conservarYUnir);
    await t.pump(_ocho);
    await _asentar(t);
  }),
  _Estado(
    '10-03-falla-conservada-de-baja',
    () => _datosCanvas()..falloAlUnir = const FailureConservadaDeBaja(),
    (t, d) async {
      await _revisarPar(t, _parItalia);
      await _tocar(t, _conservarYUnir);
      await t.pump(_ocho);
      await _asentar(t);
    },
  ),
];

/// Las tres guías de accesibilidad de Flutter menos el contraste (que con las fuentes reales no es
/// fiable: el contraste se mide aparte, par de colores por par de colores).
Future<List<String>> _guias(WidgetTester tester) async {
  final fallas = <String>[];
  Future<void> probar(String nombre, AccessibilityGuideline guia) async {
    try {
      await expectLater(tester, meetsGuideline(guia));
    } on TestFailure catch (e) {
      fallas.add('$nombre: ${e.message}');
    }
  }

  await probar('android 48dp', androidTapTargetGuideline);
  await probar('ios 44dp', iOSTapTargetGuideline);
  await probar('etiquetas', labeledTapTargetGuideline);
  return fallas;
}

void main() {
  // ----------------------------------------------------------------------------------------------
  // Ítem 0 · Cobertura del canvas con sus datos
  // ----------------------------------------------------------------------------------------------
  group('Canvas 10 con sus datos', () {
    _prueba('10·01: las tres tarjetas dicen lo mismo que el canvas (motivo, distancia, A y B)', (
      tester,
    ) async {
      await _montar(tester, _datosCanvas());

      expect(find.text('3 para revisar'), findsOneWidget);
      expect(find.text('Misma calle y número'), findsNWidgets(2));
      expect(find.text('A menos de 5 m'), findsOneWidget);
      expect(find.text('a 12${_nbsp}m'), findsOneWidget);
      expect(find.text('a 3${_nbsp}m'), findsNWidgets(2));
      // Av. Italia: dos casas de la misma dirección.
      expect(find.text('Av. Italia 1234'), findsNWidgets(2));
      expect(find.text('Casa · 2 espacios'), findsOneWidget);
      // Michigan 1540 y «Michigan 1540 bis».
      expect(find.text('Michigan 1540'), findsOneWidget);
      expect(find.text('Michigan 1540 bis'), findsOneWidget);
      // Mataojo: un edificio de 6 deptos y una casa.
      expect(find.text('Mataojo 2044'), findsNWidgets(2));
      expect(find.text('Edificio · 6 deptos'), findsOneWidget);
      // «Casa · 1 espacio»: B de Italia, A y B de Michigan, B de Mataojo.
      expect(find.text('Casa · 1 espacio'), findsNWidgets(4));
      expect(find.text('Revisar'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    _prueba('10·01: cada fila del par lleva el estado de su casa para el lector de pantalla', (
      tester,
    ) async {
      await _montar(tester, _datosCanvas());

      expect(
        find.bySemanticsLabel(
          RegExp(r'Ubicación A: Av\. Italia 1234, Casa · 2 espacios, Entrevista agendada'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'Ubicación B: Av\. Italia 1234, Casa · 1 espacio, Sin visita'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'Ubicación A: Mataojo 2044, Edificio · 6 deptos, Entrevista hecha'),
        ),
        findsOneWidget,
      );
    });

    _prueba('10·02: la hoja de Michigan (A menos de 5 m) pregunta con el motivo y la distancia, y '
        'ofrece "Son distintos"', (tester) async {
      await _montar(tester, _datosCanvas());
      await _revisarPar(tester, _parMichigan);

      expect(
        find.textContaining('A menos de 5 m, a 3${_nbsp}m.', findRichText: true),
        findsOneWidget,
      );
      expect(_sonDistintos, findsOneWidget);
      expect(find.byKey(const Key('comparar_direccion_unica')), findsNothing);
      expect(_conservarYUnir, findsOneWidget);
      expect(_despues, findsOneWidget);
    });

    _prueba('10·02: la hoja de Mataojo (edificio y casa) se puede unir: el edificio queda como A', (
      tester,
    ) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parMataojo);

      expect(
        find.descendant(of: _hoja, matching: find.text('Edificio · 6 deptos')),
        findsOneWidget,
      );
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.uniones, [(conservadaId: 'ub-e', duplicadaId: 'ub-f')]);
    });

    _prueba('10·03: el aviso lleva el texto literal del canvas y "2 para revisar"', (tester) async {
      await _montar(tester, _datosCanvas());
      await _revisarPar(tester, _parItalia);
      await _tocar(tester, _conservarYUnir);

      expect(find.text('Las dos Av. Italia 1234 quedaron unidas en una.'), findsOneWidget);
      expect(_deshacer, findsOneWidget);
      expect(find.text('2 para revisar'), findsOneWidget);
    });
  });

  // ----------------------------------------------------------------------------------------------
  // Ítems 2, 6, 7 y 9 · matriz de tamaños × texto × estado, con capturas
  // ----------------------------------------------------------------------------------------------
  group('Matriz 360×640 y 412×915 × texto 1.0 y 2.0', () {
    for (final tamano in [telefonoChico208, telefonoGrande208]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in _estados) {
          final etiqueta = '${tamano.width.toInt()}x${tamano.height.toInt()}-x$escala';
          testWidgets('${estado.nombre} · $etiqueta: sin overflow, toques de 48/44 dp, etiquetas', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            final datos = estado.datos();
            await _montar(
              tester,
              datos,
              tamano: tamano,
              escala: escala,
              situacion: estado.situacion,
              lector: estado.lector,
            );
            await estado.llegar(tester, datos);

            expect(tester.takeException(), isNull, reason: 'overflow o excepción de layout');
            expectSinTextoFueraDeLosCostados208(tester, tamano);
            final fallas = await _guias(tester);
            await capturar208(tester, '${estado.nombre}_$etiqueta');
            // La hoja es larga con texto grande: también el pie, donde están los botones.
            if (find.byType(HojaCompararDuplicado).evaluate().isNotEmpty &&
                _despues.evaluate().isNotEmpty) {
              await tester.ensureVisible(_despues);
              await tester.pump(const Duration(milliseconds: 200));
              await capturar208(tester, '${estado.nombre}_${etiqueta}_pie');
            }
            expect(fallas, isEmpty);
            await _desmontar(tester);
            semantica.dispose();
          });
        }
      }
    }
  });

  group('Aviso «N posibles duplicados · Revisar» de la Lista (matriz)', () {
    for (final tamano in [telefonoChico208, telefonoGrande208]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('${tamano.width.toInt()}x${tamano.height.toInt()} · x$escala', (tester) async {
          final semantica = tester.ensureSemantics();
          tester.view.physicalSize = tamano;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await cargarFuentes208(tester);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                ...overridesLista(repo: RepoListaFalso([filaLista('u1'), filaLista('u2')])),
                cantidadParesParaRevisarProvider.overrideWith((ref, colportorId) => 123),
              ],
              child: RepaintBoundary(
                key: raizCaptura208,
                child: MaterialApp(
                  theme: temaClaro(),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
                    child: child!,
                  ),
                  home: const Scaffold(body: ListaUbicacionesPage(colportorId: 'col-1')),
                ),
              ),
            ),
          );
          await _asentar(tester);

          expect(tester.takeException(), isNull);
          expectSinTextoFueraDeLosCostados208(tester, tamano);
          final fallas = await _guias(tester);
          await capturar208(
            tester,
            'lista-aviso_${tamano.width.toInt()}x${tamano.height.toInt()}-x$escala',
          );
          expect(fallas, isEmpty);
          semantica.dispose();
        });
      }
    }
  });

  // ----------------------------------------------------------------------------------------------
  // Ítem 6 · contraste AA de los pares de colores de la pantalla
  // ----------------------------------------------------------------------------------------------
  group('Contraste de los pares de colores', () {
    const blanco = Colors.white;

    test('el texto secundario de las filas (12.5 px) sobre la tarjeta blanca llega a 4.5:1', () {
      expect(contraste208(ColoresLista.grisEstado, blanco), greaterThanOrEqualTo(4.5));
    });

    // El gris que la fila PINTA de verdad (no un token): la opción elegida de "¿Cuál conservar?" es azul
    // claro #E6EEF8, donde el gris de la Lista (#6B7688) daba 3.9:1; el canvas usa #5B6B82 (4.6:1).
    _prueba('el texto secundario sobre la opción elegida (azul claro) llega a 4.5:1', (
      tester,
    ) async {
      await _montar(tester, _datosCanvas());
      await _revisarPar(tester, _parMichigan);

      Color colorDelResumen(String opcion) {
        final resumen = find.descendant(
          of: find.byKey(Key(opcion)),
          matching: find.textContaining('Casa'),
        );
        return tester.widget<Text>(resumen).style!.color!;
      }

      expect(
        contraste208(colorDelResumen('comparar_opcion_primera'), ColoresAlta.azulFondo),
        greaterThanOrEqualTo(4.5),
        reason: 'la elegida (A) va sobre el azul claro',
      );
      expect(
        contraste208(colorDelResumen('comparar_opcion_segunda'), blanco),
        greaterThanOrEqualTo(4.5),
        reason: 'la otra (B) va sobre blanco',
      );
    });

    test('el gris del canvas (#5B6B82) llega a 4.5:1 sobre blanco y sobre el azul claro', () {
      const canvas = Color(0xFF5B6B82);
      expect(contraste208(canvas, blanco), greaterThanOrEqualTo(4.5));
      expect(contraste208(canvas, ColoresAlta.azulFondo), greaterThanOrEqualTo(4.5));
    });

    test('la pastilla del motivo (marrón sobre ámbar claro) llega a 4.5:1', () {
      expect(
        contraste208(const Color(0xFF6E5212), const Color(0xFFFBF1DA)),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('el aviso de la unión (texto blanco y "Deshacer" sobre tinta) llega a 4.5:1', () {
      expect(contraste208(Colors.white, ColoresLista.tinta), greaterThanOrEqualTo(4.5));
      expect(contraste208(const Color(0xFFC9D6EA), ColoresLista.tinta), greaterThanOrEqualTo(4.5));
    });

    test('los enlaces azules ("Reintentar", "Entendido") sobre el aviso blanco llegan a 4.5:1', () {
      expect(contraste208(ColoresAlta.azul, blanco), greaterThanOrEqualTo(4.5));
    });

    test('el borde rojo del aviso de falla contra el blanco llega a 3:1 (componente gráfico)', () {
      expect(contraste208(ColoresAlta.rojo, blanco), greaterThanOrEqualTo(3));
    });

    test('la letra A/B (blanca sobre tinta) llega a 4.5:1', () {
      expect(contraste208(Colors.white, ColoresLista.tinta), greaterThanOrEqualTo(4.5));
    });
  });

  // ----------------------------------------------------------------------------------------------
  // Ítems 2, 5 y 6 · lector de pantalla y navegación
  // ----------------------------------------------------------------------------------------------
  group('Lector de pantalla y navegación', () {
    _prueba('la falla de la unión se anuncia (liveRegion) y deja "Reintentar" a mano', (
      tester,
    ) async {
      final datos = _datosCanvas()..falloAlUnir = const FailureInesperado();
      await _montar(tester, datos);
      await _revisarPar(tester, _parItalia);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(
        find.ancestor(
          of: find.text('No se pudo marcar como duplicado. Probá de nuevo.'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsWidgets,
      );
      expect(find.byKey(const Key('duplicados_reintentar_union')), findsOneWidget);
    });

    _prueba('con lector de pantalla el aviso con "Deshacer" no se cierra solo antes de los 8 s '
        'y se va cuando la unión se hace', (tester) async {
      final datos = _datosCanvas();
      await _montar(tester, datos, lector: true);
      await _revisarPar(tester, _parItalia);
      await _tocar(tester, _conservarYUnir);

      await tester.pump(const Duration(seconds: 7));
      expect(_deshacer, findsOneWidget);
      expect(datos.uniones, isEmpty);

      await tester.pump(const Duration(milliseconds: 1500));
      await _asentar(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(datos.uniones, hasLength(1));
      expect(_deshacer, findsNothing, reason: 'no queda un "Deshacer" de una unión ya hecha');
    });

    _prueba('"Deshacer" tocado a los 7,9 s evita la unión', (tester) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parItalia);
      await _tocar(tester, _conservarYUnir);
      // `_tocar` ya dejó correr 480 ms: con estos 7,4 s el toque cae a los 7,9 s.
      await tester.pump(const Duration(milliseconds: 7400));

      await tester.tap(_deshacer);
      await tester.pump(const Duration(seconds: 20));
      await _asentar(tester);

      expect(datos.uniones, isEmpty);
      expect(find.text('3 para revisar'), findsOneWidget);
    });

    _prueba('"Deshacer" tocado dos veces seguidas no rompe nada y el par queda sin unir', (
      tester,
    ) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parItalia);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(_deshacer);
      await tester.tap(_deshacer, warnIfMissed: false);
      await tester.pump(const Duration(seconds: 20));
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      expect(datos.uniones, isEmpty);
      expect(find.text('3 para revisar'), findsOneWidget);
    });

    _prueba('el gesto de volver del sistema cierra la hoja sin guardar y otro, la pantalla', (
      tester,
    ) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parMichigan);
      expect(_hoja, findsOneWidget);

      await tester.binding.handlePopRoute();
      await _transicion(tester);
      expect(_hoja, findsNothing);
      expect(find.byType(PosiblesDuplicadosPage), findsOneWidget);
      expect(datos.decisiones, isEmpty);

      await tester.binding.handlePopRoute();
      await _transicion(tester);
      expect(find.byType(PosiblesDuplicadosPage), findsNothing);
    });

    // skip: issue #340 — la unión que falla después de salir de la pantalla no deja rastro: el
    // provider se descarta con la página, la colportora vio "unidas en una" y al volver no se le avisa.
    // Decidido (mapa §2): hoy sin aviso; el aviso "No pudimos unir …" en la Lista va al #340.
    _prueba(
      'si la unión falla estando yo en otra pantalla, al volver el par sigue y se me avisa',
      (tester) async {
        final datos = _datosCanvas()..falloAlUnir = const FailureInesperado();
        await _montar(tester, datos);
        await _revisarPar(tester, _parItalia);
        await _tocar(tester, _conservarYUnir);
        await tester.pump(const Duration(seconds: 1));
        await _volver(tester);
        await tester.pump(_ocho);
        await _asentar(tester);

        await _abrirPantalla(tester);

        expect(_par(_parItalia), findsOneWidget, reason: 'la unión no se hizo: el par sigue');
        expect(
          find.byKey(const Key('duplicados_falla_union')),
          findsOneWidget,
          reason: 'la colportora vio "unidas en una" y la unión falló: tiene que enterarse',
        );
      },
      skip: true,
    );

    _prueba('"Conservar" B invierte quién queda: la unión va de A hacia B', (tester) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parMichigan);

      await _tocar(tester, find.byKey(const Key('comparar_opcion_segunda')));
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.uniones, [(conservadaId: 'ub-d', duplicadaId: 'ub-c')]);
    });
  });

  // ----------------------------------------------------------------------------------------------
  // Ítem 5b · casos límite de datos y de tiempo
  // ----------------------------------------------------------------------------------------------
  group('Casos límite', () {
    _prueba(
      'un puerto roto (lanza en vez de devolver una falla) deja el aviso rojo y nada trabado',
      (tester) async {
        final datos = _datosCanvas()..lanzaAlUnir = StateError('disco lleno');
        await _montar(tester, datos);
        await _revisarPar(tester, _parItalia);
        await _tocar(tester, _conservarYUnir);
        await tester.pump(_ocho);
        await _asentar(tester);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('duplicados_falla_union')), findsOneWidget);
        expect(find.text('3 para revisar'), findsOneWidget, reason: 'nada cambió: el par vuelve');
        expect(tester.widget<FilledButton>(_revisar(_parItalia)).onPressed, isNotNull);

        datos.lanzaAlUnir = null;
        await _tocar(tester, find.byKey(const Key('duplicados_reintentar_union')));
        expect(datos.uniones, hasLength(2));
        expect(find.text('2 para revisar'), findsOneWidget);
      },
    );

    _prueba('"Son distintos" no vuelve a proponerse al salir y volver a entrar', (tester) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parMichigan);
      await _tocar(tester, _sonDistintos);
      await _volver(tester);

      await _abrirPantalla(tester);

      expect(_par(_parMichigan), findsNothing);
      expect(find.text('2 para revisar'), findsOneWidget);
    });

    _prueba(
      'un solo par: el título dice "1 para revisar" y el aviso de la Lista iría en singular',
      (tester) async {
        final datos = DuplicadosEnMemoria()
          ..agregar(ubicacionDuplicable('ub-a'))
          ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 3));
        await _montar(tester, datos);

        expect(find.text('1 para revisar'), findsOneWidget);
      },
    );

    _prueba('textos largos, emoji y 128 deptos a 200 %: se leen enteros y se puede unir', (
      tester,
    ) async {
      final datos = _datosExtremos();
      await _montar(tester, datos, escala: 2);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Presidente Tomás Berreta 🙂', findRichText: true), findsWidgets);
      expect(find.text('Edificio · 128 deptos'), findsOneWidget);

      await _revisarPar(tester, 'ub-a|ub-b');
      expect(tester.takeException(), isNull);
      await _tocar(tester, _conservarYUnir);
      expect(find.textContaining('quedaron unidas en una.', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _prueba('un par que se resuelve desde afuera con la hoja abierta no deja "Conservar" tocable', (
      tester,
    ) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parItalia);

      datos.darDeBaja('ub-b');
      await _asentar(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      // Con el par resuelto, o la hoja se cierra o no deja unir algo que ya no existe.
      if (_conservarYUnir.evaluate().isNotEmpty) {
        await tester.tap(_conservarYUnir, warnIfMissed: false);
        await tester.pump(_ocho);
        await _asentar(tester);
        expect(datos.uniones, isEmpty, reason: 'no se une un par que ya no es par');
      }
    });
  });

  // ----------------------------------------------------------------------------------------------
  // Ítem 6 · nombre de lo que se toca (labeledTapTargetGuideline) en la hoja y en «Editar uno»
  // ----------------------------------------------------------------------------------------------
  group('Nombre de lo que se toca en la hoja', () {
    _prueba('cada opción de "¿Cuál conservar?" tiene su nombre en el nodo que se toca', (
      tester,
    ) async {
      await _montar(tester, _datosCanvas());
      await _revisarPar(tester, _parMichigan);

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    _prueba('cada opción de "¿Cuál querés editar?" tiene su nombre en el nodo que se toca', (
      tester,
    ) async {
      await _montar(tester, _datosCanvas());
      await _revisarPar(tester, _parMichigan);
      await _tocar(tester, find.byKey(const Key('comparar_editar_uno')));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
