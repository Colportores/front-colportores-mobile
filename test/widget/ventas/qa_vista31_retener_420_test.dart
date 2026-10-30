// QA de #420 (PR #597): la «Decisión de Cristian (23/10), Debo cliente» sobre la vista 31 «Devolución»:
// «Lo retengo» (la salida que no devuelve plata) va primera y elegida; «Se lo devuelvo ahora» y «Se lo
// devuelvo después» quedan debajo, a un toque. Cubre el orden, la elección por defecto (también para el
// lector), registrar sin tocar nada, la hoja de confirmar, el id de reintento, el cambio de monto, la
// falla a mitad, las acciones superpuestas y los tamaños. Reusa el arnés de #161
// (`qa_vista31_devolucion_161_arnes.dart`). Las capturas van a `.dart_tool/qa_capturas/` con
// `--dart-define=QA_CAPTURAS=true` (nunca se commitean); los hallazgos con `skip` se corren con
// `--dart-define=QA_HALLAZGOS=true`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/piezas_venta.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista31_devolucion_161_arnes.dart';
import '../../helpers/venta_ui_falsos.dart';

String _m(int centavos) => FormatoVenta.monto(centavos);

Finder _opcion(String nombre) => find.byKey(Key('devolucion_opcion_$nombre'));

/// Si la fila está elegida. La lista es perezosa: trae la fila a la vista antes de leerla.
Future<bool> _elegida(WidgetTester tester, String nombre) async {
  await verVisible(tester, _opcion(nombre));
  return tester.widget<FilaElegible>(_opcion(nombre)).elegida;
}

/// Dónde está la fila contando desde el principio de la lista (no desde la pantalla).
Future<double> _yEnLaLista(WidgetTester tester, String nombre) async {
  await verVisible(tester, _opcion(nombre));
  final pagina = find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable));
  final desplazado = tester.state<ScrollableState>(pagina.first).position.pixels;
  return tester.getTopLeft(_opcion(nombre)).dy + desplazado;
}

/// Lleva el formulario a «Seguir» con «Nuestros Hijos» elegido (la venta del canvas, pagó todo: sobran
/// $ 1.900).
Future<Montaje161> _hastaSeguir(
  WidgetTester tester,
  RepoFalso161 repo, {
  Size tamano = chico161,
  double escala = 1,
}) async {
  final m = await montar161(tester, repo, tamano: tamano, escala: escala);
  await tocar(tester, mas161('Nuestros Hijos'));
  await tocar(tester, cta161);
  return m;
}

Future<void> _volverDeLaHoja(WidgetTester tester) async {
  await tocar(tester, cta161);
  expect(find.text('¿Registrar la devolución?'), findsOneWidget);
}

