// QA de la vista 30 A (plan de cuotas, HU-COB-004, #166): matriz de estados × tamaños × escala con
// las guías de accesibilidad, entradas hostiles, fallas a mitad de la acción y los textos del canvas.
// Los casos que documentan un hallazgo van con `skip` mientras no se arreglen;
// `--dart-define=QA_HALLAZGOS=true` los corre.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/cuotas_arnes.dart';
import '../../helpers/plan_de_cuotas_arnes.dart';

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');
const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

// skip: QA #166 — «Modificar cuotas» con letra grande: la fila abierta se arma con un contador
// (`abierta++`) dentro del `Builder` de una lista perezosa; al construirse fuera de orden o de nuevo
// el índice se pasa (RangeError) o apunta a otro campo.
const _conHallazgo = {'modificar editada · 360x640 · ×2.0'};

typedef _Preparar = Future<void> Function(WidgetTester tester, ArnesCuotas arnes);

class _Estado {
  const _Estado(this.nombre, this.pantalla, this.plan, [this.despues, this.ahora]);

  final String nombre;
  final PantallaDeCuotas pantalla;
  final PlanDeCuotasEnMemoria Function() plan;
  final _Preparar? despues;
  final DateTime? ahora;
}

PlanDeCuotasEnMemoria _conUnaPagadaYUnaParcial() => PlanDeCuotasEnMemoria(
  montoCentavos: 250000,
  cobradoCentavos: 83300 + 40000,
  cuotas: [
    cuotaDe(1, dia: 26, mes: 10, monto: 83300, cubierta: true),
    cuotaDe(2, dia: 2, monto: 83300, pagado: 40000),
    cuotaDe(3, dia: 9, monto: 83400),
  ],
);

PlanDeCuotasEnMemoria _paraModificar() => PlanDeCuotasEnMemoria(
  montoCentavos: 250000,
  cobradoCentavos: 83300,
  cuotas: [
    cuotaDe(1, dia: 26, mes: 10, monto: 83300, cubierta: true),
    cuotaDe(2, dia: 2, monto: 100000),
    cuotaDe(3, dia: 9, monto: 66700),
  ],
);

final _estados = <_Estado>[
  const _Estado('30A-01 plan', PantallaDeCuotas.plan, PlanDeCuotasEnMemoria.new),
  _Estado('30A-02 mensual', PantallaDeCuotas.plan, PlanDeCuotasEnMemoria.new, (t, a) async {
    await tocarEnCuotas(t, find.byKey(const Key('cuotas_menos')));
    await tocarEnCuotas(t, find.text('Mensual'));
  }),
  _Estado('30A-02B editada', PantallaDeCuotas.plan, PlanDeCuotasEnMemoria.new, (t, a) async {
    await escribirCuota(t, 0, '900');
  }),
  _Estado('30A-02C supera el saldo', PantallaDeCuotas.plan, PlanDeCuotasEnMemoria.new, (
    t,
    a,
  ) async {
    await escribirCuota(t, 0, '2600');
  }),
  _Estado('plan de 12 cuotas', PantallaDeCuotas.plan, PlanDeCuotasEnMemoria.new, (t, a) async {
    for (var i = 0; i < 9; i++) {
      await tocarEnCuotas(t, find.byKey(const Key('cuotas_mas')));
    }
  }),
  _Estado('30A-08 error al crear', PantallaDeCuotas.plan, PlanDeCuotasEnMemoria.new, (t, a) async {
    a.plan.fallaAlCrear = const FailurePlanNoGuardado();
    await tocarEnCuotas(t, botonPrincipal);
  }),
  _Estado('creando', PantallaDeCuotas.plan, PlanDeCuotasEnMemoria.new, (t, a) async {
    a.plan.retenerElCrear = Completer<void>();
    addTearDown(() {
      if (!a.plan.retenerElCrear!.isCompleted) a.plan.retenerElCrear!.complete();
    });
    await t.tap(botonPrincipal);
    await t.pump(const Duration(milliseconds: 100));
  }),
  _Estado(
    '30A-07 plan sin saldo',
    PantallaDeCuotas.plan,
    () => PlanDeCuotasEnMemoria(cobradoCentavos: 250000),
  ),
  const _Estado('plan con cuotas ya armadas', PantallaDeCuotas.plan, _conUnaPagadaYUnaParcial),
  const _Estado('30A-04 lista', PantallaDeCuotas.lista, _conUnaPagadaYUnaParcial),
  _Estado(
    '30A-06 lista con vencida',
    PantallaDeCuotas.lista,
    _conUnaPagadaYUnaParcial,
    null,
    DateTime(2026, 11, 5, 9),
  ),
  _Estado(
    '30A-07 lista sin saldo',
    PantallaDeCuotas.lista,
    () => PlanDeCuotasEnMemoria(cobradoCentavos: 250000),
  ),
  const _Estado('lista sin plan', PantallaDeCuotas.lista, PlanDeCuotasEnMemoria.new),
  const _Estado('30A-09 modificar con pagada', PantallaDeCuotas.modificar, _paraModificar),
  _Estado('modificar editada', PantallaDeCuotas.modificar, _paraModificar, (t, a) async {
    await escribirCuota(t, 2, '1200');
  }),
  _Estado(
    'modificar todas pagadas',
    PantallaDeCuotas.modificar,
    () => PlanDeCuotasEnMemoria(
      montoCentavos: 250000,
      cobradoCentavos: 100000,
      cuotas: [
        cuotaDe(1, dia: 26, mes: 10, monto: 50000, cubierta: true),
        cuotaDe(2, dia: 2, monto: 50000, cubierta: true),
      ],
    ),
  ),
  _Estado('error de lectura', PantallaDeCuotas.lista, () {
    return PlanDeCuotasEnMemoria()..fallaAlLeer = true;
  }),
  _Estado('venta ausente', PantallaDeCuotas.plan, () {
    return PlanDeCuotasEnMemoria()..ventaAusente = true;
  }),
];

