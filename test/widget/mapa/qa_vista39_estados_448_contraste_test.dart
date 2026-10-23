// QA ronda 1 de la vista 39, grupo E (#448, PR #462): contraste de texto (`textContrastGuideline`) en
// cada estado y tamaño. Va aparte y SIN cargar las fuentes reales: con la letra real la guía lee los
// bordes suavizados del texto y da falsos negativos; con Ahem cada letra es un bloque y el par de
// colores se mide limpio.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/modificar_ubicacion_falsos.dart';

ItemListaUbicacion _item(String id, TipoUbicacion tipo, EstadoCasa? estado, {DateTime? baja}) =>
    ItemListaUbicacion(
      ubicacion: ubicacionGuardada(id: id, tipo: tipo, deBajaDesde: baja),
      estado: estado,
    );

final _estados = <String, Widget Function()>{
  'E·02 error': () => AvisoHojaCasa.errorAlLeer(alReintentar: () {}),
  'E·04 baja con Reactivar': () => AvisoHojaCasa.dadaDeBaja(alReactivar: () {}),
  'E·04 baja por unión': () => AvisoHojaCasa.dadaDeBaja(),
  'E·05 lejos': () => AvisoHojaCasa.lejos(metros: 650),
  'E·06 tres': () => ElegirUbicacionDelPunto(
    ubicaciones: [
      _item('u-1', TipoUbicacion.casa, EstadoCasa.cobranzaPendiente),
      _item('u-2', TipoUbicacion.casa, EstadoCasa.noContesto),
      _item('u-3', TipoUbicacion.negocio, EstadoCasa.sinVisita),
      _item('u-4', TipoUbicacion.edificio, null, baja: DateTime(2026, 10, 18)),
    ],
    alElegir: (_) {},
  ),
};

void main() {
  for (final entrada in _estados.entries) {
    for (final escala in [1.0, 2.0]) {
      testWidgets('${entrada.key} · texto $escala×: el texto cumple el contraste AA', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 640);
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
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: entrada.value(),
              ),
            ),
          ),
        );
        await tester.pump();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }
}
