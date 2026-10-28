// HU-VEN-002 (vista 27, grupo B, «Entregar ahora»): un test por artboard (27B·01, 27B·03 y 27B·04; el
// 27B·02 «No tenés suficiente en mano» no se implementa en V1, decisión del 23/10: el stock es V2), por
// los estados que el canvas no dibuja (cargando, error de lectura, vacío, error al guardar, sin
// conexión) y por cada caso límite: doble toque, falla a mitad del guardado, acciones seguidas, volver
// y reentrar, datos límite y texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/productos_de_la_entrega.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_falsos.dart';
import '../../helpers/venta_falsos.dart';
import '../../helpers/venta_ui_falsos.dart' show asentar, tocar;

Finder get _cta => find.byKey(const Key('venta_cta'));

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(_cta).onPressed != null;

String _textoDelBoton(WidgetTester tester) {
  final texto = find.descendant(of: _cta, matching: find.byType(Text));
  return tester.widget<Text>(texto).data!;
}

/// Una venta de [n] productos sueltos, cada uno con su nombre, para las listas largas.
({VentaGuardada guardada, ProductosDeLaEntrega productos}) _ventaLarga(int n, {String? nombre}) {
  return (
    guardada: VentaGuardada(
      venta: ventaDe('v-1', talonario: '0042', monto: 890000),
      items: [
        for (var i = 0; i < n; i++)
          itemDe('i-$i', 'v-1', productoId: 'p-$i', cantidad: 1, precio: 1000),
      ],
    ),
    productos: ProductosDeLaEntrega(
      nombres: {for (var i = 0; i < n; i++) 'p-$i': nombre ?? 'Libro número $i'},
    ),
  );
}

