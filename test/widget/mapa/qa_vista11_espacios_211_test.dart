// QA de la vista 11 «Espacios» (HU-UBI-007, #211, PR #468). Complementa a `hoja_ubicacion_test.dart` y
// `hoja_depto_test.dart` (Ahem, un solo tamaño) con lo que esos no miden:
//  - la matriz estados (13) × 360×640 y 412×915 × texto 1,0 y 2,0 con las FUENTES REALES de
//    `assets/fonts/`: sin overflow, sin texto fuera de la pantalla, y una captura por celda con
//    `--dart-define=QA_CAPTURAS=true` (a `.dart_tool/qa_capturas/`, gitignored);
//  - los textos literales del canvas y de la HU;
//  - validación de entradas (solo espacios, pegado largo, emoji, saltos de línea);
//  - lo tipeado que no se pierde, el atrás en cada estado, el cambio de tamaño con la hoja abierta;
//  - casos límite: la posición de la lista tras editar, la última baja sin personas, los avisos
//    como región viva para el lector de pantalla;
//  - privacidad: `toString()` del espacio.
// Los hallazgos van con `skip:` y el motivo `QA #211`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista11_211_arnes.dart';

const _repetido102 = 'Ya existe el departamento 102 en este edificio.';
const _avisoDeLaHu =
    'Este espacio tiene 3 personas. Sus datos se conservarán pero el espacio quedará '
    'marcado como baja.';
const _ultimoDeLaHu =
    'No podés borrar el último espacio activo con personas. Agregá otro o reubicá las personas '
    'primero.';

/// `true` corre los tests que documentan un hallazgo (hoy con `skip`).
const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

String _nombre(EstadoV11 e, Size t, double escala) =>
    '${e.name}_${t.width.toInt()}x${t.height.toInt()}_x$escala';

