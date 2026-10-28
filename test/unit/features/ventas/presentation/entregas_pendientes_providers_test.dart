// El cableado de la entrega diferida (HU-VEN-003, #433): los casos de uso salen del contenedor con el
// reloj y el generador de ids de las ventas, y las entregas pendientes llegan como un stream que se
// puede dejar de mirar y volver a mirar.
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_diferida.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/diferir_entrega_use_case.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/entrega_falsos.dart';

void main() {
  late EntornoDeEntrega e;
  late ProviderContainer c;
  final sabado = DateTime.utc(2026, 10, 31, 13);

  setUp(() {
    e = EntornoDeEntrega();
    c = ProviderContainer(overrides: e.overrides);
    addTearDown(c.dispose);
  });

  const pendiente = EntregaPendiente(
    ventaId: 'v-1',
    espacioPersonaId: 'ep-1',
    lineas: [LineaPendiente(entregaId: 'e-1', productoId: 'p-1', cantidad: 2)],
  );

  test('«Diferir» sale del contenedor con el reloj de las ventas y llega al repositorio', () async {
    e.entregas.respuestaDeDiferir = EntregaDiferida(
      entregas: [entregaDe('e-1', 'p-1', pendiente: true, fechaPrevista: sabado)],
      cita: agendaDe(
        'c-1',
        tipo: TipoAgenda.entrega,
        ventaId: 'v-1',
        entregaId: 'e-1',
        fecha: sabado,
      ),
    );

    final r = await c.read(diferirEntregaUseCaseProvider)(
      DiferirEntregaParams(
        ventaId: 'v-1',
        colportorId: 'col-1',
        fechaPrevista: sabado,
        productos: const [ComponenteVendido(productoId: 'p-1')],
      ),
    );

    expect(r.isRight(), isTrue);
    expect(e.entregas.diferidas.single.filasNuevas.single.id, startsWith('e-'));
  });

  test(
    'las pendientes de todos y las de una persona llegan al mirar, y al volver a mirar',
    () async {
      final todas = <List<EntregaPendiente>>[];
      final deUna = <List<EntregaPendiente>>[];
      final s1 = c.listen(entregasPendientesProvider, (_, n) => n.whenData(todas.add));
      final s2 = c.listen(entregasPendientesDeProvider('ep-1'), (_, n) => n.whenData(deUna.add));

      e.entregas.emitirPendientes(const [pendiente]);
      await pumpEventQueue();
      expect(todas.last.single.ventaId, 'v-1');
      expect(deUna.last.single.ventaId, 'v-1');

      // Salir de la pantalla y reentrar: se vuelve a suscribir sin perder lo que llegue después.
      s1.close();
      s2.close();
      final de = <List<EntregaPendiente>>[];
      c.listen(entregasPendientesProvider, (_, n) => n.whenData(de.add));
      e.entregas.emitirPendientes(const []);
      await pumpEventQueue();
      expect(de.last, isEmpty);
    },
  );

  test('una lista larga se entrega entera y en orden', () async {
    final largas = <List<EntregaPendiente>>[];
    c.listen(entregasPendientesProvider, (_, n) => n.whenData(largas.add));

    e.entregas.emitirPendientes([
      for (var i = 0; i < 300; i++)
        EntregaPendiente(
          ventaId: 'v-$i',
          espacioPersonaId: 'ep-1',
          lineas: [LineaPendiente(entregaId: 'e-$i', productoId: 'p-1', cantidad: 1)],
        ),
    ]);
    await pumpEventQueue();

    expect(largas.last, hasLength(300));
    expect(largas.last.first.ventaId, 'v-0');
    expect(largas.last.last.ventaId, 'v-299');
  });
}
