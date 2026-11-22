// QA de «Venta crece» (vista 42, 42B·09A a 09D; #693): las guías de accesibilidad de Flutter (tamaño
// de toque de Android e iOS, etiqueta en cada toque y contraste del texto) en cada pantalla y estado, a
// 360×640 y 412×915. Con la letra de prueba (Ahem): el contraste con la letra real da falsos negativos.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/venta_registrada_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/textos_venta_que_crece.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/hoja_a_que_venta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista42_venta_crece_693_arnes.dart';
import '../../helpers/venta_ui_falsos.dart';

const _tamanos = <({String nombre, Size tamano})>[
  (nombre: '360x640', tamano: telefonoChico693),
  (nombre: '412x915', tamano: telefonoGrande693),
];

final _v39 = ventaAbierta693('v-39');
final _v31 = ventaAbierta693(
  'v-31',
  numero: '0031',
  fecha: DateTime.utc(2026, 10, 12, 15),
  total: 24000,
  cobrado: 0,
  descripcion: 'Vida Feliz × 2',
);

Future<void> _guias(WidgetTester tester, {bool contraste = true}) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (contraste) await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

Future<void> _sumarSaludYHogar(WidgetTester tester) async {
  await tocar(tester, find.text('Libros'));
  await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
  await tocar(tester, find.text(TextosVenta.agregarALaVenta));
}

void main() {
  for (final t in _tamanos) {
    group('Guías de accesibilidad · ${t.nombre}', () {
      testWidgets('09A · la hoja de la casa con «Sumar un libro»', (tester) async {
        await montarHoja693(
          tester,
          repo: VentasAbiertasQA(abiertas: [_v39]),
          tamano: t.tamano,
        );
        await asentar693(tester);

        await _guias(tester);
      });

      testWidgets('09A · la hoja de la casa con «Sumar un libro» y varias ventas', (tester) async {
        await montarHoja693(
          tester,
          repo: VentasAbiertasQA(abiertas: [_v39, _v31]),
          tamano: t.tamano,
        );
        await asentar693(tester);

        await _guias(tester);
      });

      testWidgets('09A · la ficha con «Sumar un libro»', (tester) async {
        await montarFicha693(
          tester,
          repo: VentasAbiertasQA(abiertas: [_v39]),
          tamano: t.tamano,
        );
        await asentar693(tester);

        await _guias(tester);
      });

      testWidgets('09B · ¿A qué venta lo sumás?', (tester) async {
        tester.view.physicalSize = t.tamano;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: temaClaro(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => mostrarHojaAQueVenta(
                  context,
                  ventas: [_v39, _v31],
                  subtitulo: 'Pedro Gómez · Grecia 3307',
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('abrir'));
        await asentar693(tester);

        await _guias(tester);
      });

      testWidgets('09C · vacía (lo ya vendido a la vista)', (tester) async {
        final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [_v39]));
        await montarNuevaVenta(tester, e, creceSobre: _v39, tamano: t.tamano);

        await _guias(tester);
      });

      testWidgets('09C · con el libro nuevo', (tester) async {
        final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [_v39]));
        await montarNuevaVenta(tester, e, creceSobre: _v39, tamano: t.tamano);
        await _sumarSaludYHogar(tester);

        await _guias(tester);
      });

      testWidgets('09C · cambiando el monto de lo que se suma', (tester) async {
        final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [_v39]));
        await montarNuevaVenta(tester, e, creceSobre: _v39, tamano: t.tamano);
        await _sumarSaludYHogar(tester);
        await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));

        await _guias(tester);
      });

      testWidgets('09C · con la venta que ya tiene el monto cambiado', (tester) async {
        final conMotivo = ventaAbierta693('v-39', motivo: 'redondeo');
        final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [conMotivo]));
        await montarNuevaVenta(tester, e, creceSobre: conMotivo, tamano: t.tamano);
        await _sumarSaludYHogar(tester);

        await _guias(tester);
      });

      testWidgets('09C · con el aviso «No pudimos guardar» y «Reintentar»', (tester) async {
        final repo = VentasAbiertasQA(abiertas: [_v39])
          ..respuestas.add(const FailureVentaNoGuardada());
        final e = EntornoDeVenta(crece: repo);
        await montarNuevaVenta(tester, e, creceSobre: _v39, tamano: t.tamano);
        await _sumarSaludYHogar(tester);
        await tocar(tester, find.byKey(const Key('venta_cta')));

        await _guias(tester);
      });

      testWidgets('09C · con el aviso de venta cerrada', (tester) async {
        final repo = VentasAbiertasQA(abiertas: [_v39])
          ..respuestas.add(const FailureVentaCerrada(numeroTalonario: '0039'));
        final e = EntornoDeVenta(crece: repo);
        await montarNuevaVenta(tester, e, creceSobre: _v39, tamano: t.tamano);
        await _sumarSaludYHogar(tester);
        await tocar(tester, find.byKey(const Key('venta_cta')));

        await _guias(tester);
      });

      for (final cuotas in [false, true]) {
        testWidgets('09D · cierre ${cuotas ? 'con' : 'sin'} «Modificar cuotas»', (tester) async {
          tester.view.physicalSize = t.tamano;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: temaClaro(),
              home: VentaRegistradaPage(
                guardada: VentaQueCrecio(
                  venta: ventaDe('v-39', talonario: '0039', monto: 160000),
                  items: [itemDe('n-1', 'v-39', cantidad: 1, precio: 40000)],
                  totalAnteriorCentavos: 120000,
                  sumadoEl: DateTime.utc(2026, 11, 11),
                ),
                nombreDelCliente: 'Pedro Gómez',
                conEntregarAhora: true,
                conEntregarOtroDia: true,
                conCobro: true,
                crece: TextosDelCierreQueCrece(
                  eyebrow: TextosVentaQueCrece.eyebrowCierre('0039'),
                  titulo: TextosVentaQueCrece.tituloCierre('0039', 1),
                  subtitulo: TextosVentaQueCrece.subtituloCierre('Pedro Gómez', 160000, 120000),
                  rotuloEntrega: TextosVentaQueCrece.entregaDelLibroNuevo,
                  detalleCobro: TextosVentaQueCrece.saldoDeLaVenta(120000),
                  detalleModificarCuotas: cuotas
                      ? TextosVentaQueCrece.modificarCuotasSub(120000)
                      : null,
                ),
                alContinuar: (_) {},
                alTerminar: () {},
              ),
            ),
          );
          await asentar693(tester);

          await _guias(tester);
        });
      }
    });
  }
}
