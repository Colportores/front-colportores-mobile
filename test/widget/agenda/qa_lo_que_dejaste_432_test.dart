// QA de #432 / #608: el paso «Lo que dejaste» de la hoja «Terminó la entrevista» (vista 39 R·06 →
// 42B·08). Matriz 360×640 / 412×915 × 1,0 / 2,0 con las fuentes reales, guías de toque y etiquetas,
// el aviso de error, y los textos literales del artboard 42B·08 (los hallazgos que siguen abiertos
// van con `skip`, `--dart-define=QA_HALLAZGOS=true` los corre).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/misionero_dejado.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_termino_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_venta_432_arnes.dart';

final _entrada = DateTime(2026, 10, 23, 14, 23);
final _salida = DateTime(2026, 10, 23, 14, 41);

const _camino = MisioneroParaDejar(productoId: 'p-camino', nombre: 'El camino a Cristo');
const _esperanza = MisioneroParaDejar(productoId: 'p-esperanza', nombre: 'La gran esperanza');
const _familia = MisioneroParaDejar(productoId: 'p-familia', nombre: 'Esperanza para la familia');
const _largos = [
  MisioneroParaDejar(
    productoId: 'p-1',
    nombre: 'El conflicto de los siglos: edición ilustrada con comentarios para la familia',
  ),
  MisioneroParaDejar(productoId: 'p-2', nombre: 'Patriarcas y profetas'),
  MisioneroParaDejar(productoId: 'p-3', nombre: 'Los hechos de los apóstoles'),
  MisioneroParaDejar(productoId: 'p-4', nombre: 'El deseado de todas las gentes'),
  MisioneroParaDejar(productoId: 'p-5', nombre: 'Mensajes para los jóvenes'),
  MisioneroParaDejar(productoId: 'p-6', nombre: 'Consejos sobre salud y alimentación'),
];

