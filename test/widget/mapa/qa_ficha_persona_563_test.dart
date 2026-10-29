// QA de la ficha de una persona (vista 32B, HU-UBI-009, #141, PR #563): cada estado del canvas (los siete
// artboards de la historia) y los que el canvas no dibuja, a 360×640 y 412×915 con el texto al 100 % y al
// 200 %; los escenarios de la HU con su texto literal; y los casos límite que el PR no prueba (el
// error después de haber mostrado la ficha, lo que se ve mientras vuelve a leer, lo que pasa en vivo).
//
// Las capturas salen a `.dart_tool/qa_capturas/563_*.png` solo con `--dart-define=QA_CAPTURAS=true`; los
// tests de hallazgos (con `skip`) se corren con `--dart-define=QA_HALLAZGOS=true`.
import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:colportores_mobile/features/mapa/domain/services/filtro_de_historial.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ficha_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_notas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_ficha_persona_563_arnes.dart';

/// Una ficha que muestra la primera lectura y después puede fallar o volver a leer más lento.
final class _FichaQueFallaDespues extends FichaPersonaRepositorioFalso {
  _FichaQueFallaDespues({required super.persona, super.historial});

  final _estallidos = StreamController<LecturaDeFicha?>.broadcast();
  Completer<void>? compuertaDeLaSiguienteLectura;
  var _lecturas = 0;

  void fallar() => _estallidos.addError(StateError('se rompió la base'));

  @override
  Stream<LecturaDeFicha?> observar(String personaId) async* {
    _lecturas++;
    if (_lecturas > 1) await compuertaDeLaSiguienteLectura?.future;
    yield* super.observar(personaId).take(1);
    yield* _estallidos.stream;
  }
}

