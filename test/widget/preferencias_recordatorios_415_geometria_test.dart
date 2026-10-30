// HU-NOT-004 / issue #415 — las preferencias de los recordatorios (vista 24 B) a texto grande en
// teléfonos chicos, con la letra real: el interruptor y la anticipación se leen enteros, entran de
// ancho y de alto en la pantalla y se alcanzan. Va en su propio archivo porque carga la letra real
// (con la de prueba, de cuadrados, el corte de renglones no es el real) y eso cambia las medidas de
// todo el archivo.
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../helpers/notificaciones_arnes.dart';

class _SesionFija extends SesionNotifier {
  @override
  Future<Sesion?> build() async => null;
}

final _interruptor = find.byKey(const Key('pref_recordatorios_interruptor'));
final _slider = find.byKey(const Key('pref_anticipacion_slider'));
final _valor = find.byKey(const Key('pref_anticipacion_valor'));

void main() {
  setUpAll(cargarFuentesReales);

  for (final (nombre, tamano) in [
    ('360×640', const Size(360, 640)),
    ('320×568', const Size(320, 568)),
    ('412×915', const Size(412, 915)),
  ]) {
    for (final escala in [1.0, 2.0, 3.0]) {
      for (final (estado, armar) in <(String, Telefono Function())>[
        ('con todo activado', () => Telefono(estado: EstadoSistemaNotificaciones.activadas)),
        ('con el permiso del teléfono apagado', Telefono.new),
        (
          'con los recordatorios apagados',
          () =>
              Telefono(estado: EstadoSistemaNotificaciones.activadas)
                ..preferencias.preferencias = const PreferenciasRecordatorios(activados: false),
        ),
        (
          'con 120 minutos',
          () => Telefono(estado: EstadoSistemaNotificaciones.activadas)
            ..preferencias.preferencias = const PreferenciasRecordatorios(anticipacionMinutos: 120),
        ),
      ]) {
        testWidgets('a $nombre y texto $escala $estado: se lee entero y se alcanza', (
          tester,
        ) async {
          fijarTamano(tester, tamano: tamano, texto: escala);
          final telefono = armar();
          await tester.pumpWidget(
            ProviderScope(
              key: UniqueKey(),
              overrides: [...telefono.overrides, sesionProvider.overrideWith(_SesionFija.new)],
              child: MaterialApp(theme: temaClaro(), home: const NotificacionesPage()),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          for (final control in [_interruptor, _slider]) {
            await tester.ensureVisible(control);
            await tester.pumpAndSettle();
            final caja = tester.getRect(control);
            expect(caja.left, greaterThanOrEqualTo(0), reason: '$control');
            expect(caja.right, lessThanOrEqualTo(tamano.width), reason: '$control');
            expect(caja.top, greaterThanOrEqualTo(0), reason: '$control');
            expect(caja.bottom, lessThanOrEqualTo(tamano.height), reason: '$control');
          }

          // Ningún texto de las tarjetas queda cortado con puntos suspensivos.
          for (final texto in [
            'Recordatorios de agenda',
            'Antes de cada visita agendada',
            'Anticipación',
            '5 min',
            '120 min',
          ]) {
            await tester.ensureVisible(find.text(texto));
            final render = tester.renderObject<RenderParagraph>(find.text(texto));
            expect(render.didExceedMaxLines, isFalse, reason: texto);
          }
          final valor = tester.renderObject<RenderParagraph>(_valor);
          expect(valor.didExceedMaxLines, isFalse);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
