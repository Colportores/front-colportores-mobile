// QA de las vistas 03 «Alta de ubicación» y 04 «Duplicado en alta» (#193, HU-UBI-001 / HU-UBI-003).
//
// Complementa `alta_ubicacion_page_test.dart` con lo que quedaba sin cubrir: entradas con Ñ, acentos y
// emoji, texto de solo espacios o pegado con saltos de línea, el atrás del sistema en el paso de
// justificación (B·03) y las guías de accesibilidad en B·03 y a texto 2x. Las medidas de texto
// (solapes, textos cortados) están en `alta_ubicacion_qa_geometria_test.dart`, que usa las fuentes
// reales. Los tests con `skip` documentan un hallazgo de QA: el implementador les saca el `skip`
// cuando lo arregla.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:dartz/dartz.dart' show Left, Right;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart';

void main() {
  group('QA #193 · vista 03 · entradas de calle y número', () {
    testWidgets(
      'dado que escribe calle con Ñ, acentos y emoji, cuando registra, se guarda tal cual',
      (tester) async {
        final repo = RepoAltaFalso();
        await montarAlta(tester, repo: repo, geocodificador: GeocodificadorFalso());
        await tester.enterText(find.widgetWithText(TextField, 'Calle'), '  Núñez 🏠 Ñandú  ');
        await tester.enterText(find.widgetWithText(TextField, 'Nº'), '12-B');
        await tester.pump();
        await tocar(tester, find.text('Casa'));
        await tocar(tester, botonRegistrar);

        expect(tester.takeException(), isNull);
        final u = repo.llamadas.single.ubicacion;
        expect(u.calle, 'Núñez 🏠 Ñandú');
        expect(u.numero, '12-B');
      },
    );

    testWidgets(
      'dado que deja calle y número con solo espacios, cuando registra, se guardan vacíos',
      (tester) async {
        final repo = RepoAltaFalso();
        await montarAlta(tester, repo: repo, geocodificador: GeocodificadorFalso());
        await tester.enterText(find.widgetWithText(TextField, 'Calle'), '     ');
        await tester.enterText(find.widgetWithText(TextField, 'Nº'), '   ');
        await tester.pump();
        await tocar(tester, find.text('Casa'));
        await tocar(tester, botonRegistrar);

        final u = repo.llamadas.single.ubicacion;
        expect(u.calle, isNull);
        expect(u.numero, isNull);
      },
    );

    // QA #193: pegar una dirección en varias líneas no deja un `\r` suelto ni palabras pegadas. Los
    // saltos `\r\n` (pegado desde Windows) y los `\r` pasan a un espacio. Un `\n` solo lo descarta
    // antes el formateador propio de Flutter para campos de una línea y deja las palabras pegadas:
    // eso queda como pendiente de decisión (campo de varias líneas), no se prueba acá.
    testWidgets(
      'dado que pega un texto con saltos de línea `\\r\\n` en la calle, cuando registra, no llega '
      'ningún salto ni se pegan las palabras',
      (tester) async {
        final repo = RepoAltaFalso();
        await montarAlta(tester, repo: repo, geocodificador: GeocodificadorFalso());
        await tester.enterText(
          find.widgetWithText(TextField, 'Calle'),
          'Av. Italia\r\nesquina\rBlanes',
        );
        await tester.pump();
        await tocar(tester, find.text('Casa'));
        await tocar(tester, botonRegistrar);

        final calle = repo.llamadas.single.ubicacion.calle;
        expect(calle, isNotNull);
        expect(calle, isNot(contains('\r')));
        expect(calle, isNot(contains('Italiaesquina')));
        expect(calle, 'Av. Italia esquina Blanes');
      },
    );

    testWidgets('dado que tocó «Registrar» y falló, cuando vuelve a tocarlo, la calle y el número '
        'tipeados siguen y se reintenta con ellos', (tester) async {
      final repo = RepoAltaFalso();
      var intento = 0;
      repo.comportamiento = (u) async {
        intento++;
        if (intento == 1) return const Left(FailureInesperado());
        return Right(AltaRegistrada(ubicacion: u));
      };
      final salidas = await montarAlta(tester, repo: repo, geocodificador: GeocodificadorFalso());
      await tester.enterText(find.widgetWithText(TextField, 'Calle'), 'Ñandú');
      await tester.enterText(find.widgetWithText(TextField, 'Nº'), '7');
      await tester.pump();
      await tocar(tester, find.text('Casa'));

      await tocar(tester, botonRegistrar);
      expect(find.text(TextosAlta.noPudimosGuardar), findsOneWidget);
      expect(find.text('Ñandú'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      await tocar(tester, botonRegistrar);
      expect(repo.llamadas, hasLength(2));
      expect(repo.llamadas.last.ubicacion.calle, 'Ñandú');
      expect(salidas.single, isA<UbicacionCreada>());
    });
  });

  group('QA #193 · vista 04 · paso de justificación (B·03)', () {
    // Decisión del 05/10 (QA de #267): el atrás del sistema anda de a un paso, como el chevron «Volver».
    testWidgets(
      'dado que está en B·03, cuando usa el atrás del sistema, vuelve a las candidatas y conserva '
      'lo escrito; desde las candidatas el atrás cierra la hoja y el alta conserva todo sin '
      'registrar nada nuevo',
      (tester) async {
        final repo = await hastaJustificacion(tester);
        await tester.enterText(find.byType(TextField).last, 'Otra casa en la misma calle');
        await tester.pump();

        await tester.binding.handlePopRoute();
        await asentar(tester);

        expect(find.text('¿Por qué es otra ubicación?'), findsNothing);
        expect(find.text('Ya existe una ubicación a 12 m'), findsOneWidget);

        await tocar(tester, find.text('Crear igual'));
        expect(find.text('¿Por qué es otra ubicación?'), findsOneWidget);
        expect(find.text('Otra casa en la misma calle'), findsOneWidget, reason: 'se conserva');

        await tester.binding.handlePopRoute();
        await asentar(tester);
        expect(find.text('Ya existe una ubicación a 12 m'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await asentar(tester);

        expect(find.text('Ya existe una ubicación a 12 m'), findsNothing);
        expect(find.text('¿Por qué es otra ubicación?'), findsNothing);
        expect(find.text('Nueva ubicación'), findsOneWidget);
        expect(find.text('Av. Italia'), findsOneWidget);
        expect(repo.llamadas, hasLength(1));
      },
    );

    testWidgets(
      'dado que «Crear igual» está guardando, cuando usa el atrás del sistema, no pasa nada '
      'y la hoja sigue en B·03',
      (tester) async {
        final repo = await hastaJustificacion(tester);
        repo
          ..comportamiento = null
          ..bloqueo = Completer<void>();
        await tester.enterText(find.byType(TextField).last, 'Otra casa en la misma calle');
        await tester.pump();
        await tocar(tester, find.widgetWithText(FilledButton, 'Crear igual'));
        expect(repo.llamadas, hasLength(2), reason: 'el segundo registro está en curso');

        await tester.binding.handlePopRoute();
        await asentar(tester);

        expect(find.text('¿Por qué es otra ubicación?'), findsOneWidget);
        expect(find.text('Ya existe una ubicación a 12 m'), findsNothing);
        repo.bloqueo!.complete();
        await asentar(tester);
      },
    );

    testWidgets(
      'dado que escribe una justificación con Ñ, acentos y emoji, cuando toca «Crear igual», '
      'se registra la nueva con «seguir igual»',
      (tester) async {
        final repo = await hastaJustificacion(tester);
        await tester.enterText(find.byType(TextField).last, '  Otra puerta, Ñandú 🏠 del fondo  ');
        await tester.pump();
        await tocar(tester, find.widgetWithText(FilledButton, 'Crear igual'));

        expect(tester.takeException(), isNull);
        expect(repo.llamadas, hasLength(2));
        expect(repo.llamadas[1].duplicados?.esSeguirIgual, isTrue);
      },
    );

    for (final tamano in [const Size(360, 640), const Size(412, 915)]) {
      testWidgets(
        'B·03 cumple las guías de accesibilidad en ${tamano.width.toInt()}×${tamano.height.toInt()}',
        (tester) async {
          final handle = tester.ensureSemantics();
          await hastaJustificacion(tester, tamano: tamano);
          await tocar(tester, find.text('Local en planta baja'));

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        },
      );
    }

    testWidgets('B·03 a texto 2x en 360×640 no se desborda y cumple las guías', (tester) async {
      final handle = tester.ensureSemantics();
      await hastaJustificacion(tester, escala: 2, tamano: const Size(360, 640));

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  group('QA #193 · vista 03 · accesibilidad a texto 2x', () {
    testWidgets('en 360×640 y texto 2x: sin desborde y con las guías', (tester) async {
      final handle = tester.ensureSemantics();
      await montarAlta(tester, tamano: const Size(360, 640), escala: 2);

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets(
      'el aviso de falla al registrar se anuncia (liveRegion) y deja «Registrar» a mano',
      (tester) async {
        final handle = tester.ensureSemantics();
        final repo = RepoAltaFalso()..comportamiento = (_) async => const Left(FailureInesperado());
        await montarAlta(tester, repo: repo);
        await tocar(tester, find.text('Casa'));
        await tocar(tester, botonRegistrar);

        final anunciado = find
            .ancestor(
              of: find.text(TextosAlta.noPudimosGuardar),
              matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.liveRegion == true,
              ),
            )
            .evaluate()
            .isNotEmpty;
        expect(anunciado, isTrue);
        expect(tester.widget<FilledButton>(botonRegistrar).onPressed, isNotNull);
        expect(find.text(TextosAlta.registrar), findsOneWidget);
        handle.dispose();
      },
    );
  });
}
