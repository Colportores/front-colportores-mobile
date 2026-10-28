// QA de «Entregar ahora» (HU-VEN-002, vista 27 grupo B, #159, PR #534). Lo que agrega al test del PR:
// el escenario literal de la HU, cada estado en los tamaños del QA (360×640 y 412×915, texto 1,0 y
// 2,0) sin overflow y con su contenido a la vista, y los casos límite que el PR no cubre. Un test con
// `skip` documenta un hallazgo: `--dart-define=QA_HALLAZGOS=true` los corre. Capturas:
// `--dart-define=QA_CAPTURAS=true`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/productos_de_la_entrega.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/entregar_ahora_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_falsos.dart';
import '../../helpers/qa_entrega_159_arnes.dart';
import '../../helpers/venta_falsos.dart';
import '../../helpers/venta_ui_falsos.dart' show asentar;

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');
const _tamanos = [chico159, grande159];
const _escalas = [1.0, 2.0];

/// Lo que cada estado tiene que mostrar para que la persona sepa qué pasa y qué hacer.
final _contenido = <Estado159, List<Pattern>>{
  Estado159.formulario: ['QUÉ ENTREGÁS', 'Salud y Hogar × 1', 'Entregar'],
  Estado159.parcial: ['Nuestros Hijos queda para otro día.', 'Entregar 3 productos'],
  Estado159.sinNada: ['Elegí al menos un producto para entregar.', 'Entregar'],
  Estado159.cargando: [],
  Estado159.errorDeLectura: [
    'No pudimos leer lo que vendiste en tu teléfono. Probá de nuevo.',
    'Reintentar',
  ],
  Estado159.sinProductos: ['Esta venta no tiene productos para entregar.'],
  Estado159.errorAlGuardar: [
    'No pudimos guardar la entrega en tu teléfono. No se perdió nada de lo que marcaste: probá de nuevo.',
    'Reintentar',
  ],
  Estado159.guardando: [],
  Estado159.completa: ['Listo', 'Venta completa', 'Volver al mapa'],
  Estado159.conSaldo: [
    'Entrega registrada',
    'Entregado',
    'todo',
    'Saldo',
    r'$ 8.900',
    'Volver al mapa',
  ],
  Estado159.conSaldoConDestinos: ['Cobrar ahora', 'Agendar la cobranza', 'Volver al mapa'],
  Estado159.parcialResultado: ['Pendiente', 'Nuestros Hijos × 1', 'Volver al mapa'],
  Estado159.reentrada: ['Entrega registrada', 'Volver al mapa'],
};

String _textoDelBoton(WidgetTester tester) =>
    tester.widget<Text>(find.descendant(of: cta159, matching: find.byType(Text))).data!;

