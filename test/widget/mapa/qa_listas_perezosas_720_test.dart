// QA #720 (PR #721): las listas que pasaron a `ListView.builder` —«Entregas pendientes»,
// «Ver borradas» de una persona y «Ver borradas» de un lugar— con 60 registros, en 360x640 y 412x915,
// a texto 1,0 y 2,0: sin desbordes, con las guías de accesibilidad arriba y al fondo, con las
// acciones sobre filas que se construyen al desplazar (restaurar, marcar entregado, fallas, doble
// toque) y los datos límite (vacío, uno, 25/26, textos largos).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/inicio/presentation/widgets/barra_pestanas_inicio.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/notas_borradas_del_lugar_page.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregas_pendientes_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/marcar_entregado_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/piezas_entrega_diferida.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';
import '../../helpers/nota_persona_falsos.dart';
import '../../helpers/nota_ubicacion_falsos.dart';
import 'notas_lugar_arnes.dart';
import 'notas_persona_arnes.dart';

const _tamanos = <(String, Size)>[('360x640', Size(360, 640)), ('412x915', Size(412, 915))];
const _escalas = <double>[1, 2];

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

/// Vuelve a la pantalla anterior (esta cabecera no usa la flecha de la barra de Material).
Future<void> _volver(WidgetTester tester) async {
  await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
  await asentar(tester);
}

