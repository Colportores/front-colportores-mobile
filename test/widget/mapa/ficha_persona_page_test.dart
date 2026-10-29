// La ficha de una persona (HU-UBI-009, vista 32B): todos los artboards del canvas y sus casos límite.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/services/filtro_de_historial.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_baja_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ficha_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_notas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ficha_persona_arnes.dart';

/// Lleva [finder] a la vista: la lista calcula su largo a medida que arma las filas, así que hace
/// falta pasar dos veces.
Future<void> traer(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 2; i++) {
    await tester.ensureVisible(finder);
    await tester.pump();
  }
}

void main() {
  /// El mundo del canvas 32B·01: María con teléfono, cuenta, dos notas, una venta y una visita.
  MundoFicha mundoDelCanvas() {
    final m = MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha());
    m.cuentas.cuenta = cuentaConSaldo;
    return m;
  }

  group('32B·01 Ficha', () {
    testWidgets('muestra el nombre, dónde está, el teléfono, la cuenta, la nota y el historial', (
      tester,
    ) async {
      await montarFicha(tester, mundoDelCanvas());

      expect(find.text('María Pérez'), findsOneWidget);
      expect(find.textContaining('Mataojo 2044'), findsOneWidget);
      expect(find.text('+598 99 *** 456'), findsOneWidget);
      expect(find.text(TextosFicha.ver), findsOneWidget);
      expect(find.text(TextosFicha.llamar), findsOneWidget);
      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
      expect(find.text(TextosFicha.comprado), findsOneWidget);
      expect(find.text(TextosFicha.saldo), findsOneWidget);
      expect(find.text(TextosFicha.notasRotulo), findsOneWidget);
      expect(find.text(TextosFicha.masNota), findsOneWidget);
      expect(find.text('HOY 14:20 · 1 DE 2'), findsOneWidget);
      expect(find.text(TextosFicha.historial), findsOneWidget);
      expect(find.text('12/10 · VENTA 0042'), findsOneWidget);
      expect(find.text('Salud y Hogar + Nuestros Hijos'), findsOneWidget);
      expect(find.text('05/10 · VISITA'), findsOneWidget);
      expect(find.text('Entrevista hecha'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el historial junta entregas y cobros con las visitas y ventas', (tester) async {
      final m = mundoDelCanvas();
      m.movimientos.poner([
        CobroEnFicha(
          id: 'cob-1',
          fecha: DateTime(2026, 10, 20, 12),
          montoCentavos: 60000,
          efectivo: true,
          numeroTalonario: '0042',
        ),
        EntregaEnFicha(
          id: 'ent-1',
          fecha: DateTime(2026, 10, 26, 12),
          pendiente: true,
          lineas: const [LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1)],
        ),
      ]);
      await montarFicha(tester, m);

      expect(find.text('20/10 · COBRO'), findsOneWidget);
      expect(find.text('LUN 26/10 · ENTREGA PENDIENTE'), findsOneWidget);
      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
      // De la más nueva a la más vieja.
      final y = [
        for (final id in ['ent-1', 'cob-1', 'ven-1', 'vis-1'])
          tester.getTopLeft(find.byKey(ClavesFicha.fila(id))).dy,
      ];
      expect(y, orderedEquals([...y]..sort()));
    });

    testWidgets(
      'sin la cuenta (todavía no hay de dónde saberla) no muestra la tarjeta ni la inventa',
      (tester) async {
        final m = MundoFicha(historial: historialDelCanvas());
        await montarFicha(tester, m);

        expect(find.byKey(ClavesFicha.cuenta), findsNothing);
        expect(find.text('Sin movimientos aún'), findsNothing);
        expect(find.text(TextosFicha.saldo), findsNothing);
        expect(find.byKey(ClavesFicha.historial), findsOneWidget);
      },
    );

    testWidgets('sin notas muestra «Todavía no hay notas» y «+ Nota» si hay historial', (
      tester,
    ) async {
      await montarFicha(tester, MundoFicha(historial: historialDelCanvas()));

      expect(find.text(TextosFicha.sinNotas), findsOneWidget);
      expect(find.text(TextosFicha.masNota), findsOneWidget);
    });

    testWidgets('se mantiene al día: una visita nueva aparece sin volver a abrir', (tester) async {
      final m = mundoDelCanvas();
      await montarFicha(tester, m);
      expect(find.byKey(ClavesFicha.fila('vis-2')), findsNothing);

      m.fichas.poner(
        LecturaDeFicha(
          persona: mariaDePrueba(),
          historial: [visitaEnFicha('vis-2', DateTime(2026, 10, 22, 13)), ...historialDelCanvas()],
        ),
      );
      await asentar(tester);

      expect(find.byKey(ClavesFicha.fila('vis-2')), findsOneWidget);
    });

    testWidgets('«+ Nota» abre el formulario de la nota nueva', (tester) async {
      await montarFicha(tester, mundoDelCanvas());

      await tester.tap(find.text(TextosFicha.masNota));
      await asentar(tester);

      expect(find.text(TextosNotas.tituloNueva), findsWidgets);
    });

    testWidgets('tocar la última nota abre «Notas de María»', (tester) async {
      await montarFicha(tester, mundoDelCanvas());

      await tester.tap(find.byKey(ClavesFicha.ultimaNota));
      await asentar(tester);

      expect(find.text(TextosNotas.titulo('María')), findsWidgets);
    });

    testWidgets('dos toques seguidos en «+ Nota» abren un solo formulario', (tester) async {
      await montarFicha(tester, mundoDelCanvas());

      await tester.tap(find.text(TextosFicha.masNota));
      await tester.tap(find.text(TextosFicha.masNota), warnIfMissed: false);
      await asentar(tester);
      await tester.tap(find.byTooltip(TextosNotas.cerrar).first);
      await asentar(tester);

      // Si se hubieran abierto dos, quedaría otro formulario encima de la ficha.
      expect(find.text('María Pérez'), findsOneWidget);
    });

    testWidgets('la nota larga se muestra con sus primeras 200 caracteres', (tester) async {
      final m = MundoFicha(
        historial: historialDelCanvas(),
        notasIniciales: [notaDePrueba('larga', 'x' * 450)],
      );
      await montarFicha(tester, m);

      expect(find.textContaining('x' * 200), findsOneWidget);
      expect(find.textContaining('x' * 201), findsNothing);
      expect(find.textContaining('…'), findsOneWidget);
    });

    testWidgets('volver atrás y reentrar muestra la ficha de nuevo', (tester) async {
      final m = mundoDelCanvas();
      await montarFicha(tester, m);

      await volverAtras(tester);
      expect(find.text('María Pérez'), findsNothing);
      await tester.tap(find.text('abrir ficha'));
      await asentar(tester);

      expect(find.text('María Pérez'), findsOneWidget);
    });
  });

  group('32B·02 Teléfono a la vista', () {
    testWidgets('«Ver» muestra el número entero y avisa que se vuelve a ocultar', (tester) async {
      await montarFicha(tester, mundoDelCanvas());

      await tester.tap(find.text(TextosFicha.ver));
      await asentar(tester);

      expect(find.text('+598 99 123 456'), findsOneWidget);
      expect(find.text('+598 99 *** 456'), findsNothing);
      expect(find.text(TextosFicha.seVuelveAOcultar), findsOneWidget);
      expect(find.text(TextosFicha.ver), findsNothing);
      expect(find.text(TextosFicha.llamar), findsOneWidget);
    });

    testWidgets('al salir y volver a entrar el teléfono vuelve a estar oculto', (tester) async {
      await montarFicha(tester, mundoDelCanvas());
      await tester.tap(find.text(TextosFicha.ver));
      await asentar(tester);

      await volverAtras(tester);
      await tester.tap(find.text('abrir ficha'));
      await asentar(tester);

      expect(find.text('+598 99 *** 456'), findsOneWidget);
      expect(find.text('+598 99 123 456'), findsNothing);
    });

    testWidgets('el lector de pantalla no recibe el número mientras está oculto', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarFicha(tester, mundoDelCanvas());

      expect(find.bySemanticsLabel('Teléfono terminado en 456'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('123')), findsNothing);
      semantica.dispose();
    });

    testWidgets('«Llamar» audita click_to_call sin el número y abre el marcador', (tester) async {
      final m = mundoDelCanvas();
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.llamar));
      await asentar(tester);

      expect(m.marcador.numeros, ['099123456']);
      expect(m.fichas.llamadas, hasLength(1));
      expect(m.fichas.llamadas.single.personaId, 'per-1');
      expect(m.fichas.llamadas.single.toString(), isNot(contains('123456')));
    });

    testWidgets('doble toque en «Llamar»: una sola llamada y el botón se apaga mientras tanto', (
      tester,
    ) async {
      final m = mundoDelCanvas();
      m.marcador.compuerta = Completer<void>();
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.llamar));
      await tester.pump();
      await tester.tap(find.text(TextosFicha.llamar), warnIfMissed: false);
      await asentar(tester);

      expect(m.marcador.numeros, hasLength(1));
      expect(tester.widget<TextButton>(find.byKey(ClavesFicha.botonLlamar)).onPressed, isNull);

      m.marcador.compuerta!.complete();
      await asentar(tester);
      expect(tester.widget<TextButton>(find.byKey(ClavesFicha.botonLlamar)).onPressed, isNotNull);
    });

    testWidgets('si no hay marcador avisa qué hacer y el botón vuelve a poder tocarse', (
      tester,
    ) async {
      final m = mundoDelCanvas();
      m.marcador.abre = false;
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.llamar));
      await asentar(tester);

      expect(find.text(TextosFicha.noPudimosAbrirElTelefono), findsOneWidget);
      expect(find.textContaining('099'), findsNothing);
      m.marcador.abre = true;
      await tester.tap(find.text(TextosFicha.llamar));
      await asentar(tester);
      expect(m.marcador.numeros, hasLength(2));
    });

    testWidgets('si la auditoría falla, la llamada sale igual', (tester) async {
      final m = mundoDelCanvas();
      m.fichas.fallaAlLlamar = const FailureInesperado();
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.llamar));
      await asentar(tester);

      expect(m.marcador.numeros, hasLength(1));
      expect(find.text(TextosFicha.noPudimosAbrirElTelefono), findsNothing);
    });

    testWidgets('«Ver» y «Llamar» se tocan con 48 de alto como mínimo', (tester) async {
      await montarFicha(tester, mundoDelCanvas());

      for (final clave in [ClavesFicha.botonVer, ClavesFicha.botonLlamar]) {
        expect(tester.getSize(find.byKey(clave)).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(find.byKey(clave)).width, greaterThanOrEqualTo(48));
      }
    });
  });

  group('32B·05 Sin historial', () {
    testWidgets('sin visitas ni ventas: el aviso, sin teléfono y «Registrar visita»', (
      tester,
    ) async {
      final m = MundoFicha(persona: mariaDePrueba(telefono: null))
        ..conEdicion = true
        ..conRegistrarVisita = true;
      await montarFicha(tester, m);

      expect(find.text(TextosFicha.sinTelefono), findsOneWidget);
      expect(find.text(TextosFicha.agregarTelefono), findsOneWidget);
      expect(find.text(TextosFicha.llamar), findsNothing);
      expect(find.text(TextosFicha.sinHistorialTitulo), findsOneWidget);
      expect(find.text('Lo que registres con María aparece acá.'), findsOneWidget);
      expect(find.byKey(ClavesFicha.cuenta), findsNothing);
      expect(find.byKey(ClavesFicha.historial), findsNothing);
      expect(find.text(TextosFicha.registrarVisita), findsOneWidget);
    });

    testWidgets('«Registrar visita» lleva a la ubicación y el espacio de la ficha', (tester) async {
      final m = MundoFicha()..conRegistrarVisita = true;
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.registrarVisita));
      await asentar(tester);

      expect(m.visitas.single.ubicacionId, 'ub-1');
      expect(m.visitas.single.espacioId, 'esp-1');
    });

    testWidgets('sin a dónde llevar, «Registrar visita» y «Agregar» no se ofrecen', (tester) async {
      await montarFicha(tester, MundoFicha(persona: mariaDePrueba(telefono: null)));

      expect(find.text(TextosFicha.registrarVisita), findsNothing);
      expect(find.text(TextosFicha.agregarTelefono), findsNothing);
      expect(find.text(TextosFicha.sinTelefono), findsOneWidget);
    });

    testWidgets('un teléfono en blanco es como no tener: no hay «Llamar»', (tester) async {
      await montarFicha(tester, MundoFicha(persona: mariaDePrueba(telefono: '   ')));

      expect(find.text(TextosFicha.sinTelefono), findsOneWidget);
      expect(find.text(TextosFicha.llamar), findsNothing);
    });

    testWidgets('«Agregar» teléfono abre la edición de la persona', (tester) async {
      final m = MundoFicha(persona: mariaDePrueba(telefono: null))..conEdicion = true;
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.agregarTelefono));
      await asentar(tester);

      expect(m.ediciones, ['per-1']);
    });

    testWidgets('con notas pero sin historial la sección de notas sigue a la vista', (
      tester,
    ) async {
      await montarFicha(tester, MundoFicha(notasIniciales: notasDeLaFicha()));

      expect(find.text(TextosFicha.sinHistorialTitulo), findsOneWidget);
      expect(find.text(TextosFicha.notasRotulo), findsOneWidget);
      expect(find.text(TextosFicha.masNota), findsOneWidget);
    });
  });

  group('32B·06 Cargando', () {
    testWidgets('mientras la ficha no llega muestra los bloques y lo dice el lector', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarFicha(tester, MundoFicha(cargando: true));

      expect(find.byKey(ClavesFicha.cargando), findsOneWidget);
      expect(find.bySemanticsLabel(TextosFicha.cargando(null)), findsOneWidget);
      expect(find.text('María Pérez'), findsNothing);
      // La flecha de atrás sigue funcionando.
      await volverAtras(tester);
      expect(find.byKey(ClavesFicha.cargando), findsNothing);
      semantica.dispose();
    });
  });

  group('32B·07 Error al leer', () {
    testWidgets('dice que no pudo leer y «Reintentar» vuelve a leer', (tester) async {
      final m = mundoDelCanvas();
      m.fichas.errorAlObservar = StateError('no se pudo leer');
      await montarFicha(tester, m);

      expect(find.byKey(ClavesFicha.error), findsOneWidget);
      expect(find.text(TextosFicha.noPudimosLeer(null)), findsOneWidget);
      expect(find.text('María Pérez'), findsNothing);

      m.fichas.errorAlObservar = null;
      await tester.tap(find.text(TextosFicha.reintentar));
      await asentar(tester);

      expect(find.text('María Pérez'), findsOneWidget);
      expect(find.byKey(ClavesFicha.error), findsNothing);
    });

    testWidgets('si falla otra vez, sigue el error y se puede volver a reintentar', (tester) async {
      final m = mundoDelCanvas();
      m.fichas.errorAlObservar = StateError('no se pudo leer');
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.reintentar));
      await asentar(tester);
      expect(find.byKey(ClavesFicha.error), findsOneWidget);

      m.fichas.errorAlObservar = null;
      await tester.tap(find.text(TextosFicha.reintentar));
      await asentar(tester);
      expect(find.text('María Pérez'), findsOneWidget);
    });

    testWidgets('si no se puede leer la cuenta tampoco muestra una ficha a medias', (tester) async {
      final m = mundoDelCanvas();
      m.cuentas.lanza = StateError('no se pudo leer la cuenta');
      await montarFicha(tester, m);

      expect(find.byKey(ClavesFicha.error), findsOneWidget);
      expect(find.byKey(ClavesFicha.historial), findsNothing);
    });
  });

  testWidgets('la persona que ya no está en el teléfono dice que se vuelva atrás', (tester) async {
    final m = MundoFicha();
    m.fichas.poner(null);
    await montarFicha(tester, m);

    expect(find.text(TextosFicha.personaNoEncontrada), findsOneWidget);
  });

  group('32B·04 Persona de baja (solo lectura)', () {
    MundoFicha mundoDeBaja() {
      final persona = mariaDePrueba(baja: DateTime(2026, 10, 22));
      final m = MundoFicha(
        persona: persona,
        historial: historialDelCanvas(),
        notasIniciales: notasDeLaFicha(),
        contexto: contextoBajaDesde22(),
      )..conEdicion = true;
      m.cuentas.cuenta = cuentaConSaldo;
      m.personas.sembrar([clienteDeBajaDePersonas('per-1', 'María', apellido: 'Pérez')]);
      return m;
    }

    testWidgets('dice el aviso del canvas, deja ver todo y no ofrece escribir nada', (
      tester,
    ) async {
      await montarFicha(tester, mundoDeBaja(), tamano: const Size(390, 1600));

      expect(
        find.text(
          'María está de baja desde el 22/10. Podés ver su historial, pero no registrar nada.',
        ),
        findsOneWidget,
      );
      expect(find.text(TextosFicha.reactivar), findsOneWidget);
      expect(find.text('12/10 · VENTA 0042'), findsOneWidget);
      expect(find.text(TextosFicha.masNota), findsNothing);
      expect(find.text(TextosFicha.verNotas(2)), findsOneWidget);
      expect(find.byKey(ClavesFicha.menu), findsNothing);
      expect(find.text(TextosFicha.llamar), findsOneWidget);
    });

    testWidgets('«Ver (2)» abre las notas en solo lectura', (tester) async {
      await montarFicha(tester, mundoDeBaja());

      await tester.tap(find.text(TextosFicha.verNotas(2)));
      await asentar(tester);

      expect(find.text(TextosNotas.titulo('María')), findsWidgets);
    });

    testWidgets('sin notas y de baja no hay nada que abrir', (tester) async {
      final m = MundoFicha(
        persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
        historial: historialDelCanvas(),
        contexto: contextoBajaDesde22(),
      );
      await montarFicha(tester, m);

      expect(find.byKey(ClavesFicha.botonNota), findsNothing);
      expect(find.text(TextosFicha.sinNotas), findsOneWidget);
    });

    testWidgets('«Reactivar» reactiva a la persona y avisa', (tester) async {
      final m = mundoDeBaja();
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.reactivar));
      await asentar(tester);

      expect(m.personas.reactivacionesRecibidas, ['per-1']);
      expect(find.text(TextosBajaPersona.activaDeNuevo('María')), findsOneWidget);
    });

    testWidgets('reactivada, la ficha deja de ser de solo lectura al llegar la lectura nueva', (
      tester,
    ) async {
      final m = mundoDeBaja();
      await montarFicha(tester, m);
      await tester.tap(find.text(TextosFicha.reactivar));
      await asentar(tester);

      m.notas.contexto = const ContextoNotasPersona(nombre: 'María');
      m.fichas.poner(LecturaDeFicha(persona: mariaDePrueba(), historial: historialDelCanvas()));
      await asentar(tester);

      expect(find.text(TextosFicha.reactivar), findsNothing);
      expect(find.text(TextosFicha.masNota), findsOneWidget);
      expect(find.byKey(ClavesFicha.menu), findsOneWidget);
    });

    testWidgets('doble toque en «Reactivar»: una sola reactivación y dice «Reactivando…»', (
      tester,
    ) async {
      final m = mundoDeBaja();
      m.personas.compuertaReactivar = Completer<void>();
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.reactivar));
      await tester.pump();
      expect(find.text(TextosFicha.reactivando), findsOneWidget);
      await tester.tap(find.text(TextosFicha.reactivando), warnIfMissed: false);
      await asentar(tester);

      expect(m.personas.reactivacionesRecibidas, hasLength(1));
      m.personas.compuertaReactivar!.complete();
      await asentar(tester);
    });

    testWidgets('si falla, el botón vuelve a estar tocable y el aviso dice qué hacer', (
      tester,
    ) async {
      final m = mundoDeBaja();
      m.personas.resultadosReactivar.add(const FailureInesperado());
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.reactivar));
      await asentar(tester);

      expect(find.text(TextosFicha.noPudimosReactivar('María')), findsOneWidget);
      expect(find.text(TextosFicha.reactivando), findsNothing);
      await tester.tap(find.text(TextosFicha.reactivar));
      await asentar(tester);
      expect(m.personas.reactivacionesRecibidas, hasLength(2));
    });

    testWidgets('si la validación del repositorio dice qué pasó, lo dice tal cual', (tester) async {
      final m = mundoDeBaja();
      m.personas.resultadosReactivar.add(
        const FailureValidacion(campos: {'espacio': 'El depto está dado de baja.'}),
      );
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.reactivar));
      await asentar(tester);

      expect(find.text('El depto está dado de baja.'), findsOneWidget);
    });
  });

  group('32B·08 Espacio en baja (solo lectura)', () {
    MundoFicha mundoDeptoDeBaja({DateTime? ubicacionDeBaja}) {
      final m = MundoFicha(
        historial: historialDelCanvas(),
        notasIniciales: notasDeLaFicha(),
        contexto: contextoDeptoDeBaja,
        lugarInicial: (
          espacio: espacioDePersonas(numeroDepto: '3B', deletedAt: DateTime.utc(2026, 10, 20)),
          ubicacion: ubicacionDePersonas(deletedAt: ubicacionDeBaja),
        ),
      )..conEdicion = true;
      m.cuentas.cuenta = cuentaConSaldo;
      return m;
    }

    testWidgets('dice el aviso del canvas con «Reactivar el depto» y deja todo en solo lectura', (
      tester,
    ) async {
      await montarFicha(tester, mundoDeptoDeBaja(), tamano: const Size(390, 1600));

      expect(
        find.text('El depto 3B de Mataojo 2044 está dado de baja. La ficha queda en solo lectura.'),
        findsOneWidget,
      );
      expect(find.text(TextosFicha.reactivarDepto), findsOneWidget);
      expect(find.text(TextosFicha.masNota), findsNothing);
      expect(find.byKey(ClavesFicha.menu), findsNothing);
      expect(find.text('12/10 · VENTA 0042'), findsOneWidget);
    });

    testWidgets('«Reactivar el depto» lo restaura y avisa', (tester) async {
      final m = mundoDeptoDeBaja();
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.reactivarDepto));
      await asentar(tester);

      expect(m.espacios.restauraciones, ['esp-1']);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('doble toque: una sola restauración', (tester) async {
      final m = mundoDeptoDeBaja();
      m.espacios.compuertaRestaurar = Completer<void>();
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.reactivarDepto));
      await tester.pump();
      await tester.tap(find.text(TextosFicha.reactivando), warnIfMissed: false);
      await asentar(tester);

      expect(m.espacios.restauraciones, hasLength(1));
      m.espacios.compuertaRestaurar!.complete();
      await asentar(tester);
    });

    testWidgets('si falla, el botón vuelve a poder tocarse y dice qué hacer', (tester) async {
      final m = mundoDeptoDeBaja();
      m.espacios.resultadosRestaurar.add(const FailureInesperado());
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.reactivarDepto));
      await asentar(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(TextosFicha.reactivarDepto), findsOneWidget);
      await tester.tap(find.text(TextosFicha.reactivarDepto));
      await asentar(tester);
      expect(m.espacios.restauraciones, hasLength(2));
    });

    testWidgets('si la ubicación también está de baja, el depto no se puede reactivar solo', (
      tester,
    ) async {
      await montarFicha(tester, mundoDeptoDeBaja(ubicacionDeBaja: DateTime.utc(2026, 10, 20)));

      expect(find.byKey(ClavesFicha.aviso), findsOneWidget);
      expect(find.text(TextosFicha.reactivarDepto), findsNothing);
      expect(find.textContaining(TextosFicha.reactivarPrimeroLaUbicacion), findsOneWidget);
    });

    testWidgets('con el botón «Reactivar el depto» el aviso no suma la guía de la ubicación', (
      tester,
    ) async {
      await montarFicha(tester, mundoDeptoDeBaja());

      expect(find.textContaining(TextosFicha.reactivarPrimeroLaUbicacion), findsNothing);
    });

    testWidgets('sin ningún depto activo el aviso dice qué hacer', (tester) async {
      final m = MundoFicha(
        historial: historialDelCanvas(),
        contexto: const ContextoNotasPersona(
          nombre: 'María',
          causa: CausaSoloLectura.sinEspacioActivo,
        ),
      );
      await montarFicha(tester, m);

      expect(find.textContaining(TextosFicha.reactivarElDepto), findsOneWidget);
      expect(find.text(TextosFicha.masNota), findsNothing);
    });
  });

  group('32B·03 Filtro por estado', () {
    const alto = Size(390, 2600);

    /// María con una venta con saldo, una cobrada entera, una entrega pendiente y otra hecha.
    MundoFicha mundoConEstados() {
      final m = MundoFicha(
        historial: [
          VentaEnFicha(
            id: 'ven-2',
            fecha: DateTime(2026, 10, 12, 12),
            numeroTalonario: '0042',
            montoCentavos: 120000,
            lineas: const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
          ),
          VentaEnFicha(
            id: 'ven-1',
            fecha: DateTime(2026, 9, 1, 12),
            numeroTalonario: '0030',
            montoCentavos: 50000,
            lineas: const [LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1)],
          ),
          visitaEnFicha('vis-1', DateTime(2026, 10, 5, 12)),
        ],
        notasIniciales: notasDeLaFicha(),
      );
      m.cuentas.cuenta = cuentaConSaldo;
      m.movimientos.poner([
        CobroEnFicha(
          id: 'cob-1',
          fecha: DateTime(2026, 9, 10, 12),
          montoCentavos: 50000,
          efectivo: true,
          numeroTalonario: '0030',
        ),
        EntregaEnFicha(
          id: 'ent-1',
          fecha: DateTime(2026, 10, 26, 12),
          pendiente: true,
          lineas: const [LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1)],
        ),
        EntregaEnFicha(
          id: 'ent-0',
          fecha: DateTime(2026, 10, 12, 12),
          pendiente: false,
          lineas: const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
        ),
      ]);
      return m;
    }

    /// Lleva [finder] a la vista, venga de arriba o de abajo (la lista arma las filas a medida que
    /// se la recorre).
    Future<void> llegarA(WidgetTester tester, Finder finder) async {
      final lista = find.byType(Scrollable).first;
      await tester.drag(lista, const Offset(0, 20000));
      await tester.pump();
      await tester.scrollUntilVisible(finder, 400, scrollable: lista);
      await traer(tester, finder);
    }

    Future<void> elegir(WidgetTester tester, FiltroDeHistorial f) async {
      await llegarA(tester, find.byKey(ClavesFicha.filtro(f)));
      await tester.tap(find.byKey(ClavesFicha.filtro(f)));
      await asentar(tester);
    }

    void veSolo(List<String> ids) {
      for (final id in ['ven-2', 'ven-1', 'vis-1', 'cob-1', 'ent-1', 'ent-0']) {
        expect(
          find.byKey(ClavesFicha.fila(id)),
          ids.contains(id) ? findsOneWidget : findsNothing,
          reason: id,
        );
      }
    }

    testWidgets('«MOSTRAR» ofrece Todo, Con saldo y Entrega pendiente, y empieza en Todo', (
      tester,
    ) async {
      await montarFicha(tester, mundoConEstados(), tamano: alto);

      expect(find.text(TextosFicha.mostrar), findsOneWidget);
      expect(find.text('Todo'), findsOneWidget);
      expect(find.text('Con saldo'), findsOneWidget);
      expect(find.text('Entrega pendiente'), findsOneWidget);
      veSolo(['ven-2', 'ven-1', 'vis-1', 'cob-1', 'ent-1', 'ent-0']);
      expect(
        tester.widget<ChoiceChip>(find.byKey(ClavesFicha.filtro(FiltroDeHistorial.todo))).selected,
        isTrue,
      );
    });

    testWidgets('«Con saldo» deja solo la venta que se debe', (tester) async {
      await montarFicha(tester, mundoConEstados(), tamano: alto);

      await elegir(tester, FiltroDeHistorial.conSaldo);

      veSolo(['ven-2']);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(ClavesFicha.filtro(FiltroDeHistorial.conSaldo)))
            .selected,
        isTrue,
      );
      expect(find.byKey(ClavesFicha.sinResultados), findsNothing);
    });

    testWidgets('«Entrega pendiente» deja solo la entrega por hacer', (tester) async {
      await montarFicha(tester, mundoConEstados(), tamano: alto);

      await elegir(tester, FiltroDeHistorial.entregaPendiente);

      veSolo(['ent-1']);
    });

    testWidgets('volver a «Todo» trae todo de nuevo', (tester) async {
      await montarFicha(tester, mundoConEstados(), tamano: alto);
      await elegir(tester, FiltroDeHistorial.entregaPendiente);

      await elegir(tester, FiltroDeHistorial.todo);

      veSolo(['ven-2', 'ven-1', 'vis-1', 'cob-1', 'ent-1', 'ent-0']);
    });

    testWidgets('si el filtro no deja nada, lo dice y el historial queda vacío', (tester) async {
      final m = MundoFicha(historial: historialDelCanvas());
      m.cuentas.cuenta = cuentaConSaldo;
      await montarFicha(tester, m, tamano: alto);

      await elegir(tester, FiltroDeHistorial.entregaPendiente);

      expect(
        find.text(TextosFicha.sinResultadosDelFiltro(FiltroDeHistorial.entregaPendiente)),
        findsOneWidget,
      );
      expect(find.byType(FilaDeHistorial), findsNothing);
      // Y se puede volver a ver todo.
      await elegir(tester, FiltroDeHistorial.todo);
      expect(find.byKey(ClavesFicha.sinResultados), findsNothing);
      expect(find.byType(FilaDeHistorial), findsNWidgets(2));
    });

    testWidgets('una entrega que se hace con el filtro puesto sale de la lista en vivo', (
      tester,
    ) async {
      final m = mundoConEstados();
      await montarFicha(tester, m, tamano: alto);
      await elegir(tester, FiltroDeHistorial.entregaPendiente);
      veSolo(['ent-1']);

      m.movimientos.poner([
        EntregaEnFicha(
          id: 'ent-1',
          fecha: DateTime(2026, 10, 26, 12),
          pendiente: false,
          lineas: const [LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1)],
        ),
      ]);
      await asentar(tester);

      veSolo([]);
      expect(find.byKey(ClavesFicha.sinResultados), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente)))
            .selected,
        isTrue,
      );
    });

    testWidgets('al reentrar a la ficha el filtro vuelve a «Todo»', (tester) async {
      await montarFicha(tester, mundoConEstados(), tamano: alto);
      await elegir(tester, FiltroDeHistorial.conSaldo);

      await volverAtras(tester);
      await tester.tap(find.text('abrir ficha'));
      await asentar(tester);

      expect(
        tester.widget<ChoiceChip>(find.byKey(ClavesFicha.filtro(FiltroDeHistorial.todo))).selected,
        isTrue,
      );
      veSolo(['ven-2', 'ven-1', 'vis-1', 'cob-1', 'ent-1', 'ent-0']);
    });

    testWidgets('«Ver más» cuenta lo filtrado y cambiar de filtro vuelve a la primera página', (
      tester,
    ) async {
      final m = MundoFicha(
        historial: [
          for (var i = 0; i < 120; i++)
            VentaEnFicha(
              id: 'ven-${i.toString().padLeft(3, '0')}',
              fecha: DateTime(2026, 9, 1).subtract(Duration(hours: i)),
              numeroTalonario: '$i',
              montoCentavos: 1000,
              lineas: const [],
            ),
          for (var i = 0; i < 30; i++)
            visitaEnFicha(
              'vis-${i.toString().padLeft(3, '0')}',
              DateTime(2026, 6, 1).subtract(Duration(hours: i)),
            ),
        ],
      );
      m.cuentas.cuenta = cuentaConSaldo;
      await montarFicha(tester, m);
      await llegarA(tester, find.byKey(ClavesFicha.verMas));
      expect(find.text(TextosFicha.verMas(50)), findsOneWidget);

      await elegir(tester, FiltroDeHistorial.conSaldo);
      await llegarA(tester, find.byKey(ClavesFicha.verMas));
      expect(find.text(TextosFicha.verMas(20)), findsOneWidget);

      await tester.tap(find.byKey(ClavesFicha.verMas));
      await asentar(tester);
      expect(find.byKey(ClavesFicha.verMas), findsNothing);

      await elegir(tester, FiltroDeHistorial.todo);
      await llegarA(tester, find.byKey(ClavesFicha.verMas));
      expect(find.text(TextosFicha.verMas(50)), findsOneWidget);
    });

    testWidgets('también se puede filtrar con la ficha en solo lectura', (tester) async {
      final m = MundoFicha(
        persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
        historial: historialDelCanvas(),
        contexto: contextoBajaDesde22(),
      );
      m.cuentas.cuenta = cuentaConSaldo;
      await montarFicha(tester, m, tamano: alto);

      await elegir(tester, FiltroDeHistorial.conSaldo);

      expect(find.byKey(ClavesFicha.fila('ven-1')), findsOneWidget);
      expect(find.byKey(ClavesFicha.fila('vis-1')), findsNothing);
    });

    testWidgets('con texto al 200 % las opciones bajan de renglón sin desbordar', (tester) async {
      await montarFicha(tester, mundoConEstados(), escala: 2, tamano: const Size(320, 568));

      await llegarA(tester, find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente)));

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente))).height,
        greaterThanOrEqualTo(40),
      );
    });

    testWidgets('el lector oye cada opción y cuál está elegida', (tester) async {
      final asa = tester.ensureSemantics();
      await montarFicha(tester, mundoConEstados(), tamano: alto);

      expect(find.bySemanticsLabel('Todo, elegido'), findsOneWidget);
      expect(find.bySemanticsLabel('Con saldo'), findsOneWidget);
      expect(find.bySemanticsLabel('Entrega pendiente'), findsOneWidget);
      asa.dispose();
    });
  });

  group('menú «⋯»', () {
    testWidgets('«Editar persona» abre la edición con la persona', (tester) async {
      final m = mundoDelCanvas()..conEdicion = true;
      await montarFicha(tester, m);

      await tester.tap(find.byKey(ClavesFicha.menu));
      await asentar(tester);
      await tester.tap(find.byKey(ClavesFicha.opcionEditar));
      await asentar(tester);

      expect(m.ediciones, ['per-1']);
    });

    testWidgets('sin destino de edición el menú solo trae «Dar de baja»', (tester) async {
      await montarFicha(tester, mundoDelCanvas());

      await tester.tap(find.byKey(ClavesFicha.menu));
      await asentar(tester);

      expect(find.byKey(ClavesFicha.opcionEditar), findsNothing);
      expect(find.byKey(ClavesFicha.opcionBaja), findsOneWidget);
    });

    testWidgets('«Dar de baja» abre la hoja de la baja de la persona', (tester) async {
      await montarFicha(tester, mundoDelCanvas());

      await tester.tap(find.byKey(ClavesFicha.menu));
      await asentar(tester);
      await tester.tap(find.byKey(ClavesFicha.opcionBaja));
      await asentar(tester);

      expect(find.text(TextosBajaPersona.titulo('María')), findsOneWidget);
    });
  });

  group('casos límite', () {
    testWidgets('más de 100 movimientos: muestra 100 y «Ver más» trae el resto', (tester) async {
      final m = MundoFicha(
        historial: [
          for (var i = 0; i < 130; i++)
            visitaEnFicha(
              'vis-${i.toString().padLeft(3, '0')}',
              DateTime(2026, 9, 1).add(Duration(hours: i)),
            ),
        ].reversed.toList(),
      );
      await montarFicha(tester, m);
      await tester.scrollUntilVisible(
        find.byKey(ClavesFicha.verMas),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await traer(tester, find.byKey(ClavesFicha.verMas));

      expect(find.text(TextosFicha.verMas(30)), findsOneWidget);
      final visibles = tester.widgetList(find.byType(FilaDeHistorial)).length;
      expect(visibles, lessThanOrEqualTo(100));

      await traer(tester, find.byKey(ClavesFicha.verMas));
      await tester.tap(find.byKey(ClavesFicha.verMas));
      await asentar(tester);

      expect(find.byKey(ClavesFicha.verMas), findsNothing);
    });

    testWidgets('exactamente 100 movimientos no ofrece «Ver más»', (tester) async {
      final m = MundoFicha(
        historial: [
          for (var i = 0; i < 100; i++)
            visitaEnFicha(
              'vis-${i.toString().padLeft(3, '0')}',
              DateTime(2026, 9, 1).add(Duration(hours: i)),
            ),
        ],
      );
      await montarFicha(tester, m);

      expect(find.byKey(ClavesFicha.verMas), findsNothing);
    });

    testWidgets('con nombre y textos largos nada se desborda', (tester) async {
      final m = MundoFicha(
        persona: clienteDePersonas(
          'per-1',
          'María de los Ángeles Candelaria',
          apellido: 'Fernández de la Peña y Rodríguez Altamirano',
          telefono: '099123456',
        ).persona,
        historial: [
          VentaEnFicha(
            id: 'v',
            fecha: DateTime(2026, 10, 12),
            numeroTalonario: '0042',
            montoCentavos: 120000,
            lineas: [
              for (var i = 0; i < 6; i++)
                LineaDeFicha(nombre: 'Un libro con un título larguísimo número $i', cantidad: 2),
            ],
          ),
        ],
        notasIniciales: [notaDePrueba('n', 'palabra ' * 80)],
      );
      m.cuentas.cuenta = cuentaConSaldo;
      await montarFicha(tester, m, tamano: const Size(320, 568));

      expect(tester.takeException(), isNull);
    });

    for (final (nombre, preparar) in <(String, MundoFicha Function())>[
      (
        'la ficha completa',
        () =>
            MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha())
              ..cuentas.cuenta = cuentaConSaldo,
      ),
      (
        'sin historial y sin teléfono',
        () => MundoFicha(persona: mariaDePrueba(telefono: null))
          ..conEdicion = true
          ..conRegistrarVisita = true,
      ),
      (
        'persona de baja',
        () => MundoFicha(
          persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
          historial: historialDelCanvas(),
          notasIniciales: notasDeLaFicha(),
          contexto: contextoBajaDesde22(),
        ),
      ),
      (
        'depto de baja',
        () => MundoFicha(
          historial: historialDelCanvas(),
          contexto: contextoDeptoDeBaja,
          lugarInicial: (
            espacio: espacioDePersonas(numeroDepto: '3B', deletedAt: DateTime.utc(2026, 10, 20)),
            ubicacion: ubicacionDePersonas(),
          ),
        ),
      ),
      ('error al leer', () => MundoFicha()..fichas.errorAlObservar = StateError('x')),
      ('cargando', () => MundoFicha(cargando: true)),
    ]) {
      testWidgets('texto al 200 % en 320×568: $nombre no se desborda', (tester) async {
        await montarFicha(tester, preparar(), escala: 2, tamano: const Size(320, 568));

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('con el texto al 200 % el teléfono visible conserva «Llamar» tocable', (
      tester,
    ) async {
      await montarFicha(tester, mundoDelCanvas(), escala: 2, tamano: const Size(320, 568));
      await traer(tester, find.text(TextosFicha.ver));
      await tester.tap(find.text(TextosFicha.ver));
      await asentar(tester);

      expect(find.text('+598 99 123 456'), findsOneWidget);
      expect(find.text(TextosFicha.llamar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Llamar» y «Reactivar» seguidos no se pisan', (tester) async {
      final m = MundoFicha(
        persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
        historial: historialDelCanvas(),
        contexto: contextoBajaDesde22(),
      );
      m.personas.sembrar([clienteDeBajaDePersonas('per-1', 'María', apellido: 'Pérez')]);
      m.marcador.compuerta = Completer<void>();
      await montarFicha(tester, m);

      await tester.tap(find.text(TextosFicha.llamar));
      await tester.pump();
      await tester.tap(find.text(TextosFicha.reactivar));
      await asentar(tester);

      expect(m.personas.reactivacionesRecibidas, ['per-1']);
      m.marcador.compuerta!.complete();
      await asentar(tester);
      expect(m.marcador.numeros, hasLength(1));
    });
  });
}
