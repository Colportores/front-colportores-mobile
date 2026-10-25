// El «›» de una fila de la pestaña «Lista» (#294, HU-UBI-007) abre la misma hoja de la ubicación que
// «Detalle» en la vista previa del mapa (vista 11).

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';
import 'lista_ubicaciones_arnes.dart' show asentarLista;

final _sesion = Sesion(
  usuarioId: 'col-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

final class _Edicion {
  SalidaModificarUbicacion? salida;
  final abiertas = <String>[];

  Future<SalidaModificarUbicacion?> abrir(
    BuildContext context, {
    required String colportorId,
    required String ubicacionId,
    bool ofreceIrALaCobranza = false,
  }) async {
    abiertas.add(ubicacionId);
    return salida;
  }
}

Future<_Edicion> _montar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final edicion = _Edicion();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => DateTime(2026, 10, 6, 15)),
        ...overridesLista(
          repo: RepoListaFalso([
            filaLista('a', calle: 'Rivadavia', numero: '100', metrosAlNorte: 25),
            filaLista('b', calle: 'Mataojo', numero: '2044'),
          ]),
        ),
        ubicacionDeLaHojaProvider.overrideWith(
          (ref, id) => ubicacionGuardada(
            id: id,
            tipo: TipoUbicacion.edificio,
            calle: id == 'a' ? 'Rivadavia' : 'Mataojo',
            numero: id == 'a' ? '100' : '2044',
          ),
        ),
        espaciosDeUbicacionProvider.overrideWith(
          (ref, id) => [espacioDe('e-$id', id == 'a' ? '11' : '22', ubicacionId: id)],
        ),
        abridorEdicionUbicacionProvider.overrideWithValue(edicion.abrir),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  );
  await asentarLista(tester);
  await tester.tap(find.byKey(const Key('inicio_pestana_lista')));
  await asentarLista(tester);
  return edicion;
}

void main() {
  testWidgets('tocar una fila de la Lista abre la hoja de esa ubicación con sus deptos', (
    tester,
  ) async {
    await _montar(tester);

    await tester.tap(find.byKey(const ValueKey('a')));
    await asentarLista(tester);

    expect(find.byKey(ClavesHojaUbicacion.hoja), findsOneWidget);
    expect(find.text('Depto 11'), findsOneWidget);
    expect(find.text('Depto 22'), findsNothing);
  });

  testWidgets(
    'la hoja abierta desde la Lista dice la misma distancia que la fila: «EDIFICIO · A 25 '
    'M», como desde el mapa',
    (tester) async {
      await _montar(tester);

      await tester.tap(find.byKey(const ValueKey('a')));
      await asentarLista(tester);

      expect(find.text('EDIFICIO · A 25${FormatoUbicaciones.espacioDuro}M'), findsOneWidget);
      expect(find.text('EDIFICIO'), findsNothing);
    },
  );

  testWidgets('cerrar la hoja vuelve a la Lista, que sigue en la misma pestaña', (tester) async {
    await _montar(tester);
    await tester.tap(find.byKey(const ValueKey('a')));
    await asentarLista(tester);

    await tester.tap(find.byKey(ClavesHojaUbicacion.cerrar));
    await asentarLista(tester);

    expect(find.byKey(ClavesHojaUbicacion.hoja), findsNothing);
    expect(find.byKey(const Key('pestana_lista')), findsOneWidget);
    expect(find.text('Rivadavia 100'), findsOneWidget);
  });

  testWidgets('doble toque en una fila: una sola hoja', (tester) async {
    await _montar(tester);

    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.tap(find.byKey(const ValueKey('a')), warnIfMissed: false);
    await asentarLista(tester);
    await tester.tap(find.byKey(ClavesHojaUbicacion.cerrar));
    await asentarLista(tester);

    expect(find.byKey(ClavesHojaUbicacion.hoja), findsNothing);
  });

  testWidgets('si desde la edición el aviso de duplicado manda a otra ubicación, se abre la hoja '
      'de esa otra', (tester) async {
    final edicion = await _montar(tester);
    edicion.salida = const UbicacionExistenteElegida('b');
    await tester.tap(find.byKey(const ValueKey('a')));
    await asentarLista(tester);

    edicion.salida = null;
    await tester.tap(find.byKey(ClavesHojaUbicacion.editar));
    await asentarLista(tester);
    expect(edicion.abiertas, ['a']);
    expect(find.text('Depto 11'), findsOneWidget, reason: 'sin guardar, la hoja sigue');

    edicion.salida = const UbicacionExistenteElegida('b');
    await tester.tap(find.byKey(ClavesHojaUbicacion.editar));
    await asentarLista(tester);

    expect(edicion.abiertas, ['a', 'a']);
    expect(find.byKey(ClavesHojaUbicacion.hoja), findsOneWidget);
    expect(find.text('Depto 22'), findsOneWidget);
    expect(find.text('Depto 11'), findsNothing);
    // La distancia era la de «a»: la de «b» no se conoce desde acá y no se inventa.
    expect(find.text('EDIFICIO'), findsOneWidget);
    expect(find.text('EDIFICIO · A 25${FormatoUbicaciones.espacioDuro}M'), findsNothing);
  });
}
