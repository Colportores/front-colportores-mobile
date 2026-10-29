// «Terminar jornada» en la pantalla de la cuenta restringida (#472): medidas con la letra real, a
// los dos tamaños chicos del proyecto y con el texto al 100 %, 200 % y 300 %. Con la letra de
// prueba (Ahem) cada carácter mide el tamaño de la fuente y los desbordes que da no existen.
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../helpers/entrevista_falsos.dart';
import '../helpers/terminar_jornada_cuenta_arnes.dart';

final _boton = find.byKey(const Key('cuenta_terminar_jornada_boton'));
final _filaFin = find.byKey(const Key('jornada_ajustar_hora_fin'));
final _errorFin = find.byKey(const Key('jornada_error_fin'));
const _tamanos = [Size(320, 568), Size(360, 640)];
const _escalas = [1.0, 2.0, 3.0];

void main() {
  setUpAll(cargarFuentesReales);

  late LocalDeJornada local;
  late MontajeEntrevista montaje;

  setUp(() {
    montaje = MontajeEntrevista();
    local = LocalDeJornada([jornadaAbiertaDesde(DateTime(2026, 10, 23, 13, 15))]);
  });

  for (final estado in [EstadoCuenta.suspendida, EstadoCuenta.pendienteAsignacion]) {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        final cuando =
            '${estado.name} · ${tamano.width.toInt()}×${tamano.height.toInt()} · '
            'texto ${(escala * 100).toInt()} %';

        testWidgets('sin desborde y con el botón entero a mano · $cuando', (tester) async {
          await montarCuentaConJornada(
            tester,
            local: local,
            montaje: montaje,
            estado: estado,
            tamano: tamano,
            escala: escala,
          );

          await tester.ensureVisible(_boton);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull, reason: 'sin overflow');
          expect(tester.getSize(_boton).height, greaterThanOrEqualTo(52));
          expect(tester.getRect(_boton).left, greaterThanOrEqualTo(0));
          expect(tester.getRect(_boton).right, lessThanOrEqualTo(tamano.width));
          expect(tester.getRect(_filaFin).right, lessThanOrEqualTo(tamano.width));
        });

        testWidgets('el aviso de falla se lee entero y el botón vuelve a responder · $cuando', (
          tester,
        ) async {
          local.errorAlFinalizar = StateError('disco lleno');
          await montarCuentaConJornada(
            tester,
            local: local,
            montaje: montaje,
            estado: estado,
            tamano: tamano,
            escala: escala,
          );

          await tester.ensureVisible(_boton);
          await tester.tap(_boton);
          await tester.pumpAndSettle();
          await tester.ensureVisible(_errorFin);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull, reason: 'sin overflow');
          expect(find.textContaining('sigue abierta'), findsWidgets);
          expect(tester.getRect(_errorFin).right, lessThanOrEqualTo(tamano.width));
          await tester.ensureVisible(_boton);
          expect(tester.widget<FilledButton>(_boton).onPressed, isNotNull);
        });
      }
    }
  }
}
