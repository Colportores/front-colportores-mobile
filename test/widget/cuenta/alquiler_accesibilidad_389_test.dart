// Accesibilidad de «Mi alquiler» (vista 38C, HU-CTA-007, #389): las guías de toque (Android e iOS), de
// etiqueta y de contraste de Flutter en cada estado, a dos tamaños de teléfono con el texto al 100 % y
// al 200 %, y la línea «Alquiler» de Mi Cuenta.
import 'package:colportores_mobile/features/cuenta/domain/entities/alquiler.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alquiler_arnes.dart';
import '../../helpers/cuenta_arnes.dart';

/// Cada estado de la pantalla: (nombre, repositorio, conexión).
final _estados = <String, (RepositorioDeAlquilerControlable Function(), TipoConexion)>{
  '38C·01 deuda': (
    () => RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas),
    TipoConexion.wifi,
  ),
  '38C·02 por validar': (
    () => RepositorioDeAlquilerControlable(inicial: alquilerConPorValidar),
    TipoConexion.wifi,
  ),
  '38C·03 pagado': (
    () => RepositorioDeAlquilerControlable(inicial: alquilerPagado),
    TipoConexion.wifi,
  ),
  '38C·03 pagado de más': (
    () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon([
        campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
      ]),
    ),
    TipoConexion.wifi,
  ),
  '38C·04 no cobra': (
    () => RepositorioDeAlquilerControlable(inicial: AlquilerDelColportor.vacio),
    TipoConexion.wifi,
  ),
  '38C·05 sin conexión': (
    () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon(alquilerDelCanvas.campanias, bajadoEn: DateTime(2026, 11, 21, 21)),
    ),
    TipoConexion.sinConexion,
  ),
  'rechazado y devuelto': (
    () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon([
        campaniaCon(
          pagos: [
            pagoDe(3000, estado: EstadoDePagoDeAlquiler.rechazado, motivo: 'el monto no coincide'),
            pagoDe(4000, estado: EstadoDePagoDeAlquiler.devuelto),
            pagoDe(6000),
          ],
        ),
      ]),
    ),
    TipoConexion.wifi,
  ),
  'dos campañas': (
    () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon([
        campaniaCon(id: 'c-1', pagos: [pagoDe(6000)]),
        campaniaCon(id: 'c-2', nombre: 'Otoño 2026', monto: 10000),
      ]),
    ),
    TipoConexion.wifi,
  ),
  'cargando': (() => RepositorioDeAlquilerControlable(), TipoConexion.wifi),
  'error': (() => RepositorioDeAlquilerControlable()..fallaAlSuscribir = true, TipoConexion.wifi),
};

void main() {
  group('accesibilidad por estado de «Mi alquiler»', () {
    for (final estado in _estados.entries) {
      for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('${estado.key} a ${tam.key}, texto $escala: toque, etiqueta y contraste', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            final (repo, conexion) = estado.value;
            await montarAlquiler(
              tester,
              repo(),
              tamano: tam.value,
              escala: escala,
              conexion: conexion,
            );
            await tester.pump();

            final falla = tester.takeException();
            expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            // El contraste se mide a 1x: con el texto grande la guía lee mal las cajas de la fuente de
            // prueba (nota del carril).
            if (escala == 1.0) await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }
  });

  group('accesibilidad de la línea «Alquiler» de Mi Cuenta', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('texto $escala: toque, etiqueta y contraste', (tester) async {
        final semantica = tester.ensureSemantics();
        await montarCuenta(
          tester,
          RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
          tamano: const Size(390, 844),
          escala: escala,
          overrides: overridesDeAlquiler(
            RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas),
          ),
        );
        await tester.pump();

        final falla = tester.takeException();
        expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        if (escala == 1.0) await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  });
}