// Con las fuentes de prueba (Ahem) todo ancho es falso: las medidas de texto usan las reales.
Future<void> fuentes(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await c.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final bytes = iconos.readAsBytesSync();
        final c = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(bytes.buffer)));
        await c.load();
        break;
      }
    }
  });
}

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

Future<ArnesCuotas> _llegarA(
  WidgetTester tester,
  _Estado e, {
  required Size tamano,
  required double escala,
}) async {
  final arnes = await montarCuotas(
    tester,
    pantalla: e.pantalla,
    plan: e.plan(),
    tamano: tamano,
    escala: escala,
    abrir: false,
  );
  if (e.ahora != null) arnes.ahora = e.ahora!;
  await abrirCuotas(tester);
  if (e.despues != null) await e.despues!(tester, arnes);
  return arnes;
}

void main() {
  const tamanos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};
  const escalas = [1.0, 2.0];

  group('matriz: cada estado × tamaño × escala, sin overflow y con las guías', () {
    for (final e in _estados) {
      for (final t in tamanos.entries) {
        for (final escala in escalas) {
          final nombre = '${e.nombre} · ${t.key} · ×$escala';
          testWidgets(nombre, (tester) async {
            await _llegarA(tester, e, tamano: t.value, escala: escala);
            expect(tester.takeException(), isNull);
            await _guias(tester);
          }, skip: _conHallazgo.contains(nombre) && !_hallazgos);
        }
      }
    }
  });

  group('entradas hostiles en el monto de una cuota (30A-02)', () {
    const entradas = [
      '',
      '   ',
      '0',
      '-5',
      '1e3',
      'abc',
      '😀',
      '٣٣٣',
      '1.2.3',
      r'$ 900',
      '833,5',
      '833,555',
      '99999999999999',
      '12345678901234567890',
      '900\n',
      'DROP TABLE',
    ];
    for (final texto in entradas) {
      testWidgets('«${texto.replaceAll('\n', r'\n')}»: no rompe y nunca crea cuotas inválidas', (
        tester,
      ) async {
        final arnes = await montarCuotas(tester);
        await escribirCuota(tester, 1, texto);
        expect(tester.takeException(), isNull);
        if (elBotonPrincipal(tester).onPressed != null) {
          await tocarEnCuotas(tester, botonPrincipal);
          final montos = arnes.plan.ultimoPlan!.cuotas.map((c) => c.montoCentavos).toList();
          expect(montos.every((m) => m > 0), isTrue, reason: '$montos');
          expect(montos.fold<int>(0, (a, b) => a + b) <= 250000, isTrue, reason: '$montos');
        }
      });
    }

    testWidgets('campo vacío: dice qué falta y apaga el botón', (tester) async {
      await montarCuotas(tester);
      await escribirCuota(tester, 0, '');
      expect(find.text('Ingresá el monto de la cuota.'), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNull);
    });

    testWidgets('texto pegado muy largo: el campo lo corta a 14 caracteres', (tester) async {
      await montarCuotas(tester);
      await escribirCuota(tester, 0, '1' * 200);
      expect(
        tester.widget<TextField>(campoDeCuota(0)).controller!.text.length,
        lessThanOrEqualTo(14),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('falla a mitad de la acción', () {
    testWidgets('crear: el botón vuelve, lo tipeado queda y el reintento crea el plan editado', (
      tester,
    ) async {
      final arnes = await montarCuotas(tester);
      await escribirCuota(tester, 0, '900');
      arnes.plan.fallaAlCrear = const FailurePlanNoGuardado();
      await tocarEnCuotas(tester, botonPrincipal);

      expect(find.text('No pudimos crear el plan. No se agendó ninguna cobranza.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNotNull);
      expect([for (var i = 0; i < 3; i++) textoDeCuota(tester, i)], ['900', r'$ 800', r'$ 800']);

      await tocarEnCuotas(tester, botonPrincipal);
      expect(arnes.plan.ultimoPlan!.cuotas.map((c) => c.montoCentavos), [90000, 80000, 80000]);
      expect(paginaLista, findsOneWidget);
    });

    testWidgets('crear: tras la falla se cambia la cantidad y el reintento agenda esa cantidad', (
      tester,
    ) async {
      final arnes = await montarCuotas(tester);
      arnes.plan.fallaAlCrear = const FailurePlanNoGuardado();
      await tocarEnCuotas(tester, botonPrincipal);
      await tocarEnCuotas(tester, find.byKey(const Key('cuotas_mas')));
      expect(find.text('No pudimos crear el plan. No se agendó ninguna cobranza.'), findsNothing);
      await tocarEnCuotas(tester, botonPrincipal);

      expect(arnes.plan.pedidosDeCrear, 2);
      expect(arnes.plan.ultimoPlan!.cuotas, hasLength(4));
      expect(arnes.plan.actual.cuotas, hasLength(4));
      expect(arnes.telefono.recordatorios.programados, hasLength(4));
    });

    testWidgets('crear: el aviso queda a la vista aunque se haya bajado la pantalla (360×640 ×2)', (
      tester,
    ) async {
      final arnes = await montarCuotas(tester, tamano: const Size(360, 640), escala: 2);
      await traerCuotaAlAlcance(tester, campoDeCuota(2));
      arnes.plan.fallaAlCrear = const FailurePlanNoGuardado();
      await tester.tap(botonPrincipal);
      await asentarAgendar(tester);
      final aviso = find.byKey(const Key('cuotas_error'));
      expect(aviso, findsOneWidget);
      final r = tester.getRect(aviso);
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(640));
    });

    testWidgets('modificar: falla, el botón vuelve, lo tipeado queda y el reintento guarda', (
      tester,
    ) async {
      final arnes = await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.modificar,
        plan: _paraModificar(),
      );
      await escribirCuota(tester, 2, '1200');
      arnes.plan.fallaAlModificar = const FailureCuotasNoGuardadas();
      await tocarEnCuotas(tester, botonPrincipal);

      expect(find.byKey(const Key('cuotas_error')), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNotNull);
      expect(textoDeCuota(tester, 2), '1200');

      await tocarEnCuotas(tester, botonPrincipal);
      expect(arnes.plan.pedidosDeModificar, 2);
      expect(arnes.resultados, [true]);
    });

    testWidgets('modificar: el aviso de la falla queda a la vista a 360×640 ×2', (tester) async {
      final arnes = await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.modificar,
        plan: _paraModificar(),
        tamano: const Size(360, 640),
        escala: 2,
      );
      await escribirCuota(tester, 2, '1200');
      await traerCuotaAlAlcance(tester, campoDeCuota(3));
      arnes.plan.fallaAlModificar = const FailureCuotasNoGuardadas();
      await tester.tap(botonPrincipal);
      await asentarAgendar(tester);
      final r = tester.getRect(find.byKey(const Key('cuotas_error')));
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(640));
    }, skip: !_hallazgos);
  });

  group('modificar cuotas (30A-09)', () {
    testWidgets('un monto menor a lo ya cobrado de la cuota se marca y apaga el botón', (
      tester,
    ) async {
      await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.modificar,
        plan: PlanDeCuotasEnMemoria(
          montoCentavos: 250000,
          cobradoCentavos: 123300,
          cuotas: [
            cuotaDe(1, dia: 26, mes: 10, monto: 83300, cubierta: true),
            cuotaDe(2, dia: 2, monto: 83300, pagado: 40000),
            cuotaDe(3, dia: 9, monto: 83400),
          ],
        ),
      );
      await escribirCuota(tester, 2, '300');
      expect(find.text('No puede ser menos de lo que ya se cobró de esta cuota.'), findsOneWidget);
      expect(elBotonPrincipal(tester).onPressed, isNull);
    });

    testWidgets('sin cambios el botón está apagado y volver no pregunta', (tester) async {
      final arnes = await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.modificar,
        plan: _paraModificar(),
      );
      expect(elBotonPrincipal(tester).onPressed, isNull);
      await escribirCuota(tester, 2, '1200');
      await escribirCuota(tester, 2, '1000');
      expect(elBotonPrincipal(tester).onPressed, isNull);
      await tester.tap(volverDeCuotas);
      await asentarAgendar(tester);
      expect(find.text('Descartar'), findsNothing);
      expect(arnes.resultados, [false]);
    });

    testWidgets('la cuota pagada no tiene campo editable', (tester) async {
      await montarCuotas(tester, pantalla: PantallaDeCuotas.modificar, plan: _paraModificar());
      expect(find.text('Ya está pagada: no cambia.'), findsOneWidget);
      expect(campoDeCuota(1), findsNothing);
    });
  });

  group('hallazgos', () {
    // skip: QA #166 — P5 (decisión del 29/10) sin aplicar: la lista dice «Pagada el 26/10» sin
    // «· efectivo», como pide el canvas 30A-04 y la decisión; la fecha sale de la última edición de la
    // cita (`cubiertaEl`), no del cobro que la completó.
    testWidgets(
      'dada una cuota pagada en efectivo, cuando se abre la lista, dice «Pagada el 26/10 · efectivo» (30A-04, P5)',
      (tester) async {
        await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.lista,
          plan: _conUnaPagadaYUnaParcial(),
        );
        expect(find.text('Pagada el 26/10 · efectivo'), findsOneWidget);
      },
      skip: !_hallazgos,
    );
  });

  testWidgets(
    'modificar con 8 cuotas abiertas en 360×640: escribir en la 1.ª, bajar y escribir en la última no cruza los campos',
    (tester) async {
      final plan = PlanDeCuotasEnMemoria(
        montoCentavos: 800000,
        cuotas: [for (var n = 1; n <= 8; n++) cuotaDe(n, dia: n, monto: 100000)],
      );
      await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.modificar,
        plan: plan,
        tamano: const Size(360, 640),
      );
      await escribirCuota(tester, 1, '1500');
      await traerCuotaAlAlcance(tester, campoDeCuota(8));
      await tester.enterText(campoDeCuota(8), '777');
      await asentarAgendar(tester, 3);
      expect(tester.takeException(), isNull);
      expect(textoDeCuota(tester, 8), '777');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      await asentarAgendar(tester, 3);
      expect(textoDeCuota(tester, 1), '1500');
      expect(tester.takeException(), isNull);
    },
  );

  group('el monto de la cuota se ve entero (no «\$ 1.0» por «\$ 1.000»)', () {
    Future<List<int>> recortados(WidgetTester tester, Iterable<int> filas) async {
      final cortados = <int>[];
      await fuentes(tester);
      for (final i in filas) {
        await traerCuotaAlAlcance(tester, campoDeCuota(i));
        final estado = tester.state<EditableTextState>(
          find.descendant(of: campoDeCuota(i), matching: find.byType(EditableText)),
        );
        if (estado.renderEditable.maxScrollExtent > 4) cortados.add(i);
      }
      return cortados;
    }

    for (final escala in escalas) {
      testWidgets(
        '«Pagar en cuotas» con un saldo de \$ 45.000 a 360×640 ×$escala',
        (tester) async {
          await montarCuotas(
            tester,
            plan: PlanDeCuotasEnMemoria(montoCentavos: 4500000),
            tamano: const Size(360, 640),
            escala: escala,
          );
          expect(await recortados(tester, [0, 1, 2]), isEmpty);
        },
        skip: escala > 1 && !_hallazgos,
      );

      testWidgets('«Modificar cuotas» con montos de \$ 1.000 a 360×640 ×$escala', (tester) async {
        await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.modificar,
          plan: _paraModificar(),
          tamano: const Size(360, 640),
          escala: escala,
        );
        expect(await recortados(tester, [2, 3]), isEmpty);
      }, skip: escala > 1 && !_hallazgos);
    }
  });

  // Capturas (solo con `--dart-define=QA_CAPTURAS=true`; van a `.dart_tool/qa_capturas_579/`, nunca
  // al repo) con las fuentes reales del proyecto.
  group('capturas', () {
    for (final e in _estados) {
      for (final t in tamanos.entries) {
        for (final escala in escalas) {
          testWidgets('captura ${e.nombre} · ${t.key} · ×$escala', (tester) async {
            await fuentes(tester);
            await _llegarA(tester, e, tamano: t.value, escala: escala);
            tester.takeException();
            await tester.runAsync(() async {
              final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
              final img = await capa.toImage(Offset.zero & t.value);
              final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
              final nombre = '${e.nombre} ${t.key} x$escala'.replaceAll(
                RegExp(r'[^A-Za-z0-9 ._x-]'),
                '',
              );
              final dir = Directory('.dart_tool/qa_capturas_579')..createSync(recursive: true);
              File('${dir.path}/$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
            });
          });
        }
      }
    }
  }, skip: !_conCapturas);
}