void main() {
  // --------------------------------------------------------------- 1. matriz
  group('matriz de estados × tamaños × escala (fuentes reales)', () {
    for (final tamano in [telefonoChico211, telefonoGrande211]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in EstadoV11.values) {
          testWidgets('dado que la hoja está en «${estado.rotulo}» a ${tamano.width.toInt()}×'
              '${tamano.height.toInt()} con texto ×$escala, cuando se dibuja, entonces no hay overflow '
              'ni texto fuera de la pantalla', (tester) async {
            await llegarA(tester, estado, tamano: tamano, escala: escala);
            await tester.pump(const Duration(milliseconds: 400));

            expect(tester.takeException(), isNull);
            expectSinTextoFueraDeLosCostados211(tester, tamano);
            await capturar211(tester, _nombre(estado, tamano, escala));
          });
        }
      }
    }

    // El teclado abierto (280 dp) con el texto grande: el formulario sigue siendo alcanzable.
    for (final estado in [EstadoV11.alta, EstadoV11.repetido, EstadoV11.edicion]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets(
          'dado que «${estado.rotulo}» tiene el teclado abierto a 360×640 con texto ×$escala, '
          'entonces no hay overflow y los botones se alcanzan',
          (tester) async {
            await llegarA(tester, estado, tamano: telefonoChico211, escala: escala);
            tester.view.viewInsets = const FakeViewPadding(bottom: 280);
            addTearDown(tester.view.resetViewInsets);
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            expect(tester.takeException(), isNull);

            final boton = estado == EstadoV11.edicion ? botonGuardarDepto : botonAgregar;
            await tester.ensureVisible(boton);
            await tester.pump();
            final r = tester.getRect(boton);
            expect(
              r.bottom <= 640 - 280 + 0.5,
              isTrue,
              reason: 'el botón queda bajo el teclado: $r',
            );
            expect(tester.takeException(), isNull);
            await capturar211(tester, 'teclado_${estado.name}_x$escala');
          },
        );
      }
    }
  });

  // ------------------------------------------------------- visual
  group('revisión visual', () {
    for (final tipo in [TipoUbicacion.edificio, TipoUbicacion.casa]) {
      testWidgets(
        '«Editar ${tipo.name}» tiene aire entre el texto y el borde del botón, como '
        '«+ Departamento»',
        (tester) async {
          await llegarA(tester, tipo == TipoUbicacion.casa ? EstadoV11.casa : EstadoV11.lista);
          final boton = botonEditarUbicacion;
          final texto = find.descendant(of: boton, matching: find.byType(Text));
          final rb = tester.getRect(boton);
          final rt = tester.getRect(texto);

          expect(rt.left - rb.left, greaterThanOrEqualTo(12), reason: 'botón $rb, texto $rt');
          expect(rb.right - rt.right, greaterThanOrEqualTo(12), reason: 'botón $rb, texto $rt');
        },
        // skip: QA #211 — el `outlinedButtonTheme` no tiene padding horizontal (pensado para botones
        // de ancho completo) y «Editar edificio» / «Editar casa» van de ancho propio: el texto toca
        // el borde.
        skip: !_verHallazgos,
      );
    }
  });

  // ----------------------------------------------------- 2. textos literales
  group('textos literales del canvas y de la HU', () {
    testWidgets('11·01: rótulo, título, cuenta, botones y grupos del canvas', (tester) async {
      await llegarA(tester, EstadoV11.lista);

      expect(find.text('EDIFICIO · A 25 M'), findsOneWidget);
      expect(find.text('Mataojo 2044'), findsOneWidget);
      expect(find.text('6 deptos'), findsOneWidget);
      expect(find.text('+ Departamento'), findsOneWidget);
      expect(find.text('Editar edificio'), findsOneWidget);
      expect(find.text('PISO 1'), findsOneWidget);
      expect(find.text('PISO 2'), findsOneWidget);
      expect(find.text('SIN PISO'), findsOneWidget);
      expect(find.text('Depto 101'), findsOneWidget);
      // La lista es perezosa y la hoja arranca a la mitad: se baja hasta el final.
      tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!.jumpTo(5000);
      await asentarHoja(tester);
      expect(find.text('Depto PB-A'), findsOneWidget);
      expect(find.text('Sin número'), findsOneWidget);
    });

    testWidgets('11·02: rótulo, título, etiquetas y botones del canvas', (tester) async {
      await llegarA(tester, EstadoV11.alta);

      expect(find.text('MATAOJO 2044 · EDIFICIO'), findsOneWidget);
      expect(find.text('Nuevo departamento'), findsOneWidget);
      expect(find.text('NÚMERO · OBLIGATORIO'), findsOneWidget);
      expect(find.text('PISO · OPCIONAL'), findsOneWidget);
      expect(find.text('Agregar'), findsOneWidget);
      expect(find.text('Agregar y cargar otro'), findsOneWidget);
    });

    testWidgets('11·03: el aviso y el enlace del canvas', (tester) async {
      await llegarA(tester, EstadoV11.repetido);

      expect(find.text(_repetido102), findsOneWidget);
      expect(find.text('Ver depto 102 ›'), findsOneWidget);
    });

    testWidgets('HU «Baja de espacio con personas»: el aviso literal con el número de personas', (
      tester,
    ) async {
      await llegarA(tester, EstadoV11.avisoPersonas);
      expect(find.text(_avisoDeLaHu), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Dar de baja'), findsOneWidget);
    });

    testWidgets('HU «único espacio activo con personas»: el bloqueo literal', (tester) async {
      await llegarA(tester, EstadoV11.bajaBloqueada);
      expect(find.text(_ultimoDeLaHu), findsOneWidget);
    });

    testWidgets('HU «Alta de espacio en EDIFICIO»: «Apto 5B» en un edificio sin espacios se crea y '
        'la lista lo muestra', (tester) async {
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, 'Apto 5B');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(m.repo.activos.single.numeroDepto, 'Apto 5B');
      expect(find.text('Depto Apto 5B'), findsOneWidget);
      expect(find.text('1 depto'), findsOneWidget);
      expect(find.byKey(ClavesHojaUbicacion.vacio), findsNothing);
    });

    test('el generador real de ids da UUID v7 (HU: «se crea localmente con UUID v7»)', () {
      // El arnés reemplaza el generador; este test usa el del cableado real.
      final contenedor = ProviderContainer();
      addTearDown(contenedor.dispose);
      final id = contenedor.read(generadorIdEspacioProvider)();
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
        reason: id,
      );
    });
  });

  // ------------------------------------------------- 3. regla del repetido
  group('regla de «repetido» (canvas 11: «PB-A» y «pb a» son el mismo)', () {
    testWidgets('el ejemplo literal del canvas: con «PB-A» cargado, «pb a» es repetido', (
      tester,
    ) async {
      final m = await llegarA(tester, EstadoV11.lista);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, 'pb a');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(find.text('Ya existe el departamento PB-A en este edificio.'), findsOneWidget);
      expect(m.repo.activos.where((e) => e.numeroDepto == 'pb a'), isEmpty);
    });

    testWidgets('«PBA» y «PB—A» (guion largo del autocorrector) también son el mismo', (
      tester,
    ) async {
      final m = await llegarA(tester, EstadoV11.lista);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, 'PBA');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      expect(find.text('Ya existe el departamento PB-A en este edificio.'), findsOneWidget);

      await escribir(tester, campoNumero, 'PB${String.fromCharCode(0x2014)}A');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      expect(find.text('Ya existe el departamento PB-A en este edificio.'), findsOneWidget);
      expect(m.repo.activos.where((e) => e.numeroDepto != 'PB-A' && e.clave == 'pba'), isEmpty);
    });

    testWidgets('espacios y mayúsculas sí se ignoran: «pb  A» vs «PB A»', (tester) async {
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, 'PB A');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);
      await escribir(tester, campoNumero, 'pb  a');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(find.text('Ya existe el departamento PB A en este edificio.'), findsOneWidget);
      expect(m.repo.activos, hasLength(1));
    });
  });

  // -------------------------------------------------------- 4. validación
  group('validación de entradas', () {
    testWidgets('número solo con espacios: no guarda, pide el número y el botón sigue disponible', (
      tester,
    ) async {
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '     ');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(find.text('Ingresá el número o nombre del espacio.'), findsOneWidget);
      expect(m.repo.espacios, isEmpty);
      expect(habilitado(tester, botonAgregar), isTrue);
      expect(habilitado(tester, botonAgregarYCargarOtro), isTrue);
    });

    testWidgets('número vacío con piso escrito: el piso no se pierde al avisar', (tester) async {
      await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      await escribir(tester, campoPiso, '3');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(find.text('Ingresá el número o nombre del espacio.'), findsOneWidget);
      expect(textoDe(tester, campoPiso), '3');
    });

    testWidgets('piso solo con espacios: el depto queda sin piso (SIN PISO)', (tester) async {
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '7');
      await escribir(tester, campoPiso, '    ');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(m.repo.activos.single.piso, isNull);
      expect(find.text('SIN PISO'), findsOneWidget);
    });

    testWidgets('texto pegado muy largo: el número se corta en 40 y el piso en 20', (tester) async {
      await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, 'A' * 500);
      await escribir(tester, campoPiso, '9' * 500);

      expect(textoDe(tester, campoNumero).length, topeNumeroDepto);
      expect(textoDe(tester, campoPiso).length, topePisoDepto);
    });

    testWidgets('pegado en varias líneas: queda en una sola línea', (tester) async {
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '1\n02\r\n3');
      expect(textoDe(tester, campoNumero).contains('\n'), isFalse);
      expect(textoDe(tester, campoNumero).contains('\r'), isFalse);
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      expect(m.repo.activos.single.numeroDepto!.contains('\n'), isFalse);
    });

    testWidgets('emoji y caracteres especiales en el número: se guardan y se dibujan sin romper', (
      tester,
    ) async {
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '🏠 <b>3º</b> & "ñ"');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(tester.takeException(), isNull);
      expect(m.repo.activos, hasLength(1));
      expect(find.textContaining('🏠 <b>3º</b> & "ñ"'), findsWidgets);
    });

    testWidgets('el número y el piso de 40 y 20 caracteres se dibujan en la lista sin desbordar a '
        '360×640 ×2', (tester) async {
      final m = await llegarA(tester, EstadoV11.vacio, tamano: telefonoChico211, escala: 2);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, 'W' * 40);
      await escribir(tester, campoPiso, 'M' * 20);
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(m.repo.activos, hasLength(1));
      expect(tester.takeException(), isNull);
      expectSinTextoFueraDeLosCostados211(tester, telefonoChico211);
      await capturar211(tester, 'largos_360x640_x2.0');
    });

    testWidgets('dos envíos antes de que termine el primero y falla a mitad: ninguno se pisa y '
        'nada queda en «Agregando…»', (tester) async {
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      final espera = Completer<void>();
      m.repo.espera = espera;
      m.repo.fallas.add(const FailureInesperado(causa: 'x'));
      await escribir(tester, campoNumero, '12');
      await tester.tap(botonAgregar);
      await tester.pump();
      expect(find.text('Agregando…'), findsOneWidget);
      expect(habilitado(tester, botonAgregarYCargarOtro), isFalse);
      await tester.tap(botonAgregarYCargarOtro, warnIfMissed: false);
      await tester.pump();
      espera.complete();
      await asentarHoja(tester);

      expect(m.repo.llamadas, ['agregar:nuevo-1']);
      expect(find.text('Agregando…'), findsNothing);
      expect(habilitado(tester, botonAgregar), isTrue);
      expect(habilitado(tester, botonAgregarYCargarOtro), isTrue);
      expect(textoDe(tester, campoNumero), '12');
    });
  });

  // --------------------------------------- 5. lo tipeado no se pierde
  group('lo tipeado no se pierde', () {
    testWidgets('tras una falla al guardar el número y el piso siguen escritos', (tester) async {
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      m.repo.fallas.add(const FailureInesperado(causa: 'disco'));
      await escribir(tester, campoNumero, '301');
      await escribir(tester, campoPiso, '3');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(find.text('No pudimos guardar el departamento. Probá de nuevo.'), findsOneWidget);
      expect(textoDe(tester, campoNumero), '301');
      expect(textoDe(tester, campoPiso), '3');
    });

    testWidgets('tras el repetido el número y el piso siguen escritos', (tester) async {
      await llegarA(tester, EstadoV11.repetido);
      expect(textoDe(tester, campoNumero), '102');
      expect(textoDe(tester, campoPiso), isEmpty);
    });

    testWidgets('el cambio de tamaño con la hoja abierta (girar el teléfono) conserva lo escrito', (
      tester,
    ) async {
      await llegarA(tester, EstadoV11.alta, tamano: telefonoGrande211);
      await escribir(tester, campoNumero, '4C');
      await escribir(tester, campoPiso, '4');

      tester.view.physicalSize = const Size(915, 412);
      await asentarHoja(tester);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = telefonoChico211;
      await asentarHoja(tester);

      expect(tester.takeException(), isNull);
      expect(textoDe(tester, campoNumero), '4C');
      expect(textoDe(tester, campoPiso), '4');
    });

    testWidgets('con el texto al 200 % se puede escribir en el campo del número y no desborda', (
      tester,
    ) async {
      await llegarA(tester, EstadoV11.alta, escala: 2);
      await escribir(tester, campoNumero, '4C');
      expect(tester.takeException(), isNull);
      expect(textoDe(tester, campoNumero), '4C');
    });

    testWidgets(
      '«Agregar y cargar otro» conserva el piso y vacía el número; el foco vuelve al número',
      (tester) async {
        await llegarA(tester, EstadoV11.vacio);
        await abrirAltaDepto(tester);
        await escribir(tester, campoNumero, '11');
        await escribir(tester, campoPiso, '1');
        await tester.tap(botonAgregarYCargarOtro);
        await asentarHoja(tester);

        expect(textoDe(tester, campoNumero), isEmpty);
        expect(textoDe(tester, campoPiso), '1');
        final foco = tester.widget<TextField>(campoNumero).focusNode!;
        expect(foco.hasFocus, isTrue);
      },
    );
  });

  // ------------------------------------------------------- 6. navegación
  group('navegación: volver atrás en cada estado', () {
    testWidgets('el atrás del sistema en la hoja del alta la cierra y deja la lista', (
      tester,
    ) async {
      await llegarA(tester, EstadoV11.alta);
      await tester.binding.handlePopRoute();
      await asentarHoja(tester);

      expect(hojaDepto, findsNothing);
      expect(hojaUbicacion, findsOneWidget);
      expect(habilitado(tester, find.byKey(ClavesHojaUbicacion.agregarDepto)), isTrue);
    });

    testWidgets('el atrás en el repetido cierra la hoja sin guardar', (tester) async {
      final m = await llegarA(tester, EstadoV11.repetido);
      await tester.binding.handlePopRoute();
      await asentarHoja(tester);

      expect(hojaDepto, findsNothing);
      expect(m.repo.activos, hasLength(6));
    });

    testWidgets(
      'el atrás en la pregunta de la baja la cancela: la hoja de edición sigue y se puede '
      'volver a intentar',
      (tester) async {
        final m = await llegarA(tester, EstadoV11.preguntaBaja);
        await tester.binding.handlePopRoute();
        await asentarHoja(tester);

        expect(find.text('Cancelar'), findsNothing);
        expect(hojaDepto, findsOneWidget);
        expect(habilitado(tester, botonDarDeBaja), isTrue);
        expect(habilitado(tester, botonGuardarDepto), isTrue);
        expect(m.repo.llamadas, isEmpty);
      },
    );

    testWidgets('el atrás en el aviso con personas la cancela sin dar de baja', (tester) async {
      final m = await llegarA(tester, EstadoV11.avisoPersonas);
      await tester.binding.handlePopRoute();
      await asentarHoja(tester);

      expect(hojaDepto, findsOneWidget);
      expect(habilitado(tester, botonDarDeBaja), isTrue);
      expect(m.repo.activos.any((e) => e.id == 'e-101'), isTrue);
    });

    testWidgets('el atrás en la hoja de la ubicación la cierra y devuelve null', (tester) async {
      final m = await llegarA(tester, EstadoV11.lista);
      await tester.binding.handlePopRoute();
      await asentarHoja(tester);

      expect(hojaUbicacion, findsNothing);
      expect(m.salidas, [null]);
    });

    testWidgets('el atrás en cargando y en error de lectura cierra la hoja', (tester) async {
      await llegarA(tester, EstadoV11.cargando);
      await tester.binding.handlePopRoute();
      await asentarHoja(tester);
      expect(hojaUbicacion, findsNothing);
    });

    testWidgets('tocar fuera de la hoja de la ubicación (la cortina) la cierra', (tester) async {
      await llegarA(tester, EstadoV11.lista);
      await tester.tapAt(const Offset(200, 20));
      await asentarHoja(tester);
      expect(hojaUbicacion, findsNothing);
    });
  });

  // ------------------------------------------------ 7. casos límite
  group('casos límite', () {
    testWidgets('editar un depto lejano de una lista de 200 no devuelve la lista al principio', (
      tester,
    ) async {
      final muchos = [
        for (var i = 1; i <= 200; i++)
          espacioDe('e-$i', '$i', piso: '${(i - 1) ~/ 10 + 1}', orden: i % 60),
      ];
      await montarHoja(tester, espacios: muchos, tamano: telefonoGrande211);
      final lista = find.byType(CustomScrollView);
      final controlador = tester.widget<CustomScrollView>(lista).controller!;
      controlador.jumpTo(5000);
      await asentarHoja(tester);
      final antes = controlador.offset;
      expect(antes, greaterThan(1000));

      final fila = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('ubicacion_hoja_fila_'),
      );
      // La hoja arranca a la mitad: se toca una fila que cae dentro de ella.
      final visible = fila
          .evaluate()
          .map((e) => find.byElementPredicate((x) => x == e))
          .firstWhere((f) => tester.getCenter(f).dy > 640);
      await tester.tap(visible);
      await asentarHoja(tester);
      await escribir(tester, campoPiso, '99');
      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);

      final despues = tester.widget<CustomScrollView>(lista).controller!.offset;
      expect(despues, greaterThan(500), reason: 'la lista volvió al principio (offset $despues)');
    });

    testWidgets('dar de baja el único depto sin personas: la hoja queda en «vacío», con «+ '
        'Departamento» disponible', (tester) async {
      final m = await montarHoja(tester, espacios: [espacioDe('e-1', '101', piso: '1')]);
      await abrirEdicionDepto(tester, 'e-1');
      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await asentarHoja(tester);

      expect(m.repo.activos, isEmpty);
      expect(find.byKey(ClavesHojaUbicacion.vacio), findsOneWidget);
      expect(find.text('0 deptos'), findsOneWidget);
      expect(habilitado(tester, botonAgregarDepto), isTrue);
    });

    testWidgets('«Agregar y cargar otro» deja la cuenta de la hoja de atrás al día', (
      tester,
    ) async {
      await llegarA(tester, EstadoV11.lista);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '301');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);
      await escribir(tester, campoNumero, '302');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);

      expect(find.text('8 deptos', skipOffstage: false), findsOneWidget);
    });

    testWidgets('la edición que cambia solo el piso no pide el número otra vez y no marca repetido '
        'contra sí mismo', (tester) async {
      final m = await llegarA(tester, EstadoV11.lista);
      await abrirEdicionDepto(tester, 'e-101');
      await escribir(tester, campoPiso, '5');
      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);

      expect(hojaDepto, findsNothing);
      expect(m.repo.espacios.firstWhere((e) => e.id == 'e-101').piso, '5');
      expect(find.text('PISO 5'), findsOneWidget);
    });

    testWidgets('la edición con el número de otro depto avisa y conserva lo escrito en el piso', (
      tester,
    ) async {
      await llegarA(tester, EstadoV11.lista);
      await abrirEdicionDepto(tester, 'e-101');
      await escribir(tester, campoNumero, '102');
      await escribir(tester, campoPiso, '7');
      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);

      expect(find.text(_repetido102), findsOneWidget);
      expect(textoDe(tester, campoPiso), '7');
      expect(habilitado(tester, botonGuardarDepto), isTrue);
    });

    testWidgets('la baja que falla después de confirmar: avisa y se puede reintentar', (
      tester,
    ) async {
      final m = await llegarA(tester, EstadoV11.preguntaBaja);
      m.repo.fallas.add(const FailureInesperado(causa: 'x'));
      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await asentarHoja(tester);

      expect(find.text('No pudimos dar de baja el departamento. Probá de nuevo.'), findsOneWidget);
      expect(habilitado(tester, botonDarDeBaja), isTrue);
      expect(find.text('Dando de baja…'), findsNothing);
      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await asentarHoja(tester);
      expect(m.repo.activos.any((e) => e.id == 'e-101'), isFalse);
    });

    testWidgets('la lista que falla al releer tras guardar no pierde el depto guardado', (
      tester,
    ) async {
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '55');
      m.repo.fallaAlListar = const FailureInesperado(causa: 'x');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(m.repo.activos, hasLength(1), reason: 'el depto quedó guardado');
      expect(find.byKey(ClavesHojaUbicacion.error), findsOneWidget);
      m.repo.fallaAlListar = null;
      await tester.tap(find.byKey(ClavesHojaUbicacion.reintentar));
      await asentarHoja(tester);
      expect(find.text('Depto 55'), findsOneWidget);
    });
  });

  // ---------------------------------------------- 8. lector de pantalla
  group('lector de pantalla', () {
    testWidgets('el aviso de repetido y el de falla son región viva', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA(tester, EstadoV11.repetido);
      expect(
        tester.getSemantics(find.text(_repetido102)),
        matchesSemantics(label: _repetido102, isLiveRegion: true),
      );
      h.dispose();
    });

    testWidgets('la falla al guardar es región viva', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA(tester, EstadoV11.fallaGuardado);
      final nodo = tester.getSemantics(find.byKey(ClavesHojaDepto.falla));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      h.dispose();
    });

    testWidgets('cada fila de la lista es un botón con «Depto N. Editar.» y acción de tocar', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarA(tester, EstadoV11.lista);
      final nodo = tester.getSemantics(filaDepto('e-101'));
      expect(nodo.label, 'Depto 101. Editar.');
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      h.dispose();
    });

    testWidgets('los botones de la hoja tienen nombre y acción de tocar', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA(tester, EstadoV11.alta);
      for (final k in [ClavesHojaDepto.agregar, ClavesHojaDepto.agregarYCargarOtro]) {
        final nodo = tester.getSemantics(find.byKey(k));
        expect(nodo.label, isNotEmpty);
        expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }
      h.dispose();
    });

    testWidgets(
      'los campos tienen su etiqueta en el nodo del campo',
      (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, EstadoV11.alta);
        expect(tester.getSemantics(campoNumero).label, contains('NÚMERO'));
        expect(tester.getSemantics(campoPiso).label, contains('PISO'));
        h.dispose();
      },
      // skip: QA #211 — el campo no tiene nombre accesible: la etiqueta «NÚMERO · OBLIGATORIO» es un
      // Text suelto y el lector dice «cuadro de edición» a secas.
      skip: !_verHallazgos,
    );
  });

  // ------------------------------- 8. re-verificación (d020957): lo que cambió tras la revisión
  group('«Depto N agregado.» visible tras «Agregar y cargar otro» (decisión QA P2)', () {
    for (final tamano in [telefonoChico211, telefonoGrande211]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets(
          'con un número de 40 caracteres a ${tamano.width.toInt()}×${tamano.height.toInt()} y '
          'texto ×$escala la línea cabe, está sobre el campo y no hay overflow',
          (tester) async {
            await llegarA(tester, EstadoV11.vacio, tamano: tamano, escala: escala);
            await abrirAltaDepto(tester);
            final largo = 'A' * 20 + 'B' * 20;
            await escribir(tester, campoNumero, largo);
            await tester.tap(botonAgregarYCargarOtro);
            await asentarHoja(tester);
            await tester.pump(const Duration(milliseconds: 400));

            expect(tester.takeException(), isNull);
            final linea = find.byKey(ClavesHojaDepto.agregado);
            expect(linea, findsOneWidget);
            expect(find.text('Depto $largo agregado.'), findsOneWidget);
            expectSinTextoFueraDeLosCostados211(tester, tamano);
            expect(
              tester.getRect(linea).bottom,
              lessThanOrEqualTo(tester.getRect(campoNumero).top),
            );
            await capturar211(tester, 'agregado_largo_${tamano.width.toInt()}_x$escala');
          },
        );
      }
    }

    testWidgets('con el teclado abierto (280 dp) a 360×640 ×2 la línea y los botones se alcanzan', (
      tester,
    ) async {
      await llegarA(tester, EstadoV11.agregadoOtro, tamano: telefonoChico211, escala: 2);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(botonAgregar);
      await tester.pump();
      expect(tester.getRect(botonAgregar).bottom, lessThanOrEqualTo(640 - 280 + 0.5));
      expect(find.byKey(ClavesHojaDepto.agregado), findsOneWidget);
    });

    testWidgets('el lector la recibe una sola vez: un anuncio y la línea no es región viva', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final anuncios = <String>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility,
        (mensaje) async {
          if (mensaje is Map && mensaje['type'] == 'announce') {
            anuncios.add((mensaje['data'] as Map)['message'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        ),
      );
      await llegarA(tester, EstadoV11.agregadoOtro);

      expect(anuncios.where((a) => a == 'Depto 301 agregado.'), hasLength(1));
      final nodo = tester.getSemantics(find.text('Depto 301 agregado.'));
      expect(nodo.flagsCollection.isLiveRegion, isFalse);
      h.dispose();
    });

    testWidgets('cerrar la hoja y volver a abrir «+ Departamento» arranca sin la línea', (
      tester,
    ) async {
      await llegarA(tester, EstadoV11.agregadoOtro);
      await tester.binding.handlePopRoute();
      await asentarHoja(tester);
      await abrirAltaDepto(tester);

      expect(find.byKey(ClavesHojaDepto.agregado), findsNothing);
      expect(textoDe(tester, campoNumero), isEmpty);
    });

    testWidgets('tras «Agregar y cargar otro» un repetido saca la línea y avisa el repetido', (
      tester,
    ) async {
      await llegarA(tester, EstadoV11.agregadoOtro);
      await escribir(tester, campoNumero, '102');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);

      expect(find.byKey(ClavesHojaDepto.agregado), findsNothing);
      expect(find.text(_repetido102), findsOneWidget);
      expect(textoDe(tester, campoNumero), '102');
    });

    testWidgets('dos «Agregar y cargar otro» antes de que termine el primero: un solo depto, una '
        'línea y nada trabado', (tester) async {
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      final espera = Completer<void>();
      m.repo.espera = espera;
      await escribir(tester, campoNumero, '501');
      await tester.tap(botonAgregarYCargarOtro);
      await tester.pump();
      await tester.tap(botonAgregarYCargarOtro, warnIfMissed: false);
      await tester.pump();
      espera.complete();
      await asentarHoja(tester);

      expect(m.repo.activos.where((e) => e.numeroDepto == '501'), hasLength(1));
      expect(find.byKey(ClavesHojaDepto.agregado), findsOneWidget);
      expect(find.text('Depto 501 agregado.'), findsOneWidget);
      expect(habilitado(tester, botonAgregar), isTrue);
    });
  });

  group('comparación del número y orden tras el fix (d020957)', () {
    testWidgets('«pb a», «PBA», «PB–A», «PB—A», « p b - a » y «PB‑A» son el mismo que «PB-A»', (
      tester,
    ) async {
      final m = await llegarA(tester, EstadoV11.lista);
      await abrirAltaDepto(tester);
      for (final v in ['pb a', 'PBA', 'PB–A', 'PB—A', ' p b - a ', 'PB‑A']) {
        await escribir(tester, campoNumero, v);
        await tester.tap(botonAgregar);
        await asentarHoja(tester);
        expect(
          find.text('Ya existe el departamento PB-A en este edificio.'),
          findsOneWidget,
          reason: '«$v» debería ser repetido',
        );
      }
      expect(m.repo.activos, hasLength(6));
    });

    testWidgets('los puntos y las barras siguen contando: «12», «1.2» y «1/2» son distintos', (
      tester,
    ) async {
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      for (final v in ['12', '1.2', '1/2']) {
        await escribir(tester, campoNumero, v);
        await tester.tap(botonAgregarYCargarOtro);
        await asentarHoja(tester);
      }
      expect(m.repo.activos.map((e) => e.numeroDepto), ['12', '1.2', '1/2']);
    });

    testWidgets('editar «101» a «1-0-1» no es repetido de sí mismo y guarda', (tester) async {
      final m = await llegarA(tester, EstadoV11.lista);
      await abrirEdicionDepto(tester, 'e-101');
      await escribir(tester, campoNumero, '1-0-1');
      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);

      expect(find.byKey(ClavesHojaDepto.repetido), findsNothing);
      expect(m.repo.activos.firstWhere((e) => e.id == 'e-101').numeroDepto, '1-0-1');
    });

    testWidgets('un número que es solo guiones («-») se guarda y la fila dice «Sin número»', (
      tester,
    ) async {
      // Documenta el menor del revisor: pasa la validación, la clave es nula y la fila dice
      // «Sin número» aunque el dato sea «-». No se pierde nada.
      final m = await llegarA(tester, EstadoV11.vacio);
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '-');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);

      expect(tester.takeException(), isNull);
      expect(m.repo.activos.map((e) => e.numeroDepto), ['-']);
      expect(find.text('Sin número'), findsOneWidget);
    });

    testWidgets('la baja de un depto sin número pregunta «¿Dar de baja este depto sin número?»', (
      tester,
    ) async {
      await llegarA(tester, EstadoV11.preguntaBajaSinNumero);
      expect(find.text('¿Dar de baja este depto sin número?'), findsOneWidget);
    });

    testWidgets('«PB» va primero entre los pisos, sin importar mayúsculas; «Sin piso» al final', (
      tester,
    ) async {
      await montarHoja(
        tester,
        espacios: [
          espacioDe('a', '1', piso: '1', orden: 1),
          espacioDe('b', '2', piso: 'pb', orden: 2),
          espacioDe('c', '3', piso: 'Azotea', orden: 3),
          espacioDe('d', '4', orden: 4),
          espacioDe('e', '5', piso: '2', orden: 5),
        ],
        tamano: const Size(390, 1400),
      );
      final rotulos = ['PISO PB', 'PISO 1', 'PISO 2', 'PISO AZOTEA', 'SIN PISO'];
      final ys = [for (final r in rotulos) tester.getTopLeft(find.text(r)).dy];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'orden de los pisos: $ys');
    });
  });
}
