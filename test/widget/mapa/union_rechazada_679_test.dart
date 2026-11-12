// Vista 10 «Posibles duplicados»: el par cuya unión rechazó el servidor (HU-UBI-006, #679; decisión de
// Cristian, 10/11, «Unión rech.»: «queda separado en el teléfono»). El par vuelve a la lista con su
// aviso arriba en la tarjeta: con `UB003` el texto de la HU; con cualquier otro código, el genérico.
// Los demás pares no lo muestran, y el aviso no rompe la tarjeta a 320 px ni con el texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_comparar_duplicado.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/textos_posibles_duplicados.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/duplicados_falsos.dart';

const _parItalia = 'ub-a|ub-b';
const _parArtigas = 'ub-c|ub-d';

const _textoUb003 =
    'La ubicación que ibas a conservar ya está dada de baja. Revisá el par de nuevo.';
const _textoGenerico =
    'No pudimos unir estas dos ubicaciones. Quedaron separadas, como estaban. Revisá el par de nuevo.';

DuplicadosEnMemoria _datos() {
  final datos = DuplicadosEnMemoria();
  datos
    ..agregar(ubicacionDuplicable('ub-a'))
    ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 12))
    ..agregar(
      ubicacionDuplicable('ub-c', metrosAlNorte: 1000, calle: 'Bulevar Artigas', numero: '880'),
    )
    ..agregar(
      ubicacionDuplicable('ub-d', metrosAlNorte: 1010, calle: 'Bulevar Artigas', numero: '880'),
    );
  return datos;
}

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
  await tester.tap(find.byKey(const Key('abrir')));
  await _transicion(tester);
}

void _prueba(String descripcion, Future<void> Function(WidgetTester tester) cuerpo) {
  testWidgets(descripcion, (tester) async {
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}

Finder _aviso(String clave) => find.byKey(Key('union_rechazada_$clave'));

void main() {
  setUpAll(cargarFuentesReales);

  test('los textos del aviso: UB003 el de la HU, cualquier otro código el genérico', () {
    expect(TextosPosiblesDuplicados.avisoUnionRechazada('UB003'), _textoUb003);
    for (final codigo in ['UB004', '42501', 'CG001', '']) {
      expect(TextosPosiblesDuplicados.avisoUnionRechazada(codigo), _textoGenerico, reason: codigo);
    }
  });

  _prueba('dado que el servidor rechazó la unión de un par con UB003, cuando se abre la vista, ese '
      'par está para revisar con el aviso de la HU arriba y el otro par sin aviso', (tester) async {
    final datos = _datos()..rechazarUnion(_parItalia, 'UB003');

    await _montar(tester, datos);

    expect(find.text('2 para revisar'), findsOneWidget);
    expect(_aviso(_parItalia), findsOneWidget);
    expect(
      find.descendant(of: _aviso(_parItalia), matching: find.text(_textoUb003)),
      findsOneWidget,
    );
    expect(_aviso(_parArtigas), findsNothing);
    expect(find.byKey(const Key('revisar_$_parItalia')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _prueba('dado un rechazo con otro código, el aviso dice el texto genérico', (tester) async {
    final datos = _datos()..rechazarUnion(_parItalia, '42501');

    await _montar(tester, datos);

    expect(
      find.descendant(of: _aviso(_parItalia), matching: find.text(_textoGenerico)),
      findsOneWidget,
    );
    expect(find.text(_textoUb003), findsNothing);
  });

  _prueba('dado la vista abierta, cuando llega el rechazo (el motor lo deshizo en segundo plano), '
      'el aviso aparece solo, sin volver a entrar', (tester) async {
    final datos = _datos();
    await _montar(tester, datos);
    expect(_aviso(_parItalia), findsNothing);

    datos.rechazarUnion(_parItalia, 'UB003');
    await _asentar(tester);

    expect(_aviso(_parItalia), findsOneWidget);
  });

  _prueba('dado el aviso, el lector lo lee como un solo texto, sin el «!»', (tester) async {
    final manejador = tester.ensureSemantics();
    final datos = _datos()..rechazarUnion(_parItalia, 'CG001');
    await _montar(tester, datos);

    expect(
      tester.getSemantics(_aviso(_parItalia)),
      matchesSemantics(label: _textoGenerico, isLiveRegion: true),
    );
    manejador.dispose();
  });

  _prueba('dado el aviso, cuando toca «Revisar», abre la comparación del par como siempre', (
    tester,
  ) async {
    final datos = _datos()..rechazarUnion(_parItalia, 'UB003');
    await _montar(tester, datos);

    await tester.ensureVisible(find.byKey(const Key('revisar_$_parItalia')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('revisar_$_parItalia')));
    await _asentar(tester);

    expect(find.byType(HojaCompararDuplicado), findsOneWidget);
  });

  for (final (nombre, escala, tamano) in [
    ('texto al 200 % en 390 px', 2.0, const Size(390, 844)),
    ('320 px', 1.0, const Size(320, 640)),
    ('texto al 200 % en 320 px', 2.0, const Size(320, 640)),
  ]) {
    _prueba('dado el aviso con $nombre, la tarjeta no se desborda y el texto se lee entero', (
      tester,
    ) async {
      final datos = _datos()..rechazarUnion(_parItalia, '42501');

      await _montar(tester, datos, escala: escala, tamano: tamano);

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        _aviso(_parItalia),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text(_textoGenerico), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
