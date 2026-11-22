// HU-VEN-003 (vista 27, grupo C, «Entregas pendientes», #435): un test por artboard (27C·02 la lista,
// 27C·05 vacía, 27C·06 cargando, 27C·07 con error y 27C·08 sin conexión), la apertura de «Marcar
// entregado» y de «Poner fecha», y los casos límite: doble toque, reentrar, la lista que cambia
// mientras se mira, datos límite y texto al 200 %.
import 'package:colportores_mobile/features/inicio/presentation/widgets/barra_pestanas_inicio.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregas_pendientes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';
import '../../helpers/venta_ui_falsos.dart' show asentar, tocar;

/// Atrasada (miércoles 21/10), próxima (sábado 31/10) y sin fecha.
List<EntregaPendiente> _lista() => [
  pendienteDe('v-1', fecha: DateTime(2026, 10, 21, 16, 30), lineas: [lineaDe('e-1', 'p-hijos')]),
  pendienteDe(
    'v-2',
    fecha: DateTime(2026, 10, 31, 9),
    vinculo: 'ep-2',
    talonario: '0043',
    lineas: [lineaDe('e-2', 'p-salud'), lineaDe('e-3', 'p-hijos')],
  ),
  pendienteDe('v-3', vinculo: 'ep-3', talonario: '0044', lineas: [lineaDe('e-4', 'p-salud')]),
];

Route<PestanaInicio> _ruta() => EntregasPendientesPage.ruta(colportorId: 'col-1');

EntornoDeEntrega _entorno([List<EntregaPendiente>? lista]) {
  final e = EntornoDeEntrega();
  e.entregas.emitirPendientes(lista ?? _lista());
  e.entregas.respuestaDeCumplir = cumplidaCon();
  e.entregas.respuestaDeDiferir = diferidaPara(DateTime(2026, 10, 29, 8, 30));
  return e;
}

