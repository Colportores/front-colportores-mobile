// QA de #538 (tanda 1 de tests saltados: agenda y visitas). Complementa los tests del implementador
// con lo que no cruzan, sobre las vistas 23 (hoja «Día y hora», detalle) y 39 (R·05, R·06, R·07):
//  1. la hoja «Día y hora» pasa la medianoche (mes, año, 300 toques seguidos, hacia atrás, día viejo);
//  2. el detalle con la casa sin leer: aviso, «Reintentar» que recupera, tamaños y guías de toque;
//  3. R·06/R·07: la hoja no se cierra guardando (atrás, toque afuera, lector), no queda trabada tras
//     una falla, un solo guardado con dos toques, «Duración» según las horas, y el texto de una
//     jornada que ya no está;
//  4. el rótulo «OPCIONAL» y «+ Agendar» a 200 % en 360×640.
//
// Los hallazgos viven con `skip` (se corren con `--dart-define=QA_HALLAZGOS=true`); las capturas,
// con `--dart-define=QA_CAPTURAS=true` (a `.dart_tool/qa_capturas/`, ignorado por git).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/motivo_rechazo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/textos_agendar_visita.dart';
import 'package:colportores_mobile/features/agenda/presentation/textos_detalle_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_termino_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show casaMataojo, mariaFernandez;
import '../../helpers/detalle_agenda_arnes.dart'
    show AgendaRepositorioDetalle, agendaDelDetalle, ahoraDelDetalle;
import '../../helpers/notificaciones_arnes.dart' show Telefono;
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_agenda_148_arnes.dart' as a148;
import '../../helpers/qa_vista39_450_arnes.dart';

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');
const _capturas = bool.fromEnvironment('QA_CAPTURAS');

const _chico = Size(360, 640);
const _grande = Size(412, 915);

String _suf(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

// ───────────────────────── 1 · hoja «Día y hora» ─────────────────────────

final _llaveHoja = GlobalKey();

/// Abre la hoja con [inicial] y [ahora]; lo que devuelva «Listo» queda en el notificador.
Future<ValueNotifier<DateTime?>> _abrirHoja(
  WidgetTester tester, {
  required DateTime inicial,
  required DateTime ahora,
  Size tamano = _grande,
  double escala = 1,
}) async {
  await cargarFuentes(tester);
  final devuelto = ValueNotifier<DateTime?>(null);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _llaveHoja,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('qa_abrir_hoja'),
                onPressed: () async => devuelto.value = await mostrarHojaDiaYHora(
                  context,
                  inicial: inicial,
                  ahora: ahora,
                ),
                child: const Text('abrir hoja'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('qa_abrir_hoja')));
  await tester.pumpAndSettle();
  return devuelto;
}

