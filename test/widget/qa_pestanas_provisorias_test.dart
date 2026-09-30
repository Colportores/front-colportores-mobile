// QA #230/#229: las pestañas sin contenido (Mapa, Lista, Agenda, Ventas) con el ícono y «Esta
// sección llega pronto.», en los tamaños de referencia a texto 1.0 y 2.0.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _ahora = DateTime(2026, 9, 29, 14, 35, 20);
final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

JornadaModel _abiertaDesde(DateTime inicio) => JornadaModel.fromEntity(
  Jornada(
    id: 'jor-previa',
    colportorId: _sesion.usuarioId,
    inicio: inicio,
    auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: _sesion.usuarioId),
  ),
);

Future<void> _montar(
  WidgetTester tester, {
  double escala = 1,
  DateTime? abiertaDesde,
  Key? boundary,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      jornadaLocalDataSourceProvider.overrideWithValue(
        JornadaLocalDataSourceEnMemoria(
          iniciales: [if (abiertaDesde != null) _abiertaDesde(abiertaDesde)],
        ),
      ),
      disparadorBackupProvider.overrideWithValue(_BackupFalso()),
      relojJornadaProvider.overrideWithValue(() => _ahora),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  ),
);

void main() {
  const tamanios = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

  for (final MapEntry(key: nombre, value: tam) in tamanios.entries) {
    for (final escala in [1.0, 2.0]) {
      for (final pestana in PestanaInicio.values.skip(1)) {
        testWidgets('pestaña ${pestana.name} en $nombre, texto $escala: sin overflow y accesible', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          tester.view.physicalSize = tam;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await _montar(tester, escala: escala);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(Key('inicio_pestana_${pestana.name}')));
          await tester.pumpAndSettle();

          expect(find.text('Esta sección llega pronto.'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }
  }
}
