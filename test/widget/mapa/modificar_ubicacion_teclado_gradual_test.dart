// Vista 07 «Modificar ubicación» (HU-UBI-004, #307, ronda final de PR #321): «Abrir de nuevo» queda a la
// vista cuando la falla «cambió mientras la editabas» llega con el teclado todavía bajando.
//
// Con el guardado rápido (lo normal con la base local) los campos pasan a solo lectura al tocar
// «Guardar cambios» y el teclado empieza a bajar de a poco; la falla llega en cualquiera de esos
// cuadros. El aviso se lleva a la vista con la hoja de teclado abierto (cabeza compacta) y, cuando el
// teclado llega a 0, la cabeza vuelve a ser la completa: el área que se desplaza se achica y la acción
// tiene que volver a llevarse a la vista (`didUpdateWidget` de `HojaModificarDatos`).
//
// Complementa a `modificar_ubicacion_geometria_test.dart` (guardado lento: la falla llega con el
// teclado ya abajo) y a `modificar_ubicacion_qa_307_test.dart` (el teclado baja de golpe). Con las
// fuentes reales del proyecto.
import 'dart:async';
import 'dart:math' as math;

import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/modificar_ubicacion_falsos.dart' show ubicacionGuardada;
import '../../helpers/modificar_ubicacion_qa_307_arnes.dart';

void main() {
  setUpAll(cargarFuentesReales);

  final accion = find.text(TextosModificar.abrirDeNuevo);
  final objetivo = find.ancestor(of: accion, matching: find.byType(TextButton));

  final telefonos = <(String, Size)>[('360×640', telefono360x640), ('320×568', telefono320x568)];
  final sistemas = <(String, double)>[('sin barra de abajo', 0), ('con barra de 3 botones', 48)];
  // El teclado de 300 dp baja en 15 cuadros de 20 dp: la falla llega antes del primero, a mitad de
  // camino, casi al final y justo en el último.
  const cuadrosDeLaFalla = [0, 6, 12, 14];

  group('Guardado rápido: la falla llega con el teclado bajando', () {
    for (final (nombreTel, tamano) in telefonos) {
      for (final escala in [1.0, 2.0]) {
        for (final (nombreSis, barra) in sistemas) {
          for (final cuadro in cuadrosDeLaFalla) {
            testWidgets('$nombreTel · texto ${(escala * 100).round()} % · $nombreSis · la falla en '
                'el cuadro $cuadro de 15: la acción queda a la vista y se toca', (tester) async {
              final m = await abrirEdicion(
                tester,
                tamano: tamano,
                escala: escala,
                barraInferior: barra,
              );

              // Escribe el número con el teclado arriba y guarda; la lectura espera a que el test
              // suelte la falla en el cuadro elegido de la baja del teclado. Con el teclado arriba
              // en 320×568 al 200 % la hoja desborda al escribir (anterior a #307, issue aparte).
              await sinContarElDesborde(() async {
                await tester.enterText(campoNumero, '1238');
                await asentarConTeclado(tester);
                expect(tester.view.viewInsets.bottom, tecladoAbierto);
                m.repo.actual = ubicacionGuardada(actualizada: DateTime.utc(2026, 10, 1, 9));
                final lectura = m.repo.bloqueoLectura = Completer<void>();
                await tester.tap(botonGuardar);
                await tester.pump(const Duration(milliseconds: 16));
                expect(
                  tester.testTextInput.isVisible,
                  isFalse,
                  reason: 'guardando, los campos son de lectura y el teclado empieza a bajar',
                );
                await bajarTecladoDeAPoco(
                  tester,
                  alCuadro: (n) {
                    if (n == cuadro) lectura.complete();
                  },
                );
                await asentar(tester);
              });

              expect(find.textContaining('cambió mientras la editabas'), findsOneWidget);
              expect(tester.testTextInput.isVisible, isFalse, reason: 'el teclado no vuelve');
              expect(tester.view.viewInsets.bottom, 0);
              expect(tester.takeException(), isNull);

              final zona = rectZona(tester);
              final fijo = tester.getRect(botonGuardar);
              final texto = tester.getRect(accion);
              final alcance = tester.getRect(objetivo);
              expect(fijo.bottom, lessThanOrEqualTo(tamano.height - barra + .5));
              // La acción cae dentro de lo que se desplaza (4 dp de holgura: el interlineado de arriba
              // del renglón) y sobre el botón fijo.
              expect(texto.top, greaterThanOrEqualTo(zona.top - 4), reason: 'sin cortar arriba');
              expect(texto.bottom, lessThanOrEqualTo(zona.bottom + .5), reason: 'sin cortar abajo');
              expect(texto.bottom, lessThanOrEqualTo(fijo.top + .5), reason: 'sobre el botón fijo');
              // El objetivo táctil asoma al menos los 24 dp de WCAG 2.5.8 (AA).
              final visible =
                  math.min(alcance.bottom, zona.bottom) - math.max(alcance.top, zona.top);
              expect(visible, greaterThanOrEqualTo(24));

              expect(accion.hitTestable(), findsOneWidget);
              final lecturas = m.repo.lecturas;
              m.repo.bloqueoLectura = null;
              await tester.tap(accion);
              await asentar(tester);
              expect(accion, findsNothing, reason: 'el toque llegó');
              expect(m.repo.lecturas, lecturas + 1);
              expect(m.repo.escrituras, isEmpty, reason: 'nunca se pisó lo que cambió');
              expect(tester.takeException(), isNull);
            });
          }
        }
      }
    }
  });
}