/// Baja (o sube) la lista [lista] hasta el fondo (o el tope).
Future<void> _saltar(WidgetTester tester, Finder lista, {required bool alFondo}) async {
  final s = tester.state<ScrollableState>(
    find.descendant(of: lista, matching: find.byType(Scrollable)).first,
  );
  // La lista es perezosa: su largo se estima hasta construir las filas, así que se salta al fondo
  // varias veces hasta que el largo deja de cambiar.
  for (var i = 0; i < 6; i++) {
    s.position.jumpTo(alFondo ? s.position.maxScrollExtent : 0);
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

// ---------------------------------------------------------------------------------------------
// Entregas pendientes
// ---------------------------------------------------------------------------------------------

Route<PestanaInicio> _ruta() => EntregasPendientesPage.ruta(colportorId: 'col-1');

Finder get _lista => find.byKey(const Key('entregas_lista'));

/// [n] entregas: un tercio atrasadas, un tercio próximas y un tercio sin fecha, cada una de su venta;
/// la cantidad de la línea es distinta en cada una (así «Marcar entregado» dice cuál se tocó).
List<EntregaPendiente> _entregas(int n) {
  final tercio = n ~/ 3;
  return [
    for (var i = 0; i < n; i++)
      pendienteDe(
        'v-$i',
        fecha: i < tercio
            ? DateTime(2026, 10, 1 + i % 20, 10)
            : i < 2 * tercio
            ? DateTime(2026, 11, 1 + i % 25, 9)
            : null,
        vinculo: 'ep-${1 + i % 3}',
        lineas: [lineaDe('e-$i', 'p-hijos', 1 + i)],
      ),
  ];
}

EntornoDeEntrega _entorno(List<EntregaPendiente> lista) {
  final e = EntornoDeEntrega();
  e.entregas.emitirPendientes(lista);
  return e;
}

void main() {
  group('#720 Entregas pendientes: 60 registros en 4 tamaños', () {
    for (final (nombre, tam) in _tamanos) {
      for (final escala in _escalas) {
        testWidgets('$nombre x$escala: sin desbordes y con las guías arriba y al fondo', (
          tester,
        ) async {
          await montarPantalla(tester, _entorno(_entregas(60)), _ruta, tamano: tam, escala: escala);

          expect(tester.takeException(), isNull);
          await _guias(tester);

          await _saltar(tester, _lista, alFondo: true);
          expect(tester.takeException(), isNull);
          expect(find.text('Poner fecha'), findsWidgets);
          await _guias(tester);

          // Bajando de a poco hasta el fondo y subiendo: ningún cuadro desborda.
          for (var i = 0; i < 80; i++) {
            await tester.drag(_lista, const Offset(0, 260));
            await tester.pump();
            expect(tester.takeException(), isNull, reason: 'subiendo, paso $i');
          }
          await _saltar(tester, _lista, alFondo: false);
          expect(find.text('ATRASADAS'), findsOneWidget);
        });
      }
    }
  });

  group('#720 Entregas pendientes: acciones sobre filas construidas al desplazar', () {
    testWidgets('tocar la primera y la última tarjeta abre «Marcar entregado» de ESA venta', (
      tester,
    ) async {
      await montarPantalla(tester, _entorno(_entregas(60)), _ruta);
      final tarjetas = find.byType(TarjetaDeEntregaPendiente);

      // Arriba: la primera atrasada es la venta 0.
      await tester.tapAt(tester.getTopLeft(tarjetas.first) + const Offset(30, 12));
      await asentar(tester);
      expect(tester.widget<MarcarEntregadoPage>(find.byType(MarcarEntregadoPage)).ventaId, 'v-0');
      await _volver(tester);

      // Abajo (tarjeta armada al desplazar): la última «sin fecha» es la venta 59. Se toca arriba a la
      // izquierda: el centro de las «sin fecha» puede caer en «Poner fecha».
      await _saltar(tester, _lista, alFondo: true);
      await tester.tapAt(tester.getTopLeft(tarjetas.last) + const Offset(30, 12));
      await asentar(tester);
      expect(tester.widget<MarcarEntregadoPage>(find.byType(MarcarEntregadoPage)).ventaId, 'v-59');
    });

    testWidgets('dos toques seguidos sobre tarjetas distintas abren una sola pantalla', (
      tester,
    ) async {
      await montarPantalla(tester, _entorno(_entregas(60)), _ruta);
      final tarjetas = find.byType(TarjetaDeEntregaPendiente);

      await tester.tap(tarjetas.at(0), warnIfMissed: false);
      await tester.tap(tarjetas.at(1), warnIfMissed: false);
      await asentar(tester);
      expect(find.byType(MarcarEntregadoPage), findsOneWidget);
      await _volver(tester);

      // Una sola pantalla encima: al volver está «Entregas pendientes», no otra «Marcar entregado».
      expect(find.byType(MarcarEntregadoPage), findsNothing);
      expect(find.byType(EntregasPendientesPage), findsOneWidget);
    });

    testWidgets('se entrega una mientras se está al fondo: la lista se achica y no se rompe', (
      tester,
    ) async {
      final e = _entorno(_entregas(60));
      await montarPantalla(tester, e, _ruta);
      await _saltar(tester, _lista, alFondo: true);

      e.entregas.emitirPendientes(_entregas(60).sublist(1));
      await asentar(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Poner fecha'), findsWidgets);

      e.entregas.emitirPendientes(_entregas(60).sublist(1, 12));
      await asentar(tester);
      await _saltar(tester, _lista, alFondo: false);
      expect(tester.takeException(), isNull);
      expect(find.byType(TarjetaDeEntregaPendiente), findsWidgets);
      await _saltar(tester, _lista, alFondo: false);
      expect(find.text('ATRASADAS'), findsOneWidget);
    });

    testWidgets('se entregan todas estando abajo: aparece el vacío con su mensaje', (tester) async {
      final e = _entorno(_entregas(60));
      await montarPantalla(tester, e, _ruta);
      await _saltar(tester, _lista, alFondo: true);

      e.entregas.emitirPendientes(const []);
      await asentar(tester);

      expect(find.byType(TarjetaDeEntregaPendiente), findsNothing);
      expect(find.text('✓'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('salir y volver a entrar: arranca arriba y las tarjetas están', (tester) async {
      final e = _entorno(_entregas(60));
      await montarPantalla(tester, e, _ruta);
      await _saltar(tester, _lista, alFondo: true);
      await _volver(tester);

      await abrirPantalla(tester);

      expect(find.text('ATRASADAS'), findsOneWidget);
      expect(find.byType(TarjetaDeEntregaPendiente), findsWidgets);
    });
  });

  group('#720 Entregas pendientes: datos límite', () {
    for (final n in [1, 2, 25, 26, 27, 300]) {
      testWidgets('con $n entregas se llega a la última sin desbordes (360x640 x2)', (
        tester,
      ) async {
        await montarPantalla(
          tester,
          _entorno(_entregas(n)),
          _ruta,
          tamano: const Size(360, 640),
          escala: 2,
        );
        expect(find.byType(TarjetaDeEntregaPendiente), findsWidgets);

        await _saltar(tester, _lista, alFondo: true);

        expect(tester.takeException(), isNull);
        expect(find.byType(TarjetaDeEntregaPendiente), findsWidgets);
      });
    }

    testWidgets(
      'un vínculo sin rótulo entre 30 entregas: dice «Persona sin nombre» y no desborda a x2',
      (tester) async {
        final e = _entorno([
          for (var i = 0; i < 30; i++)
            pendienteDe(
              'v-$i',
              vinculo: i.isEven ? 'ep-1' : 'ep-sin-rotulo',
              lineas: [lineaDe('e-$i', 'p-hijos', 12)],
            ),
        ]);
        await montarPantalla(tester, e, _ruta, tamano: const Size(360, 640), escala: 2);
        await _saltar(tester, _lista, alFondo: true);

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Persona sin nombre'), findsWidgets);
      },
    );

    testWidgets(
      'volver a una tarjeta ya vista no muestra «Persona sin nombre» mientras lee su rótulo',
      (tester) async {
        await montarPantalla(tester, _entorno(_entregas(60)), _ruta);
        expect(find.textContaining('Persona sin nombre'), findsNothing);

        await _saltar(tester, _lista, alFondo: true);
        // Un cuadro después de volver arriba: los rótulos autoDispose se vuelven a pedir.
        final s = tester.state<ScrollableState>(
          find.descendant(of: _lista, matching: find.byType(Scrollable)).first,
        );
        s.position.jumpTo(0);
        await tester.pump();

        expect(
          find.textContaining('Persona sin nombre'),
          findsNothing,
          reason:
              'las tarjetas que ya tenían nombre muestran «Persona sin nombre» al volver a verlas',
        );
      },
    );
  });

  // -------------------------------------------------------------------------------------------
  // «Ver borradas» de una persona
  // -------------------------------------------------------------------------------------------

  const cuantas = 60;
  String id(int i) => 'b-${i.toString().padLeft(2, '0')}';

  NotaPersonaRepositorioFalso repoBorradas({int n = cuantas, String? textoLargo}) =>
      NotaPersonaRepositorioFalso(
        notas: [
          for (var i = 0; i < n; i++)
            notaDePrueba(
              id(i),
              textoLargo ?? 'Nota borrada número $i',
              creada: DateTime(2026, 10, 21).subtract(Duration(days: i % 80)),
              borrada: DateTime(2026, 10, 21, 10).subtract(Duration(days: i % 80)),
            ),
        ],
      );

  Future<void> abrirBorradas(
    WidgetTester tester,
    NotaPersonaRepositorioFalso repo, {
    double escala = 1,
    Size tamano = const Size(390, 844),
    int? total,
  }) async {
    await montarNotas(tester, repo: repo, escala: escala, tamano: tamano);
    final ver = find.text('Ver borradas (${total ?? repo.notas.length})');
    await tester.scrollUntilVisible(
      ver,
      200,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    await tester.tap(ver);
    await asentar(tester);
  }

  Finder tarjeta(String nota) => find.byKey(ValueKey('borrada_$nota'));

  Finder restaurarDe(String nota) =>
      find.descendant(of: tarjeta(nota), matching: find.text('Restaurar'));

  Future<void> llegarA(WidgetTester tester, String nota) => tester.scrollUntilVisible(
    tarjeta(nota),
    300,
    scrollable: find.byType(Scrollable).last,
    maxScrolls: 300,
  );

  group('#720 Ver borradas (persona): 60 notas en 4 tamaños', () {
    for (final (nombre, tam) in _tamanos) {
      for (final escala in _escalas) {
        testWidgets('$nombre x$escala: sin desbordes y con las guías arriba y al fondo', (
          tester,
        ) async {
          await abrirBorradas(tester, repoBorradas(), escala: escala, tamano: tam);
          expect(tester.takeException(), isNull);
          await _guias(tester);

          await llegarA(tester, id(cuantas - 1));
          expect(tester.takeException(), isNull);
          await _guias(tester);
        });
      }
    }
  });

  group('#720 Ver borradas (persona): restaurar sobre filas construidas al desplazar', () {
    testWidgets('restaurar la nota 30 la saca de la lista y avisa', (tester) async {
      final repo = repoBorradas();
      await abrirBorradas(tester, repo);
      await llegarA(tester, id(30));

      await tester.tap(restaurarDe(id(30)));
      await asentar(tester);

      expect(repo.llamadas, contains('restaurar:${id(30)}'));
      expect(tarjeta(id(30)), findsNothing);
      expect(find.text('Nota restaurada.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('restaurar la última (59) estando al fondo no rompe la lista', (tester) async {
      final repo = repoBorradas();
      await abrirBorradas(tester, repo);
      await llegarA(tester, id(cuantas - 1));

      await tester.tap(restaurarDe(id(cuantas - 1)));
      await asentar(tester);

      expect(tarjeta(id(cuantas - 1)), findsNothing);
      expect(tester.takeException(), isNull);
      // La que ahora es última se alcanza.
      await llegarA(tester, id(cuantas - 2));
      expect(tarjeta(id(cuantas - 2)), findsOneWidget);
    });

    testWidgets('restaurar falla: el aviso ofrece «Reintentar» y la nota sigue en su lugar', (
      tester,
    ) async {
      final repo = repoBorradas()
        ..resultados['restaurar'] = [const FailureServidor(mensaje: 'x'), null];
      await abrirBorradas(tester, repo);
      await llegarA(tester, id(40));

      await tester.tap(restaurarDe(id(40)));
      await asentar(tester);

      expect(find.text('No pudimos restaurar la nota. Probá de nuevo.'), findsOneWidget);
      expect(tarjeta(id(40)), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await asentar(tester);

      expect(repo.cuantas('restaurar'), 2);
      expect(tarjeta(id(40)), findsNothing);
    });

    testWidgets('dos «Restaurar» a la vez sobre filas distintas: cada una una sola vez', (
      tester,
    ) async {
      final repo = repoBorradas();
      final compuerta = Completer<void>();
      repo.compuertas['restaurar'] = compuerta;
      await abrirBorradas(tester, repo);
      await llegarA(tester, id(10));

      await tester.tap(restaurarDe(id(10)));
      await tester.pump();
      await tester.tap(restaurarDe(id(10)), warnIfMissed: false);
      await tester.pump();
      await llegarA(tester, id(11));
      await tester.tap(restaurarDe(id(11)));
      await tester.pump();
      compuerta.complete();
      await asentar(tester);

      expect(repo.cuantas('restaurar'), 2);
      expect(repo.llamadas.where((l) => l == 'restaurar:${id(10)}').length, 1);
      expect(tarjeta(id(10)), findsNothing);
      expect(tarjeta(id(11)), findsNothing);
    });

    testWidgets(
      'una restauración en vuelo con la fila fuera de pantalla: al terminar, avisa y la lista sigue',
      (tester) async {
        final repo = repoBorradas();
        final compuerta = Completer<void>();
        repo.compuertas['restaurar'] = compuerta;
        await abrirBorradas(tester, repo);
        await llegarA(tester, id(5));
        await tester.tap(restaurarDe(id(5)));
        await tester.pump();

        // La fila se va de pantalla (se destruye) mientras sigue en vuelo.
        await llegarA(tester, id(cuantas - 1));
        compuerta.complete();
        await asentar(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Nota restaurada.'), findsOneWidget);
        expect(tarjeta(id(cuantas - 1)), findsOneWidget);
      },
    );
  });

  group('#720 Ver borradas (persona): datos límite', () {
    testWidgets('sin ninguna borrada no hay «Ver borradas»', (tester) async {
      await montarNotas(tester, repo: NotaPersonaRepositorioFalso());
      expect(find.textContaining('Ver borradas'), findsNothing);
    });

    testWidgets('al restaurar la única: la lista de borradas queda con su vacío', (tester) async {
      final repo = repoBorradas(n: 1);
      await abrirBorradas(tester, repo);
      expect(tarjeta(id(0)), findsOneWidget);

      await tester.tap(restaurarDe(id(0)));
      await asentar(tester);

      expect(find.text('No hay notas borradas.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final n in [1, 25, 26]) {
      testWidgets('con $n borradas se llega a la última a 360x640 x2', (tester) async {
        await abrirBorradas(tester, repoBorradas(n: n), escala: 2, tamano: const Size(360, 640));
        await llegarA(tester, id(n - 1));
        expect(tarjeta(id(n - 1)), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('notas larguísimas con emoji y sin espacios: sin desbordes a 360x640 x2', (
      tester,
    ) async {
      final largo = '${'Ñandú 🦤 '.padRight(40, 'W')}${'palabra' * 120}';
      await abrirBorradas(
        tester,
        repoBorradas(n: 30, textoLargo: largo),
        escala: 2,
        tamano: const Size(360, 640),
      );
      for (var i = 0; i < 60; i++) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'paso $i');
      }
    });

    testWidgets('con 59 de 60 a restaurar desde la 0 hasta que quedan 25: sigue perezosa', (
      tester,
    ) async {
      final repo = repoBorradas();
      await abrirBorradas(tester, repo);
      for (var i = 0; i < 35; i++) {
        // Siempre se restaura la primera visible (la 0 desaparece, la siguiente sube).
        await tester.scrollUntilVisible(
          tarjeta(id(i)),
          -300,
          scrollable: find.byType(Scrollable).last,
          maxScrolls: 5,
        );
        await tester.tap(restaurarDe(id(i)));
        await asentar(tester);
        expect(tester.takeException(), isNull, reason: 'restaurando $i');
      }
      expect(repo.cuantas('restaurar'), 35);
      await llegarA(tester, id(cuantas - 1));
      expect(tarjeta(id(cuantas - 1)), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------
  // «Ver borradas» de un lugar
  // -------------------------------------------------------------------------------------------

  NotaUbicacionRepositorioFalso repoLugar({int n = cuantas, String? textoLargo}) =>
      NotaUbicacionRepositorioFalso(
        notas: [
          for (var i = 0; i < n; i++)
            notaDeLugar(
              id(i),
              textoLargo ?? 'Nota del lugar borrada número $i',
              creada: DateTime(2026, 10, 21).subtract(Duration(days: i % 80)),
              borrada: DateTime(2026, 10, 21, 10).subtract(Duration(days: i % 80)),
            ),
        ],
      );

  Future<void> abrirBorradasLugar(
    WidgetTester tester,
    NotaUbicacionRepositorioFalso repo, {
    double escala = 1,
    Size tamano = const Size(390, 844),
    bool soloLectura = false,
  }) async {
    await montarPestanaLugar(
      tester,
      repo: repo,
      escala: escala,
      tamano: tamano,
      soloLectura: soloLectura,
    );
    final ver = find.textContaining('Ver borradas');
    await tester.ensureVisible(ver);
    await tester.pump();
    await tester.tap(ver);
    await asentarLugar(tester);
  }

  group('#720 Ver borradas (lugar): 60 notas en 4 tamaños', () {
    for (final (nombre, tam) in _tamanos) {
      for (final escala in _escalas) {
        testWidgets('$nombre x$escala: sin desbordes y con las guías arriba y al fondo', (
          tester,
        ) async {
          await abrirBorradasLugar(tester, repoLugar(), escala: escala, tamano: tam);
          expect(find.byType(NotasBorradasDelLugarPage), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _guias(tester);

          await llegarA(tester, id(cuantas - 1));
          expect(tester.takeException(), isNull);
          await _guias(tester);
        });
      }
    }

    testWidgets('restaurar la nota 25 desde el lugar: sale de la lista y avisa', (tester) async {
      final repo = repoLugar();
      await abrirBorradasLugar(tester, repo);
      await llegarA(tester, id(25));

      await tester.tap(restaurarDe(id(25)));
      await asentarLugar(tester);

      expect(repo.llamadas, contains('restaurar:${id(25)}'));
      expect(tarjeta(id(25)), findsNothing);
      expect(find.text('Nota restaurada.'), findsOneWidget);
    });

    testWidgets('restaurar falla en una fila del fondo: queda y ofrece «Reintentar»', (
      tester,
    ) async {
      final repo = repoLugar()
        ..resultados['restaurar'] = [const FailureServidor(mensaje: 'x'), null];
      await abrirBorradasLugar(tester, repo);
      await llegarA(tester, id(cuantas - 1));

      await tester.tap(restaurarDe(id(cuantas - 1)));
      await asentarLugar(tester);

      expect(find.text('No pudimos restaurar la nota. Probá de nuevo.'), findsOneWidget);
      expect(tarjeta(id(cuantas - 1)), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await asentarLugar(tester);
      expect(tarjeta(id(cuantas - 1)), findsNothing);
    });

    testWidgets('lugar dado de baja: 60 notas, ninguna ofrece «Restaurar»', (tester) async {
      await abrirBorradasLugar(tester, repoLugar(), soloLectura: true);
      await llegarA(tester, id(cuantas - 1));
      expect(find.text('Restaurar'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con 1 borrada se restaura y queda el vacío', (tester) async {
      await abrirBorradasLugar(tester, repoLugar(n: 1));
      await tester.tap(restaurarDe(id(0)));
      await asentarLugar(tester);
      expect(find.text('No hay notas borradas.'), findsOneWidget);
    });

    testWidgets('textos larguísimos a 360x640 x2: sin desbordes al recorrer', (tester) async {
      await abrirBorradasLugar(
        tester,
        repoLugar(n: 30, textoLargo: 'Casa 🏠 ${'portón' * 150}'),
        escala: 2,
        tamano: const Size(360, 640),
      );
      for (var i = 0; i < 60; i++) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'paso $i');
      }
    });
  });
}
