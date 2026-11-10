// QA de «Registrar depósito» (vista 33 D, HU-CTA-004, #443): entradas hostiles al monto y al número de
// operación, fallas a mitad del registro, acciones superpuestas, reentrada, datos límite, lo que se
// anuncia al lector y el teclado. Los hallazgos llevan `skip`; `--dart-define=QA_HALLAZGOS=true` los
// corre para verlos fallar.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/totales_de_depositos.dart';
import 'package:colportores_mobile/features/depositos/domain/repositories/deposito_repository.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_con_ticket_use_case.dart';
import 'package:colportores_mobile/features/depositos/presentation/textos_deposito.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart'
    show TextosDescartar;
import 'package:colportores_mobile/features/tickets/domain/services/captura_de_foto.dart';
import 'package:colportores_mobile/features/tickets/domain/services/puertos_de_fotos.dart'
    show CompresorDeImagen;
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/qa_vista33_deposito_443_arnes.dart';
import '../../helpers/tickets_falsos.dart';

Finder _texto(String t) => find.text(t, findRichText: true);

Finder _campo(String clave) =>
    find.descendant(of: find.byKey(Key(clave)), matching: find.byType(TextField));

/// Un repositorio de depósitos que, al guardar, lanza en vez de devolver una falla.
final class _DepositosQueLanzan implements DepositoRepository {
  var lanzar = true;
  final guardados = <Deposito>[];

  @override
  Future<Either<Failure, DepositoRegistrado>> registrar(Deposito deposito) async {
    guardados.add(deposito);
    if (lanzar) throw StateError('disco lleno /data/user/0/uy.colportores/secreto.db');
    return Right(DepositoRegistrado(deposito: deposito));
  }

  @override
  Future<Either<Failure, List<Deposito>>> todos() async => Right(guardados);

  @override
  Stream<List<Deposito>> observar() => Stream.value(guardados);

  @override
  Future<Either<Failure, TotalesDeDepositos>> totales() async =>
      const Right(TotalesDeDepositos(validadoCentavos: 0, porValidarCentavos: 50000));
}

final class _CompresorQueLanza implements CompresorDeImagen {
  @override
  Future<Uint8List?> comprimirComoJpeg(
    Uint8List original, {
    required int ladoMaximo,
    required int calidad,
  }) async => throw StateError('OOM');
}

