// QA de #450 (vista 39 «La casa en el mapa», base: R·05 «Entrevista en curso», R·06 «Terminó la
// entrevista» y R·07 «Sin inicio registrado», más el aviso fijo sobre el mapa; HU-VIS-005 y la
// decisión de Cristian del 23/10, «Entrevista fuera»).
//
// Qué mira, además de lo que ya prueban los tests del implementador:
//  - el texto literal del canvas en cada artboard;
//  - la matriz de estados × 360×640 / 412×915 × letra 1,0 / 2,0: sin overflow, sin texto cortado, con
//    las guías de tamaño de toque y de etiqueta de Flutter;
//  - los casos límite de navegación (atrás del sistema, cerrar mientras guarda, reloj atrasado,
//    entrevista de días atrás, teclado, notas límite);
//  - privacidad (`toString` sin la nota).
//
// Capturas: `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas/`, ignorado por git).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/entrevista_en_curso.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/finalizar_entrevista_use_case.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_termino_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrevista_falsos.dart';
import '../../helpers/qa_vista39_450_arnes.dart';
import '../../helpers/venta_ui_falsos.dart' show EntornoDeVenta;

void main() {
  group('texto literal del canvas 39', () {
    testWidgets('R·05: lugar y persona, EN CURSO, cuánto va, desde cuándo, la nota y Finalizar', (
      tester,
    ) async {
      await llegar(tester, Estado39.r05);

      for (final texto in [
        'Entrevista en curso',
        'Grecia 3307 · Pedro Gómez',
        'EN CURSO',
        '18 min',
        'Desde las 14:23',
        '✎  Nota de la visita',
        'Finalizar entrevista',
      ]) {
        expect(find.text(texto), findsOneWidget, reason: texto);
      }
    });

    testWidgets('R·06: Entrada, Salida, Duración, ¿HUBO VENTA? y los dos botones', (tester) async {
      await llegar(tester, Estado39.r06);

      for (final texto in [
        'Terminó la entrevista',
        'Grecia 3307 · Pedro Gómez',
        'Entrada',
        '14:23  ✎',
        'Salida',
        '14:41  ✎',
        'Duración',
        '18 min',
        '¿HUBO VENTA?',
        'Sí, registrar la venta',
        'No, guardar y volver al mapa',
      ]) {
        expect(find.text(texto), findsOneWidget, reason: texto);
      }
      expect(find.byKey(ClavesEntrevista.avisoSinInicio), findsNothing);
    });

    testWidgets('R·07: el aviso de «No registramos el inicio…» con la hora de la visita anterior', (
      tester,
    ) async {
      await llegar(tester, Estado39.r07);

      expect(
        find.text(
          'No registramos el inicio. Tomamos la hora de tu visita anterior (14:10). Revisala.',
        ),
        findsOneWidget,
      );
      expect(find.text('Entrada'), findsOneWidget);
      expect(find.text('14:10  ✎'), findsOneWidget);
      expect(find.text('Salida'), findsOneWidget);
      expect(find.text('14:41  ✎'), findsOneWidget);
      expect(find.text('¿HUBO VENTA?'), findsOneWidget);
    });

    testWidgets(
      'R·07: el canvas dibuja solo Entrada y Salida, sin la fila «Duración» de R·06',
      (tester) async {
        await llegar(tester, Estado39.r07);

        expect(find.byKey(ClavesEntrevista.duracion), findsNothing);
      },
      // skip: QA #450 — R·07 muestra «Duración» (22 min) y el canvas no la dibuja (menor).
      skip: true,
    );
  });

  group('matriz de estados × tamaños × letra', () {
    for (final estado in Estado39.values) {
      for (final tamano in tamanos39) {
        for (final escala in escalas39) {
          final celda = nombreDeCelda(estado, tamano, escala);
          testWidgets(
            '${estado.rotulo} · $celda: sin overflow, sin texto cortado y con las guías',
            (tester) async {
              final semantica = tester.ensureSemantics();
              await llegar(tester, estado, tamano: tamano, escala: escala);

              expect(tester.takeException(), isNull);
              sinTextoCortado(tester);
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              await capturar(tester, celda);
              semantica.dispose();
            },
          );
        }
      }
    }
  });

  group('la hoja de la hora de R·06 (−5 / +5, la misma de la jornada)', () {
    for (final tamano in tamanos39) {
      for (final escala in escalas39) {
        final celda = 'hora_${tamano.width.toInt()}x${tamano.height.toInt()}_x${escala.toInt()}';
        testWidgets('abierta sobre R·06 · $celda: sin overflow y con las guías', (tester) async {
          final semantica = tester.ensureSemantics();
          await llegar(tester, Estado39.r06, tamano: tamano, escala: escala);
          await tocar(tester, find.byKey(ClavesEntrevista.filaSalida));

          expect(find.byKey(const Key('hoja_hora_usar')), findsOneWidget);
          expect(tester.takeException(), isNull);
          sinTextoCortado(tester);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await capturar(tester, celda);
          semantica.dispose();
        });
      }
    }
  });

  group('campo de la nota', () {
    testWidgets(
      'a 200 % de letra en 360×640 el rótulo «NOTA DE LA VISITA (OPCIONAL)» se lee entero',
      (tester) async {
        await enCursoEnEstaSesion(tester, escala: 2);
        await tocar(tester, find.byKey(ClavesEntrevista.botonNota));

        final rotulo = tester.renderObject<RenderParagraph>(find.text(TextosEntrevista.campoNota));
        expect(rotulo.didExceedMaxLines, isFalse, reason: 'el rótulo termina en «OPCI…»');
      },
      // skip: QA #450 — a 200 % el rótulo flotante del campo termina en «OPCI…» y se pierde «OPCIONAL».
      skip: true,
    );
  });

  group('todo se alcanza con la letra al 200 % en 360×640', () {
    testWidgets('R·06: los dos botones y las dos horas se pueden tocar desplazando', (
      tester,
    ) async {
      await llegar(tester, Estado39.r06, escala: 2);
      final alto = tester.view.physicalSize.height;

      for (final clave in [
        ClavesEntrevista.filaEntrada,
        ClavesEntrevista.filaSalida,
        ClavesEntrevista.registrarVenta,
        ClavesEntrevista.guardarYVolver,
      ]) {
        await tester.ensureVisible(find.byKey(clave));
        await tester.pump();
        final r = tester.getRect(find.byKey(clave));
        expect(r.top, greaterThanOrEqualTo(0), reason: '$clave queda arriba de la pantalla');
        expect(r.bottom, lessThanOrEqualTo(alto + 0.5), reason: '$clave queda debajo');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('R·05: la nota y Finalizar se alcanzan con el teclado abierto (280 dp)', (
      tester,
    ) async {
      await llegar(tester, Estado39.r05Nota, escala: 2);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(ClavesEntrevista.finalizar));
      await tester.pump();
      final alto = tester.view.physicalSize.height - 280;
      expect(
        tester.getRect(find.byKey(ClavesEntrevista.finalizar)).bottom,
        lessThanOrEqualTo(alto + 0.5),
      );
      await tester.ensureVisible(find.byKey(ClavesEntrevista.campoNota));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(ClavesEntrevista.campoNota)).bottom,
        lessThanOrEqualTo(alto + 0.5),
      );
    });

    testWidgets('el teléfono cambia de tamaño con R·06 abierta: nada desborda', (tester) async {
      await llegar(tester, Estado39.r06Error, tamano: const Size(412, 915));

      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesEntrevista.avisoError), findsOneWidget);
    });
  });

  group('avisos: dicen qué pasa y se anuncian', () {
    testWidgets('el error de guardar es una región viva y dice qué hacer', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegar(tester, Estado39.r06Error);

      expect(find.text(TextosEntrevista.noPudimosGuardar), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(ClavesEntrevista.avisoError)),
        isSemantics(isLiveRegion: true),
      );
      // La salida: los botones están libres para reintentar.
      expect(
        tester.widget<OutlinedButton>(find.byKey(ClavesEntrevista.guardarYVolver)).onPressed,
        isNotNull,
      );
      semantica.dispose();
    });

    testWidgets('el pedido de la hora de salida es una región viva', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegar(tester, Estado39.r06PideSalida);

      expect(find.text(TextosEntrevista.pedirSalida), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(ClavesEntrevista.avisoPedirHora)),
        isSemantics(isLiveRegion: true),
      );
      semantica.dispose();
    });

    testWidgets('sin ninguna visita anterior R·07 pide la entrada y no deja seguir sin ella', (
      tester,
    ) async {
      await llegar(tester, Estado39.r07SinVisita);

      expect(find.text(TextosEntrevista.pedirEntrada), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byKey(ClavesEntrevista.guardarYVolver)).onPressed,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(ClavesEntrevista.registrarVenta)).onPressed,
        isNull,
      );
    });
  });

  group('navegación: atrás en cada estado, reentrada', () {
    testWidgets('atrás del sistema en R·05 cierra la hoja; la entrevista y la nota siguen', (
      tester,
    ) async {
      final r = await llegar(tester, Estado39.r05Nota);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsNothing);
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
      expect(r.montaje.almacen.guardadas, hasLength(1));

      await tocar(tester, find.byKey(ClavesEntrevista.avisoFijo));
      expect(find.text('Desde las 14:23'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(ClavesEntrevista.campoNota)).controller!.text,
        startsWith('perro suelto'),
      );
    });

    testWidgets('atrás del sistema en R·06 cierra la hoja y la entrevista sigue en curso', (
      tester,
    ) async {
      final r = await llegar(tester, Estado39.r06);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesEntrevista.hojaTermino), findsNothing);
      expect(r.montaje.agenda.recibidas, isEmpty);
      expect(r.montaje.almacen.guardadas, hasLength(1));
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
      // Reentrar: vuelve a R·05 con la misma hora de inicio.
      await tocar(tester, find.byKey(ClavesEntrevista.avisoFijo));
      expect(find.text('Desde las 14:23'), findsOneWidget);
    });

    testWidgets('atrás en la hoja de la hora de R·06 deja las horas como estaban', (tester) async {
      await llegar(tester, Estado39.r06);

      await tocar(tester, find.byKey(ClavesEntrevista.filaSalida));
      expect(find.byKey(const Key('hoja_hora_usar')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
      expect(find.text('14:41  ✎'), findsOneWidget);
    });

    testWidgets('tocar el velo de R·06 sin elegir deja la entrevista y la jornada como estaban', (
      tester,
    ) async {
      final r = await llegar(tester, Estado39.r06PideSalida);

      await tester.tapAt(const Offset(180, 4));
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesEntrevista.hojaTermino), findsNothing);
      expect(r.salida, isNull);
      expect(r.montaje.almacen.guardadas, hasLength(1));
      expect(r.montaje.agenda.recibidas, isEmpty);
    });
  });

  group('casos límite del guardado', () {
    testWidgets(
      'cerrar R·06 mientras guarda: la visita se guarda una sola vez y la entrevista se borra',
      (tester) async {
        final r = await llegar(tester, Estado39.r06Guardando);
        expect(find.text(TextosEntrevista.guardando), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        r.montaje.agenda.compuerta!.complete();
        await tester.pumpAndSettle();

        expect(r.montaje.agenda.recibidas, hasLength(1));
        expect(r.montaje.almacen.guardadas, isEmpty);
        expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing);
      },
    );

    testWidgets(
      'cerrar R·06 mientras guarda: la colportora ve igual la confirmación «Guardado…»',
      (tester) async {
        final r = await llegar(tester, Estado39.r06Guardando);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        r.montaje.agenda.compuerta!.complete();
        await tester.pumpAndSettle();

        expect(find.text(TextosEntrevista.guardada('Grecia 3307')), findsOneWidget);
      },
      // skip: QA #450 — la hoja se puede cerrar mientras guarda y entonces no hay confirmación.
      skip: true,
    );

    testWidgets('con el guardado trabado y una falla después, el botón vuelve y se reintenta', (
      tester,
    ) async {
      final r = await llegar(tester, Estado39.r06Guardando);
      r.montaje.agenda.falla = const FailureInesperado();
      r.montaje.agenda.compuerta!.complete();
      await tester.pumpAndSettle();

      expect(find.text(TextosEntrevista.noPudimosGuardar), findsOneWidget);
      expect(find.text(TextosEntrevista.guardarYVolver), findsOneWidget);
      r.montaje.agenda.falla = null;
      r.montaje.agenda.compuerta = null;
      await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));

      expect(find.byKey(ClavesEntrevista.hojaTermino), findsNothing);
      expect(r.montaje.agenda.recibidas, hasLength(1));
      expect(r.montaje.almacen.guardadas, isEmpty);
    });

    testWidgets('si falla el borrado de la entrevista el reintento no duplica la visita', (
      tester,
    ) async {
      final r = await llegar(tester, Estado39.r06);
      r.montaje.rota.fallaAlBorrar = true;

      await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));
      expect(find.text(TextosEntrevista.noPudimosGuardar), findsOneWidget);
      r.montaje.rota.fallaAlBorrar = false;
      await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));

      expect(r.montaje.agenda.recibidas.map((v) => v.visita.id).toSet(), hasLength(1));
      expect(r.montaje.almacen.guardadas, isEmpty);
    });

    testWidgets('el reloj del teléfono quedó antes del inicio: avisa qué corregir y deja salida', (
      tester,
    ) async {
      final r = await llegar(tester, Estado39.r06);
      // Se atrasó el reloj de la hora: salida (ahora) < entrada.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      r.montaje.reloj = () => DateTime(2026, 10, 23, 14, 10);
      await tocar(tester, find.byKey(ClavesEntrevista.avisoFijo));
      await tocar(tester, find.byKey(ClavesEntrevista.finalizar));

      await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));

      expect(r.montaje.agenda.recibidas, isEmpty);
      expect(find.byKey(ClavesEntrevista.avisoError), findsOneWidget);
      expect(find.textContaining('La salida no puede ser antes de la entrada'), findsOneWidget);
      // Hay salida: se baja la entrada con la hoja de la hora y se puede guardar.
      await tocar(tester, find.byKey(ClavesEntrevista.filaEntrada));
      await tocar(tester, find.byKey(const Key('hoja_hora_menos')));
      await tocar(tester, find.byKey(const Key('hoja_hora_usar')));
      await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));

      expect(r.montaje.agenda.recibidas, hasLength(1));
    });

    testWidgets(
      'el reloj atrasado no muestra una duración negativa como «menos de 1 min»',
      (tester) async {
        final r = await llegar(tester, Estado39.r06);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        r.montaje.reloj = () => DateTime(2026, 10, 23, 14, 10);
        await tocar(tester, find.byKey(ClavesEntrevista.avisoFijo));
        await tocar(tester, find.byKey(ClavesEntrevista.finalizar));

        expect(find.text('menos de 1 min'), findsNothing);
      },
      // skip: QA #450 — con el reloj atrasado R·06 dice «menos de 1 min» (menor).
      skip: true,
    );
  });

  group('una entrevista que quedó abierta de días atrás', () {
    testWidgets('R·06 pide la salida, se elige dentro de las 12 h y se guarda', (tester) async {
      final montaje = MontajeEntrevista();
      await montaje.almacen.guardar(entrevistaDePrueba(inicio: DateTime(2026, 10, 21, 14, 23)));
      final r = await montar(tester, montaje: montaje);

      expect(
        find.textContaining('Entrevista en curso · Grecia 3307 · 48 h 18 min'),
        findsOneWidget,
      );
      await tocar(tester, terminarPidiendo);
      await tocar(tester, find.byKey(ClavesEntrevista.filaSalida));
      await tocar(tester, find.byKey(const Key('hoja_hora_usar')));
      await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));

      expect(tester.takeException(), isNull);
      expect(r.salida, isA<EntrevistaGuardada>());
      expect(montaje.agenda.recibidas, hasLength(1));
    });
  });

  group('notas límite', () {
    testWidgets('una nota de solo espacios no crea ninguna nota', (tester) async {
      final r = await enCursoEnEstaSesion(tester);
      await tocar(tester, find.byKey(ClavesEntrevista.botonNota));
      await tester.enterText(find.byKey(ClavesEntrevista.campoNota), '     ');
      await tester.pumpAndSettle();
      await tocar(tester, find.byKey(ClavesEntrevista.finalizar));
      await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));

      expect(r.montaje.agenda.recibidas.single.nota, isNull);
    });

    testWidgets('una nota pegada de 20 000 caracteres con emoji no desborda y viaja entera', (
      tester,
    ) async {
      final larga = '${'Perro suelto 🐕 timbre roto. ' * 700}fin';
      final r = await enCursoEnEstaSesion(tester, escala: 2);
      await tocar(tester, find.byKey(ClavesEntrevista.botonNota));
      await tester.enterText(find.byKey(ClavesEntrevista.campoNota), larga);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tocar(tester, find.byKey(ClavesEntrevista.finalizar));
      await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));

      expect(r.montaje.agenda.recibidas.single.nota!.texto, larga.trim());
    });

    testWidgets('la nota con comillas, saltos de línea y caracteres especiales se guarda igual', (
      tester,
    ) async {
      final r = await enCursoEnEstaSesion(tester);
      await tocar(tester, find.byKey(ClavesEntrevista.botonNota));
      await tester.enterText(
        find.byKey(ClavesEntrevista.campoNota),
        '«Volver» a las 6\n<b>no</b> & "otra" \\ ñandú',
      );
      await tester.pumpAndSettle();
      await tocar(tester, find.byKey(ClavesEntrevista.finalizar));
      await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));

      expect(
        r.montaje.agenda.recibidas.single.nota!.texto,
        '«Volver» a las 6\n<b>no</b> & "otra" \\ ñandú',
      );
    });
  });

  group('«Sí, registrar la venta» (#428)', () {
    testWidgets('abre la venta con la casa y la persona, y no guarda nada hasta que se guarde', (
      tester,
    ) async {
      final montaje = MontajeEntrevista()..extra.addAll(EntornoDeVenta().overrides);
      final r = await llegar(tester, Estado39.r06, montaje: montaje);

      await tocar(tester, find.byKey(ClavesEntrevista.registrarVenta));

      expect(find.byKey(const Key('nueva_venta_pagina')), findsOneWidget);
      expect(r.montaje.agenda.recibidas, isEmpty);
      expect(r.montaje.almacen.guardadas, hasLength(1));
    });

    testWidgets('si la venta no se completa, la entrevista y su aviso siguen a la vista', (
      tester,
    ) async {
      final montaje = MontajeEntrevista()..extra.addAll(EntornoDeVenta().overrides);
      final r = await llegar(tester, Estado39.r06, montaje: montaje);

      await tocar(tester, find.byKey(ClavesEntrevista.registrarVenta));
      await tocar(tester, find.byKey(const Key('venta_atras')));

      expect(r.salida, isA<VentaSinCompletar>());
      expect(r.montaje.agenda.recibidas, isEmpty);
      expect(r.montaje.almacen.guardadas, hasLength(1));
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
      expect(
        find.text('La venta no se guardó. La entrevista con Pedro Gómez sigue en curso.'),
        findsOneWidget,
      );
    });
  });

  group('privacidad', () {
    test('ni el estado, ni los parámetros ni la entrevista dejan la nota en su toString', () {
      const secreto = 'perro suelto en lo de Pedro Gómez, Grecia 3307';
      final params = FinalizarEntrevistaParams.de(
        entrevistaDePrueba(),
        entrada: inicioEntrevista,
        salida: ahoraEntrevista,
        nota: secreto,
      );
      const estado = EstadoEntrevista(cargando: false, notaBorrador: secreto);

      for (final texto in [params.toString(), estado.toString(), entrevistaDePrueba().toString()]) {
        expect(texto, isNot(contains('perro')));
        expect(texto, isNot(contains('Pedro')));
        expect(texto, isNot(contains('Grecia')));
      }
    });

    test(
      'la entrevista guardada lleva solo ids y la hora de inicio (sin nombres ni direcciones)',
      () {
        final e = entrevistaDePrueba();
        expect(e, isA<EntrevistaEnCurso>());
        expect(e.props.whereType<String>().every((s) => !s.contains(' ')), isTrue);
      },
    );
  });

  group('el tiempo corre en R·05 y en el aviso', () {
    testWidgets('a los 30 s el aviso y la hoja suben juntos de minuto', (tester) async {
      final r = await llegar(tester, Estado39.r05);
      expect(find.text('18 min'), findsOneWidget);

      r.montaje.reloj = () => ahoraEntrevista.add(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 31));

      expect(find.text('19 min'), findsOneWidget);
    });
  });

  testWidgets('no queda ningún overflow registrado al final del recorrido completo', (
    tester,
  ) async {
    final r = await enCursoEnEstaSesion(tester, escala: 2);
    await tocar(tester, find.byKey(ClavesEntrevista.botonNota));
    await tester.enterText(find.byKey(ClavesEntrevista.campoNota), 'perro suelto');
    await tocar(tester, find.byKey(ClavesEntrevista.finalizar));
    await tocar(tester, find.byKey(ClavesEntrevista.guardarYVolver));
    await tester.pump(const Duration(seconds: 6));

    expect(tester.takeException(), isNull);
    expect(r.montaje.agenda.recibidas, hasLength(1));
  });
}
