// Vista 10 «Posibles duplicados» (HU-UBI-006, #208): un test por artboard (10·01 la lista de pares,
// 10·02 comparar el par, 10·03 el par resuelto con «Deshacer»), por estado (cargando, vacío, error,
// sin conexión, éxito), por aviso literal de la HU y por caso límite (doble toque, falla a mitad de la
// acción, dos acciones seguidas, volver y reentrar, datos límite y texto a 200 %).
//
// Las ubicaciones y las decisiones están en memoria (`DuplicadosEnMemoria`) y el mapa es la vista
// falsa: ningún test espera de verdad, el reloj de los 8 s de «Deshacer» es el de `flutter_test`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_comparar_duplicado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales, situacionSinConexion;
import '../../helpers/duplicados_falsos.dart';

const _nbsp = ' ';
const _ocho = Duration(seconds: 8);

// Las claves de los tres pares del canvas (10·01).
const _parItalia = 'ub-a|ub-b';
const _parArtigas = 'ub-c|ub-d';
const _parFlores = 'ub-e|ub-f';

/// Los tres pares de la vista 10·01, a 1 km uno de otro para que no se crucen:
///
/// - Av. Italia 1234, la misma calle y número a 12 m (D1: sin «Son distintos»);
/// - Bulevar Artigas 880, la misma calle y número a 150 m (admite «Son distintos»);
/// - Gral. Flores 2101 y 2103, a 3 m (admite «Son distintos»).
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
        calle: 'Bulevar Artigas',
        numero: '880',
        creada: vieja,
      ),
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-d',
        metrosAlNorte: 1150,
        calle: 'Bulevar Artigas',
        numero: '880',
        creada: nueva,
      ),
      espacios: 3,
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-e',
        metrosAlNorte: 2000,
        calle: 'Gral. Flores',
        numero: '2101',
        creada: vieja,
      ),
    )
    ..agregar(
      ubicacionDuplicable(
        'ub-f',
        metrosAlNorte: 2003,
        calle: 'Gral. Flores',
        numero: '2103',
        creada: nueva,
      ),
    );
  datos.estados['ub-a'] = EstadoCasa.ventaCompleta;
  return datos;
}

