// Vista 39, grupo E (#448): las medidas con las fuentes reales de la app (Inter), que son las que
// importan en un teléfono de 320 dp con el texto agrandado. Va aparte porque cargar las fuentes cambia
// las medidas de todos los tests de un archivo.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/modificar_ubicacion_falsos.dart';

Future<void> _montar(WidgetTester tester, Widget hijo, double escala, Size tamano) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: hijo),
      ),
    ),
  );
}

void main() {
  setUpAll(cargarFuentesReales);

  const tamanos = [Size(320, 568), Size(360, 640), Size(412, 915)];
  const escalas = [1.0, 2.0, 3.0];

  for (final tamano in tamanos) {
    for (final escala in escalas) {
      testWidgets('los avisos y las filas de E·06 caben en ${tamano.width.toInt()}×'
          '${tamano.height.toInt()} al ${(escala * 100).toInt()} %', (tester) async {
        await _montar(
          tester,
          Column(
            spacing: 12,
            children: [
              AvisoHojaCasa.errorAlLeer(alReintentar: () {}),
              AvisoHojaCasa.dadaDeBaja(alReactivar: () {}),
              AvisoHojaCasa.lejos(metros: 3250),
              ElegirUbicacionDelPunto(
                ubicaciones: [
                  ItemListaUbicacion(
                    ubicacion: ubicacionGuardada(
                      calle: 'Avenida General Don José Gervasio Artigas',
                      numero: '12345 bis',
                    ),
                    estado: EstadoCasa.entregaYPago,
                  ),
                  ItemListaUbicacion(ubicacion: ubicacionGuardada(id: 'u-2')),
                ],
                alElegir: (_) {},
              ),
            ],
          ),
          escala,
          tamano,
        );

        expect(tester.takeException(), isNull);
        // Ninguna palabra queda cortada por dentro ni fuera de la pantalla.
        for (final clave in [
          ClavesEstadosHojaCasa.avisoErrorAlLeer,
          ClavesEstadosHojaCasa.avisoDadaDeBaja,
          ClavesEstadosHojaCasa.avisoLejos,
          ClavesEstadosHojaCasa.elegirUbicacion,
        ]) {
          final caja = tester.getRect(find.byKey(clave));
          expect(caja.left, greaterThanOrEqualTo(0));
          expect(caja.right, lessThanOrEqualTo(tamano.width));
        }
      });
    }
  }
}
