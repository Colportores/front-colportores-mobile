// QA de «Dos motivos» (vista 42B·09C, HU-VEN-001, #706): la venta que crece cuando la venta YA tenía el
// motivo del monto a mano y se le suma otro. Lo que no cubren los tests del implementador: la matriz de
// tamaños y escalas, las guías de accesibilidad, los bordes del tope de 500 (0, 1, emojis, espacios,
// pegado largo), fallas a mitad de la suma y toques a la vez.
// Con `--dart-define=QA_CAPTURAS=true` se guardan capturas en `.dart_tool/qa_capturas/`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/sumar_a_la_venta_use_case.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista42_venta_crece_693_arnes.dart';
import '../../helpers/venta_ui_falsos.dart';

const _matriz = <({String nombre, Size tamano, double escala})>[
  (nombre: '360x640 ×1,0', tamano: telefonoChico693, escala: 1),
  (nombre: '360x640 ×2,0', tamano: telefonoChico693, escala: 2),
  (nombre: '412x915 ×1,0', tamano: telefonoGrande693, escala: 1),
  (nombre: '412x915 ×2,0', tamano: telefonoGrande693, escala: 2),
];

Finder get _cta => find.byKey(const Key('venta_cta'));

Finder _campo(String clave) =>
    find.descendant(of: find.byKey(Key(clave)), matching: find.byType(TextField));

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(_cta).onPressed != null;

String _textoDe(WidgetTester tester, String clave) =>
    tester.widget<TextField>(_campo(clave)).controller!.text;

Future<void> _sumarSaludYHogar(WidgetTester tester) async {
  await tocar(tester, find.text('Libros'));
  await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
  await tocar(tester, find.text(TextosVenta.agregarALaVenta));
}

/// Abre la 0039 con [motivo] ya puesto, con «Salud y Hogar» sumado y el monto abierto para cambiar.
Future<({EntornoDeVenta e, VentasAbiertasQA repo})> _abrir(
  WidgetTester tester, {
  required String? motivo,
  Size tamano = const Size(390, 844),
  double escala = 1,
  VentasAbiertasQA? repo,
}) async {
  final venta = ventaAbierta693('v-39', motivo: motivo, total: 110000, cobrado: 0);
  final r = repo ?? VentasAbiertasQA(abiertas: [venta]);
  final e = EntornoDeVenta(crece: r);
  await montarNuevaVenta(tester, e, creceSobre: venta, tamano: tamano, escala: escala);
  await _sumarSaludYHogar(tester);
  await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));
  return (e: e, repo: r);
}

Future<void> _escribirMontoYMotivo(WidgetTester tester, String motivo) async {
  await escribir(tester, _campo('venta_monto'), '1.500');
  await escribir(tester, _campo('venta_motivo'), motivo);
}

