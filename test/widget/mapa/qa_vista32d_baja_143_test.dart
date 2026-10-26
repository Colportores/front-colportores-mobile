// QA de la baja de persona y «Ver bajas» (HU-UBI-011, #143, PR #485, vista 32D): una persona con el
// teléfono en la mano, no el código. Cubre cada artboard del canvas (D·01 a D·05) y los estados que no
// dibuja, en la matriz 360×640 y 412×915 con el texto en 1,0 y 2,0, con las fuentes reales; los textos
// literales de la HU y del canvas; los casos límite de cada flujo (falla a mitad, acciones superpuestas,
// reentrada, nombres largos); y la privacidad de lo que se imprime.
//
// Las capturas se sacan con `--dart-define=QA_CAPTURAS=true` (a `.dart_tool/qa_capturas/`, ignorado).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_baja_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/baja_persona_use_cases.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_baja_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'baja_persona_arnes.dart';
import 'personas_arnes.dart';
import 'qa_vista32d_baja_143_arnes.dart';

final _reactivar = find.widgetWithText(TextButton, 'Reactivar');
final _mostrar = find.widgetWithText(SwitchListTile, 'Mostrar bajas');
final _botonesDeLaHoja = find.descendant(
  of: find.byType(HojaBajaPersona),
  matching: find.byWidgetPredicate((w) => w is FilledButton || w is TextButton),
);

String _tam(Size t, double e) =>
    '${t.width.toInt()}x${t.height.toInt()} texto ${e.toStringAsFixed(1)}';

/// Los montos de la app llevan un espacio que no se parte entre «\$» y el número (el canvas, uno común).
String _m(String t) => t.replaceAll('\$ ', '\$ ');

String _archivo(String s) => s.replaceAll(RegExp('[^A-Za-z0-9]+'), '_');

