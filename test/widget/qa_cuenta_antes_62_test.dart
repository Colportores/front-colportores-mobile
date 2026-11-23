// QA de #62 (PR #729) — HU-AUTH-008, «Cuenta antes» (decisión de Cristian, 23/10) y 18A·07 «Ya te
// asignaron» con la campaña y la zona reales. Lo que prueba el implementador (texto literal, doble
// toque, lectura que no contesta, volver y reentrar) no se repite: acá van las guías de accesibilidad,
// los tamaños, el día de Montevideo a la medianoche, «Hoy» con los otros avisos, el cambio de día con
// la pantalla abierta, la privacidad y las pantallas vecinas.
//
// Letra de `flutter_test` (sin las fuentes reales): las guías de contraste con la fuente real dan
// falsos negativos. Las capturas, con la fuente real, están en `qa_cuenta_antes_62_capturas_test.dart`.
import 'dart:async';

import 'package:colportores_mobile/features/auth/domain/services/situacion_de_campania.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/cuenta_asignada_page.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada_rechazada.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_cuenta_antes_62_arnes.dart';

const _textoVerano =
    'Tu campaña Verano 2027 empieza el 01/12. Hasta entonces podés bajar el mapa y las casas; '
    'la jornada y las ventas se habilitan ese día.';