void main() {
  group('27C·02 Entregas pendientes', () {
    testWidgets('agrupa en atrasadas, próximas y sin fecha, en ese orden', (tester) async {
      await montarPantalla(tester, _entorno(), _ruta);

      expect(find.text('VENTAS'), findsOneWidget);
      expect(find.text('Entregas pendientes'), findsOneWidget);
      expect(find.text('ATRASADAS'), findsOneWidget);
      expect(find.text('PRÓXIMAS'), findsOneWidget);
      expect(find.text('SIN FECHA'), findsOneWidget);
      final y = [
        for (final t in ['ATRASADAS', 'PRÓXIMAS', 'SIN FECHA']) tester.getTopLeft(find.text(t)).dy,
      ];
      expect(y, orderedEquals([...y]..sort()));
    });

    testWidgets('cada tarjeta dice el día, quién, dónde y qué falta', (tester) async {
      await montarPantalla(tester, _entorno(), _ruta);

      expect(find.text('MIÉ 21/10 · 16:30'), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.text('Grecia 3310 · Nuestros Hijos × 1'), findsOneWidget);
      expect(find.text('SÁB 31/10 · 09:00'), findsOneWidget);
      expect(find.text('Juan Pérez'), findsOneWidget);
      expect(find.text('Mataojo 2044 · 3B · 2 productos'), findsOneWidget);
      expect(find.text('Ana Silva'), findsOneWidget);
      expect(find.text('Bvar. Artigas 1500 · Salud y Hogar × 1'), findsOneWidget);
    });

    testWidgets('la atrasada lleva «!» y las demás «⇢»; solo la sin fecha ofrece «Poner fecha»', (
      tester,
    ) async {
      await montarPantalla(tester, _entorno(), _ruta);

      expect(find.text('!'), findsOneWidget);
      expect(find.text('⇢'), findsNWidgets(2));
      expect(find.text('Poner fecha'), findsOneWidget);
    });

    testWidgets('el lector de pantalla oye la tarjeta completa y que está atrasada', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await montarPantalla(tester, _entorno(), _ruta);

      expect(
        find.bySemanticsLabel(
          'Atrasada. MIÉ 21/10 · 16:30. María Fernández. '
          'Grecia 3310 · Nuestros Hijos × 1',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('sin los nombres del catálogo dice cuántos productos sin inventar nada', (
      tester,
    ) async {
      final e = _entorno();
      e.fuente.fallas = 1;
      await montarPantalla(tester, e, _ruta);

      expect(find.text('Grecia 3310 · 1 producto'), findsOneWidget);
      expect(find.text('Mataojo 2044 · 3B · 2 productos'), findsOneWidget);
      expect(find.textContaining('Producto sin nombre'), findsNothing);
    });

    testWidgets('tocar una tarjeta abre «Marcar entregado» de esa venta', (tester) async {
      await montarPantalla(tester, _entorno(), _ruta);

      await tocar(tester, find.text('Juan Pérez'));

      expect(find.text('Marcar entregado'), findsWidgets);
      expect(find.text('VENTA 0043'), findsOneWidget);
      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
    });

    testWidgets('«Poner fecha» abre «Entregar otro día» para esa venta', (tester) async {
      await montarPantalla(tester, _entorno(), _ruta);

      await tocar(tester, find.byKey(const Key('entrega_poner_fecha')));

      expect(find.text('Entregar otro día'), findsOneWidget);
      expect(find.text('VENTA 0044'), findsOneWidget);
      expect(find.text('Ana Silva'), findsOneWidget);
    });

    testWidgets('la barra de pestañas devuelve la pestaña elegida', (tester) async {
      final salida = await montarPantalla(tester, _entorno(), _ruta);

      await tocar(tester, find.byKey(const Key('inicio_pestana_agenda')));

      expect(salida.cerrada, isTrue);
      expect(salida.valor, PestanaInicio.agenda);
    });

    testWidgets('«volver» cierra sin elegir pestaña', (tester) async {
      final salida = await montarPantalla(tester, _entorno(), _ruta);

      await tocar(tester, find.byKey(const Key('venta_atras')));

      expect(salida.cerrada, isTrue);
      expect(salida.valor, isNull);
    });
  });

  group('27C·05, 27C·06, 27C·07 y 27C·08', () {
    testWidgets('27C·05 vacía: dice que no hay entregas pendientes', (tester) async {
      await montarPantalla(tester, _entorno(const []), _ruta);

      expect(find.text('No tenés entregas pendientes'), findsOneWidget);
      expect(find.text('✓'), findsOneWidget);
      expect(find.text('ATRASADAS'), findsNothing);
    });

    testWidgets('27C·06 cargando: esqueleto con la barra de pestañas y sin listas', (tester) async {
      final e = EntornoDeEntrega();
      await montarPantalla(tester, e, _ruta);

      expect(find.byKey(const Key('entregas_cargando')), findsOneWidget);
      expect(find.byKey(const Key('inicio_barra')), findsOneWidget);
      expect(find.text('No tenés entregas pendientes'), findsNothing);

      e.entregas.emitirPendientes(_lista());
      await asentar(tester);

      expect(find.byKey(const Key('entregas_cargando')), findsNothing);
      expect(find.text('María Fernández'), findsOneWidget);
    });

    testWidgets('27C·07 error: avisa y «Reintentar» vuelve a leer', (tester) async {
      final e = EntornoDeEntrega();
      e.entregas.errorDePendientes = StateError('no se pudo leer');
      await montarPantalla(tester, e, _ruta);

      expect(find.text('No pudimos leer tus entregas.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      e.entregas.errorDePendientes = null;
      e.entregas.pendientesActuales = _lista();
      await tocar(tester, find.text('Reintentar'));

      expect(find.text('No pudimos leer tus entregas.'), findsNothing);
      expect(find.text('María Fernández'), findsOneWidget);
    });

    testWidgets('27C·08 sin conexión: la lista sale del teléfono y no menciona la señal', (
      tester,
    ) async {
      await montarPantalla(tester, _entorno(), _ruta);

      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.textContaining('conexión'), findsNothing);
      expect(find.textContaining('internet'), findsNothing);
    });
  });

  group('casos límite', () {
    testWidgets('dos toques seguidos en la misma tarjeta abren una sola pantalla', (tester) async {
      await montarPantalla(tester, _entorno(), _ruta);

      await tester.tap(find.text('Juan Pérez'));
      await tester.tap(find.text('Juan Pérez'), warnIfMissed: false);
      await asentar(tester);
      expect(find.text('VENTA 0043'), findsOneWidget);

      await tester.tap(find.byKey(const Key('venta_atras')));
      await asentar(tester);

      expect(find.text('Entregas pendientes'), findsOneWidget);
      expect(find.text('VENTA 0043'), findsNothing);
    });

    testWidgets('dos tarjetas distintas tocadas seguidas abren solo la primera', (tester) async {
      await montarPantalla(tester, _entorno(), _ruta);

      await tester.tap(find.text('Juan Pérez'));
      await tester.tap(find.text('María Fernández'), warnIfMissed: false);
      await asentar(tester);

      expect(find.text('VENTA 0043'), findsOneWidget);
      expect(find.text('VENTA 0042'), findsNothing);
    });

    testWidgets('volver y reentrar: la lista sigue completa y se puede abrir otra vez', (
      tester,
    ) async {
      await montarPantalla(tester, _entorno(), _ruta);
      await tocar(tester, find.byKey(const Key('venta_atras')));

      await abrirPantalla(tester);

      expect(find.text('María Fernández'), findsOneWidget);
      await tocar(tester, find.text('María Fernández'));
      expect(find.text('VENTA 0042'), findsOneWidget);
    });

    testWidgets(
      'una entrega que se marca mientras se mira sale de la lista y el grupo vacío se va',
      (tester) async {
        final e = _entorno();
        await montarPantalla(tester, e, _ruta);

        e.entregas.emitirPendientes([_lista()[1], _lista()[2]]);
        await asentar(tester);

        expect(find.text('ATRASADAS'), findsNothing);
        expect(find.text('María Fernández'), findsNothing);
        expect(find.text('Juan Pérez'), findsOneWidget);

        e.entregas.emitirPendientes(const []);
        await asentar(tester);

        expect(find.text('No tenés entregas pendientes'), findsOneWidget);
      },
    );

    testWidgets('60 entregas con nombres largos: se recorre la lista sin desbordar', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      e.entregas.emitirPendientes([
        for (var i = 0; i < 60; i++)
          pendienteDe(
            'v-$i',
            fecha: DateTime(2026, 10, 20 + i % 20, 10),
            talonario: '${1000 + i}',
            lineas: [lineaDe('e-$i', 'p-deseado', 3)],
          ),
      ]);
      await montarPantalla(tester, e, _ruta, tamano: const Size(320, 568));

      expect(tester.takeException(), isNull);
      await tester.drag(find.byKey(const Key('entregas_lista')), const Offset(0, -20000));
      await asentar(tester);
      expect(tester.takeException(), isNull);
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'texto al ${(escala * 100).round()} % a 320 × 568: nada desborda y todo se alcanza',
        (tester) async {
          final e = _entorno();
          await montarPantalla(tester, e, _ruta, escala: escala, tamano: const Size(320, 568));

          expect(tester.takeException(), isNull);
          await tester.drag(find.byKey(const Key('entregas_lista')), const Offset(0, -2000));
          await asentar(tester);
          final ponerFecha = find.byKey(const Key('entrega_poner_fecha'));
          expect(ponerFecha, findsOneWidget);
          expect(tester.getSize(ponerFecha).height, greaterThanOrEqualTo(48));
          expect(tester.getSize(ponerFecha).width, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
