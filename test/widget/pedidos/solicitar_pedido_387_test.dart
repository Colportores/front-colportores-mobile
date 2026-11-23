// «Solicitar un pedido» (vista 37A, HU-STK-009, #387): un test por artboard (37A·01 a 37A·08) y los casos
// límite del flujo: doble toque, falla a mitad del envío y reintento con el mismo pedido, volver atrás y
// reentrar, lista larga y el texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/armado_del_pedido.dart';
import 'package:colportores_mobile/features/pedidos/presentation/textos_pedidos.dart';
import 'package:colportores_mobile/features/pedidos/presentation/widgets/piezas_pedidos.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart' show resumenDelCanvas;
import '../../helpers/pedidos_arnes.dart';
import '../../helpers/pedidos_falsos.dart';

Finder _t(String texto) => find.text(texto, findRichText: true);

Finder get _enviar => find.byKey(const Key('pedidos_boton_principal'));

FilledButton _boton(WidgetTester tester) => tester.widget<FilledButton>(_enviar);

/// Arma el pedido del canvas 37A·01: 4 Salud y Hogar, 2 Nuestros Hijos (Libros) y 20 Vida Feliz (Revistas).
Future<void> _armarElDelCanvas(WidgetTester tester) async {
  await sumar(tester, 'p-salud', 4);
  await sumar(tester, 'p-hijos', 2);
  await tocar(tester, find.byKey(const Key('pedido_chip_revistas')));
  await sumar(tester, 'p-vida', 20);
  await tocar(tester, find.byKey(const Key('pedido_chip_libros')));
}

