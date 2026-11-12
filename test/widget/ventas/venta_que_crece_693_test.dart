// «Venta crece» (vista 42, 42B·09C; HU-VEN-001, #693): la venta abierta con lo ya vendido a la vista y
// el libro nuevo, sin otro talonario. Un test por estado y por caso límite: doble toque, falla a mitad
// del guardado (el botón vuelve), la venta que se cerró mientras tanto, salir con algo cargado, el
// motivo del monto, los misioneros que no se suman y texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_abierta.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/sumar_a_la_venta_use_case.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/textos_venta_que_crece.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/venta_falsos.dart';
import '../../helpers/venta_ui_falsos.dart';

/// La venta 0039 de María: una colección de 1 libro por $ 1.200, entregada el 23/10, con $ 400 pagos.
final venta39 = VentaAbierta(
  ventaId: 'v-39',
  espacioPersonaId: 'ep-1',
  numeroTalonario: '0039',
  fecha: DateTime.utc(2026, 10, 23, 15),
  montoTotalCentavos: 120000,
  cobradoCentavos: 40000,
  entregada: true,
  entregadaEl: DateTime.utc(2026, 10, 23, 15),
  renglones: const [
    RenglonYaVendido(
      nombre: 'Colección de 1 libro',
      cantidad: 1,
      precioUnitarioCentavos: 120000,
      subtotalCentavos: 120000,
      esCombo: true,
      librosDelCombo: 3,
      componentes: ['Salud y Hogar', 'El camino a Cristo', 'Vida Feliz'],
    ),
  ],
  descripcion: 'Colección de 1 libro',
);

Finder get _cta => find.byKey(const Key('venta_cta'));

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(_cta).onPressed != null;

Finder _campo(String clave) =>
    find.descendant(of: find.byKey(Key(clave)), matching: find.byType(TextField));

String _valor(WidgetTester tester, String clave) =>
    tester.widget<Text>(find.byKey(Key(clave))).data!;

/// Suma «Salud y Hogar» ($ 2.000) desde el selector de la venta vacía.
Future<void> _sumarSaludYHogar(WidgetTester tester) async {
  await tocar(tester, find.text('Libros'));
  await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
  await tocar(tester, find.text(TextosVenta.agregarALaVenta));
}