void main() {
  const tamanos = {'360x640': chico161, '412x915': grande161};

  group('Orden y elección por defecto (decisión del 23/10)', () {
    for (final t in tamanos.entries) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets(
          '${t.key} ×$escala: «Lo retengo» primera, después «ahora» y «después»; solo la primera elegida',
          (tester) async {
            await _hastaSeguir(
              tester,
              RepoFalso161(ventaCanvas161()),
              tamano: t.value,
              escala: escala,
            );
            final y = [
              for (final o in const ['retener', 'devolverAhora', 'devolverDespues'])
                await _yEnLaLista(tester, o),
            ];
            expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: 'orden en pantalla: $y');
            expect(await _elegida(tester, 'retener'), isTrue);
            expect(await _elegida(tester, 'devolverAhora'), isFalse);
            expect(await _elegida(tester, 'devolverDespues'), isFalse);
            expect(boton161(tester).onPressed, isNotNull);
            expect(find.text('Elegí qué hacés con la diferencia.'), findsNothing);
            expect(tester.takeException(), isNull);
            sinTextoCortado161(tester);
            await capturar161(tester, '420_retengo_${t.key}_x${escala.toInt()}');
          },
        );
      }
    }

    testWidgets('textos literales de las tres filas y del rótulo, sin la nota vieja', (
      tester,
    ) async {
      await _hastaSeguir(tester, RepoFalso161(ventaCanvas161()));
      expect(find.text('¿QUÉ HACÉS CON ${_m(190000)}?'), findsOneWidget);
      expect(find.text('Lo retengo'), findsOneWidget);
      expect(find.text('Como compensación; el saldo queda en cero'), findsOneWidget);
      expect(find.text('Se lo devuelvo ahora'), findsOneWidget);
      expect(find.text('Se resta de tu dinero en mano'), findsOneWidget);
      expect(find.text('Se lo devuelvo después'), findsOneWidget);
      expect(find.text('Queda como «Debo al cliente»'), findsOneWidget);
      expect(find.text('Registrar devolución'), findsOneWidget);
    });

    testWidgets('para el lector: «Lo retengo» seleccionada y las otras dos no, en un solo grupo', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _hastaSeguir(tester, RepoFalso161(ventaCanvas161()));
      for (final (nombre, sel) in const [
        ('retener', true),
        ('devolverAhora', false),
        ('devolverDespues', false),
      ]) {
        expect(
          tester.getSemantics(_opcion(nombre)),
          isSemantics(isButton: true, isSelected: sel, isInMutuallyExclusiveGroup: true),
          reason: nombre,
        );
      }
      semantica.dispose();
    });

    testWidgets('al tocar «ahora» la selección pasa de fila, también para el lector', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _hastaSeguir(tester, RepoFalso161(ventaCanvas161()));
      await tocar(tester, _opcion('devolverAhora'));
      expect(await _elegida(tester, 'devolverAhora'), isTrue);
      expect(await _elegida(tester, 'retener'), isFalse);
      expect(
        tester.getSemantics(_opcion('devolverAhora')),
        isSemantics(isButton: true, isSelected: true, isInMutuallyExclusiveGroup: true),
      );
      expect(
        tester.getSemantics(_opcion('retener')),
        isSemantics(isButton: true, isSelected: false, isInMutuallyExclusiveGroup: true),
      );
      semantica.dispose();
    });

    testWidgets('se puede volver a «Lo retengo» después de tocar «después»', (tester) async {
      await _hastaSeguir(tester, RepoFalso161(ventaCanvas161()));
      await tocar(tester, _opcion('devolverDespues'));
      expect(await _elegida(tester, 'devolverDespues'), isTrue);
      await tocar(tester, _opcion('retener'));
      expect(await _elegida(tester, 'retener'), isTrue);
      expect(await _elegida(tester, 'devolverDespues'), isFalse);
    });

    testWidgets('tocar la fila ya elegida no la apaga (sigue habiendo una elegida)', (
      tester,
    ) async {
      await _hastaSeguir(tester, RepoFalso161(ventaCanvas161()));
      await tocar(tester, _opcion('retener'));
      await tocar(tester, _opcion('retener'));
      expect(await _elegida(tester, 'retener'), isTrue);
      expect(boton161(tester).onPressed, isNotNull);
    });
  });

  group('Registrar: lo que sale es lo que se ve', () {
    testWidgets(
      'sin tocar las opciones: la hoja dice «Retenés \$ 1.900» y el pedido lleva retener',
      (tester) async {
        final repo = RepoFalso161(ventaCanvas161());
        await _hastaSeguir(tester, repo);
        await tocar(tester, cta161);
        expect(find.text('¿Registrar la devolución?'), findsOneWidget);
        expect(find.text('Retenés'), findsOneWidget);
        expect(find.text(_m(190000)), findsWidgets);
        expect(find.text('Debo al cliente'), findsNothing);
        expect(find.text('Le devolvés ahora'), findsNothing);
        await tocar(tester, find.byKey(const Key('devolucion_hoja_registrar')));

        expect(repo.pedidos, hasLength(1));
        expect(repo.pedidos.single.queHacer, QueHacerConLaDiferencia.retener);
        expect(repo.pedidos.single.unidadesPorRenglon, {'i-hijos': 1});
        expect(find.text('Devolución registrada'), findsOneWidget);
        expect(find.text('Debo al cliente'), findsNothing);
        expect(find.byKey(const Key('devolucion_agendar')), findsNothing);
      },
    );

    testWidgets('«ahora»: la hoja dice «Le devolvés ahora» y el pedido lleva devolverAhora', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      await _hastaSeguir(tester, repo);
      await tocar(tester, _opcion('devolverAhora'));
      await tocar(tester, cta161);
      expect(find.text('Le devolvés ahora'), findsOneWidget);
      expect(find.text('Retenés'), findsNothing);
      await tocar(tester, find.byKey(const Key('devolucion_hoja_registrar')));
      expect(repo.pedidos.single.queHacer, QueHacerConLaDiferencia.devolverAhora);
    });

    testWidgets(
      '«después»: la hoja dice «Debo al cliente», el pedido devolverDespues y ofrece agendar',
      (tester) async {
        final repo = RepoFalso161(ventaCanvas161());
        await _hastaSeguir(tester, repo);
        await tocar(tester, _opcion('devolverDespues'));
        await tocar(tester, cta161);
        expect(find.text('Debo al cliente'), findsOneWidget);
        await tocar(tester, find.byKey(const Key('devolucion_hoja_registrar')));
        expect(repo.pedidos.single.queHacer, QueHacerConLaDiferencia.devolverDespues);
        expect(find.byKey(const Key('devolucion_agendar')), findsOneWidget);
      },
    );

    testWidgets('«Volver» de la hoja no cambia la salida; reabrir y registrar sigue reteniendo', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      await _hastaSeguir(tester, repo);
      await _volverDeLaHoja(tester);
      await tocar(tester, find.byKey(const Key('devolucion_hoja_volver')));
      expect(find.text('¿Registrar la devolución?'), findsNothing);
      expect(repo.pedidos, isEmpty);
      expect(await _elegida(tester, 'retener'), isTrue);
      await confirmarEnLaHoja161(tester);
      expect(repo.pedidos.single.queHacer, QueHacerConLaDiferencia.retener);
    });

    testWidgets(
      'devolución total con la venta pagada: rige «Lo retengo» (el canvas 31-07 dibujaba «ahora»)',
      (tester) async {
        final repo = RepoFalso161(ventaCanvas161());
        await montar161(tester, repo);
        await tocar(tester, mas161('Salud y Hogar'));
        await tocar(tester, mas161('Nuestros Hijos'));
        await tocar(tester, cta161);
        expect(find.text('¿QUÉ HACÉS CON ${_m(450000)}?'), findsOneWidget);
        expect(await _elegida(tester, 'retener'), isTrue);
        expect(await _elegida(tester, 'devolverAhora'), isFalse);
        await confirmarEnLaHoja161(tester);
        expect(repo.pedidos.single.queHacer, QueHacerConLaDiferencia.retener);
        expect(find.text('Registramos la devolución de toda la venta.'), findsOneWidget);
      },
    );

    testWidgets('si no pagó de más no hay opciones y el pedido no lleva salida', (tester) async {
      final repo = RepoFalso161(ventaCanvas161(cobrado: 100000));
      await montar161(tester, repo);
      await tocar(tester, mas161('Nuestros Hijos'));
      await tocar(tester, cta161);
      expect(find.byKey(const Key('devolucion_opciones')), findsNothing);
      expect(boton161(tester).onPressed, isNotNull);
      await confirmarEnLaHoja161(tester);
      expect(repo.pedidos.single.queHacer, isNull);
    });
  });

  group('Cambio de monto y de etapa', () {
    testWidgets(
      '«después» elegida y después sube el monto: vuelve «Lo retengo» y registra retener por el monto nuevo',
      (tester) async {
        final repo = RepoFalso161(ventaCanvas161());
        await _hastaSeguir(tester, repo);
        await tocar(tester, _opcion('devolverDespues'));
        await alPrincipio161(tester);
        await tocar(tester, mas161('Salud y Hogar'));
        expect(find.text('¿QUÉ HACÉS CON ${_m(450000)}?'), findsOneWidget);
        expect(await _elegida(tester, 'retener'), isTrue);
        expect(await _elegida(tester, 'devolverDespues'), isFalse);
        await tocar(tester, cta161);
        expect(find.text('Retenés'), findsOneWidget);
        await tocar(tester, find.byKey(const Key('devolucion_hoja_registrar')));
        expect(repo.pedidos.single.queHacer, QueHacerConLaDiferencia.retener);
        expect(repo.pedidos.single.unidadesPorRenglon, {'i-salud': 1, 'i-hijos': 1});
      },
    );

    testWidgets('vaciar las filas y volver a elegir no arrastra la salida de antes', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      await _hastaSeguir(tester, repo);
      await tocar(tester, _opcion('devolverAhora'));
      await alPrincipio161(tester);
      await tocar(tester, menos161('Nuestros Hijos'));
      expect(find.byKey(const Key('devolucion_opciones')), findsNothing);
      expect(boton161(tester).onPressed, isNull);
      await tocar(tester, mas161('Nuestros Hijos'));
      await tocar(tester, cta161);
      expect(await _elegida(tester, 'retener'), isTrue);
      expect(await _elegida(tester, 'devolverAhora'), isFalse);
    });

    testWidgets(
      'el monto a decidir sube y baja con los libros: cada cambio vuelve a «Lo retengo»',
      (tester) async {
        // Tres libros iguales de \$ 500 pagados enteros, se devuelven de a uno.
        final venta = ventaCanvas161(
          cobrado: 150000,
          renglones: [renglon161('l', 'Libro', cantidad: 3, precio: 50000)],
        );
        final repo = RepoFalso161(venta);
        await montar161(tester, repo);
        await tocar(tester, mas161('Libro'));
        await tocar(tester, cta161);
        expect(find.text('¿QUÉ HACÉS CON ${_m(50000)}?'), findsOneWidget);
        await tocar(tester, _opcion('devolverAhora'));
        await alPrincipio161(tester);
        await tocar(tester, mas161('Libro'));
        expect(find.text('¿QUÉ HACÉS CON ${_m(100000)}?'), findsOneWidget);
        expect(await _elegida(tester, 'retener'), isTrue);
        await alPrincipio161(tester);
        await tocar(tester, menos161('Libro'));
        expect(find.text('¿QUÉ HACÉS CON ${_m(50000)}?'), findsOneWidget);
        expect(await _elegida(tester, 'retener'), isTrue);
      },
    );
  });

  group('Casos límite del flujo', () {
    testWidgets(
      'falla a mitad con la salida por defecto: «Reintentar» conserva la elección y el id',
      (tester) async {
        final repo = RepoFalso161(ventaCanvas161());
        repo.respuestas.add(() async => const Left(FailureDevolucionNoGuardada(causa: 'prueba')));
        final m = await _hastaSeguir(tester, repo);
        await escribir(tester, motivo161, 'Quiso otro título');
        await confirmarEnLaHoja161(tester);

        expect(find.text('Reintentar'), findsOneWidget);
        expect(boton161(tester).onPressed, isNotNull, reason: 'el botón no queda trabado');
        expect(await _elegida(tester, 'retener'), isTrue);
        expect(tester.widget<TextField>(motivo161).controller!.text, 'Quiso otro título');

        await tocar(tester, find.text('Reintentar'));
        expect(repo.pedidos, hasLength(2));
        expect(repo.pedidos[0].id, repo.pedidos[1].id, reason: 'mismos datos, mismo id');
        expect(repo.pedidos[1].queHacer, QueHacerConLaDiferencia.retener);
        expect(m.ids, ['d-1']);
        expect(find.text('Devolución registrada'), findsOneWidget);
      },
    );

    testWidgets('después de la falla se puede cambiar la salida: es otro pedido con otro id', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      repo.respuestas.add(() async => const Left(FailureDevolucionNoGuardada(causa: 'prueba')));
      final m = await _hastaSeguir(tester, repo);
      await confirmarEnLaHoja161(tester);
      expect(find.text('Reintentar'), findsOneWidget);

      await tocar(tester, _opcion('devolverAhora'));
      expect(await _elegida(tester, 'devolverAhora'), isTrue);
      expect(find.text('Reintentar'), findsOneWidget);
      await tocar(tester, cta161); // tras una falla, «Reintentar» registra sin volver a preguntar

      expect(repo.pedidos, hasLength(2));
      expect(repo.pedidos[0].queHacer, QueHacerConLaDiferencia.retener);
      expect(repo.pedidos[1].queHacer, QueHacerConLaDiferencia.devolverAhora);
      expect(repo.pedidos[1].id, isNot(repo.pedidos[0].id));
      expect(m.ids, ['d-1', 'd-2']);
    });

    testWidgets(
      'falla, prueba otra salida, falla, vuelve a «Lo retengo»: cada cambio de datos cambia el id',
      (tester) async {
        final repo = RepoFalso161(ventaCanvas161());
        repo.respuestas
          ..add(() async => const Left(FailureDevolucionNoGuardada(causa: 'uno')))
          ..add(() async => const Left(FailureDevolucionNoGuardada(causa: 'dos')));
        await _hastaSeguir(tester, repo);
        await confirmarEnLaHoja161(tester); // retener (falla)
        await tocar(tester, _opcion('devolverDespues'));
        await tocar(tester, cta161); // después (falla)
        await tocar(tester, _opcion('retener'));
        await tocar(tester, cta161); // retener otra vez (bien)

        expect(repo.pedidos.map((p) => p.queHacer), [
          QueHacerConLaDiferencia.retener,
          QueHacerConLaDiferencia.devolverDespues,
          QueHacerConLaDiferencia.retener,
        ]);
        expect(find.text('Devolución registrada'), findsOneWidget);
        expect(
          repo.pedidos.map((p) => p.id).toSet(),
          hasLength(3),
          reason: 'cada cambio de datos, otro id',
        );
      },
    );

    testWidgets(
      'mientras registra: segundo toque no duplica, las opciones no cambian y el botón dice «Registrando…»',
      (tester) async {
        final repo = RepoFalso161(ventaCanvas161());
        final compuerta = Completer<Either<Failure, DevolucionRegistrada>>();
        repo.respuestas.add(() => compuerta.future);
        await _hastaSeguir(tester, repo);
        await confirmarEnLaHoja161(tester);
        expect(repo.pedidos, hasLength(1));
        expect(find.text('Registrando…'), findsOneWidget);
        expect(boton161(tester).onPressed, isNull);

        // Segundo toque al botón y toque a otra opción mientras guarda.
        await tester.tap(cta161.first, warnIfMissed: false);
        await tester.pump();
        await tester.tap(_opcion('devolverAhora').first, warnIfMissed: false);
        await tester.pump();
        expect(repo.pedidos, hasLength(1));
        expect(
          await _elegida(tester, 'retener'),
          isTrue,
          reason: 'no cambia la salida en pleno guardado',
        );
        expect(await _elegida(tester, 'devolverAhora'), isFalse);

        compuerta.complete(Right(repo.registrada(repo.pedidos.single)));
        await asentar(tester);
        expect(find.text('Devolución registrada'), findsOneWidget);
        expect(repo.pedidos, hasLength(1));
      },
    );

    testWidgets(
      'falla con el motivo recién escrito: el aviso rojo queda a la vista (no se scrollea de vuelta al campo)',
      (tester) async {
        // Con el campo «Motivo» enfocado, al cerrar la hoja el foco vuelve al campo y la lista baja hasta él:
        // el aviso «No pudimos registrar la devolución. No cambió nada.» (arriba del formulario) queda
        // fuera de vista y solo se ve que el botón dice «Reintentar». Viene de #589, no del delta de #597.
        final repo = RepoFalso161(ventaCanvas161());
        repo.respuestas.add(() async => const Left(FailureDevolucionNoGuardada(causa: 'prueba')));
        await _hastaSeguir(tester, repo);
        await escribir(tester, motivo161, 'Quiso otro título');
        await confirmarEnLaHoja161(tester);
        await tester.pump(const Duration(seconds: 1));
        final aviso = find.text('No pudimos registrar la devolución. No cambió nada.');
        expect(aviso, findsOneWidget);
        expect(tester.getTopLeft(aviso).dy, greaterThanOrEqualTo(0));
      },
      // skip: QA #420 — con el motivo enfocado el aviso rojo de la falla queda fuera de vista (de #589).
      skip: !conHallazgos161,
    );

    testWidgets(
      'mientras registra, el lector no anuncia las opciones como tocables que no hacen nada',
      (tester) async {
        // Las filas se apagan en pleno guardado (alElegir == null) pero el nodo semántico conserva su
        // acción de tocar: el lector las ofrece y el toque no hace nada. Hallazgo menor.
        final semantica = tester.ensureSemantics();
        final repo = RepoFalso161(ventaCanvas161());
        final compuerta = Completer<Either<Failure, DevolucionRegistrada>>();
        repo.respuestas.add(() => compuerta.future);
        addTearDown(() {
          if (!compuerta.isCompleted) compuerta.complete(const Left(FailureDevolucionNoGuardada()));
        });
        await _hastaSeguir(tester, repo);
        await confirmarEnLaHoja161(tester);
        final datos = tester.getSemantics(_opcion('devolverAhora')).getSemanticsData();
        expect(
          datos.hasAction(SemanticsAction.tap),
          isFalse,
          reason: 'en pleno guardado la fila no cambia nada, pero el lector la ofrece con «tocar»',
        );
        semantica.dispose();
      },
      // skip: QA #420 — en pleno guardado las filas siguen ofreciendo «tocar» al lector (de #589).
      skip: !conHallazgos161,
    );

    testWidgets(
      'reentrada: salir de la pantalla y volver a abrirla empieza otra vez en «Lo retengo»',
      (tester) async {
        final repo = RepoFalso161(ventaCanvas161());
        final m = await _hastaSeguir(tester, repo);
        await tocar(tester, _opcion('devolverDespues'));
        await tester.binding.handlePopRoute();
        await asentar(tester);
        expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
        await tocar(tester, find.text('Descartar'));
        expect(find.byKey(const Key('devolucion_opciones')), findsNothing);
        expect(m.resultados, hasLength(1));

        await tocar(tester, find.byKey(const Key('abrir')));
        await tocar(tester, mas161('Nuestros Hijos'));
        await tocar(tester, cta161);
        expect(await _elegida(tester, 'retener'), isTrue);
        expect(await _elegida(tester, 'devolverDespues'), isFalse);
        expect(repo.pedidos, isEmpty);
      },
    );

    testWidgets('rotación 412×915 → 360×640 con «ahora» elegida conserva la elección', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      await _hastaSeguir(tester, repo, tamano: grande161);
      await tocar(tester, _opcion('devolverAhora'));
      tester.view.physicalSize = chico161;
      await asentar(tester);
      expect(await _elegida(tester, 'devolverAhora'), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('Capturas de lo que cambia (31-02 y 31-03)', () {
    for (final t in tamanos.entries) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets('31-02 «Lo retengo» y 31-03 «ahora» · ${t.key} · ×$escala', (tester) async {
          await llegar161(tester, Estado161.a02PagoDeMas, tamano: t.value, escala: escala);
          expect(await _elegida(tester, 'retener'), isTrue);
          await capturar161(tester, '420_31-02_${t.key}_x${escala.toInt()}');
          await tocar(tester, _opcion('devolverAhora'));
          expect(await _elegida(tester, 'devolverAhora'), isTrue);
          expect(tester.takeException(), isNull);
          sinTextoCortado161(tester);
          await capturar161(tester, '420_31-03_${t.key}_x${escala.toInt()}');
          await tocar(tester, cta161);
          await capturar161(tester, '420_31-04_ahora_${t.key}_x${escala.toInt()}');
        });
      }
    }
  });
}
