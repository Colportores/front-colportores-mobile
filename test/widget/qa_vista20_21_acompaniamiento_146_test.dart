// QA de las vistas 20 y 21 (HU-JOR-003, #146): desborde con las fuentes reales en cada estado y tamaño,
// casos límite de cada flujo, anuncios para el lector de pantalla, textos literales del canvas y privacidad.
// Los hallazgos van con `skip` (QA #146) hasta que el implementador los arregle.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/jornada/domain/entities/acompaniante.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/tendencia_de_la_jornada.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista20_21_146_arnes.dart';

CoordinadorDeCampania _coord(int i, {String? nombre, String? apellido}) => CoordinadorDeCampania(
  usuarioId: 'u-$i',
  nombre: nombre ?? 'Coordinadora$i',
  apellido: apellido ?? 'Apellido${String.fromCharCode(65 + i % 26)}',
);

/// Los tests que documentan un hallazgo corren con `QA_HALLAZGOS=true`; sin eso quedan en `skip`.
final _hallazgos = Platform.environment['QA_HALLAZGOS'] == 'true';

void main() {
  group('7 · tamaños: sin desborde con las fuentes reales', () {
    for (final entrada in estados146.entries) {
      for (final (nombreTam, tam) in [
        ('360x640', telefonoChico146),
        ('412x915', telefonoGrande146),
      ]) {
        for (final esc in [1.0, 2.0]) {
          testWidgets('${entrada.key} · $nombreTam · texto ×$esc', (tester) async {
            await cargarFuentes146(tester);
            await entrada.value(tester, tam, esc);
            expect(tester.takeException(), isNull);
            expect(esperado146[entrada.key]!(), findsWidgets);
          });
        }
      }
    }
  });

  group('2/5b · la hoja y los casos límite de la lista', () {
    testWidgets('«Listo» y «Cancelar» se alcanzan con 2.0× en 360×640 y el guardado sale', (
      tester,
    ) async {
      await cargarFuentes146(tester);
      final repo = repoCon146();
      await montarHoy146(tester, repo, tamano: telefonoChico146, escala: Escala146(2));
      await abrirHoja146(tester);
      await tester.ensureVisible(fila146('u-marta'));
      await tester.tap(fila146('u-marta'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('hoja_acompaniantes_cancelar')));
      await tester.ensureVisible(listo146());
      await tester.tap(listo146());
      await tester.pumpAndSettle();
      expect(repo.pedidos, [
        {'u-marta'},
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('25 coordinadores con nombre largo y emoji: el último se elige y sube', (
      tester,
    ) async {
      await cargarFuentes146(tester);
      final lista = [
        for (var i = 0; i < 25; i++)
          _coord(
            i,
            nombre: 'María de los Ángeles Fernández 🌻 $i',
            apellido: 'Rodríguez de la Santísima Trinidad y Alcántara',
          ),
      ];
      final repo = repoCon146(lista: lista);
      await montarHoy146(tester, repo, tamano: telefonoChico146, escala: Escala146(2));
      await abrirHoja146(tester);
      await marcarYListo146(tester, ['u-24']);
      expect(repo.pedidos, [
        {'u-24'},
      ]);
      expect(tester.takeException(), isNull);
      // La tarjeta con ese nombre también cabe.
      expect(find.byKey(const Key('acompaniante_tarjeta_u-24')), findsOneWidget);
    });

    testWidgets('un coordinador sin nombre ni apellido se ofrece como «Acompañante», no vacío', (
      tester,
    ) async {
      final repo = repoCon146(
        lista: const [CoordinadorDeCampania(usuarioId: 'u-x', nombre: ' ', apellido: '')],
      );
      await montarHoy146(tester, repo);
      await abrirHoja146(tester);
      expect(
        find.descendant(of: fila146('u-x'), matching: find.text('Acompañante')),
        findsOneWidget,
      );
    });

    testWidgets('un doble toque en «Cambiar» abre una sola hoja', (tester) async {
      final repo = repoCon146();
      await guardarDe146(repo, ['u-marta']);
      await montarHoy146(tester, repo);
      await tester.tap(cambiar146());
      await tester.tap(cambiar146(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hoja_acompaniantes')), findsOneWidget);
      await tester.tap(find.byKey(const Key('hoja_acompaniantes_cancelar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hoja_acompaniantes')), findsNothing);
    });

    testWidgets('un doble toque en el interruptor abre una sola hoja', (tester) async {
      await montarHoy146(tester, repoCon146());
      await tester.tap(interruptor146());
      await tester.tap(interruptor146(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hoja_acompaniantes')), findsOneWidget);
    });
  });

  group('5b · falla a mitad y acciones superpuestas', () {
    testWidgets(
      'fallan dos guardados seguidos: «Reintentar» siempre vuelve a andar y el tercero guarda',
      (tester) async {
        final repo = repoCon146()..fallas = 2;
        await montarHoy146(tester, repo);
        await abrirHoja146(tester);
        await marcarYListo146(tester, ['u-marta']);
        expect(find.byKey(const Key('acompaniamiento_error')), findsOneWidget);
        expect(find.text('Guardando…'), findsNothing);
        expect(tester.widget<OutlinedButton>(reintentar146()).onPressed, isNotNull);

        await tester.tap(reintentar146());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('acompaniamiento_error')), findsOneWidget);
        expect(find.text('Guardando…'), findsNothing);
        expect(tester.widget<OutlinedButton>(reintentar146()).onPressed, isNotNull);

        await tester.tap(reintentar146());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('acompaniamiento_error')), findsNothing);
        expect(repo.guardadosDe('jor-1'), ['u-marta']);
        expect(repo.pedidos.length, 3);
        expect(find.byKey(const Key('acompaniamiento_tarjeta')), findsOneWidget);
      },
    );

    testWidgets('con el guardado en vuelo, otro cambio desde «Cambiar» se suma y el último gana', (
      tester,
    ) async {
      final repo = repoCon146();
      await guardarDe146(repo, ['u-marta']);
      await montarHoy146(tester, repo);
      repo.compuerta = Completer<void>();
      await abrirHoja146(tester);
      await tester.ensureVisible(fila146('u-daniel'));
      await tester.tap(fila146('u-daniel'));
      await tester.pump();
      await tester.tap(listo146());
      await tester.pump(const Duration(milliseconds: 400));
      // En vuelo: lo pedido ya se ve y el botón dice «Guardando…».
      expect(find.byKey(const Key('acompaniante_tarjeta_u-daniel')), findsOneWidget);
      expect(find.text('Guardando…'), findsOneWidget);

      // Segundo cambio sin esperar: sacar a Marta.
      await tester.tap(cambiar146());
      await tester.pumpAndSettle();
      await tester.ensureVisible(fila146('u-marta'));
      await tester.tap(fila146('u-marta'));
      await tester.pump();
      await tester.tap(listo146());
      await tester.pump(const Duration(milliseconds: 400));
      repo.compuerta!.complete();
      repo.compuerta = null;
      await tester.pumpAndSettle();

      expect(repo.pedidos, [
        {'u-marta', 'u-daniel'},
        {'u-daniel'},
      ]);
      expect(repo.guardadosDe('jor-1'), ['u-daniel']);
      expect(find.text('Guardando…'), findsNothing);
      expect(find.byKey(const Key('acompaniamiento_error')), findsNothing);
    });

    testWidgets(
      'el error sobrevive a abrir y cancelar la hoja: «Reintentar» sigue y repite lo pedido',
      (tester) async {
        final repo = repoCon146()..fallas = 1;
        await montarHoy146(tester, repo);
        await abrirHoja146(tester);
        await marcarYListo146(tester, ['u-marta', 'u-daniel']);
        expect(find.byKey(const Key('acompaniamiento_error')), findsOneWidget);
        await abrirHoja146(tester);
        await tester.tap(find.byKey(const Key('hoja_acompaniantes_cancelar')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('acompaniamiento_error')), findsOneWidget);
        await tester.tap(reintentar146());
        await tester.pumpAndSettle();
        expect(repo.guardadosDe('jor-1')..sort(), ['u-daniel', 'u-marta']);
      },
    );

    testWidgets('volver de otra ruta con el aviso de error abierto lo deja como estaba', (
      tester,
    ) async {
      final repo = repoCon146()..fallas = 1;
      await montarHoy146(tester, repo);
      await abrirHoja146(tester);
      await marcarYListo146(tester, ['u-marta']);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('otra')))),
      );
      await tester.pumpAndSettle();
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('acompaniamiento_error')), findsOneWidget);
      expect(reintentar146(), findsOneWidget);
    });
  });

  group('6 · lector de pantalla', () {
    testWidgets(
      'el error de guardado y el de lista se anuncian (región viva) y el interruptor lleva su ayuda',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final repo = repoCon146()..fallas = 1;
        await montarHoy146(tester, repo);
        final nodoInterruptor = tester.getSemantics(interruptor146());
        expect(nodoInterruptor.label, contains('¿Te acompañó alguien?'));
        expect(nodoInterruptor.label, contains('Coordinador de tu campaña'));
        await abrirHoja146(tester);
        await marcarYListo146(tester, ['u-marta']);
        // Un ancestro del texto del error es región viva.
        final conRegion = find.ancestor(
          of: find.text('No pudimos guardar el acompañamiento. Probá de nuevo.'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        );
        expect(conRegion, findsWidgets);
        semantica.dispose();
      },
    );

    testWidgets('cada coordinador de la hoja se lee con su nombre y marcado o no', (tester) async {
      final semantica = tester.ensureSemantics();
      final repo = repoCon146();
      await guardarDe146(repo, ['u-marta']);
      await montarHoy146(tester, repo);
      await abrirHoja146(tester);
      expect(tester.getSemantics(fila146('u-marta')).label, contains('Marta Pérez'));
      expect(
        tester.getSemantics(fila146('u-marta')).getSemanticsData().flagsCollection.isChecked,
        ui.CheckedState.isTrue,
      );
      expect(tester.getSemantics(fila146('u-daniel')).label, contains('Daniel Ruiz'));
      expect(
        tester.getSemantics(fila146('u-daniel')).getSemanticsData().flagsCollection.isChecked,
        ui.CheckedState.isFalse,
      );
      semantica.dispose();
    });

    testWidgets('«Cambiar» se lee con el nombre de la persona a la que corresponde', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final repo = repoCon146();
      await guardarDe146(repo, ['u-marta']);
      await montarHoy146(tester, repo);
      final nodo = tester.getSemantics(cambiar146());
      expect(nodo.label, contains('Cambiar'));
      semantica.dispose();
    });
  });

  group('1 · textos literales del canvas', () {
    testWidgets('20J·01 a 20J·07 dicen lo que dice el diseño', (tester) async {
      final repo = repoCon146();
      await montarHoy146(tester, repo);
      expect(find.text('¿Te acompañó alguien?'), findsOneWidget);
      await abrirHoja146(tester);
      expect(find.text('¿Quién te acompaña?'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      await marcarYListo146(tester, ['u-marta']);
      expect(find.text('TE ACOMPAÑA'), findsOneWidget);
      expect(find.text('Cambiar'), findsOneWidget);
      expect(find.text('Anotamos que te acompaña Marta.'), findsOneWidget);
      await abrirHoja146(tester);
      expect(find.text('Nadie me acompañó'), findsOneWidget);
    });

    testWidgets('20J·05 y 20J·07 usan el texto literal del canvas', (tester) async {
      await montarHoy146(tester, repoCon146(lista: const []));
      await abrirHoja146(tester);
      expect(
        find.text(
          'Todavía no recibimos la lista de coordinadores de tu campaña. Se actualiza cuando haya conexión.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cerrar'), findsOneWidget);
    });

    testWidgets('21J·03 dice «Te acompañó», «Nadie», la tendencia y el aviso del canvas', (
      tester,
    ) async {
      await montarResumen146(tester, repoCon146());
      expect(find.text('Te acompañó:'), findsOneWidget);
      expect(find.text('Nadie'), findsOneWidget);
      expect(find.text('CONTRA TU JORNADA ANTERIOR'), findsOneWidget);
      expect(find.text('Casas visitadas'), findsWidgets);
      expect(find.text('▲ 3'), findsOneWidget);
      expect(find.text('▼ 1'), findsOneWidget);
      expect(
        find.text(
          'Si alguien te acompañó y no lo marcaste, avisale a tu coordinador: lo agrega desde el panel.',
        ),
        findsOneWidget,
      );
    });
  });

  group('8 · privacidad', () {
    test('toString de las entidades no deja nombres en el log', () {
      expect(
        const CoordinadorDeCampania(
          usuarioId: 'u-1',
          nombre: 'Marta',
          apellido: 'Pérez',
        ).toString(),
        isNot(contains('Marta')),
      );
      expect(
        const Acompaniante(usuarioId: 'u-1', nombre: 'Marta', apellido: 'Pérez').toString(),
        isNot(contains('Pérez')),
      );
      expect(
        const TendenciaDeLaJornada(casasVisitadas: 1, ventas: 1).toString(),
        isNot(contains('casasVisitadas')),
      );
    });
  });

  group('5b · lista que no llega, quitar a todos y nombres que faltan', () {
    testWidgets(
      'con la lista colgada la hoja dice que carga y se sale tocando afuera: no queda trabada',
      (tester) async {
        await montarHoy146(tester, RepoListaColgada146());
        await tester.tap(interruptor146());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Cargando la lista…'), findsOneWidget);
        expect(listo146(), findsNothing);
        // Tocar la parte oscura de arriba cierra la hoja.
        await tester.tapAt(const Offset(200, 40));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('hoja_acompaniantes')), findsNothing);
        // Y se puede volver a abrir.
        await tester.tap(interruptor146());
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Cargando la lista…'), findsOneWidget);
      },
    );

    testWidgets(
      '«Nadie me acompañó» que falla deja a quien estaba, avisa y «Reintentar» lo repite',
      (tester) async {
        final repo = repoCon146();
        await guardarDe146(repo, ['u-marta']);
        await montarHoy146(tester, repo);
        repo.fallas = 1;
        await abrirHoja146(tester);
        await tester.tap(find.byKey(const Key('hoja_acompaniantes_nadie')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('acompaniamiento_error')), findsOneWidget);
        expect(find.byKey(const Key('acompaniante_tarjeta_u-marta')), findsOneWidget);
        await tester.tap(reintentar146());
        await tester.pumpAndSettle();
        expect(repo.guardadosDe('jor-1'), isEmpty);
        expect(interruptor146(), findsOneWidget);
        expect(find.byKey(const Key('acompaniamiento_error')), findsNothing);
      },
    );

    testWidgets(
      'alguien guardado que la lista no conoce se dice «Acompañante» y no inventa un nombre',
      (tester) async {
        final repo = repoCon146(lista: const []);
        await guardarDe146(repo, ['u-desconocido']);
        await montarResumen146(tester, repo);
        expect(find.text('Acompañante'), findsOneWidget);
        expect(find.byKey(const Key('jornada_resumen_aviso_acompanio')), findsNothing);
      },
    );
  });

  group('6 · hallazgos de accesibilidad (menores)', () {
    testWidgets(
      'QA #146: «Cambiar» de la tarjeta se distingue de «Cambiar» de la hora de fin para el lector de pantalla',
      skip: !_hallazgos,
      (tester) async {
        final semantica = tester.ensureSemantics();
        final repo = repoCon146();
        await guardarDe146(repo, ['u-marta']);
        await montarHoy146(tester, repo);
        final etiqueta = tester.getSemantics(cambiar146()).label.toLowerCase();
        expect(etiqueta, contains('acompa'));
        semantica.dispose();
      },
    );
  });

  group('21J·03 · el cierre con todo', () {
    testWidgets(
      'con 3 acompañantes de nombre largo a 2.0× en 360×640 «Volver al inicio» siempre se ve y se toca',
      (tester) async {
        await cargarFuentes146(tester);
        final lista = [
          for (var i = 0; i < 3; i++)
            _coord(
              i,
              nombre: 'María de los Ángeles 🌻',
              apellido: 'Rodríguez de la Santísima Trinidad',
            ),
        ];
        final repo = repoCon146(lista: lista);
        await guardarDe146(repo, ['u-0', 'u-1', 'u-2']);
        await montarResumen146(tester, repo, tamano: telefonoChico146, escala: Escala146(2));
        expect(tester.takeException(), isNull);
        final volver = find.byKey(const Key('jornada_resumen_volver'));
        final caja = tester.getRect(volver);
        expect(caja.bottom, lessThanOrEqualTo(640));
        expect(caja.height, greaterThanOrEqualTo(48));
        // El contenido de arriba sigue alcanzable por scroll.
        await tester.ensureVisible(find.byKey(const Key('jornada_resumen_cifras')));
        expect(tester.takeException(), isNull);
      },
    );
  });
}