void main() {
  const hallazgos = bool.fromEnvironment('QA_HALLAZGOS');
  setUpAll(() {
    usarFuentesReales563 = true;
    WidgetsApp.debugAllowBannerOverride = false;
  });

  final marcas = <EstadoFicha, Finder Function()>{
    EstadoFicha.completa: () => find.byKey(ClavesFicha.cuenta),
    EstadoFicha.telefonoVisible: () => find.text('+598 99 123 456'),
    EstadoFicha.personaDeBaja: () => find.byKey(ClavesFicha.botonReactivar),
    EstadoFicha.sinHistorial: () => find.byKey(ClavesFicha.hero),
    EstadoFicha.cargando: () => find.byKey(ClavesFicha.cargando),
    EstadoFicha.error: () => find.byKey(ClavesFicha.error),
    EstadoFicha.deptoDeBaja: () => find.byKey(ClavesFicha.botonReactivarDepto),
    EstadoFicha.personaNoEncontrada: () => find.text(TextosFicha.personaNoEncontrada),
    EstadoFicha.sinMovimientos: () => find.byKey(ClavesFicha.historial),
    EstadoFicha.conEntregasYCobros: () => find.text('20/10 · COBRO'),
    EstadoFicha.muchosMovimientos: () => find.byKey(ClavesFicha.verMas),
    EstadoFicha.textosLargos: () => find.byKey(ClavesFicha.cuenta),
    EstadoFicha.reactivandoPersona: () => find.text(TextosFicha.reactivando),
    EstadoFicha.reactivandoDepto: () => find.text(TextosFicha.reactivando),
    EstadoFicha.errorAlReactivar: () => find.text(TextosFicha.noPudimosReactivar('María')),
    EstadoFicha.noPudoLlamar: () => find.text(TextosFicha.noPudimosAbrirElTelefono),
    EstadoFicha.menuAbierto: () => find.byKey(ClavesFicha.opcionBaja),
    EstadoFicha.conLector: () => find.byKey(ClavesFicha.cuenta),
    EstadoFicha.filtroConSaldo: () => find.byKey(ClavesFicha.fila('ven-1')),
    EstadoFicha.filtroSinResultados: () => find.byKey(ClavesFicha.sinResultados),
    EstadoFicha.ubicacionDeBaja: () => find.textContaining(TextosFicha.reactivarPrimeroLaUbicacion),
    EstadoFicha.sinDeptoActivo: () => find.textContaining(TextosFicha.reactivarElDepto),
  };

  group('matriz de estados: sin overflow, con su contenido y capturas', () {
    for (final tamano in [telefonoChico563, telefonoGrande563]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in EstadoFicha.values) {
          final donde =
              '${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()} al '
              '${(escala * 100).toInt()} %';
          testWidgets(donde, (tester) async {
            await llegarAFicha(tester, estado, tamano: tamano, escala: escala);
            final nombre =
                '${estado.name}_${tamano.width.toInt()}x${tamano.height.toInt()}_${(escala * 10).toInt()}';
            await capturar563(tester, nombre);

            // Lo propio del estado está en el árbol (la ficha es una lista perezosa: se baja hasta él).
            final marca = marcas[estado]!();
            if (marca.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                marca,
                300,
                scrollable: find.byType(Scrollable).first,
              );
            }
            expect(marca, findsWidgets, reason: '${estado.rotulo}: falta lo propio del estado');

            // Se recorre hasta el final: un overflow más abajo también cuenta.
            final listas = find.byType(ListView);
            if (listas.evaluate().isNotEmpty) {
              final lista = tester.state<ScrollableState>(
                find.descendant(of: listas.first, matching: find.byType(Scrollable)).first,
              );
              lista.position.jumpTo(lista.position.maxScrollExtent);
              await tester.pump(const Duration(milliseconds: 60));
              await capturar563(tester, '${nombre}_fin');
            }
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('HU-UBI-009: escenarios con su texto literal', () {
    testWidgets(
      'Vista de persona activa: nombre, apellido, teléfono enmascarado, 3 visitas y la venta',
      (tester) async {
        final m = MundoFicha(
          historial: [
            VentaEnFicha(
              id: 'ven-1',
              fecha: DateTime(2026, 10, 12, 12),
              numeroTalonario: '0042',
              montoCentavos: 120000,
              lineas: const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
            ),
            for (var i = 1; i <= 3; i++) visitaEnFicha('vis-$i', DateTime(2026, 10, i, 12)),
          ],
        );
        await montarFicha(tester, m, tamano: telefonoGrande563);

        expect(find.text('María Pérez'), findsOneWidget);
        expect(find.text('+598 99 *** 456'), findsOneWidget);
        expect(find.byKey(ClavesFicha.fila('ven-1')), findsOneWidget);
        for (var i = 1; i <= 3; i++) {
          expect(find.byKey(ClavesFicha.fila('vis-$i')), findsOneWidget);
        }
        // El número entero no está en ningún lado del árbol mientras esté enmascarado.
        expect(find.textContaining('123'), findsNothing);
        expect(find.textContaining('099'), findsNothing);
      },
    );

    testWidgets(
      'Toggle de visibilidad: «Ver» revela `+598 99 123 456` y al salir vuelve a ocultarse',
      (tester) async {
        await montarFicha(tester, mundoCompleto563());
        expect(find.text('+598 99 *** 456'), findsOneWidget);

        await tester.tap(find.byKey(ClavesFicha.botonVer));
        await asentar(tester);
        expect(find.text('+598 99 123 456'), findsOneWidget);
        expect(find.text('+598 99 *** 456'), findsNothing);
        expect(find.byKey(ClavesFicha.botonVer), findsNothing);

        await volverAtras(tester);
        await tester.tap(find.text('abrir ficha'));
        await asentar(tester);
        expect(find.text('+598 99 *** 456'), findsOneWidget);
      },
    );

    testWidgets('el teléfono sigue a la vista cuando llega un cambio en vivo', (tester) async {
      final m = mundoCompleto563();
      await montarFicha(tester, m);
      await tester.tap(find.byKey(ClavesFicha.botonVer));
      await asentar(tester);

      m.fichas.poner(
        LecturaDeFicha(
          persona: mariaDePrueba(),
          historial: [
            visitaEnFicha('vis-nueva', DateTime(2026, 10, 22, 14)),
            ...historialDelCanvas(),
          ],
        ),
      );
      await asentar(tester);

      expect(find.byKey(ClavesFicha.fila('vis-nueva')), findsOneWidget);
      expect(find.text('+598 99 123 456'), findsOneWidget);
    });

    testWidgets('Llamar: el marcador recibe solo los dígitos y la auditoría lleva la persona', (
      tester,
    ) async {
      final m = mundoCompleto563();
      await montarFicha(tester, m);

      await tester.tap(find.byKey(ClavesFicha.botonLlamar));
      await asentar(tester);

      expect(m.marcador.numeros, ['099123456']);
      expect(m.fichas.llamadas.map((l) => l.personaId), ['per-1']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Persona sin teléfono: no aparece «Llamar» ni «Ver»', (tester) async {
      final m = MundoFicha(persona: mariaDePrueba(telefono: null), historial: historialDelCanvas());
      await montarFicha(tester, m);

      expect(find.byKey(ClavesFicha.botonLlamar), findsNothing);
      expect(find.byKey(ClavesFicha.botonVer), findsNothing);
      expect(find.text(TextosFicha.sinTelefono), findsOneWidget);
    });

    testWidgets('Persona de baja: el banner del canvas y ninguna acción de escritura', (
      tester,
    ) async {
      final m = mundoDe563(EstadoFicha.personaDeBaja)
        ..conEdicion = true
        ..conRegistrarVisita = true;
      await montarFicha(tester, m, tamano: telefonoGrande563);

      expect(
        find.text(
          'María está de baja desde el 22/10. Podés ver su historial, pero no registrar nada.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(ClavesFicha.menu), findsNothing);
      expect(find.text(TextosFicha.masNota), findsNothing);
      expect(find.byKey(ClavesFicha.botonAgregarTelefono), findsNothing);
      expect(find.byKey(ClavesFicha.botonRegistrarVisita), findsNothing);
      expect(find.byKey(ClavesFicha.botonReactivar), findsOneWidget);
    });

    testWidgets('Depto de baja: el aviso del canvas 32B·08 y «Reactivar el depto»', (tester) async {
      await montarFicha(tester, mundoDe563(EstadoFicha.deptoDeBaja), tamano: telefonoGrande563);

      expect(
        find.text('El depto 3B de Mataojo 2044 está dado de baja. La ficha queda en solo lectura.'),
        findsOneWidget,
      );
      expect(find.byKey(ClavesFicha.botonReactivarDepto), findsOneWidget);
      expect(find.byKey(ClavesFicha.menu), findsNothing);
      expect(find.text(TextosFicha.masNota), findsNothing);
    });

    testWidgets('el texto del canvas 32B·07 con el nombre no se puede dar sin él', (tester) async {
      await montarFicha(tester, mundoDe563(EstadoFicha.error));

      // Pendiente P2 del PR (mapa §2): hoy dice «de la persona»; el canvas dice «de María».
      expect(find.text('No pudimos leer los datos de la persona en tu teléfono.'), findsOneWidget);
      expect(find.text(TextosFicha.reintentar), findsOneWidget);
    });
  });

  group('casos límite del flujo', () {
    testWidgets('si la lectura falla después de mostrar la ficha, dice el error con «Reintentar»', (
      tester,
    ) async {
      final repo = _FichaQueFallaDespues(persona: mariaDePrueba(), historial: historialDelCanvas());
      final m = mundoCompleto563();
      await montarFichaConRepo563(tester, m, repo);

      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
      repo.fallar();
      await asentar(tester);

      expect(find.byKey(ClavesFicha.error), findsOneWidget);
      expect(find.text(TextosFicha.reintentar), findsOneWidget);
      expect(find.text(TextosFicha.personaNoEncontrada), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mientras «Reintentar» vuelve a leer no dice que la persona ya no está', (
      tester,
    ) async {
      final repo = _FichaQueFallaDespues(persona: mariaDePrueba(), historial: historialDelCanvas());
      final m = mundoCompleto563();
      await montarFichaConRepo563(tester, m, repo);
      repo.fallar();
      await asentar(tester);
      repo.compuertaDeLaSiguienteLectura = Completer<void>();

      await tester.tap(find.text(TextosFicha.reintentar));
      await tester.pump(const Duration(milliseconds: 60));

      // Mientras lee: cargando (o el error), nunca «La persona ya no está en tu teléfono».
      expect(find.text(TextosFicha.personaNoEncontrada), findsNothing);
      repo.compuertaDeLaSiguienteLectura!.complete();
      await asentar(tester);
      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
    });

    testWidgets('la persona se da de baja en vivo: la ficha pasa a solo lectura sin reabrirla', (
      tester,
    ) async {
      final m = mundoCompleto563();
      await montarFicha(tester, m);
      expect(find.byKey(ClavesFicha.menu), findsOneWidget);
      expect(find.text(TextosFicha.masNota), findsOneWidget);

      m.fichas.poner(
        LecturaDeFicha(
          persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
          historial: historialDelCanvas(),
        ),
      );
      m.notas.contexto = contextoBajaDesde22();
      await asentar(tester);

      expect(find.byKey(ClavesFicha.aviso), findsOneWidget);
      expect(find.byKey(ClavesFicha.menu), findsNothing);
      expect(find.text(TextosFicha.masNota), findsNothing);
    });

    testWidgets(
      '«Ver más» sigue abierto cuando llega un movimiento nuevo y no sobra en 101 ni en 130',
      (tester) async {
        final m = mundoDe563(EstadoFicha.muchosMovimientos);
        await montarFicha(tester, m, tamano: telefonoGrande563);
        final lista = find.byType(Scrollable).first;

        await tester.scrollUntilVisible(find.byKey(ClavesFicha.verMas), 400, scrollable: lista);
        expect(find.text(TextosFicha.verMas(30)), findsOneWidget);
        await tester.ensureVisible(find.byKey(ClavesFicha.verMas));
        await tester.pump();
        await tester.tap(find.byKey(ClavesFicha.verMas));
        await asentar(tester);
        expect(find.byKey(ClavesFicha.verMas), findsNothing);
        expect(find.text(TextosFicha.verMas(30)), findsNothing);

        // 101: un movimiento más que la página.
        m.fichas.poner(
          LecturaDeFicha(
            persona: mariaDePrueba(),
            historial: [
              for (var i = 0; i < 101; i++)
                visitaEnFicha('v-${i.toString().padLeft(3, '0')}', DateTime(2026, 6, 1, i % 24, i)),
            ],
          ),
        );
        await asentar(tester);
        // Ya había abierto 200: con 101 no hay nada más que mostrar.
        expect(find.byKey(ClavesFicha.verMas), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('101 movimientos ofrecen «Ver más (1)»', (tester) async {
      final m = mundoCompleto563();
      m.fichas.poner(
        LecturaDeFicha(
          persona: mariaDePrueba(),
          historial: [
            for (var i = 0; i < 101; i++)
              visitaEnFicha(
                'v-${i.toString().padLeft(3, '0')}',
                DateTime(2026, 6, 1).add(Duration(hours: i)),
              ),
          ],
        ),
      );
      await montarFicha(tester, m);
      await tester.scrollUntilVisible(
        find.byKey(ClavesFicha.verMas),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text(TextosFicha.verMas(1)), findsOneWidget);
    });

    testWidgets('«+ Nota», volver y «+ Nota» otra vez: el guard se suelta y abre de nuevo', (
      tester,
    ) async {
      await montarFicha(tester, mundoCompleto563());

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(ClavesFicha.botonNota));
        await asentar(tester);
        expect(find.text(TextosNotas.guardarNota), findsOneWidget, reason: 'vuelta $i');
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await asentar(tester);
        expect(find.byKey(ClavesFicha.botonNota), findsOneWidget, reason: 'volvió en la vuelta $i');
      }
    });

    testWidgets('«Llamar» cuando el marcador lanza: avisa y el botón vuelve a poder tocarse', (
      tester,
    ) async {
      final m = mundoCompleto563();
      m.marcador.lanza = StateError('sin marcador');
      await montarFicha(tester, m);

      await tester.tap(find.byKey(ClavesFicha.botonLlamar));
      await asentar(tester);
      expect(find.text(TextosFicha.noPudimosAbrirElTelefono), findsOneWidget);

      m.marcador.lanza = null;
      await tester.tap(find.byKey(ClavesFicha.botonLlamar));
      await asentar(tester);
      expect(m.marcador.numeros, hasLength(2));
    });

    testWidgets('el aviso de «No pudimos abrir el teléfono» sugiere «Ver» y «Ver» sigue a mano', (
      tester,
    ) async {
      final m = mundoCompleto563();
      m.marcador.abre = false;
      await montarFicha(tester, m);

      await tester.tap(find.byKey(ClavesFicha.botonLlamar));
      await asentar(tester);

      expect(find.textContaining('Tocá «Ver»'), findsOneWidget);
      expect(find.byKey(ClavesFicha.botonVer), findsOneWidget);
    });

    for (final estado in [
      EstadoFicha.cargando,
      EstadoFicha.error,
      EstadoFicha.personaNoEncontrada,
      EstadoFicha.completa,
      EstadoFicha.sinHistorial,
      EstadoFicha.personaDeBaja,
      EstadoFicha.deptoDeBaja,
    ]) {
      testWidgets('volver atrás desde «${estado.rotulo}» cierra la ficha', (tester) async {
        await llegarAFicha(tester, estado, tamano: telefonoChico563);

        await volverAtras(tester);

        expect(find.text('abrir ficha'), findsOneWidget);
        expect(find.byType(Scrollable), findsNothing);
      });
    }

    testWidgets('«Reintentar» tras un error de lectura trae la ficha cuando ya se puede leer', (
      tester,
    ) async {
      final m = mundoDe563(EstadoFicha.error);
      await montarFicha(tester, m);
      expect(find.byKey(ClavesFicha.error), findsOneWidget);

      m.fichas.errorAlObservar = null;
      await tester.tap(find.text(TextosFicha.reintentar));
      await asentar(tester);

      expect(find.byKey(ClavesFicha.error), findsNothing);
      expect(find.text('María Pérez'), findsOneWidget);
    });

    testWidgets('una cuenta que no se puede leer no deja una ficha a medias', (tester) async {
      final m = mundoCompleto563();
      m.cuentas.lanza = StateError('x');
      await montarFicha(tester, m);

      expect(find.byKey(ClavesFicha.error), findsOneWidget);
      expect(find.byKey(ClavesFicha.cuenta), findsNothing);
    });
  });

  group('accesibilidad y lector de pantalla', () {
    testWidgets('el estado «cargando» se anuncia con contexto y sin spinner mudo', (tester) async {
      final h = tester.ensureSemantics();
      await llegarAFicha(tester, EstadoFicha.cargando);

      expect(find.bySemanticsLabel('Cargando la ficha'), findsOneWidget);
      h.dispose();
    });

    testWidgets('el error al leer es una región viva con su botón «Reintentar»', (tester) async {
      final h = tester.ensureSemantics();
      await llegarAFicha(tester, EstadoFicha.error);

      final nodo = tester.getSemantics(find.textContaining('No pudimos leer los datos'));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      final reintentar = tester.getSemantics(find.text(TextosFicha.reintentar));
      expect(reintentar.flagsCollection.isButton, isTrue);
      h.dispose();
    });

    testWidgets('mientras está enmascarado el lector no recibe el número y dice cómo termina', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarAFicha(tester, EstadoFicha.completa);

      expect(find.bySemanticsLabel('Teléfono terminado en 456'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('123')), findsNothing);
      h.dispose();
    });

    testWidgets('«Ver» y «Llamar» se leen como botones con acción de toque', (tester) async {
      final h = tester.ensureSemantics();
      await llegarAFicha(tester, EstadoFicha.completa);

      for (final clave in [ClavesFicha.botonVer, ClavesFicha.botonLlamar]) {
        final nodo = tester.getSemantics(find.byKey(clave));
        expect(nodo.flagsCollection.isButton, isTrue);
        expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }
      h.dispose();
    });

    testWidgets('la ficha deja una cabecera de nombre y las secciones son encabezados', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarAFicha(tester, EstadoFicha.completa, tamano: telefonoGrande563);

      expect(tester.getSemantics(find.text('María Pérez')).flagsCollection.isHeader, isTrue);
      expect(
        tester.getSemantics(find.text(TextosFicha.notasRotulo)).flagsCollection.isHeader,
        isTrue,
      );
      h.dispose();
    });
  });

  group('32B·03 filtro por estado (segunda ronda)', () {
    testWidgets('el lector oye «Todo, elegido» y cada opción es un botón elegible', (tester) async {
      final h = tester.ensureSemantics();
      await llegarAFicha(tester, EstadoFicha.completa);
      final todo = find.byKey(ClavesFicha.filtro(FiltroDeHistorial.todo));
      await llegarA563(tester, todo);

      final nodoTodo = tester.getSemantics(todo);
      expect(nodoTodo.label, 'Todo, elegido');
      expect(nodoTodo.flagsCollection.isSelected, Tristate.isTrue);
      expect(nodoTodo.flagsCollection.isButton, isTrue);
      final nodoSaldo = tester.getSemantics(
        find.byKey(ClavesFicha.filtro(FiltroDeHistorial.conSaldo)),
      );
      expect(nodoSaldo.label, 'Con saldo');
      expect(nodoSaldo.flagsCollection.isSelected, Tristate.isFalse);
      h.dispose();
    });

    testWidgets('el lector elige una opción con la acción de toque y cambia lo elegido', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarAFicha(tester, EstadoFicha.completa);
      final saldo = find.byKey(ClavesFicha.filtro(FiltroDeHistorial.conSaldo));
      await llegarA563(tester, saldo);

      tester.semantics.performAction(find.semantics.byLabel('Con saldo'), SemanticsAction.tap);
      await asentar(tester);

      expect(tester.getSemantics(saldo).label, 'Con saldo, elegido');
      expect(
        tester.getSemantics(find.byKey(ClavesFicha.filtro(FiltroDeHistorial.todo))).label,
        'Todo',
      );
      h.dispose();
    });

    testWidgets('cambiar de opción muchas veces seguidas deja una sola elegida y sin errores', (
      tester,
    ) async {
      await llegarAFicha(tester, EstadoFicha.conEntregasYCobros, tamano: telefonoGrande563);
      const opciones = FiltroDeHistorial.values;
      await llegarA563(tester, find.byKey(ClavesFicha.filtro(opciones.first)));
      for (var i = 0; i < 12; i++) {
        final f = opciones[i % opciones.length];
        await tester.tap(find.byKey(ClavesFicha.filtro(f)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await asentar(tester);

      final elegidas = [
        for (final f in opciones)
          if (tester.widget<ChoiceChip>(find.byKey(ClavesFicha.filtro(f))).selected) f,
      ];
      expect(elegidas, [opciones[11 % opciones.length]]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el filtro sin resultados el aviso dice qué pasa y «Todo» a mano lo deshace', (
      tester,
    ) async {
      await llegarAFicha(tester, EstadoFicha.filtroSinResultados);

      expect(
        find.text(TextosFicha.sinResultadosDelFiltro(FiltroDeHistorial.entregaPendiente)),
        findsOneWidget,
      );
      final todo = find.byKey(ClavesFicha.filtro(FiltroDeHistorial.todo));
      await llegarA563(tester, todo);
      await tester.tap(todo);
      await asentar(tester);
      expect(find.byKey(ClavesFicha.sinResultados), findsNothing);
      expect(find.byKey(ClavesFicha.fila('ven-1')), findsOneWidget);
    });

    testWidgets('sin historial no hay filtro (nada que filtrar)', (tester) async {
      await llegarAFicha(tester, EstadoFicha.sinHistorial);

      expect(find.text(TextosFicha.mostrar), findsNothing);
      expect(find.byKey(ClavesFicha.filtro(FiltroDeHistorial.todo)), findsNothing);
    });

    testWidgets(
      'sin fuente de cobros la tarjeta de la cuenta no se muestra ni dice «Sin movimientos»',
      (tester) async {
        await llegarAFicha(tester, EstadoFicha.sinMovimientos);

        expect(find.byKey(ClavesFicha.cuenta), findsNothing);
        expect(find.text('Sin movimientos aún'), findsNothing);
        expect(find.byKey(ClavesFicha.fila('ven-1')), findsOneWidget);
      },
    );

    testWidgets('los avisos de solo lectura dicen qué reactivar primero', (tester) async {
      await llegarAFicha(tester, EstadoFicha.ubicacionDeBaja);
      expect(find.textContaining(TextosFicha.reactivarPrimeroLaUbicacion), findsOneWidget);
      expect(find.text(TextosFicha.masNota), findsNothing);
    });

    testWidgets('sin ningún depto activo el aviso dice qué reactivar', (tester) async {
      await llegarAFicha(tester, EstadoFicha.sinDeptoActivo);
      expect(find.textContaining(TextosFicha.reactivarElDepto), findsOneWidget);
      expect(find.text(TextosFicha.masNota), findsNothing);
    });
  });

  group('hallazgos de la QA (se corren con --dart-define=QA_HALLAZGOS=true)', () {
    // skip: issue #141 — a 360×640 con el texto al 200 % «Comprado» se parte por la mitad («Comprad» / «o»).
    testWidgets('las filas de la cuenta no parten una palabra a 360×640 con el texto al 200 %', (
      tester,
    ) async {
      await llegarAFicha(tester, EstadoFicha.completa, escala: 2);
      await traer563(tester, find.text(TextosFicha.comprado));

      // Una sola línea de 28 px (200 % de 14): con dos líneas la palabra se partió.
      for (final rotulo in [
        TextosFicha.comprado,
        TextosFicha.entregado,
        TextosFicha.pagado,
        TextosFicha.saldo,
      ]) {
        expect(
          tester.getSize(find.text(rotulo)).height,
          lessThan(45),
          reason: '«$rotulo» ocupa más de una línea: la palabra se parte',
        );
      }
    }, skip: !hallazgos);

    // skip: issue #141 — «Ver», «Llamar», «+ Nota», «Reactivar» y «Reintentar» no traen `fontFamily`: salen
    // en la letra del sistema y no en Inter como el resto de la ficha.
    testWidgets('los botones de texto de la ficha usan la letra del tema (Inter)', (tester) async {
      await llegarAFicha(tester, EstadoFicha.completa, tamano: telefonoGrande563);

      for (final rotulo in [TextosFicha.ver, TextosFicha.llamar, TextosFicha.masNota]) {
        final texto = find.text(rotulo).first;
        final estilo = DefaultTextStyle.of(
          tester.element(texto),
        ).style.merge(tester.widget<Text>(texto).style);
        expect(estilo.fontFamily, 'Inter', reason: '«$rotulo» sin la letra del tema');
      }
    }, skip: !hallazgos);

    // skip: issue #141 — «La persona ya no está en tu teléfono. Volvé atrás.» no se anuncia al lector.
    testWidgets('cuando la persona ya no está, el aviso se anuncia como región viva', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarAFicha(tester, EstadoFicha.personaNoEncontrada);

      final nodo = tester.getSemantics(find.text(TextosFicha.personaNoEncontrada));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      h.dispose();
    }, skip: !hallazgos);
  });
}
