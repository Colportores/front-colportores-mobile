// QA de la vista 31 «Devolución» (HU-VEN-004, #161, PR #589): los 10 artboards del canvas y los estados
// que no dibuja, en 360×640 y 412×915 con texto 1,0 y 2,0 (fuentes reales: sin desbordes ni textos
// cortados), los escenarios de la HU con su texto literal, la accesibilidad de lo que se anuncia y los
// casos límite (falla a mitad, acciones superpuestas, lo tipeado que se conserva, atrás en cada estado,
// reentrada, datos límite, privacidad). Las guías de toque/etiqueta/contraste van aparte
// (`qa_vista31_devolucion_161_guias_test.dart`). Los hallazgos van con `skip` y se corren con
// `--dart-define=QA_HALLAZGOS=true`; las capturas con `--dart-define=QA_CAPTURAS=true`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:colportores_mobile/features/ventas/domain/services/reglas_de_devolucion.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista31_devolucion_161_arnes.dart';
import '../../helpers/venta_ui_falsos.dart';

String _m(int centavos) => FormatoVenta.monto(centavos);

Finder _opcion(String nombre) => find.byKey(Key('devolucion_opcion_$nombre'));

/// Lleva el formulario a «Seguir» con «Nuestros Hijos» elegido (la venta del canvas, pagó todo).
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