void main() {
  group('Hoy con la campaña por empezar: guías de accesibilidad y tamaños', () {
    for (final (nombre, ancho, alto, escala) in tamanos) {
      testWidgets('aviso fijo · $nombre', (tester) async {
        final m = Mundo(campanias: [porEmpezar()]);
        await montarHoy(tester, m, ancho: ancho, alto: alto, escala: escala);

        expect(avisoFijo, findsOneWidget);
        expect(find.text(_textoVerano), findsOneWidget);
        await cumpleLasGuias(tester);
        sinTextoFueraDeLosCostados(tester, ancho);
      });

      testWidgets('aviso fijo + 3 jornadas rechazadas, nombre largo con emoji · $nombre', (
        tester,
      ) async {
        final nombreLargo = 'Gran campaña de verano de los colportores del sur ☀️ ' * 2;
        final m = Mundo(
          campanias: [porEmpezar(nombre: nombreLargo.trim())],
          rechazadas: [
            rechazada('j1', visitas: 40),
            rechazada('j2', visitas: 1, inicio: DateTime.utc(2026, 11, 18, 14)),
            rechazada('j3', inicio: DateTime.utc(2026, 11, 17, 14)),
          ],
        );
        await montarHoy(tester, m, ancho: ancho, alto: alto, escala: escala);

        expect(find.byKey(const Key('jornada_rechazada_j3')), findsOneWidget);
        await cumpleLasGuias(tester);
        sinTextoFueraDeLosCostados(tester, ancho);
        // «Iniciar jornada» sigue a un scroll de distancia y se puede tocar.
        await tocarIniciar(tester);
        // Con letra al 200 % el aviso de abajo no entra: la vista va al aviso fijo (ronda 1 de QA).
        expect(snack.evaluate().isNotEmpty || avisoFijo.evaluate().isNotEmpty, isTrue);
      });

      testWidgets('el aviso al tocar «Iniciar jornada» (✕, tamaño de toque, contraste) · $nombre', (
        tester,
      ) async {
        final m = Mundo(campanias: [porEmpezar()]);
        await montarHoy(tester, m, ancho: ancho, alto: alto, escala: escala);
        await tocarIniciar(tester);

        if (escala == 2) {
          // No entra abajo: la vista va al aviso fijo, que sigue a la vista y cumple las guías.
          expect(snack.evaluate().isNotEmpty || avisoFijo.evaluate().isNotEmpty, isTrue);
        } else {
          expect(snack, findsOneWidget);
          expect(find.descendant(of: snack, matching: find.byType(IconButton)), findsOneWidget);
        }
        await cumpleLasGuias(tester);
        sinTextoFueraDeLosCostados(tester, ancho);
      });
    }

    testWidgets('con una campaña en curso «Hoy» no ocupa lugar con avisos de campaña', (
      tester,
    ) async {
      final m = Mundo(campanias: [enCurso(), porEmpezar()]);
      await montarHoy(tester, m, ancho: 360, alto: 640, escala: 2);

      expect(avisoFijo, findsNothing);
      await cumpleLasGuias(tester);
    });
  });

  group('«Inicio» entero: el aviso convive con los otros avisos de «Hoy»', () {
    for (final (nombre, ancho, alto, escala) in tamanos) {
      testWidgets('aviso fijo en Inicio · $nombre', (tester) async {
        final m = Mundo(campanias: [porEmpezar()], rechazadas: [rechazada('j1', visitas: 3)]);
        await montarInicio(tester, m, ancho: ancho, alto: alto, escala: escala);

        expect(avisoFijo, findsOneWidget);
        await cumpleLasGuias(tester);
        sinTextoFueraDeLosCostados(tester, ancho);
      });

      // QA #62: con texto al 200 % en 360×640 el aviso flotante (8 renglones) no entra en «Inicio»: en
      // vez de repetirlo abajo, la vista va al aviso fijo de «Hoy». En los otros tamaños entra y no tapa
      // la barra.
      testWidgets(
        'el aviso al tocar «Iniciar jornada» entra en la pantalla y no tapa la barra · $nombre',
        (tester) async {
          final m = Mundo(campanias: [porEmpezar()]);
          await montarInicio(tester, m, ancho: ancho, alto: alto, escala: escala);
          await tocarIniciar(tester);

          expect(tester.takeException(), isNull, reason: 'el aviso flotante no entra en pantalla');
          final barra = tester.getRect(find.byKey(const Key('inicio_barra')));
          if (ancho == 360 && escala == 2) {
            expect(snack, findsNothing);
            expect(avisoFijo, findsOneWidget);
            final fijo = tester.getRect(avisoFijo);
            expect(fijo.top, greaterThanOrEqualTo(0));
            // El aviso fijo es más alto que la región (8+ renglones): se ve desde su primer renglón y se
            // sigue con el scroll.
            expect(fijo.top, lessThan(barra.top));
            expect(m.jornadas.jornadas, isEmpty);
            return;
          }
          expect(snack, findsOneWidget);
          final aviso = tester.getRect(snack);
          expect(aviso.top, greaterThanOrEqualTo(0));
          expect(aviso.bottom, lessThanOrEqualTo(barra.top + 0.5), reason: 'tapa la barra');
        },
      );
    }
  });

  group('el día de Montevideo a la medianoche (HU: «se habilitan ese día»)', () {
    testWidgets('00:30 UTC del 01/12 todavía es 30/11 en Montevideo: sigue frenando', (
      tester,
    ) async {
      final m = Mundo(campanias: [porEmpezar()])..ahora = DateTime.utc(2026, 12, 1, 0, 30);
      await montarHoy(tester, m);

      expect(avisoFijo, findsOneWidget);
      await tocarIniciar(tester);
      expect(m.jornadas.jornadas, isEmpty);
      expect(snack, findsOneWidget);
    });

    testWidgets('02:59 UTC del 01/12 (23:59 en Montevideo) todavía frena', (tester) async {
      final m = Mundo(campanias: [porEmpezar()])..ahora = DateTime.utc(2026, 12, 1, 2, 59);
      await montarHoy(tester, m);

      expect(avisoFijo, findsOneWidget);
      await tocarIniciar(tester);
      expect(m.jornadas.jornadas, isEmpty);
      expect(snack, findsOneWidget);
    });

    testWidgets('03:00 UTC del 01/12 (00:00 en Montevideo) ya no frena: se inicia la jornada', (
      tester,
    ) async {
      final m = Mundo(campanias: [porEmpezar()])..ahora = DateTime.utc(2026, 12, 1, 3);
      await montarHoy(tester, m);

      expect(avisoFijo, findsNothing);
      await tocarIniciar(tester);
      expect(m.jornadas.jornadas, hasLength(1));
      expect(snack, findsNothing);
    });

    testWidgets('el último día de la campaña en curso, la siguiente por empezar no frena', (
      tester,
    ) async {
      final m = Mundo(
        campanias: [
          enCurso(),
          porEmpezar(inicio: '2026-12-16'),
        ],
      )..ahora = DateTime.utc(2026, 12, 15, 20);
      await montarHoy(tester, m);

      expect(avisoFijo, findsNothing);
      await tocarIniciar(tester);
      expect(m.jornadas.jornadas, hasLength(1));
    });

    testWidgets('la campaña en curso termina hoy y la otra empieza mañana: mañana frena el hueco', (
      tester,
    ) async {
      // Hueco entre campañas: la en curso terminó ayer, la nueva empieza mañana. No hay campaña en
      // curso: la regla de la HU frena hasta que empiece la nueva.
      final m = Mundo(
        campanias: [
          enCurso(),
          porEmpezar(inicio: '2026-12-18'),
        ],
      )..ahora = DateTime.utc(2026, 12, 17, 15);
      await montarHoy(tester, m);

      expect(avisoFijo, findsOneWidget);
    });
  });

  group('con la pantalla abierta cuando cambia el día', () {
    testWidgets('pasa la medianoche del inicio de la campaña: el aviso fijo se actualiza solo', (
      tester,
    ) async {
      final m = Mundo(campanias: [porEmpezar()])..ahora = DateTime.utc(2026, 12, 1, 2, 50);
      await montarHoy(tester, m);
      expect(avisoFijo, findsOneWidget);

      // Pasan 15 minutos con «Hoy» abierto: ya es 01/12 en Montevideo y se puede iniciar.
      m.ahora = DateTime.utc(2026, 12, 1, 3, 5);
      await tester.pump(const Duration(minutes: 15));
      await asentar(tester);

      expect(
        avisoFijo,
        findsNothing,
        reason:
            'el aviso dice «empieza el 01/12» con el 01/12 ya empezado, hasta que algo reconstruya',
      );
    });
  });

  group('privacidad', () {
    test('toString de las entidades nuevas no imprime nombre de campaña ni zona', () {
      final campania = porEmpezar(nombre: 'Campaña Secreta', zona: 'Zona Norte', ciudad: 'Salto');
      final textos = [
        campania.toString(),
        CampaniaPorEmpezar(nombre: campania.nombre, fechaInicio: campania.fechaInicio).toString(),
        JornadaRechazada(id: 'j-privada', inicio: DateTime.utc(2026), visitas: 2).toString(),
        asignacionDe('Campaña Secreta', zona: 'Norte', ciudad: 'Salto').toString(),
      ];
      for (final t in textos) {
        expect(t, isNot(contains('Secreta')));
        expect(t, isNot(contains('Norte')));
        expect(t, isNot(contains('Salto')));
        expect(t, isNot(contains('j-privada')));
      }
    });
  });

  group('18A·07 «Ya te asignaron» con la campaña y la zona reales', () {
    for (final (nombre, ancho, alto, escala) in tamanos) {
      testWidgets('campaña y zona · $nombre', (tester) async {
        final m = Mundo()
          ..asignacion.asignacion = asignacionDe(
            'Campaña Primavera 2026',
            zona: 'Centro',
            ciudad: 'Montevideo',
          );
        await montarAsignada(tester, m, ancho: ancho, alto: alto, escala: escala);

        expect(find.text('Ya te asignaron'), findsOneWidget);
        expect(find.text('Campaña Primavera 2026'), findsOneWidget);
        expect(find.text('Zona Centro · Montevideo'), findsOneWidget);
        await cumpleLasGuias(tester);
        sinTextoFueraDeLosCostados(tester, ancho);
      });

      testWidgets('nombre larguísimo, zona sin ciudad · $nombre', (tester) async {
        final largo = 'Campaña de colportaje universitario de verano ${'muy larga ' * 8}'.trim();
        final m = Mundo()..asignacion.asignacion = asignacionDe(largo, zona: 'Ciudad Vieja');
        await montarAsignada(tester, m, ancho: ancho, alto: alto, escala: escala);

        expect(find.text(largo), findsOneWidget);
        expect(find.text('Zona Ciudad Vieja'), findsOneWidget);
        await cumpleLasGuias(tester);
        sinTextoFueraDeLosCostados(tester, ancho);
      });

      testWidgets('sin zona no se inventa el renglón de la zona · $nombre', (tester) async {
        final m = Mundo()..asignacion.asignacion = asignacionDe('Verano 2027');
        await montarAsignada(tester, m, ancho: ancho, alto: alto, escala: escala);

        expect(find.text('Verano 2027'), findsOneWidget);
        expect(find.byKey(const Key('asignada_zona')), findsNothing);
        await cumpleLasGuias(tester);
      });

      testWidgets('sin saber la asignación no se inventa nada · $nombre', (tester) async {
        final m = Mundo()..asignacion.asignacion = null;
        await montarAsignada(tester, m, ancho: ancho, alto: alto, escala: escala);

        expect(find.byKey(const Key('asignada_detalle')), findsNothing);
        expect(find.text('Ya te asignaron'), findsOneWidget);
        await cumpleLasGuias(tester);
      });
    }

    testWidgets('si la consulta falla la pantalla sale igual y pasa a la principal una sola vez', (
      tester,
    ) async {
      final m = Mundo()..asignacion.falla = StateError('sin base');
      var terminadas = 0;
      await montarAsignada(tester, m, alTerminar: () => terminadas++);

      expect(find.text('Ya te asignaron'), findsOneWidget);
      expect(find.byKey(const Key('asignada_detalle')), findsNothing);
      await tester.pump(CuentaAsignadaPage.duracion + const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      expect(terminadas, 1);
    });

    testWidgets('la consulta que tarda más que la barra: no cuelga ni avisa de más', (
      tester,
    ) async {
      final m = Mundo()..asignacion.demora = Completer<void>();
      var terminadas = 0;
      await montarAsignada(tester, m, alTerminar: () => terminadas++);
      await tester.pump(CuentaAsignadaPage.duracion + const Duration(milliseconds: 100));
      expect(terminadas, 1);

      m.asignacion.demora!.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(terminadas, 1);
    });
  });
}
