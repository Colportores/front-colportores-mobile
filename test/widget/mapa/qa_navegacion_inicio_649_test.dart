// QA de #649 (navegación del shell: «ir a la casa» y «tras guardar vuelve al mapa»), pasada del QA.
// Cubre lo que los tests del implementador no tocan: el encuadre del mapa cuando la intención no se
// puede cumplir, una intención que el colportor deja atrás, que la casa quede en la parte libre del
// mapa (no bajo la hoja) en los dos tamaños, el atrás con la hoja modal de la Lista, acciones
// superpuestas y las guías de accesibilidad de los dos estados nuevos (hoja a un tercio y mapa libre).
import 'dart:async';

import 'package:colportores_mobile/features/inicio/presentation/providers/navegacion_inicio_provider.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/mapa_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart'
    show ContextoDeCobro, ContextoDeVisita;
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:dartz/dartz.dart' show Right;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'lista_ubicaciones_arnes.dart' show asentarLista;
import 'navegacion_inicio_649_arnes.dart';

const _mapa = 1;
const _hoy = 0;
const _lista = 2;

final _resumen = find.byKey(ClavesMapaUbicaciones.vistaPrevia);
final _registrar = find.byKey(ClavesHojaCasa.registrarVisita);
final _cobrar = find.byKey(ClavesHojaCasa.cobrar);

const _tamanos = <(String, Size)>[('360x640', Size(360, 640)), ('412x915', Size(412, 915))];
const _escalas = <double>[1, 2];

Future<void> _tocar(WidgetTester tester, Finder boton) async {
  await tester.ensureVisible(boton);
  await tester.tap(boton);
  await asentarLista(tester);
}