void main() {
  group('42B·09C La venta 0039 abierta, con el libro nuevo', () {
    testWidgets('el mismo talonario, lo ya vendido a la vista y sin tocar, y lo que se suma hoy', (
      tester,
    ) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      await montarNuevaVenta(tester, e, creceSobre: venta39);

      expect(find.text('VENTA 0039 · SUMAR UN LIBRO'), findsOneWidget);
      expect(find.text('Venta 0039'), findsOneWidget);
      expect(
        find.text('María Fernández · Mataojo 2044 · Depto 3B · el mismo talonario'),
        findsOneWidget,
      );
      // Sin número de talonario nuevo ni la tarjeta del cliente: no es otra venta.
      expect(find.byKey(const Key('venta_talonario')), findsNothing);
      expect(find.text('YA VENDIDO · 23/10 · NO SE CAMBIA'), findsOneWidget);
      expect(find.text('Con sus 3 libros · entregada el 23/10'), findsOneWidget);
      // Lo ya vendido no se quita.
      final yaVendido = find.byKey(const Key('venta_ya_vendido_0'));
      expect(
        find.descendant(of: yaVendido, matching: find.byTooltip(TextosVenta.quitar)),
        findsNothing,
      );
      expect(find.text(TextosVentaQueCrece.seSumaHoy), findsOneWidget);
    });

    testWidgets('al sumar el libro, «Nuevo», el total sube, lo pagado no cambia y el saldo sube', (
      tester,
    ) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      await montarNuevaVenta(tester, e, creceSobre: venta39);

      await _sumarSaludYHogar(tester);

      expect(find.text(TextosVentaQueCrece.nuevo), findsOneWidget);
      await verVisible(tester, find.byKey(const Key('venta_saldo')));
      expect(_valor(tester, 'venta_total_anterior'), r'$ 1.200');
      expect(_valor(tester, 'venta_total'), r'$ 3.200');
      expect(_valor(tester, 'venta_pagado'), r'$ 400');
      expect(_valor(tester, 'venta_saldo'), r'$ 2.800');
      expect(find.text('Sumar a la venta 0039'), findsOneWidget);
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('«Sumar a la venta» guarda lo nuevo y cierra con la venta que creció', (
      tester,
    ) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      final salida = await montarNuevaVenta(tester, e, creceSobre: venta39);
      await _sumarSaludYHogar(tester);

      await tocar(tester, _cta);

      final suma = e.crece.sumas.single;
      expect([suma.ventaId, suma.sumado, suma.motivo], ['v-39', 200000, null]);
      expect(suma.items.single.productoId, 'p-libro-0');
      expect(salida.guardada, isA<VentaQueCrecio>());
      expect(e.ventas.recibidas, isEmpty, reason: 'no es una venta nueva');
    });

    testWidgets('un doble toque suma una sola vez', (tester) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      e.crece.compuerta = Completer<void>();
      await montarNuevaVenta(tester, e, creceSobre: venta39);
      await _sumarSaludYHogar(tester);
      await verVisible(tester, _cta);

      await tester.tap(_cta);
      await tester.tap(_cta, warnIfMissed: false);
      await tester.pump();
      e.crece.compuerta!.complete();
      await asentar(tester);

      expect(e.crece.sumas, hasLength(1));
    });

    testWidgets('si falla, lo dice, el botón vuelve como «Reintentar» y el reintento es el mismo', (
      tester,
    ) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      e.crece.respuestas.add(const FailureVentaNoGuardada());
      final salida = await montarNuevaVenta(tester, e, creceSobre: venta39);
      await _sumarSaludYHogar(tester);

      await tocar(tester, _cta);

      expect(find.text(TextosVenta.errorAlGuardar), findsOneWidget);
      expect(find.text(TextosVenta.reintentar), findsOneWidget);
      expect(_habilitado(tester), isTrue);
      expect(salida.cerrada, isFalse);

      await tocar(tester, _cta);
      expect(e.crece.sumas, hasLength(2));
      expect(e.crece.sumas[0].items.first.id, e.crece.sumas[1].items.first.id);
      expect(salida.guardada, isA<VentaQueCrecio>());
    });

    testWidgets('si la venta se cerró mientras tanto, lo dice: el libro va en una venta nueva', (
      tester,
    ) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      e.crece.respuestas.add(const FailureVentaCerrada(numeroTalonario: '0039'));
      await montarNuevaVenta(tester, e, creceSobre: venta39);
      await _sumarSaludYHogar(tester);

      await tocar(tester, _cta);

      expect(find.text(const FailureVentaCerrada(numeroTalonario: '0039').mensaje), findsOneWidget);
    });

    testWidgets('cambiar el monto de lo que suma pide el motivo, y lo manda con la diferencia', (
      tester,
    ) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      await montarNuevaVenta(tester, e, creceSobre: venta39);
      await _sumarSaludYHogar(tester);

      await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));
      expect(find.text(TextosVentaQueCrece.montoDeLoQueSumas), findsWidgets);
      await escribir(tester, _campo('venta_monto'), '1.500');
      expect(_habilitado(tester), isFalse);
      expect(_valor(tester, 'venta_total'), r'$ 2.700');

      await escribir(tester, _campo('venta_motivo'), 'descuento del libro nuevo');
      await tocar(tester, _cta);

      final suma = e.crece.sumas.single;
      expect(
        [suma.sumado, suma.motivo, suma.diferencia],
        [150000, 'descuento del libro nuevo', -50000],
      );
    });

    // Decisión de Cristian del 11/11, «Dos motivos» (#706).
    VentaAbierta conMotivo(String motivo) => VentaAbierta(
      ventaId: 'v-39',
      espacioPersonaId: 'ep-1',
      numeroTalonario: '0039',
      fecha: DateTime.utc(2026, 10, 23, 15),
      montoTotalCentavos: 110000,
      cobradoCentavos: 0,
      motivoMontoManual: motivo,
    );

    testWidgets(
      'con el monto ya cambiado a mano se puede cambiar otra vez: junta los dos motivos',
      (tester) async {
        final venta = conMotivo('redondeo');
        final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta]));
        await montarNuevaVenta(tester, e, creceSobre: venta);
        await _sumarSaludYHogar(tester);

        await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));
        await escribir(tester, _campo('venta_monto'), '1.500');
        await escribir(tester, _campo('venta_motivo'), 'descuento del libro nuevo');
        await tocar(tester, _cta);

        final suma = e.crece.sumas.single;
        expect(suma.motivo, 'redondeo · descuento del libro nuevo');
        expect(suma.diferencia, -50000);
      },
    );

    testWidgets(
      'si los dos motivos no entran en 500, el campo dice cuántos quedan y no deja sumar',
      (tester) async {
        final venta = conMotivo('v' * 480);
        final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta]));
        await montarNuevaVenta(tester, e, creceSobre: venta);
        await _sumarSaludYHogar(tester);

        await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));
        await escribir(tester, _campo('venta_monto'), '1.500');
        // 480 + « · » = 483: quedan 17 para lo nuevo.
        await escribir(tester, _campo('venta_motivo'), 'descuento del libro nuevo');

        final aviso = SumarALaVentaUseCase.motivoNoEntra(17);
        expect(find.text(aviso), findsWidgets);
        expect(_habilitado(tester), isFalse);
        await tester.tap(_cta, warnIfMissed: false);
        await tester.pump();
        expect(e.crece.sumas, isEmpty);

        // Acortado, entra y se suma.
        await escribir(tester, _campo('venta_motivo'), 'descuento');
        expect(find.text(aviso), findsNothing);
        expect(_habilitado(tester), isTrue);
        await tocar(tester, _cta);
        expect(e.crece.sumas.single.motivo, '${'v' * 480} · descuento');
      },
    );

    testWidgets(
      'con el motivo viejo en 500 dice la salida: «Volver al monto calculado» suma (P1)',
      (tester) async {
        final venta = conMotivo('v' * 500);
        final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta]));
        await montarNuevaVenta(tester, e, creceSobre: venta);
        await _sumarSaludYHogar(tester);

        await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));
        await escribir(tester, _campo('venta_monto'), '1.500');
        await escribir(tester, _campo('venta_motivo'), 'x');

        final aviso = SumarALaVentaUseCase.motivoNoEntra(0);
        expect(aviso, contains('Volver al monto calculado'));
        expect(find.text(aviso), findsWidgets);
        expect(_habilitado(tester), isFalse);

        await verVisible(tester, find.byKey(const Key('venta_usar_calculado')));
        await tocar(tester, find.byKey(const Key('venta_usar_calculado')));
        expect(find.text(aviso), findsNothing);
        expect(_habilitado(tester), isTrue);
        await tocar(tester, _cta);
        expect(e.crece.sumas.single.motivo, isNull);
      },
    );

    // Decisión del 12/11, P1 del QA de #709: la ayuda dice que el motivo nuevo se suma.
    testWidgets('con un motivo ya puesto, la ayuda del campo dice que el nuevo se le suma', (
      tester,
    ) async {
      final venta = conMotivo('redondeo');
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta]));
      await montarNuevaVenta(tester, e, creceSobre: venta);
      await _sumarSaludYHogar(tester);
      await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));

      expect(find.text(TextosVentaQueCrece.motivoQueSeSuma), findsOneWidget);
      expect(find.text(TextosVenta.avisoMotivo), findsNothing);
    });

    testWidgets('sin motivo de antes, la ayuda de siempre', (tester) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      await montarNuevaVenta(tester, e, creceSobre: venta39);
      await _sumarSaludYHogar(tester);
      await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));

      expect(find.text(TextosVenta.avisoMotivo), findsOneWidget);
      expect(find.text(TextosVentaQueCrece.motivoQueSeSuma), findsNothing);
    });

    testWidgets('con el monto calculado el motivo viejo queda como estaba', (tester) async {
      final venta = conMotivo('redondeo');
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta]));
      await montarNuevaVenta(tester, e, creceSobre: venta);
      await _sumarSaludYHogar(tester);

      await tocar(tester, _cta);

      expect(e.crece.sumas.single.motivo, isNull);
    });

    testWidgets('los misioneros no se ofrecen: van por «Lo que dejaste»', (tester) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      await montarNuevaVenta(tester, e, creceSobre: venta39);

      expect(find.text(TextosVenta.misioneros), findsNothing);
    });

    testWidgets('la venta nueva de siempre sigue ofreciendo los misioneros', (tester) async {
      await montarNuevaVenta(tester, EntornoDeVenta());

      expect(find.text(TextosVenta.misioneros), findsOneWidget);
    });

    testWidgets('✕ con el libro cargado pide confirmación; «Seguir sumando» se queda', (
      tester,
    ) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      final salida = await montarNuevaVenta(tester, e, creceSobre: venta39);
      await _sumarSaludYHogar(tester);

      await tocar(tester, find.byKey(const Key('venta_atras')));
      expect(find.text(TextosVentaQueCrece.salirTitulo), findsOneWidget);
      await tocar(tester, find.text(TextosVentaQueCrece.salirSeguir));
      expect(salida.cerrada, isFalse);

      await tocar(tester, find.byKey(const Key('venta_atras')));
      await tocar(tester, find.text(TextosVenta.salirSalir));
      expect(salida.cerrada, isTrue);
      expect(salida.guardada, isNull);
      expect(e.crece.sumas, isEmpty);
    });

    testWidgets('sin nada cargado, ✕ vuelve sin preguntar (y reentrar arranca de cero)', (
      tester,
    ) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      final salida = await montarNuevaVenta(tester, e, creceSobre: venta39);

      await tocar(tester, find.byKey(const Key('venta_atras')));
      expect(salida.cerrada, isTrue);
      await tocar(tester, find.byKey(const Key('abrir_venta')));
      expect(find.text(TextosVentaQueCrece.nuevo), findsNothing);
    });

    testWidgets('con texto al 200 % en un teléfono chico se ve todo sin desbordes', (tester) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta39]));
      await montarNuevaVenta(
        tester,
        e,
        creceSobre: venta39,
        escala: 2,
        tamano: const Size(320, 568),
      );
      await _sumarSaludYHogar(tester);
      await verVisible(tester, find.byKey(const Key('venta_saldo')));

      expect(tester.takeException(), isNull);
      expect(find.text('Sumar a la venta 0039'), findsOneWidget);
    });

    testWidgets('al 200 % el aviso de los dos motivos que no entran se lee entero (#706)', (
      tester,
    ) async {
      final venta = VentaAbierta(
        ventaId: 'v-39',
        espacioPersonaId: 'ep-1',
        numeroTalonario: '0039',
        fecha: DateTime.utc(2026, 10, 23, 15),
        montoTotalCentavos: 110000,
        cobradoCentavos: 0,
        motivoMontoManual: 'v' * 480,
      );
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [venta]));
      await montarNuevaVenta(tester, e, creceSobre: venta, escala: 2, tamano: const Size(320, 568));
      await _sumarSaludYHogar(tester);
      await verVisible(tester, find.byKey(const Key('venta_cambiar_monto')));
      await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));
      await verVisible(tester, _campo('venta_monto'));
      await escribir(tester, _campo('venta_monto'), '1.500');
      await verVisible(tester, _campo('venta_motivo'));
      await escribir(tester, _campo('venta_motivo'), 'descuento del libro nuevo');

      expect(tester.takeException(), isNull);
      expect(find.text(SumarALaVentaUseCase.motivoNoEntra(17)), findsWidgets);
    });
  });
}
