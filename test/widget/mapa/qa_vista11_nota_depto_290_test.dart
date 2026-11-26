// QA de la nota del depto (vista 11, «Nota del depto», 11N·01 a 11N·07, #290, PR #776): la hoja real
// de la casa (un edificio con deptos) con el enganche de `main.dart`. Lo que el PR no prueba con la
// hoja entera: los textos literales del canvas y de la HU, la validación del formulario en un depto, los
// casos límite de cada flujo, la lectura del lector de pantalla y que ninguno de los 21 estados desborde en
// 360×640 y 412×915 con texto 1,0× y 2,0× (con captura de cada uno con `--dart-define=QA_CAPTURAS=true`).
//
// Los hallazgos van con `skip:` («QA #290: …»); `--dart-define=QA_HALLAZGOS=true` los corre.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/deptos_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/fila_nota_del_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_notas_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_ubicacion_falsos.dart';
import '../../helpers/qa_vista11_nota_depto_290_arnes.dart';

const _tamanos = [t360x640, t412x915];
const _escalas = [1.0, 2.0];

/// Los textos que muestra la pantalla (los `Text`), sin los larguísimos.
List<String> _textos(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    if (t.data != null && t.data!.length < 200) t.data!,
];

Finder get _guardar => find.text('Guardar nota');

