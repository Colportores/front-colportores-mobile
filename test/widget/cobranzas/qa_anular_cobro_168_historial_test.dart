// QA de #168 de punta a punta por la entrada de la hoja de la casa: un cobro de la pestaña Historial
// (vista 39, C·04) abre `DetalleDelCobroPage` (vista 30 B) como lo engancha `main.dart`, se anula, y al
// volver el Historial ya no cuenta ese cobro (la lectura real solo trae los cobros vivos, `CobroValido`).
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart'
    show MedioCobranza, MotivoDeAnulacion;
import 'package:colportores_mobile/features/cobranzas/presentation/pages/detalle_del_cobro_page.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/historial_de_la_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_historial_de_la_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/anular_cobro_arnes.dart';

final _hoy = DateTime.utc(2026, 10, 23, 18);

final _cobro = CobroDeLaCasa(
  id: 'c-1',
  fecha: DateTime.utc(2026, 10, 23, 17, 10),
  montoCentavos: 60000,
  medio: MedioCobranza.efectivo,
  ventaId: 'v-42',
  numeroTalonario: '0042',
);

class _Historial implements HistorialDeLaCasa {
  final controlador = StreamController<List<EventoDeLaCasa>>.broadcast();

  @override
  Stream<List<EventoDeLaCasa>> observar(String espacioId) async* {
    yield [_cobro];
    yield* controlador.stream;
  }
}

void main() {
  testWidgets(
    'tocar el cobro del Historial abre su detalle, anula y al volver el Historial ya no lo trae',
    (tester) async {
      final llave = GlobalKey<NavigatorState>();
      final repo = AnulacionesEnMemoria();
      final historial = _Historial();
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(historial.controlador.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            historialDeLaCasaFuenteProvider.overrideWithValue(historial),
            relojPersonaProvider.overrideWithValue(() => _hoy),
            relojCobroProvider.overrideWithValue(() => _hoy),
            anulacionDeCobroRepositoryProvider.overrideWithValue(repo),
            ticketValidadoDelCobroProvider.overrideWith((ref, id) async => false),
            verVentaDesdeLaCasaProvider.overrideWithValue(null),
            // Igual que `main.dart`.
            verCobroDesdeLaCasaProvider.overrideWithValue(
              (cobranzaId) => DetalleDelCobroPage.abrir(
                llave.currentContext!,
                cobranzaId: cobranzaId,
                colportorId: 'col-1',
              ),
            ),
          ],
          child: MaterialApp(
            navigatorKey: llave,
            theme: temaClaro(),
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: PestanaHistorialDeLaCasa(espacioId: 'esp-1', direccion: 'Grecia 3310'),
              ),
            ),
          ),
        ),
      );
      await asentarAgendar(tester);
      final filaDelCobro = find.byWidgetPredicate((w) => w is FilaDelHistorialDeLaCasa);
      expect(filaDelCobro, findsOneWidget);

      await tester.tap(filaDelCobro);
      await asentarAgendar(tester);
      expect(paginaDetalle, findsOneWidget);
      expect(textoDe('detalle_cobro_estado'), 'Registrado');

      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Monto equivocado');
      expect(repo.recibidos, hasLength(1));

      // La base sigue en vivo: el Historial emite sin el cobro anulado.
      historial.controlador.add(const []);
      await tocar(tester, find.byKey(const Key('venta_atras')));
      await asentarAgendar(tester);

      expect(paginaDetalle, findsNothing);
      expect(find.byWidgetPredicate((w) => w is FilaDelHistorialDeLaCasa), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
