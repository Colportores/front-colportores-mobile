// «Registrar visita» y el estado de la última visita en la ficha del depto (vista 11·04, HU-VIS-005,
// #151): la píldora «✓ Entrevista hecha · 20/09», el botón que lleva a «¿Qué pasó?» con el depto
// puesto, y los casos límite (doble toque, falla al abrir, depto de baja, texto grande).
import 'dart:async';

import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/domain/services/lector_ultima_visita_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_visita_del_depto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import '../../helpers/ultima_visita_del_espacio_falsos.dart';
import 'personas_arnes.dart';

final _registrar = find.byKey(ClavesVisitaDelDepto.registrar);
final _estado = find.byKey(ClavesVisitaDelDepto.estado);
const _noPudimos = 'No pudimos abrir «Registrar visita». Probá de nuevo.';

PersonaRepositorioFalso _conDosClientes() => PersonaRepositorioFalso()
  ..sembrar([
    clienteDePersonas('p1', 'Ana', apellido: 'Martínez', telefono: '099 123 412', minutos: 0),
    clienteDePersonas('p2', 'Pedro', apellido: 'Rodríguez', minutos: 1),
  ]);

/// Lo que recibió el destino de «Registrar visita» y cómo contesta.
final class Destino {
  final contextos = <ContextoDeVisita>[];

  /// Si no es `null`, el destino espera a que se complete (la hoja «¿Qué pasó?» abierta).
  Completer<Object?>? compuerta;
  Object? contesta = true;
  Object? lanza;

  Future<Object?> llamar(ContextoDeVisita datos) async {
    contextos.add(datos);
    final espera = compuerta;
    if (espera != null) await espera.future;
    final falla = lanza;
    if (falla != null) throw falla;
    return contesta;
  }
}

Future<void> _montar(
  WidgetTester tester, {
  LectorUltimaVisitaDelEspacio? lector,
  Destino? destino,
  bool conDestino = true,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool deBaja = false,
  bool contextoNulo = false,
}) async {
  await montarClientes(
    tester,
    repo: _conDosClientes(),
    escala: escala,
    tamano: tamano,
    contexto: deBaja ? contextoActivo(espacioDeBaja: DateTime.utc(2026, 10, 24)) : null,
    contextoNulo: contextoNulo,
    otrosOverrides: [
      lectorUltimaVisitaDelEspacioProvider.overrideWithValue(
        lector ?? LectorUltimaVisitaFalso(visitaDel20deSeptiembre()),
      ),
      if (conDestino)
        registrarVisitaDesdeLaCasaProvider.overrideWithValue((destino ?? Destino()).llamar),
    ],
  );
}

