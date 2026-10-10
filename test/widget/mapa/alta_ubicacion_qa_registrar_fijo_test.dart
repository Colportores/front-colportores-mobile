// QA ronda 1 del PR #317 (issue #305, HU-UBI-001): «Registrar» fijo al pie de la hoja del alta (vista
// 03, artboards 03A · 01 a 04). Complementa a `alta_ubicacion_registrar_fijo_test.dart` (el del
// implementador) con lo que ese no mide:
//  1. «Registrar» con la barra de gestos del sistema abajo y con el teclado, en los dos tamaños.
//  2. Cuánto queda de hoja para desplazar con el teclado abierto a texto 2x, y si el campo que se
//     escribe se ve entero.
//  3. El peor caso: todos los avisos a la vez, sin que nada quede fuera de alcance.
//  4. La lectura con lector de pantalla (nodo del botón y del motivo, orden) y el foco con Tab.
//  5. Que nunca se pierda lo escrito: rotar, cambiar la letra, abrir y cerrar el teclado, una falla,
//     el aviso de duplicado.
//  6. Los casos límite de la acción: falla a mitad con el teclado, acciones superpuestas.
//
// Medidas con las fuentes reales del proyecto. Los hallazgos de QA van con `skip` y el motivo en un
// comentario `// skip: QA #305 …`; el implementador les saca el `skip` cuando los arregla.
// Capturas: `flutter test --dart-define=QA_CAPTURAS=true …` las deja en `.dart_tool/qa_capturas/`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:dartz/dartz.dart' show Left, Right;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/alta_ubicacion_qa_317_arnes.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// «Registrar» entero dentro de lo que se ve: ni cortado por abajo (la pantalla menos el teclado o la
/// barra de gestos), ni aplastado, ni con el texto fuera del botón.
void _registrarEntero(WidgetTester tester, {required double alto, required String donde}) {
  expect(tester.takeException(), isNull, reason: '$donde: sin desborde');
  expect(botonRegistrarFijo, findsOneWidget, reason: donde);
  final r = tester.getRect(botonRegistrarFijo);
  expect(r.top, greaterThanOrEqualTo(0), reason: '$donde: «Registrar» se sale por arriba ($r)');
  expect(r.bottom, lessThanOrEqualTo(alto), reason: '$donde: «Registrar» queda cortado ($r)');
  expect(r.height, greaterThanOrEqualTo(48), reason: '$donde: «Registrar» queda aplastado ($r)');
  expect(botonRegistrarFijo.hitTestable(), findsOneWidget, reason: '$donde: no se puede tocar');
  final texto = tester.getRect(
    find.descendant(of: botonRegistrarFijo, matching: find.byType(Text)),
  );
  expect(
    r.inflate(.5).contains(texto.topLeft) && r.inflate(.5).contains(texto.bottomRight),
    isTrue,
    reason: '$donde: el texto de «Registrar» se sale del botón ($texto en $r)',
  );
}

/// El control se alcanza deslizando la hoja: su borde de arriba y su borde de abajo llegan a la zona
/// visible (si es más alto que la zona, por partes) y, si cabe, se puede tocar. Nunca queda tapado
/// por «Registrar» ni por el teclado.
Future<void> _seAlcanza(WidgetTester tester, Finder f, String que) async {
  expect(f, findsWidgets, reason: '$que: no está en la hoja');
  final zona = zonaQueSeDesplaza(tester);
  final boton = tester.getRect(botonRegistrarFijo);
  expect(zona.bottom, lessThanOrEqualTo(boton.top + .5), reason: 'la zona llega bajo «Registrar»');
  await tester.ensureVisible(f.first);
  await tester.pump();
  var r = tester.getRect(f.first);
  expect(
    r.top,
    greaterThanOrEqualTo(zona.top - .5),
    reason: '$que: su borde de arriba ($r) no se ve en $zona',
  );
  expect(r.top, lessThan(zona.bottom), reason: '$que: ($r) no se ve en $zona');
  unawaited(Scrollable.ensureVisible(tester.element(f.first), alignment: 1));
  await tester.pump();
  r = tester.getRect(f.first);
  expect(
    r.bottom,
    lessThanOrEqualTo(zona.bottom + .5),
    reason: '$que: su borde de abajo ($r) no se ve en $zona',
  );
  expect(r.bottom, greaterThan(zona.top), reason: '$que: ($r) no se ve en $zona');
  if (r.height <= zona.height) {
    expect(f.first.hitTestable(), findsOneWidget, reason: '$que: no se puede tocar');
  }
}

