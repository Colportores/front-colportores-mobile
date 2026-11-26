// QA de #769 (PR #773, «Jornada rech.», vista 20 · Hoy): el aviso fijo de una jornada que el servidor no aceptó
// por empezar antes del inicio de la campaña ahora cierra con «Contale a tu coordinador si eran de la
// campaña.». Se prueba en 360x640 y 412x915 con el texto al 100 % y al 200 %, con las guías de accesibilidad,
// con una, varias y muchas jornadas rechazadas, y que «Iniciar jornada» siga alcanzable.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/campanias_inscriptas_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/campanias_inscriptas_providers.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornadas_rechazadas_data_source.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada_rechazada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/jornada_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornadas_rechazadas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista37_387_arnes.dart' show cargarFuentes37, capturar37;

const _tamanos = <(String, Size)>[('360x640', Size(360, 640)), ('412x915', Size(412, 915))];

/// Texto al 100 % y al 200 %; con las fuentes reales de la app (anchos y desbordes) y con Ahem (el contraste: con
/// fuentes reales la guía mide el antialias del texto chico y da falsos positivos).
/// Primero con Ahem (el contraste) y después con las fuentes reales: cargarlas vale para todo el archivo.
final _matriz = <(String, Size, double, bool)>[
  for (final reales in const [false, true])
    for (final escala in const [1.0, 2.0])
      for (final (nombre, tamano) in _tamanos) (nombre, tamano, escala, reales),
];

Future<void> _fuentes(WidgetTester tester, bool reales) async {
  if (reales) await cargarFuentes37(tester);
}

void _sinDesborde(WidgetTester tester, bool reales) {
  final e = tester.takeException();
  if (reales) expect(e, isNull);
}

final _ahora = DateTime.utc(2026, 11, 20, 15);

final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'agustin@correo.com',
  accessToken: 'token',
  expiraEn: DateTime.utc(2030),
);

const _porEmpezar = CampaniaInscripta(
  campaniaId: 'camp-v',
  nombre: 'Verano 2027',
  fechaInicio: '2026-12-01',
  fechaFin: '2027-02-28',
);

final class _Rechazadas implements JornadasRechazadasDataSource {
  _Rechazadas(this.jornadas);

  final List<JornadaRechazada> jornadas;

  @override
  Stream<List<JornadaRechazada>> observar(String colportorId) => Stream.value(jornadas);
}

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

JornadaRechazada _rechazada(String id, int visitas) =>
    JornadaRechazada(id: id, inicio: DateTime.utc(2026, 11, 19, 14), visitas: visitas);

Future<void> _montar(
  WidgetTester tester,
  List<JornadaRechazada> rechazadas, {
  required Size tamano,
  required double escala,
  List<CampaniaInscripta> campanias = const [_porEmpezar],
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => _ahora),
        relojCampaniaProvider.overrideWithValue(() => _ahora),
        campaniasInscriptasDataSourceProvider.overrideWithValue(
          CampaniasInscriptasEnMemoria(campanias),
        ),
        jornadasRechazadasDataSourceProvider.overrideWithValue(_Rechazadas(rechazadas)),
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _guias(WidgetTester tester, bool reales) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (!reales) await expectLater(tester, meetsGuideline(textContrastGuideline));
}

Finder get _iniciar => find.byKey(const Key('jornada_iniciar'));

void main() {
  for (final (nombre, tamano, escala, reales) in _matriz) {
    {
      group('Hoy · jornada rechazada · $nombre · texto ${escala}x ${reales ? 'real' : 'Ahem'}', () {
        testWidgets(
          'una rechazada con 4 visitas: aviso entero, guías y «Iniciar jornada» alcanzable',
          (tester) async {
            await _fuentes(tester, reales);
            await _montar(tester, [_rechazada('j-1', 4)], tamano: tamano, escala: escala);

            final aviso = find.byKey(const Key('jornada_rechazada_j-1'));
            expect(aviso, findsOneWidget);
            expect(
              find.descendant(
                of: aviso,
                matching: find.textContaining('Contale a tu coordinador si eran de la campaña.'),
              ),
              findsOneWidget,
            );
            _sinDesborde(tester, reales);
            await _guias(tester, reales);
            if (reales) await capturar37(tester, '769_hoy_rechazada_${nombre}_$escala');

            // «Iniciar jornada» se alcanza desplazando (con la campaña por empezar avisa, no inicia).
            await tester.ensureVisible(_iniciar);
            await tester.pump();
            expect(_iniciar.hitTestable(), findsOneWidget);
            _sinDesborde(tester, reales);
          },
        );

        testWidgets('cinco rechazadas (0, 1 y varias visitas): todas con la frase final', (
          tester,
        ) async {
          await _fuentes(tester, reales);
          await _montar(
            tester,
            [for (var i = 0; i < 5; i++) _rechazada('j-$i', i == 0 ? 0 : i)],
            tamano: tamano,
            escala: escala,
          );

          for (var i = 0; i < 5; i++) {
            final aviso = find.byKey(Key('jornada_rechazada_j-$i'));
            await tester.ensureVisible(aviso);
            await tester.pump();
            expect(
              find.descendant(
                of: aviso,
                matching: find.textContaining('Contale a tu coordinador si eran de la campaña.'),
              ),
              findsOneWidget,
              reason: 'j-$i',
            );
          }
          _sinDesborde(tester, reales);
          await _guias(tester, reales);
          if (reales) await capturar37(tester, '769_hoy_cinco_rechazadas_${nombre}_$escala');
        });
      });
    }
  }
}
