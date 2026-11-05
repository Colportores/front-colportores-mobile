// Vista 10 «Posibles duplicados», hoja 10·02 con un «Par local» (HU-UBI-006, #285): una de las dos
// ubicaciones todavía no está en el servidor. La hoja solo ofrece conservar la que sí está, dice por
// qué, y la unión no cambia lo que se pide (es el motor/la base la que no encola; eso lo prueba
// `par_local_285_drift_test.dart`). El canvas no dibuja este caso.
//
// Casos límite: las dos fuera del servidor (se puede elegir cualquiera), el alta que cambia mientras la
// hoja está abierta, el alta que está subiendo (aviso rojo con «Reintentar»), doble toque en la opción
// que no se puede conservar, y texto a 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_comparar_duplicado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/duplicados_falsos.dart';

const _ocho = Duration(seconds: 8);
const _clave = 'ub-a|ub-b';

/// El texto de la hoja cuando una de las dos no se puede conservar.
const _avisoParLocal =
    'Una de las dos todavía no está en el servidor, así que se conserva la que sí está. Lo que '
    'cargaste en la otra pasa a ella y se sube con el resto.';

/// A (la más vieja) y B, el mismo número de puerta a 12 m.
DuplicadosEnMemoria _datos() => DuplicadosEnMemoria()
  ..agregar(ubicacionDuplicable('ub-a', creada: DateTime.utc(2026, 8, 1, 10)))
  ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 12, creada: DateTime.utc(2026, 8, 5, 10)));

/// El árbol de semántica del test en curso: se suelta antes de que termine el cuerpo del test.
SemanticsHandle? _semantica;

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _transicion(WidgetTester tester) async {
  await _asentar(tester);
  await tester.pump(const Duration(seconds: 1));
  await _asentar(tester);
}

