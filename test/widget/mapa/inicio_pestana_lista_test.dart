// HU-UBI-002: la pestaña «Lista» de la pantalla principal es la lista de ubicaciones, y el GPS
// se pide cuando el colportor la abre, no al arrancar la app.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
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

Future<void> _montar(WidgetTester tester, {required RepoListaFalso repo, GpsFalso? gps}) async {
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
      ],
      child: MaterialApp(
        theme: temaClaro(),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  );
  await asentarLista(tester);
}

void main() {
  testWidgets('dado que abre «Lista», entonces ve las ubicaciones del colportor de la sesión', (
    tester,
  ) async {
    final repo = RepoListaFalso([filaLista('a', calle: 'Rivadavia', numero: '100')]);
    await _montar(tester, repo: repo);

    await tester.tap(find.byKey(const Key('inicio_pestana_lista')));
    await asentarLista(tester);

    expect(find.byKey(const Key('pestana_lista')), findsOneWidget);
    expect(find.text('Rivadavia 100'), findsOneWidget);
    expect(find.text('Esta sección llega pronto.'), findsNothing);
    expect(repo.pedidos.first.colportorId, 'col-1');
  });

  testWidgets('dado que arranca en «Hoy», entonces no pide el GPS hasta abrir «Lista», y al '
      'volver a abrirla lo refresca', (tester) async {
    final gps = GpsFalso(Right(lecturaGps(8)));
    await _montar(tester, repo: RepoListaFalso([filaLista('a')]), gps: gps);
    expect(gps.lecturas, 0);

    await tester.tap(find.byKey(const Key('inicio_pestana_lista')));
    await asentarLista(tester);
    expect(gps.lecturas, 1);
    expect(find.byType(ListaUbicacionesPage), findsOneWidget);

    await tester.tap(find.byKey(const Key('inicio_pestana_hoy')));
    await asentarLista(tester);
    await tester.tap(find.byKey(const Key('inicio_pestana_lista')));
    await asentarLista(tester);

    expect(gps.lecturas, 2);
  });

  testWidgets('dado que escribe en el buscador y cambia de pestaña, entonces al volver sigue ahí', (
    tester,
  ) async {
    await _montar(
      tester,
      repo: RepoListaFalso([filaLista('a', calle: 'Rivadavia', numero: '1')]),
    );
    await tester.tap(find.byKey(const Key('inicio_pestana_lista')));
    await asentarLista(tester);
    await tester.enterText(find.byKey(const Key('lista_busqueda')), 'riv');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('inicio_pestana_hoy')));
    await asentarLista(tester);
    await tester.tap(find.byKey(const Key('inicio_pestana_lista')));
    await asentarLista(tester);

    expect(
      tester.widget<TextField>(find.byKey(const Key('lista_busqueda'))).controller!.text,
      'riv',
    );
  });
}