void main() {
  setUpAll(cargarFuentesReales);

  group('QA #305 · «Registrar» y el borde del sistema', () {
    for (final estado in EstadoAlta.values) {
      for (final (tamano, escala) in [
        (telefonoChico, 1.0),
        (telefonoChico, 2.0),
        (telefonoGrande, 1.0),
        (telefonoGrande, 2.0),
      ]) {
        testWidgets(
          '${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()}, texto ${escala}x, '
          'con la barra de gestos (34 dp): «Registrar» no queda bajo la barra',
          (tester) async {
            await abrirEn(tester, estado, tamano: tamano, escala: escala, barraInferior: 34);
            _registrarEntero(tester, alto: tamano.height - 34, donde: 'sin teclado');

            await tocar(tester, find.text('Casa'));
            _registrarEntero(tester, alto: tamano.height - 34, donde: 'con «Casa» elegida');

            await abrirTeclado(tester);
            _registrarEntero(tester, alto: tamano.height - tecladoAbierto, donde: 'con el teclado');
          },
        );
      }
    }
  });

  group('QA #305 · con el teclado abierto a texto 2x en 360×640', () {
    testWidgets('lo que queda para desplazar y si el campo que se escribe se ve entero', (
      tester,
    ) async {
      await abrirEn(tester, EstadoAlta.gpsPreciso, escala: 2, teclado: tecladoAbierto);
      await tocar(tester, find.text('Casa'));

      final zona = zonaQueSeDesplaza(tester);
      // ignore: avoid_print
      print('zona que se desplaza con teclado a 2x: ${zona.height.toStringAsFixed(1)} dp');
      expect(zona.height, greaterThanOrEqualTo(48), reason: 'cabe al menos un campo ($zona)');

      // Se toca el número: el campo con su etiqueta tiene que quedar entero en la zona visible.
      await tester.ensureVisible(campoNumero);
      await tester.pump();
      await tester.tap(campoNumero);
      await asentar(tester);
      final campo = tester.getRect(campoNumero);
      expect(
        zona.top <= campo.top + .5 && campo.bottom <= zona.bottom + .5,
        isTrue,
        reason: 'el campo «Número» ($campo) no entra entero en la zona visible ($zona)',
      );
    });

    for (final estado in [EstadoAlta.gpsPreciso, EstadoAlta.numeroEditado]) {
      testWidgets(
        '${estado.rotulo}: escribir calle y número con el teclado abierto a 2x conserva ambos',
        (tester) async {
          await abrirEn(tester, estado, escala: 2, teclado: tecladoAbierto);
          await tocar(tester, find.text('Casa'));

          await tester.ensureVisible(campoCalle);
          await tester.pump();
          await tester.enterText(campoCalle, 'Bulevar Artigas');
          await asentar(tester);
          await tester.enterText(campoNumero, '987');
          await asentar(tester);

          expect(find.widgetWithText(TextField, 'Bulevar Artigas'), findsOneWidget);
          expect(find.widgetWithText(TextField, '987'), findsOneWidget);
          _registrarEntero(tester, alto: 640 - tecladoAbierto, donde: 'escribiendo');
        },
      );
    }
  });

  group('QA #305 · el peor caso: todos los avisos a la vez, nada queda fuera de alcance', () {
    for (final teclado in [0.0, tecladoAbierto]) {
      testWidgets('GPS preciso + sin conexión + número editado + falla al registrar, texto 2x'
          '${teclado > 0 ? ' y teclado' : ''}', (tester) async {
        final repo = RepoAltaFalso()..comportamiento = (_) async => const Left(FailureInesperado());
        await abrirAlta(
          tester,
          escala: 2,
          repo: repo,
          situacion: situacionSinConexion,
          geocodificador: GeocodificadorFalso(
            (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1250'),
          ),
        );
        await tocar(tester, find.text('Casa'));
        await tester.enterText(campoNumero, '1238');
        await asentar(tester);
        await tester.tap(botonRegistrarFijo);
        await asentar(tester);
        if (teclado > 0) await abrirTeclado(tester, teclado);

        _registrarEntero(tester, alto: 640 - teclado, donde: 'todos los avisos');
        expect(find.byType(AvisoMapaConectado), findsOneWidget);
        final zona = zonaQueSeDesplaza(tester);
        expect(zona.height, greaterThanOrEqualTo(48), reason: 'queda zona para desplazar ($zona)');

        // Todo lo de la hoja se alcanza deslizando y queda arriba del botón.
        await irAlPrincipioDeLaHoja(tester);
        await _seAlcanza(tester, find.byType(AvisoMapaConectado), 'aviso Sin conexión');
        await _seAlcanza(tester, find.text('Casa'), 'Casa');
        await _seAlcanza(tester, find.text('Negocio'), 'Negocio');
        await _seAlcanza(tester, find.text('Edificio'), 'Edificio');
        await _seAlcanza(tester, find.textContaining(TextosAlta.cambiar), 'Cambiar ciudad');
        await _seAlcanza(tester, campoCalle, 'campo Calle');
        await _seAlcanza(tester, campoNumero, 'campo Número');
        await _seAlcanza(tester, find.text(TextosAlta.usar('1250')), '«Usar 1250»');
        await _seAlcanza(tester, find.text(TextosAlta.noPudimosGuardar), 'aviso de falla');
        _registrarEntero(tester, alto: 640 - teclado, donde: 'después de recorrer la hoja');
      });
    }

    for (final teclado in [0.0, tecladoAbierto]) {
      testWidgets(
        'sin GPS + sin conexión + campaña sin ciudades, texto 2x${teclado > 0 ? ' y teclado' : ''}',
        (tester) async {
          await abrirEn(tester, EstadoAlta.sinCiudades, escala: 2, teclado: teclado);
          _registrarEntero(tester, alto: 640 - teclado, donde: 'sin ciudades');
          await irAlPrincipioDeLaHoja(tester);
          await _seAlcanza(tester, find.text('Activar GPS'), '«Activar GPS»');
          await _seAlcanza(tester, find.text(TextosAlta.sinCiudades), 'aviso sin ciudades');
          await _seAlcanza(tester, find.text(TextosAlta.reintentar), '«Reintentar»');
          expect(registrarHabilitado(tester), isFalse);
        },
      );
    }

    testWidgets('sin GPS + sin conexión, texto 2x: «Activar GPS» y el aviso se alcanzan', (
      tester,
    ) async {
      await abrirEn(tester, EstadoAlta.sinGpsSinConexion, escala: 2);
      _registrarEntero(tester, alto: 640, donde: 'sin GPS y sin conexión');
      await irAlPrincipioDeLaHoja(tester);
      await _seAlcanza(tester, find.text('Activar GPS'), '«Activar GPS»');
    });
  });

  group('QA #305 · lectura con lector de pantalla y foco', () {
    testWidgets(
      '«Registrar» deshabilitado se anuncia como botón deshabilitado y el motivo lo sigue',
      (tester) async {
        final handle = tester.ensureSemantics();
        await abrirEn(tester, EstadoAlta.gpsPreciso);

        expect(registrarHabilitado(tester), isFalse);
        expect(
          tester.getSemantics(botonRegistrarFijo),
          isSemantics(
            label: TextosAlta.registrar,
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
          ),
        );
        // El motivo es un nodo propio, inmediatamente después del botón en el orden de lectura.
        final etiquetas = _etiquetasEnOrden(tester);
        final iBoton = etiquetas.indexOf(TextosAlta.registrar);
        final iMotivo = etiquetas.indexOf(TextosAlta.elegiElTipo);
        expect(iBoton, isNonNegative, reason: 'el botón está en el árbol: $etiquetas');
        expect(iMotivo, iBoton + 1, reason: 'el motivo sigue al botón: $etiquetas');
        handle.dispose();
      },
    );

    testWidgets('habilitado, «Registrar» se anuncia habilitado y con la acción de tocar', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await abrirEn(tester, EstadoAlta.gpsPreciso);
      await tocar(tester, find.text('Casa'));

      final nodo = tester.getSemantics(botonRegistrarFijo);
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        nodo,
        isSemantics(
          label: TextosAlta.registrar,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      expect(find.text(TextosAlta.elegiElTipo), findsNothing, reason: 'sin motivo cuando se puede');
      handle.dispose();
    });

    testWidgets('mientras guarda se anuncia «Registrando…» y no se puede tocar', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      await abrirAlta(tester, repo: repo);
      await tocar(tester, find.text('Casa'));
      await tester.tap(botonRegistrarFijo);
      await asentar(tester);

      expect(
        tester.getSemantics(botonRegistrarFijo),
        isSemantics(
          label: TextosAlta.registrando,
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      repo.bloqueo!.complete();
      await asentar(tester);
      handle.dispose();
    });

    testWidgets('a texto 3x el motivo pasa arriba del botón y el orden de lectura lo acompaña', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await abrirEn(tester, EstadoAlta.gpsImpreciso, escala: 3);

      final etiquetas = _etiquetasEnOrden(tester);
      final iBoton = etiquetas.indexOf(TextosAlta.registrar);
      final iMotivo = etiquetas.indexOf(TextosAlta.elegiPrecision);
      expect(iBoton, isNonNegative, reason: '$etiquetas');
      expect(iMotivo, isNonNegative, reason: '$etiquetas');
      expect(iMotivo, lessThan(iBoton), reason: 'arriba del botón se lee antes: $etiquetas');
      handle.dispose();
    });

    testWidgets('el aviso de falla es una región viva y queda a la vista con el teclado a texto 2x', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final repo = RepoAltaFalso()..comportamiento = (_) async => const Left(FailureInesperado());
      await abrirAlta(tester, escala: 2, repo: repo);
      await tocar(tester, find.text('Casa'));
      await abrirTeclado(tester);

      await tester.tap(botonRegistrarFijo);
      await asentar(tester);

      final aviso = find.text(TextosAlta.noPudimosGuardar);
      expect(aviso, findsOneWidget);
      final zona = zonaQueSeDesplaza(tester);
      final r = tester.getRect(aviso);
      // Aunque el aviso (varios renglones a 2x) sea más alto que la zona visible, empieza dentro de ella.
      expect(
        r.top,
        greaterThanOrEqualTo(zona.top - .5),
        reason: 'el aviso ($r) empieza fuera ($zona)',
      );
      expect(r.top, lessThan(zona.bottom), reason: 'el aviso ($r) no se ve ($zona)');
      expect(
        tester.getSemantics(aviso),
        isSemantics(isLiveRegion: true),
        reason: 'el aviso de falla se anuncia',
      );
      handle.dispose();
    });

    testWidgets(
      'con Tab el foco recorre calle, número y «Registrar» sin trampas, y vuelve con Shift+Tab',
      (tester) async {
        await abrirEn(tester, EstadoAlta.gpsPreciso);
        await tocar(tester, find.text('Casa'));
        await tester.tap(campoCalle);
        await asentar(tester);

        bool enRegistrar() =>
            FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<FilledButton>() !=
            null;

        final visitados = <String>[];
        for (var i = 0; i < 8 && !enRegistrar(); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          visitados.add(FocusManager.instance.primaryFocus?.debugLabel ?? '?');
        }
        expect(enRegistrar(), isTrue, reason: 'Tab llega a «Registrar» habilitado: $visitados');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          enRegistrar(),
          isFalse,
          reason: 'después de «Registrar» el foco sale (no queda atrapado)',
        );
      },
    );
  });

  group('QA #305 · nunca se pierde lo escrito', () {
    testWidgets(
      'rotar/redimensionar, cambiar la letra y abrir/cerrar el teclado conservan calle y número',
      (tester) async {
        final m = await abrirEn(tester, EstadoAlta.gpsPreciso);
        await tocar(tester, find.text('Casa'));
        await tester.enterText(campoCalle, 'Bulevar Artigas');
        await tester.enterText(campoNumero, '987');
        await asentar(tester);

        Future<void> verificar(String donde, double alto) async {
          await tester.pumpAndSettle();
          expect(find.widgetWithText(TextField, 'Bulevar Artigas'), findsOneWidget, reason: donde);
          expect(find.widgetWithText(TextField, '987'), findsOneWidget, reason: donde);
          _registrarEntero(tester, alto: alto, donde: donde);
        }

        m.escala.value = 2;
        await verificar('texto 2x', 640);
        await abrirTeclado(tester);
        await verificar('texto 2x + teclado', 640 - tecladoAbierto);
        tester.view.physicalSize = telefonoGrande;
        await verificar('412×915 con teclado', 915 - tecladoAbierto);
        await cerrarTeclado(tester);
        await verificar('412×915 sin teclado', 915);
        tester.view.physicalSize = telefonoChico;
        m.escala.value = 1;
        await verificar('de vuelta a 360×640 texto 1x', 640);
        expect(registrarHabilitado(tester), isTrue);
      },
    );

    testWidgets(
      '«Registrar» con duplicado cercano y «Cancelar»: la hoja sigue con lo escrito y habilitada',
      (tester) async {
        final repo = RepoAltaFalso()
          ..comportamiento = (_) async => Right(AltaConDuplicados(candidatas: [candidata('a')]));
        await abrirAlta(tester, escala: 2, repo: repo);
        await tocar(tester, find.text('Casa'));
        await tester.enterText(campoNumero, '1240');
        await asentar(tester);

        await tester.tap(botonRegistrarFijo);
        await asentar(tester);
        await tester.pumpAndSettle();
        expect(find.text('Cancelar'), findsWidgets);
        await tocar(tester, find.text('Cancelar'));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(TextField, '1240'), findsOneWidget);
        expect(registrarHabilitado(tester), isTrue);
        _registrarEntero(tester, alto: 640, donde: 'después de cancelar el duplicado');
        expect(repo.llamadas, hasLength(1));
      },
    );

    testWidgets(
      'falla con el teclado abierto: se conserva lo escrito y «Registrar» vuelve a habilitarse',
      (tester) async {
        var intento = 0;
        final repo = RepoAltaFalso()
          ..comportamiento = (u) async => ++intento == 1
              ? const Left(FailureSinConexion())
              : Right(AltaRegistrada(ubicacion: u));
        final m = await abrirAlta(tester, escala: 2, repo: repo);
        await tocar(tester, find.text('Casa'));
        await abrirTeclado(tester);
        await tester.enterText(campoNumero, '1240');
        await asentar(tester);

        await tester.tap(botonRegistrarFijo);
        await asentar(tester);
        expect(find.widgetWithText(TextField, '1240'), findsOneWidget);
        expect(registrarHabilitado(tester), isTrue);
        expect(find.text(TextosAlta.registrando), findsNothing);
        _registrarEntero(tester, alto: 640 - tecladoAbierto, donde: 'tras la falla con teclado');

        await tester.tap(botonRegistrarFijo);
        await asentar(tester);
        expect(m.salidas.single, isA<UbicacionCreada>());
        expect((m.salidas.single! as UbicacionCreada).ubicacion.numero, '1240');
      },
    );
  });

  group('QA #305 · acciones superpuestas', () {
    testWidgets(
      '«Registrar» tocado dos veces seguidas con el teclado abierto: una sola ubicación',
      (tester) async {
        final repo = RepoAltaFalso()..bloqueo = Completer<void>();
        final m = await abrirAlta(tester, escala: 2, repo: repo);
        await tocar(tester, find.text('Casa'));
        await abrirTeclado(tester);

        await tester.tap(botonRegistrarFijo);
        await tester.pump();
        await tester.tap(botonRegistrarFijo, warnIfMissed: false);
        await tester.pump();
        repo.bloqueo!.complete();
        await asentar(tester);

        expect(repo.llamadas, hasLength(1));
        expect(m.salidas, hasLength(1));
      },
    );

    testWidgets('«Cerrar» no sale mientras guarda y el botón fijo sigue deshabilitado', (
      tester,
    ) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final m = await abrirAlta(tester, repo: repo);
      await tocar(tester, find.text('Casa'));
      await tester.tap(botonRegistrarFijo);
      await asentar(tester);

      await tester.tap(find.byTooltip(TextosAlta.cerrar), warnIfMissed: false);
      await asentar(tester);
      expect(find.text(TextosAlta.titulo), findsOneWidget, reason: 'sigue en la hoja');
      expect(registrarHabilitado(tester), isFalse);

      repo.bloqueo!.complete();
      await asentar(tester);
      expect(m.salidas.single, isA<UbicacionCreada>());
    });

    testWidgets('el botón atrás del sistema mientras guarda no cierra el alta', (tester) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final m = await abrirAlta(tester, repo: repo);
      await tocar(tester, find.text('Casa'));
      await tester.tap(botonRegistrarFijo);
      await asentar(tester);

      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(find.text(TextosAlta.titulo), findsOneWidget);

      repo.bloqueo!.complete();
      await asentar(tester);
      expect(m.salidas.single, isA<UbicacionCreada>());
    });
  });

  group('QA #305 · los estados de espera: cargando, buscando y guardando tienen contexto', () {
    for (final (escala, teclado) in [(1.0, 0.0), (2.0, 0.0), (2.0, tecladoAbierto), (3.0, 0.0)]) {
      testWidgets('«Registrando…» a texto ${escala}x${teclado > 0 ? ' con teclado' : ''}: entero, '
          'deshabilitado y sin spinner suelto', (tester) async {
        final repo = RepoAltaFalso()..bloqueo = Completer<void>();
        await abrirAlta(tester, escala: escala, repo: repo);
        await tocar(tester, find.text('Casa'));
        if (teclado > 0) await abrirTeclado(tester, teclado);
        await tester.tap(botonRegistrarFijo);
        await asentar(tester);

        expect(find.text(TextosAlta.registrando), findsOneWidget);
        expect(registrarHabilitado(tester), isFalse);
        _registrarEntero(tester, alto: 640 - teclado, donde: '«Registrando…»');
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: 'sin spinner sin texto',
        );
        repo.bloqueo!.complete();
        await asentar(tester);
      });
    }

    for (final escala in [1.0, 2.0]) {
      testWidgets('buscando el GPS y la ciudad a texto ${escala}x: dicen qué esperan y «Registrar» '
          'queda entero y deshabilitado', (tester) async {
        final gps = GpsFalso()..bloqueo = Completer<void>();
        final ciudades = CiudadesFalsas()..bloqueoPropuesta = Completer<void>();
        await abrirAlta(
          tester,
          escala: escala,
          gps: gps,
          ciudades: ciudades,
          esperarAnimaciones: false,
        );
        addTearDown(() {
          if (!gps.bloqueo!.isCompleted) gps.bloqueo!.complete();
          if (!ciudades.bloqueoPropuesta!.isCompleted) ciudades.bloqueoPropuesta!.complete();
        });

        expect(
          find.text(TextosAlta.buscandoGps),
          findsOneWidget,
          reason: 'el indicador dice qué espera',
        );
        expect(registrarHabilitado(tester), isFalse);
        _registrarEntero(tester, alto: 640, donde: 'buscando el GPS');
        await _seAlcanza(tester, find.textContaining(TextosAlta.buscandoCiudad), 'ciudad en curso');
      });
    }
  });

  group('QA #305 · textos y letra muy grande, sin desborde', () {
    for (final estado in EstadoAlta.values) {
      for (final escala in [2.5, 3.0]) {
        for (final teclado in [0.0, tecladoAbierto]) {
          testWidgets(
            '${estado.rotulo} a 360×640, texto ${escala}x${teclado > 0 ? ' y teclado' : ''}: '
            '«Registrar» entero y sin desborde',
            (tester) async {
              await abrirEn(tester, estado, escala: escala, teclado: teclado);
              _registrarEntero(tester, alto: 640 - teclado, donde: estado.rotulo);
              await tocar(tester, find.text('Casa'));
              _registrarEntero(tester, alto: 640 - teclado, donde: '${estado.rotulo} con Casa');
            },
          );
        }
      }
    }
  });

  group('QA #305 · tamaño de toque y etiquetas en cada estado, tamaño y letra', () {
    for (final estado in EstadoAlta.values) {
      for (final (tamano, escala, teclado) in [
        (telefonoChico, 1.0, 0.0),
        (telefonoChico, 2.0, 0.0),
        (telefonoChico, 2.0, tecladoAbierto),
        (telefonoGrande, 1.0, 0.0),
        (telefonoGrande, 2.0, 0.0),
      ]) {
        testWidgets(
          '${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()}, texto ${escala}x'
          '${teclado > 0 ? ' y teclado' : ''}: 48 dp (Android), 44 pt (iOS) y etiquetas',
          (tester) async {
            final handle = tester.ensureSemantics();
            await abrirEn(
              tester,
              estado,
              tamano: tamano,
              escala: escala,
              barraInferior: 34,
              teclado: teclado,
            );
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

            // Con el tipo elegido (el botón habilitado cuando el estado lo permite).
            await tocar(tester, find.text('Casa'));
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            handle.dispose();
          },
        );
      }
    }
  });

  group('QA #305 · la regla de los dos tercios con la letra de 1x a 3x', () {
    for (final estado in [
      EstadoAlta.gpsPreciso,
      EstadoAlta.sinGps,
      EstadoAlta.gpsImpreciso,
      EstadoAlta.sinGpsSinConexion,
    ]) {
      for (final tamano in [telefonoChico, telefonoGrande]) {
        testWidgets('${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()}: «Registrar» entero, '
            'el motivo a la vista y lo fijo deja hoja para desplazar', (tester) async {
          final m = await abrirEn(tester, estado, tamano: tamano);
          final filas = <String>[];
          for (var e = 1.0; e <= 3.001; e += .1) {
            m.escala.value = e;
            await tester.pumpAndSettle();
            final donde =
                '${estado.rotulo} ${tamano.width.toInt()}×${tamano.height.toInt()} a ${e.toStringAsFixed(1)}x';
            _registrarEntero(tester, alto: tamano.height, donde: donde);

            final hoja = tester.getRect(find.byType(HojaAlta));
            final zona = zonaQueSeDesplaza(tester);
            final fijo = hoja.bottom - zona.bottom;
            final motivo = find.textContaining(RegExp(r'para registrar\.$'));
            final hayMotivo = motivo.evaluate().isNotEmpty;
            final abajo =
                hayMotivo && find.descendant(of: desplazable, matching: motivo).evaluate().isEmpty;
            filas.add(
              '${e.toStringAsFixed(1)}x fijo=${fijo.toStringAsFixed(0)}/${hoja.height.toStringAsFixed(0)} '
              'zona=${zona.height.toStringAsFixed(0)} motivo=${hayMotivo ? (abajo ? 'abajo' : 'arriba') : 'sin'}',
            );
            if (abajo) {
              final r = tester.getRect(motivo.first);
              expect(
                r.bottom,
                lessThanOrEqualTo(tamano.height),
                reason: '$donde: el motivo se corta ($r)',
              );
              expect(
                motivo.first.hitTestable(),
                findsOneWidget,
                reason: '$donde: el motivo no se ve',
              );
            } else if (hayMotivo) {
              await _seAlcanza(tester, motivo, 'motivo ($donde)');
            }
            await irAlPrincipioDeLaHoja(tester);
            if (abajo) {
              expect(
                fijo,
                // Cota floja (cuatro quintos): la regla de 2/3 mide el botón con 52 dp y con la letra
                // grande el botón crece (03A · 03 a 2x llega al 68 %). Decidido el 08/10 (P2, #305).
                lessThanOrEqualTo(hoja.height * .8),
                reason:
                    '$donde: lo fijo (${fijo.toStringAsFixed(0)}) pasa de 4/5 de la hoja (${hoja.height.toStringAsFixed(0)})',
              );
            }
            {
              expect(
                zona.height,
                greaterThanOrEqualTo(48),
                reason: '$donde: queda poca hoja para desplazar ($zona)',
              );
            }
          }
          // ignore: avoid_print
          print(
            '${estado.rotulo} ${tamano.width.toInt()}×${tamano.height.toInt()}\n  '
            '${filas.join('\n  ')}',
          );
        });
      }
    }
  });

  group('QA #305 · la pista y el chip del mapa con la letra de 1x a 3x', () {
    final pistas = <(EstadoAlta, String)>[
      (EstadoAlta.gpsPreciso, TextosAlta.mover),
      (EstadoAlta.gpsImpreciso, TextosAlta.mover),
      (EstadoAlta.sinGps, TextosAlta.tocar),
    ];
    for (final (estado, pista) in pistas) {
      for (final tamano in [telefonoChico, telefonoGrande]) {
        testWidgets(
          '${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()}: «$pista» queda entera '
          'sobre el mapa, sin tapar el pin ni la hoja (hasta 2x; por encima solo se informa)',
          (tester) async {
            final m = await abrirEn(tester, estado, tamano: tamano);
            final filas = <String>[];
            for (var e = 1.0; e <= 3.001; e += .1) {
              m.escala.value = e;
              await tester.pumpAndSettle();
              final donde = '${estado.rotulo} a ${e.toStringAsFixed(1)}x';
              expect(tester.takeException(), isNull, reason: donde);
              final hoja = tester.getRect(
                find.ancestor(of: find.byType(HojaAlta), matching: find.byType(Material)).first,
              );
              final texto = tester.getRect(find.text(pista));
              final pin = tester.getRect(find.byType(PinAlta));
              final bajoLaHoja = texto.bottom + 6 - hoja.top;
              final tapaElPin = texto.top < pin.bottom - 2;
              filas.add(
                '${e.toStringAsFixed(1)}x pista.bottom=${(texto.bottom + 6).toStringAsFixed(0)} '
                'hoja.top=${hoja.top.toStringAsFixed(0)} pin.bottom=${pin.bottom.toStringAsFixed(0)}'
                '${bajoLaHoja > .5 ? '  <- la hoja tapa ${bajoLaHoja.toStringAsFixed(0)} dp de la pista' : ''}'
                '${tapaElPin ? '  <- la pista tapa el pin' : ''}',
              );
              if (e <= 2.001) {
                expect(bajoLaHoja, lessThanOrEqualTo(.5), reason: '$donde: la hoja tapa la pista');
                expect(tapaElPin, isFalse, reason: '$donde: la pista tapa el pin');
              }
            }
            // ignore: avoid_print
            print(
              '${estado.rotulo} ${tamano.width.toInt()}×${tamano.height.toInt()}\n  '
              '${filas.join('\n  ')}',
            );
          },
        );
      }
    }
  });

  group('QA #305 · con una barra de estado alta (muesca) el chip, el pin y la pista se acomodan', () {
    // Un 360×640 con muesca no existe (a 48 dp arriba la hoja ya tapa 3 dp del borde de la pista a 2x
    // y a 59 dp tapa el segundo renglón); los teléfonos con muesca son grandes.
    for (final (tamano, arriba) in [
      (telefonoChico, 32.0),
      (telefonoGrande, 32.0),
      (telefonoGrande, 48.0),
      (telefonoGrande, 59.0),
    ]) {
      {
        testWidgets(
          'GPS ±6 m a ${tamano.width.toInt()}×${tamano.height.toInt()} con ${arriba.toInt()} dp arriba y '
          'texto 1x y 2x: el chip no tapa el pin ni «Cerrar», la pista no queda bajo la hoja',
          (tester) async {
            final m = await abrirEn(
              tester,
              EstadoAlta.gpsPreciso,
              tamano: tamano,
              barraSuperior: arriba,
            );
            for (final e in [1.0, 1.5, 2.0]) {
              m.escala.value = e;
              await tester.pumpAndSettle();
              final donde =
                  '${arriba.toInt()} dp arriba, ${tamano.width.toInt()}×${tamano.height.toInt()} a ${e}x';
              expect(tester.takeException(), isNull, reason: donde);
              final chip = tester.getRect(
                find.ancestor(
                  of: find.textContaining('GPS ±'),
                  matching: find.byWidgetPredicate((w) => w is Material && w.elevation == 2),
                ),
              );
              final pin = tester.getRect(find.byType(PinAlta));
              final cerrar = tester.getRect(find.byTooltip(TextosAlta.cerrar));
              final hoja = tester.getRect(
                find.ancestor(of: find.byType(HojaAlta), matching: find.byType(Material)).first,
              );
              final pista = tester.getRect(find.text(TextosAlta.mover));
              expect(chip.overlaps(pin), isFalse, reason: '$donde: el chip tapa el pin');
              expect(chip.overlaps(cerrar), isFalse, reason: '$donde: el chip pisa «Cerrar»');
              expect(
                chip.top,
                greaterThanOrEqualTo(arriba),
                reason: '$donde: el chip queda bajo la barra de estado',
              );
              expect(
                pin.bottom,
                lessThan(hoja.top),
                reason: '$donde: la hoja tapa el pin ($pin, hoja $hoja)',
              );
              expect(
                pista.bottom + 6,
                lessThanOrEqualTo(hoja.top + .5),
                reason: '$donde: la hoja tapa la pista ($pista, hoja $hoja)',
              );
              expect(
                find.byTooltip(TextosAlta.cerrar).hitTestable(),
                findsOneWidget,
                reason: donde,
              );
              _registrarEntero(tester, alto: tamano.height, donde: donde);
            }
          },
        );
      }
    }
  });

  group('QA #305 · entradas largas', () {
    testWidgets(
      'un texto pegado larguísimo con emoji en calle y número no desborda ni tapa «Registrar»',
      (tester) async {
        final m = await abrirEn(tester, EstadoAlta.gpsPreciso, escala: 2, teclado: tecladoAbierto);
        await tocar(tester, find.text('Casa'));
        final largo = ('Avenida del Libertador General San Martín 🏠' * 20);
        await tester.enterText(campoCalle, largo);
        await asentar(tester);
        await tester.enterText(campoNumero, '12345678901234567890' * 5);
        await asentar(tester);

        _registrarEntero(tester, alto: 640 - tecladoAbierto, donde: 'texto largo');
        await tester.tap(botonRegistrarFijo);
        await asentar(tester);
        expect(m.repo.llamadas, hasLength(1));
        final u = m.repo.llamadas.single.ubicacion;
        expect(
          u.calle?.runes.length ?? 0,
          lessThanOrEqualTo(200),
          reason: 'la calle tiene un tope',
        );
        expect(u.numero?.length ?? 0, lessThanOrEqualTo(40), reason: 'el número tiene un tope');
      },
    );

    testWidgets('calle de solo espacios: «Registrar» no la manda como texto', (tester) async {
      final m = await abrirEn(tester, EstadoAlta.gpsPreciso);
      await tocar(tester, find.text('Casa'));
      await tester.enterText(campoCalle, '     ');
      await asentar(tester);
      await tester.tap(botonRegistrarFijo);
      await asentar(tester);
      expect(m.repo.llamadas, hasLength(1));
      expect(m.repo.llamadas.single.ubicacion.calle?.trim() ?? '', isEmpty);
    });
  });

  // Solo con `--dart-define=QA_CAPTURAS=true`: sin eso el grupo no se registra (no deja tests salteados).
  if (_conCapturas) {
    group('QA #305 · capturas', () {
      final configs = <(String, Size, double, double)>[
        ('chico1x', telefonoChico, 1.0, 0),
        ('chico2x', telefonoChico, 2.0, 0),
        ('chico2xTeclado', telefonoChico, 2.0, tecladoAbierto),
        ('chico1xTeclado', telefonoChico, 1.0, tecladoAbierto),
        ('grande1x', telefonoGrande, 1.0, 0),
        ('grande2x', telefonoGrande, 2.0, 0),
        ('chico3x', telefonoChico, 3.0, 0),
      ];
      for (final estado in EstadoAlta.values) {
        for (final (nombre, tamano, escala, teclado) in configs) {
          testWidgets('captura ${estado.name} $nombre', (tester) async {
            await cargarIconosParaCapturas(tester);
            await abrirEn(tester, estado, tamano: tamano, escala: escala);
            if (estado != EstadoAlta.numeroEditado &&
                estado.index <= EstadoAlta.gpsImpreciso.index) {
              // En el canvas el tipo ya viene elegido («Casa»).
              await tocar(tester, find.text('Casa'));
            }
            if (teclado > 0) await abrirTeclado(tester, teclado);
            await capturar(tester, '${estado.name}_$nombre');
          });
        }
      }
    });
  }
}

/// Las etiquetas de los nodos de semántica de la hoja, en el orden en que las lee el lector.
List<String> _etiquetasEnOrden(WidgetTester tester) {
  final salida = <String>[];
  void visitar(SemanticsNode nodo) {
    if (nodo.label.isNotEmpty) salida.add(nodo.label);
    nodo.visitChildren((hijo) {
      visitar(hijo);
      return true;
    });
  }

  visitar(tester.getSemantics(find.byType(HojaAlta)));
  return salida;
}
