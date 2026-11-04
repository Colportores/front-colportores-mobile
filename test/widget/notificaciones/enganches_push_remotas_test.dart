// HU-NOT-003 (#187) — R-NO05: tocar el aviso de una push lo marca como leído y lleva a su destino,
// con los mismos textos que el centro de notificaciones.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/enganches_push_remotas.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/centro_notificaciones_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/push_remotas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/historial_notificaciones_falsos.dart';

Notificacion _pedido({DestinoNotificacion? destino}) => Notificacion(
  id: 'push-1',
  tipo: TipoNotificacion.pedidoAutorizado,
  titulo: 'Tu pedido fue autorizado',
  destino: destino,
  recibidaEn: ahoraDelCentro,
);

void main() {
  late CentroArnes arnes;
  late GlobalKey<NavigatorState> navegador;

  setUp(() {
    arnes = CentroArnes(avisos: [_pedido(destino: const DestinoAgenda('age-1'))]);
    navegador = GlobalKey<NavigatorState>();
  });

  Future<ProviderContainer> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...arnes.overrides, ...EnganchesPushRemotas.enganches(navegador)],
        child: MaterialApp(
          navigatorKey: navegador,
          theme: temaClaro(),
          home: const Scaffold(body: Text('Hoy')),
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.text('Hoy')));
  }

  Future<void> tocar(WidgetTester tester, ProviderContainer c, Notificacion aviso) async {
    await c.read(abridorAvisoPushProvider)(aviso);
    await tester.pump();
  }

  testWidgets('dado un aviso con destino que existe, cuando se toca, entonces queda leído y se '
      'abre el destino', (tester) async {
    final c = await montar(tester);

    await tocar(tester, c, _pedido(destino: const DestinoAgenda('age-1')));

    expect(arnes.historial.marcadas, ['push-1']);
    expect(arnes.abridor.abiertos, [const DestinoAgenda('age-1')]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('dado un aviso sin destino (el pedido autorizado no tiene pantalla), cuando se toca, '
      'entonces queda leído y se abre el centro de notificaciones con ese aviso', (tester) async {
    final c = await montar(tester);

    await tocar(tester, c, _pedido());
    await tester.pumpAndSettle();

    expect(arnes.historial.marcadas, ['push-1']);
    expect(arnes.abridor.abiertos, isEmpty);
    expect(find.byType(CentroNotificacionesPage), findsOneWidget);
    expect(find.text('Tu pedido fue autorizado'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final tipo in [
    TipoNotificacion.ticketValidado,
    TipoNotificacion.ticketRechazado,
    TipoNotificacion.asignacionCampania,
    TipoNotificacion.cuotaPendiente,
    TipoNotificacion.agendaManana,
  ]) {
    testWidgets(
      'dado un aviso de ${tipo.codigo} (sin pantalla de detalle), cuando se toca, entonces '
      'abre el centro',
      (tester) async {
        final c = await montar(tester);

        await tocar(
          tester,
          c,
          Notificacion(id: 'push-1', tipo: tipo, titulo: 'Un aviso', recibidaEn: ahoraDelCentro),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CentroNotificacionesPage), findsOneWidget);
      },
    );
  }

  testWidgets(
    'dado que el centro ya está arriba, cuando se toca otro aviso sin destino, entonces no '
    'se abre un segundo centro',
    (tester) async {
      final c = await montar(tester);
      await tocar(tester, c, _pedido());
      await tester.pumpAndSettle();

      await tocar(tester, c, _pedido());
      await tester.pumpAndSettle();

      expect(find.byType(CentroNotificacionesPage), findsOneWidget);
      navegador.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(CentroNotificacionesPage), findsNothing);
      expect(find.text('Hoy'), findsOneWidget);
    },
  );

  testWidgets('dado un destino que ya no existe (24C·07), cuando se toca, entonces no se abre y se '
      'explica', (tester) async {
    arnes.destinos.inexistentes.add(const DestinoAgenda('age-1'));
    final c = await montar(tester);

    await tocar(tester, c, _pedido(destino: const DestinoAgenda('age-1')));

    expect(arnes.abridor.abiertos, isEmpty);
    expect(find.text('Esa agenda ya no está: se canceló o se borró.'), findsOneWidget);
  });

  testWidgets(
    'dado que marcar como leído falla, cuando se toca, entonces el destino se abre igual',
    (tester) async {
      arnes.historial.fallaAlMarcar = true;
      final c = await montar(tester);

      await tocar(tester, c, _pedido(destino: const DestinoAgenda('age-1')));

      expect(arnes.abridor.abiertos, [const DestinoAgenda('age-1')]);
    },
  );

  testWidgets('dado que no se puede saber si el destino existe, cuando se toca, entonces se dice '
      'qué hacer', (tester) async {
    arnes.destinos.falla = true;
    final c = await montar(tester);

    await tocar(tester, c, _pedido(destino: const DestinoAgenda('age-1')));

    expect(arnes.abridor.abiertos, isEmpty);
    expect(find.text('No pudimos abrir ese aviso. Probá de nuevo.'), findsOneWidget);
  });

  testWidgets('dado que abrir el destino lanza, cuando se toca, entonces no tira la app y se dice '
      'qué hacer', (tester) async {
    arnes.abridor.falla = StateError('sin pantalla');
    final c = await montar(tester);

    await tocar(tester, c, _pedido(destino: const DestinoAgenda('age-1')));

    expect(tester.takeException(), isNull);
    expect(find.text('No pudimos abrir ese aviso. Probá de nuevo.'), findsOneWidget);
  });

  testWidgets('dado dos toques seguidos, entonces el segundo aviso no deja el primer mensaje '
      'apilado', (tester) async {
    arnes.destinos.inexistentes.add(const DestinoAgenda('age-1'));
    final c = await montar(tester);

    await tocar(tester, c, _pedido(destino: const DestinoAgenda('age-1')));
    await tocar(tester, c, _pedido(destino: const DestinoAgenda('age-1')));

    expect(find.text('Esa agenda ya no está: se canceló o se borró.'), findsOneWidget);
  });
}
