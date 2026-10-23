// Finalizar la jornada con una entrevista abierta (vista 39, R·05; decisión de Cristian, 23/10, #450):
// la app pide la hora de salida de la entrevista y nunca la inventa; si no se termina, ni la
// entrevista ni la jornada se pierden.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
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

import '../helpers/entrevista_falsos.dart';
import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;

final _sesion = Sesion(
  usuarioId: 'col-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

void main() {
  late MontajeEntrevista montaje;
  late JornadaLocalDataSourceEnMemoria jornadas;

  setUp(() {
    montaje = MontajeEntrevista();
    final inicio = DateTime(2026, 10, 23, 13, 15);
    jornadas = JornadaLocalDataSourceEnMemoria(
      iniciales: [
        JornadaModel.fromEntity(
          Jornada(
            id: 'jor-1',
            colportorId: _sesion.usuarioId,
            inicio: inicio,
            auditoria: Auditoria(
              createdAt: inicio,
              updatedAt: inicio,
              createdBy: _sesion.usuarioId,
            ),
          ),
        ),
      ],
    );
  });

  Future<void> montar(WidgetTester tester, {double escala = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jornadaLocalDataSourceProvider.overrideWithValue(jornadas),
          disparadorBackupProvider.overrideWithValue(_BackupFalso()),
          relojJornadaProvider.overrideWithValue(() => ahoraEntrevista),
          ...overridesPestanaMapa(),
          ...montaje.overrides,
        ],
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
    );
    await tester.pumpAndSettle();
  }

  Future<void> finalizarJornada(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
    await tester.tap(find.byKey(const Key('jornada_finalizar')));
    await tester.pumpAndSettle();
  }

  bool jornadaAbierta() => jornadas.jornadas.any((j) => j.fin == null);

  testWidgets('sin entrevista abierta la jornada se finaliza como siempre', (tester) async {
    await montar(tester);

    await finalizarJornada(tester);

    expect(find.text('Terminó la entrevista'), findsNothing);
    expect(jornadaAbierta(), isFalse);
  });

  testWidgets('con una entrevista abierta pide su hora de salida antes de cerrar la jornada', (
    tester,
  ) async {
    await montaje.almacen.guardar(entrevistaDePrueba());
    await montar(tester);

    await finalizarJornada(tester);

    expect(find.text('Terminó la entrevista'), findsOneWidget);
    expect(find.text(TextosEntrevista.pedirSalida), findsOneWidget);
    expect(jornadaAbierta(), isTrue);
    expect(montaje.agenda.recibidas, isEmpty);
  });

  testWidgets('elegida la salida y guardada la entrevista, la jornada se cierra', (tester) async {
    await montaje.almacen.guardar(entrevistaDePrueba());
    await montar(tester);

    await finalizarJornada(tester);
    await tester.tap(find.byKey(ClavesEntrevista.filaSalida));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hoja_hora_menos')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('hoja_hora_usar')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));
    await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
    await tester.pumpAndSettle();

    expect(montaje.agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.entrevista);
    expect(montaje.almacen.guardadas, isEmpty);
    expect(jornadaAbierta(), isFalse);
  });

  testWidgets('si no se termina la entrevista, la jornada y la entrevista siguen abiertas', (
    tester,
  ) async {
    await montaje.almacen.guardar(entrevistaDePrueba());
    await montar(tester);

    await finalizarJornada(tester);
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();

    expect(jornadaAbierta(), isTrue);
    expect(montaje.almacen.guardadas, hasLength(1));
    // «Finalizar jornada» vuelve a responder: nada quedó «finalizando».
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('jornada_finalizar'))).onPressed,
      isNotNull,
    );
  });

  testWidgets('«Sí, registrar la venta» no cierra la jornada ni guarda la entrevista', (
    tester,
  ) async {
    await montaje.almacen.guardar(entrevistaDePrueba());
    await montar(tester);

    await finalizarJornada(tester);
    await tester.tap(find.byKey(ClavesEntrevista.filaSalida));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hoja_hora_usar')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(ClavesEntrevista.registrarVenta));
    await tester.tap(find.byKey(ClavesEntrevista.registrarVenta));
    await tester.pumpAndSettle();

    expect(jornadaAbierta(), isTrue);
    expect(montaje.agenda.recibidas, isEmpty);
    expect(montaje.almacen.guardadas, hasLength(1));
  });

  testWidgets('si la entrevista no se pudo guardar, la jornada sigue abierta', (tester) async {
    await montaje.almacen.guardar(entrevistaDePrueba());
    montaje.agenda.falla = const FailureInesperado();
    await montar(tester);

    await finalizarJornada(tester);
    await tester.tap(find.byKey(ClavesEntrevista.filaSalida));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hoja_hora_usar')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));
    await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
    await tester.pumpAndSettle();

    expect(find.text(TextosEntrevista.noPudimosGuardar), findsOneWidget);
    expect(jornadaAbierta(), isTrue);
  });
}
