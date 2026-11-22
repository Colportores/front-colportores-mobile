// HU-UBI-013 (#145), vista 22 grupo A: la sección «COBRANZA» de la ficha de la persona (22A·01, 22A·06,
// 22A·07, 22A·08, 22A·09 y 22A·10) y su camino al selector. El selector va en
// `ubicacion_alternativa_selector_145_test.dart`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ficha_persona_arnes.dart';

void main() {
  final italia = ubicacionParaAlternativa('ub-2');
  final italiaDeBaja = ubicacionParaAlternativa('ub-2', deletedAt: DateTime(2026, 10, 20));
  final casaCercana = ubicacionParaAlternativa(
    'ub-3',
    calle: 'Mataojo',
    numero: '2051',
    tipo: TipoUbicacion.casa,
  );

  const alto = Size(390, 1700);

  /// María en el depto 3B de Mataojo 2044 (el canvas 32B·01) con sus ubicaciones para elegir.
  MundoFicha mundo({
    EstadoUbicacionAlternativa estado = const SinUbicacionAlternativa(),
    List<Ubicacion>? candidatas,
    bool deBaja = false,
  }) {
    final m = deBaja
        ? MundoFicha(
            persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
            historial: historialDelCanvas(),
            contexto: contextoBajaDesde22(),
          )
        : MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha());
    m.alternativas
      ..ponerEstado(estado)
      ..ponerCandidatas(candidatas ?? [italia, casaCercana]);
    return m;
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await asentar(tester);
  }

  final seccion = find.byKey(ClavesAlternativa.seccion);
  final sin = find.byKey(ClavesAlternativa.sinAlternativa);
  final vigente = find.byKey(ClavesAlternativa.vigente);
  final quitar = find.byKey(ClavesAlternativa.quitar);
  final selector = find.byKey(ClavesAlternativa.selector);

  /// Elige [id] en el selector abierto.
  Future<void> elegirFila(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ClavesAlternativa.fila(id)));
    await asentar(tester);
  }

  group('22A·01 · ficha sin alternativa', () {
    testWidgets('dice «Cobrar en otro lugar» con «Elegir», debajo del historial', (tester) async {
      await montarFicha(tester, mundo(), tamano: alto);

      expect(find.text('COBRANZA'), findsOneWidget);
      expect(find.text('Cobrar en otro lugar'), findsOneWidget);
      expect(
        find.text('Si acepta que le cobres en su trabajo u otra dirección que ya registraste.'),
        findsOneWidget,
      );
      expect(find.text('Elegir'), findsOneWidget);
      // «La ubicación alternativa (vista 22) va debajo del historial» (nota del canvas 32B·01).
      expect(
        tester.getTopLeft(seccion).dy,
        greaterThan(tester.getBottomLeft(find.byKey(ClavesFicha.historial)).dy),
      );
    });

    testWidgets('la tarjeta es un botón de al menos 48 dp que dice qué es', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarFicha(tester, mundo(), tamano: alto);

      expect(tester.getSize(sin).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(sin),
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          label:
              'Cobrar en otro lugar\n'
              'Si acepta que le cobres en su trabajo u otra dirección que ya registraste.\n'
              'Elegir',
        ),
      );
      semantica.dispose();
    });

    testWidgets('mientras se lee, cargando', (tester) async {
      final m = mundo()..alternativas.sinLectura();
      await montarFicha(tester, m, tamano: alto);
      expect(find.byKey(ClavesAlternativa.cargando), findsOneWidget);
      expect(sin, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si no se puede leer, el aviso con «Reintentar» que vuelve a leer', (tester) async {
      final conError = mundo()..alternativas.errorAlObservar = StateError('sin db');
      await montarFicha(tester, conError, tamano: alto);
      expect(find.byKey(ClavesAlternativa.errorLectura), findsOneWidget);
      expect(
        find.text('No pudimos leer dónde se le cobra a María. Probá de nuevo.'),
        findsOneWidget,
      );

      // «Reintentar» vuelve a leer.
      conError.alternativas.errorAlObservar = null;
      await tocar(tester, find.byKey(ClavesAlternativa.reintentarLectura));
      expect(sin, findsOneWidget);
      expect(find.byKey(ClavesAlternativa.errorLectura), findsNothing);
    });
  });

  group('22A·02 → 22A·06 · elegir y vincular', () {
    testWidgets(
      '«Elegir» abre el selector con las ubicaciones del colportor y la del espacio afuera',
      (tester) async {
        final m = mundo();
        await montarFicha(tester, m, tamano: alto);

        await tocar(tester, sin);

        expect(selector, findsOneWidget);
        expect(find.text('¿Dónde le cobrás?'), findsOneWidget);
        expect(m.alternativas.pedidasCandidatas, [(colportorId: 'col-1', espacioId: 'esp-1')]);
      },
    );

    testWidgets('elegir una ubicación la vincula, avisa y deja «SE COBRA ACÁ» con «Quitar»', (
      tester,
    ) async {
      final m = mundo();
      await montarFicha(tester, m, tamano: alto);

      await tocar(tester, sin);
      await elegirFila(tester, 'ub-2');

      expect(m.alternativas.establecidas, ['ub-2']);
      expect(selector, findsNothing);
      expect(
        find.text('Las cobranzas de María se van a proponer en Av. Italia 2810.'),
        findsOneWidget,
      );
      expect(vigente, findsOneWidget);
      expect(find.text('SE COBRA ACÁ'), findsOneWidget);
      expect(find.descendant(of: vigente, matching: find.text('Av. Italia 2810')), findsOneWidget);
      expect(find.descendant(of: vigente, matching: find.text('Negocio')), findsOneWidget);
      expect(quitar, findsOneWidget);
      expect(sin, findsNothing);
    });

    testWidgets('cerrar el selector sin elegir no cambia nada, y se puede volver a abrir', (
      tester,
    ) async {
      final m = mundo();
      await montarFicha(tester, m, tamano: alto);

      await tocar(tester, sin);
      await tester.tap(find.byKey(ClavesAlternativa.selectorCerrar));
      await asentar(tester);

      expect(selector, findsNothing);
      expect(m.alternativas.establecidas, isEmpty);
      expect(sin, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      // Reentrar: el selector abre igual y la ficha sigue en pie.
      await tocar(tester, sin);
      expect(selector, findsOneWidget);
    });

    testWidgets('volver atrás desde la ficha y reentrar la muestra con lo que quedó guardado', (
      tester,
    ) async {
      final m = mundo();
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);
      await elegirFila(tester, 'ub-2');

      await volverAtras(tester);
      expect(find.text('abrir ficha'), findsOneWidget);
      await tester.tap(find.text('abrir ficha'));
      await asentar(tester);

      expect(vigente, findsOneWidget);
      expect(find.text('Av. Italia 2810'), findsOneWidget);
    });

    testWidgets('dos toques seguidos en «Elegir» abren un solo selector', (tester) async {
      await montarFicha(tester, mundo(), tamano: alto);

      await tester.ensureVisible(sin);
      await tester.pump();
      await tester.tap(sin);
      await tester.tap(sin);
      await asentar(tester);
      await tester.tap(find.byKey(ClavesAlternativa.selectorCerrar));
      await asentar(tester);

      // Si se hubieran abierto dos, tras cerrar uno seguiría el otro.
      expect(selector, findsNothing);
      expect(sin, findsOneWidget);
    });

    testWidgets('dos toques seguidos sobre la misma ubicación la guardan una sola vez', (
      tester,
    ) async {
      final m = mundo();
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);

      final fila = find.byKey(ClavesAlternativa.fila('ub-2'));
      await tester.tap(fila);
      await tester.tap(fila);
      await asentar(tester);

      expect(m.alternativas.establecidas, ['ub-2']);
      expect(find.text('abrir ficha'), findsNothing);
      expect(vigente, findsOneWidget);
    });

    testWidgets('mientras se guarda dice «Guardando…» y nada más se puede tocar', (tester) async {
      final m = mundo()..alternativas.compuertaEstablecer = Completer<void>();
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);

      await elegirFila(tester, 'ub-2');

      expect(find.byKey(ClavesAlternativa.guardando), findsOneWidget);
      expect(find.text('Guardando…'), findsOneWidget);
      expect(sin, findsNothing);
      expect(quitar, findsNothing);
      // «+ Agendar cobranza» y el resto de la ficha esperan: un segundo flujo no se abre encima.
      final agendar = find.byKey(ClavesFicha.botonAgendarCobranza);
      if (agendar.evaluate().isNotEmpty) {
        expect(tester.widget<ActionChip>(agendar).onPressed, isNull);
      }

      m.alternativas.compuertaEstablecer!.complete();
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.guardando), findsNothing);
      expect(vigente, findsOneWidget);
    });

    testWidgets('cambiar la alternativa por otra es fijarla de nuevo (desde «Elegir otra»)', (
      tester,
    ) async {
      final m = mundo(estado: UbicacionAlternativaDeBaja('ub-2', ubicacion: italiaDeBaja));
      await montarFicha(tester, m, tamano: alto);

      await tocar(tester, find.byKey(ClavesAlternativa.elegirOtra));
      await elegirFila(tester, 'ub-3');

      expect(m.alternativas.establecidas, ['ub-3']);
      expect(
        find.text('Las cobranzas de María se van a proponer en Mataojo 2051.'),
        findsOneWidget,
      );
      expect(find.byKey(ClavesAlternativa.avisoDeBaja), findsNothing);
    });
  });

  group('22A·10 · sin conexión', () {
    testWidgets('vincula igual y dice «Guardado en tu teléfono.»', (tester) async {
      final m = mundo()..telefono.conexion.tipo = TipoConexion.sinConexion;
      await montarFicha(tester, m, tamano: alto);

      await tocar(tester, sin);
      await elegirFila(tester, 'ub-2');

      expect(m.alternativas.establecidas, ['ub-2']);
      expect(find.text('Guardado en tu teléfono.'), findsOneWidget);
      expect(find.textContaining('se van a proponer'), findsNothing);
      expect(vigente, findsOneWidget);
    });
  });

  group('22A·09 · error al guardar', () {
    testWidgets('el aviso del canvas con «Reintentar»; la tarjeta vuelve a ofrecer «Elegir»', (
      tester,
    ) async {
      final m = mundo()..alternativas.resultadosEstablecer.add(const FailureInesperado());
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);

      await elegirFila(tester, 'ub-2');

      expect(find.byKey(ClavesAlternativa.errorAlGuardar), findsOneWidget);
      expect(
        find.text('No pudimos guardar la ubicación alternativa en tu teléfono. Probá de nuevo.'),
        findsOneWidget,
      );
      // Nada queda trabado: ni «Guardando…» ni la tarjeta apagada.
      expect(find.byKey(ClavesAlternativa.guardando), findsNothing);
      expect(sin, findsOneWidget);
      expect(
        tester.widget<InkWell>(find.descendant(of: sin, matching: find.byType(InkWell))).onTap,
        isNotNull,
      );
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('«Reintentar» guarda la misma ubicación y el aviso desaparece', (tester) async {
      final m = mundo()..alternativas.resultadosEstablecer.add(const FailureInesperado());
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);
      await elegirFila(tester, 'ub-2');

      await tocar(tester, find.byKey(ClavesAlternativa.reintentarGuardar));

      expect(m.alternativas.establecidas, ['ub-2', 'ub-2']);
      expect(find.byKey(ClavesAlternativa.errorAlGuardar), findsNothing);
      expect(vigente, findsOneWidget);
    });

    testWidgets('si falla otra vez, el aviso sigue y «Reintentar» sigue tocable', (tester) async {
      final m = mundo()
        ..alternativas.resultadosEstablecer.addAll([
          const FailureInesperado(),
          StateError('se cortó'),
        ]);
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);
      await elegirFila(tester, 'ub-2');

      await tocar(tester, find.byKey(ClavesAlternativa.reintentarGuardar));

      expect(find.byKey(ClavesAlternativa.errorAlGuardar), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.guardando), findsNothing);
      await tocar(tester, find.byKey(ClavesAlternativa.reintentarGuardar));
      expect(vigente, findsOneWidget);
    });

    testWidgets('dos toques seguidos en «Reintentar» guardan una sola vez', (tester) async {
      final m = mundo()..alternativas.resultadosEstablecer.add(const FailureInesperado());
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);
      await elegirFila(tester, 'ub-2');

      // El segundo intento queda esperando: mientras tanto un segundo toque no guarda de nuevo.
      m.alternativas.compuertaEstablecer = Completer<void>();
      final reintentar = find.byKey(ClavesAlternativa.reintentarGuardar);
      await tester.ensureVisible(reintentar);
      await tester.pump();
      await tester.tap(reintentar);
      await tester.tap(reintentar);
      await asentar(tester);

      expect(m.alternativas.establecidas, ['ub-2', 'ub-2']);
      m.alternativas.compuertaEstablecer!.complete();
      await asentar(tester);
      expect(m.alternativas.establecidas, ['ub-2', 'ub-2']);
      expect(vigente, findsOneWidget);
    });

    testWidgets('una ubicación que la persistencia rechaza explica por qué y pide elegir otra', (
      tester,
    ) async {
      final m = mundo()
        ..alternativas.resultadosEstablecer.add(
          const FailureValidacion(
            campos: {
              'ubicacionAlternativa': 'Esa ubicación ya no está en tu teléfono. Elegí otra.',
            },
          ),
        );
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);
      await elegirFila(tester, 'ub-2');

      expect(find.text('Esa ubicación ya no está en tu teléfono. Elegí otra.'), findsOneWidget);
      // Repetir lo mismo no sirve: no hay «Reintentar», sí «Elegir».
      expect(find.byKey(ClavesAlternativa.reintentarGuardar), findsNothing);
      expect(sin, findsOneWidget);
    });

    testWidgets('elegir otra tras el error limpia el aviso', (tester) async {
      final m = mundo()..alternativas.resultadosEstablecer.add(const FailureInesperado());
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);
      await elegirFila(tester, 'ub-2');
      expect(find.byKey(ClavesAlternativa.errorAlGuardar), findsOneWidget);

      await tocar(tester, sin);
      await elegirFila(tester, 'ub-3');

      expect(find.byKey(ClavesAlternativa.errorAlGuardar), findsNothing);
      expect(find.text('Mataojo 2051'), findsWidgets);
    });
  });

  group('22A·07 · quitar la vinculación', () {
    MundoFicha conVigente() => mundo(estado: UbicacionAlternativaVigente(italia));

    testWidgets('«Quitar» abre la hoja con lo que pasa con las cobranzas y no escribe todavía', (
      tester,
    ) async {
      final m = conVigente();
      await montarFicha(tester, m, tamano: alto);

      await tocar(tester, quitar);

      expect(find.byKey(ClavesAlternativa.hojaQuitar), findsOneWidget);
      expect(find.text('¿Quitar Av. Italia 2810?'), findsOneWidget);
      expect(
        find.text(
          'Las próximas cobranzas de María se van a proponer en su casa, Mataojo 2044 · Depto 3B. '
          'Las que ya agendaste no cambian.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancelar'), findsOneWidget);
      expect(m.alternativas.quitadas, isEmpty);
    });

    testWidgets('«Cancelar» cierra la hoja y la alternativa sigue', (tester) async {
      final m = conVigente();
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, quitar);

      await tester.tap(find.byKey(ClavesAlternativa.hojaQuitarCancelar));
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.hojaQuitar), findsNothing);
      expect(m.alternativas.quitadas, isEmpty);
      expect(vigente, findsOneWidget);
    });

    testWidgets('«Quitar» en la hoja la quita, avisa y la tarjeta vuelve a ofrecer «Elegir»', (
      tester,
    ) async {
      final m = conVigente();
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, quitar);

      await tester.tap(find.byKey(ClavesAlternativa.hojaQuitarConfirmar));
      await asentar(tester);

      expect(m.alternativas.quitadas, ['per-1']);
      expect(find.byKey(ClavesAlternativa.hojaQuitar), findsNothing);
      expect(find.text('Las cobranzas de María se van a proponer en su casa.'), findsOneWidget);
      expect(sin, findsOneWidget);
      expect(vigente, findsNothing);
    });

    testWidgets('dos toques seguidos en «Quitar» de la hoja quitan una sola vez', (tester) async {
      final m = conVigente()..alternativas.compuertaQuitar = Completer<void>();
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, quitar);

      final confirmar = find.byKey(ClavesAlternativa.hojaQuitarConfirmar);
      await tester.tap(confirmar);
      await tester.tap(confirmar);
      await asentar(tester);

      // Mientras escribe: «Quitando…», nada se toca y no se puede cerrar.
      expect(find.text('Quitando…'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirmar).onPressed, isNull);
      expect(
        tester.widget<TextButton>(find.byKey(ClavesAlternativa.hojaQuitarCancelar)).onPressed,
        isNull,
      );
      expect(m.alternativas.quitadas, ['per-1']);

      m.alternativas.compuertaQuitar!.complete();
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.hojaQuitar), findsNothing);
      expect(m.alternativas.quitadas, ['per-1']);
    });

    testWidgets('si falla, la hoja explica qué pasó y «Quitar» vuelve a quedar habilitado', (
      tester,
    ) async {
      final m = conVigente()..alternativas.resultadosQuitar.add(const FailureInesperado());
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, quitar);

      await tester.tap(find.byKey(ClavesAlternativa.hojaQuitarConfirmar));
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.hojaQuitarError), findsOneWidget);
      expect(
        find.text('No pudimos quitar la ubicación alternativa de María. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Quitando…'), findsNothing);
      final confirmar = find.byKey(ClavesAlternativa.hojaQuitarConfirmar);
      expect(tester.widget<FilledButton>(confirmar).onPressed, isNotNull);

      // Reintenta y sale.
      await tester.tap(confirmar);
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.hojaQuitar), findsNothing);
      expect(m.alternativas.quitadas, ['per-1', 'per-1']);
      expect(sin, findsOneWidget);
    });

    testWidgets('una falla que se lanza (no un Failure) tampoco deja la hoja trabada', (
      tester,
    ) async {
      final m = conVigente()..alternativas.resultadosQuitar.add(StateError('se cortó'));
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, quitar);

      await tester.tap(find.byKey(ClavesAlternativa.hojaQuitarConfirmar));
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.hojaQuitarError), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(ClavesAlternativa.hojaQuitarConfirmar)).onPressed,
        isNotNull,
      );
    });

    testWidgets('«Quitar» es un botón de al menos 48 dp que dice cuál ubicación quita', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarFicha(tester, conVigente(), tamano: alto);

      expect(tester.getSize(quitar).height, greaterThanOrEqualTo(48));
      final nodo = tester.getSemantics(quitar);
      expect(nodo.label, 'Quitar la ubicación alternativa Av. Italia 2810');
      expect(nodo.flagsCollection.isButton, isTrue);
      semantica.dispose();
    });
  });

  group('22A·08 · la alternativa se dio de baja', () {
    MundoFicha deBaja() =>
        mundo(estado: UbicacionAlternativaDeBaja('ub-2', ubicacion: italiaDeBaja));

    testWidgets('avisa con el texto del canvas y muestra la tarjeta tachada y «DADA DE BAJA»', (
      tester,
    ) async {
      await montarFicha(tester, deBaja(), tamano: alto);

      expect(
        find.text('Ubicación alternativa dada de baja - actualizá antes de cobrar acá'),
        findsOneWidget,
      );
      expect(find.text('Elegir otra'), findsOneWidget);
      expect(find.text('DADA DE BAJA'), findsOneWidget);
      final direccion = tester.widget<Text>(find.text('Av. Italia 2810'));
      expect(direccion.style?.decoration, TextDecoration.lineThrough);
      expect(find.text('SE COBRA ACÁ'), findsNothing);
      expect(quitar, findsOneWidget);
    });

    testWidgets('«Quitar» sirve también con la alternativa dada de baja', (tester) async {
      final m = deBaja();
      await montarFicha(tester, m, tamano: alto);

      await tocar(tester, quitar);
      expect(find.text('¿Quitar Av. Italia 2810?'), findsOneWidget);
      await tester.tap(find.byKey(ClavesAlternativa.hojaQuitarConfirmar));
      await asentar(tester);

      expect(m.alternativas.quitadas, ['per-1']);
      expect(find.byKey(ClavesAlternativa.avisoDeBaja), findsNothing);
      expect(sin, findsOneWidget);
    });

    testWidgets('si la alternativa no está en el teléfono no se afirma que esté de baja', (
      tester,
    ) async {
      final m = mundo(estado: const UbicacionAlternativaFaltante('ub-9'));
      await montarFicha(tester, m, tamano: alto);

      expect(find.byKey(ClavesAlternativa.faltante), findsOneWidget);
      expect(find.textContaining('dada de baja'), findsNothing);
      expect(
        find.text('No encontramos la ubicación alternativa en tu teléfono. Elegí otra o quitala.'),
        findsOneWidget,
      );
      await tocar(tester, quitar);
      expect(find.text('¿Quitar la ubicación alternativa?'), findsOneWidget);
    });
  });

  group('persona de baja o depto de baja (32B·04, 32B·08): solo lectura', () {
    testWidgets('con alternativa se ve, sin «Quitar» ni «Elegir otra»', (tester) async {
      final m = mundo(estado: UbicacionAlternativaVigente(italia), deBaja: true);
      await montarFicha(tester, m, tamano: alto);

      expect(vigente, findsOneWidget);
      expect(find.text('SE COBRA ACÁ'), findsOneWidget);
      expect(quitar, findsNothing);
    });

    testWidgets('con la alternativa dada de baja avisa pero no ofrece cambiarla', (tester) async {
      final m = mundo(
        estado: UbicacionAlternativaDeBaja('ub-2', ubicacion: italiaDeBaja),
        deBaja: true,
      );
      await montarFicha(tester, m, tamano: alto);

      expect(find.byKey(ClavesAlternativa.avisoDeBaja), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.elegirOtra), findsNothing);
      expect(quitar, findsNothing);
    });

    testWidgets('sin alternativa no hay sección: no hay nada que ofrecer', (tester) async {
      await montarFicha(tester, mundo(deBaja: true), tamano: alto);

      expect(seccion, findsNothing);
      expect(find.text('Cobrar en otro lugar'), findsNothing);
    });
  });

  group('datos límite', () {
    for (final (nombre, estado, accion) in <(String, EstadoUbicacionAlternativa, Finder)>[
      ('sin alternativa', const SinUbicacionAlternativa(), sin),
      (
        'vigente con una dirección larga',
        UbicacionAlternativaVigente(
          ubicacionParaAlternativa(
            'ub-largo',
            calle: 'Avenida Doctor Luis Alberto de Herrera y Sarmiento',
            numero: '12345 bis',
          ),
        ),
        quitar,
      ),
      ('dada de baja', UbicacionAlternativaDeBaja('ub-2', ubicacion: italiaDeBaja), quitar),
    ]) {
      testWidgets('con el texto al 200 % la tarjeta $nombre entra sin desbordar', (tester) async {
        await montarFicha(tester, mundo(estado: estado), escala: 2, tamano: const Size(360, 3200));

        expect(tester.takeException(), isNull);
        expect(seccion, findsOneWidget);
        // La acción sigue a la vista y es tocable.
        expect(accion, findsOneWidget);
        expect(tester.getSize(accion).height, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('una dirección larguísima no rompe la tarjeta de la alternativa vigente', (
      tester,
    ) async {
      final larga = ubicacionParaAlternativa(
        'ub-largo',
        calle: 'Avenida Doctor Luis Alberto de Herrera y Sarmiento de Gamboa',
        numero: '12345 bis apto 1204',
      );
      await montarFicha(
        tester,
        mundo(estado: UbicacionAlternativaVigente(larga)),
        tamano: const Size(320, 1800),
      );

      expect(tester.takeException(), isNull);
      expect(vigente, findsOneWidget);
    });
  });
}