void main() {
  group('monto: cada entrada acepta solo el dato requerido', () {
    testWidgets('lo que no es un monto se marca y apaga el botón; un monto válido lo enciende', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      await montar443(tester, arnes);
      await sacarLaFoto(tester);

      const invalidos = [
        'abc',
        '1.8',
        '-5',
        '1e3',
        '😀',
        '0',
        '0,00',
        '21.474.837',
        '1,234',
        '１２',
        '1..800',
        r'$',
        '1 8 0 0 a',
        '١٢٣',
      ];
      for (final texto in invalidos) {
        await escribirMonto(tester, texto);
        expect(
          botonRegistrar(tester).onPressed,
          isNull,
          reason: '«$texto» no debería poder registrarse',
        );
        expect(_texto(TextosDeposito.montoInvalido), findsOneWidget, reason: '«$texto» se marca');
      }

      for (final texto in ['   ', '\t']) {
        await escribirMonto(tester, texto);
        expect(botonRegistrar(tester).onPressed, isNull, reason: 'solo espacios');
        expect(_texto(TextosDeposito.montoInvalido), findsNothing);
        expect(_texto(TextosDeposito.faltaElMonto), findsWidgets, reason: 'dice qué falta');
      }

      for (final texto in ['1800', '1.800', '1.800,50', '2.400', r'$ 1.800', '0,01', '  900  ']) {
        await escribirMonto(tester, texto);
        expect(
          botonRegistrar(tester).onPressed,
          isNotNull,
          reason: '«$texto» debería poder registrarse',
        );
        expect(_texto(TextosDeposito.montoInvalido), findsNothing);
      }

      await escribirMonto(tester, '2.400,01');
      expect(_texto(r'Tenés $ 2.400,01 en mano.'), findsNothing);
      expect(_texto(r'Tenés $ 2.400 en mano.'), findsOneWidget, reason: 'un centavo de más');
      expect(botonRegistrar(tester).onPressed, isNull);

      await escribirMonto(tester, '2.400');
      expect(botonRegistrar(tester).onPressed, isNotNull, reason: 'justo lo que hay en mano');
      expect(arnes.depositos.guardados, isEmpty);
    });

    testWidgets('un texto pegado muy largo se recorta y no rompe nada', (tester) async {
      await montar443(tester, ArnesDeDeposito(), escala: 2);
      await escribirMonto(tester, '9' * 5000);
      final texto = tester.widget<TextField>(_campo('deposito_monto')).controller!.text;
      expect(texto.runes.length, lessThanOrEqualTo(14));
      expect(tester.takeException(), isNull);

      await escribirMonto(tester, '😀' * 200);
      final emoji = tester.widget<TextField>(_campo('deposito_monto')).controller!.text;
      expect(emoji.runes.length, lessThanOrEqualTo(14));
      expect(String.fromCharCodes(emoji.runes), emoji, reason: 'no parte un emoji a la mitad');
      expect(tester.takeException(), isNull);
    });

    testWidgets('tras la falla de «más de lo que tenés», corregir el monto habilita el botón', (
      tester,
    ) async {
      await montar443(tester, ArnesDeDeposito());
      await sacarLaFoto(tester);
      await escribirMonto(tester, '3000');
      expect(_texto(r'Tenés $ 2.400 en mano.'), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNull);
      await escribirMonto(tester, '2000');
      expect(_texto(r'Tenés $ 2.400 en mano.'), findsNothing);
      expect(botonRegistrar(tester).onPressed, isNotNull);
    });
  });

  group('número de operación: texto libre y opcional', () {
    testWidgets(
      'un número con emoji que el campo acepta (25 puntos de código) se registra',
      (tester) async {
        final arnes = ArnesDeDeposito();
        await montar443(tester, arnes);
        await escribirMonto(tester, '1800');
        await sacarLaFoto(tester);
        await verEnElFormulario(tester, const Key('deposito_referencia'));
        await tester.enterText(_campo('deposito_referencia'), '😀' * 25);
        await tester.pump();
        expect(
          tester.widget<TextField>(_campo('deposito_referencia')).controller!.text.runes,
          hasLength(25),
          reason: 'el campo lo acepta: el límite es de 40 puntos de código',
        );
        await tocarRegistrar(tester);

        expect(find.byKey(const Key('deposito_error')), findsNothing, reason: 'el aviso rojo');
        expect(arnes.depositos.guardados, hasLength(1));
      },
      // skip: QA #443 — el campo cuenta puntos de código (40) y el ticket UTF-16 (40): 25 emoji no entran.
      skip: !verHallazgos443,
    );

    testWidgets('texto largo pegado con acentos: se recorta a 40 y se registra', (tester) async {
      final arnes = ArnesDeDeposito();
      await montar443(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await verEnElFormulario(tester, const Key('deposito_referencia'));
      await tester.enterText(_campo('deposito_referencia'), 'ñandú-${'á' * 500}');
      await tester.pump();
      await tocarRegistrar(tester);

      final numero = arnes.tickets.guardados.single.ticket.numeroAutorizacion!;
      expect(numero.runes.length, 40);
    });

    testWidgets('solo espacios es como no escribir nada', (tester) async {
      final arnes = ArnesDeDeposito();
      await montar443(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await verEnElFormulario(tester, const Key('deposito_referencia'));
      await tester.enterText(_campo('deposito_referencia'), '     ');
      await tester.pump();
      await tocarRegistrar(tester);
      expect(arnes.tickets.guardados.single.ticket.numeroAutorizacion, isNull);
    });
  });

  group('falla a mitad de la acción: nada queda trabado', () {
    testWidgets('el repositorio lanza: avisa, conserva lo cargado y «Reintentar» registra', (
      tester,
    ) async {
      final depositos = _DepositosQueLanzan();
      final arnes = ArnesDeDeposito();
      await montar443(tester, arnes, depositos: depositos);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);

      expect(find.byKey(const Key('deposito_error')), findsOneWidget);
      expect(_texto(const FailureDepositoNoGuardado().mensaje), findsOneWidget);
      expect(_texto('secreto'), findsNothing, reason: 'la excepción cruda no llega a la pantalla');
      expect(find.textContaining('StateError'), findsNothing);
      expect(botonRegistrar(tester).onPressed, isNotNull, reason: 'el botón vuelve a responder');
      expect(_texto(TextosDeposito.reintentar), findsOneWidget);
      expect(find.byKey(const Key('deposito_foto_miniatura')), findsOneWidget);
      expect(tester.widget<TextField>(_campo('deposito_monto')).controller!.text, '1800');

      depositos.lanzar = false;
      await tocarRegistrar(tester);
      expect(_texto(TextosDeposito.tituloRegistrado), findsOneWidget);
      expect(depositos.guardados.map((d) => d.id), ['d-1', 'd-1'], reason: 'mismos ids');
    });

    testWidgets('el compresor revienta: dice que no se pudo leer y se puede sacar otra', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      await montar443(tester, arnes, compresor: _CompresorQueLanza());
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);

      expect(_texto(TextosDeposito.fotoIlegible), findsOneWidget);
      expect(_texto(TextosDeposito.preparandoFoto), findsNothing, reason: 'no queda trabado');
      expect(find.byKey(const Key('deposito_foto_miniatura')), findsNothing);
      expect(botonRegistrar(tester).onPressed, isNull);
      expect(
        tester.getSemantics(find.byKey(const Key('deposito_foto_error'))),
        isSemantics(isLiveRegion: true),
        reason: 'el error de la foto se anuncia',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('la foto se está achicando: ni registrar ni cambiar la foto responden', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      final lento = CompresorLento443();
      await montar443(tester, arnes, compresor: lento);
      await escribirMonto(tester, '1800');
      await verEnElFormulario(tester, const Key('deposito_foto'));
      await tester.tap(find.byKey(const Key('deposito_foto')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deposito_foto_camara')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_texto(TextosDeposito.preparandoFoto), findsWidgets);
      expect(botonRegistrar(tester).onPressed, isNull);
      await tester.tap(find.byKey(const Key('deposito_foto')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect((arnes.capturador as CapturadorGuionado).pedidos, hasLength(1));

      lento.espera.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('deposito_foto_camara')),
        findsNothing,
        reason: 'ninguna hoja quedó abierta',
      );
      expect(find.byKey(const Key('deposito_foto_miniatura')), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNotNull);
    });

    testWidgets('sin permiso de cámara y después una foto de la galería: el aviso se va', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito(
        capturador: CapturadorGuionado([
          const CapturaSinPermiso(),
          FotoCapturada(fotoDePrueba(4000)),
        ]),
      );
      await montar443(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      expect(_texto(TextosDeposito.sinPermisoDeCamara), findsOneWidget);

      await tester.tap(find.byKey(const Key('deposito_foto')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deposito_foto_galeria')));
      await tester.pumpAndSettle();
      expect(_texto(TextosDeposito.sinPermisoDeCamara), findsNothing);
      expect(botonRegistrar(tester).onPressed, isNotNull);
    });
  });

  group('acciones superpuestas', () {
    testWidgets('«Reintentar» tocado dos veces seguidas registra una sola vez', (tester) async {
      final arnes = ArnesDeDeposito()
        ..depositos.fallarUnaVezCon = const FailureDepositoNoGuardado();
      await montar443(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);
      expect(arnes.depositos.guardados, hasLength(1));

      arnes.depositos.espera = Completer<void>();
      await tester.tap(find.byKey(const Key('venta_cta')));
      await tester.tap(find.byKey(const Key('venta_cta')), warnIfMissed: false);
      await tester.pump();
      arnes.depositos.espera!.complete();
      await tester.pumpAndSettle();

      expect(arnes.depositos.guardados.map((d) => d.id), ['d-1', 'd-1']);
      expect(arnes.tickets.guardados, hasLength(2), reason: 'ticket del intento 1 y del reintento');
      expect(_texto(TextosDeposito.tituloRegistrado), findsOneWidget);
    });

    testWidgets('«Listo» tocado dos veces cierra una sola vez', (tester) async {
      final arnes = ArnesDeDeposito();
      final resultados = await montar443(tester, arnes);
      await escribirMonto(tester, '1000');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      await tocarRegistrar(tester);

      await tester.tap(find.byKey(const Key('deposito_listo')));
      await tester.tap(find.byKey(const Key('deposito_listo')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(resultados, [true]);
      expect(find.byKey(const Key('abrir_deposito')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Descartar» tocado dos veces cierra una sola vez', (tester) async {
      final resultados = await montar443(tester, ArnesDeDeposito());
      await escribirMonto(tester, '1800');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(TextosDescartar.titulo), findsOneWidget);
      await tester.tap(find.text(TextosDescartar.descartar));
      await tester.tap(find.text(TextosDescartar.descartar), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(resultados, [false]);
      expect(find.byKey(const Key('abrir_deposito')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('atrás mientras registra no cierra y al terminar muestra el éxito', (tester) async {
      final arnes = ArnesDeDeposito();
      final resultados = await montar443(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      arnes.depositos.espera = Completer<void>();
      await tocarRegistrar(tester, esperar: false);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);
      expect(resultados, isEmpty);

      arnes.depositos.espera!.complete();
      await tester.pumpAndSettle();
      expect(_texto(TextosDeposito.tituloRegistrado), findsOneWidget);
      expect(find.text(TextosDescartar.titulo), findsNothing);
    });
  });

  group('reentrada', () {
    testWidgets('después de registrar y salir, la pantalla vuelve vacía y registra otro depósito', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      final resultados = await montar443(tester, arnes);
      await escribirMonto(tester, '1000');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      await tocarRegistrar(tester);
      await tester.tap(find.byKey(const Key('deposito_listo')));
      await tester.pumpAndSettle();

      await abrirDeposito(tester);
      expect(tester.widget<TextField>(_campo('deposito_monto')).controller!.text, isEmpty);
      expect(find.byKey(const Key('deposito_foto_miniatura')), findsNothing);
      expect(botonRegistrar(tester).onPressed, isNull);

      await escribirMonto(tester, '1000');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      await tocarRegistrar(tester);
      expect(arnes.depositos.guardados.map((d) => d.id), ['d-1', 'd-2'], reason: 'otro depósito');
      expect(resultados, [true]);
    });

    testWidgets('salir con la pregunta «Descartar» y volver a entrar no arrastra lo escrito', (
      tester,
    ) async {
      await montar443(tester, ArnesDeDeposito());
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextosDescartar.descartar));
      await tester.pumpAndSettle();

      await abrirDeposito(tester);
      expect(tester.widget<TextField>(_campo('deposito_monto')).controller!.text, isEmpty);
      expect(find.byKey(const Key('deposito_foto_miniatura')), findsNothing);
    });
  });

  group('datos límite de la cuenta', () {
    testWidgets('cuenta nueva (sin un peso en mano): lo dice y no deja registrar nada', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito(
        cuenta: RepositorioDeCuentaControlable(inicial: resumenCuentaNueva),
      );
      await montar443(tester, arnes);
      await sacarLaFoto(tester);
      expect(_texto(r'En mano: $ 0'), findsOneWidget);
      await escribirMonto(tester, '1');
      expect(_texto(r'Tenés $ 0 en mano.'), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNull);
      expect(arnes.depositos.guardados, isEmpty);
    });

    testWidgets('la cuenta no se puede leer: sin tope ni «En mano», registra y no inventa cifras', (
      tester,
    ) async {
      final cuenta = RepositorioDeCuentaControlable()..fallaAlSuscribir = true;
      final arnes = ArnesDeDeposito(cuenta: cuenta);
      await montar443(tester, arnes);
      expect(find.textContaining('En mano:'), findsNothing);

      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);

      expect(_texto(TextosDeposito.tituloRegistrado), findsOneWidget);
      expect(find.byKey(const Key('deposito_fila_en_mano')), findsNothing);
      expect(find.byKey(const Key('deposito_fila_por_validar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la cuenta todavía carga: se puede escribir y el tope llega cuando llega', (
      tester,
    ) async {
      final cuenta = RepositorioDeCuentaControlable();
      final arnes = ArnesDeDeposito(cuenta: cuenta);
      await montar443(tester, arnes);
      await escribirMonto(tester, '3000');
      expect(find.textContaining('Tenés'), findsNothing);

      cuenta.emitir(resumenDelCanvas);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tenés'), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNull);
    });

    testWidgets('una fecha de ayer sobrevive a la falla y el reintento la repite', (tester) async {
      final arnes = ArnesDeDeposito()
        ..depositos.fallarUnaVezCon = const FailureDepositoNoGuardado();
      await montar443(tester, arnes);
      await escribirMonto(tester, '600');
      await sacarLaFoto(tester);
      await verEnElFormulario(tester, const Key('cobro_fecha'));
      await tester.tap(find.byKey(const Key('cobro_fecha')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tocarRegistrar(tester);
      expect(find.byKey(const Key('deposito_error')), findsOneWidget);
      await verEnElFormulario(tester, const Key('cobro_fecha'));
      expect(find.textContaining('Ayer'), findsOneWidget);

      await tocarRegistrar(tester);
      expect(arnes.depositos.guardados.map((d) => d.id), ['d-1', 'd-1']);
      expect(arnes.depositos.guardados.last.fecha, DateTime.utc(2026, 11, 9, 15));
    });
  });

  group('alquiler: la campaña a la que paga', () {
    testWidgets('mientras se lee la campaña el botón espera y después se enciende', (tester) async {
      final espera = Completer<String?>();
      final arnes = ArnesDeDeposito();
      await montar443(tester, arnes, campania: () => espera.future);
      await escribirMonto(tester, '1500');
      await tester.tap(find.byKey(const Key('deposito_concepto_1')));
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      expect(botonRegistrar(tester).onPressed, isNull);

      espera.complete('camp-9');
      await tester.pumpAndSettle();
      expect(botonRegistrar(tester).onPressed, isNotNull);
      await tocarRegistrar(tester);
      expect(arnes.depositos.guardados.single.campaniaId, 'camp-9');
    });

    testWidgets(
      'si la campaña no se puede leer, la pantalla lo dice (no deja el botón apagado sin motivo)',
      (tester) async {
        final arnes = ArnesDeDeposito();
        await montar443(
          tester,
          arnes,
          campania: () async => throw StateError('tabla campania_colportor ilegible'),
        );
        await escribirMonto(tester, '1500');
        await tester.tap(find.byKey(const Key('deposito_concepto_1')));
        await tester.tap(find.byKey(const Key('deposito_destino_2')));
        await tester.pump(const Duration(seconds: 1));

        expect(botonRegistrar(tester).onPressed, isNull);
        final hayAviso =
            find.byKey(const Key('deposito_sin_campania')).evaluate().isNotEmpty ||
            find.byKey(const Key('deposito_error')).evaluate().isNotEmpty ||
            find.textContaining('campaña').evaluate().isNotEmpty;
        expect(hayAviso, isTrue, reason: 'botón apagado sin decir por qué ni qué hacer');
      },
      // skip: QA #443 — con la lectura de la campaña fallida el botón queda apagado sin aviso.
      skip: !verHallazgos443,
    );
  });

  group('lector de pantalla', () {
    testWidgets('el aviso de error, el del monto y la confirmación se anuncian', (tester) async {
      final semantica = tester.ensureSemantics();
      final arnes = ArnesDeDeposito()
        ..depositos.fallarUnaVezCon = const FailureDepositoNoGuardado();
      await montar443(tester, arnes);
      await escribirMonto(tester, '3000');
      expect(
        tester.getSemantics(find.text(r'Tenés $ 2.400 en mano.')),
        isSemantics(isLiveRegion: true),
        reason: 'el error del monto se anuncia',
      );

      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);
      expect(
        tester.getSemantics(find.byKey(const Key('deposito_error'))),
        isSemantics(isLiveRegion: true),
      );

      await tocarRegistrar(tester);
      expect(
        tester.getSemantics(_texto(TextosDeposito.quedaPorValidarTicket)),
        isSemantics(isLiveRegion: true),
        reason: 'el éxito se anuncia',
      );
      semantica.dispose();
    });

    testWidgets('«Registrando…» no deja el botón sin nombre', (tester) async {
      final semantica = tester.ensureSemantics();
      final arnes = ArnesDeDeposito();
      await llegarA443(tester, Estado443.registrando, arnes: arnes);
      expect(
        tester.getSemantics(find.byKey(const Key('venta_cta'))),
        isSemantics(label: TextosDeposito.registrando, isButton: true),
      );
      await soltar443(tester, arnes);
      semantica.dispose();
    });
  });

  group('teclado', () {
    testWidgets(
      'con el teclado abierto a 360×640 y texto al 200 %, el monto se ve y el botón alcanza',
      (tester) async {
        await montar443(tester, ArnesDeDeposito(), escala: 2);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        expect(tester.takeException(), isNull);
        final monto = tester.getRect(_campo('deposito_monto'));
        final cta = tester.getRect(find.byKey(const Key('venta_cta')));
        expect(monto.top, greaterThanOrEqualTo(0));
        expect(
          monto.bottom,
          lessThanOrEqualTo(cta.top + 1),
          reason: 'el campo no queda bajo el botón',
        );
        expect(
          cta.bottom,
          lessThanOrEqualTo(640 - 280 + 1),
          reason: 'el botón queda sobre el teclado',
        );
        await capturar443(tester, 'teclado_360x640_x2.0');
      },
    );
  });

  group('privacidad', () {
    test(
      'toString de lo que lleva el depósito no imprime el número de operación ni los montos',
      () {
        final params = RegistrarDepositoConTicketParams(
          depositoId: 'd-1',
          ticketId: 't-1',
          colportorId: 'col-1',
          montoCentavos: 123456,
          destino: DestinoDeDeposito.banco,
          concepto: ConceptoDeDeposito.casaEditora,
          foto: fotoDePrueba(20),
          referencia: 'OP-SECRETA-777',
        );
        expect(params.toString(), isNot(contains('OP-SECRETA-777')));
        expect(params.toString(), isNot(contains('123456')));
      },
    );
  });

  group('criterios de aceptación de HU-CTA-004 (texto literal)', () {
    testWidgets(
      'Depósito de lo que tengo en mano: deposito todo, sin elegir cobros, y «En mano» pasa a 0',
      (tester) async {
        final arnes = ArnesDeDeposito(
          cuenta: RepositorioDeCuentaControlable(
            inicial: ResumenDeCuenta(enMano: cifra(5000), porCobrar: cifra(0)),
          ),
        );
        await montar443(tester, arnes);
        await escribirMonto(tester, '5000');
        await sacarLaFoto(tester);
        await tocarRegistrar(tester);

        expect(find.textContaining('cobro'), findsNothing, reason: 'sin elegir cobros');
        expect(_texto(r'$ 5.000 → $ 0'), findsOneWidget);
        expect(arnes.depositos.guardados.single.montoCentavos, 500000);
      },
    );

    testWidgets('Depósito parcial: tengo 5000, deposito 3000 y «En mano» queda en 2000', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito(
        cuenta: RepositorioDeCuentaControlable(
          inicial: ResumenDeCuenta(enMano: cifra(5000), porCobrar: cifra(0)),
        ),
      );
      await montar443(tester, arnes);
      await escribirMonto(tester, '3000');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);

      expect(_texto(r'$ 5.000 → $ 2.000'), findsOneWidget);
      expect(arnes.depositos.guardados.single.montoCentavos, 300000);
    });

    testWidgets('Depósito para el alquiler: queda con el concepto «alquiler» y su campaña', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      await montar443(tester, arnes);
      await escribirMonto(tester, '1500');
      await tester.tap(find.byKey(const Key('deposito_concepto_1')));
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);

      final d = arnes.depositos.guardados.single;
      expect(d.concepto, ConceptoDeDeposito.alquiler);
      expect(d.campaniaId, 'camp-1');
      expect(d.montoCentavos, 150000);
    });
  });

  group('decisión del 10/11 sobre los textos (P2 del implementador)', () {
    testWidgets(
      'sin cámara y alquiler sin campaña dicen lo que decidió el agente de decisiones',
      (tester) async {
        await montar443(tester, ArnesDeDeposito(sinCamara: true));
        expect(
          _texto('Este teléfono no tiene cámara: elegí la foto del ticket de la galería.'),
          findsOneWidget,
        );

        await montar443(tester, ArnesDeDeposito(campania: null));
        await escribirMonto(tester, '700');
        await tester.tap(find.byKey(const Key('deposito_concepto_1')));
        await tester.pumpAndSettle();
        expect(
          _texto(
            'No estás inscripto en una campaña en curso, y el alquiler se paga a tu campaña. '
            'Si es de una campaña que ya terminó, avisale a tu coordinador.',
          ),
          findsOneWidget,
        );
      },
      // skip: QA #443 — textos de la decisión del 10/11 (P2) sin aplicar; no frena el merge.
      skip: !verHallazgos443,
    );
  });
}
