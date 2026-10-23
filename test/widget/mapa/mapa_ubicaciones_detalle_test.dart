// «Detalle» de la vista previa del mapa (canvas 06C·04, #294 y #298): abre la hoja de la ubicación
// (vista 11, HU-UBI-007) y, con lo que devuelve la edición (vista 07), el mapa selecciona la
// ubicación editada (07·03), deja de mostrar la que se dio de baja (09) o elige la otra del aviso de
// duplicado. Los otros botones del canvas («Registrar visita», «Agendar») son de #151.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';
import 'hoja_espacios_arnes.dart' show hojaUbicacion;
import 'mapa_ubicaciones_arnes.dart';

final class _Edicion {
  final abiertas = <String>[];
  SalidaModificarUbicacion? salida;
  Completer<SalidaModificarUbicacion?>? espera;

  Future<SalidaModificarUbicacion?> abrir(
    BuildContext context, {
    required String colportorId,
    required String ubicacionId,
    bool ofreceIrALaCobranza = false,
  }) async {
    abiertas.add(ubicacionId);
    return espera != null ? espera!.future : salida;
  }
}

List<Override> _extras(_Edicion edicion) => [
  ubicacionDeLaHojaProvider.overrideWith(
    (ref, id) => ubicacionGuardada(
      id: id,
      tipo: TipoUbicacion.edificio,
      calle: 'Av. Italia',
      numero: id == 'a' ? '1234' : '1250',
    ),
  ),
  espaciosDeUbicacionProvider.overrideWith(
    (ref, id) => [espacioDe('e-1', '101', piso: '1', ubicacionId: id)],
  ),
  abridorEdicionUbicacionProvider.overrideWithValue(edicion.abrir),
];

final _detalle = find.byKey(ClavesMapaUbicaciones.detalle);

