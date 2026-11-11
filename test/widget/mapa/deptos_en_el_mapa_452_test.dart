// La hoja del edificio en la pestaña Mapa (vista 39, #452): el atrás del teléfono va de a un paso (del
// depto a la lista de deptos y recién después cierra la hoja) y un edificio recién registrado arranca
// sumando sus deptos (N·04); la próxima vez que se toca, es uno más (C·09).
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resumen_del_depto.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart'
    show UbicacionCreada;
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/deptos_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';

final _edificio = filaLista(
  'ed-1',
  tipo: TipoUbicacion.edificio,
  calle: 'Grecia',
  numero: '3313',
  metrosAlNorte: 35,
  espacios: 2,
  estado: EstadoCasa.cobranzaPendiente,
);

final _deptos = [
  espacioDe('d-1a', '1A', piso: '1', ubicacionId: 'ed-1'),
  espacioDe('d-3b', '3B', piso: '3', ubicacionId: 'ed-1', orden: 1),
];

String _titulo(WidgetTester tester) => tester.widget<Text>(find.byKey(ClavesHojaCasa.titulo)).data!;

Future<MontajeMapaUbicaciones> _montar(WidgetTester tester) => montarMapaUbicaciones(
  tester,
  repo: RepoListaFalso([_edificio]),
  otrosOverrides: [
    espaciosDeUbicacionProvider.overrideWith((ref, ubicacionId) async => _deptos),
    resumenDeLosDeptosProvider.overrideWith(
      (ref, clave) => Stream.value({'d-1a': ResumenDelDepto(), 'd-3b': ResumenDelDepto()}),
    ),
  ],
);

void main() {
  testWidgets('tocar el edificio abre sus deptos (C·09); un depto lo abre como una casa (C·10); el '
      'atrás vuelve a la lista de deptos y, otra vez, cierra la hoja', (tester) async {
    final m = await _montar(tester);
    m.mapa.tocarPunto('ed-1');
    await asentarLista(tester);

    expect(find.byType(DeptosDeLaCasa), findsOneWidget);
    expect(_titulo(tester), 'Grecia 3313');

    final fila = find.byKey(ClavesDeptosDeLaCasa.fila('d-3b'));
    await tester.ensureVisible(fila);
    await tester.pump();
    await tester.tap(fila);
    await asentarLista(tester);
    expect(_titulo(tester), 'Grecia 3313 · Depto 3B');

    await tester.binding.handlePopRoute();
    await asentarLista(tester);
    expect(find.byType(HojaCasa), findsOneWidget, reason: 'el atrás va de a un paso');
    expect(_titulo(tester), 'Grecia 3313');
    expect(seleccionadaId(tester), 'ed-1');

    await tester.binding.handlePopRoute();
    await asentarLista(tester);
    expect(find.byType(HojaCasa), findsNothing);
    expect(seleccionadaId(tester), isNull);
  });

  testWidgets('un edificio recién registrado arranca en N·04; cerrado y vuelto a tocar, es uno más '
      '(C·09)', (tester) async {
    final m = await _montar(tester);
    m.salidaAlta = UbicacionCreada(_edificio.ubicacion);

    await tester.tap(botonNueva);
    await asentarLista(tester);
    expect(_titulo(tester), 'Edificio en Grecia 3313');
    expect(find.byKey(ClavesDeptosDeLaCasa.seguir), findsOneWidget);

    await tester.tap(cerrarVistaPrevia);
    await asentarLista(tester);
    m.mapa.tocarPunto('ed-1');
    await asentarLista(tester);

    expect(_titulo(tester), 'Grecia 3313');
    expect(find.byKey(ClavesDeptosDeLaCasa.seguir), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
