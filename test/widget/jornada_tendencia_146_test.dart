// Cómo va la jornada contra la anterior (vista 21, 21J·01 a 21J·04; decisión del 04/11, regla R3): casas
// visitadas y ventas con ▲ o ▼; la primera jornada de la campaña no tiene tendencia; el cierre dice con
// quién se trabajó y, si nadie figura, que el coordinador lo puede agregar desde el panel (HU-JOR-003).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/campanias_inscriptas_providers.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/data/repositories/fakes/acompaniamiento_repository_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/acompaniante.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/tendencia_de_la_jornada.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/resumen_jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/acompaniamiento_providers.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/jornada/presentation/widgets/tarjeta_de_tendencia.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

final _ahora = DateTime(2026, 11, 20, 14, 35, 20);

final _sesion = Sesion(
  usuarioId: 'col-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token',
  expiraEn: DateTime.utc(2030),
);

final _inicio = DateTime(2026, 11, 20, 8, 10);

/// La campaña en curso de Lucía el día de la jornada: de ella sale contra cuál se compara.
Override _campaniaEnCurso() => campaniasInscriptasProvider('col-1').overrideWith(
  (ref) => Stream.value(const [
    CampaniaInscripta(
      campaniaId: 'cam-1',
      nombre: 'Verano',
      fechaInicio: '2026-11-01',
      fechaFin: '2026-11-30',
    ),
  ]),
);

Jornada _jornada({DateTime? fin}) => Jornada(
  id: 'jor-1',
  colportorId: 'col-1',
  inicio: _inicio,
  fin: fin,
  auditoria: Auditoria(createdAt: _inicio, updatedAt: _inicio, createdBy: 'col-1'),
);