void main() {
  group('11·04 · estado de la última visita', () {
    testWidgets(
      'dado un depto con una entrevista hecha, cuando se abre, muestra el estado del canvas y '
      '«Registrar visita» debajo',
      (tester) async {
        await _montar(tester);

        expect(find.text('Entrevista hecha · 20/09'), findsOneWidget);
        expect(find.text('✓'), findsOneWidget);
        expect(find.text('Registrar visita'), findsOneWidget);
        final y = tester.getTopLeft(_estado).dy;
        expect(tester.getTopLeft(find.text('Depto 101')).dy, lessThan(y));
        expect(y, lessThan(tester.getTopLeft(_registrar).dy));
        expect(
          tester.getTopLeft(_registrar).dy,
          lessThan(tester.getTopLeft(find.text('CLIENTES · 2')).dy),
        );
      },
    );

    for (final (resultado, texto) in [
      (TipoResultadoVisita.entrevista, 'Entrevista hecha · 20/09'),
      (TipoResultadoVisita.noContesto, 'No contestó · 20/09'),
      (TipoResultadoVisita.rechazo, 'Rechazó · 20/09'),
      (TipoResultadoVisita.venta, 'Venta · 20/09'),
      (TipoResultadoVisita.cobranza, 'Cobranza · 20/09'),
    ]) {
      testWidgets(
        'dado que la última visita fue ${resultado.codigo}, cuando se abre, dice «$texto» y el '
        'lector de pantalla lo lee entero',
        (tester) async {
          final handle = tester.ensureSemantics();
          await _montar(
            tester,
            lector: LectorUltimaVisitaFalso(visitaDel20deSeptiembre(resultado)),
          );

          expect(find.text(texto), findsOneWidget);
          expect(find.bySemanticsLabel(texto), findsOneWidget);
          handle.dispose();
        },
      );
    }

    testWidgets(
      'dado un depto sin visitas, cuando se abre, dice «Sin visitas todavía» y ofrece registrar la '
      'primera',
      (tester) async {
        await _montar(tester, lector: LectorUltimaVisitaFalso());

        expect(find.text('Sin visitas todavía'), findsOneWidget);
        expect(_registrar, findsOneWidget);
      },
    );

    testWidgets(
      'dado que la lectura sigue en curso, cuando se abre, no afirma ningún estado pero deja '
      'registrar',
      (tester) async {
        await _montar(tester, lector: LectorUltimaVisitaCargando());

        expect(_estado, findsNothing);
        expect(find.text('Sin visitas todavía'), findsNothing);
        expect(_registrar, findsOneWidget);
      },
    );

    testWidgets(
      'dado que la lectura falla, cuando se abre, no afirma ningún estado y la pantalla sigue entera',
      (tester) async {
        await _montar(tester, lector: LectorUltimaVisitaQueFalla());

        expect(_estado, findsNothing);
        expect(find.text('Sin visitas todavía'), findsNothing);
        expect(_registrar, findsOneWidget);
        expect(find.text('CLIENTES · 2'), findsOneWidget);
        expect(find.text('Ana Martínez'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que se registra una visita con la pantalla abierta, cuando la tabla cambia, el estado '
      'se actualiza solo, y vuelve a «Sin visitas» si la deshacen',
      (tester) async {
        final lector = LectorUltimaVisitaFalso();
        await _montar(tester, lector: lector);
        expect(find.text('Sin visitas todavía'), findsOneWidget);

        lector.cambiarA(visitaDel20deSeptiembre(TipoResultadoVisita.noContesto));
        await asentar(tester);
        expect(find.text('No contestó · 20/09'), findsOneWidget);
        expect(find.text('Sin visitas todavía'), findsNothing);

        lector.cambiarA(null);
        await asentar(tester);
        expect(find.text('Sin visitas todavía'), findsOneWidget);
        expect(find.text('No contestó · 20/09'), findsNothing);
      },
    );

    testWidgets(
      'dado un depto que no está más en el teléfono, cuando se abre, no hay estado ni botón',
      (tester) async {
        await _montar(tester, contextoNulo: true);

        expect(_estado, findsNothing);
        expect(_registrar, findsNothing);
      },
    );
  });

  group('11·04 · «Registrar visita»', () {
    testWidgets(
      'dado un destino enganchado, cuando se toca, abre «¿Qué pasó?» con la ubicación y el depto '
      'puestos y sin agenda',
      (tester) async {
        final destino = Destino();
        await _montar(tester, destino: destino);

        await tester.tap(_registrar);
        await asentar(tester);

        expect(destino.contextos, [(ubicacionId: 'ub-1', espacioId: 'esp-1', agendaId: null)]);
        expect(find.text('CLIENTES · 2'), findsOneWidget, reason: 'la pantalla sigue donde estaba');
        expect(find.textContaining('No pudimos'), findsNothing);
      },
    );

    testWidgets(
      'dado que todavía no hay destino enganchado, cuando se abre, no hay botón que no lleve a '
      'nada, pero el estado sí se ve',
      (tester) async {
        await _montar(tester, conDestino: false);

        expect(_registrar, findsNothing);
        expect(find.text('Registrar visita'), findsNothing);
        expect(find.text('Entrevista hecha · 20/09'), findsOneWidget);
      },
    );

    testWidgets(
      'dado un depto dado de baja, cuando se abre, se ve el estado pero no se ofrece registrar una '
      'visita',
      (tester) async {
        await _montar(tester, deBaja: true);

        expect(find.text('Entrevista hecha · 20/09'), findsOneWidget);
        expect(_registrar, findsNothing);
      },
    );

    testWidgets(
      'dado dos toques seguidos con «¿Qué pasó?» todavía abierta, cuando llega el segundo, no abre '
      'otra hoja encima; al terminar se puede volver a registrar',
      (tester) async {
        final destino = Destino()..compuerta = Completer<Object?>();
        await _montar(tester, destino: destino);

        await tester.tap(_registrar);
        await tester.pump();
        await tester.tap(_registrar);
        await tester.pump();
        expect(destino.contextos, hasLength(1));

        destino.compuerta!.complete(true);
        await asentar(tester);
        destino.compuerta = null;
        await tester.tap(_registrar);
        await asentar(tester);
        expect(destino.contextos, hasLength(2));
      },
    );

    testWidgets(
      'dado que el destino falla al abrir, cuando se toca, el aviso dice qué hacer y el botón vuelve '
      'a poder tocarse',
      (tester) async {
        final destino = Destino()..lanza = StateError('boom');
        await _montar(tester, destino: destino);

        await tester.tap(_registrar);
        await asentar(tester);
        expect(find.text(_noPudimos), findsOneWidget);
        expect(
          find.textContaining('boom'),
          findsNothing,
          reason: 'el detalle del error no se muestra',
        );

        destino
          ..lanza = null
          ..contesta = true;
        await tester.tap(_registrar);
        await asentar(tester);

        expect(destino.contextos, hasLength(2));
      },
    );

    testWidgets(
      'dado que «¿Qué pasó?» se cierra sin elegir, cuando vuelve false, no hay aviso de error y el '
      'estado no cambia',
      (tester) async {
        final destino = Destino()..contesta = false;
        await _montar(tester, destino: destino);

        await tester.tap(_registrar);
        await asentar(tester);

        expect(find.textContaining('No pudimos'), findsNothing);
        expect(find.text('Entrevista hecha · 20/09'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que se vuelve atrás tras una falla y se reentra, cuando se toca otra vez, el botón anda',
      (tester) async {
        final destino = Destino()..lanza = StateError('boom');
        await _montar(tester, destino: destino);
        await tester.tap(_registrar);
        await asentar(tester);
        await tester.tap(find.byTooltip('Volver'));
        await asentar(tester);

        destino.lanza = null;
        await tester.tap(find.text('abrir clientes'));
        await asentar(tester);
        await tester.tap(_registrar);
        await asentar(tester);

        expect(destino.contextos, hasLength(2));
        expect(find.text(_noPudimos), findsNothing);
      },
    );

    testWidgets(
      'dado que se sale de la pantalla mientras «¿Qué pasó?» está abierta, cuando termina con una '
      'falla, no rompe nada al querer avisar',
      (tester) async {
        final destino = Destino()
          ..compuerta = Completer<Object?>()
          ..lanza = StateError('boom');
        await _montar(tester, destino: destino);
        await tester.tap(_registrar);
        await tester.pump();
        await tester.tap(find.byTooltip('Volver'));
        await asentar(tester);

        destino.compuerta!.complete(null);
        await asentar(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('abrir clientes'), findsOneWidget);
      },
    );
  });

  group('11·04 · texto grande y pantallas chicas', () {
    for (final tamano in [const Size(320, 568), const Size(360, 640), const Size(412, 915)]) {
      for (final escala in [1.0, 2.0, 3.0]) {
        testWidgets(
          '${tamano.width.toInt()}x${tamano.height.toInt()} a $escala×: sin desborde, el botón se '
          'alcanza y la lista de clientes sigue a la vista',
          (tester) async {
            final destino = Destino();
            await _montar(tester, destino: destino, tamano: tamano, escala: escala);

            expect(tester.takeException(), isNull, reason: 'overflow');
            await tester.ensureVisible(_registrar);
            await tester.pump();
            final boton = tester.getRect(_registrar);
            expect(boton.height, greaterThanOrEqualTo(52));
            expect(boton.left, greaterThanOrEqualTo(0));
            expect(boton.right, lessThanOrEqualTo(tamano.width + 0.6));
            expect(boton.bottom, lessThanOrEqualTo(tamano.height + 0.6));
            final lista = tester.getRect(find.byType(ListView));
            expect(
              lista.height,
              greaterThanOrEqualTo(tamano.height * 0.2),
              reason: 'la lista de clientes conserva su lugar',
            );

            await tester.tap(_registrar);
            await asentar(tester);
            expect(destino.contextos, hasLength(1));
          },
        );
      }
    }

    testWidgets(
      'dado un texto largo y 2×, cuando se muestra el estado, el rótulo se parte en vez de salirse '
      'de la píldora',
      (tester) async {
        await _montar(tester, tamano: const Size(320, 568), escala: 2);

        final pildora = tester.getRect(_estado);
        final texto = tester.getRect(find.text('Entrevista hecha · 20/09'));
        expect(texto.left, greaterThanOrEqualTo(pildora.left));
        expect(texto.right, lessThanOrEqualTo(pildora.right + 0.6));
        expect(pildora.right, lessThanOrEqualTo(320 + 0.6));
      },
    );
  });
}
