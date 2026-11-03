// QA de #509 (vista 32: las notas borradas se van a los 90 días y la baja con entrega pendiente pide
// confirmar, PR #604). Artboards: 32E·04/05 («Ver borradas» con «Se borra el …») y 32D·02/03 (la baja
// con entrega pendiente). Matriz: cada estado × 360×640 / 412×915 × texto 1,0 / 2,0, con las fuentes
// reales del proyecto. Las guías de toque y de contraste van en `qa_vista32_509_guias_test.dart`.
//
// Capturas: `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas/`, nunca al repo).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_baja_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_notas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_persona_falsos.dart';
import 'baja_persona_arnes.dart';
import 'notas_persona_arnes.dart';
import 'qa_vista32_509_arnes.dart';

void main() {
  group('32E · «Ver borradas» (matriz de estados)', () {
    for (final estado in EstadoBorradas.values) {
      for (final tamano in tamanos) {
        for (final escala in escalas) {
          final nombre =
              '${estado.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · ×$escala';
          testWidgets(nombre, (tester) async {
            await borradasEn(tester, estado, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull, reason: 'overflow o excepción');

            switch (estado) {
              case EstadoBorradas.e04:
                // Las dos borradas vigentes cuentan; el enlace dice cuántas.
                await verEnPantalla(tester, find.text('Ver borradas (2)'));
                dentroDeLaPantalla(tester, find.text('Ver borradas (2)'));
              case EstadoBorradas.e05Vacia:
                expect(find.text('No hay notas borradas.'), findsOneWidget);
                expect(find.byKey(ClavesNotas.seBorraEl), findsNothing);
              case EstadoBorradas.e05SoloLectura:
                expect(find.text('Restaurar'), findsNothing);
                await verEnPantalla(tester, find.byKey(ClavesNotas.seBorraEl).first);
                expect(find.text('Se borra el 20/01'), findsOneWidget);
              case EstadoBorradas.e05Tres:
                // Una se va hoy a las 16:00 (a las 15:00 sigue): dice 22/10.
                await verEnPantalla(tester, find.text('Se borra el 22/10'));
                expect(find.text('Se borra el 20/01'), findsOneWidget);
                expect(find.text('Se borra el 03/01'), findsOneWidget);
                expect(find.text('Sigue activa.'), findsNothing);
              case EstadoBorradas.e05Muchas:
                await verEnPantalla(tester, find.byKey(ClavesNotas.seBorraEl).first);
                expect(find.textContaining('Se borra el 30/11'), findsWidgets);
              default:
                await verEnPantalla(tester, find.byKey(ClavesNotas.seBorraEl).first);
                dentroDeLaPantalla(tester, find.byKey(ClavesNotas.seBorraEl).first);
                expect(find.textContaining('Se borra el '), findsWidgets);
            }
            expect(tester.takeException(), isNull);
            sinTextoCortado(tester);
            await capturar(
              tester,
              '32E_${estado.name}_${tamano.width.toInt()}_x${escala.toStringAsFixed(0)}',
            );
          });
        }
      }
    }
  });

  group('32D · la baja con entrega pendiente (matriz de estados)', () {
    for (final estado in EstadoBaja509.values) {
      for (final tamano in tamanos) {
        for (final escala in escalas) {
          final nombre =
              '${estado.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · ×$escala';
          testWidgets(nombre, (tester) async {
            await hojaEn(tester, estado, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull);

            final esPlural = estado.cuenta.entregasPendientes > 1;
            final entregas = esPlural ? '3 entregas pendientes' : '1 entrega pendiente';
            final conDeuda = estado.cuenta.tieneSaldo;
            if (!estado.segunda) {
              expect(find.text('¿Dar de baja a Jorge?'), findsOneWidget);
              final aviso = conDeuda
                  ? 'Jorge te debe ${FormatoBajaPersona.monto(120000)} y tiene $entregas.'
                  : 'Jorge tiene $entregas.';
              await verEnPantalla(tester, find.text(aviso));
              expect(find.text(aviso), findsOneWidget);
              await verEnPantalla(tester, find.text('Dar de baja igual'));
              dentroDeLaPantalla(tester, find.text('Dar de baja igual'));
              dentroDeLaPantalla(tester, find.text('Cancelar'));
            } else {
              expect(find.text('¿Seguro?'), findsOneWidget);
              // Decisión #509 P2: con entregas, la segunda confirmación dice que no se cancelan
              // (con deuda, después de la frase de la deuda).
              final entrega = esPlural
                  ? 'Las 3 entregas pendientes no se cancelan: quedan registradas aunque Jorge esté de baja.'
                  : 'La entrega pendiente no se cancela: queda registrada aunque Jorge esté de baja.';
              final cuerpo = conDeuda
                  ? 'La deuda de ${FormatoBajaPersona.monto(120000)} sigue en tu cuenta aunque Jorge esté de baja. $entrega'
                  : entrega;
              expect(find.text(cuerpo), findsOneWidget);
              await verEnPantalla(tester, find.text('Sí, dar de baja'));
              dentroDeLaPantalla(tester, find.text('Sí, dar de baja'));
              dentroDeLaPantalla(tester, find.text('No, volver'));
            }
            expect(tester.takeException(), isNull);
            sinTextoCortado(tester);
            await capturar(
              tester,
              '32D_${estado.name}_${tamano.width.toInt()}_x${escala.toStringAsFixed(0)}',
            );
          });
        }
      }
    }
  });

  group('32D · nombre larguísimo y la entrega', () {
    for (final tamano in tamanos) {
      for (final escala in escalas) {
        testWidgets(
          'dado un nombre largo, la entrega pendiente se lee entera · ${tamano.width.toInt()} · ×$escala',
          (tester) async {
            const nombre = 'Maximiliano-Bartolomé';
            await hojaConCuenta(
              tester,
              cuentaSoloUnaEntrega,
              tamano: tamano,
              escala: escala,
              nombre: nombre,
              apellido: 'Rodríguez de la Fuente y Pérez Castellanos',
            );
            expect(tester.takeException(), isNull);
            await verEnPantalla(tester, find.textContaining('tiene 1 entrega pendiente'));
            sinTextoCortado(tester);
            await capturar(
              tester,
              '32D_nombreLargo_${tamano.width.toInt()}_x${escala.toStringAsFixed(0)}',
            );
            await tester.tap(find.text('Dar de baja igual'));
            await asentar(tester);
            expect(tester.takeException(), isNull);
            await verEnPantalla(tester, find.text('Sí, dar de baja'));
            sinTextoCortado(tester);
          },
        );
      }
    }
  });

  group('32D · casos límite del flujo', () {
    testWidgets('dado solo 1 entrega pendiente, «Dar de baja igual» no escribe y «Sí, dar de baja» '
        'sí, con la confirmación', (tester) async {
      final e = await hojaConCuenta(tester, cuentaSoloUnaEntrega);
      expect(e.repo.bajasRecibidas, isEmpty);

      await tester.tap(find.text('Dar de baja igual'));
      await asentar(tester);
      expect(e.repo.bajasRecibidas, isEmpty, reason: 'la primera confirmación no escribe');

      await tester.tap(find.text('Sí, dar de baja'));
      await asentar(tester);
      expect(e.repo.bajasRecibidas, hasLength(1));
      expect(e.resultado.cierres, 1);
    });

    testWidgets('dado «No, volver» en 32D·03 solo con entrega, vuelve al resumen y no escribe', (
      tester,
    ) async {
      final e = await hojaConCuenta(tester, cuentaSoloUnaEntrega, segunda: true);
      await tester.tap(find.text('No, volver'));
      await asentar(tester);

      expect(find.text('¿Dar de baja a Jorge?'), findsOneWidget);
      expect(find.text('Jorge tiene 1 entrega pendiente.'), findsOneWidget);
      expect(e.repo.bajasRecibidas, isEmpty);
      // Y se puede volver a confirmar.
      await tester.tap(find.text('Dar de baja igual'));
      await asentar(tester);
      await tester.tap(find.text('Sí, dar de baja'));
      await asentar(tester);
      expect(e.repo.bajasRecibidas, hasLength(1));
    });

    testWidgets('dado un doble toque en «Sí, dar de baja» con entrega, se escribe una sola baja', (
      tester,
    ) async {
      final e = await hojaConCuenta(tester, cuentaSoloTresEntregas, segunda: true);
      e.repo.compuertaBaja = Completer<void>();

      await tester.tap(find.text('Sí, dar de baja'));
      await tester.pump();
      await tester.tap(find.text('Dando de baja…'), warnIfMissed: false);
      await tester.pump();
      expect(e.repo.bajasRecibidas, hasLength(1));

      e.repo.compuertaBaja!.complete();
      await asentar(tester);
      expect(e.repo.bajasRecibidas, hasLength(1));
      expect(e.resultado.cierres, 1);
    });

    testWidgets('dada una falla a mitad de la baja con entrega, el botón vuelve y reintenta', (
      tester,
    ) async {
      final e = await hojaConCuenta(tester, cuentaSoloUnaEntrega, segunda: true);
      e.repo.resultadosBaja.add(const FailureInesperado());

      await tester.tap(find.text('Sí, dar de baja'));
      await asentar(tester);
      expect(e.resultado.cierres, 0, reason: 'la hoja sigue abierta');
      expect(find.text('Sí, dar de baja'), findsOneWidget, reason: 'el botón volvió');
      expect(find.text('No, volver'), findsOneWidget);
      expect(find.text('Dando de baja…'), findsNothing);

      await tester.tap(find.text('Sí, dar de baja'));
      await asentar(tester);
      expect(e.repo.bajasRecibidas, hasLength(2));
      expect(e.resultado.cierres, 1);
    });

    testWidgets('dado que entregó de más (hechas > totales), no hay pendientes: una confirmación', (
      tester,
    ) async {
      await hojaConCuenta(tester, cuentaConEntregaDeMas);
      expect(find.text('Dar de baja'), findsOneWidget);
      expect(find.textContaining('entrega pendiente'), findsNothing);
      expect(find.text('Dar de baja igual'), findsNothing);
    });

    testWidgets('dado todo pagado y entregado, la baja es la de una confirmación (32D·01)', (
      tester,
    ) async {
      await hojaConCuenta(tester, cuentaAlDia);
      expect(find.text('Dar de baja'), findsOneWidget);
      expect(find.text('Dar de baja igual'), findsNothing);
    });

    testWidgets('dada solo deuda (sin entregas), el aviso no menciona entregas y 32D·03 es el '
        'del canvas', (tester) async {
      await hojaConCuenta(tester, cuentaSoloDeuda, segunda: true);
      expect(
        find.text(
          'La deuda de ${FormatoBajaPersona.monto(120000)} sigue en tu cuenta aunque Jorge esté de baja.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('entrega'), findsNothing);
    });

    testWidgets('dada una entrega que llega entre la apertura y la confirmación, se frena y avisa '
        'con la entrega', (tester) async {
      // Se abre sin pendientes (32D·01); al confirmar, la cuenta ya tiene una entrega.
      final cuentas = CuentasFalsas(secuencia: [cuentaAlDia, cuentaSoloUnaEntrega]);
      final e = await hojaConCuenta(tester, cuentaAlDia, cuentas: cuentas);
      await tester.tap(find.text('Dar de baja'));
      await asentar(tester);

      expect(e.repo.bajasRecibidas, isEmpty, reason: 'no se escribió sin la doble confirmación');
      expect(find.text('Jorge tiene 1 entrega pendiente.'), findsOneWidget);
      expect(find.text('Dar de baja igual'), findsOneWidget);
    });

    testWidgets('dado Cancelar en el resumen con entrega, se cierra sin escribir', (tester) async {
      final e = await hojaConCuenta(tester, cuentaSoloUnaEntrega);
      await tester.tap(find.text('Cancelar'));
      await asentar(tester);
      expect(e.repo.bajasRecibidas, isEmpty);
      expect(e.resultado.cierres, 1);
    });

    test('los textos de la entrega (singular, plural, cero) son los de la decisión del 27/10', () {
      expect(TextosBajaPersona.entregasPendientes(1), '1 entrega pendiente');
      expect(TextosBajaPersona.entregasPendientes(2), '2 entregas pendientes');
      expect(TextosBajaPersona.entregasPendientes(12), '12 entregas pendientes');
      expect(
        TextosBajaPersona.resumenDeSaldo('Jorge', cuentaSoloUnaEntrega),
        'Jorge tiene 1 entrega pendiente.',
      );
      expect(
        TextosBajaPersona.resumenDeSaldo('María', cuentaDeudaYEntrega),
        'María te debe ${FormatoBajaPersona.monto(120000)} y tiene 1 entrega pendiente.',
      );
    });
  });

  group('32E · «Se borra el …»: fechas y casos límite', () {
    NotaPersona borradaEn(DateTime cuando) => notaDePrueba('x', 'n', borrada: cuando);

    test('dado un día de fin de año o bisiesto, los 90 días caen en el día correcto', () {
      // Se compara en hora local de cada fecha: los 90 días son 90 × 24 h.
      expect(FormatoNotas.diaDeBorrado(borradaEn(DateTime.utc(2026, 10, 2, 12))), '31/12');
      expect(FormatoNotas.diaDeBorrado(borradaEn(DateTime.utc(2026, 10, 3, 12))), '01/01');
      // 2027-12-02 + 90 días = 2028-03-01 (2028 es bisiesto: febrero tiene 29).
      expect(FormatoNotas.diaDeBorrado(borradaEn(DateTime.utc(2027, 12, 2, 12))), '01/03');
      expect(FormatoNotas.diaDeBorrado(borradaEn(DateTime.utc(2026, 12, 2, 12))), '02/03');
    });

    test('dada una nota sin borrar, no hay fecha de borrado', () {
      expect(FormatoNotas.diaDeBorrado(notaDePrueba('x', 'n')), isNull);
    });

    test('dado el huso del equipo, la fecha es la del día local (borrada de noche)', () {
      // 22/10 a las 22:00 en Montevideo (UTC-3) es el 23/10 01:00 UTC: a los 90 días, el 20/01 a las
      // 22:00 locales (21/01 en UTC). Se prueba con el huso con el que corra la suite.
      final nota = borradaEn(DateTime.utc(2026, 10, 23, 1));
      final offset = DateTime.now().timeZoneOffset;
      final esperado = offset == const Duration(hours: -3) ? '20/01' : '21/01';
      if (offset == Duration.zero || offset == const Duration(hours: -3)) {
        expect(FormatoNotas.diaDeBorrado(nota), esperado);
      }
    });

    testWidgets('dada una nota que se vence con la pantalla abierta y sin otro cambio, a las 16:01 '
        'ya no se muestra al volver a pintar', (tester) async {
      var hora = DateTime(2026, 10, 22, 15);
      final repo = NotaPersonaRepositorioFalso(
        notas: [
          notaDePrueba('b1', 'Se va a las 16:00.', borrada: borradaSeVaHoy),
          notaDePrueba('b2', 'Se queda.', borrada: borradaHoy),
        ],
      );
      await montarNotas(tester, repo: repo, reloj: () => hora);
      await tester.tap(find.text('Ver borradas (2)'));
      await asentar(tester);
      expect(find.text('Se va a las 16:00.'), findsOneWidget);

      // Pasa la hora y la persona toca «Restaurar» en la que se queda: la lista se pinta de nuevo.
      hora = DateTime(2026, 10, 22, 16, 1);
      await tester.tap(find.bySemanticsLabel(RegExp('^Restaurar la nota')).last);
      await asentar(tester);
      expect(find.text('Se va a las 16:00.'), findsNothing);
    });

    testWidgets('dada una restauración que falla, la nota sigue en «Ver borradas» con su fecha y '
        'el aviso ofrece Reintentar', (tester) async {
      final e = await borradasEn(tester, EstadoBorradas.e05FallaRestaurar);
      expect(find.text('No pudimos restaurar la nota. Probá de nuevo.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.byKey(ClavesNotas.seBorraEl), findsNWidgets(2));
      expect(e.repo.cuantas('restaurar'), 1);

      await tester.tap(find.text('Reintentar'));
      await asentar(tester);
      expect(e.repo.cuantas('restaurar'), 2);
      expect(find.byKey(ClavesNotas.seBorraEl), findsNWidgets(1));
    });

    testWidgets('dado un doble toque en «Restaurar» de una nota, se restaura una sola vez', (
      tester,
    ) async {
      final e = await borradasEn(tester, EstadoBorradas.e05Restaurando);
      // El primer toque quedó en vuelo (compuerta): un segundo toque no repite.
      await tester.tap(find.bySemanticsLabel(RegExp('^Restaurar la nota')).first);
      await tester.pump();
      expect(e.repo.cuantas('restaurar'), 1);
      e.repo.compuertas['restaurar']!.complete();
      await asentar(tester);
      expect(e.repo.cuantas('restaurar'), 1);
    });

    testWidgets('dado un lector de pantalla a 2,0×, «Se borra el» está en el nodo de la nota y '
        '«Restaurar» sigue como botón aparte', (tester) async {
      final semantica = tester.ensureSemantics();
      await borradasEn(
        tester,
        EstadoBorradas.e05Una,
        escala: 2,
        tamano: const Size(360, 640),
        lector: true,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^hoy a las 14:20\. Pidió volver el sábado con el esposo\.\. Se borra el 20/01\.$',
          ),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^Restaurar la nota')), findsOneWidget);
      semantica.dispose();
    });
  });
}