Future<void> _tocarHoja(WidgetTester tester, Key k, [int veces = 1]) async {
  for (var i = 0; i < veces; i++) {
    await tester.tap(find.byKey(k));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _capturarHoja(WidgetTester tester, String nombre) async {
  if (!_capturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_llaveHoja));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa538_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

// ───────────────────────── 2 · detalle con la casa sin leer ─────────────────────────

/// Como `EspacioRepositorioParaPersonas`, pero con la falla que se puede sacar entre medio.
final class _EspacioMutable implements EspacioRepository {
  _EspacioMutable(this.contexto, {this.falla});

  EspacioConUbicacion? contexto;
  Failure? falla;
  var lecturas = 0;

  @override
  Future<Either<Failure, EspacioConUbicacion?>> buscar(String id) async {
    lecturas++;
    return falla != null ? Left(falla!) : Right(contexto);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _llaveDetalle = GlobalKey();

Future<List<String>> _montarDetalle(
  WidgetTester tester,
  _EspacioMutable espacio, {
  Size tamano = _grande,
  double escala = 1,
  List<String>? registros,
}) async {
  await cargarFuentes(tester);
  final recibidos = registros ?? <String>[];
  final telefono = Telefono()..recordatorios.permisoConcedido = true;
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final personas = PersonaRepositorioFalso()..sembrar([mariaFernandez]);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _llaveDetalle,
      child: ProviderScope(
        overrides: [
          agendaRepositoryProvider.overrideWithValue(
            AgendaRepositorioDetalle(DetalleDeAgenda(agenda: agendaDelDetalle())),
          ),
          relojVisitaProvider.overrideWithValue(ahoraDelDetalle),
          ...telefono.overrides,
          personaRepositoryProvider.overrideWithValue(personas),
          espacioRepositoryProvider.overrideWithValue(espacio),
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((c) {
            recibidos.add('registro');
            return true;
          }),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => unawaited(
                    DetalleAgendaPage.abrir(context, agendaId: 'ag-1', colportorId: 'col-1'),
                  ),
                  child: const Text('abrir detalle'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir detalle'));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return recibidos;
}

Future<void> _pasar(WidgetTester tester, [int veces = 12]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _capturarDetalle(WidgetTester tester, String nombre) async {
  if (!_capturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_llaveDetalle));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa538_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  // ═════════════════════════ 1 · HOJA «DÍA Y HORA» (QA #408) ═════════════════════════
  group('Hoja «Día y hora»: la medianoche', () {
    testWidgets(
      'fin de año: 31/12 23:55 + un toque → 01/01 00:00, el chip de mañana queda elegido y «Listo» '
      'devuelve el instante',
      (tester) async {
        final ahora = DateTime(2026, 12, 31, 20);
        final devuelto = await _abrirHoja(
          tester,
          inicial: DateTime(2026, 12, 31, 23, 55),
          ahora: ahora,
        );
        expect(find.text('23:55'), findsOneWidget);

        await _tocarHoja(tester, ClavesAgendarVisita.hojaMas);

        expect(find.text('00:00'), findsOneWidget);
        expect(tester.widget<ChoiceChip>(find.byKey(ClavesAgendarVisita.dia(1))).selected, isTrue);
        expect(tester.widget<ChoiceChip>(find.byKey(ClavesAgendarVisita.dia(0))).selected, isFalse);
        await _tocarHoja(tester, ClavesAgendarVisita.hojaListo);
        expect(devuelto.value, DateTime(2027, 1, 1));
      },
    );

    testWidgets('fin de mes hacia atrás: 01/11 00:00 − un toque → 31/10 23:55', (tester) async {
      final devuelto = await _abrirHoja(
        tester,
        inicial: DateTime(2026, 11, 1),
        ahora: DateTime(2026, 10, 30, 9),
      );
      await _tocarHoja(tester, ClavesAgendarVisita.hojaMenos);
      expect(find.text('23:55'), findsOneWidget);
      await _tocarHoja(tester, ClavesAgendarVisita.hojaListo);
      expect(devuelto.value, DateTime(2026, 10, 31, 23, 55));
    });

    testWidgets(
      '300 toques seguidos en «+» (25 h) y 300 en «−» vuelven al mismo instante: el día y la hora '
      'nunca se desfasan',
      (tester) async {
        final ahora = DateTime(2026, 10, 24, 8);
        final devuelto = await _abrirHoja(
          tester,
          inicial: DateTime(2026, 10, 24, 10),
          ahora: ahora,
        );

        await _tocarHoja(tester, ClavesAgendarVisita.hojaMas, 300);
        await _tocarHoja(tester, ClavesAgendarVisita.hojaListo);
        expect(devuelto.value, DateTime(2026, 10, 25, 11));

        devuelto.value = null;
        await tester.tap(find.byKey(const Key('qa_abrir_hoja')));
        await tester.pumpAndSettle();
        // Reabrir parte de nuevo del instante inicial (la hoja no guarda estado entre aperturas).
        expect(find.text('10:00'), findsOneWidget);
        await _tocarHoja(tester, ClavesAgendarVisita.hojaMenos, 120); // 10:00 -> 00:00 de hoy
        expect(find.text('00:00'), findsOneWidget);
        await _tocarHoja(tester, ClavesAgendarVisita.hojaMenos, 3); // no baja de hoy
        expect(find.text('00:00'), findsOneWidget);
        expect(tester.widget<ChoiceChip>(find.byKey(ClavesAgendarVisita.dia(0))).selected, isTrue);
      },
    );

    testWidgets(
      '«Hoy», 00:05: dos toques en «−» dejan 00:00 (el segundo no hace nada) y el día sigue '
      'siendo hoy',
      (tester) async {
        await _abrirHoja(
          tester,
          inicial: DateTime(2026, 10, 24, 0, 5),
          ahora: DateTime(2026, 10, 24, 0, 1),
        );
        await _tocarHoja(tester, ClavesAgendarVisita.hojaMenos, 2);
        expect(find.text('00:00'), findsOneWidget);
        expect(tester.widget<ChoiceChip>(find.byKey(ClavesAgendarVisita.dia(0))).selected, isTrue);
      },
    );

    testWidgets(
      'un día elegido a mano lejos (a 30 días): cruzar la medianoche hacia atrás cae en el día '
      'anterior a 23:55',
      (tester) async {
        final devuelto = await _abrirHoja(
          tester,
          inicial: DateTime(2026, 11, 23),
          ahora: DateTime(2026, 10, 24, 9),
        );
        await _tocarHoja(tester, ClavesAgendarVisita.hojaMenos);
        await _tocarHoja(tester, ClavesAgendarVisita.hojaListo);
        expect(devuelto.value, DateTime(2026, 11, 22, 23, 55));
      },
    );

    for (final escala in [1.0, 2.0]) {
      for (final tamano in [_chico, _grande]) {
        testWidgets(
          'a medianoche (23:55 → 00:00) sin desborde y con las guías de toque · ${_suf(tamano, escala)}',
          (tester) async {
            await _abrirHoja(
              tester,
              inicial: DateTime(2026, 10, 24, 23, 55),
              ahora: DateTime(2026, 10, 24, 9),
              tamano: tamano,
              escala: escala,
            );
            await _tocarHoja(tester, ClavesAgendarVisita.hojaMas);
            expect(tester.takeException(), isNull);
            await _capturarHoja(tester, 'hoja_medianoche_${_suf(tamano, escala)}');
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          },
        );
      }
    }

    testWidgets(
      'si la página quedó abierta de un día para otro (el día de la hoja es de AYER), «+» y «−» '
      'siguen moviendo la hora',
      (tester) async {
        await _abrirHoja(
          tester,
          inicial: DateTime(2026, 10, 23, 10),
          ahora: DateTime(2026, 10, 24, 8),
        );
        await _tocarHoja(tester, ClavesAgendarVisita.hojaMas);
        expect(
          find.text('10:05'),
          findsOneWidget,
          reason: 'el botón «+» quedó muerto con un día viejo',
        );
        await _tocarHoja(tester, ClavesAgendarVisita.hojaMenos, 2);
        expect(
          find.text('09:55'),
          findsOneWidget,
          reason: 'el botón «−» quedó muerto con un día viejo',
        );
      },
      skip:
          !_hallazgos, // skip: QA #538 — con el día de la hoja anterior a hoy, «+» y «−» no hacen nada.
    );
  });

  // ═════════════════════════ 2 · DETALLE DE LA AGENDA (QA #409) ═════════════════════════
  group('Detalle con la casa sin leer', () {
    testWidgets(
      'la casa falla: el aviso dice qué pasó, «Reintentar» está a mano, «Registrar resultado» '
      'queda apagado y no registra',
      (tester) async {
        final registros = await _montarDetalle(
          tester,
          _EspacioMutable(casaMataojo(), falla: const FailureInesperado()),
        );
        expect(find.byKey(ClavesDetalleAgenda.avisoCasa), findsOneWidget);
        expect(find.text(TextosDetalleAgenda.noPudimosLeerLaCasa), findsOneWidget);
        expect(find.byKey(ClavesDetalleAgenda.reintentar), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byKey(ClavesDetalleAgenda.registrar)).onPressed,
          isNull,
        );
        await tester.tap(find.byKey(ClavesDetalleAgenda.registrar), warnIfMissed: false);
        await _pasar(tester);
        expect(registros, isEmpty);
      },
    );

    testWidgets(
      '«Reintentar» con la casa que ya responde: el aviso se va, «Registrar resultado» se enciende '
      'y registra una sola vez',
      (tester) async {
        final espacio = _EspacioMutable(casaMataojo(), falla: const FailureInesperado());
        final registros = await _montarDetalle(tester, espacio);
        final lecturasAntes = espacio.lecturas;
        espacio.falla = null;

        await tester.ensureVisible(find.byKey(ClavesDetalleAgenda.reintentar));
        await tester.tap(find.byKey(ClavesDetalleAgenda.reintentar));
        await _pasar(tester);

        expect(espacio.lecturas, greaterThan(lecturasAntes));
        expect(find.byKey(ClavesDetalleAgenda.avisoCasa), findsNothing);
        expect(find.byKey(ClavesDetalleAgenda.reintentar), findsNothing);
        final registrar = find.byKey(ClavesDetalleAgenda.registrar);
        expect(tester.widget<FilledButton>(registrar).onPressed, isNotNull);
        await tester.ensureVisible(registrar);
        await tester.tap(registrar);
        await _pasar(tester);
        expect(registros, hasLength(1));
      },
    );

    testWidgets(
      '«Reintentar» que vuelve a fallar: el aviso sigue y se puede reintentar de nuevo (nada queda '
      'trabado)',
      (tester) async {
        final espacio = _EspacioMutable(casaMataojo(), falla: const FailureInesperado());
        await _montarDetalle(tester, espacio);
        for (var i = 0; i < 3; i++) {
          await tester.ensureVisible(find.byKey(ClavesDetalleAgenda.reintentar));
          await tester.tap(find.byKey(ClavesDetalleAgenda.reintentar));
          await _pasar(tester);
          expect(find.byKey(ClavesDetalleAgenda.avisoCasa), findsOneWidget, reason: 'vuelta $i');
          expect(find.byKey(ClavesDetalleAgenda.reintentar), findsOneWidget, reason: 'vuelta $i');
        }
        espacio.falla = null;
        await tester.ensureVisible(find.byKey(ClavesDetalleAgenda.reintentar));
        await tester.tap(find.byKey(ClavesDetalleAgenda.reintentar));
        await _pasar(tester);
        expect(find.byKey(ClavesDetalleAgenda.avisoCasa), findsNothing);
      },
    );

    testWidgets(
      'la casa ya no está en el teléfono: el aviso lo dice, sin «Reintentar» (no serviría) y con '
      '«Registrar resultado» apagado',
      (tester) async {
        await _montarDetalle(tester, _EspacioMutable(null));
        expect(find.byKey(ClavesDetalleAgenda.avisoCasa), findsOneWidget);
        expect(find.text(TextosAgendarVisita.casaNoEstaMas), findsOneWidget);
        expect(find.byKey(ClavesDetalleAgenda.reintentar), findsNothing);
        expect(
          tester.widget<FilledButton>(find.byKey(ClavesDetalleAgenda.registrar)).onPressed,
          isNull,
        );
      },
    );

    testWidgets('con la casa bien no hay aviso (el aviso no es permanente)', (tester) async {
      await _montarDetalle(tester, _EspacioMutable(casaMataojo()));
      expect(find.byKey(ClavesDetalleAgenda.avisoCasa), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(ClavesDetalleAgenda.registrar)).onPressed,
        isNotNull,
      );
    });

    testWidgets('el aviso de la casa es una región viva (se anuncia cuando aparece)', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await _montarDetalle(
        tester,
        _EspacioMutable(casaMataojo(), falla: const FailureInesperado()),
      );
      final nodo = tester.getSemantics(find.byKey(ClavesDetalleAgenda.avisoCasa));
      expect(nodo.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      h.dispose();
    });

    for (final tamano in [_chico, _grande]) {
      for (final escala in [1.0, 2.0]) {
        for (final conFalla in [true, false]) {
          testWidgets(
            'casa ${conFalla ? 'sin leer' : 'que no está'} · ${_suf(tamano, escala)}: sin desborde, el '
            'aviso y «Reintentar» se alcanzan y cumplen las guías de toque',
            (tester) async {
              await _montarDetalle(
                tester,
                _EspacioMutable(casaMataojo(), falla: conFalla ? const FailureInesperado() : null)
                  ..contexto = conFalla ? casaMataojo() : null,
                tamano: tamano,
                escala: escala,
              );
              expect(tester.takeException(), isNull);
              await tester.ensureVisible(find.byKey(ClavesDetalleAgenda.avisoCasa));
              await _pasar(tester, 6);
              await _capturarDetalle(
                tester,
                'detalle_casa_${conFalla ? 'error' : 'nohay'}_${_suf(tamano, escala)}',
              );
              final pantalla = Offset.zero & tamano;
              final aviso = tester.getRect(find.byKey(ClavesDetalleAgenda.avisoCasa));
              expect(
                pantalla.contains(aviso.topLeft),
                isTrue,
                reason: 'aviso fuera de vista: $aviso',
              );
              if (conFalla) {
                await tester.ensureVisible(find.byKey(ClavesDetalleAgenda.reintentar));
                final r = tester.getRect(find.byKey(ClavesDetalleAgenda.reintentar));
                expect(r.height, greaterThanOrEqualTo(48), reason: '«Reintentar» de $r');
              }
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            },
          );
        }
      }
    }
  });

  group('Detalle apilado (QA #409)', () {
    testWidgets(
      'abrir el detalle de OTRA agenda con uno ya arriba sí apila (no se descarta lo que no es '
      'repetido) y volver deja el primero',
      (tester) async {
        await _montarDetalle(tester, _EspacioMutable(casaMataojo()));
        final contexto = tester.element(find.byType(DetalleAgendaPage));
        unawaited(DetalleAgendaPage.abrir(contexto, agendaId: 'ag-2', colportorId: 'col-1'));
        await _pasar(tester);
        expect(find.byType(DetalleAgendaPage, skipOffstage: false), findsNWidgets(2));
        Navigator.of(tester.element(find.byType(DetalleAgendaPage).last)).pop();
        await _pasar(tester);
        expect(find.byType(DetalleAgendaPage, skipOffstage: false), findsOneWidget);
      },
    );

    testWidgets(
      'abrir el mismo detalle 5 veces seguidas deja uno solo, y una sola vuelta atrás vuelve a la '
      'pantalla de origen',
      (tester) async {
        await _montarDetalle(tester, _EspacioMutable(casaMataojo()));
        final contexto = tester.element(find.byType(DetalleAgendaPage));
        for (var i = 0; i < 5; i++) {
          unawaited(DetalleAgendaPage.abrir(contexto, agendaId: 'ag-1', colportorId: 'col-1'));
        }
        await _pasar(tester);
        expect(find.byType(DetalleAgendaPage, skipOffstage: false), findsOneWidget);
        await tester.binding.handlePopRoute();
        await _pasar(tester, 20);
        expect(find.byType(DetalleAgendaPage, skipOffstage: false), findsNothing);
        expect(find.text('abrir detalle'), findsOneWidget);
      },
    );

    testWidgets(
      'el futuro de `abrir` sobre la repetida termina enseguida (nadie queda esperando)',
      (tester) async {
        await _montarDetalle(tester, _EspacioMutable(casaMataojo()));
        final contexto = tester.element(find.byType(DetalleAgendaPage));
        var termino = false;
        unawaited(
          DetalleAgendaPage.abrir(
            contexto,
            agendaId: 'ag-1',
            colportorId: 'col-1',
          ).then((_) => termino = true),
        );
        await tester.pump();
        expect(termino, isTrue);
      },
    );
  });

  // ═════════════════════════ 3 · R·06 / R·07 (QA #450) ═════════════════════════
  group('R·06 guardando: la hoja no se cierra por ninguna salida', () {
    testWidgets('el toque afuera de la hoja no la cierra mientras guarda, y al terminar llega la '
        'confirmación', (tester) async {
      final r = await llegar(tester, Estado39.r06Guardando, tamano: _grande);
      final arriba = tester.getTopLeft(find.byKey(ClavesEntrevista.hojaTermino)).dy;
      expect(arriba, greaterThan(20), reason: 'a 412×915 queda aire arriba de la hoja');
      await tester.tapAt(Offset(206, arriba / 2));
      await tester.pumpAndSettle();
      expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
      r.montaje.agenda.compuerta!.complete();
      await tester.pumpAndSettle();
      expect(find.text(TextosEntrevista.guardada('Grecia 3307')), findsOneWidget);
    });

    testWidgets('«descartar» del lector (dismiss del telón) tampoco la cierra mientras guarda', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final r = await llegar(tester, Estado39.r06Guardando, tamano: _grande);
      final dismiss = find.semantics.byAction(SemanticsAction.dismiss);
      if (dismiss.evaluate().isNotEmpty) {
        tester.semantics.performAction(dismiss.first, SemanticsAction.dismiss);
        await tester.pumpAndSettle();
      }
      expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
      r.montaje.agenda.compuerta!.complete();
      await tester.pumpAndSettle();
      expect(find.text(TextosEntrevista.guardada('Grecia 3307')), findsOneWidget);
      h.dispose();
    });

    testWidgets('el atrás repetido 5 veces mientras guarda no la cierra ni rompe nada', (
      tester,
    ) async {
      final r = await llegar(tester, Estado39.r06Guardando);
      for (var i = 0; i < 5; i++) {
        await tester.binding.handlePopRoute();
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
      expect(tester.takeException(), isNull);
      r.montaje.agenda.compuerta!.complete();
      await tester.pumpAndSettle();
      expect(find.text(TextosEntrevista.guardada('Grecia 3307')), findsOneWidget);
    });

    testWidgets(
      'si el guardado FALLA, la hoja vuelve a poder cerrarse (atrás) y no queda trabada en «Guardando…»',
      (tester) async {
        final r = await llegar(tester, Estado39.r06Guardando);
        r.montaje.agenda.falla = const FailureInesperado();
        r.montaje.agenda.compuerta!.complete();
        await tester.pumpAndSettle();
        expect(find.byKey(ClavesEntrevista.avisoError), findsOneWidget);
        expect(find.text(TextosEntrevista.guardando), findsNothing);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(ClavesEntrevista.hojaTermino), findsNothing);
      },
    );

    testWidgets('falla, se arregla y «Guardar y volver» otra vez guarda una sola visita', (
      tester,
    ) async {
      final r = await llegar(tester, Estado39.r06Error);
      expect(find.byKey(ClavesEntrevista.avisoError), findsOneWidget);
      r.montaje.agenda.falla = null;
      await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));
      expect(find.text(TextosEntrevista.guardada('Grecia 3307')), findsOneWidget);
      expect(r.montaje.agenda.recibidas, hasLength(1));
    });

    testWidgets('dos toques seguidos en «Guardar y volver» guardan una sola vez', (tester) async {
      final r = await llegar(tester, Estado39.r06);
      r.montaje.agenda.compuerta = Completer<void>();
      final boton = find.byKey(ClavesEntrevista.guardarYVolver);
      await tester.ensureVisible(boton);
      await tester.tap(boton);
      await tester.tap(boton, warnIfMissed: false);
      await tester.pump();
      r.montaje.agenda.compuerta!.complete();
      await tester.pumpAndSettle();
      expect(r.montaje.agenda.recibidas, hasLength(1));
    });
  });

  group('R·06 / R·07: «Duración»', () {
    Future<void> montarHoja(
      WidgetTester tester, {
      required DateTime? entrada,
      required DateTime? salida,
      required bool inferida,
      Size tamano = _chico,
      double escala = 1,
    }) async {
      await cargarFuentes(tester);
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Scaffold(
            body: HojaTerminoEntrevista(
              direccion: 'Grecia 3307',
              persona: 'Pedro Gómez',
              entrada: entrada,
              salida: salida,
              entradaInferida: inferida,
              alGuardar: (_, _) async => null,
              reloj: () => DateTime(2026, 10, 23, 15),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final dia = DateTime(2026, 10, 23);

    testWidgets('R·06 con las dos horas: «Duración» dice la diferencia', (tester) async {
      await montarHoja(
        tester,
        entrada: dia.add(const Duration(hours: 14)),
        salida: dia.add(const Duration(hours: 14, minutes: 30)),
        inferida: false,
      );
      expect(find.byKey(ClavesEntrevista.duracion), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
    });

    testWidgets('R·06 con entrada == salida: «Duración» no se esconde y no dice nada falso', (
      tester,
    ) async {
      await montarHoja(
        tester,
        entrada: dia.add(const Duration(hours: 14)),
        salida: dia.add(const Duration(hours: 14)),
        inferida: false,
      );
      expect(find.byKey(ClavesEntrevista.duracion), findsOneWidget);
      expect(find.textContaining('-'), findsNothing);
    });

    testWidgets('R·06 con la salida ANTES de la entrada: sin fila «Duración» ni «menos de 1 min»', (
      tester,
    ) async {
      await montarHoja(
        tester,
        entrada: dia.add(const Duration(hours: 14, minutes: 30)),
        salida: dia.add(const Duration(hours: 14, minutes: 10)),
        inferida: false,
      );
      expect(find.byKey(ClavesEntrevista.duracion), findsNothing);
      expect(find.text('menos de 1 min'), findsNothing);
    });

    testWidgets('R·06 con una sola hora: sin «Duración»; las filas dicen «Elegir»', (tester) async {
      await montarHoja(
        tester,
        entrada: dia.add(const Duration(hours: 14)),
        salida: null,
        inferida: false,
      );
      expect(find.byKey(ClavesEntrevista.duracion), findsNothing);
      expect(find.textContaining('Elegir'), findsWidgets);
    });

    testWidgets('R·07 (entrada inferida) con las dos horas válidas: sin «Duración», con el aviso', (
      tester,
    ) async {
      await montarHoja(
        tester,
        entrada: dia.add(const Duration(hours: 14, minutes: 10)),
        salida: dia.add(const Duration(hours: 14, minutes: 40)),
        inferida: true,
      );
      expect(find.byKey(ClavesEntrevista.duracion), findsNothing);
      expect(find.byKey(ClavesEntrevista.avisoSinInicio), findsOneWidget);
      expect(find.text('30 min'), findsNothing);
    });

    for (final escala in [1.0, 2.0]) {
      for (final tamano in [_chico, _grande]) {
        testWidgets(
          'R·07 · ${_suf(tamano, escala)}: sin desborde, ni texto cortado, guías de toque',
          (tester) async {
            await montarHoja(
              tester,
              entrada: dia.add(const Duration(hours: 14, minutes: 10)),
              salida: dia.add(const Duration(hours: 14, minutes: 40)),
              inferida: true,
              tamano: tamano,
              escala: escala,
            );
            expect(tester.takeException(), isNull);
            sinTextoCortado(tester);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          },
        );
      }
    }
  });

  group('R·06: el rechazo de una jornada que ya no está', () {
    testWidgets(
      'la hoja muestra el texto de «jornada inexistente» (qué pasó y qué hacer), no «Revisá los '
      'datos ingresados»',
      (tester) async {
        final r = await llegar(tester, Estado39.r06);
        // Lo que devuelve el repositorio real (`_correr`): el texto del motivo, en `campos` y en `mensaje`.
        r.montaje.agenda.falla = FailureValidacion(
          campos: {
            MotivoRechazoAgenda.jornadaInexistente.campo:
                MotivoRechazoAgenda.jornadaInexistente.mensaje,
          },
          mensaje: MotivoRechazoAgenda.jornadaInexistente.mensaje,
        );
        await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));
        expect(
          find.text(MotivoRechazoAgenda.jornadaInexistente.mensaje),
          findsOneWidget,
          reason: 'la hoja dice: ${_textoDelAviso(tester)}',
        );
      },
    );
  });

  // ═════════════════════════ 4 · RÓTULO «OPCIONAL» Y «+ AGENDAR» ═════════════════════════
  group('Rótulo «OPCIONAL» de la nota (R·05) a 200 %', () {
    for (final tamano in [_chico, _grande]) {
      for (final escala in [1.0, 1.5, 2.0]) {
        testWidgets(
          'el rótulo se lee entero, sin «…», con la nota vacía y con texto · ${_suf(tamano, escala)}',
          (tester) async {
            await llegar(tester, Estado39.r05Nota, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull);
            final rotulo = find.textContaining('OPCIONAL', findRichText: true);
            expect(rotulo, findsOneWidget);
            final parrafo = tester.renderObject<RenderParagraph>(
              find.descendant(of: find.byKey(ClavesEntrevista.campoNota), matching: rotulo),
            );
            expect(parrafo.didExceedMaxLines, isFalse, reason: 'rótulo cortado');
            expect(parrafo.text.toPlainText(), TextosEntrevista.campoNota);
            await capturar(tester, 'rotulo_nota_${_suf(tamano, escala)}');
          },
        );
      }
    }

    testWidgets(
      'el campo enfocado y vacío a 360×640 ×2: el rótulo flotante no se pisa con el texto',
      (tester) async {
        await llegar(tester, Estado39.r05, tamano: _chico, escala: 2);
        await tocar(tester, find.byKey(ClavesEntrevista.botonNota));
        await tester.tap(find.byKey(ClavesEntrevista.campoNota));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(ClavesEntrevista.campoNota), 'Volver a las seis');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capturar(tester, 'rotulo_nota_enfocado_360x640_x2');
        final campo = tester.getRect(find.byKey(ClavesEntrevista.campoNota));
        final rotulo = tester.getRect(find.textContaining('OPCIONAL', findRichText: true));
        expect(rotulo.left, greaterThanOrEqualTo(campo.left));
        expect(rotulo.right, lessThanOrEqualTo(campo.right));
      },
    );
  });

  group('Rótulo de la nota: aire entre sus renglones y la nota', () {
    testWidgets(
      'a 360×640 ×2 el rótulo flotante (en dos renglones) queda arriba del texto de la nota, sin '
      'tocarlo',
      (tester) async {
        await llegar(tester, Estado39.r05Nota, tamano: _chico, escala: 2);
        final rotulo = tester.getRect(find.textContaining('OPCIONAL', findRichText: true));
        final texto = tester.getRect(
          find.descendant(
            of: find.byKey(ClavesEntrevista.campoNota),
            matching: find.byType(EditableText),
          ),
        );
        expect(
          rotulo.bottom,
          lessThanOrEqualTo(texto.top),
          reason: 'rótulo en $rotulo y la nota empieza en ${texto.top}',
        );
      },
      skip:
          !_hallazgos, // skip: QA #538 — el rótulo de dos renglones toca el texto de la nota a 200 %.
    );
  });

  group('Capturas de R·06 y R·07 a 360×640 ×2', () {
    for (final e in [Estado39.r06, Estado39.r07, Estado39.r07SinVisita]) {
      testWidgets(e.rotulo, (tester) async {
        await llegar(tester, e, tamano: _chico, escala: 2);
        expect(tester.takeException(), isNull);
        await capturar(tester, '538_${e.id}_360x640_x2');
      });
    }
  });

  group('«+ Agendar» del vacío (23B·07) a 200 % y 360×640', () {
    for (final tamano in [_chico, _grande]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('aire a los lados, un solo renglón y 48 dp de alto · ${_suf(tamano, escala)}', (
          tester,
        ) async {
          await a148.llegarA(tester, a148.Estado148.e07, tamano: tamano, escala: escala);
          expect(tester.takeException(), isNull);
          final boton = find.widgetWithText(OutlinedButton, '+ Agendar');
          await tester.ensureVisible(boton);
          final rb = tester.getRect(boton);
          final texto = tester.getRect(
            find.descendant(of: boton, matching: find.text('+ Agendar')),
          );
          expect(rb.height, greaterThanOrEqualTo(48));
          expect(rb.width - texto.width, greaterThanOrEqualTo(24));
          expect(
            texto.height,
            lessThan(40 * escala),
            reason: 'el texto no se parte en dos renglones',
          );
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await a148.capturar(tester, 'qa538_mas_agendar_${_suf(tamano, escala)}');
        });
      }
    }
  });
}

/// El texto del aviso de error de la hoja de término (para el motivo de un fallo).
String _textoDelAviso(WidgetTester tester) {
  final aviso = find.byKey(ClavesEntrevista.avisoError);
  if (aviso.evaluate().isEmpty) return '(sin aviso)';
  return [
    for (final w in find.descendant(of: aviso, matching: find.byType(Text)).evaluate())
      (w.widget as Text).data ?? '',
  ].join('|');
}
