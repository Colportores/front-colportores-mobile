// QA de la vista 37 (HU-STK-009, #387): los escenarios de la HU con sus cifras, la navegación entre las
// pantallas, el aviso que queda a la vista, los avisos que se anuncian, el «cargando» con contexto y la
// privacidad. Los tests que documentan un hallazgo van con `skip` (se corren con `QA_HALLAZGOS=true`).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/armado_del_pedido.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/pedido.dart';
import 'package:colportores_mobile/features/pedidos/domain/usecases/enviar_pedido_use_case.dart';
import 'package:colportores_mobile/features/pedidos/presentation/pages/mis_pedidos_page.dart';
import 'package:colportores_mobile/features/pedidos/presentation/pages/pedir_pedido_page.dart';
import 'package:colportores_mobile/features/pedidos/presentation/textos_pedidos.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pedidos_arnes.dart';
import '../../helpers/pedidos_falsos.dart';
import '../../helpers/qa_vista37_387_arnes.dart';

Finder _t(String texto) => find.text(texto, findRichText: true);

Finder get _enviar => find.byKey(const Key('pedidos_boton_principal'));

Finder get _aviso => find.byKey(const Key('pedidos_aviso_texto'));

/// Una pausa para que corran las transiciones de ruta.
Future<void> _transicion(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _seAnuncia(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).flagsCollection.isLiveRegion;

const _dosMil = ProductoPedible(
  id: 'p-dosmil',
  nombre: 'Libro de dos mil',
  categoriaDelCatalogo: CategoriaDeProducto.bonificables,
  precioDeCompraCentavos: 200000,
  stock: 1,
  esBonificable: true,
);

const _cincoMil = ProductoPedible(
  id: 'p-cincomil',
  nombre: 'Libro de cinco mil',
  categoriaDelCatalogo: CategoriaDeProducto.bonificables,
  precioDeCompraCentavos: 500000,
  stock: 1,
  esBonificable: true,
);

void main() {
  group('Criterios de aceptación de HU-STK-009', () {
    testWidgets(
      'Armar y enviar: debo \$ 12.000 y armo un pedido de \$ 8.000: veo la deuda actual y la deuda '
      'con este pedido, y al enviarlo llega a mi coordinador por autorizar',
      (tester) async {
        final arnes = ArnesDePedidos(deudaPesos: 12000, armado: ArmadoFalso(productos: [_dosMil]));
        await montarPedir(tester, arnes);
        await sumar(tester, 'p-dosmil', 4);

        expect(_t(r'$ 12.000'), findsOneWidget, reason: 'Deuda actual');
        expect(_t(r'+ $ 8.000'), findsOneWidget, reason: 'Este pedido');
        expect(_t(r'$ 20.000'), findsOneWidget, reason: 'Deuda con este pedido');

        await tocar(tester, _enviar, cuadros: 4);
        expect(arnes.pedidos.enviados, hasLength(1));
        final enviado = arnes.pedidos.enviados.single;
        expect(enviado.estado, EstadoDelPedido.porAutorizar);
        expect(enviado.montoCentavos, 800000);
        expect(_t(TextosPedidos.tituloEnviado), findsOneWidget);
      },
    );

    testWidgets(
      'Pedido que supera el límite: límite \$ 20.000, debo \$ 10.000 y pido \$ 15.000: la app '
      'avisa, la deuda con el pedido es \$ 25.000 y me deja enviarlo igual',
      (tester) async {
        final arnes = ArnesDePedidos(
          deudaPesos: 10000,
          limitePesos: 20000,
          armado: ArmadoFalso(productos: [_cincoMil]),
        );
        await montarPedir(tester, arnes);
        await sumar(tester, 'p-cincomil', 3);

        expect(_t(TextosPedidos.superaElLimite(2000000)), findsOneWidget);
        expect(_t(r'$ 25.000'), findsOneWidget);
        expect(tester.widget<FilledButton>(_enviar).onPressed, isNotNull);

        await tocar(tester, _enviar, cuadros: 4);
        expect(arnes.pedidos.enviados, hasLength(1), reason: 'el límite no bloquea');
        expect(arnes.pedidos.enviados.single.excedeLimite, isTrue);
      },
    );

    testWidgets(
      'Pedido sin conexión: armo y envío sin red, queda guardado y la pantalla lo dice con verdad',
      (tester) async {
        final arnes = ArnesDePedidos();
        await montarPedir(tester, arnes, conexion: TipoConexion.sinConexion);
        await sumar(tester, 'p-salud', 2);
        await tocar(tester, _enviar, cuadros: 4);

        expect(arnes.pedidos.enviados, hasLength(1));
        expect(_t(TextosPedidos.heroEnCola), findsOneWidget);
        expect(_t(TextosPedidos.detalleEnCola), findsOneWidget);
        expect(_t(TextosPedidos.heroEnviado), findsNothing);
      },
    );
  });

  group('Navegación entre las pantallas del pedido', () {
    testWidgets(
      'dado que llego a «Nuevo pedido» desde «Mis pedidos» y envío, «Ver mis pedidos» no apila '
      'una segunda lista de pedidos',
      (tester) async {
        final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe()]));
        await montarMisPedidos(tester, arnes);
        await tocar(tester, find.text(TextosPedidos.nuevoPedido), cuadros: 1);
        await _transicion(tester);
        await sumar(tester, 'p-salud', 1);
        await tocar(tester, _enviar, cuadros: 4);
        await tocar(tester, find.text(TextosPedidos.verMisPedidos), cuadros: 1);
        await _transicion(tester);

        expect(find.byType(MisPedidosPage), findsOneWidget);
        // Con una sola lista en la pila, atrás sale de los pedidos (acá no hay pantalla de abajo).
        expect(
          find.byType(MisPedidosPage, skipOffstage: false),
          findsOneWidget,
          reason: 'la lista vieja sigue debajo de la nueva: hacen falta dos «atrás» para salir',
        );
      },
      // skip: QA #387 — «Ver mis pedidos» reemplaza «Nuevo pedido» por otra «Mis pedidos» encima de la que
      // ya estaba: la pila queda con dos listas.
      skip: !verHallazgos37,
    );

    testWidgets('dado un doble toque en «Ver mis pedidos», se abre una sola lista', (tester) async {
      final arnes = ArnesDePedidos();
      await montarPedir(tester, arnes);
      await sumar(tester, 'p-salud', 1);
      await tocar(tester, _enviar, cuadros: 4);
      final boton = find.text(TextosPedidos.verMisPedidos);
      await tester.ensureVisible(boton);
      await tester.pump();
      await tester.tap(boton);
      await tester.tap(boton, warnIfMissed: false);
      await _transicion(tester);
      expect(find.byType(MisPedidosPage, skipOffstage: false), findsOneWidget);
    });

    testWidgets(
      'dado un doble toque en «Armar uno nuevo» del pedido no autorizado, se abre un solo «Nuevo '
      'pedido»',
      (tester) async {
        final arnes = ArnesDePedidos(
          pedidos: PedidosFalsos([
            pedidoDe(estado: EstadoDelPedido.rechazado, motivoRechazo: 'Depositá y pedí de nuevo'),
          ]),
        );
        await montarDetalle(tester, arnes, 'ped-1');
        final boton = find.text(TextosPedidos.armarUnoNuevo);
        await tester.ensureVisible(boton);
        await tester.pump();
        await tester.tap(boton);
        await tester.tap(boton, warnIfMissed: false);
        await _transicion(tester);

        expect(find.byType(PedirPedidoPage, skipOffstage: false), findsOneWidget);
      },
    );

    testWidgets('dado que salgo de «Nuevo pedido» sin armar nada, vuelvo a lo que veía', (
      tester,
    ) async {
      await montarPedir(tester, ArnesDePedidos());
      await tocar(tester, find.byKey(const Key('pedidos_volver')), cuadros: 1);
      await _transicion(tester);
      expect(find.byKey(const Key('abrir_pedir')), findsOneWidget);
      expect(find.byType(PedirPedidoPage), findsNothing);
    });
  });

  group('El aviso queda a la vista de quien tocó el botón de abajo', () {
    testWidgets(
      'dado un pedido de 40 productos y un envío que falla, el aviso del error se ve (la pantalla '
      'sube) y el botón dice «Reintentar»',
      (tester) async {
        final arnes = ArnesDePedidos(
          armado: ArmadoFalso(productos: [for (var i = 1; i <= 40; i++) productoNumero37(i)]),
        );
        arnes.pedidos.fallasAlEnviar.add(const FailurePedidoNoGuardado(causa: 'X'));
        await montarPedir(tester, arnes, tamano: telefonoChico37, escala: 2);
        await sumar(tester, 'p-40', 1);
        await tocar(tester, _enviar, cuadros: 4);
        await tester.pump();

        expect(_aviso, findsOneWidget);
        final r = tester.getRect(_aviso);
        expect(r.top, greaterThanOrEqualTo(0));
        expect(
          r.top,
          lessThan(telefonoChico37.height - 60),
          reason: 'el aviso arranca a la vista (a 2× el texto largo puede seguir más abajo)',
        );
        expect(_t(TextosPedidos.reintentar), findsOneWidget);
      },
    );

    testWidgets(
      'dado un pedido de 40 líneas y una cancelación que falla, el aviso se ve sin tener que '
      'desplazar la pantalla hacia arriba',
      (tester) async {
        final nombres = {for (var i = 1; i <= 40; i++) 'p-$i': 'Libro número $i'};
        final arnes = ArnesDePedidos(
          armado: ArmadoFalso(nombres: nombres),
          pedidos: PedidosFalsos([
            pedidoDe(
              lineas: [
                for (var i = 1; i <= 40; i++)
                  LineaDelPedido(id: 'l-$i', productoId: 'p-$i', cantidad: i),
              ],
            ),
          ]),
        );
        arnes.pedidos.fallasAlCancelar.add(const FailurePedidoNoCancelado(causa: 'X'));
        await montarDetalle(tester, arnes, 'ped-1', tamano: telefonoChico37, escala: 1);
        await tocar(tester, find.byKey(const Key('pedidos_boton_secundario')), cuadros: 3);
        await tocar(tester, find.byKey(const Key('pedido_si_cancelar')), cuadros: 4);
        await tester.pump();

        expect(_aviso, findsOneWidget);
        final r = tester.getRect(_aviso);
        expect(
          r.top >= 0 && r.bottom <= telefonoChico37.height,
          isTrue,
          reason: 'el aviso quedó fuera de la pantalla (arriba: ${r.top})',
        );
      },
      // skip: QA #387 — al fallar «Cancelar pedido» con muchas líneas el aviso queda arriba del todo y quien
      // tocó el botón del final no lo ve (el envío de 37A sí sube la pantalla; el detalle no).
      skip: !verHallazgos37,
    );
  });

  group('Los avisos se anuncian (liveRegion)', () {
    testWidgets('37A·07 el error al enviar, 37A·06 sin conexión y 37A·02 el límite', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      final arnes = ArnesDePedidos(limitePesos: 100);
      arnes.pedidos.fallasAlEnviar.add(const FailurePedidoNoGuardado(causa: 'X'));
      await montarPedir(tester, arnes, conexion: TipoConexion.sinConexion);
      expect(_seAnuncia(tester, _aviso.first), isTrue, reason: 'sin conexión');
      await sumar(tester, 'p-salud', 1);
      expect(_seAnuncia(tester, _aviso.last), isTrue, reason: 'el límite');
      await tocar(tester, _enviar, cuadros: 4);
      expect(_aviso, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        expect(_seAnuncia(tester, _aviso.at(i)), isTrue, reason: 'aviso $i');
      }
      manejador.dispose();
    });

    testWidgets('37B·06 el error de la lista y el de la cancelación', (tester) async {
      final manejador = tester.ensureSemantics();
      final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe()]));
      arnes.pedidos.fallaAlLeer = true;
      await montarMisPedidos(tester, arnes);
      expect(_seAnuncia(tester, _aviso), isTrue);
      manejador.dispose();
    });

    testWidgets('el error al cancelar se anuncia', (tester) async {
      final manejador = tester.ensureSemantics();
      final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe()]));
      arnes.pedidos.fallasAlCancelar.add(const FailurePedidoNoCancelado(causa: 'X'));
      await montarDetalle(tester, arnes, 'ped-1');
      await tocar(tester, find.byKey(const Key('pedidos_boton_secundario')), cuadros: 3);
      await tocar(tester, find.byKey(const Key('pedido_si_cancelar')), cuadros: 4);
      expect(_seAnuncia(tester, _aviso), isTrue);
      manejador.dispose();
    });
  });

  group('37A · el cargando tiene contexto', () {
    testWidgets(
      'dado que los productos todavía no bajaron de la base, la pantalla dice qué está cargando',
      (tester) async {
        final manejador = tester.ensureSemantics();
        final espera = ArmadoQueEspera();
        await montarPedirCargando(tester, ArnesDePedidos(), espera);

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('[Cc]argando')),
          findsWidgets,
          reason: 'un spinner suelto no dice qué carga (convenciones §8.3)',
        );
        espera.productos.complete(productosDelCanvas);
        await tester.pump();
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        manejador.dispose();
      },
      // skip: QA #387 — mientras bajan los productos 37A pinta un `CircularProgressIndicator` sin texto ni
      // etiqueta, y la situación un bloque gris sin etiqueta (37B·05 sí dice «Cargando tus pedidos»).
      skip: !verHallazgos37,
    );
  });

  group('Privacidad', () {
    test('toString de pedido, parámetros y fallas no imprime datos de la persona', () {
      final pedido = pedidoDe(motivoRechazo: 'Juan Pérez, Rivera 123, 099 123 456');
      expect(pedido.toString(), isNot(contains('Juan')));
      expect(pedido.toString(), isNot(contains('col-1')));
      const params = EnviarPedidoParams(
        pedidoId: 'ped-1',
        colportorId: 'col-secreto',
        cantidades: {'p-salud': 1},
        productos: [saludYHogar],
        idsDeLineas: {'p-salud': 'l-1'},
      );
      expect(params.toString(), isNot(contains('col-secreto')));
      expect(
        const FailurePedidoNoGuardado(causa: 'SqliteException').toString(),
        isNot(contains('INSERT')),
      );
    });
  });

  group('Sin pedidos enviados todavía (sin conexión)', () {
    testWidgets(
      'dado un pedido guardado que no llegó al servidor, la lista lo distingue de uno ya recibido',
      (tester) async {
        final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(id: 'guardado')]));
        await montarMisPedidos(tester, arnes);
        expect(_t(TextosPedidos.sinLlegar), findsOneWidget);
      },
      // skip: QA #387 — `TextosPedidos.sinLlegar` («Esperando conexión para enviarse») no se usa en ningún
      // lado: en la lista un pedido que no salió del teléfono dice «Por autorizar» igual que uno que ya llegó.
      skip: !verHallazgos37,
    );
  });
}