Future<void> _montar(
  WidgetTester tester,
  DuplicadosEnMemoria datos,
  ConsultorAltaUbicacionFalso altas, {
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(datos.cerrar);
  _semantica = tester.ensureSemantics();
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesDuplicados(datos, conMapa: true, altas: altas),
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

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _asentar(tester);
}

Future<void> _abrirHoja(WidgetTester tester) =>
    _tocar(tester, find.byKey(const Key('revisar_$_clave')));

/// Saca todo del árbol y deja correr el reloj: lo que quedó esperando se confirma.
Future<void> _desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void _prueba(String descripcion, Future<void> Function(WidgetTester tester) cuerpo) {
  testWidgets(descripcion, (tester) async {
    await cuerpo(tester);
    await _desmontar(tester);
    _semantica?.dispose();
    _semantica = null;
  });
}

final _conservarYUnir = find.byKey(const Key('comparar_conservar_y_unir'));
final _primera = find.byKey(const Key('comparar_opcion_primera'));
final _segunda = find.byKey(const Key('comparar_opcion_segunda'));
final _avisoDeLaHoja = find.byKey(const Key('comparar_par_local'));

/// Lo que lee el lector de pantalla de una opción (la etiqueta dice cuál se conserva y por qué no).
String _lee(WidgetTester tester, Finder opcion) => tester.getSemantics(opcion).label;

void main() {
  setUpAll(cargarFuentesReales);

  group('10·02 · Par local', () {
    _prueba('dado que B solo está en el teléfono, cuando abro el par, se explica por qué se '
        'conserva A y "Conservar A y unir" une B en A', (tester) async {
      final datos = _datos();
      final altas = ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono});
      await _montar(tester, datos, altas);
      await _abrirHoja(tester);

      expect(find.byType(HojaCompararDuplicado), findsOneWidget);
      expect(find.text(_avisoParLocal), findsOneWidget);
      expect(_lee(tester, _primera), contains('Ubicación A, la que se conserva'));
      expect(_lee(tester, _segunda), contains('Ubicación B, solo en tu teléfono: queda como baja'));

      // No se puede elegir la que solo está en el teléfono: el toque no cambia cuál se conserva.
      await _tocar(tester, _segunda);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
    });

    _prueba('dado que A (la más vieja) es la que solo está en el teléfono, se propone y se une '
        'conservando B', (tester) async {
      final datos = _datos();
      final altas = ConsultorAltaUbicacionFalso({'ub-a': EstadoAltaUbicacion.soloEnTelefono});
      await _montar(tester, datos, altas);
      await _abrirHoja(tester);

      expect(find.text(_avisoParLocal), findsOneWidget);
      expect(_lee(tester, _primera), contains('Ubicación B, solo en tu teléfono: queda como baja'));
      expect(_lee(tester, _segunda), contains('Ubicación A, la que se conserva'));

      await _tocar(tester, _primera);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.uniones, [(conservadaId: 'ub-b', duplicadaId: 'ub-a')]);
    });

    _prueba('dado que las dos están fuera del servidor, se puede conservar cualquiera y no hay '
        'aviso', (tester) async {
      final datos = _datos();
      final altas = ConsultorAltaUbicacionFalso({
        'ub-a': EstadoAltaUbicacion.soloEnTelefono,
        'ub-b': EstadoAltaUbicacion.soloEnTelefono,
      });
      await _montar(tester, datos, altas);
      await _abrirHoja(tester);

      expect(_avisoDeLaHoja, findsNothing);
      await _tocar(tester, _segunda);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.uniones, [(conservadaId: 'ub-b', duplicadaId: 'ub-a')]);
    });

    _prueba('dado un par común (las dos en el servidor), la hoja no dice nada de "Par local"', (
      tester,
    ) async {
      final datos = _datos();
      await _montar(tester, datos, ConsultorAltaUbicacionFalso());
      await _abrirHoja(tester);

      expect(_avisoDeLaHoja, findsNothing);
      expect(_lee(tester, _segunda), contains('Ubicación B, la que queda como baja'));
      expect(_lee(tester, _segunda), isNot(contains('solo en tu teléfono')));
    });

    _prueba('dado que mientras la hoja está abierta el alta de B sube, el aviso se va y se puede '
        'elegir B de nuevo', (tester) async {
      final datos = _datos();
      final altas = ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono});
      await _montar(tester, datos, altas);
      await _abrirHoja(tester);
      expect(_avisoDeLaHoja, findsOneWidget);

      altas.poner('ub-b', EstadoAltaUbicacion.enServidor);
      await _asentar(tester);

      expect(_avisoDeLaHoja, findsNothing);
      await _tocar(tester, _segunda);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);
      expect(datos.uniones, [(conservadaId: 'ub-b', duplicadaId: 'ub-a')]);
    });

    _prueba('dado que el alta de la elegida cambia de lugar con la hoja abierta, la hoja pasa a '
        'conservar la que sí está', (tester) async {
      final datos = _datos();
      final altas = ConsultorAltaUbicacionFalso();
      await _montar(tester, datos, altas);
      await _abrirHoja(tester);

      // A (elegida por defecto) vuelve a quedar solo en el teléfono.
      altas.poner('ub-a', EstadoAltaUbicacion.soloEnTelefono);
      await _asentar(tester);

      expect(_avisoDeLaHoja, findsOneWidget);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);
      expect(datos.uniones, [(conservadaId: 'ub-b', duplicadaId: 'ub-a')]);
    });

    _prueba('dado doble toque en la opción que no se puede conservar, no pasa nada y "Conservar" '
        'sigue andando una sola vez', (tester) async {
      final datos = _datos();
      final altas = ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono});
      await _montar(tester, datos, altas);
      await _abrirHoja(tester);

      await tester.tap(_segunda);
      await tester.tap(_segunda);
      await _asentar(tester);
      await tester.tap(_conservarYUnir);
      await tester.tap(_conservarYUnir, warnIfMissed: false);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.uniones, hasLength(1));
      expect(datos.uniones.single.conservadaId, 'ub-a');
    });

    _prueba('dado que el alta está subiendo, el aviso rojo dice que espere y "Reintentar" lo hace '
        'de nuevo cuando ya contestó', (tester) async {
      final datos = _datos()..falloAlUnir = const FailureAltaSubiendo();
      final altas = ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.subiendo});
      await _montar(tester, datos, altas);
      await _abrirHoja(tester);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(find.byKey(const Key('duplicados_falla_union')), findsOneWidget);
      expect(
        find.text(
          'Una de las dos ubicaciones se está subiendo ahora. Esperá un momento y probá de nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('duplicados_reintentar_union')), findsOneWidget);
      expect(
        find.byKey(const Key('par_$_clave')),
        findsOneWidget,
        reason: 'el par sigue para revisar',
      );

      datos.falloAlUnir = null;
      altas.poner('ub-b', EstadoAltaUbicacion.enServidor);
      await _tocar(tester, find.byKey(const Key('duplicados_reintentar_union')));

      expect(find.byKey(const Key('duplicados_falla_union')), findsNothing);
      expect(datos.uniones, hasLength(2));
    });

    _prueba('dado texto al 200 % en un teléfono chico, la hoja del par local no desborda', (
      tester,
    ) async {
      final datos = _datos();
      final altas = ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono});
      await _montar(tester, datos, altas, escala: 2, tamano: const Size(360, 640));
      await _abrirHoja(tester);

      expect(find.text(_avisoParLocal), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
