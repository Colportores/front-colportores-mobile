// QA de #415 (vista 24 grupo B): contraste del texto (`textContrastGuideline`) en cada estado, en
// 360×640 y 412×915. Va en su propio archivo con la letra de prueba: con las fuentes reales la guía
// da falsos negativos (lee los píxeles del trazo suavizado).
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notificaciones_arnes.dart';

class _SesionFija extends SesionNotifier {
  @override
  Future<Sesion?> build() async => null;
}

Future<void> _montar(WidgetTester tester, Telefono t, Size tam) async {
  fijarTamano(tester, tamano: tam);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [...t.overrides, sesionProvider.overrideWith(_SesionFija.new)],
      child: MaterialApp(theme: temaClaro(), home: const NotificacionesPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final (nombreTam, tam) in [
    ('360×640', const Size(360, 640)),
    ('412×915', const Size(412, 915)),
  ]) {
    final estados = <(String, Telefono Function(), Future<void> Function(WidgetTester, Telefono)?)>[
      ('24B·01 preferencias', () => Telefono(estado: EstadoSistemaNotificaciones.activadas), null),
      (
        '24B·02 recordatorios apagados',
        () =>
            Telefono(estado: EstadoSistemaNotificaciones.activadas)
              ..preferencias.preferencias = const PreferenciasRecordatorios(activados: false),
        null,
      ),
      ('24B·04 permiso apagado', Telefono.new, null),
      (
        '24B·06 error al guardar',
        () =>
            Telefono(estado: EstadoSistemaNotificaciones.activadas)
              ..preferencias.fallaAlGuardar = true,
        (tester, t) async {
          await tester.tap(find.byKey(const Key('pref_recordatorios_interruptor')));
          await tester.pumpAndSettle();
        },
      ),
      (
        'error al leer',
        () =>
            Telefono(estado: EstadoSistemaNotificaciones.activadas)
              ..preferencias.fallaAlLeer = true,
        null,
      ),
      ('permiso bloqueado', () => Telefono()..recuerdo.pedido = PedidoNotificaciones.sistema, null),
    ];
    for (final (nombre, armar, accion) in estados) {
      testWidgets('$nombre · $nombreTam: contraste del texto AA', (tester) async {
        final t = armar();
        await _montar(tester, t, tam);
        if (accion != null) await accion(tester, t);

        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    }
  }
}
