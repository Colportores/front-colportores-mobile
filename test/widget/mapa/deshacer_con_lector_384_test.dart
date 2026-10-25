// «Deshacer» con lector de pantalla (HU-UBI-006, vista 10; issue #384; decisión de Cristian 21/10,
// «Deshacer AA»): con `accessibleNavigation` la unión NO corre contra el reloj de 8 s (WCAG 2.2.1).
// Se hace cuando la persona cierra el aviso, sale de la pantalla o une otro par; «Deshacer» la cancela.
// Sin lector, todo sigue igual: 8 s.
//
// El cierre del aviso con el lector es la acción semántica `dismiss` del SnackBar (el gesto de descartar
// de TalkBack / VoiceOver), no un toque: el aviso no se arrastra (`DismissDirection.none`).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/duplicados_falsos.dart';

const _ocho = Duration(seconds: 8);
const _parItalia = 'ub-a|ub-b';
const _parArtigas = 'ub-c|ub-d';

/// Av. Italia 1234 (A–B, a 12 m) y Bulevar Artigas 880 (C–D, a 150 m), a 1 km uno del otro.
DuplicadosEnMemoria _datos() {
  final vieja = DateTime.utc(2026, 8, 1, 10);
  final nueva = DateTime.utc(2026, 8, 5, 10);
  return DuplicadosEnMemoria()
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
    );
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

/// Monta la app con un botón «abrir» que lleva a «Posibles duplicados», y la abre.
Future<void> _montar(
  WidgetTester tester,
  DuplicadosEnMemoria datos, {
  required bool lector,
  double escala = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(datos.cerrar);
  // El lector se enciende en la plataforma, como en el teléfono: un `MediaQuery` dentro del
  // `MaterialApp.builder` queda dentro del `ScaffoldMessenger`, que seguiría viendo `false`.
  if (lector) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      accessibleNavigation: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
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
  await tester.tap(find.byKey(const Key('abrir')));
  await _transicion(tester);
}

void _prueba(String descripcion, Future<void> Function(WidgetTester tester) cuerpo) {
  testWidgets(descripcion, (tester) async {
    final semantica = tester.ensureSemantics();
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    semantica.dispose();
  });
}

final _conservarYUnir = find.byKey(const Key('comparar_conservar_y_unir'));
final _deshacer = find.text('Deshacer');
final _aviso = find.byType(SnackBar);

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _asentar(tester);
}

/// Abre la hoja del par [clave] y toca «Conservar A y unir».
Future<void> _unir(WidgetTester tester, String clave) async {
  await _tocar(tester, find.byKey(Key('revisar_$clave')));
  await _tocar(tester, _conservarYUnir);
  // La hoja se va y el aviso termina de entrar.
  await tester.pump(const Duration(milliseconds: 500));
}

/// La persona descarta el aviso con el lector (acción semántica `dismiss`).
Future<void> _descartarElAviso(WidgetTester tester) async {
  tester.semantics.performAction(
    find.semantics.byAction(SemanticsAction.dismiss).first,
    SemanticsAction.dismiss,
  );
  await _transicion(tester);
}