bool _habilitado(WidgetTester tester, Finder boton) {
  final b = find.ancestor(
    of: boton,
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  return tester.widget<ButtonStyleButton>(b.first).onPressed != null;
}

Future<void> _escribir(WidgetTester tester, String texto) async {
  await tester.enterText(find.byKey(ClavesNotas.campo), texto);
  await tester.pump();
}

SemanticsNode _nodoConTexto(WidgetTester tester, String texto) {
  final nodos = <SemanticsNode>[];
  void visitar(SemanticsNode n) {
    if (n.label.contains(texto)) nodos.add(n);
    n.visitChildren((h) {
      visitar(h);
      return true;
    });
  }

  visitar(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  expect(nodos, isNotEmpty, reason: 'no hay un nodo de semántica con «$texto»');
  return nodos.last;
}

void main() {
  const hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

  group('textos literales del canvas 11N y de la HU (HU-UBI-007)', () {
    testWidgets(
      'dado un depto sin nota, la hoja dice «+ Agregar una nota» y el ejemplo del canvas, arriba de '
      'las personas',
      (tester) async {
        await llegarA290(tester, Estado290.sinNota);

        expect(find.text('+ Agregar una nota'), findsOneWidget);
        expect(find.text('Por ejemplo, «timbre roto, tocar fuerte»'), findsOneWidget);
      },
    );

    testWidgets('dado un depto con nota, la hoja dice «NOTA DEL DEPTO», el texto y «Editar»', (
      tester,
    ) async {
      await llegarA290(tester, Estado290.conNota);

      expect(find.text('NOTA DEL DEPTO'), findsOneWidget);
      expect(find.text(textoCanvas290), findsOneWidget);
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('+ Agregar una nota'), findsNothing);
    });

    testWidgets(
      'el error al guardar dice lo del canvas 11N·07 y ofrece «Reintentar» y «Cancelar»',
      (tester) async {
        await llegarA290(tester, Estado290.formularioError);

        expect(find.text('No pudimos guardar la nota. El texto sigue acá.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text,
          textoCanvas290,
        );
        expect(find.byTooltip('Cerrar'), findsOneWidget, reason: 'la salida del formulario');
      },
    );

    testWidgets('el formulario de un depto dice que la nota queda solo en el teléfono', (
      tester,
    ) async {
      await llegarA290(tester, Estado290.formularioNuevo);

      // Texto del aviso de las notas (decisión de Cristian del 23/10); el canvas dice «Esta nota queda
      // solo en tu teléfono.» (P3 del archivo de pendientes, a confirmar).
      expect(find.text('Estas notas viven solo en tu celular.'), findsOneWidget);
    });
  });

  group('validación de entradas del formulario de la nota del depto', () {
    testWidgets(
      'dado un campo vacío o solo espacios, no guarda, avisa qué hacer y el texto queda',
      (tester) async {
        final m = await llegarA290(tester, Estado290.formularioNuevo);

        await tester.tap(_guardar);
        await asentarLugar(tester);
        expect(_textos(tester), contains('Escribí la nota para poder guardarla.'));

        await _escribir(tester, '   \n  ');
        await tester.tap(_guardar);
        await asentarLugar(tester);

        expect(_textos(tester), contains('Escribí la nota para poder guardarla.'));
        expect(m.notasDeptos.llamadas, isEmpty);
        expect(
          find.byKey(ClavesNotas.campo),
          findsOneWidget,
          reason: 'el formulario sigue abierto',
        );
      },
    );

    testWidgets('dado texto con espacios alrededor, guarda el texto sin ellos', (tester) async {
      final m = await llegarA290(tester, Estado290.formularioNuevo);

      await _escribir(tester, '   timbre roto   ');
      await tester.tap(_guardar);
      await asentarLugar(tester);

      expect(m.notasDeptos.notas.single.texto, 'timbre roto');
    });

    testWidgets('dado emoji, tildes, eñes y símbolos, se guardan intactos y se ven en la fila', (
      tester,
    ) async {
      final m = await llegarA290(tester, Estado290.formularioNuevo);
      const texto = 'Ñandú 😀👍🏽 «timbre» <b>&amp;</b> 100% \$ \\n ç';

      await _escribir(tester, texto);
      await tester.tap(_guardar);
      await asentarLugar(tester);

      expect(m.notasDeptos.notas.single.texto, texto);
      expect(find.text(texto), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'dado texto pegado de 6000 caracteres, avisa el límite blando y deja guardar la nota entera',
      (tester) async {
        final m = await llegarA290(tester, Estado290.formularioNotaLarga);

        expect(
          _textos(tester),
          contains(
            'La nota tiene 6000 caracteres y lo recomendado es hasta 5000. Podés guardarla igual.',
          ),
        );
        await tester.tap(_guardar);
        await asentarLugar(tester);

        expect(m.notasDeptos.notas.single.texto, hasLength(6000), reason: 'sin cortar lo pegado');
        expect(find.byKey(ClavesNotas.campo), findsNothing);
      },
    );

    testWidgets(
      'dado un depto con nota, cuando borro todo el texto y guardo, la nota queda como estaba',
      (tester) async {
        final m = await llegarA290(tester, Estado290.formularioEditar);
        expect(
          tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text,
          textoCanvas290,
        );

        await _escribir(tester, '');
        await tester.tap(_guardar);
        await asentarLugar(tester);

        expect(m.notasDeptos.notas.single.texto, textoCanvas290);
        expect(_textos(tester), contains('Escribí la nota para poder guardarla.'));
      },
    );

    testWidgets('dado un guardado lento, un segundo toque en «Guardar nota» no lo repite', (
      tester,
    ) async {
      final repo = _RepoLento();
      final m = await montarHoja290(tester, notasDeptos: repo);
      await tester.tap(find.byKey(ClavesNotaDelDepto.agregar));
      await asentarLugar(tester);

      await _escribir(tester, 'una sola');
      await tester.tap(_guardar);
      await tester.pump();
      // Mientras guarda, el botón ya no dice «Guardar nota» ni deja tocar de nuevo.
      for (final boton in find.byWidgetPredicate((w) => w is ButtonStyleButton).evaluate()) {
        final b = boton.widget as ButtonStyleButton;
        if (b.onPressed != null) await tester.tap(find.byWidget(b), warnIfMissed: false);
      }
      await tester.pump();
      repo.liberar();
      await asentarLugar(tester);

      expect(m.notasDeptos.llamadas.where((l) => l.startsWith('agregar')), hasLength(1));
    });
  });

  group('casos límite de los flujos', () {
    testWidgets(
      'dado que guardar falla dos veces seguidas, el texto sigue, el botón se habilita cada vez y '
      'al tercero guarda una sola nota',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso()
          ..resultados['agregar'] = [
            const FailureInesperado(causa: 'x'),
            const FailureInesperado(causa: 'y'),
          ];
        await montarHoja290(tester, notasDeptos: repo);
        await tester.tap(find.byKey(ClavesNotaDelDepto.agregar));
        await asentarLugar(tester);
        await _escribir(tester, 'Esta se guarda al tercer intento');

        for (var i = 0; i < 2; i++) {
          await tester.tap(find.text(i == 0 ? 'Guardar nota' : 'Reintentar'));
          await asentarLugar(tester);
          expect(
            find.text('No pudimos guardar la nota. El texto sigue acá.'),
            findsOneWidget,
            reason: 'falla $i',
          );
          expect(_habilitado(tester, find.text('Reintentar')), isTrue);
        }
        await tester.tap(find.text('Reintentar'));
        await asentarLugar(tester);

        expect(repo.notas, hasLength(1));
        expect(find.text('NOTA DEL DEPTO'), findsOneWidget);
        expect(find.text('Esta se guarda al tercer intento'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que borro la nota más nueva desde la pestaña, «Deshacer» la trae de vuelta en su lugar',
      (tester) async {
        final m = await llegarA290(tester, Estado290.pestanaAvisoBorrada);
        expect(find.text('Deshacer'), findsOneWidget);
        expect(m.notasDeptos.notas.firstWhere((n) => n.id == 'c1').estaBorrada, isTrue);

        await tester.tap(find.text('Deshacer'));
        await asentarLugar(tester);

        expect(m.notasDeptos.notas.firstWhere((n) => n.id == 'c1').estaBorrada, isFalse);
        expect(find.byKey(ClavesNotasDelLugar.nota('c1')), findsOneWidget);
        expect(find.text('Deshacer'), findsNothing);
      },
    );

    testWidgets(
      'dado que borro todas las notas desde la pestaña, la pestaña dice que no hay y ofrece '
      '«+ Nota del depto»; «Ver borradas» las lista para restaurar',
      (tester) async {
        final m = await llegarA290(tester, Estado290.pestanaConNotas);
        await borrarPorMenu290(tester, 'c1');
        await borrarPorMenu290(tester, 'c2');
        await borrarPorMenu290(tester, 'c3');
        expect(m.notasDeptos.notas.where((n) => !n.estaBorrada), isEmpty);

        expect(_textos(tester), contains('+ Nota del depto'));
        expect(find.byKey(ClavesNotasDelLugar.verBorradas), findsOneWidget);
        await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.verBorradas));
        await tester.tap(find.byKey(ClavesNotasDelLugar.verBorradas));
        await asentarLugar(tester);
        expect(find.text('Mejor después de las 18.'), findsOneWidget);
      },
    );

    testWidgets(
      'dado la hoja a 1/2 con dos notas, «Editar» abre la más nueva y al guardar la fila muestra el '
      'texto nuevo',
      (tester) async {
        await montarHoja290(
          tester,
          notas: [
            notaDeDepto('n1', 'la más nueva', creada: DateTime(2026, 10, 22, 14)),
            notaDeDepto('n2', 'la vieja', creada: DateTime(2026, 10, 1)),
          ],
        );
        await tester.tap(find.byKey(ClavesNotaDelDepto.editar));
        await asentarLugar(tester);
        expect(
          tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text,
          'la más nueva',
        );

        await _escribir(tester, 'la más nueva, corregida');
        await tester.tap(_guardar);
        await asentarLugar(tester);

        expect(find.text('la más nueva, corregida'), findsOneWidget);
        expect(find.text('la vieja'), findsNothing);
      },
    );

    testWidgets(
      'dado que borrar falla, la nota sigue en la pestaña y el aviso ofrece «Reintentar» (no queda '
      'ningún estado trabado)',
      (tester) async {
        final m = await llegarA290(tester, Estado290.pestanaAvisoFalla);

        expect(m.notasDeptos.notas.single.estaBorrada, isFalse);
        expect(find.text('Reintentar'), findsWidgets);
      },
    );

    testWidgets('dado un depto de baja con nota, la ve pero no hay «Editar» ni «+ Agregar»', (
      tester,
    ) async {
      await llegarA290(tester, Estado290.deBajaConNota);
      expect(find.text(textoCanvas290), findsOneWidget);
      expect(find.byKey(ClavesNotaDelDepto.editar), findsNothing);
      expect(find.byKey(ClavesNotaDelDepto.agregar), findsNothing);
    });

    testWidgets('dado un depto de baja sin nota, la hoja no dibuja la fila de la nota', (
      tester,
    ) async {
      await llegarA290(tester, Estado290.deBajaSinNota);
      expect(find.byKey(ClavesNotaDelDepto.fila), findsNothing);
      expect(find.byKey(ClavesNotaDelDepto.agregar), findsNothing);
    });

    testWidgets('dado que voy y vuelvo entre deptos, cada depto muestra solo su nota', (
      tester,
    ) async {
      await montarHoja290(
        tester,
        notas: [
          notaDeDepto('a', 'del 3B'),
          notaDeDepto('b', 'del 1A', duenio: depto1A),
        ],
      );
      expect(find.text('del 3B'), findsOneWidget);
      expect(find.text('del 1A'), findsNothing);

      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.volver));
      await asentarLugar(tester);
      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.fila(depto1A)));
      await asentarLugar(tester);

      expect(find.text('del 1A'), findsOneWidget);
      expect(find.text('del 3B'), findsNothing);
    });

    testWidgets('dado que la nota llegó de otro dueño (el edificio), el depto no la muestra', (
      tester,
    ) async {
      await montarHoja290(
        tester,
        notasEdificio: NotaUbicacionRepositorioFalso(
          notas: [notaDeDepto('e', 'perro en el patio', duenio: ubicacion290)],
        ),
      );
      expect(find.text('perro en el patio'), findsNothing);
      expect(find.text('+ Agregar una nota'), findsOneWidget);
    });

    testWidgets(
      'dado un depto con nota y la lista C·09, la fila dice «✎» y el principio de la nota',
      (tester) async {
        await llegarA290(tester, Estado290.listaConNota);

        expect(find.byKey(ClavesDeptosDeLaCasa.nota(depto3B)), findsOneWidget);
        expect(find.text('✎ $textoCanvas290'), findsOneWidget);
        expect(find.byKey(ClavesDeptosDeLaCasa.nota(depto1A)), findsNothing);
      },
    );

    testWidgets(
      'QA #290: dado un depto con una nota de 5000 caracteres, el lector de la lista no lee la nota entera',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await llegarA290(tester, Estado290.listaConNotaLarga);

        final largo = tester
            .getSemantics(find.byKey(ClavesDeptosDeLaCasa.fila(depto1A)))
            .label
            .length;
        expect(
          largo,
          lessThan(400),
          reason: 'la fila ve una línea; el lector de pantalla lee $largo caracteres de nota',
        );
        semantica.dispose();
      },
      // QA #290: la fila de la lista de deptos le dice al lector la nota entera aunque se ve una línea.
      skip: !hallazgos,
    );
  });

  group('aviso del límite blando de 5000 caracteres', () {
    for (final tamano in _tamanos) {
      testWidgets(
        'QA #290: dado texto pegado de 6000 caracteres en ${tamano.width.toInt()}×${tamano.height.toInt()}, '
        'el aviso del límite se ve (no queda tapado por «Guardar nota»)',
        (tester) async {
          await llegarA290(tester, Estado290.formularioNotaLarga, tamano: tamano);

          final aviso = find.textContaining('La nota tiene 6000 caracteres');
          expect(aviso, findsOneWidget);
          final tope = tester.getTopLeft(_guardar).dy;
          final pantalla = tester.view.physicalSize.height;
          expect(tester.getBottomLeft(aviso).dy, lessThanOrEqualTo(tope));
          expect(tester.getTopLeft(aviso).dy, lessThan(pantalla));
        },
        // QA #290: en el formulario compartido de las notas, el campo largo empuja el aviso bajo el botón.
        skip: !hallazgos,
      );
    }
  });

  group('lector de pantalla', () {
    testWidgets('los avisos de error de la nota se anuncian (región viva)', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegarA290(tester, Estado290.formularioError);

      final nodo = _nodoConTexto(tester, 'No pudimos guardar la nota');
      // ignore: deprecated_member_use
      expect(nodo.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
      semantica.dispose();
    });

    testWidgets('el error al leer las notas del depto se anuncia y tiene «Reintentar»', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await llegarA290(tester, Estado290.errorAlLeer);

      final nodo = _nodoConTexto(tester, 'No pudimos leer las notas del depto');
      // ignore: deprecated_member_use
      expect(nodo.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
      expect(find.byKey(ClavesNotaDelDepto.reintentar), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('la fila con nota le dice al lector «NOTA DEL DEPTO» y el texto entero', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await llegarA290(tester, Estado290.notaLarga);

      final nodo = _nodoConTexto(tester, 'NOTA DEL DEPTO');
      expect(nodo.label, contains(textoLargoCanvas290));
      semantica.dispose();
    });

    testWidgets('«+ Agregar una nota» es un botón con su ejemplo para el lector', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegarA290(tester, Estado290.sinNota);

      final nodo = _nodoConTexto(tester, '+ Agregar una nota');
      expect(nodo.label, contains('timbre roto, tocar fuerte'));
      // ignore: deprecated_member_use
      expect(nodo.hasFlag(SemanticsFlag.isButton), isTrue);
      semantica.dispose();
    });
  });

  group('tamaños: sin overflow en los 21 estados', () {
    for (final estado in Estado290.values) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          testWidgets('${estado.name} · ${sufijo290(tamano, escala)}', (tester) async {
            await cargarFuentes205(tester);
            await llegarA290(tester, estado, tamano: tamano, escala: escala);
            await tester.pump(const Duration(milliseconds: 100));

            expect(tester.takeException(), isNull);
            await capturar290(tester, '${estado.name}_${sufijo290(tamano, escala)}');
          });
        }
      }
    }
  });
}

/// Un repositorio cuyo `agregar` espera a que el test lo libere (guardado lento).
final class _RepoLento extends NotaUbicacionRepositorioFalso {
  final _espera = Completer<void>();

  void liberar() => _espera.complete();

  @override
  Future<Either<Failure, NotaUbicacion>> agregar(NotaUbicacion nota) async {
    await _espera.future;
    return super.agregar(nota);
  }
}
