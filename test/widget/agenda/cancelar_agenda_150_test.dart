// Cancelar una agenda (HU-VIS-004, #150, vista 23C·04 y 23C·05): el enlace al pie del detalle, la hoja
// de confirmación, la cancelación y el aviso. Los escenarios llevan el título de la HU y los casos
// límite de cada flujo: doble toque, falla a mitad, dos acciones seguidas, volver y reentrar, y el
// texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/enlace_cancelar_agenda.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cancelar_agenda_150_arnes.dart';

const _cuerpoEntrevista =
    'Queda como cancelada (la ves con el filtro «Canceladas»), se borra el recordatorio y la '
    'casa vuelve a su estado anterior.';
const _cuerpoCobranza =
    'Queda como cancelada (la ves con el filtro «Canceladas») y se borra el recordatorio.';
const _noPudimos = 'No pudimos guardar el cambio. La agenda sigue como estaba.';

void main() {
  Future<void> abrirHoja(WidgetTester tester) async {
    await tester.tap(enlaceCancelar);
    await asentarCancelacion(tester);
  }

  Future<void> confirmar(WidgetTester tester) async {
    await tester.tap(botonCancelarDeLaHoja);
    await asentarCancelacion(tester);
  }

  group('23C·01 → 23C·04: el enlace y la hoja', () {
    testWidgets('dado el detalle de una agenda PROGRAMADA, cuando lo miro, «Cancelar agenda» está '
        'al pie como enlace', (tester) async {
      await montarCancelacion(tester);

      expect(enlaceCancelar, findsOneWidget);
      expect(find.byType(TextButton), findsWidgets);
      expect(hoja, findsNothing);
    });

    testWidgets('dado una entrevista, cuando toco «Cancelar agenda», se abre «¿Cancelar la '
        'entrevista?» con el texto del canvas y las dos salidas', (tester) async {
      await montarCancelacion(tester);

      await abrirHoja(tester);

      expect(hoja, findsOneWidget);
      expect(find.text('¿Cancelar la entrevista?'), findsOneWidget);
      expect(find.text(_cuerpoEntrevista), findsOneWidget);
      expect(
        find.descendant(of: botonCancelarDeLaHoja, matching: find.text('Cancelar agenda')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: botonVolverDeLaHoja, matching: find.text('Volver')),
        findsOneWidget,
      );
    });

    testWidgets('dado una cobranza, cuando toco «Cancelar agenda», el título dice cobranza y el '
        'texto no promete cambiar el color de la casa', (tester) async {
      await montarCancelacion(tester, tipo: TipoAgenda.cobranza);

      await abrirHoja(tester);

      expect(find.text('¿Cancelar la cobranza?'), findsOneWidget);
      expect(find.text(_cuerpoCobranza), findsOneWidget);
      expect(find.textContaining('casa vuelve'), findsNothing);
    });

    for (final estado in [EstadoAgenda.cumplida, EstadoAgenda.noCumplida, EstadoAgenda.cancelada]) {
      testWidgets('dado una agenda ${estado.codigo}, cuando miro el detalle, no hay enlace para '
          'cancelarla (23C·06)', (tester) async {
        await montarCancelacion(tester, estado: estado);

        expect(enlaceCancelar, findsNothing);
        expect(find.text('Cancelar agenda'), findsNothing);
      });
    }

    testWidgets('dado que «Volver», cuando lo toco, la hoja se cierra y no se cancela nada '
        '(vuelvo al detalle sin cambios)', (tester) async {
      final arnes = await montarCancelacion(tester);
      await abrirHoja(tester);

      await tester.tap(botonVolverDeLaHoja);
      await asentarCancelacion(tester);

      expect(hoja, findsNothing);
      expect(find.text('Detalle de prueba'), findsOneWidget);
      expect(arnes.repositorio.canceladas, isEmpty);
      expect(arnes.recordatorios.llamadas, isEmpty);
    });

    testWidgets('dado la hoja abierta, cuando uso «atrás» del sistema, se cierra sin cancelar', (
      tester,
    ) async {
      final arnes = await montarCancelacion(tester);
      await abrirHoja(tester);

      await tester.binding.handlePopRoute();
      await asentarCancelacion(tester);

      expect(hoja, findsNothing);
      expect(find.text('Detalle de prueba'), findsOneWidget);
      expect(arnes.repositorio.canceladas, isEmpty);
    });
  });

  group('Escenario: Cancelar (23C·05)', () {
    testWidgets(
      'dado que tengo agenda PROGRAMADA, cuando cancelo, se cancela con la hora de ahora, '
      'se saca el recordatorio, vuelvo a la lista y veo «Agenda cancelada.»',
      (tester) async {
        final arnes = await montarCancelacion(tester);
        await abrirHoja(tester);

        await confirmar(tester);

        expect(arnes.repositorio.canceladas, [(agendaId: idAgendaCancelar, ahora: ahoraCancelar)]);
        expect(arnes.recordatorios.llamadas, ['cancelar:$idAgendaCancelar']);
        expect(arnes.recordatorios.programados, isEmpty);
        expect(hoja, findsNothing);
        expect(find.text('Detalle de prueba'), findsNothing);
        expect(find.text('Lista de agendas'), findsOneWidget);
        expect(find.text('Agenda cancelada.'), findsOneWidget);
      },
    );

    testWidgets('dado que el teléfono no puede sacar el aviso, cuando cancelo, la agenda queda '
        'cancelada y el aviso lo dice con qué hacer', (tester) async {
      final recordatorios = RecordatoriosEnMemoria()..puedeCancelar = false;
      final arnes = await montarCancelacion(tester, recordatorios: recordatorios);
      await abrirHoja(tester);

      await confirmar(tester);

      expect(arnes.repositorio.canceladas, hasLength(1));
      expect(find.text('Lista de agendas'), findsOneWidget);
      expect(
        find.text('Agenda cancelada. No pudimos borrar el recordatorio: puede sonar igual.'),
        findsOneWidget,
      );
      expect(find.text('Agenda cancelada.'), findsNothing);
    });

    testWidgets(
      'dado un detalle que se queda (alCancelar), cuando cancelo, el aviso sale, se llama '
      'a alCancelar y el enlace desaparece al repintarse con la agenda cancelada',
      (tester) async {
        final arnes = await montarCancelacion(tester, cierraAlCancelar: false);
        await abrirHoja(tester);

        await confirmar(tester);

        expect(arnes.cancelaciones, [true]);
        expect(find.text('Detalle de prueba'), findsOneWidget);
        expect(find.text('Estado: CANCELADA'), findsOneWidget);
        expect(find.text('Agenda cancelada.'), findsOneWidget);
        expect(enlaceCancelar, findsNothing);
      },
    );
  });

  group('Cancelando: doble toque y dos acciones seguidas', () {
    testWidgets('dado que la cancelación está en curso, cuando miro la hoja, el botón dice '
        '«Cancelando…» y ni él ni «Volver» responden', (tester) async {
      final arnes = await montarCancelacion(tester);
      arnes.repositorio.compuertaCancelar = Completer<void>();
      await abrirHoja(tester);

      await tester.tap(botonCancelarDeLaHoja);
      await tester.pump();

      expect(find.text('Cancelando…'), findsOneWidget);
      expect(tester.widget<FilledButton>(botonCancelarDeLaHoja).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(botonVolverDeLaHoja).onPressed, isNull);

      arnes.repositorio.compuertaCancelar!.complete();
      await asentarCancelacion(tester);
      expect(find.text('Lista de agendas'), findsOneWidget);
    });

    testWidgets('dado un doble toque en «Cancelar agenda», cuando llega el segundo, se cancela una '
        'sola vez', (tester) async {
      final arnes = await montarCancelacion(tester);
      arnes.repositorio.compuertaCancelar = Completer<void>();
      await abrirHoja(tester);
      final alTocar = tester.widget<FilledButton>(botonCancelarDeLaHoja).onPressed!;

      alTocar();
      alTocar();
      await tester.pump();

      expect(arnes.repositorio.canceladas, hasLength(1));
      arnes.repositorio.compuertaCancelar!.complete();
      await asentarCancelacion(tester);
      expect(arnes.repositorio.canceladas, hasLength(1));
      expect(arnes.recordatorios.llamadas, ['cancelar:$idAgendaCancelar']);
    });

    testWidgets(
      'dado un doble toque en el enlace, cuando llega el segundo, se abre una sola hoja',
      (tester) async {
        await montarCancelacion(tester);
        final alTocar = tester
            .widget<TextButton>(
              find.ancestor(of: enlaceCancelar, matching: find.byType(TextButton)),
            )
            .onPressed!;

        alTocar();
        alTocar();
        await asentarCancelacion(tester);

        expect(hoja, findsOneWidget);
      },
    );

    testWidgets('dado que cancelo y enseguida toco «Volver» o «atrás», cuando la cancelación '
        'sigue en curso, la hoja no se cierra de costado: espera al resultado', (tester) async {
      final arnes = await montarCancelacion(tester);
      arnes.repositorio.compuertaCancelar = Completer<void>();
      await abrirHoja(tester);
      await tester.tap(botonCancelarDeLaHoja);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));

      expect(hoja, findsOneWidget);
      arnes.repositorio.compuertaCancelar!.complete();
      await asentarCancelacion(tester);
      expect(hoja, findsNothing);
      expect(arnes.repositorio.canceladas, hasLength(1));
      expect(find.text('Agenda cancelada.'), findsOneWidget);
    });
  });

  group('Falla a mitad de la acción', () {
    testWidgets('dado que la base falla, cuando cancelo, aparece el aviso rojo, el botón pasa a '
        '«Reintentar» y vuelve a responder; «Volver» también', (tester) async {
      final arnes = await montarCancelacion(tester);
      arnes.repositorio.resultadosCancelar.add(const FailureInesperado(causa: 'StateError'));
      await abrirHoja(tester);

      await confirmar(tester);

      expect(hoja, findsOneWidget);
      expect(find.text(_noPudimos), findsOneWidget);
      expect(find.text('Cancelando…'), findsNothing);
      expect(
        find.descendant(of: botonCancelarDeLaHoja, matching: find.text('Reintentar')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(botonCancelarDeLaHoja).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(botonVolverDeLaHoja).onPressed, isNotNull);
      expect(arnes.recordatorios.llamadas, isEmpty, reason: 'el aviso sigue: la agenda también');
      expect(arnes.recordatorios.programados.keys, [idAgendaCancelar]);
    });

    testWidgets('dado una falla, cuando toco «Reintentar», se cancela, el aviso rojo se va y '
        'vuelvo a la lista con «Agenda cancelada.»', (tester) async {
      final arnes = await montarCancelacion(tester);
      arnes.repositorio.resultadosCancelar.add(const FailureInesperado(causa: 'StateError'));
      await abrirHoja(tester);
      await confirmar(tester);

      await confirmar(tester);

      expect(arnes.repositorio.canceladas, hasLength(2));
      expect(find.text(_noPudimos), findsNothing);
      expect(find.text('Lista de agendas'), findsOneWidget);
      expect(find.text('Agenda cancelada.'), findsOneWidget);
      expect(arnes.recordatorios.programados, isEmpty);
    });

    testWidgets('dado una excepción que se escapa del repositorio, cuando cancelo, se trata como '
        'una falla: la hoja no queda trabada y el reintento funciona', (tester) async {
      final arnes = await montarCancelacion(tester);
      arnes.repositorio.cancelarLanza = true;
      await abrirHoja(tester);

      await confirmar(tester);

      expect(find.text(_noPudimos), findsOneWidget);
      expect(find.text('Cancelando…'), findsNothing);
      expect(tester.widget<FilledButton>(botonCancelarDeLaHoja).onPressed, isNotNull);

      arnes.repositorio.cancelarLanza = false;
      await confirmar(tester);
      expect(find.text('Agenda cancelada.'), findsOneWidget);
    });

    testWidgets('dado que la agenda ya se cumplió mientras la hoja estaba abierta, cuando cancelo, '
        'el aviso dice por qué y queda solo «Volver» (reintentar no cambiaría nada)', (
      tester,
    ) async {
      final arnes = await montarCancelacion(tester);
      arnes.repositorio.resultadosCancelar.add(
        const FailureValidacion(
          campos: {
            'agenda': 'Esa agenda ya se cumplió o se canceló. Revisá la lista de agendados.',
          },
        ),
      );
      await abrirHoja(tester);

      await confirmar(tester);

      expect(
        find.text('Esa agenda ya se cumplió o se canceló. Revisá la lista de agendados.'),
        findsOneWidget,
      );
      expect(botonCancelarDeLaHoja, findsNothing);
      expect(find.text('Reintentar'), findsNothing);
      expect(botonVolverDeLaHoja, findsOneWidget);
      expect(arnes.recordatorios.llamadas, isEmpty);

      await tester.tap(botonVolverDeLaHoja);
      await asentarCancelacion(tester);
      expect(hoja, findsNothing);
    });

    testWidgets(
      'dado una validación sin mensaje, cuando cancelo, el aviso usa el texto de siempre',
      (tester) async {
        final arnes = await montarCancelacion(tester);
        arnes.repositorio.resultadosCancelar.add(const FailureValidacion(campos: {}));
        await abrirHoja(tester);

        await confirmar(tester);

        expect(
          find.text('Esa agenda ya se cumplió o se canceló. Revisá la lista de agendados.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Volver atrás y reentrar', () {
    testWidgets(
      'dado que falló y toqué «Volver», cuando abro la hoja de nuevo, empieza limpia: sin '
      'el aviso y con «Cancelar agenda», no «Reintentar»',
      (tester) async {
        final arnes = await montarCancelacion(tester);
        arnes.repositorio.resultadosCancelar.add(const FailureInesperado(causa: 'StateError'));
        await abrirHoja(tester);
        await confirmar(tester);
        await tester.tap(botonVolverDeLaHoja);
        await asentarCancelacion(tester);

        await abrirHoja(tester);

        expect(find.text(_noPudimos), findsNothing);
        expect(
          find.descendant(of: botonCancelarDeLaHoja, matching: find.text('Cancelar agenda')),
          findsOneWidget,
        );
        expect(find.text('Reintentar'), findsNothing);
        expect(hoja, findsOneWidget);
      },
    );

    testWidgets('dado que cancelé y volví a la lista, cuando entro de nuevo al detalle con la '
        'agenda ya cancelada, no hay enlace', (tester) async {
      final arnes = await montarCancelacion(tester);
      await abrirHoja(tester);
      await confirmar(tester);
      arnes.cambiarEstado(EstadoAgenda.cancelada);

      await tester.tap(find.text('abrir detalle'));
      await asentarCancelacion(tester);

      expect(find.text('Detalle de prueba'), findsOneWidget);
      expect(enlaceCancelar, findsNothing);
      expect(arnes.aperturasDelDetalle, 2);
    });

    testWidgets('dado que el detalle se cierra con la hoja abierta (atrás dos veces), cuando '
        'cancelo no queda ningún aviso colgado ni excepción', (tester) async {
      await montarCancelacion(tester);
      await abrirHoja(tester);

      await tester.binding.handlePopRoute();
      await asentarCancelacion(tester);
      await tester.binding.handlePopRoute();
      await asentarCancelacion(tester);

      expect(find.text('Lista de agendas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Datos límite: texto al 200 % y pantallas chicas', () {
    for (final tamano in const [Size(390, 844), Size(320, 568)]) {
      testWidgets('dado el texto al 200 % en ${tamano.width.toInt()}×${tamano.height.toInt()}, '
          'cuando abro la hoja y cancelo, todo se alcanza y no hay desbordes', (tester) async {
        final arnes = await montarCancelacion(tester, escala: 2, tamano: tamano);
        expect(enlaceCancelar, findsOneWidget);
        await tester.ensureVisible(enlaceCancelar);
        await abrirHoja(tester);

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(botonCancelarDeLaHoja);
        await tester.pump();
        await tester.ensureVisible(botonVolverDeLaHoja);
        await tester.pump();
        await tester.ensureVisible(botonCancelarDeLaHoja);
        await tester.tap(botonCancelarDeLaHoja);
        await asentarCancelacion(tester);

        expect(tester.takeException(), isNull);
        expect(arnes.repositorio.canceladas, hasLength(1));
        expect(find.text('Agenda cancelada.'), findsOneWidget);
      });

      testWidgets(
        'dado el texto al 200 % en ${tamano.width.toInt()}×${tamano.height.toInt()} y una '
        'falla, cuando miro la hoja, el aviso entero y los dos botones se alcanzan',
        (tester) async {
          final arnes = await montarCancelacion(
            tester,
            escala: 2,
            tamano: tamano,
            tipo: TipoAgenda.cobranza,
          );
          arnes.repositorio.resultadosCancelar.add(const FailureInesperado(causa: 'StateError'));
          await abrirHoja(tester);
          await tester.ensureVisible(botonCancelarDeLaHoja);
          await tester.tap(botonCancelarDeLaHoja);
          await asentarCancelacion(tester);

          expect(tester.takeException(), isNull);
          expect(find.text(_noPudimos), findsOneWidget);
          await tester.ensureVisible(botonCancelarDeLaHoja);
          await tester.pump();
          expect(tester.getRect(botonCancelarDeLaHoja).bottom, lessThanOrEqualTo(tamano.height));
          await tester.ensureVisible(botonVolverDeLaHoja);
          await tester.pump();
          expect(tester.getRect(botonVolverDeLaHoja).bottom, lessThanOrEqualTo(tamano.height));
        },
      );
    }
  });

  group('Accesibilidad', () {
    testWidgets('dado el enlace y la hoja, cuando los miro, tienen objetivo táctil de 48, etiqueta '
        'y contraste', (tester) async {
      final handle = tester.ensureSemantics();
      await montarCancelacion(tester);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await abrirHoja(tester);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('dado la hoja abierta, cuando la recorre un lector, el título es un encabezado y '
        'los dos botones tienen su rótulo', (tester) async {
      final handle = tester.ensureSemantics();
      await montarCancelacion(tester);
      await abrirHoja(tester);

      expect(
        tester.getSemantics(find.text('¿Cancelar la entrevista?')),
        isSemantics(label: '¿Cancelar la entrevista?', isHeader: true),
      );
      expect(
        tester.getSemantics(botonCancelarDeLaHoja),
        isSemantics(label: 'Cancelar agenda', isButton: true, isEnabled: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('dado una falla, cuando aparece el aviso, se anuncia como región viva', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final arnes = await montarCancelacion(tester);
      arnes.repositorio.resultadosCancelar.add(const FailureInesperado(causa: 'StateError'));
      await abrirHoja(tester);
      await confirmar(tester);

      expect(tester.getSemantics(find.text(_noPudimos)), isSemantics(isLiveRegion: true));
      handle.dispose();
    });
  });

  testWidgets('dado EnlaceCancelarAgenda sin ProviderScope de prueba cargado, cuando el estado es '
      'cancelada, no pinta nada (ocupa 0×0)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EnlaceCancelarAgenda(
            agendaId: 'x',
            tipo: TipoAgenda.entrevista,
            estado: EstadoAgenda.cancelada,
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(EnlaceCancelarAgenda)), Size.zero);
  });
}
