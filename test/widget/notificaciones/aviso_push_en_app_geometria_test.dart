// HU-NOT-003 (#187) — 24C·08 con la letra real: el aviso de arriba con un título largo y el texto
// agrandado cabe a lo ancho, se parte en renglones y no tapa media pantalla. (Con la letra de
// prueba cada carácter mide el tamaño de la fuente y las alturas no valen: va en su propio archivo.)
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/aviso_push_en_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;

const _tituloLargo =
    'Tu pedido de libros de la campaña de verano fue autorizado por tu coordinador';

Notificacion _aviso({String titulo = _tituloLargo}) => Notificacion(
  id: 'a',
  tipo: TipoNotificacion.pedidoAutorizado,
  titulo: titulo,
  destino: const DestinoAgenda('x'),
  recibidaEn: DateTime.utc(2026, 11, 9, 15, 30),
);

void main() {
  setUpAll(cargarFuentesReales);

  for (final (ancho, alto, texto) in [
    (320.0, 568.0, 2.0),
    (360.0, 640.0, 2.0),
    (390.0, 844.0, 1.0),
    (390.0, 844.0, 3.0),
  ]) {
    testWidgets('dado un título largo a ${ancho.toInt()} dp con el texto al $texto, entonces el '
        'aviso se parte en renglones, cabe a lo ancho y no tapa media pantalla', (tester) async {
      tester.view
        ..physicalSize = Size(ancho, alto)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = texto;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: temaClaro(),
          home: Scaffold(
            body: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AvisoPushEnApp(aviso: _aviso(), onAbrir: () {}, onCerrar: () {}),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final caja = tester.getRect(find.byType(AvisoPushEnApp));
      expect(caja.left, greaterThanOrEqualTo(0));
      expect(caja.right, lessThanOrEqualTo(ancho));
      expect(
        tester.getRect(find.byKey(const Key('aviso_push_en_app_cerrar'))).right,
        lessThanOrEqualTo(ancho),
      );
      expect(
        caja.bottom,
        lessThan(alto * 0.75),
        reason: 'no tapa más de tres cuartos de la pantalla',
      );
    });
  }
}
