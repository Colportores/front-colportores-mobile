// HU-VEN-001 (vista 27, «Registrar venta»): un test por artboard (27A·01 a 27A·13; el 27A·09 no se
// implementa, decisión P4 de #158; el 27A·14 está en venta_registrada_page_test.dart), por los
// estados que el canvas no dibuja (cargando, error de precios, sin catálogo, sin conexión) y por cada
// caso límite: doble toque, falla a mitad del guardado, acciones seguidas, volver y reentrar, datos
// límite y texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/ciudad_consultable.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/cliente_de_la_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/precios_de_la_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/venta_repository.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/precios_falsos.dart' show cMontevideo;
import '../../helpers/venta_ui_falsos.dart';

Finder get _cta => find.byKey(const Key('venta_cta'));

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(_cta).onPressed != null;

Finder _campo(String clave) =>
    find.descendant(of: find.byKey(Key(clave)), matching: find.byType(TextField));

/// 27A·01 → 27A·04: elige «Colección de 2 libros» y los libros [uno] y [dos] (o solo [uno]).
Future<void> _armarColeccionDe2(
  WidgetTester tester, {
  String uno = 'Salud y Hogar',
  String? dos,
}) async {
  await tocar(tester, find.text('Colección de 2 libros'));
  await tocar(tester, find.text(TextosVenta.armarLaColeccion));
  await tocar(tester, find.byKey(const Key('armar_libro_1')));
  await tocar(tester, find.text(uno));
  await tocar(tester, find.text(TextosVenta.listo));
  if (dos != null) {
    await tocar(tester, find.byKey(const Key('armar_libro_2')));
    await tocar(tester, find.text(dos).last);
    await tocar(tester, find.text(TextosVenta.listo));
  }
}

/// Deja una venta con la colección de 2 libros en la pantalla (27A·05).
Future<void> _ventaConLaColeccion(WidgetTester tester) async {
  await _armarColeccionDe2(tester, dos: 'Nuestros Hijos');
  await tocar(tester, find.text(TextosVenta.agregarALaVenta));
}