void main() {
  late _Edicion edicion;
  setUp(() => edicion = _Edicion());

  Future<MontajeMapaUbicaciones> montar(WidgetTester tester) async {
    final m = await montarMapaUbicaciones(
      tester,
      repo: RepoListaFalso([
        filaLista('a', calle: 'Av. Italia', numero: '1234', metrosAlNorte: 40, espacios: 2),
        filaLista('b', calle: 'Av. Italia', numero: '1250', metrosAlNorte: 55),
      ]),
      extras: _extras(edicion),
    );
    m.mapa.tocarPunto('a');
    await asentarLista(tester);
    return m;
  }

  testWidgets('la vista previa tiene «Detalle» y todavía no «Registrar visita» ni «Agendar» '
      '(#151)', (tester) async {
    await montar(tester);

    expect(vistaPrevia, findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Detalle'), findsOneWidget);
    expect(tester.getSize(_detalle).height, greaterThanOrEqualTo(48));
    expect(find.text('Registrar visita'), findsNothing);
    expect(find.text('Agendar'), findsNothing);
  });

  testWidgets('«Detalle» abre la hoja de esa ubicación, con la distancia del mapa', (tester) async {
    await montar(tester);

    await tester.tap(_detalle);
    await asentarLista(tester);

    expect(hojaUbicacion, findsOneWidget);
    expect(find.text('Av. Italia 1234'), findsWidgets);
    expect(find.text('EDIFICIO · A 40 M'), findsOneWidget);
    expect(find.text('Depto 101'), findsOneWidget);
  });

  testWidgets('cerrar la hoja vuelve a la vista previa de la misma ubicación', (tester) async {
    final m = await montar(tester);
    await tester.tap(_detalle);
    await asentarLista(tester);

    await tester.tap(find.byKey(ClavesHojaUbicacion.cerrar));
    await asentarLista(tester);

    expect(hojaUbicacion, findsNothing);
    expect(vistaPrevia, findsOneWidget);
    expect(seleccionadaId(tester), 'a');
    expect(punto(m.mapa, 'a').etiqueta, isNotNull);
  });

  testWidgets('doble toque en «Detalle»: una sola hoja', (tester) async {
    await montar(tester);

    await tester.tap(_detalle);
    await tester.tap(_detalle, warnIfMissed: false);
    await asentarLista(tester);

    expect(hojaUbicacion, findsOneWidget);
    await tester.tap(find.byKey(ClavesHojaUbicacion.cerrar));
    await asentarLista(tester);
    expect(hojaUbicacion, findsNothing, reason: 'no quedó una segunda hoja debajo');
  });

  testWidgets('volver atrás y reentrar: «Detalle» abre la hoja otra vez', (tester) async {
    await montar(tester);
    await tester.tap(_detalle);
    await asentarLista(tester);
    await tester.tap(find.byKey(ClavesHojaUbicacion.cerrar));
    await asentarLista(tester);

    await tester.tap(_detalle);
    await asentarLista(tester);

    expect(hojaUbicacion, findsOneWidget);
  });

  group('lo que devuelve la edición de la ubicación (#298)', () {
    testWidgets('«Editar edificio» sin guardar deja la hoja abierta y el mapa como estaba', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(_detalle);
      await asentarLista(tester);

      await tester.tap(find.byKey(ClavesHojaUbicacion.editar));
      await asentarLista(tester);

      expect(edicion.abiertas, ['a']);
      expect(hojaUbicacion, findsOneWidget);
      expect(seleccionadaId(tester), 'a');
    });

    testWidgets('si se guardó, la hoja se cierra y la ubicación editada queda seleccionada y '
        'centrada (07·03)', (tester) async {
      final m = await montar(tester);
      await tester.tap(find.byKey(ClavesMapaUbicaciones.cerrarVistaPrevia));
      await asentarLista(tester);
      m.mapa.tocarPunto('b');
      await asentarLista(tester);
      edicion.salida = UbicacionEditada(
        ubicacionGuardada(id: 'b', calle: 'Av. Italia', numero: '1250'),
      );
      await tester.tap(_detalle);
      await asentarLista(tester);

      await tester.tap(find.byKey(ClavesHojaUbicacion.editar));
      await asentarLista(tester);

      expect(hojaUbicacion, findsNothing);
      expect(seleccionadaId(tester), 'b');
      expect(vistaPrevia, findsOneWidget);
    });

    testWidgets('si se dio de baja, la hoja se cierra y el mapa deja de seleccionarla (09)', (
      tester,
    ) async {
      await montar(tester);
      edicion.salida = UbicacionBajaRealizada(ubicacionGuardada(id: 'a'));
      await tester.tap(_detalle);
      await asentarLista(tester);

      await tester.tap(find.byKey(ClavesHojaUbicacion.editar));
      await asentarLista(tester);

      expect(hojaUbicacion, findsNothing);
      expect(seleccionadaId(tester), isNull);
      expect(vistaPrevia, findsNothing);
    });

    testWidgets('si el aviso de duplicado mandó a otra ubicación, el mapa elige esa otra', (
      tester,
    ) async {
      await montar(tester);
      edicion.salida = const UbicacionExistenteElegida('b');
      await tester.tap(_detalle);
      await asentarLista(tester);

      await tester.tap(find.byKey(ClavesHojaUbicacion.editar));
      await asentarLista(tester);

      expect(hojaUbicacion, findsNothing);
      expect(seleccionadaId(tester), 'b');
    });

    testWidgets('si la elegida no es del colportor, el mapa lo dice y no deja nada seleccionado', (
      tester,
    ) async {
      await montar(tester);
      edicion.salida = const UbicacionExistenteElegida('de-otro');
      await tester.tap(_detalle);
      await asentarLista(tester);

      await tester.tap(find.byKey(ClavesHojaUbicacion.editar));
      await asentarLista(tester);

      expect(seleccionadaId(tester), isNull);
      expect(find.textContaining('otro colportor'), findsOneWidget);
    });
  });
}