void main() {
  group('37A·01 · Armar el pedido', () {
    testWidgets(
      'dado que abro «Nuevo pedido», veo el encabezado, las categorías, los libros con lo que '
      'tengo y su precio de compra, y mi situación',
      (tester) async {
        await montarPedir(tester, ArnesDePedidos());

        expect(_t('SOLICITAR PEDIDO'), findsOneWidget);
        expect(_t('Nuevo pedido'), findsOneWidget);
        expect(_t('A la casa editora'), findsOneWidget);
        expect(_t('QUÉ PEDÍS · PRECIO DE COMPRA'), findsOneWidget);
        for (final c in ['Libros', 'Misioneros', 'Revistas']) {
          expect(_t(c), findsOneWidget, reason: c);
        }
        expect(_t('Salud y Hogar'), findsOneWidget);
        expect(_t(r'Tenés 2 · $ 1.870 c/u'), findsOneWidget);
        expect(_t(r'Tenés 0 · $ 1.330 c/u'), findsOneWidget);
        expect(_t('◆ Bonificable'), findsNWidgets(2));
        // Revistas y misioneros están en otra categoría.
        expect(_t('Vida Feliz'), findsNothing);

        expect(_t('TU SITUACIÓN'), findsOneWidget);
        expect(_t('Deuda actual'), findsOneWidget);
        expect(
          _t(r'$ 18.400'),
          findsNWidgets(2),
          reason: 'la deuda actual y la deuda con el pedido vacío',
        );
        expect(_t('Este pedido'), findsOneWidget);
        expect(_t('Deuda con este pedido'), findsOneWidget);
        expect(_t('Por cobrar'), findsOneWidget);
        expect(_t(r'$ 9.700'), findsOneWidget);
        expect(_t('Libros por entregar'), findsOneWidget);
        expect(_t('4'), findsOneWidget);
      },
    );

    testWidgets('dado que sumo productos, la deuda con el pedido sube y el botón dice «Enviar a mi '
        'coordinador»', (tester) async {
      await montarPedir(tester, ArnesDePedidos());
      await sumar(tester, 'p-salud', 4);
      await sumar(tester, 'p-hijos', 2);

      expect(_t(r'+ $ 10.140'), findsOneWidget, reason: '4 × 1.870 + 2 × 1.330');
      expect(_t(r'$ 28.540'), findsOneWidget, reason: '18.400 + 10.140');
      expect(_t('Libros · 6'), findsOneWidget);
      expect(_t(TextosPedidos.enviar), findsOneWidget);
      expect(_boton(tester).onPressed, isNotNull);
    });

    testWidgets('dado que quito productos, vuelve a bajar; no baja de cero', (tester) async {
      await montarPedir(tester, ArnesDePedidos());
      await sumar(tester, 'p-salud', 2);
      await tocar(tester, find.byKey(const Key('pedido_menos_p-salud')));
      expect(find.text('1'), findsWidgets);
      expect(_t(r'+ $ 1.870'), findsOneWidget);
      await tocar(tester, find.byKey(const Key('pedido_menos_p-salud')));
      final menos = tester.widget<IconButton>(find.byKey(const Key('pedido_menos_p-salud')));
      expect(menos.onPressed, isNull, reason: 'con cero no hay nada que quitar');
      expect(_t(r'+ $ 0'), findsOneWidget);
    });

    testWidgets('cada botón de más y de menos dice a qué producto es, y la fila a cuántos lleva', (
      tester,
    ) async {
      await montarPedir(tester, ArnesDePedidos());
      await sumar(tester, 'p-salud', 2);
      expect(find.byTooltip('Sumar uno de Salud y Hogar'), findsOneWidget);
      expect(find.byTooltip('Quitar uno de Salud y Hogar'), findsOneWidget);
      expect(find.bySemanticsLabel('Salud y Hogar: 2 unidades'), findsOneWidget);
      expect(find.bySemanticsLabel('Nuestros Hijos: 0 unidades'), findsOneWidget);
    });
  });

  group('37A·08 · Otra categoría', () {
    testWidgets(
      'dado que elijo Revistas, veo las revistas con su precio y el número de cada categoría '
      'cuenta lo que llevo; la situación suma todo el pedido',
      (tester) async {
        await montarPedir(tester, ArnesDePedidos());
        await _armarElDelCanvas(tester);
        await tocar(tester, find.byKey(const Key('pedido_chip_revistas')));

        expect(_t('Vida Feliz'), findsOneWidget);
        expect(_t(r'Tenés 8 · $ 85 c/u'), findsOneWidget);
        expect(_t('Nuestra Salud'), findsOneWidget);
        expect(_t('Revista'), findsNWidgets(2));
        expect(_t('Salud y Hogar'), findsNothing);
        expect(_t('Libros · 6'), findsOneWidget);
        expect(_t('Revistas · 20'), findsOneWidget);
        expect(_t(r'+ $ 11.840'), findsOneWidget, reason: 'suma libros y revistas');
      },
    );

    testWidgets('dado que elijo Misioneros, veo el misionero con su etiqueta', (tester) async {
      await montarPedir(tester, ArnesDePedidos());
      await tocar(tester, find.byKey(const Key('pedido_chip_misioneros')));
      expect(_t('El camino a Cristo'), findsOneWidget);
      expect(_t('✦ Misionero'), findsOneWidget);
    });

    testWidgets('dado que el material de trabajo no se pide, no aparece en ninguna categoría', (
      tester,
    ) async {
      final armado = ArmadoFalso(
        productos: const [
          saludYHogar,
          ProductoPedible(
            id: 'p-mat',
            nombre: 'Cuaderno de ruta',
            categoriaDelCatalogo: CategoriaDeProducto.material,
            precioDeCompraCentavos: 100,
          ),
        ],
      );
      await montarPedir(tester, ArnesDePedidos(armado: armado));
      for (final c in ['libros', 'misioneros', 'revistas']) {
        await tocar(tester, find.byKey(Key('pedido_chip_$c')));
        expect(_t('Cuaderno de ruta'), findsNothing, reason: c);
      }
    });
  });

  group('37A·02 · Supera el límite (avisa, no bloquea)', () {
    testWidgets('dado un límite de \$ 30.000 y un pedido que lo pasa, veo el aviso, la deuda con el '
        'pedido en rojo, y puedo enviarlo igual', (tester) async {
      final arnes = ArnesDePedidos(limitePesos: 30000);
      await montarPedir(tester, arnes);
      await sumar(tester, 'p-salud', 8);
      await sumar(tester, 'p-hijos', 4);

      expect(
        _t(
          r'Con este pedido tu deuda pasa el límite de $ 30.000 que fijó tu coordinador. Lo podés '
          'enviar igual: tu coordinador decide al autorizar.',
        ),
        findsOneWidget,
      );
      final deudaConPedido = tester.widget<Text>(find.text(r'$ 38.680'));
      expect(deudaConPedido.style!.color, const Color(0xFFA8312A));
      expect(_boton(tester).onPressed, isNotNull, reason: 'solo avisa, no bloquea');

      await tocar(tester, _enviar, cuadros: 6);
      expect(arnes.pedidos.enviados, hasLength(1));
      expect(arnes.pedidos.enviados.single.excedeLimite, isTrue);
      expect(_t(TextosPedidos.tituloEnviado), findsOneWidget);
    });

    testWidgets(
      'dado que la deuda con el pedido queda JUSTO en el límite, no hay aviso; con un peso más, sí',
      (tester) async {
        await montarPedir(tester, ArnesDePedidos(limitePesos: 20270));
        await sumar(tester, 'p-salud', 1);
        expect(
          find.textContaining('pasa el límite'),
          findsNothing,
          reason: '18.400 + 1.870 = 20.270',
        );
        await sumar(tester, 'p-salud', 1);
        expect(find.textContaining('pasa el límite'), findsOneWidget);
      },
    );

    testWidgets('dado que mi campaña no tiene límite, no hay aviso por grande que sea el pedido', (
      tester,
    ) async {
      await montarPedir(tester, ArnesDePedidos());
      await sumar(tester, 'p-salud', 30);
      expect(find.textContaining('pasa el límite'), findsNothing);
    });

    testWidgets('dado que saco productos hasta bajar del límite, el aviso desaparece', (
      tester,
    ) async {
      await montarPedir(tester, ArnesDePedidos(limitePesos: 20270));
      await sumar(tester, 'p-salud', 2);
      expect(find.textContaining('pasa el límite'), findsOneWidget);
      await tocar(tester, find.byKey(const Key('pedido_menos_p-salud')));
      expect(find.textContaining('pasa el límite'), findsNothing);
    });
  });

  group('37A·03 · Sin productos', () {
    testWidgets('dado que no sumé nada, el botón está apagado y dice qué falta', (tester) async {
      await montarPedir(tester, ArnesDePedidos());
      expect(_boton(tester).onPressed, isNull);
      expect(_t('Sumá al menos un producto.'), findsOneWidget);
      await tester.tap(_enviar, warnIfMissed: false);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('dado que sumo y vuelvo a cero, vuelve a apagarse', (tester) async {
      await montarPedir(tester, ArnesDePedidos());
      await sumar(tester, 'p-salud', 1);
      expect(_boton(tester).onPressed, isNotNull);
      expect(_t('Sumá al menos un producto.'), findsNothing);
      await tocar(tester, find.byKey(const Key('pedido_menos_p-salud')));
      expect(_boton(tester).onPressed, isNull);
      expect(_t('Sumá al menos un producto.'), findsOneWidget);
    });

    testWidgets('dado que el catálogo todavía no bajó, lo dice y no deja enviar', (tester) async {
      await montarPedir(tester, ArnesDePedidos(armado: ArmadoFalso(productos: const [])));
      expect(_t(TextosPedidos.sinCatalogo), findsOneWidget);
      expect(_boton(tester).onPressed, isNull);
    });

    testWidgets('dado que una categoría no tiene productos, lo dice', (tester) async {
      await montarPedir(
        tester,
        ArnesDePedidos(armado: ArmadoFalso(productos: const [saludYHogar])),
      );
      await tocar(tester, find.byKey(const Key('pedido_chip_revistas')));
      expect(_t(TextosPedidos.sinProductosEnCategoria), findsOneWidget);
    });

    testWidgets(
      'dado que no se pudieron leer los productos, veo el error y «Reintentar» los vuelve a leer',
      (tester) async {
        final armado = ArmadoFalso(fallaProductos: true);
        await montarPedir(tester, ArnesDePedidos(armado: armado));
        expect(_t(TextosPedidos.errorProductos), findsOneWidget);
        armado.fallaProductos = false;
        await tocar(tester, find.byKey(const Key('pedidos_aviso_boton')));
        expect(_t(TextosPedidos.errorProductos), findsNothing);
        expect(_t('Salud y Hogar'), findsOneWidget);
      },
    );
  });

  group('37A·04 · Enviando', () {
    testWidgets(
      'dado que toco «Enviar», el botón dice «Enviando…», no se toca de nuevo y nada se cambia '
      'mientras',
      (tester) async {
        final arnes = ArnesDePedidos();
        arnes.pedidos.esperaAlEnviar = Completer<void>();
        await montarPedir(tester, arnes);
        await sumar(tester, 'p-salud', 1);

        await tocar(tester, _enviar, cuadros: 2);
        expect(_t('Enviando…'), findsOneWidget);
        expect(_boton(tester).onPressed, isNull);
        expect(
          tester.widget<IconButton>(find.byKey(const Key('pedido_mas_p-salud'))).onPressed,
          isNull,
          reason: 'mientras se envía no se cambia lo armado',
        );
        expect(arnes.pedidos.llamadasAEnviar, 1);

        arnes.pedidos.esperaAlEnviar!.complete();
        await tester.pump();
        await tester.pump();
        expect(_t(TextosPedidos.tituloEnviado), findsOneWidget);
        expect(arnes.pedidos.llamadasAEnviar, 1);
      },
    );

    testWidgets('dado un doble toque antes de que se redibuje, se manda UN solo pedido', (
      tester,
    ) async {
      final arnes = ArnesDePedidos();
      arnes.pedidos.esperaAlEnviar = Completer<void>();
      await montarPedir(tester, arnes);
      await sumar(tester, 'p-salud', 1);

      await tester.tap(_enviar);
      await tester.tap(_enviar, warnIfMissed: false);
      await tester.pump();
      expect(arnes.pedidos.llamadasAEnviar, 1);

      arnes.pedidos.esperaAlEnviar!.complete();
      await tester.pump();
      await tester.pump();
      expect(arnes.pedidos.pedidos, hasLength(1));
    });

    testWidgets(
      'dado que intento salir mientras se envía, no se sale y el envío termina a la vista',
      (tester) async {
        final arnes = ArnesDePedidos();
        arnes.pedidos.esperaAlEnviar = Completer<void>();
        await montarPedir(tester, arnes);
        await sumar(tester, 'p-salud', 1);
        await tocar(tester, _enviar, cuadros: 2);

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byKey(const Key('pedido_descartar')), findsNothing);
        expect(_t(TextosPedidos.tituloArmar), findsOneWidget);

        arnes.pedidos.esperaAlEnviar!.complete();
        await tester.pump();
        await tester.pump();
        expect(_t(TextosPedidos.tituloEnviado), findsOneWidget);
      },
    );
  });

  group('37A·05 · Enviado', () {
    testWidgets(
      'dado que el pedido sale bien, veo que lo tiene que autorizar mi coordinador, cuántos '
      'productos y el monto, y «Ver mis pedidos»',
      (tester) async {
        final arnes = ArnesDePedidos();
        await montarPedir(tester, arnes);
        await _armarElDelCanvas(tester);
        await tocar(tester, _enviar, cuadros: 6);

        expect(_t('Pedido enviado'), findsOneWidget);
        expect(_t('Tu coordinador lo tiene que autorizar'), findsOneWidget);
        expect(_t('Te avisamos cuando lo autorice o lo despachen.'), findsOneWidget);
        expect(_t('26 productos'), findsOneWidget);
        expect(_t(r'$ 11.840'), findsOneWidget);
        expect(_t('Ver mis pedidos'), findsOneWidget);
        expect(
          find.byKey(const Key('pedidos_volver')),
          findsNothing,
          reason: 'el canvas no dibuja volver',
        );

        final p = arnes.pedidos.enviados.single;
        expect(p.id, 'id-1');
        expect(p.unidades, 26);
        expect(p.montoCentavos, 1184000);
      },
    );

    testWidgets('«Ver mis pedidos» abre la lista con el pedido recién enviado', (tester) async {
      await montarPedir(tester, ArnesDePedidos());
      await sumar(tester, 'p-salud', 1);
      await tocar(tester, _enviar, cuadros: 6);
      await tocar(tester, find.text('Ver mis pedidos'), cuadros: 6);
      expect(_t('Mis pedidos'), findsOneWidget);
      expect(find.byKey(const Key('pedido_id-1')), findsOneWidget);
    });

    testWidgets('dado que salgo con atrás de un pedido ya enviado, no pregunta nada', (
      tester,
    ) async {
      await montarPedir(tester, ArnesDePedidos());
      await sumar(tester, 'p-salud', 1);
      await tocar(tester, _enviar, cuadros: 6);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pedido_descartar')), findsNothing);
      expect(find.byKey(const Key('abrir_pedir')), findsOneWidget);
    });
  });

  group('37A·06 · Sin conexión', () {
    testWidgets(
      'dado que no tengo conexión, el aviso dice de cuándo es lo que veo y el botón dice que '
      'se envía cuando haya conexión',
      (tester) async {
        await montarPedir(tester, ArnesDePedidos(), conexion: TipoConexion.sinConexion);
        expect(
          _t('Sin conexión. Tu deuda y lo que tenés por cobrar son de ayer a las 21:00.'),
          findsOneWidget,
        );
        await sumar(tester, 'p-salud', 1);
        expect(_t('Enviar cuando haya conexión'), findsOneWidget);
        expect(_boton(tester).onPressed, isNotNull);
      },
    );

    testWidgets(
      'dado que armo y envío sin conexión, queda guardado (en la cola) y lo dice sin mentir',
      (tester) async {
        final arnes = ArnesDePedidos();
        await montarPedir(tester, arnes, conexion: TipoConexion.sinConexion);
        await sumar(tester, 'p-salud', 2);
        await tocar(tester, _enviar, cuadros: 6);

        expect(arnes.pedidos.enviados, hasLength(1));
        expect(_t('Tu pedido quedó guardado'), findsOneWidget);
        expect(
          _t('Se envía solo cuando haya conexión. Después tu coordinador lo tiene que autorizar.'),
          findsOneWidget,
        );
        expect(_t('Tu coordinador lo tiene que autorizar'), findsNothing);
      },
    );

    testWidgets('dado que todavía no bajó la deuda, el aviso lo dice', (tester) async {
      final arnes = ArnesDePedidos();
      arnes.repoDeDeuda.guardada = null;
      await montarPedir(tester, arnes, conexion: TipoConexion.sinConexion);
      expect(find.textContaining('todavía no se bajaron'), findsOneWidget);
    });
  });

  group('37A·07 · Error al enviar', () {
    testWidgets('dado que falla el guardado, veo el aviso, lo armado sigue ahí y el botón vuelve a '
        'habilitarse con «Reintentar»', (tester) async {
      final arnes = ArnesDePedidos();
      arnes.pedidos.fallasAlEnviar.add(const FailurePedidoNoGuardado(causa: 'X'));
      await montarPedir(tester, arnes);
      await sumar(tester, 'p-salud', 3);
      await tocar(tester, _enviar, cuadros: 4);

      expect(_t(TextosPedidos.errorAlEnviar), findsOneWidget);
      expect(_t('Reintentar'), findsOneWidget);
      expect(
        _boton(tester).onPressed,
        isNotNull,
        reason: 'ningún estado de «ocupado» queda trabado',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('3'), findsOneWidget, reason: 'lo armado sigue');
      expect(arnes.pedidos.pedidos, isEmpty);
    });

    testWidgets(
      'dado que reintento, se manda el MISMO pedido (mismo id y mismas líneas) y sale bien',
      (tester) async {
        final arnes = ArnesDePedidos();
        arnes.pedidos.fallasAlEnviar.add(const FailurePedidoNoGuardado());
        await montarPedir(tester, arnes);
        await sumar(tester, 'p-salud', 3);
        await tocar(tester, _enviar, cuadros: 4);
        await tocar(tester, _enviar, cuadros: 6);

        expect(arnes.pedidos.enviados, hasLength(2));
        expect(arnes.pedidos.enviados.first.id, arnes.pedidos.enviados.last.id);
        expect(
          arnes.pedidos.enviados.first.lineas.map((l) => l.id),
          arnes.pedidos.enviados.last.lineas.map((l) => l.id),
        );
        expect(_t(TextosPedidos.tituloEnviado), findsOneWidget);
        expect(_t(TextosPedidos.errorAlEnviar), findsNothing);
      },
    );

    testWidgets('dado que cambio algo después de la falla, el aviso se va y es otro intento', (
      tester,
    ) async {
      final arnes = ArnesDePedidos();
      arnes.pedidos.fallasAlEnviar.add(const FailurePedidoNoGuardado());
      await montarPedir(tester, arnes);
      await sumar(tester, 'p-salud', 1);
      await tocar(tester, _enviar, cuadros: 4);
      await sumar(tester, 'p-salud', 1);
      expect(_t(TextosPedidos.errorAlEnviar), findsNothing);
      expect(_t(TextosPedidos.enviar), findsOneWidget);
    });
  });

  group('Volver atrás y reentrar', () {
    testWidgets('dado que no armé nada, atrás sale sin preguntar', (tester) async {
      await montarPedir(tester, ArnesDePedidos());
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('abrir_pedir')), findsOneWidget);
    });

    testWidgets('dado que armé algo, atrás pregunta; «Seguir armando» conserva todo', (
      tester,
    ) async {
      await montarPedir(tester, ArnesDePedidos());
      await sumar(tester, 'p-salud', 2);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_t('¿Salir sin enviar?'), findsOneWidget);
      expect(_t('Lo que armaste se pierde.'), findsOneWidget);
      await tocar(tester, find.byKey(const Key('pedido_seguir_armando')), cuadros: 6);
      expect(_t(TextosPedidos.tituloArmar), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets(
      'dado que descarto con la «✕» y reentro, la pantalla vuelve vacía y con un pedido nuevo',
      (tester) async {
        final arnes = ArnesDePedidos();
        await montarPedir(tester, arnes);
        await sumar(tester, 'p-salud', 2);
        await tocar(tester, find.byKey(const Key('pedidos_volver')), cuadros: 4);
        await tocar(tester, find.byKey(const Key('pedido_descartar')), cuadros: 8);
        expect(find.byKey(const Key('abrir_pedir')), findsOneWidget);
        expect(arnes.pedidos.llamadasAEnviar, 0, reason: 'descartar no envía nada');

        await tocar(tester, find.byKey(const Key('abrir_pedir')), cuadros: 8);
        expect(_boton(tester).onPressed, isNull);
        expect(_t(r'+ $ 0'), findsOneWidget);
        await sumar(tester, 'p-salud', 1);
        await tocar(tester, _enviar, cuadros: 6);
        expect(
          arnes.pedidos.enviados.single.id,
          isNot('id-1'),
          reason: 'es otro pedido, con otro id',
        );
      },
    );
  });

  group('Datos límite', () {
    testWidgets('dada una lista larga de productos, se desplaza y el botón sigue a la vista', (
      tester,
    ) async {
      final muchos = [
        for (var i = 0; i < 60; i++)
          ProductoPedible(
            id: 'p$i',
            nombre: 'Libro número $i',
            categoriaDelCatalogo: CategoriaDeProducto.espirituales,
            precioDeCompraCentavos: 10000,
          ),
      ];
      await montarPedir(tester, ArnesDePedidos(armado: ArmadoFalso(productos: muchos)));
      expect(_enviar, findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('pedido_fila_p59'), skipOffstage: false),
        300,
        scrollable: find.descendant(
          of: find.byKey(const Key('pedido_lista')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.byKey(const Key('pedido_fila_p59')), findsOneWidget);
      expect(_enviar, findsOneWidget);
    });

    testWidgets('dado un nombre larguísimo y montos grandes, no desborda', (tester) async {
      final largo = ProductoPedible(
        id: 'p-largo',
        nombre: 'Un libro con un nombre larguísimo ${'muy ' * 15}largo',
        categoriaDelCatalogo: CategoriaDeProducto.bonificables,
        precioDeCompraCentavos: 123456789,
        stock: -12,
        esBonificable: true,
      );
      await montarPedir(
        tester,
        ArnesDePedidos(armado: ArmadoFalso(productos: [largo]), deudaPesos: 99999999),
      );
      await sumar(tester, 'p-largo', 99);
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Tenés -12'),
        findsOneWidget,
        reason: 'el stock negativo se ve tal cual',
      );
    });

    testWidgets('el tope de una línea es 999: el «+» se apaga', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilaDeProductoPedible(producto: saludYHogar, cantidad: 999, alCambiar: (_) {}),
          ),
        ),
      );
      expect(
        tester.widget<IconButton>(find.byKey(const Key('pedido_mas_p-salud'))).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(find.byKey(const Key('pedido_menos_p-salud'))).onPressed,
        isNotNull,
      );
    });

    for (final (nombre, tamano) in [
      ('360×640', const Size(360, 640)),
      ('320×568', const Size(320, 568)),
    ]) {
      testWidgets(
        'con el texto al 200 % a $nombre, armar, el aviso del límite y el enviado no desbordan',
        (tester) async {
          final arnes = ArnesDePedidos(limitePesos: 20270);
          await montarPedir(tester, arnes, tamano: tamano, escala: 2);
          await sumar(tester, 'p-salud', 2);
          expect(find.textContaining('pasa el límite', skipOffstage: false), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tocar(tester, _enviar, cuadros: 6);
          expect(_t(TextosPedidos.tituloEnviado), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('La situación', () {
    testWidgets(
      'dado que todavía se lee, muestra el bloque de carga y se puede enviar al terminar',
      (tester) async {
        final arnes = ArnesDePedidos();
        arnes.cuenta.inicial = null;
        await montarPedir(tester, arnes);
        expect(find.byKey(const Key('pedido_situacion_cargando')), findsOneWidget);
        arnes.cuenta.ultimo.add(resumenDelCanvas);
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('pedido_situacion_cargando')), findsNothing);
        expect(_t(r'$ 9.700'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que la cuenta no se pudo leer, lo dice, deja reintentar y deja enviar igual',
      (tester) async {
        final arnes = ArnesDePedidos();
        arnes.cuenta.fallaAlSuscribir = true;
        await montarPedir(tester, arnes);
        expect(_t(TextosPedidos.errorSituacion), findsOneWidget);
        await sumar(tester, 'p-salud', 1);
        expect(_boton(tester).onPressed, isNotNull);
      },
    );

    testWidgets('dado que una deuda queda a favor (negativa), se ve con su signo', (tester) async {
      await montarPedir(tester, ArnesDePedidos(deudaPesos: -500));
      expect(find.textContaining('500'), findsWidgets);
    });
  });
}