void main() {
  group('27A·01 Elegir la colección', () {
    testWidgets('muestra al cliente, el talonario, dónde se cotiza y las colecciones', (
      tester,
    ) async {
      await montarNuevaVenta(tester, EntornoDeVenta());

      expect(find.text('Nueva venta'), findsOneWidget);
      expect(find.text('REGISTRAR VENTA'), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
      expect(find.text('Nº DE TALONARIO'), findsWidgets);
      expect(find.text('◉ Precios de Montevideo, según la casa del cliente.'), findsOneWidget);
      for (final chip in ['Colecciones', 'Libros', 'Misioneros', 'Revistas']) {
        expect(find.text(chip), findsOneWidget);
      }
      expect(find.text('Colección de 1 libro'), findsOneWidget);
      expect(find.text('Colección de 2 libros'), findsOneWidget);
      expect(find.text(r'$ 8.900'), findsOneWidget);
    });

    testWidgets('«Armar la colección» espera a que se elija una', (tester) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      expect(_habilitado(tester), isFalse);

      await tocar(tester, find.text('Colección de 2 libros'));

      expect(_habilitado(tester), isTrue);
    });

    testWidgets('las colecciones se leen del catálogo de la ciudad de la casa', (tester) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);

      expect(e.repo.pedidos, contains(cMontevideo.campaniaCiudadId));
      expect(e.fuente.lecturas, 1);
    });
  });

  group('27A·02 a 27A·04 Armar la colección', () {
    testWidgets('27A·02 lo que siempre va y un lugar por libro, sin poder seguir', (tester) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await tocar(tester, find.text('Colección de 2 libros'));
      await tocar(tester, find.text(TextosVenta.armarLaColeccion));

      expect(find.byKey(const Key('armar_coleccion_pagina')), findsOneWidget);
      expect(find.text('NUEVA VENTA · COLECCIÓN'), findsOneWidget);
      expect(find.text(r'$ 8.900 en Montevideo'), findsOneWidget);
      expect(find.text('SIEMPRE VAN'), findsOneWidget);
      for (final fijo in ['El camino a Cristo', 'Vida Feliz', 'El Deseado de todas las gentes']) {
        expect(find.text(fijo), findsOneWidget);
      }
      expect(find.text('LIBROS QUE ELEGÍS'), findsOneWidget);
      expect(find.text('LIBRO 1'), findsOneWidget);
      expect(find.text('LIBRO 2'), findsOneWidget);
      expect(find.text('Elegir del catálogo'), findsNWidgets(2));
      expect(_habilitado(tester), isFalse);
      expect(find.text('Elegí el libro 1 para seguir.'), findsOneWidget);
    });

    testWidgets('27A·03 la hoja «Libro 1» busca por nombre y «Listo» pone el libro', (
      tester,
    ) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await tocar(tester, find.text('Colección de 2 libros'));
      await tocar(tester, find.text(TextosVenta.armarLaColeccion));

      await tocar(tester, find.byKey(const Key('armar_libro_1')));

      expect(find.text('Libro 1'), findsOneWidget);
      expect(find.text('Buscar por nombre o código'), findsOneWidget);
      expect(find.text('Libro · ◆ Bonificable'), findsWidgets);
      await escribir(tester, _campo('venta_hoja_libro_busqueda'), 'nuestros');
      expect(find.text('Nuestros Hijos'), findsOneWidget);
      expect(find.text('Salud y Hogar'), findsNothing);
      await tocar(tester, find.text('Nuestros Hijos'));
      await tocar(tester, find.text(TextosVenta.listo));
      expect(find.text('Nuestros Hijos'), findsOneWidget);
      expect(find.text('Cambiar'), findsOneWidget);
      expect(find.text('Elegí el libro 2 para seguir.'), findsOneWidget);
    });

    testWidgets('la hoja no deja «Listo» sin haber elegido y cerrarla no cambia nada', (
      tester,
    ) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await tocar(tester, find.text('Colección de 2 libros'));
      await tocar(tester, find.text(TextosVenta.armarLaColeccion));
      await tocar(tester, find.byKey(const Key('armar_libro_1')));

      final listo = find.widgetWithText(FilledButton, TextosVenta.listo);
      expect(tester.widget<FilledButton>(listo).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(find.text('Elegir del catálogo'), findsNWidgets(2));
    });

    testWidgets('27A·04 con los dos libros se puede agregar a la venta', (tester) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await _armarColeccionDe2(tester, dos: 'Nuestros Hijos');

      expect(_habilitado(tester), isTrue);
      expect(find.textContaining('para seguir'), findsNothing);
      expect(find.text('Cambiar'), findsNWidgets(2));
    });

    testWidgets('un libro se puede repetir dentro de la colección (el canvas lo deja)', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await _armarColeccionDe2(tester, dos: 'Salud y Hogar');
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      await escribir(tester, _campo('venta_talonario'), '0042');
      await tocar(tester, _cta);

      final item = e.ventas.recibidas.single.items.single;
      expect(
        item.componentes!.firstWhere((c) => c.productoId == 'p-libro-0').cantidad,
        2,
        reason: 'el mismo libro dos veces va como cantidad 2 en la colección',
      );
    });

    testWidgets('un pack fijo (sin libros a elegir) se agrega sin elegir nada', (tester) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await tocar(tester, find.text('Pack Familia'));
      await tocar(tester, find.text(TextosVenta.armarLaColeccion));

      expect(find.text('LIBROS QUE ELEGÍS'), findsNothing);
      expect(_habilitado(tester), isTrue);
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      expect(find.text(r'$ 3.000'), findsWidgets);
    });

    testWidgets('sin libros en el catálogo avisa y no deja seguir', (tester) async {
      final base = catalogoDeVentas();
      final e = EntornoDeVenta(
        catalogo: CatalogoLocal(
          productos: base.productos,
          combos: base.combos,
          generales: [
            for (final g in base.generales)
              if (g.productoId != 'p-deseado' && !(g.productoId ?? '').startsWith('p-libro')) g,
          ],
        ),
      );
      await montarNuevaVenta(tester, e);
      await tocar(tester, find.text('Colección de 2 libros'));
      await tocar(tester, find.text(TextosVenta.armarLaColeccion));

      expect(find.byKey(const Key('armar_sin_libros')), findsOneWidget);
      expect(_habilitado(tester), isFalse);
      await tocar(tester, find.byKey(const Key('armar_libro_1')));
      expect(find.byKey(const Key('venta_hoja_libro_vacia')), findsOneWidget);
      expect(find.text(TextosVenta.sinLibrosParaElegir), findsWidgets);
    });
  });

  group('27A·05 Venta con la colección y 27A·06 cambiar un libro', () {
    testWidgets('27A·05 «EN LA VENTA» muestra la colección, el total y las acciones', (
      tester,
    ) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await _ventaConLaColeccion(tester);

      expect(find.text('EN LA VENTA'), findsOneWidget);
      expect(find.text('+ Agregar'), findsOneWidget);
      expect(find.text('COLECCIÓN DE 2 LIBROS'), findsOneWidget);
      expect(find.text('Salud y Hogar · Nuestros Hijos'), findsOneWidget);
      expect(
        find.text('+ El camino a Cristo, Vida Feliz, El Deseado de todas las gentes'),
        findsOneWidget,
      );
      expect(find.text('Total'), findsOneWidget);
      expect(find.byKey(const Key('venta_total')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('venta_total'))).data, r'$ 8.900');
      expect(find.text('Cambiar el monto'), findsOneWidget);
      expect(find.text('Registrar venta'), findsOneWidget);
    });

    testWidgets('sin número de talonario no se registra y la nota dice por qué', (tester) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await _ventaConLaColeccion(tester);

      expect(_habilitado(tester), isFalse);
      expect(find.text(TextosVenta.talonarioVacio), findsOneWidget);
      await escribir(tester, _campo('venta_talonario'), '0042');
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('27A·06 tocar la colección reabre el armado con «Cambiar el libro 1»', (
      tester,
    ) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await _ventaConLaColeccion(tester);

      await tocar(tester, find.text('Salud y Hogar · Nuestros Hijos'));
      expect(find.byKey(const Key('armar_coleccion_pagina')), findsOneWidget);
      expect(find.text('Cambiar'), findsNWidgets(2));
      await tocar(tester, find.byKey(const Key('armar_libro_1')));
      expect(find.text('Cambiar el libro 1'), findsOneWidget);
      await tocar(tester, find.text('Vida sin estrés'));
      await tocar(tester, find.text(TextosVenta.listo));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));

      expect(find.text('Vida sin estrés · Nuestros Hijos'), findsOneWidget);
      expect(find.text('Salud y Hogar · Nuestros Hijos'), findsNothing);
      expect(find.byKey(const Key('venta_total')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('venta_total'))).data, r'$ 8.900');
    });

    testWidgets('desde el armado se puede sacar la colección de la venta', (tester) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await _ventaConLaColeccion(tester);
      await tocar(tester, find.text('Salud y Hogar · Nuestros Hijos'));

      await tocar(tester, find.byKey(const Key('armar_quitar')));

      expect(find.text('EN LA VENTA'), findsNothing);
      expect(find.text('Colección de 2 libros'), findsOneWidget);
    });

    testWidgets('«Registrar venta» guarda la colección con lo que traía y cierra con la venta', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      final salida = await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '  0042 ');

      await tocar(tester, _cta);

      final recibida = e.ventas.recibidas.single;
      expect(recibida.venta.numeroTalonario, '0042');
      expect(recibida.venta.montoTotalCentavos, 890000);
      expect(recibida.venta.espacioPersonaId, 'ep-1');
      expect(recibida.venta.colportorId, 'col-1');
      expect(recibida.diferencia, isNull);
      final item = recibida.items.single;
      expect(item.coleccionId, 'k-2');
      expect(item.productoId, isNull);
      expect(item.cantidad, 1);
      expect(item.componentes, const [
        ComponenteVendido(productoId: 'p-camino'),
        ComponenteVendido(productoId: 'p-deseado'),
        ComponenteVendido(productoId: 'p-libro-0'),
        ComponenteVendido(productoId: 'p-libro-1'),
        ComponenteVendido(productoId: 'p-vida-feliz'),
      ]);
      expect(salida.cerrada, isTrue);
      expect(salida.guardada!.venta.id, recibida.venta.id);
    });
  });

  group('27A·07 y 27A·08 Productos sueltos', () {
    testWidgets('27A·07 revistas con cantidad: suman al total', (tester) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await tocar(tester, find.text('+ Agregar'));

      expect(find.text('Agregar productos'), findsOneWidget);
      expect(find.text('NUEVA VENTA · AGREGAR'), findsOneWidget);
      await tocar(tester, find.text('Revistas'));
      expect(find.text('Vida Feliz'), findsOneWidget);
      expect(find.text('Nuestra Salud'), findsOneWidget);
      expect(find.text('Revista'), findsNWidgets(2));
      expect(_habilitado(tester), isFalse);
      await tocar(tester, find.byTooltip('Uno más de Vida Feliz'));
      await tocar(tester, find.byTooltip('Uno más de Vida Feliz'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));

      expect(find.text(r'2 × $ 120'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('venta_total'))).data, r'$ 9.140');
      await escribir(tester, _campo('venta_talonario'), '7');
      await tocar(tester, _cta);
      final items = e.ventas.recibidas.single.items;
      expect(items.length, 2);
      expect(items.last.productoId, 'p-vida-feliz');
      expect([items.last.cantidad, items.last.precioUnitarioCentavos], [2, 12000]);
    });

    testWidgets('27A·08 misioneros «sin cobrar» no suman y quedan con precio 0', (tester) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await tocar(tester, find.text('+ Agregar'));
      await tocar(tester, find.text('Misioneros'));

      expect(find.text('Entregarlos sin cobrar'), findsOneWidget);
      expect(find.text('No suman al total de la venta.'), findsOneWidget);
      expect(find.text('✦ Misionero'), findsNWidgets(2));
      for (var i = 0; i < 3; i++) {
        await tocar(tester, find.byTooltip('Uno más de El camino a Cristo'));
      }
      await tocar(tester, find.byKey(const Key('venta_sin_cobrar')));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));

      expect(find.text('3 · sin cobrar'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('venta_total'))).data, r'$ 8.900');
      await escribir(tester, _campo('venta_talonario'), '8');
      await tocar(tester, _cta);
      final item = e.ventas.recibidas.single.items.last;
      expect(
        [item.productoId, item.cantidad, item.precioUnitarioCentavos, item.subtotalCentavos],
        ['p-camino', 3, 0, 0],
      );
    });

    testWidgets('sin colecciones se parte de la primera categoría que tiene productos', (
      tester,
    ) async {
      final base = catalogoDeVentas();
      await montarNuevaVenta(
        tester,
        EntornoDeVenta(
          catalogo: CatalogoLocal(
            productos: base.productos,
            generales: [
              for (final g in base.generales)
                if (g.comboId == null) g,
            ],
          ),
        ),
      );

      expect(find.text('Salud y Hogar'), findsOneWidget);
      expect(find.text(TextosVenta.armarLaColeccion), findsNothing);
      await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      expect(find.text('EN LA VENTA'), findsOneWidget);
      expect(find.text(r'1 × $ 2.000'), findsOneWidget);
    });

    testWidgets('categoría sin productos lo dice sin inventar precios', (tester) async {
      final base = catalogoDeVentas();
      await montarNuevaVenta(
        tester,
        EntornoDeVenta(
          catalogo: CatalogoLocal(
            productos: base.productos,
            combos: base.combos,
            generales: [
              for (final g in base.generales)
                if (g.productoId != 'p-vida-feliz' && g.productoId != 'p-nuestra-salud') g,
            ],
          ),
        ),
      );

      await tocar(tester, find.text('Revistas'));

      expect(find.byKey(const Key('venta_categoria_vacia')), findsOneWidget);
      expect(find.text('No hay productos en esta categoría'), findsOneWidget);
    });

    testWidgets('un suelto se saca de la venta con la ✕ y la venta sigue', (tester) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await _ventaConLaColeccion(tester);
      await tocar(tester, find.text('+ Agregar'));
      await tocar(tester, find.text('Revistas'));
      await tocar(tester, find.byTooltip('Uno más de Vida Feliz'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      expect(tester.widget<Text>(find.byKey(const Key('venta_total'))).data, r'$ 9.020');

      await tocar(tester, find.byTooltip('Quitar de la venta').last);

      expect(tester.widget<Text>(find.byKey(const Key('venta_total'))).data, r'$ 8.900');
    });
  });

  group('27A·10 Campaña terminada', () {
    testWidgets('no se vende: dice qué campaña terminó y deja volver', (tester) async {
      final e = EntornoDeVenta(
        precios: SinCampaniaVigente(
          terminada: CampaniaTerminada(nombre: 'Primavera 2026', terminoEl: DateTime(2026, 12, 15)),
        ),
      );
      await montarNuevaVenta(tester, e);

      expect(find.byKey(const Key('venta_campania_terminada')), findsOneWidget);
      expect(find.text('Primavera 2026 terminó el 15/12'), findsOneWidget);
      expect(find.textContaining('Sus precios ya no se usan para vender'), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.text('Nº DE TALONARIO'), findsNothing);
      await tocar(tester, find.text('Volver'));
      expect(find.byKey(const Key('nueva_venta_pagina')), findsNothing);
    });

    testWidgets('sin ninguna campaña conocida no inventa una fecha', (tester) async {
      await montarNuevaVenta(tester, EntornoDeVenta(precios: const SinCampaniaVigente()));

      expect(find.text('No tenés precios vigentes'), findsOneWidget);
    });
  });

  group('27A·11 Talonario repetido', () {
    testWidgets('avisa mientras escribe, con el día de la venta, y no deja registrar', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      e.ventas.talonario = VentaDelTalonario(ventaId: 'v-0', fecha: DateTime.utc(2026, 3, 12, 15));
      await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);

      await escribir(tester, _campo('venta_talonario'), '0042');

      expect(
        find.text('Ya usaste el talonario 0042 este año (venta del 12/03). Revisá el número.'),
        findsOneWidget,
      );
      expect(_habilitado(tester), isFalse);
      e.ventas.talonario = null;
      await escribir(tester, _campo('venta_talonario'), '0043');
      expect(find.textContaining('Ya usaste el talonario'), findsNothing);
      expect(_habilitado(tester), isTrue);
    });

    testWidgets(
      'si el repetido aparece recién al guardar, también queda marcado y no se pierde nada',
      (tester) async {
        final e = EntornoDeVenta();
        e.ventas.respuesta = FailureTalonarioRepetido(
          numero: '0042',
          ventaDel: DateTime(2026, 3, 12),
        );
        await montarNuevaVenta(tester, e);
        await _ventaConLaColeccion(tester);
        await escribir(tester, _campo('venta_talonario'), '0042');

        await tocar(tester, _cta);

        expect(find.textContaining('Ya usaste el talonario 0042'), findsOneWidget);
        expect(find.text('Salud y Hogar · Nuestros Hijos'), findsOneWidget);
        expect(find.byKey(const Key('venta_error')), findsNothing);
        expect(_habilitado(tester), isFalse);
      },
    );
  });

  group('27A·12 Monto cambiado a mano', () {
    testWidgets('muestra lo calculado, el monto, el aviso al coordinador y el motivo', (
      tester,
    ) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await _ventaConLaColeccion(tester);

      await tocar(tester, find.text('Cambiar el monto'));

      expect(find.text('Calculado'), findsOneWidget);
      expect(find.text(r'$ 8.900'), findsWidgets);
      expect(find.text('MONTO DE LA VENTA'), findsWidgets);
      expect(find.text('Tu coordinador va a ver que lo cambiaste.'), findsOneWidget);
      await verVisible(tester, find.text(TextosVenta.avisoMotivo));
      expect(
        find.text('Tu coordinador va a leer este motivo. No pongas datos del cliente.'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(_campo('venta_monto')).controller!.text, '8.900');
    });

    testWidgets('guarda el monto a mano, el motivo sin espacios de los bordes y la diferencia', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');
      await tocar(tester, find.text('Cambiar el monto'));

      await escribir(tester, _campo('venta_monto'), r'$ 8.500');
      await escribir(tester, _campo('venta_motivo'), '  descuento por pago en efectivo \n');
      await tocar(tester, _cta);

      final r = e.ventas.recibidas.single;
      expect(r.venta.montoTotalCentavos, 850000);
      expect(r.venta.motivoMontoManual, 'descuento por pago en efectivo');
      expect(r.diferencia, -40000);
      expect(r.items.single.subtotalCentavos, 890000, reason: 'el ítem guarda el precio de lista');
    });

    testWidgets('un monto que no es un monto no deja registrar y lo explica', (tester) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');
      await tocar(tester, find.text('Cambiar el monto'));

      await escribir(tester, _campo('venta_monto'), 'abc');

      expect(find.text('Escribí un monto válido, por ejemplo 8.500.'), findsOneWidget);
      expect(_habilitado(tester), isFalse);
      await escribir(tester, _campo('venta_monto'), '8500,50');
      expect(find.text('Escribí un monto válido, por ejemplo 8.500.'), findsNothing);
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('«Volver al monto calculado» deja el total de lista y borra el motivo', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');
      await tocar(tester, find.text('Cambiar el monto'));
      await escribir(tester, _campo('venta_monto'), '100');
      await escribir(tester, _campo('venta_motivo'), 'motivo');

      await tocar(tester, find.byKey(const Key('venta_usar_calculado')));
      await tocar(tester, _cta);

      final r = e.ventas.recibidas.single;
      expect(r.venta.montoTotalCentavos, 890000);
      expect(r.venta.motivoMontoManual, isNull);
      expect(r.diferencia, isNull);
    });

    testWidgets('un motivo de más de 500 caracteres no se rechaza: llega cortado', (tester) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');
      await tocar(tester, find.text('Cambiar el monto'));
      await escribir(tester, _campo('venta_monto'), '1');

      await escribir(tester, _campo('venta_motivo'), 'x' * 800);
      await tocar(tester, _cta);

      expect(e.ventas.recibidas.single.venta.motivoMontoManual!.length, lessThanOrEqualTo(500));
    });
  });

  group('27A·13 Error al guardar', () {
    testWidgets('muestra el aviso, no pierde lo cargado y deja «Reintentar»', (tester) async {
      final e = EntornoDeVenta();
      e.ventas.respuesta = const FailureVentaNoGuardada();
      await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');

      await tocar(tester, _cta);

      expect(
        find.text(
          'No pudimos guardar la venta en tu teléfono. No se perdió nada de lo que cargaste: '
          'probá de nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Salud y Hogar · Nuestros Hijos'), findsOneWidget);
      expect(tester.widget<TextField>(_campo('venta_talonario')).controller!.text, '0042');
      expect(_habilitado(tester), isTrue, reason: 'el botón no queda trabado en «guardando»');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('«Reintentar» guarda la misma venta, una sola vez', (tester) async {
      final e = EntornoDeVenta();
      e.ventas.respuesta = const FailureVentaNoGuardada();
      final salida = await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');
      await tocar(tester, _cta);
      e.ventas.respuesta = null;

      await tocar(tester, _cta);

      expect(e.ventas.recibidas.length, 2);
      expect(e.ventas.recibidas[0].venta.id, e.ventas.recibidas[1].venta.id);
      expect(salida.cerrada, isTrue);
    });

    testWidgets('si falla algo inesperado, la base cerrada incluida, vuelve a poder intentarse', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');
      e.ventas.respuesta = const FailureInesperado();

      await tocar(tester, _cta);

      expect(find.byKey(const Key('venta_error')), findsOneWidget);
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('el aviso se va apenas la colportora toca algo', (tester) async {
      final e = EntornoDeVenta();
      e.ventas.respuesta = const FailureVentaNoGuardada();
      await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');
      await tocar(tester, _cta);

      await escribir(tester, _campo('venta_talonario'), '0043');

      expect(find.byKey(const Key('venta_error')), findsNothing);
      expect(find.text('Registrar venta'), findsOneWidget);
    });
  });

  group('Estados que el canvas no dibuja', () {
    testWidgets('cargando: esqueleto, con el cliente a la vista', (tester) async {
      final e = EntornoDeVenta();
      e.fuente.bloqueo = Completer<void>();
      await montarNuevaVenta(tester, e);

      expect(find.byKey(const Key('venta_cargando')), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget);
      e.fuente.bloqueo!.complete();
      await asentar(tester);
      expect(find.byKey(const Key('venta_cargando')), findsNothing);
      expect(find.text('Colección de 2 libros'), findsOneWidget);
    });

    testWidgets('no se pudo leer la ciudad: lo dice y deja reintentar, sin afirmar nada falso', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      e.fuente.respuesta = const Left(FailurePreciosNoDisponibles());
      await montarNuevaVenta(tester, e);

      expect(find.text('No pudimos leer los precios guardados en tu teléfono.'), findsOneWidget);
      expect(find.text('No tenés precios vigentes'), findsNothing);
      e.fuente.respuesta = const Right(PreciosVigentes(cMontevideo));
      await tocar(tester, find.text('Reintentar'));
      expect(find.text('Colección de 2 libros'), findsOneWidget);
      expect(e.fuente.lecturas, 2);
    });

    testWidgets('no se pudo leer el catálogo: error con «Reintentar» y después carga', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      e.repo.fallas = 1;
      await montarNuevaVenta(tester, e);

      expect(find.text('No pudimos leer los precios guardados en tu teléfono.'), findsOneWidget);
      await tocar(tester, find.text('Reintentar'));
      expect(find.text('Colección de 2 libros'), findsOneWidget);
    });

    testWidgets('catálogo vacío: «No tenés precios vigentes», nunca una lista vacía muda', (
      tester,
    ) async {
      await montarNuevaVenta(tester, EntornoDeVenta(catalogo: const CatalogoLocal()));

      expect(find.byKey(const Key('venta_sin_precios')), findsOneWidget);
      expect(find.text('No tenés precios vigentes'), findsOneWidget);
    });

    testWidgets('sin conexión se registra igual: la venta se guarda en el teléfono', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      final salida = await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');

      await tocar(tester, _cta);

      expect(salida.cerrada, isTrue);
      expect(e.ventas.recibidas, hasLength(1));
    });
  });

  group('Casos límite', () {
    testWidgets('doble toque en «Registrar venta»: se guarda una sola vez', (tester) async {
      final e = EntornoDeVenta();
      final espera = Completer<void>();
      e.ventas.compuerta = espera.future;
      final salida = await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');

      await tester.tap(_cta);
      await tester.pump();
      await tester.tap(_cta, warnIfMissed: false);
      await tester.pump();

      expect(e.ventas.recibidas, hasLength(1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<TextField>(_campo('venta_talonario')).enabled, isFalse);
      espera.complete();
      await asentar(tester);
      expect(e.ventas.recibidas, hasLength(1));
      expect(salida.cerrada, isTrue);
    });

    testWidgets('dos toques seguidos en «+ Agregar»: se abre una sola pantalla', (tester) async {
      await montarNuevaVenta(tester, EntornoDeVenta());
      await _ventaConLaColeccion(tester);

      await tester.ensureVisible(find.text('+ Agregar'));
      await tester.tap(find.text('+ Agregar'));
      await tester.tap(find.text('+ Agregar'), warnIfMissed: false);
      await asentar(tester);

      expect(
        find.byKey(const Key('agregar_productos_pagina'), skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('dos colecciones iguales son una con cantidad 2; distintas, dos de 1', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await tocar(tester, find.text('+ Agregar'));
      await tocar(tester, find.text('Colección de 2 libros'));
      await tocar(tester, find.text(TextosVenta.armarLaColeccion));
      for (final (i, nombre) in ['Nuestros Hijos', 'Salud y Hogar'].indexed) {
        await tocar(tester, find.byKey(Key('armar_libro_${i + 1}')));
        await tocar(tester, find.text(nombre));
        await tocar(tester, find.text(TextosVenta.listo));
      }
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      // Mismos libros en otro orden: es la misma colección.
      expect(find.textContaining('×2'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('venta_total'))).data, r'$ 17.800');

      await tocar(tester, find.text('+ Agregar'));
      await tocar(tester, find.text('Colección de 1 libro'));
      await tocar(tester, find.text(TextosVenta.armarLaColeccion));
      await tocar(tester, find.byKey(const Key('armar_libro_1')));
      await tocar(tester, find.text('El hogar feliz'));
      await tocar(tester, find.text(TextosVenta.listo));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));

      await escribir(tester, _campo('venta_talonario'), '0042');
      await tocar(tester, _cta);
      final items = e.ventas.recibidas.single.items;
      expect(items.map((i) => i.cantidad).toList(), [2, 1]);
      expect(items.map((i) => i.coleccionId).toList(), ['k-2', 'k-1']);
    });

    testWidgets('salir con la venta a medias pide confirmar; «Seguir» no pierde nada', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      final salida = await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);

      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(find.text('Esta venta todavía no se registró'), findsOneWidget);
      await tocar(tester, find.text('Seguir con la venta'));
      expect(find.text('Salud y Hogar · Nuestros Hijos'), findsOneWidget);
      expect(salida.cerrada, isFalse);

      await tester.binding.handlePopRoute();
      await asentar(tester);
      await tocar(tester, find.text('Salir'));

      expect(salida.cerrada, isTrue);
      expect(salida.guardada, isNull);
      expect(e.ventas.recibidas, isEmpty, reason: 'salir no guarda nada');
    });

    testWidgets('volver y reentrar: otra venta, vacía y con otro id, sin restos de la anterior', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');
      await tester.binding.handlePopRoute();
      await asentar(tester);
      await tocar(tester, find.text('Salir'));

      await tocar(tester, find.byKey(const Key('abrir_venta')));

      expect(tester.widget<TextField>(_campo('venta_talonario')).controller!.text, isEmpty);
      expect(find.text('EN LA VENTA'), findsNothing);
      expect(find.text('Colección de 2 libros'), findsOneWidget);
      await _armarColeccionDe2(tester, dos: 'Nuestros Hijos');
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      await escribir(tester, _campo('venta_talonario'), '0042');
      await tocar(tester, _cta);
    });

    testWidgets('sin nada cargado, volver sale directo', (tester) async {
      final salida = await montarNuevaVenta(tester, EntornoDeVenta());

      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(salida.cerrada, isTrue);
      expect(find.text('Esta venta todavía no se registró'), findsNothing);
    });

    testWidgets('el antesDeGuardar de la entrevista corre al registrar, antes de la venta', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      var corrio = 0;
      await montarNuevaVenta(tester, e, antesDeGuardar: () async => corrio++);
      await _ventaConLaColeccion(tester);
      await escribir(tester, _campo('venta_talonario'), '0042');

      await tocar(tester, _cta);

      expect(corrio, 1);
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'textos largos y texto al ${(escala * 100).round()} %: nada se corta ni desborda',
        (tester) async {
          final e = EntornoDeVenta();
          await montarNuevaVenta(
            tester,
            e,
            escala: escala,
            tamano: const Size(360, 640),
            cliente: const ClienteDeLaVenta(
              espacioPersonaId: 'ep-1',
              nombre: 'María de los Ángeles Fernández de la Peña y Rodríguez Santos',
              direccion:
                  'Avenida Doctor Luis Alberto de Herrera 1234 bis · Depto 12 B · Torre Norte',
            ),
          );
          expect(tester.takeException(), isNull);
          await tocar(tester, find.text('Colección de 2 libros'));
          await tocar(tester, find.text(TextosVenta.armarLaColeccion));
          expect(tester.takeException(), isNull);
          await tocar(tester, find.byKey(const Key('armar_libro_1')));
          expect(tester.takeException(), isNull);
          await escribir(tester, _campo('venta_hoja_libro_busqueda'), 'Salud');
          await tocar(tester, find.text('Salud y Hogar'));
          await tocar(tester, find.text(TextosVenta.listo));
          await tocar(tester, find.byKey(const Key('armar_libro_2')));
          await escribir(tester, _campo('venta_hoja_libro_busqueda'), 'Nuestros');
          await tocar(tester, find.text('Nuestros Hijos'));
          await tocar(tester, find.text(TextosVenta.listo));
          await tocar(tester, find.text(TextosVenta.agregarALaVenta));
          expect(tester.takeException(), isNull);
          await tocar(tester, find.text('Cambiar el monto'));
          await escribir(tester, _campo('venta_motivo'), 'm' * 400);
          expect(tester.takeException(), isNull);
          expect(find.text('Registrar venta'), findsOneWidget);
          // El botón se puede tocar con el texto grande: mide lo que su texto y nunca menos de 48.
          expect(tester.getSize(_cta).height, greaterThanOrEqualTo(48));
        },
      );
    }

    testWidgets('lista larga de libros: la hoja busca entre 300 y no se traba', (tester) async {
      await montarNuevaVenta(tester, EntornoDeVenta(catalogo: catalogoDeVentas(libros: 300)));
      await tocar(tester, find.text('Colección de 2 libros'));
      await tocar(tester, find.text(TextosVenta.armarLaColeccion));
      await tocar(tester, find.byKey(const Key('armar_libro_1')));

      await escribir(tester, _campo('venta_hoja_libro_busqueda'), 'Libro 0250');
      expect(find.byWidgetPredicate((w) => w is Text && w.data == 'Libro 0250'), findsOneWidget);
      await escribir(tester, _campo('venta_hoja_libro_busqueda'), 'zzz no existe');
      expect(find.text('No encontramos ese libro'), findsOneWidget);
      await escribir(tester, _campo('venta_hoja_libro_busqueda'), '');
      expect(tester.takeException(), isNull);
    });

    testWidgets('categoría con cientos de productos sueltos: se arma la lista y se agrega', (
      tester,
    ) async {
      final e = EntornoDeVenta(catalogo: catalogoDeVentas(libros: 300));
      await montarNuevaVenta(tester, e);
      await tocar(tester, find.text('Libros'));

      await tocar(tester, find.byTooltip('Uno más de El hogar feliz'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));

      expect(find.text('EN LA VENTA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Formato de montos', () {
    test('se leen con punto de miles, coma decimal y símbolo', () {
      expect(FormatoVenta.parsearMonto('8500'), 850000);
      expect(FormatoVenta.parsearMonto(r'$ 8.500'), 850000);
      expect(FormatoVenta.parsearMonto('8.500,5'), 850050);
      expect(FormatoVenta.parsearMonto('1.234.567,89'), 123456789);
      expect(FormatoVenta.parsearMonto('0'), 0);
    });

    test('lo que no es un monto no se lee', () {
      for (final malo in [
        '',
        ' ',
        'abc',
        '-5',
        '8,500,1',
        '85.0',
        '8.50',
        '1,234',
        '99999999999',
      ]) {
        expect(FormatoVenta.parsearMonto(malo), isNull, reason: malo);
      }
    });
  });
}
