// HU-NOT-002 / issue #453 — el recordatorio tocado llega al enganche de la vista 23 una sola vez.
import 'dart:async';

import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:test/test.dart';

void main() {
  late RecordatoriosEnMemoria recordatorios;
  late List<String> abiertas;

  setUp(() {
    recordatorios = RecordatoriosEnMemoria();
    abiertas = [];
  });

  ProviderContainer armar({void Function(String)? abridor}) {
    final overrides = <Override>[
      recordatoriosProvider.overrideWithValue(recordatorios),
      toquesDeRecordatoriosProvider.overrideWithValue(recordatorios),
      abridorDetalleAgendaProvider.overrideWithValue(abridor ?? abiertas.add),
    ];
    final contenedor = ProviderContainer(overrides: overrides);
    addTearDown(contenedor.dispose);
    return contenedor;
  }

  Future<void> asentar() => Future<void>.delayed(Duration.zero);

  test('dado un recordatorio tocado mientras nadie escuchaba, cuando la pantalla principal lo '
      'mira, abre el detalle una sola vez', () async {
    recordatorios.tocar('ag-1');
    final contenedor = armar();

    final lectura = contenedor.listen(aperturasDesdeRecordatorioProvider, (_, _) {});
    await asentar();

    expect(abiertas, ['ag-1']);
    lectura.close();

    // Otra pantalla principal (otro ingreso): el pendiente ya se entregó.
    contenedor.listen(aperturasDesdeRecordatorioProvider, (_, _) {});
    await asentar();
    expect(abiertas, ['ag-1']);
  });

  test('dado que la pantalla principal ya escucha, cuando se toca un recordatorio, abre el detalle '
      'en el momento, cada vez', () async {
    final contenedor = armar();
    contenedor.listen(aperturasDesdeRecordatorioProvider, (_, _) {});
    await asentar();

    recordatorios.tocar('ag-1');
    recordatorios.tocar('ag-2');
    await asentar();

    expect(abiertas, ['ag-1', 'ag-2']);
  });

  test('dado que la pantalla principal se fue (cierre de sesión), cuando se toca un recordatorio, '
      'queda pendiente para el próximo ingreso', () async {
    final contenedor = armar();
    final lectura = contenedor.listen(aperturasDesdeRecordatorioProvider, (_, _) {});
    await asentar();
    lectura.close();
    await asentar();

    recordatorios.tocar('ag-3');
    await asentar();
    expect(abiertas, isEmpty);

    contenedor.listen(aperturasDesdeRecordatorioProvider, (_, _) {});
    await asentar();
    expect(abiertas, ['ag-3']);
  });

  test(
    'dado que no se tocó ningún recordatorio, cuando la pantalla principal lo mira, no abre nada',
    () async {
      final contenedor = armar();

      contenedor.listen(aperturasDesdeRecordatorioProvider, (_, _) {});
      await asentar();

      expect(abiertas, isEmpty);
    },
  );

  test(
    'dado que abrir el detalle falla, cuando se toca un recordatorio, no se rompe y el siguiente '
    'toque anda',
    () async {
      final llamadas = <String>[];
      final contenedor = armar(
        abridor: (id) {
          llamadas.add(id);
          if (id == 'ag-1') throw StateError('no hay navegador');
        },
      );
      contenedor.listen(aperturasDesdeRecordatorioProvider, (_, _) {});
      await asentar();

      recordatorios.tocar('ag-1');
      recordatorios.tocar('ag-2');
      await asentar();

      expect(llamadas, ['ag-1', 'ag-2']);
    },
  );

  test(
    'dado el enganche sin reemplazar, cuando se toca un recordatorio, no hace nada (todavía no hay '
    'detalle de la visita)',
    () async {
      final contenedor = ProviderContainer(
        overrides: [
          recordatoriosProvider.overrideWithValue(recordatorios),
          toquesDeRecordatoriosProvider.overrideWithValue(recordatorios),
        ],
      );
      addTearDown(contenedor.dispose);
      contenedor.listen(aperturasDesdeRecordatorioProvider, (_, _) {});
      await asentar();

      recordatorios.tocar('ag-1');
      await asentar();

      expect(recordatorios.programados, isEmpty);
    },
  );

  test('dado el default de los providers, cuando se piden, son el mismo objeto en memoria', () {
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);

    expect(contenedor.read(recordatoriosProvider), isA<RecordatoriosEnMemoria>());
    expect(
      contenedor.read(recordatoriosProvider),
      same(contenedor.read(toquesDeRecordatoriosProvider)),
    );
  });
}