void main() {
  group('09C · con el motivo de antes: matriz de tamaños y escalas', () {
    for (final c in _matriz) {
      testWidgets('${c.nombre}: motivos que entran y que no entran, sin desbordes', (tester) async {
        await cargarFuentes693(tester);
        await _abrir(tester, motivo: 'redondeo', tamano: c.tamano, escala: c.escala);
        expect(tester.takeException(), isNull);
        await verVisible(tester, _campo('venta_motivo'));
        await capturarPantalla693(
          tester,
          '706_09C_motivo_vacio_${c.tamano.width.toInt()}_x${c.escala.toInt()}',
        );

        await _escribirMontoYMotivo(tester, 'descuento del libro nuevo');
        expect(tester.takeException(), isNull);
        expect(textosFueraDeLaPantalla693(tester, c.tamano), isEmpty);
        expect(_habilitado(tester), isTrue);
        await verVisible(tester, _cta);
        await capturarPantalla693(
          tester,
          '706_09C_motivo_entra_${c.tamano.width.toInt()}_x${c.escala.toInt()}',
        );
      });

      testWidgets('${c.nombre}: el aviso «te quedan N» se lee entero y el botón explica', (
        tester,
      ) async {
        await cargarFuentes693(tester);
        await _abrir(tester, motivo: 'v' * 480, tamano: c.tamano, escala: c.escala);
        await _escribirMontoYMotivo(tester, 'descuento del libro nuevo');
        final aviso = SumarALaVentaUseCase.motivoNoEntra(17);

        expect(tester.takeException(), isNull);
        expect(textosFueraDeLaPantalla693(tester, c.tamano), isEmpty);
        expect(_habilitado(tester), isFalse);
        // Está en el campo y en la nota del botón.
        expect(find.text(aviso), findsNWidgets(2));
        // El del campo, a la vista y en una región viva (el lector lo anuncia al aparecer).
        final delCampo = find.descendant(
          of: find.byKey(const Key('venta_motivo')),
          matching: find.text(aviso),
        );
        await verVisible(tester, delCampo);
        final caja = tester.getRect(delCampo);
        expect(caja.bottom, lessThanOrEqualTo(c.tamano.height));
        expect(caja.top, greaterThanOrEqualTo(0));
        await capturarPantalla693(
          tester,
          '706_09C_motivo_no_entra_${c.tamano.width.toInt()}_x${c.escala.toInt()}',
        );
      });
    }

    testWidgets('el aviso del campo es una región viva para el lector', (tester) async {
      final handle = tester.ensureSemantics();
      await _abrir(tester, motivo: 'v' * 480);
      await _escribirMontoYMotivo(tester, 'descuento del libro nuevo');

      final aviso = find.descendant(
        of: find.byKey(const Key('venta_motivo')),
        matching: find.text(SumarALaVentaUseCase.motivoNoEntra(17)),
      );
      expect(
        tester.getSemantics(aviso),
        isSemantics(label: SumarALaVentaUseCase.motivoNoEntra(17), isLiveRegion: true),
      );
      handle.dispose();
    });
  });

  group('09C · los bordes del tope de 500 sobre el texto unido', () {
    testWidgets('quedan 0: el aviso lo dice, el botón queda apagado y se puede salir', (
      tester,
    ) async {
      // 497 + « · » (3) = 500: no queda lugar para nada.
      final x = await _abrir(tester, motivo: 'v' * 497);
      await _escribirMontoYMotivo(tester, 'x');

      expect(find.text(SumarALaVentaUseCase.motivoNoEntra(0)), findsWidgets);
      // Con 0 no hay nada que acortar: el aviso manda a la salida, no a «acortalo».
      expect(SumarALaVentaUseCase.motivoNoEntra(0), isNot(contains('acortalo')));
      expect(SumarALaVentaUseCase.motivoNoEntra(0), contains('Volver al monto calculado'));
      expect(_habilitado(tester), isFalse);

      // La salida: volver al monto calculado.
      await tocar(tester, find.text('Volver al monto calculado'));
      expect(_habilitado(tester), isTrue);
      await tocar(tester, _cta);
      expect(x.repo.sumas.single.motivo, isNull);
    });

    testWidgets('quedan 1: entra un carácter y con dos no (singular en el aviso)', (tester) async {
      final x = await _abrir(tester, motivo: 'v' * 496);
      await _escribirMontoYMotivo(tester, 'ab');

      expect(find.text(SumarALaVentaUseCase.motivoNoEntra(1)), findsWidgets);
      expect(SumarALaVentaUseCase.motivoNoEntra(1), contains('te queda 1 carácter'));
      expect(_habilitado(tester), isFalse);

      await escribir(tester, _campo('venta_motivo'), 'a');
      expect(_habilitado(tester), isTrue);
      await tocar(tester, _cta);
      expect(x.repo.sumas.single.motivo, '${'v' * 496} · a');
      expect(x.repo.sumas.single.motivo!.runes.length, 500);
    });

    testWidgets('justo 500 entra; 501 no', (tester) async {
      final x = await _abrir(tester, motivo: 'v' * 100);
      // 100 + 3 = 103: quedan 397.
      await _escribirMontoYMotivo(tester, 'n' * 398);
      expect(_habilitado(tester), isFalse);
      expect(find.text(SumarALaVentaUseCase.motivoNoEntra(397)), findsWidgets);

      await escribir(tester, _campo('venta_motivo'), 'n' * 397);
      expect(_habilitado(tester), isTrue);
      await tocar(tester, _cta);
      expect(x.repo.sumas.single.motivo!.runes.length, 500);
    });

    testWidgets('emojis: se cuentan como un carácter cada uno, como el CHECK del servidor', (
      tester,
    ) async {
      // 249 emojis (2 unidades UTF-16 cada uno) + « · » = 252: quedan 248.
      final previo = '🎁' * 249;
      final x = await _abrir(tester, motivo: previo);
      await _escribirMontoYMotivo(tester, '🎉' * 249);
      expect(_habilitado(tester), isFalse);
      expect(find.text(SumarALaVentaUseCase.motivoNoEntra(248)), findsWidgets);

      await escribir(tester, _campo('venta_motivo'), '🎉' * 248);
      expect(_habilitado(tester), isTrue);
      await tocar(tester, _cta);
      final guardado = x.repo.sumas.single.motivo!;
      expect(guardado.runes.length, 500);
      expect(guardado, '$previo · ${'🎉' * 248}');
    });

    testWidgets('un emoji compuesto (👨‍👩‍👧) cuenta por sus puntos de código, no por grafema', (
      tester,
    ) async {
      const familia = '👨‍👩‍👧';
      final puntos = familia.runes.length; // 5
      final previo = 'v' * 400;
      // Quedan 97: con 20 familias son 100 puntos de código → no entra, aunque sean 20 grafemas.
      final x = await _abrir(tester, motivo: previo);
      await _escribirMontoYMotivo(tester, familia * 20);

      expect(puntos * 20, greaterThan(97));
      expect(_habilitado(tester), isFalse);
      expect(x.repo.sumas, isEmpty);
    });

    testWidgets('espacios en los bordes del motivo viejo y del nuevo no se guardan', (
      tester,
    ) async {
      final x = await _abrir(tester, motivo: '  redondeo  ');
      await _escribirMontoYMotivo(tester, '   descuento del libro nuevo   ');

      await tocar(tester, _cta);

      expect(x.repo.sumas.single.motivo, 'redondeo · descuento del libro nuevo');
    });

    testWidgets('un motivo viejo en blanco no deja el « · » colgando', (tester) async {
      final x = await _abrir(tester, motivo: '   ');
      await _escribirMontoYMotivo(tester, 'descuento');

      await tocar(tester, _cta);

      expect(x.repo.sumas.single.motivo, 'descuento');
    });

    testWidgets('un motivo viejo en blanco deja el tope entero (500) para lo nuevo', (
      tester,
    ) async {
      final x = await _abrir(tester, motivo: '   ');
      await _escribirMontoYMotivo(tester, 'n' * 500);

      expect(_habilitado(tester), isTrue);
      await tocar(tester, _cta);
      expect(x.repo.sumas.single.motivo!.runes.length, 500);
    });

    testWidgets('el motivo nuevo con « · » adentro se guarda tal cual, sin partirse', (
      tester,
    ) async {
      final x = await _abrir(tester, motivo: 'redondeo');
      await _escribirMontoYMotivo(tester, 'a · b');

      await tocar(tester, _cta);

      expect(x.repo.sumas.single.motivo, 'redondeo · a · b');
    });

    testWidgets('texto pegado larguísimo (900): se acota a 500 y avisa cuánto queda', (
      tester,
    ) async {
      final x = await _abrir(tester, motivo: 'redondeo');
      await _escribirMontoYMotivo(tester, 'a' * 900);

      expect(tester.takeException(), isNull);
      expect(_textoDe(tester, 'venta_motivo').runes.length, lessThanOrEqualTo(500));
      // 500 − 8 − 3 = 489 para lo nuevo.
      expect(find.text(SumarALaVentaUseCase.motivoNoEntra(489)), findsWidgets);
      expect(_habilitado(tester), isFalse);
      expect(x.repo.sumas, isEmpty);
    });

    testWidgets('caracteres especiales y saltos de línea en lo nuevo no rompen nada', (
      tester,
    ) async {
      final x = await _abrir(tester, motivo: 'redondeo');
      await _escribirMontoYMotivo(tester, "<b>50%</b> & 'comilla' \"doble\"\nsegunda línea");

      expect(tester.takeException(), isNull);
      await tocar(tester, _cta);
      expect(x.repo.sumas.single.motivo, startsWith('redondeo · <b>50%</b>'));
    });
  });

  group('09C · fallas, reintentos y toques a la vez con el motivo de antes', () {
    testWidgets('si falla a mitad: el botón vuelve, lo tipeado queda y reintentar une una sola vez', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(
        abiertas: [ventaAbierta693('v-39', motivo: 'redondeo', total: 110000, cobrado: 0)],
      )..respuestas.add(const FailureVentaNoGuardada());
      final x = await _abrir(tester, motivo: 'redondeo', repo: repo);
      await _escribirMontoYMotivo(tester, 'descuento del libro nuevo');

      await tocar(tester, _cta);

      expect(find.text(TextosVenta.errorAlGuardar), findsOneWidget);
      expect(_habilitado(tester), isTrue);
      expect(_textoDe(tester, 'venta_motivo'), 'descuento del libro nuevo');
      expect(_textoDe(tester, 'venta_monto'), isNotEmpty);

      await tocar(tester, _cta);

      // El primer intento (que falló) y el reintento llevan el mismo texto unido: no se junta dos veces.
      expect(
        [for (final m in x.repo.sumas) m.motivo],
        ['redondeo · descuento del libro nuevo', 'redondeo · descuento del libro nuevo'],
      );
    });

    testWidgets('un segundo toque mientras guarda no suma dos veces ni une el motivo dos veces', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(
        abiertas: [ventaAbierta693('v-39', motivo: 'redondeo', total: 110000, cobrado: 0)],
      )..compuerta = Completer<void>();
      final x = await _abrir(tester, motivo: 'redondeo', repo: repo);
      await _escribirMontoYMotivo(tester, 'descuento');
      await verVisible(tester, _cta);

      await tester.tap(_cta);
      await tester.pump();
      await tester.tap(_cta, warnIfMissed: false);
      await tester.pump();
      repo.compuerta!.complete();
      await asentar693(tester);

      expect(x.repo.sumas, hasLength(1));
      expect(x.repo.sumas.single.motivo, 'redondeo · descuento');
    });

    testWidgets('mientras guarda no se puede cambiar el motivo (no se junta uno distinto)', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(
        abiertas: [ventaAbierta693('v-39', motivo: 'redondeo', total: 110000, cobrado: 0)],
      )..compuerta = Completer<void>();
      await _abrir(tester, motivo: 'redondeo', repo: repo);
      await _escribirMontoYMotivo(tester, 'descuento');
      await verVisible(tester, _cta);
      await tester.tap(_cta);
      await tester.pump();

      expect(tester.widget<TextField>(_campo('venta_motivo')).enabled, isFalse);
      expect(tester.widget<TextField>(_campo('venta_monto')).enabled, isFalse);

      repo.compuerta!.complete();
      await asentar693(tester);
    });

    testWidgets('con una venta cerrada entre medio avisa y no deja nada a medio unir', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(
        abiertas: [ventaAbierta693('v-39', motivo: 'redondeo', total: 110000, cobrado: 0)],
      )..respuestas.add(const FailureVentaCerrada(numeroTalonario: '0039'));
      final x = await _abrir(tester, motivo: 'redondeo', repo: repo);
      await _escribirMontoYMotivo(tester, 'descuento');

      await tocar(tester, _cta);

      expect(find.textContaining('0039'), findsWidgets);
      expect(x.repo.sumas, hasLength(1));
    });

    testWidgets('volver al monto calculado y cambiarlo otra vez conserva lo escrito', (
      tester,
    ) async {
      await _abrir(tester, motivo: 'redondeo');
      await _escribirMontoYMotivo(tester, 'descuento');

      await tocar(tester, find.text('Volver al monto calculado'));
      await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));

      expect(tester.takeException(), isNull);
      // Lo escrito no se pierde ni se duplica junto al motivo de antes.
      final motivo = _textoDe(tester, 'venta_motivo');
      expect(motivo, isNot(contains('redondeo')));
    });

    testWidgets('con el motivo viejo el aviso de «sin motivo» sigue pidiendo el nuevo', (
      tester,
    ) async {
      await _abrir(tester, motivo: 'redondeo');
      await escribir(tester, _campo('venta_monto'), '1.500');

      expect(find.text(TextosVenta.motivoFalta), findsWidgets);
      expect(_habilitado(tester), isFalse);
    });
  });

  group('09C · sin motivo de antes no cambia nada', () {
    testWidgets('la venta sin motivo guarda solo el nuevo y acota a 500', (tester) async {
      final x = await _abrir(tester, motivo: null);
      await _escribirMontoYMotivo(tester, 'a' * 900);

      expect(find.textContaining('te quedan'), findsNothing);
      await tocar(tester, _cta);
      expect(x.repo.sumas.single.motivo, 'a' * 500);
    });
  });
}