/// La tarjeta de tendencia sola, con la jornada en curso: 21J·01, 21J·02 y 21J·04 la dibujan en la pantalla
/// «Finalizar jornada» que todavía no existe (decisión del 26/11, `Cristian §3`); hoy se ve en el cierre.
Future<void> _montarTarjeta(
  WidgetTester tester,
  AcompaniamientoRepositoryEnMemoria repo, {
  double escala = 1,
  Size tamanio = const Size(390, 844),
  bool conCampania = true,
}) async {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        acompaniamientoRepositoryProvider.overrideWithValue(repo),
        if (conCampania) _campaniaEnCurso(),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: TarjetaDeTendencia(colportorId: 'col-1', jornada: _jornada()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _montarHoy(
  WidgetTester tester,
  AcompaniamientoRepositoryEnMemoria repo, {
  double escala = 1,
  Size tamanio = const Size(390, 844),
  bool conCampania = true,
}) async {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(
          JornadaLocalDataSourceEnMemoria(iniciales: [JornadaModel.fromEntity(_jornada())]),
        ),
        relojJornadaProvider.overrideWithValue(() => _ahora),
        acompaniamientoRepositoryProvider.overrideWithValue(repo),
        if (conCampania) _campaniaEnCurso(),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(body: JornadaPage(sesion: _sesion)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _montarResumen(WidgetTester tester, AcompaniamientoRepositoryEnMemoria repo) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [acompaniamientoRepositoryProvider.overrideWithValue(repo), _campaniaEnCurso()],
      child: MaterialApp(
        theme: temaClaro(),
        home: ResumenJornadaPage(
          jornada: _jornada(fin: _inicio.add(const Duration(hours: 6, minutes: 25))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _texto(WidgetTester tester, String clave) =>
    tester.widget<Text>(find.byKey(Key(clave))).data!;

void main() {
  group('21J·01 y 21J·02 · cerrar con la tendencia', () {
    testWidgets(
      'dado una jornada anterior, veo casas y ventas contra ella con ▲ y ▼ además del color',
      (tester) async {
        final repo = AcompaniamientoRepositoryEnMemoria(
          tendencia: const TendenciaDeLaJornada(
            casasVisitadas: 14,
            ventas: 2,
            casasVisitadasAntes: 11,
            ventasAntes: 3,
          ),
        );

        await _montarTarjeta(tester, repo);

        expect(find.text('CONTRA TU JORNADA ANTERIOR'), findsOneWidget);
        expect(_texto(tester, 'jornada_tendencia_casas_valor'), '14');
        expect(_texto(tester, 'jornada_tendencia_casas_variacion'), '▲ 3');
        expect(_texto(tester, 'jornada_tendencia_ventas_valor'), '2');
        expect(_texto(tester, 'jornada_tendencia_ventas_variacion'), '▼ 1');
        expect(find.text('Cobros'), findsNothing, reason: 'los cobros no entran');
      },
    );

    testWidgets('lo igual se dice con palabras y el lector de pantalla lee la diferencia', (
      tester,
    ) async {
      final repo = AcompaniamientoRepositoryEnMemoria(
        tendencia: const TendenciaDeLaJornada(
          casasVisitadas: 5,
          ventas: 0,
          casasVisitadasAntes: 5,
          ventasAntes: 2,
        ),
      );
      final semantica = tester.ensureSemantics();

      await _montarTarjeta(tester, repo);

      expect(_texto(tester, 'jornada_tendencia_casas_variacion'), '= igual');
      expect(
        find.bySemanticsLabel('Casas visitadas: 5, igual que en tu jornada anterior'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Ventas: 0, 2 menos que en tu jornada anterior'),
        findsOneWidget,
      );
      semantica.dispose();
    });
  });

  group('21J·04 · primera jornada: sin tendencia', () {
    testWidgets('muestra las cifras de hoy y la frase, sin flechas ni comparación', (tester) async {
      final repo = AcompaniamientoRepositoryEnMemoria(
        tendencia: const TendenciaDeLaJornada(casasVisitadas: 14, ventas: 2),
      );

      await _montarTarjeta(tester, repo);

      expect(find.text('TU JORNADA'), findsOneWidget);
      expect(find.text('CONTRA TU JORNADA ANTERIOR'), findsNothing);
      expect(_texto(tester, 'jornada_tendencia_casas_valor'), '14');
      expect(find.byKey(const Key('jornada_tendencia_casas_variacion')), findsNothing);
      expect(
        find.text('Es tu primera jornada: desde mañana te mostramos cómo vas contra la anterior.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'sin saber la campaña de la jornada no se muestra nada (no se afirma una «primera»)',
      (tester) async {
        await _montarTarjeta(
          tester,
          AcompaniamientoRepositoryEnMemoria(
            tendencia: const TendenciaDeLaJornada(casasVisitadas: 3, ventas: 1),
          ),
          conCampania: false,
        );

        expect(find.byKey(const Key('jornada_tendencia')), findsNothing);
        expect(find.textContaining('primera jornada'), findsNothing);
      },
    );

    testWidgets('con el texto al 200 % en 320×568 la tarjeta no desborda', (tester) async {
      final repo = AcompaniamientoRepositoryEnMemoria(
        tendencia: const TendenciaDeLaJornada(
          casasVisitadas: 1234,
          ventas: 987,
          casasVisitadasAntes: 11,
          ventasAntes: 3,
        ),
      );

      // Solo la tarjeta: a 320 dp y 200 % la fila de la hora de fin de «Hoy» ya desborda en develop.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            acompaniamientoRepositoryProvider.overrideWithValue(repo),
            _campaniaEnCurso(),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: TarjetaDeTendencia(colportorId: 'col-1', jornada: _jornada()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('jornada_tendencia')), findsOneWidget);
      expect(_texto(tester, 'jornada_tendencia_casas_valor'), '1234');
    });

    testWidgets('cambia sola cuando la colportora visita otra casa', (tester) async {
      final repo = AcompaniamientoRepositoryEnMemoria(
        tendencia: const TendenciaDeLaJornada(casasVisitadas: 1, ventas: 0),
      );
      await _montarTarjeta(tester, repo);

      repo.tendencia = const TendenciaDeLaJornada(casasVisitadas: 2, ventas: 0);
      await tester.pumpAndSettle();

      expect(_texto(tester, 'jornada_tendencia_casas_valor'), '2');
    });
  });

  group('«Hoy» no lleva la tendencia', () {
    testWidgets(
      'con la jornada en curso, «Hoy» muestra el interruptor y no la comparación (decisión 26/11)',
      (tester) async {
        final repo = AcompaniamientoRepositoryEnMemoria(
          tendencia: const TendenciaDeLaJornada(
            casasVisitadas: 14,
            ventas: 2,
            casasVisitadasAntes: 11,
            ventasAntes: 3,
          ),
        );

        await _montarHoy(tester, repo);

        expect(find.byKey(const Key('jornada_tendencia')), findsNothing);
        expect(find.byKey(const Key('acompaniamiento_interruptor')), findsOneWidget);
      },
    );
  });

  group('21J·03 · jornada cerrada', () {
    testWidgets('sin acompañantes dice «Nadie» y le avisa que su coordinador lo puede agregar', (
      tester,
    ) async {
      await _montarResumen(tester, AcompaniamientoRepositoryEnMemoria());

      expect(_texto(tester, 'jornada_resumen_acompanio_quienes'), 'Nadie');
      expect(
        find.text(
          'Si alguien te acompañó y no lo marcaste, avisale a tu coordinador: lo agrega desde el panel.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('con acompañantes los nombra a todos y no muestra el aviso', (tester) async {
      final repo = AcompaniamientoRepositoryEnMemoria(
        lista: const [
          CoordinadorDeCampania(usuarioId: 'u-marta', nombre: 'Marta', apellido: 'Pérez'),
          CoordinadorDeCampania(usuarioId: 'u-daniel', nombre: 'Daniel', apellido: 'Ruiz'),
        ],
      );
      await repo.guardar(
        jornadaId: 'jor-1',
        colportorId: 'col-1',
        usuarioIds: {'u-marta', 'u-daniel'},
      );

      await _montarResumen(tester, repo);

      expect(_texto(tester, 'jornada_resumen_acompanio_quienes'), 'Daniel Ruiz, Marta Pérez');
      expect(find.byKey(const Key('jornada_resumen_aviso_acompanio')), findsNothing);
    });

    testWidgets('las cifras de casas y ventas son las guardadas; los cobros siguen en «—»', (
      tester,
    ) async {
      final repo = AcompaniamientoRepositoryEnMemoria(
        tendencia: const TendenciaDeLaJornada(casasVisitadas: 14, ventas: 2),
      );

      await _montarResumen(tester, repo);

      expect(_texto(tester, 'jornada_resumen_cifra_0'), '14');
      expect(_texto(tester, 'jornada_resumen_cifra_1'), '2');
      expect(_texto(tester, 'jornada_resumen_cifra_2'), '—');
      expect(
        find.byKey(const Key('jornada_tendencia')),
        findsNothing,
        reason: 'primera: sin comparación',
      );
    });

    testWidgets('con la tendencia y el resumen de siempre: «Volver al inicio» sigue ahí', (
      tester,
    ) async {
      final repo = AcompaniamientoRepositoryEnMemoria(
        tendencia: const TendenciaDeLaJornada(
          casasVisitadas: 14,
          ventas: 2,
          casasVisitadasAntes: 11,
          ventasAntes: 3,
        ),
      );

      await _montarResumen(tester, repo);

      expect(_texto(tester, 'jornada_tendencia_casas_variacion'), '▲ 3');
      expect(find.byKey(const Key('jornada_resumen_volver')), findsOneWidget);
      expect(find.byKey(const Key('jornada_resumen_duracion')), findsOneWidget);
    });
  });
}