void main() {
  group('Escenario de la HU: venta + entrega inmediata', () {
    testWidgets(
      'Dado una venta de 3 libros, cuando elijo «Entregar ahora» y confirmo, entonces se crea el '
      'registro de entrega con todas las cantidades',
      (tester) async {
        final e = EntornoDeEntrega(
          fuente: FuenteDeProductosFalsa(
            const ProductosDeLaEntrega(
              nombres: {'l-1': 'Salud y Hogar', 'l-2': 'Nuestros Hijos', 'l-3': 'Vida sin estrés'},
            ),
          ),
        );
        final venta = VentaGuardada(
          venta: ventaDe('v-1', talonario: '0042', monto: 150000),
          items: [
            itemDe('i-1', 'v-1', productoId: 'l-1', cantidad: 3),
            itemDe('i-2', 'v-1', productoId: 'l-2', cantidad: 1),
            itemDe('i-3', 'v-1', productoId: 'l-3', cantidad: 2),
          ],
        );
        final m = await montar159(tester, Estado159.formulario, venta: venta, entorno: e);
        expect(filas159, findsNWidgets(3));
        await tocarCta159(tester);

        final filas = e.entregas.recibidas.single.filas;
        expect(filas, hasLength(3));
        expect({for (final f in filas) f.productoId: f.cantidad}, {'l-1': 3, 'l-2': 1, 'l-3': 2});
        expect(filas.every((f) => !f.pendiente && f.fechaEntrega == e.ahora), isTrue);
        expect(m.salida.cerrada, isFalse);
        expect(find.text('Entrega registrada'), findsOneWidget);
        expect(find.text('todo'), findsOneWidget);
      },
    );

    testWidgets('un solo producto: se entrega con «Entregar» y no hay aviso de pendiente', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      await montar159(
        tester,
        Estado159.formulario,
        venta: ventaDeUnaRevista(cantidad: 1),
        entorno: e,
      );
      expect(filas159, findsOneWidget);
      expect(_textoDelBoton(tester), 'Entregar');
      expect(find.textContaining('queda para otro día'), findsNothing);
      await tocarCta159(tester);
      expect(e.entregas.recibidas.single.filas.single.cantidad, 1);
    });

    testWidgets('con un solo producto, destildarlo apaga «Entregar» y dice por qué', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      await montar159(
        tester,
        Estado159.formulario,
        venta: ventaDeUnaRevista(cantidad: 1),
        entorno: e,
      );
      await tocarFila159(tester, 0);
      expect(tester.widget<FilledButton>(cta159).onPressed, isNull);
      expect(find.text('Elegí al menos un producto para entregar.'), findsOneWidget);
      await tester.tap(cta159, warnIfMissed: false);
      await asentar(tester);
      expect(e.entregas.recibidas, isEmpty);
    });
  });

  group('Cada estado en los tamaños del QA', () {
    for (final estado in Estado159.values) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          testWidgets(
            '${estado.rotulo} · ${tamano.width.toInt()}×${tamano.height.toInt()} · texto ${escala}x',
            (tester) async {
              final m = await montar159(tester, estado, tamano: tamano, escala: escala);
              expect(tester.takeException(), isNull, reason: 'overflow o error al pintar');
              if (estado == Estado159.parcial) {
                // El aviso va al final de la lista: se baja hasta él.
                await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
                await asentar(tester);
              }
              for (final t in _contenido[estado]!) {
                expect(find.textContaining(t as String), findsWidgets, reason: 'falta «$t»');
              }
              if (estado == Estado159.cargando) {
                expect(find.bySemanticsLabel('Cargando lo que vendiste'), findsOneWidget);
              }
              if (estado == Estado159.guardando) {
                expect(find.byType(CircularProgressIndicator), findsOneWidget);
              }
              sinTextoCortado159(tester);
              await capturar159(tester, nombreDeCaptura159(estado, tamano, escala));
              await soltar159(tester, m);
            },
          );
        }
      }
    }
  });

  group('Avisos de error: a la vista y con la acción a mano', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        testWidgets(
          'error al guardar con la lista larga y el scroll abajo: el aviso y «Reintentar» se ven '
          '· ${tamano.width.toInt()}×${tamano.height.toInt()} · ${escala}x',
          (tester) async {
            final e = EntornoDeEntrega();
            e.entregas.fallas.add(const FailureEntregaNoGuardada());
            const n = 40;
            final venta = VentaGuardada(
              venta: ventaDe('v-1', talonario: '0042', monto: 890000),
              items: [
                for (var i = 0; i < n; i++)
                  itemDe('i-$i', 'v-1', productoId: 'p-$i', cantidad: 1, precio: 1000),
              ],
            );
            e.fuente.productos = ProductosDeLaEntrega(
              nombres: {for (var i = 0; i < n; i++) 'p-$i': 'Libro número $i'},
            );
            await montar159(
              tester,
              Estado159.formulario,
              tamano: tamano,
              escala: escala,
              venta: venta,
              entorno: e,
            );
            await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
            await asentar(tester);
            await tocarCta159(tester);

            final aviso = find.textContaining('No pudimos guardar la entrega');
            expect(aviso, findsOneWidget);
            expect(enPantalla159(tester, aviso), isTrue, reason: 'el aviso quedó fuera de vista');
            expect(enPantalla159(tester, cta159), isTrue);
            expect(_textoDelBoton(tester), 'Reintentar');
            await capturar159(tester, 'error_lista_larga_${tamano.width.toInt()}_${escala}x');
          },
        );
      }
    }

    testWidgets('los avisos de error se anuncian al lector (región viva)', (tester) async {
      final handle = tester.ensureSemantics();
      final m = await montar159(tester, Estado159.errorAlGuardar);
      final aviso = find.ancestor(
        of: find.textContaining('No pudimos guardar la entrega'),
        matching: find.byType(Semantics),
      );
      final vivos = [
        for (final s in aviso.evaluate())
          if ((s.widget as Semantics).properties.liveRegion == true) s,
      ];
      expect(vivos, isNotEmpty);
      await soltar159(tester, m);
      handle.dispose();
    });

    testWidgets(
      'cambiar la selección después de un error saca el aviso y el botón vuelve a «Entregar N»',
      (tester) async {
        final m = await montar159(tester, Estado159.errorAlGuardar);
        expect(_textoDelBoton(tester), 'Reintentar');
        await tocarTexto159(tester, 'Nuestros Hijos × 1');
        expect(find.textContaining('No pudimos guardar'), findsNothing);
        expect(_textoDelBoton(tester), 'Entregar 3 productos');
        expect(tester.widget<FilledButton>(cta159).onPressed, isNotNull);
        await soltar159(tester, m);
      },
    );

    testWidgets('dos fallas seguidas y después éxito: nada queda trabado ni se duplica', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      e.entregas.fallas.addAll([
        const FailureEntregaNoGuardada(),
        const FailureEntregaNoGuardada(),
      ]);
      await montar159(tester, Estado159.formulario, entorno: e);
      await tocarTexto159(tester, 'Nuestros Hijos × 1');
      await tocarCta159(tester);
      await tocarCta159(tester);
      expect(find.textContaining('No pudimos guardar'), findsOneWidget);
      expect(tester.widget<FilledButton>(cta159).onPressed, isNotNull);
      await tocarCta159(tester);
      expect(e.entregas.recibidas, hasLength(3));
      expect(find.text('Entrega registrada'), findsOneWidget);
      expect(e.entregas.guardadas['v-1'], hasLength(e.entregas.recibidas.last.filas.length));
    });

    testWidgets('error al leer y «Reintentar»: la segunda lectura trae el formulario', (
      tester,
    ) async {
      final m = await montar159(tester, Estado159.errorDeLectura);
      await tester.tap(find.byKey(const Key('venta_aviso_accion')));
      await asentar(tester);
      expect(find.text('QUÉ ENTREGÁS'), findsOneWidget);
      expect(filas159, findsWidgets);
      expect(m.entorno.fuente.lecturas, 2);
    });

    testWidgets('error al leer: la flecha de volver cierra y devuelve null', (tester) async {
      final m = await montar159(tester, Estado159.errorDeLectura);
      await tester.tap(find.byKey(const Key('venta_atras')));
      await asentar(tester);
      expect(m.salida.cerrada, isTrue);
      expect(m.salida.registrada, isNull);
    });
  });

  group('Casos límite de la salida', () {
    testWidgets('«Volver al mapa» dos veces seguidas cierra una sola vez y devuelve lo entregado', (
      tester,
    ) async {
      final m = await montar159(tester, Estado159.conSaldo);
      final volver = find.text('Volver al mapa');
      await tester.tap(volver);
      await tester.tap(volver, warnIfMissed: false);
      await asentar(tester);
      expect(tester.takeException(), isNull);
      expect(m.salida.cerrada, isTrue);
      expect(m.salida.registrada, isNotNull);
      expect(m.salida.registrada!.entregas, isNotEmpty);
    });

    testWidgets('el gesto de volver del sistema en el resultado devuelve lo entregado', (
      tester,
    ) async {
      final m = await montar159(tester, Estado159.conSaldo);
      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(m.salida.cerrada, isTrue);
      expect(m.salida.registrada, isNotNull);
    });

    testWidgets('reentrar tras una entrega parcial muestra lo pendiente y no vuelve a escribir', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      final m = await montar159(tester, Estado159.formulario, entorno: e);
      await tocarTexto159(tester, 'Nuestros Hijos × 1');
      await tocarCta159(tester);
      await tester.tap(find.text('Volver al mapa'));
      await asentar(tester);
      expect(m.salida.cerrada, isTrue);
      await tester.tap(find.byKey(const Key('abrir_entrega')));
      await asentar(tester);
      expect(find.text('Entrega registrada'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.textContaining('Nuestros Hijos × 1'), findsWidgets);
      expect(e.entregas.recibidas, hasLength(1));
    });

    testWidgets('si se sale mientras guarda, la entrega se escribe y al reentrar se ve entera', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      e.entregas.compuerta = Completer<void>();
      await montar159(tester, Estado159.formulario, entorno: e);
      await tocarCta159(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      e.entregas.compuerta!.complete();
      await asentar(tester);
      expect(tester.takeException(), isNull);
      expect(e.entregas.guardadas['v-1'], isNotNull);
      e.entregas.compuerta = null;
      if (find.byKey(const Key('abrir_entrega')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('abrir_entrega')));
        await asentar(tester);
      }
      expect(find.text('Entrega registrada'), findsOneWidget);
      expect(e.entregas.recibidas, hasLength(1));
    });
  });

  group('Datos límite', () {
    testWidgets('100 productos a 360×640 con texto 2,0: se recorre, «Entregar» queda a mano', (
      tester,
    ) async {
      const n = 100;
      final e = EntornoDeEntrega();
      e.fuente.productos = ProductosDeLaEntrega(
        nombres: {for (var i = 0; i < n; i++) 'p-$i': 'Libro $i'},
      );
      final venta = VentaGuardada(
        venta: ventaDe('v-1', talonario: '0042', monto: 890000),
        items: [
          for (var i = 0; i < n; i++)
            itemDe('i-$i', 'v-1', productoId: 'p-$i', cantidad: 1, precio: 10),
        ],
      );
      await montar159(tester, Estado159.formulario, escala: 2, venta: venta, entorno: e);
      expect(tester.takeException(), isNull);
      expect(enPantalla159(tester, cta159), isTrue);
      await tocarCta159(tester);
      expect(e.entregas.recibidas.single.filas, hasLength(n));
    });

    testWidgets(
      'nombres de 300 caracteres con emoji y comillas, texto 2,0 en 360×640: sin overflow',
      (tester) async {
        final largo = '📚 «Libro» ${'muy largo ' * 30}ñandú 🙏';
        final e = EntornoDeEntrega();
        e.fuente.productos = ProductosDeLaEntrega(nombres: {'p-1': largo, 'p-2': largo});
        final venta = VentaGuardada(
          venta: ventaDe('v-1', talonario: '0042', monto: 890000),
          items: [
            itemDe('i-1', 'v-1', productoId: 'p-1', cantidad: 1),
            itemDe('i-2', 'v-1', productoId: 'p-2', cantidad: 1),
          ],
        );
        await montar159(tester, Estado159.formulario, escala: 2, venta: venta, entorno: e);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await asentar(tester);
        await tester.tap(filas159.last);
        await asentar(tester);
        expect(tester.takeException(), isNull);
        await capturar159(tester, 'nombre_largo_parcial');
        await tocarCta159(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Pendiente'), findsOneWidget);
        await capturar159(tester, 'nombre_largo_resultado');
      },
    );

    testWidgets('cantidades grandes (999) se ven completas en la fila', (tester) async {
      final venta = ventaDeUnaRevista(cantidad: 999);
      await montar159(tester, Estado159.formulario, venta: venta);
      expect(find.textContaining('999'), findsWidgets);
    });
  });

  group('Privacidad', () {
    test('ni el estado ni los argumentos ni los avisos llevan datos de la persona', () {
      final args = ArgumentosDeEntrega(guardada: ventaConColeccion(), lineas: const []);
      const estado = EntregarAhoraState(marcadas: {'a'}, falla: FailureEntregaNoGuardada());
      for (final s in [
        args.toString(),
        estado.toString(),
        const FailureEntregaNoGuardada().toString(),
      ]) {
        expect(s.contains('María'), isFalse);
        expect(s.contains('Fernández'), isFalse);
        expect(s.contains('0042'), isFalse);
      }
    });
  });

  group('Hallazgos (skip: corren con QA_HALLAZGOS=true)', () {
    testWidgets('QA #159: sin nada tildado el botón apagado dice «Entregar 0 productos»', (
      tester,
    ) async {
      await montar159(tester, Estado159.sinNada);
      expect(_textoDelBoton(tester), isNot(contains('0 productos')));
    }, skip: !_hallazgos);

    testWidgets(
      'QA #159: el botón dice «Entregar 3 productos» y el resultado «5 de 6 productos»: unidades distintas',
      (tester) async {
        await montar159(tester, Estado159.formulario);
        await tocarTexto159(tester, 'Nuestros Hijos × 1');
        final boton = RegExp(r'(\d+)').firstMatch(_textoDelBoton(tester))!.group(1)!;
        await tocarCta159(tester);
        final resultado = find.textContaining(RegExp(r'^\d+ de \d+ productos$'));
        expect(resultado, findsOneWidget);
        final entregados = RegExp(
          r'^(\d+)',
        ).firstMatch((tester.widget<Text>(resultado).data)!)!.group(1)!;
        expect(
          entregados,
          boton,
          reason: 'el botón cuenta filas y el resultado cuenta componentes',
        );
      },
      skip: !_hallazgos,
    );

    testWidgets(
      'QA #159: con la entrega en curso, el «atrás» del sistema cierra la pantalla (la flecha ya está oculta)',
      (tester) async {
        final m = await montar159(tester, Estado159.guardando);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(m.salida.cerrada, isFalse, reason: 'se salió con el guardado en curso');
        await soltar159(tester, m);
      },
      skip: !_hallazgos,
    );

    testWidgets('QA #159: «Cobrar ahora» tocado dos veces llama dos veces al destino', (
      tester,
    ) async {
      final m = await montar159(tester, Estado159.conSaldoConDestinos);
      final cobrar = find.byKey(const Key('entrega_cobrar'));
      await tester.tap(cobrar);
      await tester.tap(cobrar);
      await tester.pump();
      expect(m.salida.cobrar, hasLength(1));
    }, skip: !_hallazgos);

    testWidgets('QA #159: al pasar a «Entrega registrada» (27B·04) nada se anuncia al lector', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await montar159(tester, Estado159.conSaldo);
      final vivas = <SemanticsNode>[];
      void recorrer(SemanticsNode n) {
        if (n.getSemanticsData().flagsCollection.isLiveRegion) vivas.add(n);
        n.visitChildren((h) {
          recorrer(h);
          return true;
        });
      }

      recorrer(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
      expect(vivas, isNotEmpty);
      handle.dispose();
    }, skip: !_hallazgos);
  });
}
