// QA de «Registrar venta» (vista 27, HU-VEN-001, #158, PR #531): lo que la implementación no prueba
// (matriz de estados × tamaños × texto 1,0/2,0 sin overflow ni texto cortado, el texto literal de la
// HU, entradas límite, acciones superpuestas, navegación y privacidad). Las guías de accesibilidad
// están en `qa_vista27_venta_158_guias_test.dart`.
//
// Los casos con `skip:` documentan un hallazgo del QA (el implementador saca el `skip` al arreglarlo).
// `--dart-define=QA_CAPTURAS=true` guarda una captura por celda en `.dart_tool/qa_capturas/`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/cliente_de_la_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart'
    show TextosVenta;
import 'package:colportores_mobile/features/ventas/presentation/pages/venta_registrada_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/nueva_venta_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista27_venta_158_arnes.dart';
import '../../helpers/venta_falsos.dart';
import '../../helpers/venta_ui_falsos.dart';

/// `--dart-define=QA_HALLAZGOS=true` corre los casos que documentan un hallazgo (hoy fallan).
const conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

const _tamanos = {'360x640': chico531, '412x915': grande531};
const _escalas = [1.0, 2.0];

void main() {
  // ---------------------------------------------------------------------------------------------
  // 7 · Tamaños: cada estado, 360×640 y 412×915, texto 1,0 y 2,0, sin overflow ni texto cortado.
  // ---------------------------------------------------------------------------------------------
  group('Matriz de estados', () {
    for (final estado in Estado531.values) {
      for (final t in _tamanos.entries) {
        for (final escala in _escalas) {
          testWidgets('${estado.titulo} · ${t.key} · ×$escala', (tester) async {
            await llegar531(tester, estado, tamano: t.value, escala: escala);
            expect(tester.takeException(), isNull, reason: 'overflow o error de render');
            sinTextoCortado531(tester);
            await capturar531(tester, '${estado.name}_${t.key}_x${escala.toStringAsFixed(0)}');
          });
        }
      }
    }
  });

  group('Texto muy grande y pantalla chica', () {
    testWidgets(
      'la confirmación de salida a 360×640 y texto 3,0 no desborda',
      (tester) async {
        await llegar531(tester, Estado531.confirmaSalida, tamano: chico531, escala: 3);
        expect(tester.takeException(), isNull, reason: 'el AlertDialog no se desplaza');
      },
      skip: !conHallazgos,
    ); // skip: QA #158 — el diálogo de salida (AlertDialog sin scrollable) desborda a 3,0
    testWidgets('la confirmación de salida a 320×568 y texto 2,0 no desborda', (tester) async {
      await llegar531(tester, Estado531.confirmaSalida, tamano: const Size(320, 568), escala: 2);
      expect(tester.takeException(), isNull, reason: 'el AlertDialog no se desplaza');
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 1 · Criterios de aceptación con el texto de la HU.
  // ---------------------------------------------------------------------------------------------
  group('HU-VEN-001 · criterios de aceptación', () {
    testWidgets('Venta simple con 3 libros: el monto es la suma, se guarda y se encola', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      final salida = await montarNuevaVenta(tester, e);
      await tocar(tester, find.text('Libros'));
      for (var i = 0; i < 3; i++) {
        await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
      }
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      await escribir(tester, campo531('venta_talonario'), 'T-100');

      expect(find.text(r'$ 6.000'), findsWidgets);
      await tocar(tester, cta531);

      final r = e.ventas.recibidas.single;
      expect(r.venta.numeroTalonario, 'T-100');
      expect(r.venta.montoTotalCentavos, 600000);
      expect(r.items.single.cantidad, 3);
      expect(salida.cerrada, isTrue);
    });

    testWidgets('Venta de un combo fijo: aparece como un solo ítem con el precio del combo', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await tocar(tester, find.text('Pack Familia'));
      await tocar(tester, find.text(TextosVenta.armarLaColeccion));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      await escribir(tester, campo531('venta_talonario'), 'T-101');

      expect(find.text(r'$ 3.000'), findsWidgets);
      expect(find.byKey(const Key('venta_total')), findsOneWidget);
      await tocar(tester, cta531);

      final r = e.ventas.recibidas.single;
      expect(r.items, hasLength(1));
      expect(r.venta.montoTotalCentavos, 300000);
    });

    testWidgets('Talonario duplicado: bloquea con el texto del canvas (decisión del 23/10)', (
      tester,
    ) async {
      await llegar531(tester, Estado531.a11TalonarioRepetido);
      expect(
        find.text('Ya usaste el talonario 0042 este año (venta del 12/03). Revisá el número.'),
        findsOneWidget,
      );
      expect(habilitado531(tester), isFalse);
    });

    testWidgets('Producto sin precio en mi ciudad: no aparece en el selector', (tester) async {
      final base = catalogoDeVentas();
      await montarNuevaVenta(
        tester,
        EntornoDeVenta(
          catalogo: CatalogoLocal(
            productos: base.productos,
            combos: base.combos,
            generales: [
              for (final g in base.generales)
                if (g.productoId != 'p-nuestra-salud') g,
            ],
          ),
        ),
      );
      await tocar(tester, find.text('Revistas'));
      expect(find.text('Vida Feliz'), findsOneWidget);
      expect(find.text('Nuestra Salud'), findsNothing);
    });

    testWidgets(
      'Producto sin precio: «un mensaje sugiere Pedile al coordinador que configure el precio»',
      (tester) async {
        final base = catalogoDeVentas();
        await montarNuevaVenta(
          tester,
          EntornoDeVenta(
            catalogo: CatalogoLocal(
              productos: base.productos,
              combos: base.combos,
              generales: [
                for (final g in base.generales)
                  if (g.productoId != 'p-vida-feliz' && g.productoId != 'p-nuestra-salud') g,
              ],
            ),
          ),
        );
        await tocar(tester, find.text('Revistas'));
        expect(find.textContaining('coordinador'), findsOneWidget);
      },
      // La HU: «un mensaje sugiere "Pedile al coordinador que configure el precio"». La pantalla dice
      // «Si esperabas verlos, puede que no tengan precio en esta ciudad» (sin la salida) y, con el
      // producto suelto sin precio dentro de una categoría con otros, no dice nada.
      skip:
          !conHallazgos, // skip: QA #158 — la HU pide sugerir «Pedile al coordinador que configure el precio»
    );

    testWidgets('Monto manual: queda la diferencia anotada y el aviso al coordinador', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      await llegar531(tester, Estado531.a12MontoConMotivo, entorno: e);
      expect(find.text('Tu coordinador va a ver que lo cambiaste.'), findsOneWidget);
      expect(
        find.text('Tu coordinador va a leer este motivo. No pongas datos del cliente.'),
        findsOneWidget,
      );
      await tocar(tester, cta531);
      expect(e.ventas.recibidas.single.diferencia, -40000);
      expect(e.ventas.recibidas.single.venta.montoTotalCentavos, 850000);
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 3 · Avisos de error: que se vean donde la colportora está mirando.
  // ---------------------------------------------------------------------------------------------
  group('Avisos de error', () {
    testWidgets('27A·13 a 360×640 con texto 2,0 y la lista abajo: el aviso está a la vista', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      e.ventas.respuesta = const FailureVentaNoGuardada();
      await montarNuevaVenta(tester, e, tamano: chico531, escala: 2);
      await ventaConColeccion531(tester);
      await alFinal531(tester);
      await tester.tap(cta531);
      await asentar(tester);

      // El guardado falló: el botón fijo ya dice «Reintentar»…
      expect(find.text('Reintentar'), findsOneWidget);
      // …pero el aviso que explica qué pasó no está a la vista (la lista lo desarma al estar abajo).
      expect(
        enVistaEnLaLista531(tester, find.byKey(const Key('venta_error'))),
        isTrue,
        reason: 'el aviso queda fuera de la parte visible de la lista',
      );
    });

    testWidgets('27A·13 a 412×915 con texto 1,0 y 3 renglones: el aviso está a la vista', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      e.ventas.respuesta = const FailureVentaNoGuardada();
      await montarNuevaVenta(tester, e, tamano: grande531);
      await ventaConColeccion531(tester);
      await tocar(tester, find.text('+ Agregar'));
      await tocar(tester, find.text('Revistas'));
      await tocar(tester, find.byTooltip('Uno más de Vida Feliz'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      await alFinal531(tester);
      await tester.tap(cta531);
      await asentar(tester);

      expect(find.byKey(const Key('venta_error')), findsOneWidget);
      expect(enVistaEnLaLista531(tester, find.byKey(const Key('venta_error'))), isTrue);
    });

    testWidgets('«Reintentar» después de la falla deja guardar la misma venta y no duplica', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      e.ventas.respuesta = const FailureVentaNoGuardada();
      final salida = await montarNuevaVenta(tester, e);
      await ventaConColeccion531(tester);
      await tocar(tester, cta531);
      expect(find.text('Reintentar'), findsOneWidget);
      e.ventas.respuesta = null;
      await tocar(tester, cta531);
      expect(salida.cerrada, isTrue);
      expect(e.ventas.recibidas.map((r) => r.venta.id).toSet(), hasLength(1));
    });

    testWidgets(
      'con el botón apagado por un talonario repetido, abajo no dice por qué',
      (tester) async {
        await llegar531(tester, Estado531.a11TalonarioRepetido, tamano: chico531, escala: 2);
        await alFinal531(tester);

        expect(habilitado531(tester), isFalse);
        final error = find.textContaining('Ya usaste el talonario');
        // El error está en el campo de arriba: a 2,0 y con la lista abajo no se ve cuando el botón está apagado.
        expect(
          enVistaEnLaLista531(tester, error),
          isTrue,
          reason: 'el botón está apagado y la razón no se ve sin subir la lista',
        );
      },
      skip: !conHallazgos,
    ); // skip: QA #158 — «Registrar venta» apagado por talonario repetido sin razón a la vista
  });

  // ---------------------------------------------------------------------------------------------
  // 4 · Validación de entradas.
  // ---------------------------------------------------------------------------------------------
  group('Validación de entradas', () {
    Future<EntornoDeVenta> venta(WidgetTester tester, {String talonario = ''}) async {
      final e = EntornoDeVenta();
      await montarNuevaVenta(tester, e);
      await ventaConColeccion531(tester, talonario: talonario);
      return e;
    }

    testWidgets('talonario vacío o solo espacios: no deja registrar y dice por qué', (
      tester,
    ) async {
      final e = await venta(tester);
      expect(habilitado531(tester), isFalse);
      expect(find.text(TextosVenta.talonarioVacio), findsOneWidget);
      await escribir(tester, campo531('venta_talonario'), '     ');
      expect(habilitado531(tester), isFalse);
      expect(find.text(TextosVenta.talonarioVacio), findsOneWidget);
      await tester.tap(cta531, warnIfMissed: false);
      await asentar(tester);
      expect(e.ventas.recibidas, isEmpty);
    });

    testWidgets('talonario con espacios en los bordes se guarda recortado', (tester) async {
      final e = await venta(tester, talonario: '  T-100  ');
      await tocar(tester, cta531);
      expect(e.ventas.recibidas.single.venta.numeroTalonario, 'T-100');
    });

    testWidgets('talonario pegado de 200 caracteres: el campo corta en 30 y se registra', (
      tester,
    ) async {
      final e = await venta(tester, talonario: 'A' * 200);
      expect(tester.widget<TextField>(campo531('venta_talonario')).controller!.text.length, 30);
      await tocar(tester, cta531);
      expect(e.ventas.recibidas.single.venta.numeroTalonario, 'A' * 30);
    });

    testWidgets('talonario con caracteres especiales y emoji se guarda tal cual', (tester) async {
      final e = await venta(tester, talonario: "T/100-ñ'\"<b>🙂");
      await tocar(tester, cta531);
      expect(e.ventas.recibidas.single.venta.numeroTalonario, "T/100-ñ'\"<b>🙂");
    });

    testWidgets(
      '30 emoji compuestos (cada uno son varios puntos de código): no deja un error sin salida',
      (tester) async {
        final e = await venta(tester, talonario: '👨‍👩‍👧' * 30);
        await tocar(tester, cta531);
        // O se guarda, o el campo lo rechaza: nunca «No pudimos guardar… probá de nuevo» que no sirve.
        final fallo = find.byKey(const Key('venta_error'));
        expect(
          fallo.evaluate().isEmpty || e.ventas.recibidas.isNotEmpty,
          isTrue,
          reason: 'el aviso de «probá de nuevo» sale por una validación que reintentar no arregla',
        );
        expect(habilitado531(tester), isTrue);
      },
      skip: !conHallazgos,
    ); // skip: QA #158 — 30 emoji compuestos pasan el campo y la validación los rechaza

    for (final malo in ['abc', '-100', '8.50', '8,5,5', r'$$', '1e3', '99999999999', '']) {
      testWidgets('monto «$malo»: no es un monto, no deja registrar y lo explica en el campo', (
        tester,
      ) async {
        final e = await venta(tester, talonario: '0042');
        await tocar(tester, find.text('Cambiar el monto'));
        await escribir(tester, campo531('venta_monto'), malo);
        await escribir(tester, campo531('venta_motivo'), 'un motivo');

        expect(find.text(TextosVenta.montoInvalido), findsOneWidget);
        expect(habilitado531(tester), isFalse);
        await tester.tap(cta531, warnIfMissed: false);
        await asentar(tester);
        expect(e.ventas.recibidas, isEmpty);
      });
    }

    testWidgets('monto «0»: se acepta con motivo y se guarda una venta de \$ 0 (a confirmar)', (
      tester,
    ) async {
      final e = await venta(tester, talonario: '0042');
      await tocar(tester, find.text('Cambiar el monto'));
      await escribir(tester, campo531('venta_monto'), '0');
      await escribir(tester, campo531('venta_motivo'), 'regalo');
      // Documenta lo que hoy pasa; ver la pregunta del QA sobre el monto 0.
      if (habilitado531(tester)) {
        await tocar(tester, cta531);
        expect(e.ventas.recibidas.single.venta.montoTotalCentavos, 0);
      }
    });

    testWidgets('motivo pegado de 800 caracteres con emoji: llega cortado a 500 puntos de código', (
      tester,
    ) async {
      final e = await venta(tester, talonario: '0042');
      await tocar(tester, find.text('Cambiar el monto'));
      await escribir(tester, campo531('venta_monto'), '8500');
      await escribir(tester, campo531('venta_motivo'), '🙂' * 800);
      await tocar(tester, cta531);
      final motivo = e.ventas.recibidas.single.venta.motivoMontoManual!;
      expect(motivo.runes.length, lessThanOrEqualTo(500));
    });

    testWidgets('después de un error al guardar, lo tipeado (monto y motivo) no se pierde', (
      tester,
    ) async {
      final e = await venta(tester, talonario: '0042');
      await tocar(tester, find.text('Cambiar el monto'));
      await escribir(tester, campo531('venta_monto'), '8500');
      await escribir(tester, campo531('venta_motivo'), 'descuento');
      e.ventas.respuesta = const FailureVentaNoGuardada();
      await tocar(tester, cta531);

      expect(tester.widget<TextField>(campo531('venta_monto')).controller!.text, '8500');
      expect(tester.widget<TextField>(campo531('venta_motivo')).controller!.text, 'descuento');
      expect(tester.widget<TextField>(campo531('venta_talonario')).controller!.text, '0042');
      expect(habilitado531(tester), isTrue);
    });

    testWidgets('el monto a mano no se queda viejo si después se agrega algo a la venta', (
      tester,
    ) async {
      await venta(tester, talonario: '0042');
      await tocar(tester, find.text('Cambiar el monto'));
      await escribir(tester, campo531('venta_monto'), '8500');
      await escribir(tester, campo531('venta_motivo'), 'descuento');
      await tocar(tester, find.text('+ Agregar'));
      await tocar(tester, find.text('Revistas'));
      await tocar(tester, find.byTooltip('Uno más de Vida Feliz'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));

      // El calculado subió a $ 9.020: lo que se cobra sigue siendo lo que escribió, a la vista.
      expect(find.text(r'$ 9.020'), findsWidgets);
      expect(tester.widget<TextField>(campo531('venta_monto')).controller!.text, '8500');
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 5b · Casos límite del flujo.
  // ---------------------------------------------------------------------------------------------
  group('Casos límite', () {
    testWidgets(
      '«+ Agregar» mientras se guarda no deja la pantalla de agregar con la venta guardada',
      (tester) async {
        final e = EntornoDeVenta();
        final espera = Completer<void>();
        e.ventas.compuerta = espera.future;
        final salida = await montarNuevaVenta(tester, e);
        await ventaConColeccion531(tester);

        await tester.tap(cta531);
        await tester.pump();
        await tester.ensureVisible(find.text('+ Agregar'));
        await tester.tap(find.text('+ Agregar'), warnIfMissed: false);
        await asentar(tester);
        espera.complete();
        await asentar(tester);

        expect(tester.takeException(), isNull);
        expect(e.ventas.recibidas, hasLength(1));
        expect(salida.cerrada, isTrue, reason: 'la pantalla de la venta tiene que cerrarse');
        expect(find.byKey(const Key('agregar_productos_pagina')), findsNothing);
      },
    );

    testWidgets(
      'volver mientras se guarda: no dice «se pierde lo que cargaste» si ya se está guardando',
      (tester) async {
        final e = EntornoDeVenta();
        e.ventas.compuerta = Completer<void>().future;
        await montarNuevaVenta(tester, e);
        await ventaConColeccion531(tester);
        await tester.tap(cta531);
        await tester.pump();

        await tester.binding.handlePopRoute();
        await asentar(tester);

        expect(find.text(TextosVenta.salirTitulo), findsNothing);
      },
      skip: !conHallazgos,
    ); // skip: QA #158 — con el guardado en curso, «Volver» ofrece salir y perder lo cargado

    testWidgets('falla a mitad de la acción: ningún estado de «guardando» queda trabado', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      e.ventas.respuesta = const FailureVentaNoGuardada();
      await montarNuevaVenta(tester, e);
      await ventaConColeccion531(tester);
      for (var i = 0; i < 3; i++) {
        await tocar(tester, cta531);
        expect(habilitado531(tester), isTrue, reason: 'intento ${i + 1}');
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.widget<TextField>(campo531('venta_talonario')).enabled, isTrue);
      }
    });

    testWidgets(
      'quitar todo lo que se vende con el monto abierto y volver a agregar parte limpio',
      (tester) async {
        final e = EntornoDeVenta();
        await montarNuevaVenta(tester, e);
        await ventaConColeccion531(tester);
        await tocar(tester, find.text('Cambiar el monto'));
        await escribir(tester, campo531('venta_monto'), '8500');
        await escribir(tester, campo531('venta_motivo'), 'descuento');
        await tocar(tester, find.byTooltip(TextosVenta.quitar));
        expect(find.text('Elegí al menos un producto para registrar la venta.'), findsNothing);

        await tocar(tester, find.text('Revistas'));
        await tocar(tester, find.byTooltip('Uno más de Vida Feliz'));
        await tocar(tester, find.text(TextosVenta.agregarALaVenta));

        // La revista vale $ 120: el monto de $ 8.500 de la venta anterior no puede cobrarse sin avisar.
        final monto = find.byKey(const Key('venta_monto'));
        if (monto.evaluate().isNotEmpty) {
          expect(
            tester.widget<TextField>(campo531('venta_monto')).controller!.text,
            isNot('8500'),
            reason: 'quedó el monto a mano de una venta que ya no existe',
          );
        }
      },
      skip: !conHallazgos,
    ); // skip: QA #158 — el monto a mano de una venta quitada queda abierto al agregar otra

    testWidgets('«Continuar» y «Terminar» de 27A·14: un segundo toque no repite la acción', (
      tester,
    ) async {
      var seguimientos = 0;
      var terminos = 0;
      tester.view.physicalSize = chico531;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: VentaRegistradaPage(
            guardada: _guardada(),
            nombreDelCliente: 'María Fernández',
            conEntrega: true,
            conCobro: true,
            alContinuar: (_) => seguimientos++,
            alTerminar: () => terminos++,
          ),
        ),
      );
      await asentar(tester);
      await tester.tap(find.text('Continuar'));
      await tester.tap(find.text('Continuar'), warnIfMissed: false);
      await tester.tap(find.text('Terminar sin entregar ni cobrar'), warnIfMissed: false);
      await asentar(tester);
      expect(seguimientos, 1);
      expect(terminos, 0);
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 5 · Navegación.
  // ---------------------------------------------------------------------------------------------
  group('Navegación', () {
    testWidgets('el botón de volver del sistema en 27A·14 no deja salir sin elegir', (
      tester,
    ) async {
      await llegar531(tester, Estado531.a14Sola);
      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(find.byKey(const Key('venta_registrada_pagina')), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
    });

    testWidgets('desde el armado de la colección, volver regresa a elegir sin perder la venta', (
      tester,
    ) async {
      await llegar531(tester, Estado531.a02Armado);
      await tocar(tester, find.byTooltip(TextosVenta.volver));
      expect(find.byKey(const Key('armar_coleccion_pagina')), findsNothing);
      expect(find.text(TextosVenta.armarLaColeccion), findsOneWidget);
    });

    testWidgets('la hoja del libro se cierra con volver y deja el armado como estaba', (
      tester,
    ) async {
      await llegar531(tester, Estado531.a03HojaLibro);
      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(find.byKey(const Key('venta_hoja_libro_busqueda')), findsNothing);
      expect(find.text('Elegir del catálogo'), findsNWidgets(2));
    });

    testWidgets('27A·10: la ✕ de arriba y «Volver» cierran sin pedir confirmación', (tester) async {
      await llegar531(tester, Estado531.a10Campania);
      await tocar(tester, find.byTooltip(TextosVenta.volver).first);
      expect(find.byKey(const Key('nueva_venta_pagina')), findsNothing);
    });

    testWidgets('cargando: se puede volver sin confirmar', (tester) async {
      await llegar531(tester, Estado531.cargando);
      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(find.byKey(const Key('nueva_venta_pagina')), findsNothing);
    });

    testWidgets('error de lectura: «Reintentar» carga los precios', (tester) async {
      await llegar531(tester, Estado531.errorDeLectura);
      expect(find.text(TextosVenta.errorPrecios), findsOneWidget);
      await tocar(tester, find.byKey(const Key('venta_aviso_accion')));
      expect(find.text('Colección de 2 libros'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 8 · Privacidad.
  // ---------------------------------------------------------------------------------------------
  group('Privacidad', () {
    test('toString de los argumentos y del estado de la venta no lleva datos del cliente', () {
      const cliente = ClienteDeLaVenta(
        espacioPersonaId: 'ep-1',
        nombre: 'María Fernández',
        direccion: 'Mataojo 2044 · Depto 3B',
      );
      const args = ArgumentosDeVenta(colportorId: 'col-1', cliente: cliente);
      final estado = const NuevaVentaState().copiar(
        talonario: 'T-100',
        motivo: 'descuento por pago en efectivo',
        montoTexto: '8500',
      );
      for (final s in [cliente.toString(), args.toString(), estado.toString()]) {
        expect(s, isNot(contains('María')));
        expect(s, isNot(contains('Mataojo')));
        expect(s, isNot(contains('descuento')));
      }
    });

    test('toString de la falla de talonario repetido no lleva datos del cliente', () {
      final f = FailureTalonarioRepetido(numero: '0042', ventaDel: DateTime(2026, 3, 12));
      expect(f.toString(), isNot(contains('María')));
    });
  });
}

VentaGuardada _guardada() => VentaGuardada(
  venta: ventaDe('v-1', talonario: '0042', monto: 890000),
  items: const [],
);
