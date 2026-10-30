// «Cobrar» con tarjeta y por transferencia (vista 29, HU-COB-002 y HU-COB-003, #164): un grupo por
// artboard (29A·01 a 29A·05 y 29B·01 a 29B·04; 29A·03 y el grupo C son de HU-COB-007) y los casos
// límite de cada flujo: doble toque, falla a mitad de la acción, dos cobros seguidos, volver atrás y
// reentrar, y datos límite (textos largos, textScaler 2.0).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/usecases/registrar_cobro_use_case.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/cobro_arnes.dart';

String _texto(String clave) => (find.byKey(Key(clave)).evaluate().single.widget as Text).data!;

Finder _medio(int i) => find.byKey(Key('cobro_medio_$i'));
final _efectivo = _medio(0);
final _tarjeta = _medio(1);
final _transferencia = _medio(2);
final _debito = find.byKey(const Key('cobro_tipo_0'));
final _credito = find.byKey(const Key('cobro_tipo_1'));
Finder _marca(String m) => find.byKey(Key('cobro_marca_$m'));
Finder _campo(String clave) =>
    find.descendant(of: find.byKey(Key(clave)), matching: find.byType(TextField));
final _banco = find.byKey(const Key('cobro_banco'));
Finder _bancoDeLaHoja(String b) => find.byKey(Key('cobro_banco_$b'));
final _bancoListo = find.byKey(const Key('cobro_banco_listo'));
final _listo = find.byKey(const Key('cobro_listo'));

Future<void> _escribir(WidgetTester tester, String clave, String texto) async {
  await traerAlAlcance(tester, _campo(clave));
  await tester.enterText(_campo(clave), texto);
  await asentarAgendar(tester, 3);
}

/// Elige el medio y escribe el monto.
Future<void> _preparar(WidgetTester tester, Finder medio, String monto) async {
  await tocarCobro(tester, medio);
  await escribirMonto(tester, monto);
}

Future<void> _registrar(WidgetTester tester) => tocarCobro(tester, botonRegistrar);

/// El control [f] se anuncia como elegido (`Semantics.selected`).
bool _elegido(WidgetTester tester, Finder f) => find
    .descendant(
      of: f,
      matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true),
      matchRoot: true,
    )
    .evaluate()
    .isNotEmpty;

/// El control [f] está dentro de una región viva (se anuncia al aparecer).
bool _vivo(Finder f) {
  final viva = find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true);
  return find.ancestor(of: f, matching: viva).evaluate().isNotEmpty ||
      find.descendant(of: f, matching: viva).evaluate().isNotEmpty;
}

/// Vuelve al principio del formulario: con él desplazado, la cabecera y los avisos de arriba quedan
/// fuera de la lista armada.
Future<void> _alTope(WidgetTester tester) async {
  final lista = find.descendant(of: pagina, matching: find.byType(Scrollable)).first;
  await tester.drag(lista, const Offset(0, 3000));
  await asentarAgendar(tester);
}

/// «✕», que está en la cabecera.
Future<void> _cerrar(WidgetTester tester) async {
  await _alTope(tester);
  await tocarCobro(tester, cerrarCobro);
}

/// Elige [banco] en la hoja y la cierra con «Listo».
Future<void> _elegirBanco(WidgetTester tester, String banco) async {
  await tocarCobro(tester, _banco);
  await tocarCobro(tester, _bancoDeLaHoja(banco));
  await tocarCobro(tester, _bancoListo);
}

