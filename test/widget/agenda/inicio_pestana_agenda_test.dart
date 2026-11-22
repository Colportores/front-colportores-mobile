// HU-VIS-002: la pestaña «Agenda» de la pantalla principal es la agenda real (vista 23B), con los
// datos del colportor de la sesión, y conserva sus filtros al cambiar de pestaña.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';

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

Future<void> _montar(WidgetTester tester, ConsultaAgendaFalsa repo) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => DateTime(2026, 10, 28, 10)),
        relojAgendaProvider.overrideWithValue(() => DateTime(2026, 10, 28, 10)),
        consultaAgendaRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('dado que abre «Agenda», entonces ve las visitas del colportor de la sesión', (
    tester,
  ) async {
    final repo = ConsultaAgendaFalsa([itemAgenda('e1', DateTime(2026, 10, 28, 14, 30))]);
    await _montar(tester, repo);

    await tester.tap(find.byKey(const Key('inicio_pestana_agenda')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('pestana_agenda')), findsOneWidget);
    expect(find.byType(AgendaPage), findsOneWidget);
    expect(find.text('Ana Martínez'), findsOneWidget);
    expect(find.text('Esta sección llega pronto.'), findsNothing);
    expect(repo.pedidos.first.colportorId, 'col-1');
  });

  testWidgets('dado que elige «Cobranzas» y cambia de pestaña, entonces al volver sigue elegido', (
    tester,
  ) async {
    final repo = ConsultaAgendaFalsa([
      itemAgenda('e1', DateTime(2026, 10, 28, 14, 30)),
      itemAgenda('c1', DateTime(2026, 10, 28, 17), nombre: 'Luis', tipo: TipoAgenda.cobranza),
    ]);
    await _montar(tester, repo);
    await tester.tap(find.byKey(const Key('inicio_pestana_agenda')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Cobranzas'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('inicio_pestana_hoy')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('inicio_pestana_agenda')));
    await tester.pump();

    expect(find.text('Luis Martínez'), findsOneWidget);
    expect(find.text('Ana Martínez'), findsNothing);
    expect(repo.pedidos, hasLength(1), reason: 'la lectura sigue viva: no se vuelve a pedir');
  });

  testWidgets('dado que no hay base abierta, entonces la agenda dice que no pudo leer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
          disparadorBackupProvider.overrideWithValue(_BackupFalso()),
          relojJornadaProvider.overrideWithValue(() => DateTime(2026, 10, 28, 10)),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: InicioPage(sesion: _sesion),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inicio_pestana_agenda')));
    await tester.pump();
    await tester.pump();

    expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
  });
}