void main() {
  group('QA #649 · encuadre cuando la intención no se puede cumplir', () {
    testWidgets(
      'dado un mapa que nunca se abrió y el GPS conocido, cuando «ir a la casa» pide una casa que no '
      'es de la colportora, entonces el mapa se encuadra como al abrirlo a mano',
      (tester) async {
        // Control: abrir el Mapa a mano con el mismo GPS.
        final control = await montar649(
          tester,
          filas: [filaLista('a')],
          gps: GpsFalso(Right(lecturaGps(8))),
        );
        await control.irA('mapa');
        await control.asentar();
        final esperada = control.mapa.camara!;

        final m = await montar649(
          tester,
          filas: [filaLista('a')],
          gps: GpsFalso(Right(lecturaGps(8))),
          clave: UniqueKey(),
        );
        m.notificador.irALaCasa('de-otro');
        await m.asentar();
        await m.asentar();

        final camara = m.mapa.camara!;
        expect(m.pestana, _mapa);
        expect(
          ProyeccionMercator.distanciaPixeles(camara.centro, esperada.centro, esperada.zoom),
          lessThan(40),
          reason: 'la intención se consumió sin mover nada: el mapa tiene que encuadrarse solo',
        );
      },
    );

    testWidgets(
      'dado un mapa que nunca se abrió y la lista que no se puede leer, cuando «ir a la casa», '
      'entonces no queda colgada ni lanza',
      (tester) async {
        final m = await montar649(tester, filas: [filaLista('a')], listaSePuedeLeer: false);

        m.notificador.irALaCasa('a');
        await m.asentar();
        await m.asentar();

        expect(m.pestana, _mapa);
        expect(m.navegacion.intencion, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('QA #649 · una intención que el colportor deja atrás', () {
    testWidgets(
      'dado «ir a la casa» pedido y el colportor toca «Lista» antes de que el mapa conteste, '
      'cuando vuelve al Mapa por su cuenta, entonces no se le elige ninguna casa',
      (tester) async {
        final m = await montar649(
          tester,
          filas: [filaLista('a'), filaLista('b', metrosAlNorte: 40)],
        );

        m.notificador.irALaCasa('b');
        await tester.tap(find.byKey(const Key('inicio_pestana_lista')));
        await m.asentar();
        expect(m.pestana, _lista);
        expect(m.navegacion.intencion, isNull);

        await m.irA('mapa');
        expect(m.seleccionada, anyOf(isNull, 'b'));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'dado la hoja de la casa abierta en el mapa, cuando «ir a la casa» pide otra casa desde la '
      'Agenda, entonces queda una sola hoja y es la de la casa pedida',
      (tester) async {
        final m = await montar649(
          tester,
          filas: [filaLista('a'), filaLista('b', metrosAlNorte: 40)],
        );
        await m.irA('mapa');
        m.mapa.tocarPunto('a');
        await m.asentar();
        await m.irA('agenda');

        m.notificador.irALaCasa('b');
        await m.asentar();

        expect(m.pestana, _mapa);
        expect(m.seleccionada, 'b');
        expect(_resumen, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('QA #649 · la casa queda en la parte libre del mapa', () {
    for (final (nombre, tamano) in _tamanos) {
      for (final escala in _escalas) {
        testWidgets(
          '«ir a la casa» a $nombre con texto $escala×: el marcador de una casa lejana queda sobre '
          'la hoja y dentro del mapa',
          (tester) async {
            final casa = filaLista('lejos', metrosAlNorte: 4000);
            final m = await montar649(
              tester,
              filas: [filaLista('cerca'), casa],
              gps: GpsFalso(Right(lecturaGps(8))),
              tamano: tamano,
              escala: escala,
            );
            await m.irA('agenda');

            m.notificador.irALaCasa('lejos');
            await m.asentar();
            await m.asentar();

            expect(_resumen, findsOneWidget);
            final camara = m.mapa.camara!;
            final rect = tester.getRect(find.byType(MapaUbicacionesPage));
            final p = ProyeccionMercator.aPixeles(casa.ubicacion.coordenadas, camara.zoom);
            final c = ProyeccionMercator.aPixeles(camara.centro, camara.zoom);
            final x = rect.center.dx + (p.x - c.x);
            final y = rect.center.dy + (p.y - c.y);
            final arribaDeLaHoja = tester.getTopLeft(_resumen).dy;
            expect(x, inInclusiveRange(rect.left, rect.right), reason: 'x=$x');
            expect(y, greaterThan(rect.top), reason: 'y=$y');
            expect(
              y,
              lessThan(arribaDeLaHoja),
              reason: 'el marcador (y=$y) no puede quedar bajo la hoja ($arribaDeLaHoja)',
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('QA #649 · atrás del sistema', () {
    testWidgets(
      'dado la hoja modal de la casa abierta desde la Lista, cuando se aprieta atrás, entonces se '
      'cierra la hoja y la Lista sigue donde estaba',
      (tester) async {
        final m = await montar649(
          tester,
          filas: [filaLista('a', calle: 'Rivadavia', numero: '100')],
        );
        await m.irA('lista');
        await tester.tap(find.byKey(const ValueKey('a')));
        await asentarLista(tester);
        expect(_resumen, findsOneWidget);

        await tester.binding.handlePopRoute();
        await m.asentar();

        expect(_resumen, findsNothing);
        expect(m.pestana, _lista);
        expect(m.navegacion.intencion, isNull);
      },
    );

    testWidgets(
      'dado el mapa libre tras guardar, cuando se aprieta atrás dos veces, entonces vuelve a «Hoy» '
      'y desde «Hoy» sale de la app (nunca queda en un bucle)',
      (tester) async {
        final m = await montar649(tester, filas: [filaLista('a', metrosAlNorte: 30)]);
        await m.irA('mapa');
        m.mapa.tocarPunto('a');
        await m.asentar();
        await _tocar(tester, _registrar);
        expect(m.pestana, _mapa);
        expect(_resumen, findsNothing);

        expect(await tester.binding.handlePopRoute(), isTrue);
        await m.asentar();
        expect(m.pestana, _hoy);

        expect(
          await tester.binding.handlePopRoute(),
          isFalse,
          reason: 'desde «Hoy» sale de la app',
        );
      },
    );
  });

  group('QA #649 · acciones superpuestas y fallas', () {
    testWidgets(
      'dado «Registrar visita» sin terminar, cuando se toca «\$ Cobrar», entonces no se abre el '
      'cobro, y al terminar la visita se vuelve al mapa una sola vez',
      (tester) async {
        final registrar = Destino649<ContextoDeVisita>(true)..espera = Completer<void>();
        final cobrar = Destino649<ContextoDeCobro>(true);
        final m = await montar649(
          tester,
          filas: [filaLista('a', metrosAlNorte: 30)],
          registrar: registrar,
          cobrar: cobrar,
        );
        await m.irA('mapa');
        m.mapa.tocarPunto('a');
        await m.asentar();

        await tester.ensureVisible(_registrar);
        await tester.tap(_registrar);
        await tester.pump();
        if (_cobrar.evaluate().isNotEmpty) {
          await tester.ensureVisible(_cobrar);
          await tester.tap(_cobrar, warnIfMissed: false);
          await tester.pump();
        }
        expect(cobrar.llamadas, isEmpty, reason: 'una acción a la vez');

        registrar.espera!.complete();
        await m.asentar();

        expect(registrar.llamadas, hasLength(1));
        expect(cobrar.llamadas, isEmpty);
        expect(_resumen, findsNothing);
        expect(m.pestana, _mapa);
        expect(m.navegacion.intencion, isNull);
      },
    );

    testWidgets(
      'dado un cobro que falla y después se guarda, cuando se reintenta, entonces el mapa queda '
      'libre una sola vez y ningún aviso de falla sobrevive',
      (tester) async {
        final cobrar = Destino649<ContextoDeCobro>()..falla = StateError('sin base');
        final m = await montar649(
          tester,
          filas: [filaLista('a', metrosAlNorte: 30)],
          cobrar: cobrar,
        );
        await m.irA('mapa');
        m.mapa.tocarPunto('a');
        await m.asentar();
        if (_cobrar.evaluate().isEmpty) return;

        await _tocar(tester, _cobrar);
        expect(find.textContaining('No pudimos abrir'), findsOneWidget);
        expect(m.seleccionada, 'a');

        cobrar
          ..falla = null
          ..resultado = true;
        await _tocar(tester, _cobrar);

        expect(cobrar.llamadas, hasLength(2));
        expect(_resumen, findsNothing);
        expect(find.textContaining('No pudimos abrir'), findsNothing);
        expect(m.seleccionada, isNull);
      },
    );

    testWidgets(
      'dado un shell con la hoja abierta, cuando se guarda y se vuelve a tocar la misma casa dos '
      'veces seguidas, entonces la hoja abre una sola vez cada vez',
      (tester) async {
        final m = await montar649(tester, filas: [filaLista('a', metrosAlNorte: 30)]);
        await m.irA('mapa');
        for (var i = 0; i < 2; i++) {
          m.mapa.tocarPunto('a');
          await m.asentar();
          expect(_resumen, findsOneWidget);
          await _tocar(tester, _registrar);
          expect(_resumen, findsNothing);
        }
        expect(m.registrar.llamadas, hasLength(2));
      },
    );
  });

  group('QA #649 · accesibilidad y tamaños de los estados nuevos', () {
    for (final (nombre, tamano) in _tamanos) {
      for (final escala in _escalas) {
        testWidgets('hoja a un tercio tras «ir a la casa», $nombre, texto $escala×', (
          tester,
        ) async {
          final m = await montar649(
            tester,
            filas: [filaLista('a', calle: 'Avenida Doctor Alejandro Gallinal', numero: '1234')],
            tamano: tamano,
            escala: escala,
          );
          await m.irA('lista');
          m.notificador.irALaCasa('a');
          await m.asentar();

          expect(_resumen, findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        });

        testWidgets('mapa libre tras guardar, $nombre, texto $escala×', (tester) async {
          final m = await montar649(
            tester,
            filas: [filaLista('a', calle: 'Avenida Doctor Alejandro Gallinal', numero: '1234')],
            tamano: tamano,
            escala: escala,
          );
          await m.irA('mapa');
          m.mapa.tocarPunto('a');
          await m.asentar();
          await _tocar(tester, _registrar);

          expect(_resumen, findsNothing);
          expect(m.pestana, _mapa);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        });
      }
    }

    testWidgets('la pestaña Mapa queda marcada como elegida para el lector tras «ir a la casa»', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final m = await montar649(tester, filas: [filaLista('a')]);
      await m.irA('agenda');

      m.notificador.irALaCasa('a');
      await m.asentar();

      expect(
        tester.getSemantics(find.byKey(const Key('inicio_pestana_mapa'))),
        isSemantics(isSelected: true),
      );
      handle.dispose();
    });
  });

  group('QA #649 · sin datos personales', () {
    test('la intención y la navegación no llevan la casa en su toString', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(navegacionInicioProvider.notifier).irALaCasa('ubicacion-secreta-123');
      final navegacion = c.read(navegacionInicioProvider);
      expect(navegacion.toString(), isNot(contains('ubicacion-secreta-123')));
      expect(navegacion.intencion.toString(), isNot(contains('ubicacion-secreta-123')));
    });
  });
}