void main() {
  group('Escenario: con lector de pantalla la unión espera a que se cierre el aviso', () {
    _prueba('dado el lector encendido, cuando toco "Conservar A y unir" y no hago nada, pasan los '
        '8 s, 30 s y 5 min y no se une nada: el aviso con "Deshacer" sigue', (tester) async {
      final datos = _datos();
      await _montar(tester, datos, lector: true);

      await _unir(tester, _parItalia);
      for (final espera in [_ocho, const Duration(seconds: 30), const Duration(minutes: 5)]) {
        await tester.pump(espera);
        expect(datos.uniones, isEmpty, reason: 'a $espera todavía no se cerró el aviso');
        expect(_aviso, findsOneWidget);
        expect(_deshacer, findsOneWidget);
      }
    });

    _prueba('cuando cierro el aviso (descartar del lector), la unión se hace una sola vez y el par '
        'sale de la lista', (tester) async {
      final datos = _datos();
      await _montar(tester, datos, lector: true);
      await _unir(tester, _parItalia);
      await tester.pump(const Duration(seconds: 20));
      expect(datos.uniones, isEmpty);

      await _descartarElAviso(tester);

      expect(datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
      expect(_aviso, findsNothing);
      expect(_deshacer, findsNothing, reason: 'no queda un "Deshacer" de una unión ya hecha');
      expect(find.text('1 para revisar'), findsOneWidget);
      // Un segundo descarte, o pasar el tiempo, no repite nada.
      await tester.pump(const Duration(minutes: 1));
      expect(datos.uniones, hasLength(1));
    });

    _prueba(
      'cuando toco "Deshacer" no cambia nada: el par sigue en la lista y pasado el tiempo no se '
      'une',
      (tester) async {
        final datos = _datos();
        await _montar(tester, datos, lector: true);
        await _unir(tester, _parItalia);
        expect(find.text('1 para revisar'), findsOneWidget);

        await tester.tap(_deshacer);
        await _transicion(tester);
        await tester.pump(const Duration(minutes: 1));

        expect(datos.uniones, isEmpty);
        expect(_aviso, findsNothing);
        expect(find.text('2 para revisar'), findsOneWidget);
      },
    );

    _prueba('cuando salgo de la pantalla con el aviso abierto, la unión se hace', (tester) async {
      final datos = _datos();
      await _montar(tester, datos, lector: true);
      await _unir(tester, _parItalia);
      await tester.pump(const Duration(seconds: 30));
      expect(datos.uniones, isEmpty);

      await tester.tap(find.byKey(const Key('duplicados_volver')));
      await _transicion(tester);

      expect(datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
      expect(find.byType(PosiblesDuplicadosPage), findsNothing);
      expect(_aviso, findsNothing);
    });

    _prueba(
      'cuando salgo y reentro, el par ya unido no está y el otro sigue: nada se une dos veces',
      (tester) async {
        final datos = _datos();
        await _montar(tester, datos, lector: true);
        await _unir(tester, _parItalia);
        await tester.tap(find.byKey(const Key('duplicados_volver')));
        await _transicion(tester);

        await tester.tap(find.byKey(const Key('abrir')));
        await _transicion(tester);
        await tester.pump(const Duration(seconds: 30));

        expect(datos.uniones, hasLength(1));
        expect(find.byKey(const Key('par_$_parItalia')), findsNothing);
        expect(find.byKey(const Key('par_$_parArtigas')), findsOneWidget);
        expect(find.text('1 para revisar'), findsOneWidget);
      },
    );

    _prueba(
      'cuando uno otro par con el primero esperando, el primero queda definitivo y el segundo '
      'espera el cierre',
      (tester) async {
        final datos = _datos();
        await _montar(tester, datos, lector: true);
        await _unir(tester, _parItalia);
        await tester.pump(const Duration(seconds: 20));
        expect(datos.uniones, isEmpty);

        await _unir(tester, _parArtigas);
        await tester.pump(const Duration(seconds: 20));

        expect(datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
        expect(_deshacer, findsOneWidget);

        await _descartarElAviso(tester);
        expect(datos.uniones, hasLength(2));
        expect(datos.uniones.last, (conservadaId: 'ub-c', duplicadaId: 'ub-d'));
        expect(find.text('Deshacer'), findsNothing);
      },
    );

    _prueba(
      'cuando toco "Deshacer" y enseguida "Conservar A y unir" del mismo par, el aviso viejo al '
      'irse no hace la unión nueva',
      (tester) async {
        final datos = _datos();
        await _montar(tester, datos, lector: true);
        await _unir(tester, _parItalia);
        await tester.tap(_deshacer);
        // El aviso viejo todavía se está yendo cuando la persona vuelve a unir el mismo par.
        await tester.pump(const Duration(milliseconds: 50));

        await _unir(tester, _parItalia);
        await _transicion(tester);

        expect(datos.uniones, isEmpty, reason: 'el cierre del aviso viejo no confirma al nuevo');
        expect(_deshacer, findsOneWidget);
        await _descartarElAviso(tester);
        expect(datos.uniones, hasLength(1));
      },
    );

    _prueba('si la unión falla al cerrar el aviso, el par vuelve a la lista con el aviso rojo y '
        '"Reintentar" anda', (tester) async {
      final datos = _datos()..falloAlUnir = const FailureInesperado();
      await _montar(tester, datos, lector: true);
      await _unir(tester, _parItalia);

      await _descartarElAviso(tester);

      expect(datos.uniones, hasLength(1), reason: 'un intento, que falló');
      expect(find.byKey(const Key('duplicados_falla_union')), findsOneWidget);
      expect(find.text('2 para revisar'), findsOneWidget);

      datos.falloAlUnir = null;
      await tester.tap(find.byKey(const Key('duplicados_reintentar_union')));
      await _transicion(tester);

      expect(datos.uniones, hasLength(2), reason: 'el reintento corre ya, sin otra espera');
      expect(find.byKey(const Key('duplicados_falla_union')), findsNothing);
    });

    _prueba('con el texto al 200 % "Deshacer" está a la vista, anda y el aviso se descarta igual', (
      tester,
    ) async {
      final datos = _datos();
      await _montar(tester, datos, lector: true, escala: 2);
      await _unir(tester, _parItalia);
      await tester.pump(const Duration(seconds: 30));
      expect(datos.uniones, isEmpty);
      expect(tester.takeException(), isNull);

      await _descartarElAviso(tester);

      expect(datos.uniones, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('Escenario: el aviso dice la verdad (mapa §2, P1 de la QA)', () {
    _prueba('con lector el aviso dice que se une cuando se cierre, en pantalla y para el lector', (
      tester,
    ) async {
      final datos = _datos();
      await _montar(tester, datos, lector: true);
      await _unir(tester, _parItalia);

      const texto = 'Las dos Av. Italia 1234 se unen en una cuando cierres este aviso.';
      expect(find.text(texto), findsOneWidget);
      expect(find.textContaining('quedaron unidas'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('cuando cierres este aviso')), findsWidgets);
      expect(_deshacer, findsOneWidget);
    });

    _prueba('sin lector el aviso dice lo de siempre', (tester) async {
      final datos = _datos();
      await _montar(tester, datos, lector: false);
      await _unir(tester, _parItalia);

      expect(find.text('Las dos Av. Italia 1234 quedaron unidas en una.'), findsOneWidget);
      expect(find.textContaining('cuando cierres'), findsNothing);
    });
  });

  group('Escenario: otro aviso cierra el de "Deshacer" (mapa §2, P2 de la QA)', () {
    _prueba(
      'con lector, si otro aviso lo cierra (hide) la unión sigue esperando y el aviso vuelve',
      (tester) async {
        final datos = _datos();
        await _montar(tester, datos, lector: true);
        await _unir(tester, _parItalia);

        ScaffoldMessenger.of(
          tester.element(find.byType(PosiblesDuplicadosPage)),
        ).hideCurrentSnackBar();
        await _transicion(tester);
        await tester.pump(const Duration(minutes: 1));

        expect(datos.uniones, isEmpty, reason: 'no la cerró la persona');
        expect(_deshacer, findsOneWidget, reason: 'el aviso vuelve a mostrarse');
        expect(find.text('1 para revisar'), findsOneWidget);

        await _descartarElAviso(tester);
        expect(datos.uniones, hasLength(1));
      },
    );
  });

  group('Escenario: sin lector de pantalla todo sigue igual, 8 s', () {
    _prueba(
      'dado el lector apagado, cuando toco "Conservar A y unir", a los 8 s la unión se hace y el '
      'aviso se va',
      (tester) async {
        final datos = _datos();
        await _montar(tester, datos, lector: false);
        await _unir(tester, _parItalia);

        await tester.pump(const Duration(seconds: 6));
        expect(datos.uniones, isEmpty);
        expect(_deshacer, findsOneWidget);

        await tester.pump(const Duration(seconds: 3));
        await _transicion(tester);

        expect(datos.uniones, hasLength(1));
        expect(_aviso, findsNothing);
      },
    );

    _prueba('dado el lector apagado, cuando toco "Deshacer" antes de los 8 s, no se une nada', (
      tester,
    ) async {
      final datos = _datos();
      await _montar(tester, datos, lector: false);
      await _unir(tester, _parItalia);
      await tester.pump(const Duration(seconds: 5));

      await tester.tap(_deshacer);
      await _transicion(tester);
      await tester.pump(const Duration(minutes: 1));

      expect(datos.uniones, isEmpty);
      expect(find.text('2 para revisar'), findsOneWidget);
    });
  });
}