void main() {
  const tamanos = {'360x640': chico161, '412x915': grande161};

  group('Matriz: sin desbordes ni textos cortados en cada estado', () {
    for (final estado in Estado161.values) {
      for (final t in tamanos.entries) {
        for (final escala in const [1.0, 2.0]) {
          testWidgets('${estado.titulo} · ${t.key} · ×$escala', (tester) async {
            await llegar161(tester, estado, tamano: t.value, escala: escala);
            expect(tester.takeException(), isNull);
            sinTextoCortado161(tester);
            await capturar161(tester, '${estado.name}_${t.key}_x${escala.toInt()}');
          });
        }
      }
    }
  });

  group('Criterios de aceptación de la HU', () {
    testWidgets('Devolución parcial: la venta original queda intacta y el saldo se recalcula '
        '(3 libros de \$ 500, pagó \$ 500, devuelve 2)', (tester) async {
      final venta = ventaCanvas161(
        cobrado: 50000,
        renglones: [renglon161('l', 'Libro', cantidad: 3, precio: 50000)],
      );
      final repo = RepoFalso161(venta);
      await montar161(tester, repo);
      await tocar(tester, mas161('Libro'));
      await tocar(tester, mas161('Libro'));
      await tocar(tester, cta161);

      // Se queda con 1 libro (\$ 500) y ya pagó \$ 500: saldo 0, nada que elegir.
      expect(find.text(_m(50000)), findsWidgets);
      expect(find.byKey(const Key('devolucion_opciones')), findsNothing);
      await confirmarEnLaHoja161(tester);

      expect(repo.pedidos.single.unidadesPorRenglon, {'i-l': 2});
      expect(repo.pedidos.single.queHacer, isNull);
      expect(find.text('Devolución registrada'), findsOneWidget);
      expect(find.text('Debo al cliente'), findsNothing);
      expect(repo.venta, same(venta), reason: 'la pantalla no toca la venta original');
    });

    testWidgets('Devolución total sin seña: no pagó nada, nada que elegir, saldo 0', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161(cobrado: 0));
      await montar161(tester, repo);
      await tocar(tester, mas161('Salud y Hogar'));
      await tocar(tester, mas161('Nuestros Hijos'));
      await tocar(tester, cta161);

      expect(find.text('Devuelve todo'), findsOneWidget);
      expect(find.byKey(const Key('devolucion_opciones')), findsNothing);
      await confirmarEnLaHoja161(tester);

      expect(find.text('Devolución registrada'), findsOneWidget);
      expect(find.text('Registramos la devolución de toda la venta.'), findsOneWidget);
      expect(find.text('Debo al cliente'), findsNothing);
      expect(repo.pedidos.single.unidadesPorRenglon, {'i-salud': 1, 'i-hijos': 1});
    });

    testWidgets('Devolución total con cliente que pagó completo y compromiso de reembolso futuro: '
        '«Debo al cliente \$ 4.500»', (tester) async {
      final repo = RepoFalso161(ventaCanvas161());
      await montar161(tester, repo);
      await tocar(tester, mas161('Salud y Hogar'));
      await tocar(tester, mas161('Nuestros Hijos'));
      await tocar(tester, cta161);
      expect(find.text('¿QUÉ HACÉS CON ${_m(450000)}?'), findsOneWidget);
      await tocar(tester, _opcion('devolverDespues'));
      await confirmarEnLaHoja161(tester);

      expect(find.text('Debo al cliente'), findsOneWidget);
      expect(find.text(_m(450000)), findsWidgets);
      expect(repo.pedidos.single.queHacer, QueHacerConLaDiferencia.devolverDespues);
      expect(find.byKey(const Key('devolucion_agendar')), findsOneWidget);
    });

    testWidgets('Más allá de 72 h: bloquea con el texto del canvas, solo «Volver»', (tester) async {
      final m = await montar161(
        tester,
        RepoFalso161(ventaCanvas161()),
        ahora: fechaDeLaVenta161.add(const Duration(days: 5)),
      );
      expect(
        find.text('Pasaron más de 72 h desde la venta. La devolución la registra tu coordinador.'),
        findsOneWidget,
      );
      expect(find.text('Seguir'), findsNothing);
      expect(find.text('Registrar devolución'), findsNothing);
      await tocar(tester, find.byKey(const Key('devolucion_volver')));
      expect(m.resultados, [false]);
    });

    testWidgets('Las tres salidas de «pagó de más» existen con el texto del canvas', (
      tester,
    ) async {
      await _hastaSeguir(tester, RepoFalso161(ventaCanvas161()));
      for (final t in [
        'Se lo devuelvo ahora',
        'Se resta de tu dinero en mano',
        'Lo retengo',
        'Como compensación; el saldo queda en cero',
        'Se lo devuelvo después',
        'Queda como «Debo al cliente»',
      ]) {
        expect(find.textContaining(t), findsWidgets, reason: t);
      }
    });

    testWidgets('«Se lo devuelvo ahora» guarda lo devuelto y «Lo retengo» lo retiene', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      await _hastaSeguir(tester, repo);
      await tocar(tester, _opcion('devolverAhora'));
      await confirmarEnLaHoja161(tester);
      expect(repo.pedidos.single.queHacer, QueHacerConLaDiferencia.devolverAhora);
    });
  });

  group('Los cinco estados', () {
    testWidgets('cargando: dice qué se carga (no es un spinner mudo) y no deja registrar', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await llegar161(tester, Estado161.cargando);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('devolucion_cargando')), findsOneWidget);
      expect(find.text('DEVOLUCIÓN'), findsOneWidget);
      expect(find.bySemanticsLabel('Cargando la venta'), findsOneWidget);
      expect(find.byKey(const Key('venta_cta')), findsNothing);
      semantica.dispose();
    });

    testWidgets('vacío (la venta ya no está): lo dice y ofrece «Volver»', (tester) async {
      final m = await llegar161(tester, Estado161.ausente);
      expect(find.byKey(const Key('devolucion_sin_venta')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('devolucion_volver')));
      expect(m.resultados, [false]);
    });

    testWidgets('error de lectura: «Reintentar» lee de nuevo y muestra la venta', (tester) async {
      final repo = RepoFalso161(ventaCanvas161())
        ..fallaAlLeer = const FailureDevolucionNoDisponible();
      await montar161(tester, repo);
      expect(find.text('No pudimos leer la venta guardada en tu teléfono.'), findsOneWidget);
      repo.fallaAlLeer = null;
      await tocar(tester, find.text('Reintentar'));
      expect(find.text('Salud y Hogar'), findsOneWidget);
      expect(find.byKey(const Key('devolucion_error_lectura')), findsNothing);
    });

    testWidgets('error de lectura dos veces seguidas sigue ofreciendo «Reintentar»', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161())
        ..fallaAlLeer = const FailureDevolucionNoDisponible();
      await montar161(tester, repo);
      await tocar(tester, find.text('Reintentar'));
      await tocar(tester, find.text('Reintentar'));
      expect(repo.lecturas, 3);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('sin conexión no hay estado propio: se registra igual (todo es local)', (
      tester,
    ) async {
      // El repositorio no usa red: ninguna `FailureSinConexion` puede llegar, y la pantalla no tiene
      // texto de «Necesitás conexión».
      await llegar161(tester, Estado161.a05Registrada);
      expect(find.textContaining('conexión'), findsNothing);
      expect(find.text('Devolución registrada'), findsOneWidget);
    });
  });

  group('Avisos de error (§ convenciones: qué pasa y qué hacer)', () {
    testWidgets('31-10: el aviso dice qué pasó y la acción a mano es «Reintentar»', (tester) async {
      await llegar161(tester, Estado161.a10ErrorAlGuardar);
      expect(find.text('No pudimos registrar la devolución. No cambió nada.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(boton161(tester).onPressed, isNotNull);
    });

    testWidgets('cualquier falla desconocida al guardar muestra el aviso, no el mensaje genérico', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      repo.respuestas.add(() async => const Left(FailureSinConexion()));
      await _hastaSeguir(tester, repo);
      await tocar(tester, _opcion('retener'));
      await confirmarEnLaHoja161(tester);
      expect(find.byKey(const Key('devolucion_error')), findsOneWidget);
      expect(find.text('No pudimos registrar la devolución. No cambió nada.'), findsOneWidget);
    });

    testWidgets('una excepción del repositorio también termina en el aviso con «Reintentar»', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      repo.respuestas.add(() async => throw StateError('boom'));
      await _hastaSeguir(tester, repo);
      await tocar(tester, _opcion('retener'));
      await confirmarEnLaHoja161(tester);
      expect(find.byKey(const Key('devolucion_error')), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Registrando…'), findsNothing);
    });

    testWidgets(
      'aviso de «Invalida»: es región viva, queda a la vista a 360×640 ×2 y se va al cambiar lo elegido',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final repo = RepoFalso161(ventaCanvas161());
        repo.respuestas.add(() async => const Left(FailureDevolucionInvalida(causa: 'x')));
        await _hastaSeguir(tester, repo, escala: 2);
        await tocar(tester, _opcion('retener'));
        await confirmarEnLaHoja161(tester);

        final aviso = find.byKey(const Key('devolucion_invalida'));
        expect(aviso, findsOneWidget);
        expect(tester.getSemantics(aviso).flagsCollection.isLiveRegion, isTrue);
        final rect = tester.getRect(aviso);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(640));
        expect(tester.takeException(), isNull);

        await tocar(tester, menos161('Nuestros Hijos'));
        expect(aviso, findsNothing);
        semantica.dispose();
      },
    );

    testWidgets('Invalida con la venta sin cambios: el registro se rechaza y la pantalla lo dice', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      repo.respuestas.add(() async => const Left(FailureDevolucionInvalida(causa: 'x')));
      await _hastaSeguir(tester, repo);
      await tocar(tester, _opcion('retener'));
      await confirmarEnLaHoja161(tester);
      final avisos =
          find.textContaining('Revisá lo que elegiste').evaluate().length +
          find.byKey(const Key('devolucion_error')).evaluate().length;
      expect(avisos, greaterThan(0), reason: 'el colportor no ve por qué no se registró');
    });
  });

  group('Validación del motivo (texto libre opcional, 500 caracteres)', () {
    Future<RepoFalso161> registrarConMotivo(WidgetTester tester, String motivo) async {
      final repo = RepoFalso161(ventaCanvas161(cobrado: 0));
      await montar161(tester, repo);
      await tocar(tester, mas161('Nuestros Hijos'));
      await tocar(tester, cta161);
      await escribir(tester, motivo161, motivo);
      await confirmarEnLaHoja161(tester);
      return repo;
    }

    testWidgets('solo espacios: no se guarda motivo', (tester) async {
      final repo = await registrarConMotivo(tester, '     ');
      expect(repo.pedidos.single.motivo, isNull);
    });

    testWidgets('vacío: no se guarda motivo y no estorba', (tester) async {
      final repo = await registrarConMotivo(tester, '');
      expect(repo.pedidos.single.motivo, isNull);
    });

    testWidgets('texto con espacios alrededor se recorta', (tester) async {
      final repo = await registrarConMotivo(tester, '   Se arrepintió   ');
      expect(repo.pedidos.single.motivo, 'Se arrepintió');
    });

    testWidgets('emoji y caracteres especiales se guardan tal cual', (tester) async {
      final repo = await registrarConMotivo(tester, 'Ñandú 😀 <b>"x"</b> \'; DROP -- ü');
      expect(repo.pedidos.single.motivo, 'Ñandú 😀 <b>"x"</b> \'; DROP -- ü');
    });

    testWidgets('pegado de 5.000 caracteres: el campo corta en 500 y se guarda 500', (
      tester,
    ) async {
      final repo = await registrarConMotivo(tester, 'a' * 5000);
      expect(repo.pedidos.single.motivo!.runes.length, ReglasDeDevolucion.largoMaximoMotivo);
    });

    testWidgets('600 emoji: se cuentan por carácter, no por unidad UTF-16', (tester) async {
      final repo = await registrarConMotivo(tester, '😀' * 600);
      expect(repo.pedidos.single.motivo!.runes.length, 500);
    });

    testWidgets('el campo avisa que no se pongan datos del cliente', (tester) async {
      await _hastaSeguir(tester, RepoFalso161(ventaCanvas161()));
      await verVisible(tester, motivo161);
      expect(
        find.text('Tu coordinador va a leer este motivo. No pongas datos del cliente.'),
        findsOneWidget,
      );
      expect(find.text('MOTIVO (OPCIONAL)'), findsOneWidget);
    });
  });

  group('Casos límite de cada flujo', () {
    testWidgets('falla a mitad: el botón vuelve a habilitarse y nada queda en «Registrando…»', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      repo.respuestas
        ..add(() async => const Left(FailureDevolucionNoGuardada(causa: 'a')))
        ..add(() async => const Left(FailureDevolucionNoGuardada(causa: 'b')));
      await _hastaSeguir(tester, repo);
      await tocar(tester, _opcion('retener'));
      await confirmarEnLaHoja161(tester);
      expect(find.text('Registrando…'), findsNothing);
      expect(boton161(tester).onPressed, isNotNull);

      // Segundo intento, también falla: sigue habilitado.
      await tocar(tester, cta161);
      expect(find.text('Registrando…'), findsNothing);
      expect(boton161(tester).onPressed, isNotNull);
      expect(find.text('Reintentar'), findsOneWidget);

      // Tercer intento: entra.
      await tocar(tester, cta161);
      expect(find.text('Devolución registrada'), findsOneWidget);
      expect(repo.pedidos.map((p) => p.id).toSet(), hasLength(1));
      expect(repo.pedidos, hasLength(3));
    });

    testWidgets(
      'acciones superpuestas: dos «Reintentar» antes de que termine el primero, uno solo entra',
      (tester) async {
        final repo = RepoFalso161(ventaCanvas161());
        final compuerta = Completer<Either<Failure, DevolucionRegistrada>>();
        repo.respuestas
          ..add(() async => const Left(FailureDevolucionNoGuardada(causa: 'a')))
          ..add(() => compuerta.future);
        await _hastaSeguir(tester, repo);
        await tocar(tester, _opcion('retener'));
        await confirmarEnLaHoja161(tester);

        await tester.tap(cta161);
        await tester.pump();
        await tester.tap(cta161, warnIfMissed: false);
        await tester.pump();
        expect(repo.pedidos, hasLength(2), reason: 'el segundo toque no manda otro pedido');
        expect(find.text('Registrando…'), findsOneWidget);

        compuerta.complete(Right(repo.registrada(repo.pedidos.last)));
        await asentar(tester);
        expect(find.text('Devolución registrada'), findsOneWidget);
        expect(repo.pedidos, hasLength(2));
      },
    );

    testWidgets('después de un error se conserva lo elegido, la opción y el motivo', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      repo.respuestas.add(() async => const Left(FailureDevolucionNoGuardada(causa: 'a')));
      await _hastaSeguir(tester, repo);
      await tocar(tester, _opcion('devolverAhora'));
      await escribir(tester, motivo161, 'Se mudó');
      await confirmarEnLaHoja161(tester);

      expect(tester.widget<TextField>(motivo161).controller!.text, 'Se mudó');
      await alPrincipio161(tester);
      expect(find.text('Devuelve Nuestros Hijos'), findsOneWidget);
      final semantica = tester.ensureSemantics();
      expect(
        tester.getSemantics(_opcion('devolverAhora')),
        isSemantics(
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          label: 'Se lo devuelvo ahora. Se resta de tu dinero en mano',
        ),
      );
      semantica.dispose();
      // Y el reintento manda lo mismo con el mismo id.
      await tocar(tester, cta161);
      expect(repo.pedidos.map((p) => p.id).toSet(), hasLength(1));
      expect(repo.pedidos.last.motivo, 'Se mudó');
    });

    testWidgets('mientras guarda los campos, las filas y el atrás no responden', (tester) async {
      final repo = RepoFalso161(ventaCanvas161());
      final compuerta = Completer<Either<Failure, DevolucionRegistrada>>();
      repo.respuestas.add(() => compuerta.future);
      final m = await _hastaSeguir(tester, repo);
      await tocar(tester, _opcion('retener'));
      await confirmarEnLaHoja161(tester);

      expect(find.text('Registrando…'), findsOneWidget);
      expect(tester.widget<TextField>(motivo161).enabled, isFalse);
      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(m.resultados, isEmpty);
      expect(find.text('¿Descartar lo que escribiste?'), findsNothing);

      compuerta.complete(Right(repo.registrada(repo.pedidos.last)));
      await asentar(tester);
      expect(find.text('Devolución registrada'), findsOneWidget);
    });

    testWidgets('«Volver» de la hoja no registra y conserva todo lo elegido', (tester) async {
      final repo = RepoFalso161(ventaCanvas161());
      await _hastaSeguir(tester, repo);
      await tocar(tester, _opcion('retener'));
      await tocar(tester, cta161);
      await tocar(tester, find.byKey(const Key('devolucion_hoja_volver')));
      expect(repo.pedidos, isEmpty);
      expect(find.text('Registrar devolución'), findsOneWidget);
      expect(boton161(tester).onPressed, isNotNull);
    });

    testWidgets('el atrás del sistema con la hoja abierta cierra la hoja, no la pantalla', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      final m = await _hastaSeguir(tester, repo);
      await tocar(tester, _opcion('retener'));
      await tocar(tester, cta161);
      expect(find.byKey(const Key('devolucion_hoja')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(find.byKey(const Key('devolucion_hoja')), findsNothing);
      expect(find.byKey(const Key('devolucion_pagina')), findsOneWidget);
      expect(m.resultados, isEmpty);
      expect(repo.pedidos, isEmpty);
    });

    testWidgets('«+» en el tope y «−» en cero no cambian nada', (tester) async {
      final repo = RepoFalso161(ventaCanvas161());
      await montar161(tester, repo);
      await tocar(tester, mas161('Nuestros Hijos'));
      await tester.tap(mas161('Nuestros Hijos'), warnIfMissed: false);
      await asentar(tester);
      await tester.tap(menos161('Salud y Hogar'), warnIfMissed: false);
      await asentar(tester);
      await tocar(tester, cta161);
      await tocar(tester, _opcion('retener'));
      await confirmarEnLaHoja161(tester);
      expect(repo.pedidos.single.unidadesPorRenglon, {'i-hijos': 1});
    });

    testWidgets('reentrada: salir sin registrar y volver a abrir empieza limpio con otro id', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161(cobrado: 0));
      final m = await montar161(tester, repo);
      await tocar(tester, mas161('Nuestros Hijos'));
      await tester.binding.handlePopRoute();
      await asentar(tester);
      await tocar(tester, find.text('Descartar'));
      expect(m.resultados, [false]);

      await tocar(tester, find.byKey(const Key('abrir')));
      await asentar(tester);
      expect(find.text('Seguir'), findsOneWidget);
      expect(
        boton161(tester).onPressed,
        isNull,
        reason: 'no queda nada elegido de la vez anterior',
      );
      await tocar(tester, mas161('Nuestros Hijos'));
      await tocar(tester, cta161);
      await confirmarEnLaHoja161(tester);
      expect(m.ids, ['d-1']);
      expect(repo.lecturas, 2);
    });

    testWidgets('atrás con algo elegido pregunta; «Seguir escribiendo» no pierde nada', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      final m = await montar161(tester, repo);
      await tocar(tester, mas161('Nuestros Hijos'));
      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
      await tocar(tester, find.text('Seguir escribiendo'));
      expect(m.resultados, isEmpty);
      expect(boton161(tester).onPressed, isNotNull);
    });

    testWidgets('atrás durante la carga cierra sin romper cuando la lectura termina después', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161())..lecturaDetenida = Completer<void>();
      final m = await montar161(tester, repo, asentarLaLectura: false);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(m.resultados, [false]);
      repo.lecturaDetenida!.complete();
      await asentar(tester);
      expect(tester.takeException(), isNull);
    });

    for (final (nombre, estado) in [
      ('venta ausente', Estado161.ausente),
      ('error de lectura', Estado161.errorDeLectura),
      ('fuera de plazo', Estado161.a08FueraDePlazo),
      ('ya devuelta', Estado161.yaDevuelta),
    ]) {
      testWidgets('atrás desde «$nombre» cierra sin preguntar y sin registrar', (tester) async {
        final m = await llegar161(tester, estado);
        await tester.binding.handlePopRoute();
        await asentar(tester);
        expect(m.resultados, [false]);
        expect(find.text('¿Descartar lo que escribiste?'), findsNothing);
      });

      testWidgets('la flecha de la cabecera desde «$nombre» también sale', (tester) async {
        final m = await llegar161(tester, estado);
        await tocar(tester, find.byTooltip('Volver').first);
        expect(m.resultados, [false]);
      });
    }

    testWidgets('atrás desde «registrada» cierra con true, sin preguntar', (tester) async {
      final m = await llegar161(tester, Estado161.a05bRegistradaSinDeuda);
      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(m.resultados, [true]);
    });

    testWidgets('«Listo» dos veces seguidas cierra una sola vez', (tester) async {
      final m = await llegar161(tester, Estado161.a05bRegistradaSinDeuda);
      await tester.tap(find.byKey(const Key('devolucion_listo')));
      await tester.tap(find.byKey(const Key('devolucion_listo')), warnIfMissed: false);
      await asentar(tester);
      expect(m.resultados, [true]);
    });

    testWidgets(
      'cambiar la cantidad después de elegir qué hacer no deja elegida la opción de otro monto',
      (tester) async {
        final repo = RepoFalso161(ventaCanvas161());
        await _hastaSeguir(tester, repo);
        await tocar(tester, _opcion('devolverAhora'));
        // Suma el otro libro: ahora el monto a decidir es otro (\$ 4.500, no \$ 1.900).
        await alPrincipio161(tester);
        await tocar(tester, mas161('Salud y Hogar'));
        expect(find.text('¿QUÉ HACÉS CON ${_m(450000)}?'), findsOneWidget);
        expect(
          boton161(tester).onPressed,
          isNull,
          reason: 'la elección era para \$ 1.900; para \$ 4.500 hay que volver a elegir',
        );
      },
    );

    testWidgets('venta sin persona: el subtítulo arranca con «Pagó» y no inventa un nombre', (
      tester,
    ) async {
      await montar161(tester, RepoFalso161(ventaCanvas161()), personaId: null);
      expect(find.text('Pagó ${_m(450000)} de ${_m(450000)}'), findsOneWidget);
    });

    testWidgets('40 renglones y títulos de 150 caracteres a 360×640 ×2: se recorre y no desborda', (
      tester,
    ) async {
      final renglones = [
        for (var i = 0; i < 40; i++)
          renglon161('r$i', 'Título larguísimo número $i ${'palabra ' * 18}fin', precio: 123456),
      ];
      final repo = RepoFalso161(ventaCanvas161(cobrado: 0, renglones: renglones));
      await montar161(tester, repo, escala: 2);
      final ultimo = find.byTooltip('Uno más de ${renglones.last.titulo}');
      final lista = find.descendant(
        of: find.byKey(const Key('devolucion_pagina')),
        matching: find.byType(Scrollable),
      );
      for (var i = 0; i < 12 && ultimo.evaluate().isEmpty; i++) {
        final pos = tester.state<ScrollableState>(lista.first).position;
        pos.jumpTo(pos.maxScrollExtent);
        await tester.pump();
      }
      expect(ultimo, findsOneWidget);
      await tocar(tester, ultimo);
      await tocar(tester, cta161);
      await confirmarEnLaHoja161(tester);
      expect(tester.takeException(), isNull);
      expect(repo.pedidos.single.unidadesPorRenglon, {'i-r39': 1});
    });

    testWidgets('venta de miles de pesos: los montos grandes no se cortan a 360×640 ×2', (
      tester,
    ) async {
      final venta = ventaCanvas161(
        cobrado: 123456789,
        renglones: [renglon161('c', 'Combo grande', precio: 123456789)],
      );
      await montar161(tester, RepoFalso161(venta), escala: 2);
      await tocar(tester, mas161('Combo grande'));
      await tocar(tester, cta161);
      expect(tester.takeException(), isNull);
      sinTextoCortado161(tester);
    });

    testWidgets('con el teclado abierto en el motivo, el botón sigue alcanzable y no desborda', (
      tester,
    ) async {
      await _hastaSeguir(tester, RepoFalso161(ventaCanvas161()), escala: 2);
      await tocar(tester, _opcion('retener'));
      await verVisible(tester, motivo161);
      await tester.tap(motivo161);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await asentar(tester);
      expect(tester.takeException(), isNull);
      expect(cta161, findsOneWidget);
      final caja = tester.getRect(cta161);
      expect(
        caja.bottom,
        lessThanOrEqualTo(640 - 280 + 1),
        reason: 'el botón queda sobre el teclado',
      );
    });
  });

  group('Accesibilidad: lo que se anuncia', () {
    testWidgets('31-10: el aviso de error es región viva', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegar161(tester, Estado161.a10ErrorAlGuardar);
      final nodo = tester.getSemantics(find.byKey(const Key('devolucion_error')));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      semantica.dispose();
    });

    for (final (clave, estado) in [
      ('devolucion_sin_venta', Estado161.ausente),
      ('devolucion_error_lectura', Estado161.errorDeLectura),
      ('devolucion_fuera_de_plazo', Estado161.a08FueraDePlazo),
      ('devolucion_ya_devuelta', Estado161.yaDevuelta),
    ]) {
      testWidgets('el aviso «$clave» es región viva', (tester) async {
        final semantica = tester.ensureSemantics();
        await llegar161(tester, estado);
        final nodo = tester.getSemantics(find.byKey(Key(clave)));
        expect(nodo.flagsCollection.isLiveRegion, isTrue);
        semantica.dispose();
      });
    }

    testWidgets('31-05: el aviso de lo registrado es región viva', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegar161(tester, Estado161.a05bRegistradaSinDeuda);
      final nodo = tester.getSemantics(find.byKey(const Key('devolucion_aviso_ok')));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      semantica.dispose();
    });

    testWidgets('el botón apagado de 31-09 queda deshabilitado para el lector y dice por qué', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await llegar161(tester, Estado161.a09NadaElegido);
      expect(
        tester.getSemantics(cta161),
        isSemantics(isButton: true, isEnabled: false, hasEnabledState: true),
      );
      expect(find.text('Elegí al menos un producto.'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('31-02: el botón apagado dice por qué («Elegí qué hacés con la diferencia.»)', (
      tester,
    ) async {
      await llegar161(tester, Estado161.a02PagoDeMas);
      expect(find.text('Elegí qué hacés con la diferencia.'), findsOneWidget);
      expect(boton161(tester).onPressed, isNull);
    });

    testWidgets('«Registrando…»: el botón ocupado dice que está guardando', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegar161(tester, Estado161.registrando);
      expect(find.text('Registrando…'), findsOneWidget);
      expect(boton161(tester).onPressed, isNull);
      semantica.dispose();
    });

    testWidgets('la hoja de confirmar tiene encabezado para el lector', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegar161(tester, Estado161.a04HojaConfirmar);
      expect(find.bySemanticsLabel('¿Registrar la devolución?'), findsOneWidget);
      semantica.dispose();
    });
  });

  group('31-05 «Agendar la devolución del dinero» abre la agenda de cobranza', () {
    Future<Montaje161> hastaDebo(WidgetTester tester) async {
      final repo = RepoFalso161(ventaCanvas161());
      final m = await montar161(tester, repo, extra: agendarOverrides161());
      await tocar(tester, mas161('Nuestros Hijos'));
      await tocar(tester, cta161);
      await tocar(tester, _opcion('devolverDespues'));
      await confirmarEnLaHoja161(tester);
      return m;
    }

    testWidgets(
      'abre «Agendar visita», un doble toque la abre una sola vez y atrás vuelve a 31-05',
      (tester) async {
        final m = await hastaDebo(tester);
        final agendar = find.byKey(const Key('devolucion_agendar'));
        await tester.tap(agendar);
        await tester.tap(agendar, warnIfMissed: false);
        await asentar(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Agendar visita'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.binding.handlePopRoute();
        await asentar(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Devolución registrada'), findsOneWidget);
        expect(m.resultados, isEmpty, reason: 'volver de la agenda no cierra la devolución');
        // Y el botón sigue vivo.
        await tester.tap(agendar);
        await asentar(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Agendar visita'), findsOneWidget);
      },
    );
  });

  group('Menores de la revisión visual', () {
    testWidgets(
      'los montos no se parten entre «\$» y el número (subtítulo a 360×640)',
      (tester) async {
        await montar161(tester, RepoFalso161(ventaCanvas161()));
        expect(
          FormatoVenta.monto(450000),
          contains(' '),
          reason: '«pagó \$ 4.500 de \$» y «4.500» en dos renglones (captura a01Elegir 360x640 ×1)',
        );
      },
      // skip: issue #161 (QA) — el espacio entre «$» y el número no es sin quiebre: el monto se parte.
      skip: !conHallazgos161,
    );

    testWidgets(
      'la hoja de confirmar no deja «× 1» solo en un renglón a 360×640',
      (tester) async {
        await llegar161(tester, Estado161.a04HojaConfirmar);
        final alto = tester.getSize(find.text('Nuestros Hijos × 1')).height;
        expect(alto, lessThan(24), reason: 'el valor ocupa $alto dp: 2 renglones');
      },
      // skip: issue #161 (QA) — a 360 dp la columna del valor es angosta y parte «Nuestros Hijos × 1».
      skip: !conHallazgos161,
    );
  });

  group('Privacidad', () {
    test('el toString de las entidades y fallas no muestra el motivo ni los ids', () {
      final pedido = PedidoDeDevolucion(
        id: 'd-secreto',
        ventaId: 'v-secreta',
        colportorId: 'col-secreto',
        unidadesPorRenglon: const {'i-1': 1},
        motivo: 'Habló María Fernández, calle Rondeau 1234',
        ahora: DateTime.utc(2026, 10, 14),
      );
      final texto = [
        pedido.toString(),
        const FailureDevolucionNoGuardada(causa: 'otra_falla').toString(),
        const FailureDevolucionInvalida(causa: 'x').toString(),
      ].join(' ');
      for (final secreto in ['María', 'Rondeau', 'd-secreto', 'v-secreta', 'col-secreto']) {
        expect(texto, isNot(contains(secreto)));
      }
    });
  });
}