void main() {
  group('27B·01 Entregar ahora', () {
    testWidgets('dice la venta, el cliente y qué se entrega, con todo tildado', (tester) async {
      await montarEntrega(tester, EntornoDeEntrega(), ventaConColeccion());

      expect(find.text('VENTA 0042'), findsOneWidget);
      expect(find.text('Entregar ahora'), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.text('QUÉ ENTREGÁS'), findsOneWidget);
      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
      // La base de la colección va junta, en una sola fila.
      expect(
        find.text('El camino a Cristo, Vida Feliz y El Deseado de todas las gentes'),
        findsOneWidget,
      );
      expect(find.text('Base de la colección'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNWidgets(3));
      expect(_textoDelBoton(tester), 'Entregar');
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('en V1 no muestra el stock: ni «Tenés N en mano» ni «No tenés suficiente»', (
      tester,
    ) async {
      await montarEntrega(tester, EntornoDeEntrega(), ventaConColeccion());

      expect(find.textContaining('en mano'), findsNothing);
      expect(find.textContaining('Tenés'), findsNothing);
      expect(find.textContaining('suficiente'), findsNothing);
    });

    testWidgets('«Entregar» guarda una fila por producto, con todas las cantidades', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      await montarEntrega(tester, e, ventaConColeccion(conRevista: true));

      await tocar(tester, find.byKey(const Key('venta_cta')));

      final recibida = e.entregas.recibidas.single;
      expect(recibida.ventaId, 'v-1');
      expect(
        {for (final f in recibida.filas) f.productoId: (f.cantidad, f.pendiente, f.fechaEntrega)},
        {
          'p-camino': (1, false, e.ahora),
          'p-vida-feliz': (1, false, e.ahora),
          'p-deseado': (1, false, e.ahora),
          'p-salud': (1, false, e.ahora),
          'p-hijos': (1, false, e.ahora),
          'p-nuestra-salud': (2, false, e.ahora),
        },
      );
      expect(recibida.filas.every((f) => f.auditoria.createdBy == 'col-1'), isTrue);
    });

    testWidgets('destildar un libro lo deja para otro día y lo avisa', (tester) async {
      final e = EntornoDeEntrega();
      await montarEntrega(tester, e, ventaConColeccion());

      await tocar(tester, find.text('Nuestros Hijos × 1'));

      expect(find.text('Nuestros Hijos queda para otro día.'), findsOneWidget);
      expect(_textoDelBoton(tester), 'Entregar 2 productos');

      await tocar(tester, find.byKey(const Key('venta_cta')));

      final filas = {for (final f in e.entregas.recibidas.single.filas) f.productoId: f};
      expect(filas['p-hijos']!.pendiente, isTrue);
      expect(filas['p-hijos']!.fechaEntrega, isNull);
      expect(filas['p-salud']!.pendiente, isFalse);
      expect(filas['p-camino']!.pendiente, isFalse);
    });

    testWidgets('con dos filas destildadas el aviso las nombra a las dos', (tester) async {
      await montarEntrega(tester, EntornoDeEntrega(), ventaConColeccion());

      await tocar(tester, find.text('Nuestros Hijos × 1'));
      await tocar(tester, find.text('Salud y Hogar × 1'));

      expect(find.text('Nuestros Hijos y Salud y Hogar quedan para otro día.'), findsNothing);
      expect(find.text('Salud y Hogar y Nuestros Hijos quedan para otro día.'), findsOneWidget);
      expect(_textoDelBoton(tester), 'Entregar 1 producto');
    });

    testWidgets('volver a tildar lo deja como estaba', (tester) async {
      await montarEntrega(tester, EntornoDeEntrega(), ventaConColeccion());

      await tocar(tester, find.text('Nuestros Hijos × 1'));
      await tocar(tester, find.text('Nuestros Hijos × 1'));

      expect(find.textContaining('queda para otro día'), findsNothing);
      expect(_textoDelBoton(tester), 'Entregar');
    });

    testWidgets('sin nada tildado no se puede entregar y dice por qué', (tester) async {
      final e = EntornoDeEntrega();
      await montarEntrega(tester, e, ventaConColeccion());

      await tocar(tester, find.text('Nuestros Hijos × 1'));
      await tocar(tester, find.text('Salud y Hogar × 1'));
      await tocar(tester, find.text('Base de la colección'));

      expect(_habilitado(tester), isFalse);
      expect(find.text('Elegí al menos un producto para entregar.'), findsOneWidget);
      expect(e.entregas.recibidas, isEmpty);
    });

    testWidgets('un producto que el catálogo no conoce se muestra sin nombre, no desaparece', (
      tester,
    ) async {
      final e = EntornoDeEntrega(fuente: FuenteDeProductosFalsa(const ProductosDeLaEntrega()));
      await montarEntrega(tester, e, ventaDeUnaRevista(cantidad: 2));

      expect(find.text('Producto sin nombre × 2'), findsOneWidget);
    });

    testWidgets('las filas se anuncian como casillas tildadas o no', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarEntrega(tester, EntornoDeEntrega(), ventaConColeccion());

      expect(
        tester.getSemantics(find.text('Nuestros Hijos × 1')),
        isSemantics(label: 'Nuestros Hijos × 1', isChecked: true, hasTapAction: true),
      );
      await tocar(tester, find.text('Nuestros Hijos × 1'));
      expect(
        tester.getSemantics(find.text('Nuestros Hijos × 1')),
        isSemantics(label: 'Nuestros Hijos × 1', isChecked: false, hasTapAction: true),
      );
      semantica.dispose();
    });

    testWidgets('cumple las guías de toque y de contraste a 390 × 844', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarEntrega(tester, EntornoDeEntrega(), ventaConColeccion());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  });

  group('27B·03 Entregada y pagada: venta completa', () {
    testWidgets('sin nada que cobrar, entregar todo deja «Venta completa»', (tester) async {
      final e = EntornoDeEntrega();
      final salida = await montarEntrega(tester, e, ventaDeUnaRevista());

      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(find.text('VENTA 0042'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      expect(find.text('Venta completa'), findsOneWidget);
      expect(
        find.text(
          'Entregaste todo y no había nada para cobrar. La casa quedó como «Venta completa» en el '
          'mapa.',
        ),
        findsOneWidget,
      );
      expect(find.text('Volver al mapa'), findsOneWidget);
      expect(find.text('Saldo'), findsNothing);

      await tocar(tester, find.text('Volver al mapa'));

      expect(salida.cerrada, isTrue);
      expect(salida.registrada!.entregas.single.productoId, 'p-nuestra-salud');
    });

    testWidgets('con las filas pendientes no es «Venta completa» aunque no haya saldo', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      e.entregas.colorDeLaCasa = null;
      await montarEntrega(tester, e, ventaConColeccion(monto: 0));

      await tocar(tester, find.text('Nuestros Hijos × 1'));
      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(find.text('Venta completa'), findsNothing);
      expect(find.text('Entrega registrada'), findsOneWidget);
      expect(find.text('4 de 5 productos'), findsOneWidget);
      expect(
        find.text(
          'Lo que falta queda pendiente para otro día. La casa se actualiza cuando lo entregues.',
        ),
        findsOneWidget,
      );
    });
  });

  group('27B·04 Entregada con saldo', () {
    testWidgets('dice que se entregó todo, el saldo y cómo queda la casa', (tester) async {
      final e = EntornoDeEntrega();
      await montarEntrega(tester, e, ventaConColeccion());

      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(find.text('Entrega registrada'), findsOneWidget);
      expect(find.text('Entregado'), findsOneWidget);
      expect(find.text('todo'), findsOneWidget);
      expect(find.text('Saldo'), findsOneWidget);
      expect(find.text(r'$ 8.900'), findsOneWidget);
      expect(
        find.text('La casa queda como «Cobranza pendiente» hasta que el saldo llegue a cero.'),
        findsOneWidget,
      );
      expect(find.text('Volver al mapa'), findsOneWidget);
    });

    testWidgets('«Cobrar ahora» y «Agendar la cobranza» no se dibujan si no tienen destino', (
      tester,
    ) async {
      await montarEntrega(tester, EntornoDeEntrega(), ventaConColeccion());

      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(find.text('Cobrar ahora'), findsNothing);
      expect(find.text('Agendar la cobranza'), findsNothing);
    });

    testWidgets('con destino, «Cobrar ahora» y «Agendar la cobranza» llevan lo entregado', (
      tester,
    ) async {
      final salida = await montarEntrega(
        tester,
        EntornoDeEntrega(),
        ventaConColeccion(),
        conCobro: true,
        conAgendar: true,
      );

      await tocar(tester, find.byKey(const Key('venta_cta')));
      expect(find.text('Cobrar ahora'), findsOneWidget);
      expect(find.text('Agendar la cobranza'), findsOneWidget);

      await tocar(tester, find.text('Cobrar ahora'));
      await tocar(tester, find.text('Agendar la cobranza'));

      expect(salida.cobrar, hasLength(1));
      expect(salida.agendar, hasLength(1));
      expect(salida.cobrar.single.entregas, hasLength(5));
      expect(salida.cerrada, isFalse);

      await tocar(tester, find.text('Volver al mapa'));
      expect(salida.cerrada, isTrue);
    });

    testWidgets('entrega parcial: dice qué falta y que la casa sigue con entrega pendiente', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      await montarEntrega(tester, e, ventaConColeccion());

      await tocar(tester, find.text('Nuestros Hijos × 1'));
      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(find.text('Entrega registrada'), findsOneWidget);
      expect(find.text('4 de 5 productos'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
      expect(find.text(r'$ 8.900'), findsOneWidget);
      expect(
        find.text(
          'La casa sigue como «Entrega y cobranza pendientes» hasta que entregues lo que falta y '
          'el saldo llegue a cero.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('el gesto de volver no deja a medias: equivale a «Volver al mapa»', (tester) async {
      final salida = await montarEntrega(tester, EntornoDeEntrega(), ventaConColeccion());
      await tocar(tester, find.byKey(const Key('venta_cta')));

      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(salida.cerrada, isTrue);
      expect(salida.registrada, isNotNull);
    });
  });

  group('estados que el canvas no dibuja', () {
    testWidgets('cargando: un esqueleto que el lector nombra, sin filas ni botón', (tester) async {
      final e = EntornoDeEntrega();
      e.fuente.bloqueo = Completer<void>();
      await montarEntrega(tester, e, ventaConColeccion());

      expect(find.byKey(const Key('entrega_cargando')), findsOneWidget);
      expect(find.bySemanticsLabel('Cargando lo que vendiste'), findsOneWidget);
      expect(_cta, findsNothing);

      e.fuente.bloqueo!.complete();
      await asentar(tester);

      expect(find.byKey(const Key('entrega_cargando')), findsNothing);
      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
    });

    testWidgets('error de lectura del catálogo: lo dice, deja reintentar y no inventa productos', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      e.fuente.fallas = 1;
      await montarEntrega(tester, e, ventaConColeccion());

      expect(
        find.text('No pudimos leer lo que vendiste en tu teléfono. Probá de nuevo.'),
        findsOne,
      );
      expect(find.text('Salud y Hogar × 1'), findsNothing);
      expect(_cta, findsNothing);

      await tocar(tester, find.text('Reintentar'));

      expect(find.textContaining('No pudimos leer'), findsNothing);
      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
    });

    testWidgets('error de lectura de las entregas: igual, con «Reintentar»', (tester) async {
      final e = EntornoDeEntrega();
      e.entregas.fallasDeLectura = 1;
      await montarEntrega(tester, e, ventaConColeccion());

      expect(find.textContaining('No pudimos leer lo que vendiste'), findsOneWidget);

      await tocar(tester, find.text('Reintentar'));

      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
    });

    testWidgets('el error de lectura se puede cerrar con la flecha de volver', (tester) async {
      final e = EntornoDeEntrega();
      e.fuente.fallas = 1;
      final salida = await montarEntrega(tester, e, ventaConColeccion());

      await tocar(tester, find.byKey(const Key('venta_atras')));

      expect(salida.cerrada, isTrue);
      expect(salida.registrada, isNull);
    });

    testWidgets('una venta sin productos no ofrece entregar nada y lo dice', (tester) async {
      final guardada = VentaGuardada(
        venta: ventaDe('v-1', talonario: '0042'),
        items: const [],
      );
      await montarEntrega(tester, EntornoDeEntrega(), guardada);

      expect(find.text('Esta venta no tiene productos para entregar.'), findsOneWidget);
      expect(_cta, findsNothing);
    });

    testWidgets('sin conexión funciona igual: nada de lo que hace sale a la red', (tester) async {
      // Entregar escribe en el teléfono y encola; no hay pantalla de «sin conexión» porque no la usa.
      final e = EntornoDeEntrega();
      await montarEntrega(tester, e, ventaConColeccion());

      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(find.text('Entrega registrada'), findsOneWidget);
      expect(find.textContaining('conexión'), findsNothing);
      expect(find.textContaining('internet'), findsNothing);
    });
  });

  group('casos límite', () {
    testWidgets('doble toque en «Entregar»: se entrega una sola vez', (tester) async {
      final e = EntornoDeEntrega();
      e.entregas.compuerta = Completer<void>();
      await montarEntrega(tester, e, ventaConColeccion());

      await tester.tap(_cta);
      await tester.pump();
      await tester.tap(_cta, warnIfMissed: false);
      await tester.pump();

      expect(e.entregas.recibidas, hasLength(1));

      e.entregas.compuerta!.complete();
      await asentar(tester);

      expect(e.entregas.recibidas, hasLength(1));
      expect(find.text('Entrega registrada'), findsOneWidget);
    });

    testWidgets('mientras se guarda el botón no responde y dice que está ocupado', (tester) async {
      final e = EntornoDeEntrega();
      e.entregas.compuerta = Completer<void>();
      await montarEntrega(tester, e, ventaConColeccion());

      await tester.tap(_cta);
      await tester.pump();

      expect(_habilitado(tester), isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // No se puede salir a la mitad: la entrega se escribiría igual.
      expect(find.byKey(const Key('venta_atras')), findsNothing);

      e.entregas.compuerta!.complete();
      await asentar(tester);
    });

    testWidgets('falla al guardar: el aviso, nada destildado se pierde y el botón vuelve', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      e.entregas.fallas.add(const FailureEntregaNoGuardada());
      await montarEntrega(tester, e, ventaConColeccion());
      await tocar(tester, find.text('Nuestros Hijos × 1'));

      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(
        find.text(
          'No pudimos guardar la entrega en tu teléfono. No se perdió nada de lo que marcaste: '
          'probá de nuevo.',
        ),
        findsOneWidget,
      );
      expect(_textoDelBoton(tester), 'Reintentar');
      expect(_habilitado(tester), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Lo que había destildado sigue destildado.
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      expect(find.text('Nuestros Hijos queda para otro día.'), findsOneWidget);

      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(e.entregas.recibidas, hasLength(2));
      expect(find.text('Entrega registrada'), findsOneWidget);
      expect(find.text('4 de 5 productos'), findsOneWidget);
    });

    testWidgets('una excepción inesperada del repositorio también deja reintentar', (tester) async {
      final e = EntornoDeEntrega();
      await montarEntrega(tester, e, ventaConColeccion());
      e.entregas.compuerta = Completer<void>();
      final fallar = e.entregas.compuerta!;

      await tester.tap(_cta);
      await tester.pump();
      e.entregas.fallas.add(const FailureEntregaNoGuardada(causa: 'StateError'));
      fallar.complete();
      await asentar(tester);

      expect(find.textContaining('No pudimos guardar la entrega'), findsOneWidget);
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('tocar una fila o «Entregar» mientras se guarda no cambia nada', (tester) async {
      final e = EntornoDeEntrega();
      e.entregas.compuerta = Completer<void>();
      await montarEntrega(tester, e, ventaConColeccion());

      await tester.tap(_cta);
      await tester.pump();
      await tester.tap(find.text('Nuestros Hijos × 1'), warnIfMissed: false);
      await tester.pump();

      e.entregas.compuerta!.complete();
      await asentar(tester);

      // Se entregó lo que estaba tildado cuando se tocó «Entregar»: nada quedó pendiente.
      expect(e.entregas.recibidas.single.filas.every((f) => !f.pendiente), isTrue);
      expect(find.text('todo'), findsOneWidget);
    });

    testWidgets('destildar y tildar seguido termina con lo último que se tocó', (tester) async {
      final e = EntornoDeEntrega();
      await montarEntrega(tester, e, ventaConColeccion());

      await tester.tap(find.text('Nuestros Hijos × 1'));
      await tester.tap(find.text('Salud y Hogar × 1'));
      await tester.tap(find.text('Nuestros Hijos × 1'));
      await tester.pump();

      await tocar(tester, find.byKey(const Key('venta_cta')));

      final filas = {for (final f in e.entregas.recibidas.single.filas) f.productoId: f.pendiente};
      expect(filas['p-hijos'], isFalse);
      expect(filas['p-salud'], isTrue);
    });

    testWidgets('volver sin entregar y reabrir: vuelve a empezar con todo tildado', (tester) async {
      final e = EntornoDeEntrega();
      final salida = await montarEntrega(tester, e, ventaConColeccion());
      await tocar(tester, find.text('Nuestros Hijos × 1'));

      await tocar(tester, find.byKey(const Key('venta_atras')));
      expect(salida.cerrada, isTrue);
      expect(salida.registrada, isNull);
      expect(e.entregas.recibidas, isEmpty);

      await tocar(tester, find.byKey(const Key('abrir_entrega')));

      expect(find.byIcon(Icons.check), findsNWidgets(3));
      expect(find.textContaining('queda para otro día'), findsNothing);
    });

    testWidgets(
      'volver después de entregar y reabrir: muestra lo que quedó, sin entregar de nuevo',
      (tester) async {
        final e = EntornoDeEntrega();
        final salida = await montarEntrega(tester, e, ventaConColeccion());
        await tocar(tester, find.text('Nuestros Hijos × 1'));
        await tocar(tester, find.byKey(const Key('venta_cta')));
        await tocar(tester, find.text('Volver al mapa'));
        expect(salida.cerrada, isTrue);

        await tocar(tester, find.byKey(const Key('abrir_entrega')));

        expect(find.text('Entrega registrada'), findsOneWidget);
        expect(find.text('4 de 5 productos'), findsOneWidget);
        expect(find.text('Pendiente'), findsOneWidget);
        expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
        expect(find.text('Entregar'), findsNothing);
        expect(find.text('Volver al mapa'), findsOneWidget);
        expect(e.entregas.recibidas, hasLength(1));
      },
    );

    testWidgets('una lista larga se recorre y se entrega entera', (tester) async {
      final venta = _ventaLarga(40);
      final e = EntornoDeEntrega(fuente: FuenteDeProductosFalsa(venta.productos));
      await montarEntrega(tester, e, venta.guardada);

      await tester.dragUntilVisible(
        find.text('Libro número 39 × 1'),
        find.byType(ListView).first,
        const Offset(0, -300),
      );
      await tocar(tester, find.text('Libro número 39 × 1'));

      expect(find.text('Libro número 39 queda para otro día.'), findsOneWidget);
      expect(_textoDelBoton(tester), 'Entregar 39 productos');
      // El botón de abajo sigue a la vista aunque la lista sea larga.
      expect(_cta, findsOneWidget);

      await tocar(tester, find.byKey(const Key('venta_cta')));

      final filas = e.entregas.recibidas.single.filas;
      expect(filas, hasLength(40));
      expect(filas.where((f) => f.pendiente), hasLength(1));
    });

    testWidgets('un nombre larguísimo se parte en renglones y nada desborda', (tester) async {
      final venta = _ventaLarga(1, nombre: 'Un libro con un título larguísimo ' * 6);
      final e = EntornoDeEntrega(fuente: FuenteDeProductosFalsa(venta.productos));
      await montarEntrega(tester, e, venta.guardada, tamano: const Size(320, 568));

      expect(tester.takeException(), isNull);
      await tocar(tester, find.byKey(const Key('venta_cta')));
      expect(tester.takeException(), isNull);
      expect(find.text('Entrega registrada'), findsOneWidget);
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'texto al ${(escala * 100).round()} % a 320 × 568: nada desborda y se alcanza todo',
        (tester) async {
          final e = EntornoDeEntrega();
          await montarEntrega(
            tester,
            e,
            ventaConColeccion(conRevista: true),
            escala: escala,
            tamano: const Size(320, 568),
          );

          expect(tester.takeException(), isNull);
          expect(tester.getSize(_cta).height, greaterThanOrEqualTo(48));
          await tocar(tester, find.text('Nuestros Hijos × 1'));
          expect(tester.takeException(), isNull);
          await tocar(tester, find.byKey(const Key('venta_cta')));
          expect(tester.takeException(), isNull);
          expect(find.text('Entrega registrada'), findsOneWidget);
          expect(
            tester.getSize(find.byKey(const Key('venta_cta'))).height,
            greaterThanOrEqualTo(48),
          );
        },
      );
    }

    testWidgets('el resultado con saldo y todo lo que ofrece entra en 320 × 568 al 200 %', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      await montarEntrega(
        tester,
        e,
        ventaConColeccion(),
        escala: 2,
        tamano: const Size(320, 568),
        conCobro: true,
        conAgendar: true,
      );
      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(tester.takeException(), isNull);
      for (final clave in ['entrega_cobrar', 'entrega_agendar_cobranza', 'entrega_volver']) {
        expect(tester.getSize(find.byKey(Key(clave))).height, greaterThanOrEqualTo(48));
      }
    });
  });
}
