// QA de la vista 11 «Espacios» (HU-UBI-007, #211, PR #468), ronda 3: las guías de accesibilidad de
// Flutter con el aviso puesto DENTRO de la hoja (cuenta restringida y edición que no se pudo abrir),
// a 360×640 y 412×915 con texto ×1 y ×2. Archivo aparte con la letra de prueba (Ahem): con las fuentes
// reales el `textContrastGuideline` da falsos negativos.
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista11_211_arnes.dart';

class _Cuenta extends EstadoCuentaNotifier {
  _Cuenta(this._estado);
  final EstadoCuenta _estado;
  @override
  Future<EstadoCuenta?> build() async => _estado;
}

void main() {
  setUpAll(() => usarFuentesReales211 = false);

  for (final tamano in [telefonoChico211, telefonoGrande211]) {
    for (final escala in [1.0, 2.0]) {
      for (final cuenta in [EstadoCuenta.suspendida, EstadoCuenta.pendienteAsignacion]) {
        testWidgets('con el aviso de la cuenta ${cuenta.name} dentro de la hoja cumple las guías a '
            '${tamano.width.toInt()}×${tamano.height.toInt()} con texto ×$escala', (tester) async {
          final h = tester.ensureSemantics();
          await montarHoja(
            tester,
            espacios: deptosDelCanvas(),
            tamano: tamano,
            escala: escala,
            abrir: false,
            extras: [estadoCuentaProvider.overrideWith(() => _Cuenta(cuenta))],
          );
          final contenedor = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
          final suscripcion = contenedor.listen(estadoCuentaProvider, (_, _) {});
          addTearDown(suscripcion.close);
          await asentarHoja(tester);
          await abrirLaHoja(tester);
          await tester.tap(botonAgregarDepto);
          await asentarHoja(tester);

          expect(find.byKey(ClavesHojaUbicacion.aviso), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          h.dispose();
        });
      }
    }
  }
}