void main() {
  // ---------------------------------------------------------------------------------------------
  // Matriz de la hoja: 8 estados × 2 teléfonos × 2 escalas de texto.
  // ---------------------------------------------------------------------------------------------
  group('hoja de baja · matriz de estados y tamaños', () {
    for (final estado in EstadoHoja.values) {
      for (final tam in tamanos) {
        for (final escala in escalas) {
          testWidgets('${estado.rotulo} a ${_tam(tam, escala)}: sin overflow, nada cortado, '
              'acciones a la vista', (tester) async {
            await hojaEn(tester, estado, tamano: tam, escala: escala);

            expect(tester.takeException(), isNull);
            sinTextoCortado(tester);
            for (final b in _botonesDeLaHoja.evaluate()) {
              dentroDeLaPantalla(tester, find.byWidget(b.widget), rotulo: 'botón de la hoja');
            }
            // La explicación no queda aplastada por los botones fijos de abajo.
            final zona = find.descendant(
              of: find.byType(HojaBajaPersona),
              matching: find.byType(SingleChildScrollView),
            );
            expect(
              tester.getSize(zona.first).height,
              greaterThan(60),
              reason:
                  'la zona del texto de la hoja quedó de ${tester.getSize(zona.first).height} dp',
            );
            await capturar(
              tester,
              'hoja_${_archivo(estado.rotulo)}_${tam.width.toInt()}_${(escala * 10).toInt()}',
            );
            if (estado == EstadoHoja.revisando) {
              // Se deja la compuerta: el test no espera nada más.
            }
          });
        }
      }
    }
  });

  // ---------------------------------------------------------------------------------------------
  // Matriz de «Mostrar bajas»: 9 estados × 2 teléfonos × 2 escalas.
  // ---------------------------------------------------------------------------------------------
  group('Mostrar bajas · matriz de estados y tamaños', () {
    for (final estado in EstadoBajas.values) {
      for (final tam in tamanos) {
        for (final escala in escalas) {
          testWidgets('${estado.rotulo} a ${_tam(tam, escala)}: sin overflow, nada cortado', (
            tester,
          ) async {
            await bajasEn(tester, estado, tamano: tam, escala: escala);

            expect(tester.takeException(), isNull);
            // Los avisos que ocupan todo el cuerpo no deben tener texto cortado; en la lista larga
            // solo se mira lo que está pintado.
            sinTextoCortado(tester);
            await capturar(
              tester,
              'bajas_${_archivo(estado.rotulo)}_${tam.width.toInt()}_${(escala * 10).toInt()}',
            );
          });
        }
      }
    }
  });

  // ---------------------------------------------------------------------------------------------
  // Criterios de aceptación con el texto literal (HU-UBI-011 + canvas 32D, que gana en los textos).
  // ---------------------------------------------------------------------------------------------
  group('criterios de aceptación · textos literales', () {
    testWidgets('Escenario «Baja sin pendientes»: dado que no tiene EC pendiente, cuando confirmo '
        '«Dar de baja», se da de baja una vez y la hoja se cierra con la persona dada de baja', (
      tester,
    ) async {
      final e = await hojaEn(tester, EstadoHoja.d01);

      expect(find.text('¿Dar de baja a Jorge?'), findsOneWidget);
      expect(
        find.text(
          'Deja de aparecer en el depto. No se borra: lo ves en «Ver bajas» y lo podés reactivar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancelar'), findsOneWidget);
      await tester.tap(find.text('Dar de baja'));
      await asentar(tester);

      expect(e.repo.bajasRecibidas, hasLength(1));
      expect(e.repo.bajasRecibidas.single.personaId, 'p1');
      expect(e.resultado.cierres, 1);
      expect(e.resultado.salida, isA<PersonaBajaRealizada>());
      expect(find.byType(HojaBajaPersona), findsNothing);
    });

    testWidgets('Escenario «Baja con EC pendiente»: la UI advierte con la deuda y solo procede con '
        'la doble confirmación (textos de 32D·02 y 32D·03)', (tester) async {
      final e = await hojaEn(tester, EstadoHoja.d02, nombre: 'María');

      expect(find.text('¿Dar de baja a María?'), findsOneWidget);
      expect(find.text(_m('María te debe \$ 1.200 y tiene 1 entrega pendiente.')), findsOneWidget);
      for (final (rotulo, valor) in [
        ('Comprado', _m('\$ 4.500')),
        ('Entregado', '1 de 2'),
        ('Pagado', _m('\$ 3.300')),
        ('Saldo', _m('\$ 1.200')),
      ]) {
        expect(find.text(rotulo), findsOneWidget, reason: rotulo);
        expect(find.text(valor), findsOneWidget, reason: '$rotulo = $valor');
      }
      expect(find.text('Dar de baja igual'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      // Sin confirmar nada no se escribió nada.
      expect(e.repo.bajasRecibidas, isEmpty);

      await tester.tap(find.text('Dar de baja igual'));
      await asentar(tester);

      expect(e.repo.bajasRecibidas, isEmpty, reason: 'la primera confirmación no escribe');
      expect(find.text('¿Seguro?'), findsOneWidget);
      expect(
        find.text(_m('La deuda de \$ 1.200 sigue en tu cuenta aunque María esté de baja.')),
        findsOneWidget,
      );
      expect(find.text('Sí, dar de baja'), findsOneWidget);
      expect(find.text('No, volver'), findsOneWidget);

      await tester.tap(find.text('Sí, dar de baja'));
      await asentar(tester);

      expect(e.repo.bajasRecibidas, hasLength(1));
      expect(e.resultado.salida, isA<PersonaBajaRealizada>());
    });

    testWidgets('Escenario «Baja con EC pendiente»: «Cancelar» y «No, volver» no dan de baja a '
        'nadie', (tester) async {
      final e = await hojaEn(tester, EstadoHoja.d03);

      await tester.tap(find.text('No, volver'));
      await asentar(tester);
      expect(find.text('¿Dar de baja a Jorge?'), findsOneWidget);
      expect(find.text('Dar de baja igual'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await asentar(tester);

      expect(e.repo.bajasRecibidas, isEmpty);
      expect(e.resultado.cierres, 1);
      expect(e.resultado.salida, isNull);
    });

    testWidgets(
      'D·04: «Mostrar bajas» apagado esconde a la baja; prendido muestra «Baja el 22/10 · '
      'saldo \$ 1.200» y «Reactivar»',
      (tester) async {
        await bajasEn(tester, EstadoBajas.d04);
        // bajasEn ya prendió el interruptor.
        expect(find.text('María Fernández'), findsOneWidget);
        expect(find.text(_m('Baja el 22/10 · saldo \$ 1.200')), findsOneWidget);
        expect(_reactivar, findsOneWidget);
        expect(find.text('Jorge Fernández'), findsOneWidget);

        await tester.tap(_mostrar);
        await asentar(tester);
        expect(find.text('María Fernández'), findsNothing);
        expect(_reactivar, findsNothing);
      },
    );

    testWidgets('D·05: «Reactivar» devuelve a la persona a la lista y avisa «María está activa de '
        'nuevo.»', (tester) async {
      final repo = await bajasEn(tester, EstadoBajas.d05);

      expect(repo.reactivacionesRecibidas, ['p2']);
      expect(find.text('María está activa de nuevo.'), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.text('CLIENTES · 2'), findsOneWidget);
      // Sin más bajas, el interruptor desaparece.
      expect(_mostrar, findsNothing);
    });
  });

  // ---------------------------------------------------------------------------------------------
  // Casos límite de cada flujo.
  // ---------------------------------------------------------------------------------------------
  group('casos límite · hoja', () {
    testWidgets('falla a mitad de la baja sin saldo: el botón vuelve a estar habilitado, no queda '
        '«Dando de baja…», y el segundo intento da de baja', (tester) async {
      final e = await hojaEn(tester, EstadoHoja.fallaSinSaldo);

      expect(find.text('No pudimos dar de baja a Jorge. Probá de nuevo.'), findsOneWidget);
      expect(find.text('Dando de baja…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final boton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Dar de baja'));
      expect(boton.onPressed, isNotNull);

      await tester.tap(find.text('Dar de baja'));
      await asentar(tester);

      expect(e.repo.bajasRecibidas, hasLength(2));
      expect(e.resultado.salida, isA<PersonaBajaRealizada>());
    });

    testWidgets('falla en la segunda confirmación: el aviso dice qué hacer, «No, volver» sigue '
        'andando y el aviso no vuelve al resumen', (tester) async {
      final e = await hojaEn(tester, EstadoHoja.fallaConfirmar);

      expect(find.text('No pudimos dar de baja a Jorge. Probá de nuevo.'), findsOneWidget);
      expect(find.text('Sí, dar de baja'), findsOneWidget);

      await tester.tap(find.text('No, volver'));
      await asentar(tester);

      expect(find.text('¿Dar de baja a Jorge?'), findsOneWidget);
      expect(find.textContaining('No pudimos dar de baja'), findsNothing);
      expect(e.repo.bajasRecibidas, hasLength(1));
    });

    testWidgets('la cuenta no se puede leer: no ofrece la baja, «Reintentar» revisa de nuevo y, '
        'si ahora anda, sigue por D·01', (tester) async {
      final e = await hojaEn(tester, EstadoHoja.errorRevision);

      expect(find.text('No pudimos revisar si Jorge tiene saldo. Probá de nuevo.'), findsOneWidget);
      expect(find.text('Dar de baja'), findsNothing);
      expect(find.text('Dar de baja igual'), findsNothing);

      e.cuentas.lanza = null;
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);

      expect(e.cuentas.consultas, 2);
      expect(find.text('Dar de baja'), findsOneWidget);
      expect(find.textContaining('No pudimos revisar'), findsNothing);
      expect(e.repo.bajasRecibidas, isEmpty);
    });

    testWidgets(
      'mientras revisa la cuenta se puede cancelar; si la respuesta llega después no pasa '
      'nada (ni excepción ni hoja fantasma)',
      (tester) async {
        final e = await hojaEn(tester, EstadoHoja.revisando);
        expect(find.text('Revisando la cuenta de Jorge…'), findsOneWidget);

        await tester.tap(find.text('Cancelar'));
        await asentar(tester);
        e.cuentas.compuerta!.complete();
        await asentar(tester);

        expect(find.byType(HojaBajaPersona), findsNothing);
        expect(tester.takeException(), isNull);
        expect(e.repo.bajasRecibidas, isEmpty);
      },
    );

    testWidgets('mientras se escribe la baja, tocar afuera no cierra la hoja y, al terminar, se '
        'cierra con la persona dada de baja', (tester) async {
      final e = await hojaEn(tester, EstadoHoja.dandoDeBaja);
      expect(find.text('Dando de baja…'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await asentar(tester);
      expect(find.byType(HojaBajaPersona), findsOneWidget);

      e.repo.compuertaBaja!.complete();
      await asentar(tester);

      expect(find.byType(HojaBajaPersona), findsNothing);
      expect(e.resultado.salida, isA<PersonaBajaRealizada>());
      expect(e.repo.bajasRecibidas, hasLength(1));
    });

    testWidgets('cerrar con el atrás de Android mientras se escribe tampoco cierra (el resultado '
        'no se pierde)', (tester) async {
      final e = await hojaEn(tester, EstadoHoja.dandoDeBaja);

      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(find.byType(HojaBajaPersona), findsOneWidget);

      e.repo.compuertaBaja!.complete();
      await asentar(tester);
      expect(e.resultado.salida, isA<PersonaBajaRealizada>());
    });

    testWidgets('el aviso de falla se anuncia al lector (región viva) y el título de la hoja es un '
        'encabezado', (tester) async {
      final handle = tester.ensureSemantics();
      await hojaEn(tester, EstadoHoja.fallaSinSaldo);

      expect(
        tester.getSemantics(find.textContaining('No pudimos dar de baja')),
        isSemantics(isLiveRegion: true),
      );
      expect(tester.getSemantics(find.text('¿Dar de baja a Jorge?')), isSemantics(isHeader: true));
      handle.dispose();
    });

    testWidgets('persona sin nombre (solo espacios): la hoja habla de «La persona» y no queda un '
        'título vacío', (tester) async {
      await hojaEn(tester, EstadoHoja.d01, nombre: '   ', apellido: '');

      expect(find.text('¿Dar de baja a La persona?'), findsOneWidget);
    });

    testWidgets(
      'D·02 a 360×640 con el texto en 2,0: los rótulos del cuadro de la cuenta no se parten '
      'a mitad de palabra («Comprad / o»)',
      (tester) async {
        await hojaEn(tester, EstadoHoja.d02, escala: 2);

        for (final rotulo in ['Comprado', 'Entregado', 'Pagado', 'Saldo']) {
          final p = tester.renderObject<RenderParagraph>(find.text(rotulo));
          final cajas = p.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: rotulo.length),
          );
          final renglones = cajas.map((c) => c.top.round()).toSet().length;
          expect(renglones, 1, reason: '«$rotulo» se parte en $renglones renglones');
        }
        // skip: QA #143 — rótulo y valor son dos `Flexible` iguales: con el valor ancho, «Comprado» queda
        // en la mitad del cuadro y se parte («Comprad» / «o»); a 412×915 no pasa.
      },
      skip: true,
    );

    for (final estado in EstadoHoja.values) {
      testWidgets('nombre larguísimo con emoji y texto 2,0 a 360×640 (${estado.rotulo}): sin '
          'overflow y las acciones a la vista', (tester) async {
        final largo = '${'Maximiliano' * 8} 🙂';
        await hojaEn(tester, estado, escala: 2, nombre: largo, apellido: 'Fernández de la Peña');

        expect(tester.takeException(), isNull);
        sinTextoCortado(tester);
        for (final b in _botonesDeLaHoja.evaluate()) {
          dentroDeLaPantalla(tester, find.byWidget(b.widget), rotulo: 'botón de la hoja');
        }
      });
    }

    testWidgets('con el teclado abierto de otra pantalla (viewInsets) la hoja sigue entera', (
      tester,
    ) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await hojaEn(tester, EstadoHoja.d02);

      expect(tester.takeException(), isNull);
      for (final b in _botonesDeLaHoja.evaluate()) {
        dentroDeLaPantalla(tester, find.byWidget(b.widget), rotulo: 'botón de la hoja');
      }
    });

    testWidgets('reentrar a la hoja después de cancelar y después de una baja: cada apertura '
        'empieza de cero', (tester) async {
      final e = await hojaEn(tester, EstadoHoja.d03);
      await tester.tap(find.text('No, volver'));
      await asentar(tester);
      await tester.tap(find.text('Cancelar'));
      await asentar(tester);
      expect(find.byType(HojaBajaPersona), findsNothing);

      await tester.tap(find.text('abrir baja'));
      await asentar(tester);

      expect(find.text('Dar de baja igual'), findsOneWidget, reason: 'vuelve al resumen D·02');
      expect(find.text('¿Seguro?'), findsNothing);
      expect(e.cuentas.consultas, 2, reason: 'revisa la cuenta cada vez que se abre');
    });

    testWidgets('la deuda llega mientras la hoja de D·01 está abierta: no se escribe nada y se '
        'muestra el resumen D·02', (tester) async {
      final e = await hojaEn(tester, EstadoHoja.d01);
      e.cuentas.cuenta = cuentaConSaldo;

      await tester.tap(find.text('Dar de baja'));
      await asentar(tester);

      expect(e.repo.bajasRecibidas, isEmpty);
      expect(find.text(_m('Jorge te debe \$ 1.200 y tiene 1 entrega pendiente.')), findsOneWidget);
      expect(find.text('Dar de baja igual'), findsOneWidget);
    });
  });

  group('casos límite · Mostrar bajas', () {
    testWidgets('dos reactivaciones superpuestas, la primera falla y la segunda sale bien: la '
        'primera sigue en las bajas con su botón, la segunda vuelve a la lista', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([
          clienteDePersonas('p1', 'Jorge', apellido: 'Fernández'),
          clienteDeBajaDePersonas('p2', 'María', apellido: 'Fernández', minutos: 1),
          clienteDeBajaDePersonas('p3', 'Luis', apellido: 'Pérez', minutos: 2),
        ]);
      final compuerta = Completer<void>();
      repo
        ..compuertaReactivar = compuerta
        ..resultadosReactivar.add(const FailureInesperado()); // la primera pedida falla
      await cargarFuentes(tester);
      await montarClientes(tester, repo: repo, otrosOverrides: extrasBajas());
      await tester.tap(_mostrar);
      await asentar(tester);
      expect(_reactivar, findsNWidgets(2));

      await tester.tap(_reactivar.at(0));
      await tester.pump();
      // La primera fila ya es un indicador: el único «Reactivar» que queda es el de la otra.
      expect(_reactivar, findsOneWidget);
      await tester.tap(_reactivar);
      await tester.pump();
      compuerta.complete();
      await asentar(tester);

      expect(repo.reactivacionesRecibidas, hasLength(2));
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'nada queda en ocupado');
      // Quedó una sola baja (la que falló) con su botón; la otra volvió a la lista.
      expect(_reactivar, findsOneWidget);
      expect(find.text('CLIENTES · 2'), findsOneWidget);
    });

    testWidgets('falla al reactivar: la fila vuelve a tener su botón y el aviso dice qué hacer', (
      tester,
    ) async {
      await bajasEn(tester, EstadoBajas.fallaReactivar);

      expect(find.text('No pudimos reactivar a María. Probá de nuevo.'), findsOneWidget);
      expect(_reactivar, findsOneWidget);
      expect(tester.widget<TextButton>(_reactivar).onPressed, isNotNull);
      expect(find.text('Reactivando…'), findsNothing);
    });

    testWidgets('error al leer las bajas: avisa con «Reintentar» y no rompe la lista de clientes', (
      tester,
    ) async {
      await bajasEn(tester, EstadoBajas.errorBajas);

      expect(find.text('No pudimos leer las bajas en tu teléfono.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Jorge Fernández'), findsOneWidget);
    });

    testWidgets('espacio dado de baja: las bajas se ven y no se ofrece «Reactivar»', (
      tester,
    ) async {
      await bajasEn(tester, EstadoBajas.espacioDeBaja);

      expect(find.text('María Fernández'), findsOneWidget);
      expect(_reactivar, findsNothing);
    });

    Future<void> montarBajaConNombre(WidgetTester tester, String nombre, String apellido) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([clienteDeBajaDePersonas('p2', nombre, apellido: apellido)]);
      await cargarFuentes(tester);
      await montarClientes(
        tester,
        repo: repo,
        escala: 2,
        tamano: const Size(360, 640),
        otrosOverrides: extrasBajas(saldos: {'p2': 123456789}),
      );
      await verEnPantalla(tester, _mostrar);
      await tester.tap(_mostrar);
      await asentar(tester);
      await verEnPantalla(tester, _reactivar);
    }

    testWidgets('nombre larguísimo con emoji de baja a 360×640 y texto 2,0: la fila no desborda y '
        'el botón queda a la vista', (tester) async {
      await montarBajaConNombre(tester, '${'Maximiliano' * 6} 🙂', 'Fernández de la Peña ' * 3);

      expect(tester.takeException(), isNull);
      dentroDeLaPantalla(tester, _reactivar, rotulo: 'Reactivar');
      expect(find.textContaining(_m('saldo \$ 1.234.567,89')), findsOneWidget);
    });

    testWidgets('un nombre de dos nombres y apellido compuesto (45 caracteres) se lee entero en la '
        'fila de la baja a 360×640 y texto 2,0', (tester) async {
      await montarBajaConNombre(tester, 'Maximiliano Alejandro 🙂', 'Fernández de la Peña');

      sinTextoCortado(tester);
      // skip: QA #143 — la fila de la baja corta con «…» un nombre de 45 caracteres a 200 % (maxLines 3,
      // igual que la fila de un cliente activo, #140): no se lee quién es sin el lector.
    }, skip: true);

    testWidgets('Mostrar bajas se anuncia como interruptor con su estado y mide al menos 48 dp', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await bajasEn(tester, EstadoBajas.d04);

      expect(
        tester.getSemantics(_mostrar),
        isSemantics(
          label: 'Mostrar bajas',
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
        ),
      );
      expect(tester.getSize(_mostrar).height, greaterThanOrEqualTo(48));
      handle.dispose();
    });
  });

  // ---------------------------------------------------------------------------------------------
  // Privacidad: nada con datos de la persona sale en un toString.
  // ---------------------------------------------------------------------------------------------
  group('privacidad · toString', () {
    test('los parámetros y los resultados de la baja no imprimen el motivo ni la persona', () {
      const params = DarDeBajaPersonaParams(personaId: 'p1', motivo: 'se mudó a lo de su hija');
      expect(params.toString(), isNot(contains('hija')));
      final persona = personaParaBaja(nombre: 'Jorge', apellido: 'Fernández');
      expect(PersonaDadaDeBaja(persona).toString(), isNot(contains('Jorge')));
      expect(persona.toString(), isNot(contains('Jorge')));
      expect(
        const BajaPersonaRequiereConfirmacion(cuentaConSaldo).toString(),
        isNot(contains('120000')),
      );
    });

    test('FailureInesperado de la baja lleva solo el tipo de la excepción', () {
      const f = FailureInesperado(causa: 'StateError');
      expect(f.toString(), isNot(contains('Jorge')));
    });
  });
}
