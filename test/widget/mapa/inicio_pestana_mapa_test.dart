// HU-UBI-003: la pestaña «Mapa» de la pantalla principal es el mapa de ubicaciones, no se arma ni
// pide el GPS hasta que el colportor la abre, y no se pierde lo que eligió al cambiar de pestaña.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/mapa_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
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

Future<void> _montar(
  WidgetTester tester, {
  required RepoListaFalso repo,
  GpsFalso? gps,
  FabricaMapaFalsa? mapa,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => DateTime(2026, 10, 6, 15)),
        ...overridesLista(repo: repo, gps: gps),
        ...overridesPestanaMapa(mapa),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  );
  await asentarLista(tester);
}

Future<void> _irA(WidgetTester tester, String pestana) async {
  await tester.tap(find.byKey(Key('inicio_pestana_$pestana')));
  await asentarLista(tester);
}

void main() {
  testWidgets('dado que abre «Mapa», entonces ve las ubicaciones del colportor de la sesión', (
    tester,
  ) async {
    final repo = RepoListaFalso([filaLista('a', calle: 'Rivadavia', numero: '100')]);
    final mapa = FabricaMapaFalsa();
    await _montar(tester, repo: repo, mapa: mapa);

    await _irA(tester, 'mapa');

    expect(find.byKey(const Key('pestana_mapa')), findsOneWidget);
    expect(find.byType(MapaUbicacionesPage), findsOneWidget);
    expect(find.text('Esta sección llega pronto.'), findsNothing);
    expect(find.byKey(ClavesMapaUbicaciones.hoja), findsOneWidget);
    expect(mapa.config!.puntos.map((p) => p.id), contains('a'));
    expect(repo.pedidos.first.colportorId, 'col-1');
  });

  testWidgets('dado que arranca en «Hoy», entonces el mapa no se arma ni pide el GPS hasta abrir '
      '«Mapa», y al volver a abrirlo refresca el GPS', (tester) async {
    final gps = GpsFalso(Right(lecturaGps(8)));
    final repo = RepoListaFalso([filaLista('a')]);
    final mapa = FabricaMapaFalsa();
    await _montar(tester, repo: repo, gps: gps, mapa: mapa);
    expect(gps.lecturas, 0);
    expect(mapa.armada, isFalse);
    // La pestaña «Lista» ya leyó la base; la del mapa no (cada una tiene su suscripción).
    final lecturasDeLaLista = repo.suscripciones;

    await _irA(tester, 'mapa');
    expect(gps.lecturas, 1);
    expect(mapa.armada, isTrue);
    expect(repo.suscripciones, greaterThan(lecturasDeLaLista));

    await _irA(tester, 'hoy');
    await _irA(tester, 'mapa');

    expect(gps.lecturas, 2);
  });

  testWidgets('dado que eligió una ubicación y cambia de pestaña, entonces al volver sigue elegida '
      'y la hoja a la misma altura', (tester) async {
    final mapa = FabricaMapaFalsa();
    await _montar(tester, repo: RepoListaFalso([filaLista('a', metrosAlNorte: 30)]), mapa: mapa);
    await _irA(tester, 'mapa');
    mapa.tocarPunto('a');
    await asentarLista(tester);
    expect(find.byKey(ClavesMapaUbicaciones.vistaPrevia), findsOneWidget);
    final alto = tester.getSize(find.byKey(ClavesMapaUbicaciones.hoja)).height;

    await _irA(tester, 'lista');
    await _irA(tester, 'mapa');

    expect(find.byKey(ClavesMapaUbicaciones.vistaPrevia), findsOneWidget);
    expect(tester.getSize(find.byKey(ClavesMapaUbicaciones.hoja)).height, alto);
  });

  testWidgets('dado que está en «Mapa», entonces «Lista» sigue siendo la lista y no el mapa', (
    tester,
  ) async {
    await _montar(tester, repo: RepoListaFalso([filaLista('a')]));
    await _irA(tester, 'mapa');

    await _irA(tester, 'lista');

    expect(find.byKey(const Key('pestana_lista')), findsOneWidget);
  });
  group('el atrás del teléfono con la vista previa abierta (decisión del 07/10 en el #294)', () {
    int pestanaElegida(WidgetTester tester) =>
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

    Future<FabricaMapaFalsa> abrirConVistaPrevia(WidgetTester tester) async {
      final mapa = FabricaMapaFalsa();
      await _montar(
        tester,
        repo: RepoListaFalso([
          filaLista('a', metrosAlNorte: 30),
          filaLista('b', metrosAlNorte: 60),
        ]),
        mapa: mapa,
      );
      await _irA(tester, 'mapa');
      mapa.tocarPunto('a');
      await asentarLista(tester);
      expect(find.byKey(ClavesMapaUbicaciones.vistaPrevia), findsOneWidget);
      return mapa;
    }

    testWidgets('dado que mira la vista previa de una ubicación, cuando toca atrás, entonces se '
        'cierra como con la ✕: sigue en «Mapa» y la hoja queda a la misma altura', (tester) async {
      await abrirConVistaPrevia(tester);
      final indice = pestanaElegida(tester);
      final alto = tester.getSize(find.byKey(ClavesMapaUbicaciones.hoja)).height;

      final atendido = await tester.binding.handlePopRoute();
      await asentarLista(tester);

      expect(atendido, isTrue);
      expect(find.byKey(ClavesMapaUbicaciones.vistaPrevia), findsNothing);
      expect(find.byKey(ClavesMapaUbicaciones.fila('a')), findsOneWidget);
      expect(pestanaElegida(tester), indice, reason: 'no vuelve a «Hoy» de golpe');
      expect(tester.getSize(find.byKey(ClavesMapaUbicaciones.hoja)).height, alto);
    });

    testWidgets('dado que ya cerró la vista previa con atrás, cuando toca atrás otra vez, entonces '
        'vuelve a «Hoy» como siempre', (tester) async {
      await abrirConVistaPrevia(tester);

      await tester.binding.handlePopRoute();
      await asentarLista(tester);
      await tester.binding.handlePopRoute();
      await asentarLista(tester);

      expect(pestanaElegida(tester), 0);
    });

    testWidgets('dado que eligió otra ubicación después de cerrarla con atrás, entonces el atrás '
        'vuelve a cerrar esa', (tester) async {
      final mapa = await abrirConVistaPrevia(tester);
      await tester.binding.handlePopRoute();
      await asentarLista(tester);
      final indice = pestanaElegida(tester);

      mapa.tocarPunto('b');
      await asentarLista(tester);
      expect(find.byKey(ClavesMapaUbicaciones.vistaPrevia), findsOneWidget);
      await tester.binding.handlePopRoute();
      await asentarLista(tester);

      expect(find.byKey(ClavesMapaUbicaciones.vistaPrevia), findsNothing);
      expect(pestanaElegida(tester), indice);
    });

    testWidgets('dado que dejó la vista previa abierta y está en «Lista», cuando toca atrás, '
        'entonces vuelve a «Hoy» y la vista previa sigue ahí al volver a «Mapa»', (tester) async {
      await abrirConVistaPrevia(tester);
      await _irA(tester, 'lista');

      await tester.binding.handlePopRoute();
      await asentarLista(tester);

      expect(pestanaElegida(tester), 0);
      await _irA(tester, 'mapa');
      expect(find.byKey(ClavesMapaUbicaciones.vistaPrevia), findsOneWidget);
    });

    testWidgets('dado que no eligió nada, cuando toca atrás en «Mapa», entonces vuelve a «Hoy»', (
      tester,
    ) async {
      await _montar(tester, repo: RepoListaFalso([filaLista('a')]), mapa: FabricaMapaFalsa());
      await _irA(tester, 'mapa');

      await tester.binding.handlePopRoute();
      await asentarLista(tester);

      expect(pestanaElegida(tester), 0);
    });
  });
}
