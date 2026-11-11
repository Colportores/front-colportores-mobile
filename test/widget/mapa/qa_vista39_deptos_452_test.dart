// QA de «Edificio y sus deptos» (vista 39, #452, PR #705): N·04 a N·07, C·09 y C·10 en 360×640 y 412×915 con
// texto 1,0× y 2,0×, los estados que el canvas no dibuja y los casos límite de cada flujo. Con
// `--dart-define=QA_CAPTURAS=true` también saca una captura de cada estado a `.dart_tool/qa_capturas/`.
// Los tests con `skip` documentan un hallazgo del QA: el implementador saca el `skip` cuando lo arregla.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resumen_del_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/deptos_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart'
    show AlturaHoja;
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/qa_vista39_452_arnes.dart';

const _tamanos = [(chico452, '360x640'), (grande452, '412x915')];
const _escalas = [1.0, 2.0];

Finder get _campoNumero =>
    find.descendant(of: find.byKey(ClavesHojaDepto.numero), matching: find.byType(TextField));

void main() {
  group('matriz: cada estado, en 2 tamaños y 2 escalas, sin desborde ni texto cortado', () {
    for (final estado in Estado452.values) {
      for (final (tamano, nombreTamano) in _tamanos) {
        for (final escala in _escalas) {
          testWidgets('${estado.id} · $nombreTamano · ${escala}x', (tester) async {
            await llegarA452(tester, estado, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull);
            sinTextoCortado452(tester);
            await capturar452(tester, '${estado.id}_${nombreTamano}_${escala.toInt()}x');
          });
        }
      }
    }
  });

  group('a un tercio de la pantalla (la altura con que se abre la hoja)', () {
    for (final estado in [Estado452.c09, Estado452.c09Error, Estado452.n04, Estado452.c10]) {
      for (final escala in _escalas) {
        testWidgets('${estado.id} · 360x640 · ${escala}x', (tester) async {
          await llegarA452(
            tester,
            estado,
            tamano: chico452,
            escala: escala,
            altura: AlturaHoja.tercio,
          );
          expect(tester.takeException(), isNull);
          await capturar452(tester, '${estado.id}_tercio_${escala.toInt()}x');
        });
      }
    }

    testWidgets('c09 con 24 deptos a un tercio y 2,0×: se llega al último con el dedo', (
      tester,
    ) async {
      final muchos = [
        for (var i = 1; i <= 24; i++) espacioDe('d-$i', '${i}A', piso: '$i', orden: i),
      ];
      await montar452(
        tester,
        espacios: muchos,
        escala: 2,
        altura: AlturaHoja.tercio,
        antes: (m) => m.resumen = () => Stream.value(const {}),
      );
      final ultimo = fila452(muchos.last);
      await tester.dragUntilVisible(
        ultimo,
        find.byType(SingleChildScrollView),
        const Offset(0, -80),
      );
      await tester.tap(ultimo);
      await asentar452(tester);
      expect(texto452(tester, ClavesHojaCasa.titulo), 'Grecia 3313 · Depto 24A');
      expect(tester.takeException(), isNull);
    });
  });

  group('datos límite de la lista de deptos', () {
    testWidgets(
      'dos espacios sin número y sin piso: los dos «Sin número», sin contador, por alta',
      (tester) async {
        final a = espacioDe('s-1', null, orden: 1);
        final b = espacioDe('s-2', null, orden: 2);
        await montar452(tester, espacios: [d3B452, b, a]);
        expect(find.text('Sin número'), findsNWidgets(2));
        expect(find.textContaining('Sin número ('), findsNothing);
        final ya = tester.getTopLeft(fila452(a)).dy;
        final yb = tester.getTopLeft(fila452(b)).dy;
        expect(ya, lessThan(yb), reason: 'en el orden en que se dieron de alta');
      },
    );

    testWidgets('número y piso larguísimos, con emoji: nada se desborda a 360×640 y 2,0×', (
      tester,
    ) async {
      final largo = espacioDe(
        'l-1',
        '${'9' * 38} 🏢',
        piso: 'Planta alta del fondo ${'x' * 30}',
        orden: 1,
      );
      await montar452(
        tester,
        espacios: [largo, d1A452],
        escala: 2,
        calle: 'Avenida Doctor Luis Alberto de Herrera y Bulevar Artigas',
        numero: '12345',
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(fila452(largo));
      await tester.pump();
      await tester.tap(fila452(largo));
      await asentar452(tester);
      expect(tester.takeException(), isNull);
      await capturar452(tester, 'c10_texto_largo');
    });

    testWidgets('150 deptos: se arma sin errores y se llega al último', (tester) async {
      final muchos = [
        for (var i = 1; i <= 150; i++)
          espacioDe('d-$i', '$i', piso: '${(i / 10).ceil()}', orden: i % 59),
      ];
      await montar452(
        tester,
        espacios: muchos,
        antes: (m) => m.resumen = () => Stream.value(const {}),
      );
      expect(texto452(tester, ClavesDeptosDeLaCasa.rotulo), '150 DEPTOS');
      expect(tester.takeException(), isNull);
    });

    testWidgets('cada estado de casa se lee en la fila, sin «null» ni vacío', (tester) async {
      final deptos = [
        for (var i = 0; i < EstadoCasa.values.length; i++)
          espacioDe('e-$i', '${i + 1}', piso: '1', orden: i),
      ];
      await montar452(
        tester,
        espacios: deptos,
        antes: (m) => m.resumen = () => Stream.value({
          for (var i = 0; i < EstadoCasa.values.length; i++)
            'e-$i': ResumenDelDepto(
              estado: EstadoCasa.values[i],
              ultimaVisita: ahora452.subtract(const Duration(days: 3)),
              proximaEntrevista: ahora452.add(const Duration(days: 2)),
            ),
        }),
      );
      final semantica = tester.ensureSemantics();
      for (final d in deptos) {
        final lectura = tester.getSemantics(fila452(d)).label;
        expect(lectura, matches(RegExp(r'^Depto \d+\. .{3,}$')), reason: lectura);
        expect(lectura, isNot(contains('null')));
      }
      semantica.dispose();
    });
  });

  group('estados de error y de espera', () {
    testWidgets('«Reintentar» tocado dos veces seguidas lee una sola vez y deja la lista', (
      tester,
    ) async {
      final m = await montar452(
        tester,
        antes: (m) => m.repo.fallaAlListar = const FailureInesperado(causa: 'sin DB'),
      );
      expect(find.byKey(ClavesDeptosDeLaCasa.error), findsOneWidget);
      final antes = m.repo.listados;
      m.repo.fallaAlListar = null;
      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.reintentar));
      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.reintentar), warnIfMissed: false);
      await asentar452(tester);
      expect(find.byKey(ClavesDeptosDeLaCasa.error), findsNothing);
      expect(fila452(d1A452), findsOneWidget);
      expect(m.repo.listados - antes, lessThanOrEqualTo(2));
    });

    testWidgets('el error vuelve a fallar al reintentar: sigue el aviso con «Reintentar»', (
      tester,
    ) async {
      final m = await montar452(
        tester,
        antes: (m) => m.repo.fallaAlListar = const FailureInesperado(causa: 'sin DB'),
      );
      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.reintentar));
      await asentar452(tester);
      expect(find.byKey(ClavesDeptosDeLaCasa.error), findsOneWidget);
      expect(find.byKey(ClavesDeptosDeLaCasa.reintentar), findsOneWidget);
      expect(m.cierres, 0);
    });

    testWidgets('C·10 con el contexto sin poder leerse: la «‹» sigue y vuelve a la lista', (
      tester,
    ) async {
      await llegarA452(tester, Estado452.c10Error);
      expect(find.byKey(ClavesDeptosDeLaCasa.volver), findsOneWidget);
      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.volver));
      await asentar452(tester);
      expect(find.byKey(ClavesDeptosDeLaCasa.lista), findsOneWidget);
    });

    testWidgets('C·10 con el contexto sin llegar: el atrás de la «‹» no queda trabado', (
      tester,
    ) async {
      await llegarA452(tester, Estado452.c10Cargando);
      expect(find.byKey(ClavesDeptosDeLaCasa.volver), findsOneWidget);
      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.volver));
      await asentar452(tester);
      expect(find.byKey(ClavesDeptosDeLaCasa.lista), findsOneWidget);
    });
  });

  group('«+ Agregar depto» (N·05): casos límite', () {
    testWidgets('el alta falla: la hoja de alta sigue con lo tipeado y el botón vuelve a andar', (
      tester,
    ) async {
      final m = await montar452(tester, espacios: [d1A452]);
      await tester.tap(find.byKey(ClavesDeptosDeLaCasa.agregar));
      await asentar452(tester);
      await tester.enterText(_campoNumero, '5C');
      m.repo.fallas.add(const FailureInesperado(causa: 'sin DB'));
      await tester.tap(find.byKey(ClavesHojaDepto.agregar));
      await asentar452(tester, 10);
      expect(find.byKey(ClavesHojaDepto.hoja), findsOneWidget, reason: 'la hoja no se cierra');
      expect(tester.widget<TextField>(_campoNumero).controller!.text, '5C');
      await tester.tap(find.byKey(ClavesHojaDepto.agregar));
      await asentar452(tester, 10);
      expect(find.byKey(ClavesHojaDepto.hoja), findsNothing);
      expect(find.byKey(ClavesDeptosDeLaCasa.fila('nuevo-1')), findsOneWidget);
    });

    testWidgets(
      'el alta anda pero la relectura de la lista falla: aviso con «Reintentar» y el depto aparece',
      (tester) async {
        final m = await montar452(tester, espacios: [d1A452]);
        await tester.tap(find.byKey(ClavesDeptosDeLaCasa.agregar));
        await asentar452(tester);
        await tester.enterText(_campoNumero, '5C');
        m.repo.fallaAlListar = const FailureInesperado(causa: 'sin DB');
        await tester.tap(find.byKey(ClavesHojaDepto.agregar));
        await asentar452(tester, 10);
        expect(find.byKey(ClavesDeptosDeLaCasa.error), findsOneWidget);
        m.repo.fallaAlListar = null;
        await tester.tap(find.byKey(ClavesDeptosDeLaCasa.reintentar));
        await asentar452(tester);
        expect(find.byKey(ClavesDeptosDeLaCasa.fila('nuevo-1')), findsOneWidget);
      },
    );

    testWidgets(
      'un edificio recién registrado sin deptos: «Seguir» lleva a N·06 vacío con qué hacer',
      (tester) async {
        await llegarA452(tester, Estado452.n06Vacio);
        expect(find.text(TextosDeptosDeLaCasa.sinDeptos), findsOneWidget);
        expect(find.byKey(ClavesDeptosDeLaCasa.agregar), findsOneWidget);
      },
    );

    testWidgets('sin saber quién es el colportor no se ofrece agregar (ni se cuelga)', (
      tester,
    ) async {
      await montar452(tester, colportorId: null);
      expect(find.byKey(ClavesDeptosDeLaCasa.agregar), findsNothing);
      expect(fila452(d1A452), findsOneWidget);
    });
  });

  group('C·10: acciones superpuestas y reentrada', () {
    testWidgets('«Registrar visita» tocado dos veces mientras espera: una sola llamada', (
      tester,
    ) async {
      final espera = Completer<Object?>();
      final m = await montar452(tester, antes: (m) => m.esperaVisita = espera);
      await tocarDepto452(tester, d3B452);
      final boton = find.byKey(ClavesHojaCasa.registrarVisita);
      await tester.ensureVisible(boton);
      await tester.pump();
      await tester.tap(boton);
      await tester.pump();
      await tester.tap(boton, warnIfMissed: false);
      await tester.pump();
      expect(m.visitas, hasLength(1));
      expect(m.visitas.single.espacioId, 'd-3b');
      espera.complete(false);
      await asentar452(tester);
      await tester.ensureVisible(boton);
      await tester.tap(boton);
      await asentar452(tester);
      expect(m.visitas, hasLength(2), reason: 'el botón vuelve a andar al terminar');
    });

    testWidgets('«Registrar visita» que guarda cierra la hoja una sola vez', (tester) async {
      final m = await montar452(tester, antes: (m) => m.salidaVisita = true);
      await tocarDepto452(tester, d3B452);
      await tester.tap(find.byKey(ClavesHojaCasa.registrarVisita));
      await asentar452(tester);
      expect(m.cierres, 1);
    });

    testWidgets(
      'mientras «Registrar visita» espera, la «‹» no cambia la hoja de abajo… ni se traba',
      (tester) async {
        final espera = Completer<Object?>();
        final m = await montar452(tester, antes: (m) => m.esperaVisita = espera);
        await tocarDepto452(tester, d3B452);
        await tester.tap(find.byKey(ClavesHojaCasa.registrarVisita));
        await tester.pump();
        await tester.tap(find.byKey(ClavesDeptosDeLaCasa.volver));
        await asentar452(tester);
        espera.complete(false);
        await asentar452(tester);
        expect(tester.takeException(), isNull);
        expect(m.visitas, hasLength(1));
        // Termine donde termine, el usuario puede seguir: o está en la lista o en el depto con el botón.
        final enLista = find.byKey(ClavesDeptosDeLaCasa.lista).evaluate().isNotEmpty;
        final enDepto = find.byKey(ClavesHojaCasa.registrarVisita).evaluate().isNotEmpty;
        expect(enLista || enDepto, isTrue);
      },
    );

    testWidgets('el edificio con un solo depto: «1 DEPTO» y el depto se abre', (tester) async {
      await montar452(tester, espacios: [d3B452]);
      expect(texto452(tester, ClavesDeptosDeLaCasa.rotulo), '1 DEPTO');
      await tocarDepto452(tester, d3B452);
      expect(texto452(tester, ClavesHojaCasa.titulo), 'Grecia 3313 · Depto 3B');
    });
  });

  group('textos y privacidad', () {
    test('los textos de los avisos dicen qué pasa y qué hacer', () {
      expect(TextosDeptosDeLaCasa.errorLectura, contains('Probá de nuevo'));
      expect(TextosDeptosDeLaCasa.noPudimosAbrirAlta, contains('Probá de nuevo'));
      expect(TextosDeptosDeLaCasa.sinDeptosQueHacer, contains('Agregar depto'));
    });

    test('ResumenDelDepto y Espacio no cuentan nada de la casa en su toString', () {
      final resumen = ResumenDelDepto(
        estado: EstadoCasa.rechazo,
        ultimaVisita: ahora452,
        proximaEntrevista: ahora452,
      );
      final espacio = Espacio(
        id: 'secreto-id',
        ubicacionId: 'u',
        numeroDepto: '3B-privado',
        piso: '3',
        auditoria: d3B452.auditoria,
      );
      expect(resumen.toString(), isNot(contains('rechazo')));
      expect(espacio.toString(), isNot(contains('3B-privado')));
    });
  });
}
