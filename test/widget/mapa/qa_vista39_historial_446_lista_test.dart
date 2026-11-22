// QA del Historial de la hoja de la casa (vista 39, C·03 y C·04, #446, PR #677) desde la hoja modal de la
// Lista de ubicaciones: la hoja es una ruta modal, el detalle de la visita se apila encima y al cerrarlo
// la hoja sigue arriba, en Historial. Con las fuentes reales, en 360×640 y 412×915, con letra ×1 y ×2.
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/historial_de_la_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_detalle_de_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/qa_vista39_446_arnes.dart';
import 'lista_ubicaciones_arnes.dart';

void main() {
  Future<Montaje446> abrirDesdeLaLista(
    WidgetTester tester, {
    required Size tamano,
    required double escala,
    Object? Function(ContextoDeVentaDeLaCasa)? verVenta,
  }) async {
    await cargarFuentes205(tester);
    final m = Montaje446(HistorialPorLectura446((_) => Stream.value(eventosC03())));
    await montarLista(
      tester,
      repo: RepoListaFalso([
        filaLista('a', calle: 'Av. Italia', numero: '1234', metrosAlNorte: 40),
      ]),
      escala: escala,
      tamano: tamano,
      lecturaContexto: (_) =>
          Stream.value(const ContextoDeLaCasa(espacioId: 'esp-1', personas: [])),
      masOverrides: [
        historialDeLaCasaFuenteProvider.overrideWithValue(m.fuente),
        relojPersonaProvider.overrideWithValue(() => ahora446),
        verVentaDesdeLaCasaProvider.overrideWithValue(
          verVenta ??
              (v) {
                m.ventasAbiertas.add(v);
                return true;
              },
        ),
        pestanaHistorialDeLaCasaProvider.overrideWithValue(
          (context, c) => PestanaHistorialDeLaCasa(espacioId: c.espacioId, direccion: c.direccion),
        ),
      ],
    );
    await tester.tap(find.text('Av. Italia 1234'));
    await asentarLista(tester);
    await tester.tap(find.byKey(ClavesHojaCasa.asaDeLaLista));
    await asentarLista(tester);
    await tester.ensureVisible(find.byKey(ClavesHojaCasa.pestana('historial')));
    await tester.tap(find.byKey(ClavesHojaCasa.pestana('historial')));
    await asentar446(tester);
    return m;
  }

  for (final tamano in const [t360x640, t412x915]) {
    for (final escala in const [1.0, 2.0]) {
      final donde = '${tamano.width.toInt()}×${tamano.height.toInt()} con letra ×$escala';

      testWidgets(
        'dado el Historial en la hoja de la Lista a $donde, se ven las filas sin desbordar',
        (tester) async {
          await abrirDesdeLaLista(tester, tamano: tamano, escala: escala);

          expect(find.byType(ListaUbicacionesPage), findsOneWidget);
          expect(find.byKey(ClavesHistorialDeLaCasa.fila('ven-1')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capturar446(tester, 'lista_${sufijo446(tamano, escala)}');
        },
      );

      testWidgets(
        'dado el Historial en la hoja de la Lista a $donde, el detalle se apila, «Ver la venta» abre y la hoja sigue en Historial',
        (tester) async {
          final m = await abrirDesdeLaLista(tester, tamano: tamano, escala: escala);

          await tocarFila446(tester, 'ven-1');
          expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget);
          await capturar446(tester, 'lista_detalle_${sufijo446(tamano, escala)}');
          expect(tester.takeException(), isNull);

          await tocarEnLaHoja446(tester, ClavesDetalleDeVisita.verLaVenta);
          expect(m.ventasAbiertas.map((v) => v.ventaId), ['ven-1']);
          expect(find.byKey(ClavesDetalleDeVisita.hoja), findsNothing);
          expect(find.byKey(ClavesHistorialDeLaCasa.pestana), findsOneWidget);
          expect(find.byKey(ClavesHistorialDeLaCasa.fila('vis-2')), findsOneWidget);
        },
      );

      testWidgets(
        'dado que abrir la venta falla desde la hoja de la Lista a $donde, el aviso queda en la hoja',
        (tester) async {
          await abrirDesdeLaLista(
            tester,
            tamano: tamano,
            escala: escala,
            verVenta: (_) => throw StateError('sin sesión'),
          );
          await tocarFila446(tester, 'ven-1');
          await tocarEnLaHoja446(tester, ClavesDetalleDeVisita.verLaVenta);

          // El aviso existe en la hoja; que se vea a 360×640 con letra ×2 lo prueba el archivo principal.
          expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsOneWidget);
          await capturar446(tester, 'lista_aviso_${sufijo446(tamano, escala)}');
        },
      );
    }
  }

  // QA #446 (bloqueante, arreglado): en la hoja de la Lista a 360×640 con letra ×2 el aviso de «No
  // pudimos abrir la venta» quedaba fuera de la parte visible de la hoja; ahora la hoja se desplaza.
  testWidgets(
    'dado que «Ver la venta» falla en la hoja de la Lista a 360×640 con letra ×2, el aviso está a la vista',
    (tester) async {
      await abrirDesdeLaLista(
        tester,
        tamano: t360x640,
        escala: 2,
        verVenta: (_) => throw StateError('sin sesión'),
      );
      await tocarFila446(tester, 'ven-1');
      await tocarEnLaHoja446(tester, ClavesDetalleDeVisita.verLaVenta);

      expect(find.byKey(ClavesHistorialDeLaCasa.aviso).hitTestable(), findsOneWidget);
    },
  );
}
