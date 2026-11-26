// QA de #769 (PR #773, «Pedir mater.», vista 37A): la cuarta pestaña «Materiales» del pedido a la casa editora,
// en 360x640 y 412x915 con el texto al 100 % y al 200 %, con las guías de accesibilidad de Flutter y las
// fuentes reales: vacía, con productos, con el pedido armado (suma, límite) y con nombres largos.
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/armado_del_pedido.dart';
import 'package:colportores_mobile/features/pedidos/presentation/textos_pedidos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pedidos_arnes.dart';
import '../../helpers/pedidos_falsos.dart';
import '../../helpers/qa_vista37_387_arnes.dart' show cargarFuentes37, capturar37;

const _tamanos = <(String, Size)>[('360x640', Size(360, 640)), ('412x915', Size(412, 915))];

/// Texto al 100 % y al 200 %; con las fuentes reales de la app (anchos y desbordes) y con Ahem (el contraste: con
/// fuentes reales la guía mide el antialias del texto chico y da falsos positivos).
/// Primero con Ahem (el contraste) y después con las fuentes reales: cargarlas vale para todo el archivo.
final _matriz = <(String, Size, double, bool)>[
  for (final reales in const [false, true])
    for (final escala in const [1.0, 2.0])
      for (final (nombre, tamano) in _tamanos) (nombre, tamano, escala, reales),
];

Future<void> _fuentes(WidgetTester tester, bool reales) async {
  if (reales) await cargarFuentes37(tester);
}

void _sinDesborde(WidgetTester tester, bool reales) {
  final e = tester.takeException();
  if (reales) expect(e, isNull);
}

const _cuaderno = ProductoPedible(
  id: 'p-mat',
  nombre: 'Cuaderno de ruta',
  categoriaDelCatalogo: CategoriaDeProducto.material,
  precioDeCompraCentavos: 25000,
);

const _largo = ProductoPedible(
  id: 'p-mat-largo',
  nombre: 'Maletín de colportor con bandolera reforzada y bolsillo para el talonario de cobros',
  categoriaDelCatalogo: CategoriaDeProducto.material,
  precioDeCompraCentavos: 123456789,
  stock: 12345,
);

Finder get _enviar => find.byKey(const Key('pedidos_boton_principal'));
Finder get _chipMateriales => find.byKey(const Key('pedido_chip_materiales'));

Future<void> _guias(WidgetTester tester, bool reales) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (!reales) await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  for (final (nombre, tamano, escala, reales) in _matriz) {
    {
      group('37A · Materiales · $nombre · texto ${escala}x ${reales ? 'real' : 'Ahem'}', () {
        testWidgets('con productos: pestaña, fila, suma y guías', (tester) async {
          await _fuentes(tester, reales);
          final arnes = ArnesDePedidos(
            armado: ArmadoFalso(productos: const [saludYHogar, _cuaderno, _largo]),
          );
          await montarPedir(tester, arnes, tamano: tamano, escala: escala);

          await tocar(tester, _chipMateriales);
          expect(find.text('Cuaderno de ruta', findRichText: true), findsOneWidget);
          _sinDesborde(tester, reales);
          await _guias(tester, reales);
          if (reales) await capturar37(tester, '769_37A_materiales_${nombre}_$escala');

          await sumar(tester, 'p-mat', 3);
          await sumar(tester, 'p-mat-largo', 1);
          _sinDesborde(tester, reales);
          expect(_enviar, findsOneWidget);
          await _guias(tester, reales);
          if (reales) await capturar37(tester, '769_37A_materiales_sumados_${nombre}_$escala');
        });

        testWidgets('sin materiales: lo dice, guía y las guías pasan', (tester) async {
          await _fuentes(tester, reales);
          await montarPedir(tester, ArnesDePedidos(), tamano: tamano, escala: escala);

          await tocar(tester, _chipMateriales);
          expect(
            find.text(TextosPedidos.sinProductosEnCategoria, findRichText: true),
            findsOneWidget,
          );
          _sinDesborde(tester, reales);
          await _guias(tester, reales);
          if (reales) await capturar37(tester, '769_37A_materiales_vacio_${nombre}_$escala');
        });

        testWidgets('supera el límite solo por los materiales: avisa y no bloquea', (tester) async {
          await _fuentes(tester, reales);
          final arnes = ArnesDePedidos(
            armado: ArmadoFalso(productos: const [saludYHogar, _cuaderno]),
            limitePesos: 18500,
          );
          await montarPedir(tester, arnes, tamano: tamano, escala: escala);
          await tocar(tester, _chipMateriales);
          await sumar(tester, 'p-mat', 2);

          expect(find.textContaining('pasa el límite'), findsOneWidget);
          expect(tester.widget<FilledButton>(_enviar).onPressed, isNotNull);
          _sinDesborde(tester, reales);
          await _guias(tester, reales);
          if (reales) await capturar37(tester, '769_37A_materiales_limite_${nombre}_$escala');
        });
      });
    }
  }

  group('37A · Materiales · casos límite', () {
    testWidgets(
      'el pedido mezcla libros y materiales: se envía todo y el chip de cada uno cuenta lo suyo',
      (tester) async {
        final arnes = ArnesDePedidos(
          armado: ArmadoFalso(productos: const [saludYHogar, _cuaderno]),
        );
        await montarPedir(tester, arnes);

        await sumar(tester, 'p-salud', 2);
        await tocar(tester, _chipMateriales);
        await sumar(tester, 'p-mat', 3);

        expect(find.text('Materiales · 3', findRichText: true), findsOneWidget);
        expect(find.text('Libros · 2', findRichText: true), findsOneWidget);

        await tocar(tester, _enviar, cuadros: 6);
        final lineas = arnes.pedidos.enviados.single.lineas;
        expect(
          {for (final l in lineas) l.productoId: l.cantidadVigente},
          {'p-salud': 2, 'p-mat': 3},
        );
      },
    );

    testWidgets('sumar y volver a cero un material apaga «Enviar» y el chip vuelve a cero', (
      tester,
    ) async {
      final arnes = ArnesDePedidos(armado: ArmadoFalso(productos: const [_cuaderno]));
      await montarPedir(tester, arnes);
      await tocar(tester, _chipMateriales);

      await sumar(tester, 'p-mat', 2);
      await tocar(tester, find.byKey(const Key('pedido_menos_p-mat')));
      await tocar(tester, find.byKey(const Key('pedido_menos_p-mat')));

      expect(find.text('Materiales', findRichText: true), findsOneWidget);
      expect(tester.widget<FilledButton>(_enviar).onPressed, isNull);
    });
  });
}