void main() {
  usarFuentesReales = true;
  var guardados = 0;
  Future<Failure?> Function(Map<String, int>) alGuardar = (m) async => null;
  Completer<void>? compuerta;

  setUp(() {
    guardados = 0;
    compuerta = null;
    alGuardar = (m) async => null;
  });

  Future<void> montar(
    WidgetTester tester, {
    Size tamano = telefonoChico,
    double escala = 1,
    List<MisioneroParaDejar> misioneros = const [_camino, _esperanza, _familia],
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => mostrarHojaTerminoEntrevista(
                  context,
                  direccion: 'Grecia 3305',
                  persona: 'Rosa Díaz',
                  entrada: _entrada,
                  salida: _salida,
                  entradaInferida: false,
                  reloj: () => _salida,
                  misioneros: misioneros,
                  alGuardar: (e, s, m) async {
                    guardados++;
                    if (compuerta case final c?) await c.future;
                    return alGuardar(m);
                  },
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  /// «No hubo venta» (42B·08A → 08B).
  Future<void> alPaso2(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));
    await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
    await tester.pumpAndSettle();
  }

  Future<void> unoMas(WidgetTester tester, MisioneroParaDejar m, {int veces = 1}) async {
    for (var i = 0; i < veces; i++) {
      final mas = find.byTooltip('Uno más de ${m.nombre}');
      await tester.ensureVisible(mas);
      await tester.pumpAndSettle();
      await tester.tap(mas);
      await tester.pump();
    }
  }

  Future<void> guias(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  }

  for (final tamano in tamanos) {
    for (final escala in escalas) {
      final cual = '${tamano.width.toInt()}×${tamano.height.toInt()} ×$escala';
      group('matriz $cual', () {
        testWidgets('R·06 (paso 1) sin desborde y con las guías de toque', (tester) async {
          final h = tester.ensureSemantics();
          await montar(tester, tamano: tamano, escala: escala);
          expect(tester.takeException(), isNull);
          await guias(tester);
          await capturar(tester, 'horas_${tamano.width.toInt()}_$escala');
          h.dispose();
        });

        testWidgets('paso 2 vacío', (tester) async {
          final h = tester.ensureSemantics();
          await montar(tester, tamano: tamano, escala: escala);
          await alPaso2(tester);
          expect(tester.takeException(), isNull);
          expect(find.text(TextosEntrevista.loQueDejasteTitulo), findsOneWidget);
          await guias(tester);
          await capturar(tester, 'vacio_${tamano.width.toInt()}_$escala');
          h.dispose();
        });

        testWidgets('paso 2 con 6 títulos (uno de nombre largo) y 3 elegidos', (tester) async {
          final h = tester.ensureSemantics();
          await montar(tester, tamano: tamano, escala: escala, misioneros: _largos);
          await alPaso2(tester);
          await unoMas(tester, _largos[0], veces: 2);
          await unoMas(tester, _largos[5]);
          expect(tester.takeException(), isNull);
          await guias(tester);
          await capturar(tester, 'largos_${tamano.width.toInt()}_$escala');
          h.dispose();
        });

        testWidgets('paso 2 con el aviso de error de guardado', (tester) async {
          final h = tester.ensureSemantics();
          alGuardar = (m) async => const FailureInesperado();
          await montar(tester, tamano: tamano, escala: escala, misioneros: _largos);
          await alPaso2(tester);
          await unoMas(tester, _largos[1]);
          await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarLoQueDejaste));
          await tester.tap(find.byKey(ClavesEntrevista.guardarLoQueDejaste));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(ClavesEntrevista.avisoError), findsOneWidget);
          await guias(tester);
          await capturar(tester, 'error_${tamano.width.toInt()}_$escala');
          h.dispose();
        });
      });
    }
  }

  group('el aviso de error', () {
    testWidgets('se anuncia como región viva y el botón vuelve a estar habilitado', (tester) async {
      final h = tester.ensureSemantics();
      alGuardar = (m) async => const FailureInesperado();
      await montar(tester);
      await alPaso2(tester);
      await unoMas(tester, _camino);
      await tester.tap(find.byKey(ClavesEntrevista.guardarLoQueDejaste));
      await tester.pumpAndSettle();

      final nodo = tester.getSemantics(find.byKey(ClavesEntrevista.avisoError));
      var viva = nodo.getSemanticsData().flagsCollection.isLiveRegion;
      void buscar(SemanticsNode n) {
        if (n.getSemanticsData().flagsCollection.isLiveRegion) viva = true;
        n.visitChildren((c) {
          buscar(c);
          return true;
        });
      }

      buscar(nodo);
      expect(viva, isTrue, reason: 'el error de guardar se anuncia al lector');
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(ClavesEntrevista.guardarLoQueDejaste))
            .onPressed,
        isNotNull,
      );
      h.dispose();
    });

    // skip: QA #432 — a 360×640 ×2 el aviso rojo (226 dp) aparece entre la lista y «Guardar»: queda
    // cortado (bottom 736 > 640) y el botón de reintento, fuera de la pantalla.
    testWidgets(
      'tras fallar, el aviso y el botón de reintento quedan a la vista (360×640 ×2)',
      (tester) async {
        alGuardar = (m) async => const FailureInesperado();
        await montar(tester, tamano: telefonoChico, escala: 2, misioneros: _largos);
        await alPaso2(tester);
        await unoMas(tester, _largos[1]);
        await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarLoQueDejaste));
        await tester.tap(find.byKey(ClavesEntrevista.guardarLoQueDejaste));
        await tester.pumpAndSettle();

        final pantalla = Offset.zero & telefonoChico;
        final aviso = tester.getRect(find.byKey(ClavesEntrevista.avisoError));
        final boton = tester.getRect(find.byKey(ClavesEntrevista.guardarLoQueDejaste));
        expect(
          pantalla.contains(aviso.topLeft) && pantalla.contains(aviso.bottomRight),
          isTrue,
          reason: 'aviso $aviso',
        );
        expect(
          pantalla.contains(boton.topLeft) && pantalla.contains(boton.bottomRight),
          isTrue,
          reason: 'botón $boton',
        );
      },
      skip: !verHallazgos,
    );
  });

  group('casos límite', () {
    testWidgets('un segundo toque en «Guardar» con el primero en vuelo no guarda dos veces', (
      tester,
    ) async {
      compuerta = Completer<void>();
      await montar(tester);
      await alPaso2(tester);
      await unoMas(tester, _camino, veces: 2);
      await tester.tap(find.byKey(ClavesEntrevista.guardarLoQueDejaste));
      await tester.pump();
      await tester.tap(find.byKey(ClavesEntrevista.guardarLoQueDejaste), warnIfMissed: false);
      await tester.pump();

      expect(guardados, 1);
      compuerta!.complete();
      await tester.pumpAndSettle();
      expect(guardados, 1);
    });

    testWidgets('«No dejé nada» en vuelo no se puede tocar y no pierde lo anotado', (tester) async {
      compuerta = Completer<void>();
      await montar(tester);
      await alPaso2(tester);
      await unoMas(tester, _camino, veces: 3);
      await tester.tap(find.byKey(ClavesEntrevista.guardarLoQueDejaste));
      await tester.pump();
      await tester.tap(find.byKey(ClavesEntrevista.noDejeNada), warnIfMissed: false);
      await tester.pump();

      expect(find.byKey(ClavesEntrevista.loQueDejaste), findsOneWidget);
      expect(guardados, 1);
      compuerta!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('un misionero a 999 no pasa de 999 aunque se siga tocando', (tester) async {
      await montar(tester, misioneros: const [_camino]);
      await alPaso2(tester);
      final mas = find.byTooltip('Uno más de ${_camino.nombre}');
      for (var i = 0; i < 1005; i++) {
        await tester.tap(mas, warnIfMissed: false);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text(TextosEntrevista.dejas(999)), findsOneWidget);
    });

    testWidgets('el título del paso es un encabezado y el hint de cada fila dice cuántos', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await montar(tester);
      await alPaso2(tester);
      await unoMas(tester, _camino, veces: 2);

      expect(
        tester.getSemantics(find.text(TextosEntrevista.loQueDejasteTitulo)),
        isSemantics(isHeader: true),
      );
      expect(find.bySemanticsLabel(RegExp('El camino a Cristo.*2')), findsWidgets);
      h.dispose();
    });
  });

  group('42B·08 · textos literales del artboard', () {
    // QA #432 — 42B·08B/C: el pie lleva «Guardar» (apagado sin nada elegido) y «No dejé nada».
    testWidgets('el pie tiene «Guardar» y «No dejé nada»', (tester) async {
      await montar(tester);
      await alPaso2(tester);

      expect(find.text('Guardar'), findsOneWidget);
      expect(find.text('No dejé nada'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(ClavesEntrevista.guardarLoQueDejaste))
            .onPressed,
        isNull,
      );
    });

    // QA #432 — 42B·08B: sin nada elegido dice «Sumá lo que dejaste o tocá «No dejé nada».».
    testWidgets('vacío: «Sumá lo que dejaste o tocá «No dejé nada».»', (tester) async {
      await montar(tester);
      await alPaso2(tester);

      expect(find.text('Sumá lo que dejaste o tocá «No dejé nada».'), findsOneWidget);
    });

    // QA #432 — 42B·08C: con 3 elegidos dice «Dejás 3 misioneros. No es una venta: no lleva
    // talonario ni monto.» y la ayuda de arriba es «Grecia 3305 · Rosa Díaz. A colaboración, sin precio.».
    testWidgets('con 3 elegidos: «Dejás 3 misioneros. No es una venta…»', (tester) async {
      await montar(tester);
      await alPaso2(tester);
      await unoMas(tester, _camino, veces: 2);
      await unoMas(tester, _esperanza);

      expect(
        find.text('Dejás 3 misioneros. No es una venta: no lleva talonario ni monto.'),
        findsOneWidget,
      );
      expect(find.text('Grecia 3305 · Rosa Díaz. A colaboración, sin precio.'), findsOneWidget);
    });
  });
}