void main() {
  group('El selector «MEDIO»', () {
    testWidgets('dado el canvas, dibuja Efectivo, Tarjeta y Transferencia, con Efectivo elegido', (
      tester,
    ) async {
      await montarCobro(tester);

      expect(find.text('MEDIO'), findsOneWidget);
      expect(find.text('Efectivo'), findsOneWidget);
      expect(find.text('Tarjeta'), findsOneWidget);
      expect(find.text('Transferencia'), findsOneWidget);
      expect(_elegido(tester, _efectivo), isTrue);
      expect(_elegido(tester, _tarjeta), isFalse);
      expect(_elegido(tester, _transferencia), isFalse);
      // Con efectivo no hay nada de la tarjeta ni de la transferencia, y sigue el canvas 28.
      expect(find.text('COBRO EN EFECTIVO'), findsOneWidget);
      expect(find.text('MARCA (OPCIONAL)'), findsNothing);
      expect(find.text('REFERENCIA (OPCIONAL)'), findsNothing);
    });

    testWidgets(
      'el orden es MEDIO, MONTO y FECHA, con los datos del medio entre el monto y la fecha',
      (tester) async {
        await montarCobro(tester, tamano: const Size(800, 1600));
        await tocarCobro(tester, _tarjeta);

        double arriba(Finder f) => tester.getTopLeft(f.first).dy;
        expect(arriba(find.text('MEDIO')), lessThan(arriba(find.text('MONTO'))));
        expect(arriba(find.text('MONTO')), lessThan(arriba(find.text('MARCA (OPCIONAL)'))));
        expect(arriba(find.text('MARCA (OPCIONAL)')), lessThan(arriba(find.text('FECHA'))));
      },
    );

    testWidgets('el lector de pantalla oye cuál está elegido, y cada uno mide al menos 48', (
      tester,
    ) async {
      await montarCobro(tester);
      await tocarCobro(tester, _transferencia);

      expect(_elegido(tester, _transferencia), isTrue);
      expect(_elegido(tester, _efectivo), isFalse);
      for (final m in [_efectivo, _tarjeta, _transferencia]) {
        expect(tester.getSize(m).height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('pasar de Tarjeta a Efectivo cobra en efectivo y sin datos de la tarjeta', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await tocarCobro(tester, _tarjeta);
      await _escribir(tester, 'cobro_aprobacion', '884213');
      await tocarCobro(tester, _efectivo);
      await escribirMonto(tester, '600');

      await _registrar(tester);

      final cobro = a.repo.recibidos.single;
      expect(cobro.medio, MedioCobranza.efectivo);
      expect(cobro.numeroAprobacion, isNull);
      expect(cobro.tarjetaTipo, isNull);
      expect(
        find.text('Sumamos \$ 600 a tu dinero en mano. Queda en mano hasta que lo deposites.'),
        findsOneWidget,
      );
    });
  });

  group('29A·01 · Cobro con tarjeta', () {
    testWidgets('dado el canvas, dibuja Débito y Crédito, las marcas y el número de aprobación', (
      tester,
    ) async {
      await montarCobro(tester);

      await tocarCobro(tester, _tarjeta);

      expect(find.text('COBRO'), findsOneWidget);
      expect(find.text('COBRO EN EFECTIVO'), findsNothing);
      expect(_elegido(tester, _tarjeta), isTrue);
      expect(find.text('Débito'), findsOneWidget);
      expect(find.text('Crédito'), findsOneWidget);
      expect(_elegido(tester, _debito), isTrue);
      expect(_elegido(tester, _credito), isFalse);
      expect(find.text('MARCA (OPCIONAL)'), findsOneWidget);
      for (final m in ['Visa', 'Mastercard', 'OCA', 'Otra']) {
        expect(_marca(m), findsOneWidget);
      }
      expect(find.text('Nº DE APROBACIÓN (OPCIONAL)'), findsOneWidget);
      expect(
        tester.widget<TextField>(_campo('cobro_aprobacion')).decoration!.hintText,
        'Lo dice el ticket',
      );
      expect(find.text('Registrar cobro'), findsOneWidget);
      await traerAlAlcance(tester, find.text('FECHA'));
      expect(find.text('FECHA'), findsOneWidget);
      // Ninguna marca viene elegida: es opcional y no se inventa un dato.
      expect(find.byKey(const Key('cobro_marca_otra')), findsNothing);
    });

    testWidgets(
      'marca y aprobación son opcionales: UYU 800 sin más se guarda con aprobación nula',
      (tester) async {
        final a = await montarCobro(tester);

        await _preparar(tester, _tarjeta, '800');
        expect(elBoton(tester).onPressed, isNotNull);
        await _registrar(tester);

        final cobro = a.repo.recibidos.single;
        expect(cobro.medio, MedioCobranza.tarjeta);
        expect(cobro.montoCentavos, 80000);
        expect(cobro.numeroAprobacion, isNull);
        expect(cobro.tarjetaMarca, isNull);
        expect(cobro.tarjetaTipo, TipoTarjeta.debito);
        expect(cobro.referenciaTransferencia, isNull);
        expect(cobro.bancoOrigen, isNull);
      },
    );

    testWidgets('con crédito, una marca y la aprobación, se guardan los tres', (tester) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _tarjeta, '800');

      await tocarCobro(tester, _credito);
      await tocarCobro(tester, _marca('Visa'));
      await _escribir(tester, 'cobro_aprobacion', '884213');
      await _registrar(tester);

      final cobro = a.repo.recibidos.single;
      expect(cobro.tarjetaTipo, TipoTarjeta.credito);
      expect(cobro.tarjetaMarca, 'Visa');
      expect(cobro.numeroAprobacion, '884213');
    });

    testWidgets('elegir una marca desmarca la anterior; tocar la elegida la quita', (tester) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _tarjeta, '800');

      await tocarCobro(tester, _marca('Visa'));
      await tocarCobro(tester, _marca('OCA'));
      expect(_elegido(tester, _marca('OCA')), isTrue);
      expect(_elegido(tester, _marca('Visa')), isFalse);
      await tocarCobro(tester, _marca('OCA'));
      expect(_elegido(tester, _marca('OCA')), isFalse);
      await _registrar(tester);

      expect(a.repo.recibidos.single.tarjetaMarca, isNull);
    });

    testWidgets('«Otra» abre un campo para escribir la marca, sin espacios de más', (tester) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _tarjeta, '800');

      await tocarCobro(tester, _marca('Otra'));
      expect(find.text('OTRA MARCA'), findsOneWidget);
      await _escribir(tester, 'cobro_marca_otra', '  Naranja   X  ');
      await _registrar(tester);

      expect(a.repo.recibidos.single.tarjetaMarca, 'Naranja X');
    });

    testWidgets('«Otra» sin escribir nada queda como «Otra», y otra marca cierra el campo', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _tarjeta, '800');
      await tocarCobro(tester, _marca('Otra'));

      await _registrar(tester);

      expect(a.repo.recibidos.single.tarjetaMarca, 'Otra');

      // Y al elegir una marca de la lista, el campo de «Otra» se va.
      await tocarCobro(tester, _listo);
      await abrirCobro(tester);
      await tocarCobro(tester, _tarjeta);
      await tocarCobro(tester, _marca('Otra'));
      expect(find.byKey(const Key('cobro_marca_otra')), findsOneWidget);
      await tocarCobro(tester, _marca('OCA'));
      expect(find.byKey(const Key('cobro_marca_otra')), findsNothing);
    });

    testWidgets('el número de aprobación llega sin espacios de más y no pasa de 40 caracteres', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _tarjeta, '800');

      await _escribir(tester, 'cobro_aprobacion', '  88  4213 ');
      await _registrar(tester);
      expect(a.repo.recibidos.single.numeroAprobacion, '88 4213');
    });

    testWidgets('el campo de aprobación admite hasta 40 caracteres y sin corrector', (
      tester,
    ) async {
      await montarCobro(tester);
      await tocarCobro(tester, _tarjeta);

      await _escribir(tester, 'cobro_aprobacion', 'A' * 60);

      final campo = tester.widget<TextField>(_campo('cobro_aprobacion'));
      expect(campo.controller!.text.length, RegistrarCobroUseCase.maximoAprobacion);
      expect(campo.autocorrect, isFalse);
      expect(campo.enableSuggestions, isFalse);
    });

    testWidgets('con solo espacios en la aprobación se guarda como «sin dato»', (tester) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _tarjeta, '800');

      await _escribir(tester, 'cobro_aprobacion', '     ');
      await _registrar(tester);

      expect(a.repo.recibidos.single.numeroAprobacion, isNull);
    });

    testWidgets(
      'lo cargado de la tarjeta queda al ir y volver entre medios, pero no viaja de otro',
      (tester) async {
        final a = await montarCobro(tester);
        await _preparar(tester, _tarjeta, '800');
        await _escribir(tester, 'cobro_aprobacion', '884213');
        await tocarCobro(tester, _marca('Visa'));

        await tocarCobro(tester, _transferencia);
        expect(find.text('MARCA (OPCIONAL)'), findsNothing);
        await tocarCobro(tester, _tarjeta);

        expect(tester.widget<TextField>(_campo('cobro_aprobacion')).controller!.text, '884213');
        expect(_elegido(tester, _marca('Visa')), isTrue);

        await tocarCobro(tester, _transferencia);
        await _registrar(tester);
        final cobro = a.repo.recibidos.single;
        expect(cobro.medio, MedioCobranza.transferencia);
        expect(cobro.numeroAprobacion, isNull);
        expect(cobro.tarjetaMarca, isNull);
        expect(cobro.tarjetaTipo, isNull);
      },
    );
  });

  group('29A·02 · Tarjeta registrada (V1)', () {
    testWidgets(
      'cobrar todo el saldo dice que suma al dinero depositado y pide guardar el ticket',
      (tester) async {
        await montarCobro(tester);

        await _preparar(tester, _tarjeta, '1200');
        await _registrar(tester);

        expect(find.text('Cobro registrado'), findsOneWidget);
        expect(find.text('COBRO'), findsOneWidget);
        expect(find.text('María Fernández · Mataojo 2044 · Depto 3B'), findsOneWidget);
        expect(_texto('cobro_pagado'), r'$ 4.500');
        expect(_texto('cobro_saldo'), r'$ 0');
        expect(find.text(r'Sumamos $ 1.200 a tu dinero depositado.'), findsOneWidget);
        expect(
          find.text('Guardá el ticket de la tarjeta: tu coordinador te lo va a pedir.'),
          findsOneWidget,
        );
        // El aviso es el del canvas, no el de la HU que promete una V2.
        expect(find.textContaining('V2'), findsNothing);
        expect(find.textContaining('dinero en mano'), findsNothing);
        expect(find.text('Listo'), findsOneWidget);
        expect(find.text('Volver al mapa'), findsNothing);
        expect(find.text('Agendar la próxima cobranza'), findsNothing);
        expect(cerrarCobro, findsNothing);
      },
    );

    testWidgets('«Listo» cierra y avisa que se cobró', (tester) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _tarjeta, '1200');
      await _registrar(tester);

      await tocarCobro(tester, _listo);

      expect(pagina, findsNothing);
      expect(a.resultados, [true]);
    });

    testWidgets('el gesto de atrás en la confirmación también cierra con «se cobró»', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _tarjeta, '1200');
      await _registrar(tester);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(pagina, findsNothing);
      expect(a.resultados, [true]);
    });

    testWidgets('un cobro parcial suma lo cobrado, ofrece agendar la próxima y avisa del ticket', (
      tester,
    ) async {
      await montarCobro(tester);

      await _preparar(tester, _tarjeta, '800');
      await _registrar(tester);

      expect(find.text(r'Sumamos $ 800 a tu dinero depositado.'), findsOneWidget);
      expect(_texto('cobro_saldo'), r'$ 400');
      expect(find.byKey(const Key('cobro_aviso_ticket')), findsOneWidget);
      expect(find.text('Agendar la próxima cobranza'), findsOneWidget);
      expect(_listo, findsOneWidget);
    });

    testWidgets('los avisos se leen: el verde y el ámbar son regiones vivas', (tester) async {
      await montarCobro(tester);
      await _preparar(tester, _tarjeta, '1200');
      await _registrar(tester);

      for (final clave in ['cobro_aviso_ok', 'cobro_aviso_ticket']) {
        expect(_vivo(find.byKey(Key(clave))), isTrue, reason: clave);
      }
    });
  });

  group('29A·04 · Monto mayor al saldo', () {
    testWidgets('UYU 1.500 con un saldo de 1.200 se marca y el botón queda apagado', (
      tester,
    ) async {
      final a = await montarCobro(tester);

      await _preparar(tester, _tarjeta, '1500');

      expect(find.text(r'El saldo es $ 1.200. Ingresá hasta ese monto.'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('el mismo monto cambia de dueño con el medio: vale igual para la transferencia', (
      tester,
    ) async {
      await montarCobro(tester);
      await escribirMonto(tester, '1500');

      await tocarCobro(tester, _transferencia);

      expect(find.text(r'El saldo es $ 1.200. Ingresá hasta ese monto.'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);
    });
  });

  group('29A·05 · Error al guardar', () {
    testWidgets(
      'el aviso dice que no se registró nada, conserva lo cargado y ofrece «Reintentar»',
      (tester) async {
        final a = await montarCobro(tester);
        a.repo.fallas.add(const FailureCobroNoGuardado());
        await _preparar(tester, _tarjeta, '800');
        await tocarCobro(tester, _credito);
        await _escribir(tester, 'cobro_aprobacion', '884213');

        await _registrar(tester);

        expect(
          find.text('No pudimos guardar el cobro. No se registró nada: probá de nuevo.'),
          findsOneWidget,
        );
        expect(find.text('Reintentar'), findsOneWidget);
        expect(elBoton(tester).onPressed, isNotNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.widget<TextField>(campoMonto).controller!.text, '800');
        expect(tester.widget<TextField>(_campo('cobro_aprobacion')).controller!.text, '884213');
        expect(_elegido(tester, _tarjeta), isTrue);
        expect(_elegido(tester, _credito), isTrue);
        expect(a.repo.cobros.containsKey('cobro-1'), isFalse);
      },
    );

    testWidgets('«Reintentar» repite el mismo id y no cobra dos veces', (tester) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureCobroNoGuardado());
      await _preparar(tester, _tarjeta, '800');
      await _registrar(tester);

      await _registrar(tester);

      expect(a.repo.recibidos.map((c) => c.id), ['cobro-1', 'cobro-1']);
      expect(a.idsGenerados, ['cobro-1']);
      expect(a.repo.cobros.keys.where((k) => !k.startsWith('previo')), ['cobro-1']);
      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(find.byKey(const Key('cobro_error')), findsNothing);
    });

    testWidgets('si entre la falla y el reintento cambia un dato del medio, es otro cobro', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureCobroNoGuardado());
      await _preparar(tester, _tarjeta, '800');
      await _registrar(tester);

      await tocarCobro(tester, _marca('OCA'));
      await _registrar(tester);

      expect(a.idsGenerados, ['cobro-1', 'cobro-2']);
      expect(a.repo.recibidos.last.tarjetaMarca, 'OCA');
    });

    testWidgets('si entre la falla y el reintento cambia el medio, es otro cobro', (tester) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureCobroNoGuardado());
      await _preparar(tester, _tarjeta, '800');
      await _registrar(tester);

      await tocarCobro(tester, _transferencia);
      await _registrar(tester);

      expect(a.idsGenerados, ['cobro-1', 'cobro-2']);
      expect(a.repo.recibidos.last.medio, MedioCobranza.transferencia);
    });

    testWidgets('una excepción al guardar deja el aviso y el botón libre, no trabado', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      a.repo.lanzar = StateError('se cayó');
      await _preparar(tester, _tarjeta, '800');

      await _registrar(tester);

      expect(find.byKey(const Key('cobro_error')), findsOneWidget);
      expect(elBoton(tester).onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_elegido(tester, _tarjeta), isTrue);
      await _registrar(tester);
      expect(find.text('Cobro registrado'), findsOneWidget);
    });

    testWidgets('un dato del medio demasiado largo para el servidor muestra el mismo aviso', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureCobroDatoDelMedioInvalido());
      await _preparar(tester, _tarjeta, '800');

      await _registrar(tester);

      expect(find.byKey(const Key('cobro_error')), findsOneWidget);
      expect(elBoton(tester).onPressed, isNotNull);
    });
  });

  group('Registrando', () {
    testWidgets('el medio, los datos y los chips se bloquean mientras guarda', (tester) async {
      final a = await montarCobro(tester);
      a.repo.compuerta = Completer<void>();
      await _preparar(tester, _tarjeta, '800');
      await tocarCobro(tester, _marca('Visa'));

      await _registrar(tester);

      expect(find.text('Registrando…'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);
      expect(tester.widget<TextField>(_campo('cobro_aprobacion')).enabled, isFalse);
      // Tocar otro medio, el tipo o una marca no cambia nada.
      await tester.tap(_transferencia, warnIfMissed: false);
      await tester.tap(_credito, warnIfMissed: false);
      await tester.tap(_marca('OCA'), warnIfMissed: false);
      await asentarAgendar(tester);
      expect(_elegido(tester, _tarjeta), isTrue);
      expect(_elegido(tester, _debito), isTrue);
      expect(_elegido(tester, _marca('Visa')), isTrue);
      expect(_elegido(tester, _marca('OCA')), isFalse);

      a.repo.compuerta!.complete();
      await asentarAgendar(tester);
      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(a.repo.recibidos.single.tarjetaMarca, 'Visa');
    });

    testWidgets('con transferencia, el campo del banco tampoco responde mientras guarda', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      a.repo.compuerta = Completer<void>();
      await _preparar(tester, _transferencia, '800');

      await _registrar(tester);
      await tester.tap(_banco, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(find.text('Banco de origen'), findsNothing);
      a.repo.compuerta!.complete();
      await asentarAgendar(tester);
    });

    testWidgets('doble toque en «Registrar cobro» con tarjeta: un solo cobro', (tester) async {
      final a = await montarCobro(tester);
      a.repo.compuerta = Completer<void>();
      await _preparar(tester, _tarjeta, '800');

      await _registrar(tester);
      await tester.tap(botonRegistrar, warnIfMissed: false);
      await asentarAgendar(tester);
      a.repo.compuerta!.complete();
      await asentarAgendar(tester);

      expect(a.repo.recibidos, hasLength(1));
      expect(a.idsGenerados, ['cobro-1']);
    });
  });

  group('29B·01 · Cobro por transferencia', () {
    testWidgets('dado el canvas, dibuja la referencia y el banco de origen', (tester) async {
      await montarCobro(tester);

      await tocarCobro(tester, _transferencia);

      expect(find.text('COBRO'), findsOneWidget);
      expect(_elegido(tester, _transferencia), isTrue);
      expect(find.text('REFERENCIA (OPCIONAL)'), findsOneWidget);
      expect(
        tester.widget<TextField>(_campo('cobro_referencia')).decoration!.hintText,
        'Nº de operación',
      );
      expect(find.text('BANCO DE ORIGEN (OPCIONAL)'), findsOneWidget);
      expect(find.text('Elegir banco'), findsOneWidget);
      expect(find.text('MARCA (OPCIONAL)'), findsNothing);
      expect(find.text('Débito'), findsNothing);
    });

    testWidgets('TX-12345 y UYU 800 se persisten como transferencia con esa referencia', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _transferencia, '800');

      await _escribir(tester, 'cobro_referencia', 'TX-12345');
      await _registrar(tester);

      final cobro = a.repo.recibidos.single;
      expect(cobro.medio, MedioCobranza.transferencia);
      expect(cobro.montoCentavos, 80000);
      expect(cobro.referenciaTransferencia, 'TX-12345');
      expect(cobro.bancoOrigen, isNull);
      expect(cobro.tarjetaTipo, isNull);
      expect(cobro.tarjetaMarca, isNull);
      expect(cobro.numeroAprobacion, isNull);
    });

    testWidgets('la referencia y el banco son opcionales: sin ninguno también se guarda', (
      tester,
    ) async {
      final a = await montarCobro(tester);

      await _preparar(tester, _transferencia, '800');
      expect(elBoton(tester).onPressed, isNotNull);
      await _registrar(tester);

      final cobro = a.repo.recibidos.single;
      expect(cobro.referenciaTransferencia, isNull);
      expect(cobro.bancoOrigen, isNull);
    });

    testWidgets('la referencia llega sin espacios de más y el campo no pasa de 40 caracteres', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _transferencia, '800');

      await _escribir(tester, 'cobro_referencia', '  TX  12345 ');
      await _registrar(tester);
      expect(a.repo.recibidos.single.referenciaTransferencia, 'TX 12345');
    });

    testWidgets('el campo de la referencia admite hasta 40 caracteres y sin corrector', (
      tester,
    ) async {
      await montarCobro(tester);
      await tocarCobro(tester, _transferencia);

      await _escribir(tester, 'cobro_referencia', '9' * 60);

      final campo = tester.widget<TextField>(_campo('cobro_referencia'));
      expect(campo.controller!.text.length, RegistrarCobroUseCase.maximoReferencia);
      expect(campo.autocorrect, isFalse);
    });
  });

  group('29B·02 · Banco de origen', () {
    testWidgets('«Elegir banco» abre la hoja con BROU, Itaú, Santander, Scotiabank, BBVA y Otro', (
      tester,
    ) async {
      await montarCobro(tester);
      await tocarCobro(tester, _transferencia);

      await tocarCobro(tester, _banco);

      expect(find.text('Banco de origen'), findsOneWidget);
      for (final b in ['BROU', 'Itaú', 'Santander', 'Scotiabank', 'BBVA', 'Otro']) {
        expect(_bancoDeLaHoja(b), findsOneWidget);
      }
      expect(_bancoListo, findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      // Ninguno viene elegido, y «Otro» todavía no pide texto.
      expect(find.byKey(const Key('cobro_banco_otro')), findsNothing);
    });

    testWidgets('elegir BROU y «Listo» lo pone en el campo y el cobro lo guarda', (tester) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _transferencia, '800');

      await _elegirBanco(tester, 'BROU');

      expect(find.text('BROU'), findsOneWidget);
      expect(find.text('Elegir banco'), findsNothing);
      await _registrar(tester);
      expect(a.repo.recibidos.single.bancoOrigen, 'BROU');
    });

    testWidgets('cerrar la hoja sin «Listo» no cambia nada', (tester) async {
      await montarCobro(tester);
      await tocarCobro(tester, _transferencia);
      await _elegirBanco(tester, 'Itaú');

      await tocarCobro(tester, _banco);
      await tocarCobro(tester, _bancoDeLaHoja('BBVA'));
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(find.text('Itaú'), findsOneWidget);
      expect(find.text('BBVA'), findsNothing);
    });

    testWidgets('«Otro» abre un campo de texto y se guarda el nombre, sin espacios de más', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _transferencia, '800');
      await tocarCobro(tester, _banco);

      await tocarCobro(tester, _bancoDeLaHoja('Otro'));
      expect(find.byKey(const Key('cobro_banco_otro')), findsOneWidget);
      await _escribir(tester, 'cobro_banco_otro', '  Banco   Ñandú  ');
      await tocarCobro(tester, _bancoListo);

      expect(find.text('Banco Ñandú'), findsOneWidget);
      await _registrar(tester);
      expect(a.repo.recibidos.single.bancoOrigen, 'Banco Ñandú');
    });

    testWidgets('«Otro» sin escribir nada queda como «Otro»', (tester) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _transferencia, '800');

      await _elegirBanco(tester, 'Otro');
      await _registrar(tester);

      expect(a.repo.recibidos.single.bancoOrigen, 'Otro');
    });

    testWidgets('al volver a abrir la hoja viene elegido el banco de antes, también el escrito', (
      tester,
    ) async {
      await montarCobro(tester);
      await tocarCobro(tester, _transferencia);
      await _elegirBanco(tester, 'Santander');

      await tocarCobro(tester, _banco);
      expect(_elegido(tester, _bancoDeLaHoja('Santander')), isTrue);
      await tocarCobro(tester, _bancoDeLaHoja('Otro'));
      await _escribir(tester, 'cobro_banco_otro', 'Heritage');
      await tocarCobro(tester, _bancoListo);

      await tocarCobro(tester, _banco);
      expect(_elegido(tester, _bancoDeLaHoja('Otro')), isTrue);
      expect(tester.widget<TextField>(_campo('cobro_banco_otro')).controller!.text, 'Heritage');
    });

    testWidgets('tocar el banco elegido lo quita: el campo vuelve a «Elegir banco»', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _transferencia, '800');
      await _elegirBanco(tester, 'BBVA');

      await tocarCobro(tester, _banco);
      await tocarCobro(tester, _bancoDeLaHoja('BBVA'));
      await tocarCobro(tester, _bancoListo);

      expect(find.text('Elegir banco'), findsOneWidget);
      await _registrar(tester);
      expect(a.repo.recibidos.single.bancoOrigen, isNull);
    });

    testWidgets('el nombre del banco escrito no pasa de 60 caracteres', (tester) async {
      await montarCobro(tester);
      await tocarCobro(tester, _transferencia);
      await tocarCobro(tester, _banco);
      await tocarCobro(tester, _bancoDeLaHoja('Otro'));

      await _escribir(tester, 'cobro_banco_otro', 'B' * 90);

      final campo = tester.widget<TextField>(_campo('cobro_banco_otro'));
      expect(campo.controller!.text.length, RegistrarCobroUseCase.maximoBanco);
    });

    testWidgets('dos toques seguidos en el campo del banco abren una sola hoja', (tester) async {
      await montarCobro(tester);
      await tocarCobro(tester, _transferencia);

      await tester.tap(_banco);
      await tester.tap(_banco, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(find.text('Banco de origen'), findsOneWidget);
    });
  });

  group('29B·03 · Transferencia registrada', () {
    testWidgets('dice que suma al dinero depositado y repite la referencia', (tester) async {
      await montarCobro(tester);
      await _preparar(tester, _transferencia, '1200');
      await _escribir(tester, 'cobro_referencia', '88213');

      await _registrar(tester);

      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(
        find.text(r'Sumamos $ 1.200 a tu dinero depositado. Referencia 88213.'),
        findsOneWidget,
      );
      // El aviso del ticket es solo de la tarjeta.
      expect(find.byKey(const Key('cobro_aviso_ticket')), findsNothing);
      expect(find.textContaining('ticket'), findsNothing);
      expect(find.text('Listo'), findsOneWidget);
      expect(find.text('Volver al mapa'), findsNothing);
    });

    testWidgets('sin referencia, el aviso no la menciona', (tester) async {
      await montarCobro(tester);
      await _preparar(tester, _transferencia, '1200');

      await _registrar(tester);

      expect(find.text(r'Sumamos $ 1.200 a tu dinero depositado.'), findsOneWidget);
      expect(find.textContaining('Referencia'), findsNothing);
    });

    testWidgets('un cobro parcial ofrece agendar la próxima cobranza y «Listo» cierra', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await _preparar(tester, _transferencia, '500');
      await _registrar(tester);

      expect(find.text('Agendar la próxima cobranza'), findsOneWidget);
      await tocarCobro(tester, _listo);

      expect(pagina, findsNothing);
      expect(a.resultados, [true]);
    });
  });

  group('29B·04 · Sin conexión', () {
    testWidgets(
      'el cobro por transferencia funciona igual sin red: no hay otro estado ni otro texto',
      (tester) async {
        final a = await montarCobro(tester);
        a.telefono.conexion.cambiarA(TipoConexion.sinConexion);
        await asentarAgendar(tester);

        expect(find.textContaining('conexión'), findsNothing);
        await _preparar(tester, _transferencia, '600');
        await _registrar(tester);

        expect(a.repo.recibidos, hasLength(1));
        expect(find.text('Cobro registrado'), findsOneWidget);
        expect(find.textContaining('conexión'), findsNothing);
      },
    );

    testWidgets('con tarjeta, igual', (tester) async {
      final a = await montarCobro(tester);
      a.telefono.conexion.cambiarA(TipoConexion.sinConexion);
      await asentarAgendar(tester);

      await _preparar(tester, _tarjeta, '600');
      await _registrar(tester);

      expect(a.repo.recibidos.single.medio, MedioCobranza.tarjeta);
      expect(find.text('Cobro registrado'), findsOneWidget);
    });
  });

  group('Casos límite', () {
    testWidgets(
      'dos cobros seguidos de medios distintos: el segundo ve el saldo nuevo y empieza limpio',
      (tester) async {
        final a = await montarCobro(tester);
        await _preparar(tester, _tarjeta, '800');
        await tocarCobro(tester, _credito);
        await _escribir(tester, 'cobro_aprobacion', '111');
        await _registrar(tester);
        await tocarCobro(tester, _listo);

        await abrirCobro(tester);
        expect(_texto('cobro_saldo'), r'$ 400');
        expect(_elegido(tester, _efectivo), isTrue);
        await tocarCobro(tester, _transferencia);
        await escribirMonto(tester, '400');
        await _escribir(tester, 'cobro_referencia', 'TX-9');
        await _registrar(tester);

        expect(find.text('Venta pagada'), findsNothing);
        expect(_texto('cobro_saldo'), r'$ 0');
        expect(a.idsGenerados, ['cobro-1', 'cobro-2']);
        final primero = a.repo.recibidos.first;
        final segundo = a.repo.recibidos.last;
        expect(primero.tarjetaTipo, TipoTarjeta.credito);
        expect(primero.numeroAprobacion, '111');
        expect(primero.referenciaTransferencia, isNull);
        expect(segundo.medio, MedioCobranza.transferencia);
        expect(segundo.referenciaTransferencia, 'TX-9');
        expect(segundo.numeroAprobacion, isNull);
        expect(segundo.tarjetaTipo, isNull);
      },
    );

    testWidgets('con un dato del medio escrito, «✕» y atrás preguntan antes de descartar', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await tocarCobro(tester, _tarjeta);
      await _escribir(tester, 'cobro_aprobacion', '884213');

      await _cerrar(tester);
      expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
      await tocarCobro(tester, find.text('Seguir escribiendo'));
      expect(tester.widget<TextField>(_campo('cobro_aprobacion')).controller!.text, '884213');
      await _cerrar(tester);
      await tocarCobro(tester, find.text('Descartar'));

      expect(pagina, findsNothing);
      expect(a.resultados, [false]);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('con un banco elegido también pregunta; con solo el medio cambiado no', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      await tocarCobro(tester, _transferencia);
      await tocarCobro(tester, _tarjeta);
      await tocarCobro(tester, _credito);
      await _cerrar(tester);
      expect(pagina, findsNothing);
      expect(a.resultados, [false]);

      await abrirCobro(tester);
      await tocarCobro(tester, _transferencia);
      await _elegirBanco(tester, 'BROU');
      await _cerrar(tester);
      expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
    });

    testWidgets('volver atrás y reentrar empieza de cero: efectivo, débito y sin datos', (
      tester,
    ) async {
      await montarCobro(tester);
      await tocarCobro(tester, _tarjeta);
      await tocarCobro(tester, _credito);
      await tocarCobro(tester, _marca('Visa'));
      await _escribir(tester, 'cobro_aprobacion', '884213');
      await _cerrar(tester);
      await tocarCobro(tester, find.text('Descartar'));

      await abrirCobro(tester);

      expect(_elegido(tester, _efectivo), isTrue);
      await tocarCobro(tester, _tarjeta);
      expect(_elegido(tester, _debito), isTrue);
      expect(_elegido(tester, _marca('Visa')), isFalse);
      expect(tester.widget<TextField>(_campo('cobro_aprobacion')).controller!.text, isEmpty);
    });

    testWidgets('el id del cobro no cambia si solo se espacia distinto el mismo dato', (
      tester,
    ) async {
      final a = await montarCobro(tester);
      a.repo.fallas.add(const FailureCobroNoGuardado());
      await _preparar(tester, _tarjeta, '800');
      await _escribir(tester, 'cobro_aprobacion', '884213');
      await _registrar(tester);

      await _escribir(tester, 'cobro_aprobacion', '  884213 ');
      await _registrar(tester);

      expect(a.idsGenerados, ['cobro-1']);
      expect(a.repo.recibidos.map((c) => c.id), ['cobro-1', 'cobro-1']);
    });
  });

  group('textScaler 2.0 en 320×568', () {
    const chico = Size(320, 568);

    Future<void> alAlcance(WidgetTester tester, Finder f) async {
      await traerAlAlcance(tester, f);
      final rect = tester.getRect(f.first);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(568));
    }

    testWidgets('el selector del medio se apila y los tres se leen enteros', (tester) async {
      await montarCobro(tester, escala: 2, tamano: chico);
      await traerAlAlcance(tester, _transferencia);

      expect(tester.takeException(), isNull);
      // Apilados: cada uno debajo del anterior.
      expect(tester.getTopLeft(_tarjeta).dy, greaterThan(tester.getBottomLeft(_efectivo).dy - 1));
      expect(
        tester.getTopLeft(_transferencia).dy,
        greaterThan(tester.getBottomLeft(_tarjeta).dy - 1),
      );
      for (final m in [_efectivo, _tarjeta, _transferencia]) {
        expect(tester.getSize(m).width, lessThanOrEqualTo(320));
      }
    });

    testWidgets('con lugar de sobra el selector es una fila de tres iguales', (tester) async {
      await montarCobro(tester, tamano: const Size(800, 900));

      expect(tester.getTopLeft(_tarjeta).dy, tester.getTopLeft(_efectivo).dy);
      expect(tester.getTopLeft(_transferencia).dy, tester.getTopLeft(_efectivo).dy);
      expect(tester.getSize(_tarjeta).width, tester.getSize(_efectivo).width);
    });

    testWidgets('el formulario de la tarjeta con «Otra» y el aviso de falla no desbordan', (
      tester,
    ) async {
      final a = await montarCobro(tester, escala: 2, tamano: chico);
      a.repo.fallas.add(const FailureCobroNoGuardado());
      await tocarCobro(tester, _tarjeta);
      await escribirMonto(tester, '600');
      await tocarCobro(tester, _marca('Otra'));
      await _escribir(tester, 'cobro_marca_otra', 'M' * 40);
      await _escribir(tester, 'cobro_aprobacion', 'A' * 40);

      await tocarCobro(tester, botonRegistrar);

      expect(tester.takeException(), isNull);
      await _alTope(tester);
      expect(find.byKey(const Key('cobro_error')), findsOneWidget);
      await alAlcance(tester, botonRegistrar);
      await alAlcance(tester, campoFecha);
    });

    testWidgets('el formulario de la transferencia con un banco largo no desborda', (tester) async {
      await montarCobro(tester, escala: 2, tamano: chico);
      await tocarCobro(tester, _transferencia);
      await tocarCobro(tester, _banco);
      await tocarCobro(tester, _bancoDeLaHoja('Otro'));
      await _escribir(tester, 'cobro_banco_otro', 'Banco de la República ' * 3);
      expect(tester.takeException(), isNull);
      await alAlcance(tester, _bancoListo);
      await tocarCobro(tester, _bancoListo);

      expect(tester.takeException(), isNull);
      await alAlcance(tester, _banco);
      await _escribir(tester, 'cobro_referencia', 'R' * 40);
      await alAlcance(tester, botonRegistrar);
    });

    testWidgets('la confirmación de la tarjeta, con el aviso del ticket, deja «Listo» al alcance', (
      tester,
    ) async {
      await montarCobro(tester, escala: 2, tamano: chico);
      await tocarCobro(tester, _tarjeta);
      await escribirMonto(tester, '1200');
      await tocarCobro(tester, botonRegistrar);

      expect(tester.takeException(), isNull);
      await alAlcance(tester, find.byKey(const Key('cobro_aviso_ticket')));
      await alAlcance(tester, _listo);
    });

    testWidgets('la confirmación de la transferencia con referencia larga no desborda', (
      tester,
    ) async {
      await montarCobro(tester, escala: 2, tamano: chico);
      await tocarCobro(tester, _transferencia);
      await escribirMonto(tester, '1200');
      await _escribir(tester, 'cobro_referencia', 'X' * 40);
      await tocarCobro(tester, botonRegistrar);

      expect(tester.takeException(), isNull);
      await alAlcance(tester, _listo);
    });
  });
}