/// [cantidad] pares de a dos, a 1 km uno de otro (una lista larga).
DuplicadosEnMemoria _datosLargos(int cantidad) {
  final datos = DuplicadosEnMemoria();
  for (var i = 0; i < cantidad; i++) {
    final n = i.toString().padLeft(2, '0');
    datos
      ..agregar(
        ubicacionDuplicable(
          'p${n}a',
          metrosAlNorte: i * 1000.0,
          calle: 'Calle $n',
          numero: '${100 + i}',
        ),
      )
      ..agregar(
        ubicacionDuplicable(
          'p${n}b',
          metrosAlNorte: i * 1000.0 + 10,
          calle: 'Calle $n',
          numero: '${100 + i}',
        ),
      );
  }
  return datos;
}

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Monta una pantalla con el botón «abrir» que lleva a «Posibles duplicados», y la abre.
Future<void> _montar(
  WidgetTester tester,
  DuplicadosEnMemoria datos, {
  double escala = 1,
  Size tamano = const Size(390, 844),
  SituacionMapa? situacion,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(datos.cerrar);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesDuplicados(datos, conMapa: true, situacion: situacion),
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
  await _abrirPantalla(tester);
}

/// Deja terminar la transición de página (hasta 800 ms en Android) y lo que se dispara al terminar
/// (por ejemplo, la salida del aviso).
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

/// Saca todo del árbol y deja correr el reloj: lo que quedó esperando se confirma y no queda ningún
/// temporizador pendiente.
Future<void> _desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

/// Un test de widget que desmonta todo al terminar.
void _prueba(String descripcion, Future<void> Function(WidgetTester tester) cuerpo) {
  testWidgets(descripcion, (tester) async {
    await cuerpo(tester);
    await _desmontar(tester);
  });
}

Finder _revisar(String clave) => find.byKey(Key('revisar_$clave'));
Finder _par(String clave) => find.byKey(Key('par_$clave'));
final _conservarYUnir = find.byKey(const Key('comparar_conservar_y_unir'));
final _sonDistintos = find.byKey(const Key('comparar_son_distintos'));
final _despues = find.byKey(const Key('comparar_despues'));
final _hoja = find.byType(HojaCompararDuplicado);
final _avisoDeshacer = find.text('Deshacer');

Future<void> _revisarPar(WidgetTester tester, String clave) async {
  await tester.ensureVisible(_revisar(clave));
  await tester.pump();
  await tester.tap(_revisar(clave));
  await _asentar(tester);
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _asentar(tester);
}

void main() {
  setUpAll(cargarFuentesReales);

  group('10·01 · Lista de pares', () {
    _prueba('dado tres pares, cuando se abre la pantalla, se ve "3 para revisar" con el subtítulo, '
        'el motivo, la distancia, A y B de cada par y un "Revisar" por par', (tester) async {
      await _montar(tester, _datosCanvas());

      expect(find.byKey(const Key('duplicados_titulo')), findsOneWidget);
      expect(find.text('3 para revisar'), findsOneWidget);
      expect(
        find.text('Son ubicaciones tuyas con la misma calle y número, o a menos de 5${_nbsp}m.'),
        findsOneWidget,
      );
      expect(find.text('POSIBLES DUPLICADOS'), findsOneWidget);
      for (final clave in [_parItalia, _parArtigas, _parFlores]) {
        expect(_par(clave), findsOneWidget, reason: clave);
        expect(_revisar(clave), findsOneWidget, reason: clave);
      }
      expect(find.text('Revisar'), findsNWidgets(3));
      expect(find.text('Misma calle y número'), findsNWidgets(2));
      expect(find.text('A menos de 5 m'), findsOneWidget);
      expect(find.text('a 12${_nbsp}m'), findsOneWidget);
      expect(find.text('a 150${_nbsp}m'), findsOneWidget);
      expect(find.text('a 3${_nbsp}m'), findsOneWidget);
      expect(find.text('A'), findsNWidgets(3));
      expect(find.text('B'), findsNWidgets(3));
      expect(find.text('Av. Italia 1234'), findsNWidgets(2));
      expect(find.text('Gral. Flores 2101'), findsOneWidget);
      expect(find.text('Gral. Flores 2103'), findsOneWidget);
      // La más vieja es A, y se ve cuántos espacios tiene cada una.
      expect(find.text('Casa · 2 espacios'), findsOneWidget);
      expect(find.text('Casa · 3 espacios'), findsOneWidget);
      expect(find.text('Casa · 1 espacio'), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });

    _prueba('dado un solo par, cuando se abre la pantalla, el título dice "1 para revisar"', (
      tester,
    ) async {
      final datos = DuplicadosEnMemoria()
        ..agregar(ubicacionDuplicable('ub-a'))
        ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 3));
      await _montar(tester, datos);

      expect(find.text('1 para revisar'), findsOneWidget);
    });

    _prueba('dado la lista, cuando toco "‹", vuelvo a la pantalla de antes', (tester) async {
      await _montar(tester, _datosCanvas());

      await _volver(tester);

      expect(find.byType(PosiblesDuplicadosPage), findsNothing);
      expect(find.byKey(const Key('abrir')), findsOneWidget);
    });

    _prueba('dado que salí de la pantalla, cuando vuelvo a entrar, veo la misma lista', (
      tester,
    ) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _volver(tester);

      await _abrirPantalla(tester);

      expect(find.text('3 para revisar'), findsOneWidget);
      expect(datos.uniones, isEmpty);
    });
  });

  group('Estados que el canvas no dibuja', () {
    _prueba('dado que todavía se está leyendo la lista, se ve "Buscando posibles duplicados" y no '
        'hay nada que tocar', (tester) async {
      final datos = _datosCanvas()..lecturaColgada = true;
      await _montar(tester, datos);

      expect(find.text('Buscando posibles duplicados'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Revisar'), findsNothing);
      expect(find.byKey(const Key('duplicados_vacio')), findsNothing);
    });

    _prueba('dado que no hay pares, se ve "No hay posibles duplicados" y cómo aparecen', (
      tester,
    ) async {
      final datos = DuplicadosEnMemoria()
        ..agregar(ubicacionDuplicable('ub-a'))
        ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 500, calle: 'Otra', numero: '9'));
      await _montar(tester, datos);

      expect(find.byKey(const Key('duplicados_vacio')), findsOneWidget);
      expect(find.text('No hay posibles duplicados'), findsOneWidget);
      expect(
        find.text(
          'Cuando dos de tus ubicaciones tengan la misma calle y número, o estén a menos de 5 m, '
          'aparecen acá.',
        ),
        findsOneWidget,
      );
      expect(find.text('Revisar'), findsNothing);
      expect(find.text('0 para revisar'), findsNothing);
    });

    _prueba(
      'dado que la lectura falla, se avisa y "Reintentar" vuelve a leer: sin quedar trabado',
      (tester) async {
        final datos = _datosCanvas()..errorDeLectura = StateError('disco');
        await _montar(tester, datos);

        expect(find.byKey(const Key('duplicados_error_lectura')), findsOneWidget);
        expect(find.text('No pudimos revisar tus ubicaciones.'), findsOneWidget);
        expect(find.text('Revisar'), findsNothing);

        datos.errorDeLectura = null;
        await _tocar(tester, find.byKey(const Key('duplicados_reintentar_lectura')));

        expect(find.byKey(const Key('duplicados_error_lectura')), findsNothing);
        expect(find.text('3 para revisar'), findsOneWidget);
        expect(datos.lecturas, 2);
      },
    );

    _prueba('dado que no hay conexión, la pantalla funciona igual: todo se lee del teléfono', (
      tester,
    ) async {
      final datos = _datosCanvas();
      await _montar(tester, datos, situacion: situacionSinConexion);

      expect(find.text('3 para revisar'), findsOneWidget);
      await _revisarPar(tester, _parItalia);
      expect(_hoja, findsOneWidget);
      expect(find.text('Sin conexión a internet'), findsNothing);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.uniones, hasLength(1));
    });
  });

  group('10·02 · Comparar el par', () {
    _prueba('dado un par, cuando toco "Revisar", se abre la hoja con la pregunta, el mapa, las dos '
        'ubicaciones, el aviso de la unión y los botones', (tester) async {
      await _montar(tester, _datosCanvas());

      await _revisarPar(tester, _parArtigas);

      expect(_hoja, findsOneWidget);
      expect(find.textContaining('¿Es el mismo lugar?', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('Misma calle y número, a 150${_nbsp}m.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('¿CUÁL CONSERVAR?'), findsOneWidget);
      expect(
        find.descendant(of: _hoja, matching: find.text('Bulevar Artigas 880')),
        findsNWidgets(2),
      );
      expect(
        find.text(
          'Las visitas y los clientes de B pasan a A. B queda como baja con motivo “Duplicado”.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('comparar_distancia')), findsOneWidget);
      expect(find.text('150${_nbsp}m'), findsOneWidget);
      expect(_conservarYUnir, findsOneWidget);
      expect(find.text('Conservar A y unir'), findsOneWidget);
      expect(_sonDistintos, findsOneWidget);
      expect(find.text('Son distintos'), findsOneWidget);
      expect(find.text('Después'), findsOneWidget);
      expect(find.byKey(const Key('comparar_direccion_unica')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    _prueba(
      'dado la misma dirección a menos de 100 m (D1), la hoja dice que no pueden quedar las dos '
      'y no ofrece "Son distintos"',
      (tester) async {
        await _montar(tester, _datosCanvas());

        await _revisarPar(tester, _parItalia);

        expect(_sonDistintos, findsNothing);
        expect(find.byKey(const Key('comparar_direccion_unica')), findsOneWidget);
        expect(
          find.text(
            'Estas dos ubicaciones tienen la misma dirección y no pueden quedar las dos. '
            'Marcá cuál es el duplicado o corregí la dirección de una.',
          ),
          findsOneWidget,
        );
        expect(_conservarYUnir, findsOneWidget);
      },
    );

    _prueba(
      'dado que A es la más vieja, cuando elijo la otra, la letra "A" pasa a la que se conserva',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await _montar(tester, _datosCanvas());
        await _revisarPar(tester, _parItalia);

        // Por defecto se conserva la más vieja (ub-a: 2 espacios y venta completa).
        expect(
          find.bySemanticsLabel(
            RegExp('Ubicación A, la que se conserva: Av. Italia 1234, Casa · 2'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp('Ubicación B, la que queda como baja: Av. Italia 1234, Casa · 1 espacio'),
          ),
          findsOneWidget,
        );

        await _tocar(tester, find.byKey(const Key('comparar_opcion_segunda')));

        expect(
          find.bySemanticsLabel(
            RegExp('Ubicación A, la que se conserva: Av. Italia 1234, Casa · 1 espacio'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp('Ubicación B, la que queda como baja: Av. Italia 1234, Casa · 2'),
          ),
          findsOneWidget,
        );
        semantica.dispose();
      },
    );

    _prueba(
      'dado que elegí conservar la otra, cuando toco "Conservar A y unir", se une esa y se da de '
      'baja la más vieja',
      (tester) async {
        final datos = _datosCanvas();
        await _montar(tester, datos);
        await _revisarPar(tester, _parItalia);

        await _tocar(tester, find.byKey(const Key('comparar_opcion_segunda')));
        await _tocar(tester, _conservarYUnir);
        await tester.pump(_ocho);
        await _asentar(tester);

        expect(datos.uniones, [(conservadaId: 'ub-b', duplicadaId: 'ub-a')]);
      },
    );

    _prueba('dado la hoja, cuando toco "Después", se cierra sin guardar nada y el par sigue en la '
        'lista', (tester) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parFlores);

      await _tocar(tester, _despues);
      await tester.pump(const Duration(seconds: 20));

      expect(_hoja, findsNothing);
      expect(datos.uniones, isEmpty);
      expect(datos.decisiones, isEmpty);
      expect(find.text('3 para revisar'), findsOneWidget);
      expect(_par(_parFlores), findsOneWidget);
    });

    _prueba('dado la hoja de un par, cuando una de las dos ubicaciones se da de baja desde afuera '
        '(el sync), la hoja se cierra sola: ya no es un par', (tester) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parFlores);

      datos.darDeBaja('ub-f');
      await _asentar(tester);

      expect(_hoja, findsNothing);
      expect(find.text('2 para revisar'), findsOneWidget);
      expect(_par(_parFlores), findsNothing);
    });

    _prueba(
      'dado "Editar uno" con el selector "¿Cuál querés editar?" abierto, cuando una de las dos se '
      'da de baja desde afuera, se cierran el selector y la hoja: no queda una hoja sin respuesta',
      (tester) async {
        final datos = _datosCanvas();
        await _montar(tester, datos);
        await _revisarPar(tester, _parFlores);
        await _tocar(tester, find.byKey(const Key('comparar_editar_uno')));
        expect(find.text('¿Cuál querés editar?'), findsOneWidget);

        datos.darDeBaja('ub-f');
        await _transicion(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('¿Cuál querés editar?'), findsNothing);
        expect(_hoja, findsNothing, reason: 'el cierre sacaba el selector y dejaba la hoja');
        expect(find.byType(PosiblesDuplicadosPage), findsOneWidget);
        expect(find.text('2 para revisar'), findsOneWidget);

        // La pantalla sigue respondiendo: se abre la hoja de otro par.
        await _revisarPar(tester, _parItalia);
        expect(_hoja, findsOneWidget);
      },
    );

    _prueba(
      'dado "Editar uno" con la edición abierta, cuando el par deja de existir, no se le saca la '
      'edición a quien escribe y la hoja se cierra al volver',
      (tester) async {
        final datos = _datosCanvas();
        await _montar(tester, datos);
        await _revisarPar(tester, _parFlores);
        await _tocar(tester, find.byKey(const Key('comparar_editar_uno')));
        await tester.tap(find.byKey(const Key('editar_opcion_ub-e')));
        await _transicion(tester);
        expect(find.byType(ModificarUbicacionPage), findsOneWidget);

        datos.darDeBaja('ub-f');
        await _transicion(tester);

        expect(tester.takeException(), isNull);
        expect(find.byType(ModificarUbicacionPage), findsOneWidget, reason: 'la edición sigue');
        expect(find.byType(HojaCompararDuplicado, skipOffstage: false), findsOneWidget);

        await tester.binding.handlePopRoute();
        await _transicion(tester);

        expect(find.byType(ModificarUbicacionPage), findsNothing);
        expect(find.byType(HojaCompararDuplicado, skipOffstage: false), findsNothing);
        expect(find.text('2 para revisar'), findsOneWidget);
      },
    );

    _prueba('dado un par con dos toques seguidos en "Revisar", se abre una sola hoja', (
      tester,
    ) async {
      await _montar(tester, _datosCanvas());

      await tester.tap(_revisar(_parArtigas));
      await tester.tap(_revisar(_parArtigas), warnIfMissed: false);
      await _asentar(tester);

      expect(_hoja, findsOneWidget);
      await _tocar(tester, _despues);
      expect(_hoja, findsNothing);
    });
  });

  group('«Son distintos» e «Ignorar»', () {
    _prueba(
      'dado un par que admite "Son distintos", cuando lo toco, se guarda la decisión, la hoja '
      'se cierra y el par sale de la lista',
      (tester) async {
        final datos = _datosCanvas();
        await _montar(tester, datos);
        await _revisarPar(tester, _parArtigas);

        await _tocar(tester, _sonDistintos);

        expect(datos.decisiones, [
          (clave: _parArtigas, decision: DecisionParDuplicado.conservarAmbos),
        ]);
        expect(_hoja, findsNothing);
        expect(find.text('2 para revisar'), findsOneWidget);
        expect(_par(_parArtigas), findsNothing);
        expect(datos.uniones, isEmpty);
      },
    );

    _prueba('dado "Son distintos", cuando lo toco dos veces seguidas, se guarda una sola vez', (
      tester,
    ) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parFlores);

      await tester.tap(_sonDistintos);
      await tester.tap(_sonDistintos, warnIfMissed: false);
      await _asentar(tester);

      expect(datos.decisiones, hasLength(1));
      expect(_hoja, findsNothing);
    });

    _prueba('dado "Ignorar", cuando lo toco, se esconde el par y la hoja se cierra', (
      tester,
    ) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parItalia);

      await _tocar(tester, find.byKey(const Key('comparar_ignorar')));

      expect(datos.decisiones, [(clave: _parItalia, decision: DecisionParDuplicado.ignorar)]);
      expect(_hoja, findsNothing);
      expect(find.text('2 para revisar'), findsOneWidget);
    });

    _prueba('dado que la decisión no se pudo guardar, la hoja avisa, no se cierra y los botones se '
        'pueden volver a tocar', (tester) async {
      final datos = _datosCanvas()..falloAlDecidir = const FailureInesperado();
      await _montar(tester, datos);
      await _revisarPar(tester, _parFlores);

      await _tocar(tester, _sonDistintos);

      expect(find.byKey(const Key('comparar_falla')), findsOneWidget);
      expect(find.text('No pudimos guardar tu decisión. Probá de nuevo.'), findsOneWidget);
      expect(_hoja, findsOneWidget);
      expect(tester.widget<OutlinedButton>(_sonDistintos).onPressed, isNotNull);
      expect(tester.widget<FilledButton>(_conservarYUnir).onPressed, isNotNull);

      datos.falloAlDecidir = null;
      await _tocar(tester, _sonDistintos);

      expect(_hoja, findsNothing);
      expect(datos.decisiones, hasLength(1));
    });

    _prueba('dado "Editar uno", cuando elijo cuál, se abre la edición de esa ubicación', (
      tester,
    ) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parFlores);

      await _tocar(tester, find.byKey(const Key('comparar_editar_uno')));

      expect(find.text('¿Cuál querés editar?'), findsOneWidget);
      expect(find.byKey(const Key('editar_opcion_ub-e')), findsOneWidget);
      expect(find.byKey(const Key('editar_opcion_ub-f')), findsOneWidget);

      await tester.tap(find.byKey(const Key('editar_opcion_ub-f')));
      await _asentar(tester);

      expect(find.text('¿Cuál querés editar?'), findsNothing);
      expect(find.byType(ModificarUbicacionPage), findsOneWidget);
    });

    _prueba('dado "Editar uno", cuando cancelo, no se abre nada y la hoja sigue', (tester) async {
      await _montar(tester, _datosCanvas());
      await _revisarPar(tester, _parFlores);

      await _tocar(tester, find.byKey(const Key('comparar_editar_uno')));
      await _tocar(tester, find.text('Cancelar'));

      expect(find.text('¿Cuál querés editar?'), findsNothing);
      expect(find.byType(ModificarUbicacionPage), findsNothing);
      expect(_hoja, findsOneWidget);
    });
  });

  group('10·03 · Par resuelto: "Conservar A y unir" con 8 s de "Deshacer"', () {
    _prueba('dado "Conservar A y unir", la hoja se cierra, el par sale de la lista y el aviso dice '
        '"Las dos Av. Italia 1234 quedaron unidas en una." con "Deshacer"', (tester) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parItalia);

      await _tocar(tester, _conservarYUnir);

      expect(_hoja, findsNothing);
      expect(find.text('2 para revisar'), findsOneWidget);
      expect(_par(_parItalia), findsNothing);
      expect(find.text('Las dos Av. Italia 1234 quedaron unidas en una.'), findsOneWidget);
      expect(_avisoDeshacer, findsOneWidget);
    });

    _prueba(
      'dado el aviso, durante los 8 s no cambia nada en la base y pasados los 8 s la unión es '
      'definitiva y el aviso se va',
      (tester) async {
        final datos = _datosCanvas();
        await _montar(tester, datos);
        await _revisarPar(tester, _parItalia);
        await _tocar(tester, _conservarYUnir);

        await tester.pump(const Duration(seconds: 7));
        expect(datos.uniones, isEmpty);
        expect(_avisoDeshacer, findsOneWidget);

        await tester.pump(const Duration(milliseconds: 1500));
        await _asentar(tester);
        await tester.pump(const Duration(seconds: 1));

        expect(datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
        expect(find.text('Las dos Av. Italia 1234 quedaron unidas en una.'), findsNothing);
        expect(find.text('2 para revisar'), findsOneWidget);
      },
    );

    _prueba('dado el aviso, cuando toco "Deshacer", no se une nada y el par vuelve a la lista', (
      tester,
    ) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parItalia);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(const Duration(seconds: 3));

      await _tocar(tester, _avisoDeshacer);
      await tester.pump(const Duration(seconds: 20));
      await _asentar(tester);

      expect(datos.uniones, isEmpty);
      expect(find.text('3 para revisar'), findsOneWidget);
      expect(_par(_parItalia), findsOneWidget);
      expect(find.text('Las dos Av. Italia 1234 quedaron unidas en una.'), findsNothing);
    });

    _prueba('dado "Conservar A y unir" tocado dos veces seguidas, se une una sola vez', (
      tester,
    ) async {
      final datos = _datosCanvas();
      await _montar(tester, datos);
      await _revisarPar(tester, _parItalia);

      await tester.tap(_conservarYUnir);
      await tester.tap(_conservarYUnir, warnIfMissed: false);
      await _asentar(tester);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.uniones, hasLength(1));
    });

    _prueba(
      'dado un par esperando su "Deshacer", cuando uno otro par, el primero queda definitivo y '
      'el aviso pasa al nuevo',
      (tester) async {
        final datos = _datosCanvas();
        await _montar(tester, datos);
        await _revisarPar(tester, _parItalia);
        await _tocar(tester, _conservarYUnir);
        await tester.pump(const Duration(seconds: 2));

        await _revisarPar(tester, _parArtigas);
        await _tocar(tester, _conservarYUnir);

        expect(datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
        expect(find.text('Las dos Av. Italia 1234 quedaron unidas en una.'), findsNothing);
        expect(find.text('Las dos Bulevar Artigas 880 quedaron unidas en una.'), findsOneWidget);
        expect(find.text('1 para revisar'), findsOneWidget);

        await tester.pump(_ocho);
        await _asentar(tester);

        expect(datos.uniones, hasLength(2));
      },
    );

    _prueba(
      'dado un aviso con "Deshacer", cuando salgo de la pantalla, la unión queda definitiva y '
      'el aviso se va',
      (tester) async {
        final datos = _datosCanvas();
        await _montar(tester, datos);
        await _revisarPar(tester, _parItalia);
        await _tocar(tester, _conservarYUnir);
        await tester.pump(const Duration(seconds: 1));

        await _volver(tester);

        expect(datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
        expect(find.text('Las dos Av. Italia 1234 quedaron unidas en una.'), findsNothing);

        await _abrirPantalla(tester);

        expect(find.text('2 para revisar'), findsOneWidget);
        expect(_par(_parItalia), findsNothing);
      },
    );

    _prueba(
      'dado que la unión falla, el par vuelve a la lista con el aviso "No se pudo marcar como '
      'duplicado. Probá de nuevo." y "Reintentar" la hace de nuevo',
      (tester) async {
        final datos = _datosCanvas()..falloAlUnir = const FailureInesperado();
        await _montar(tester, datos);
        await _revisarPar(tester, _parItalia);
        await _tocar(tester, _conservarYUnir);

        await tester.pump(_ocho);
        await _asentar(tester);

        expect(find.byKey(const Key('duplicados_falla_union')), findsOneWidget);
        expect(find.text('No se pudo marcar como duplicado. Probá de nuevo.'), findsOneWidget);
        expect(_par(_parItalia), findsOneWidget, reason: 'nada cambió: el par sigue para revisar');
        expect(find.text('3 para revisar'), findsOneWidget);
        expect(tester.widget<FilledButton>(_revisar(_parItalia)).onPressed, isNotNull);

        datos.falloAlUnir = null;
        await _tocar(tester, find.byKey(const Key('duplicados_reintentar_union')));

        expect(find.byKey(const Key('duplicados_falla_union')), findsNothing);
        expect(datos.uniones, hasLength(2));
        expect(find.text('2 para revisar'), findsOneWidget);
        expect(_par(_parItalia), findsNothing);
      },
    );

    _prueba('dado que la unión falla otra vez al reintentar, el aviso sigue y nada queda trabado', (
      tester,
    ) async {
      final datos = _datosCanvas()..falloAlUnir = const FailureInesperado();
      await _montar(tester, datos);
      await _revisarPar(tester, _parItalia);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);

      await _tocar(tester, find.byKey(const Key('duplicados_reintentar_union')));

      expect(find.byKey(const Key('duplicados_falla_union')), findsOneWidget);
      expect(datos.uniones, hasLength(2));
      expect(_par(_parItalia), findsOneWidget);
      expect(tester.widget<FilledButton>(_revisar(_parItalia)).onPressed, isNotNull);
    });

    _prueba('dado que la que se iba a conservar ya está de baja, el aviso dice que revise el par y '
        'no ofrece "Reintentar"', (tester) async {
      final datos = _datosCanvas()..falloAlUnir = const FailureConservadaDeBaja();
      await _montar(tester, datos);
      await _revisarPar(tester, _parItalia);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(
        find.text(
          'La ubicación que ibas a conservar ya está dada de baja. Revisá el par de nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('duplicados_reintentar_union')), findsNothing);

      await _tocar(tester, find.byKey(const Key('duplicados_descartar_falla')));

      expect(find.byKey(const Key('duplicados_falla_union')), findsNothing);
    });

    _prueba('dado el último par, cuando lo uno, la pantalla pasa a "No hay posibles duplicados" '
        'y el aviso de la falla, si hubo, se sigue viendo', (tester) async {
      final datos = DuplicadosEnMemoria()
        ..agregar(ubicacionDuplicable('ub-a'))
        ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 3))
        ..falloAlUnir = const FailureInesperado();
      await _montar(tester, datos);
      await _revisarPar(tester, 'ub-a|ub-b');
      await _tocar(tester, _conservarYUnir);

      expect(find.byKey(const Key('duplicados_vacio')), findsOneWidget);

      await tester.pump(_ocho);
      await _asentar(tester);

      expect(find.byKey(const Key('duplicados_vacio')), findsNothing);
      expect(find.byKey(const Key('duplicados_falla_union')), findsOneWidget);
      expect(find.text('1 para revisar'), findsOneWidget);
    });
  });

  group('Datos límite y texto grande', () {
    _prueba('dado treinta pares, la lista se desplaza hasta el último y todos se pueden revisar', (
      tester,
    ) async {
      await _montar(tester, _datosLargos(30), tamano: const Size(360, 640));

      expect(find.text('30 para revisar'), findsOneWidget);
      await tester.scrollUntilVisible(
        _revisar('p29a|p29b'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_revisar('p29a|p29b'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _prueba('dado textos largos y la letra al 200 %, ni la lista ni la hoja se desbordan y los '
        'botones llegan a 48', (tester) async {
      final datos = DuplicadosEnMemoria()
        ..agregar(
          ubicacionDuplicable(
            'ub-a',
            calle: 'Avenida General Don José Gervasio Artigas y Doctor Luis Alberto de Herrera',
            numero: '123456789',
          ),
        )
        ..agregar(
          ubicacionDuplicable(
            'ub-b',
            metrosAlNorte: 150,
            calle: 'Avenida General Don José Gervasio Artigas y Doctor Luis Alberto de Herrera',
            numero: '123456789',
          ),
        );
      await _montar(tester, datos, escala: 2, tamano: const Size(360, 640));

      expect(tester.takeException(), isNull);
      expect(tester.getSize(_revisar('ub-a|ub-b')).height, greaterThanOrEqualTo(48));

      await _revisarPar(tester, 'ub-a|ub-b');
      final desplazable = find.descendant(of: _hoja, matching: find.byType(Scrollable)).first;
      for (final boton in [_conservarYUnir, _sonDistintos, _despues]) {
        await tester.scrollUntilVisible(boton, 200, scrollable: desplazable);
        expect(tester.getSize(boton).height, greaterThanOrEqualTo(48), reason: '$boton');
      }
      expect(tester.takeException(), isNull);

      await _tocar(tester, _conservarYUnir);
      expect(tester.takeException(), isNull);
      expect(_avisoDeshacer, findsOneWidget);
      final boton = find.ancestor(of: _avisoDeshacer, matching: find.byType(TextButton));
      expect(tester.getSize(boton).height, greaterThanOrEqualTo(48));
    });

    _prueba('dado un lector de pantalla, los títulos son encabezados y las tarjetas se anuncian '
        'completas', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, _datosCanvas());

      expect(
        find.bySemanticsLabel(RegExp('Ubicación A: Av. Italia 1234, Casa · 2 espacios')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Posibles duplicados'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantica.dispose();
    });
  });
}
