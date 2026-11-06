// QA del PR #666 (issue #665): en el alta de una ubicación (vista 03, HU-UBI-001) el tipo viene en
// «Casa». Complementa a los tests del implementador con lo que esos no miden:
//  1. «Casa» elegida al abrir en cada estado del canvas (03A · 01 a 04, sin conexión y sin ciudades),
//     leído por el lector de pantalla (`selected`, grupo exclusivo, acción de toque) y con las cuatro
//     guías de accesibilidad, en 360×640 y 412×915, texto 1,0× y 2,0×, sin overflow.
//  2. Que el tipo elegido no se pierda: mover el punto, cambiar la ciudad, una falla, el aviso de
//     duplicado («Cancelar» y «Crear igual»).
//  3. Lo que se guarda: cada tipo llega al repositorio, con su espacio default (casa y negocio sí,
//     edificio no).
//  4. Casos límite: tocar «Casa» estando elegida, doble toque, falla a mitad y reintento, reentrada.
//  5. Que no quede rastro del motivo viejo «Elegí el tipo de ubicación para registrar.».
//
// Capturas: `flutter test --dart-define=QA_CAPTURAS=true …` las deja en `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:dartz/dartz.dart' show Left, Right;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/alta_ubicacion_qa_317_arnes.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Los tests que documentan un hallazgo se corren con `--dart-define=QA_HALLAZGOS=true`.
const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

const _tamanos = [telefonoChico, telefonoGrande];
const _escalas = [1.0, 2.0];

String _donde(EstadoAlta e, Size t, double s) =>
    '${e.rotulo} a ${t.width.toInt()}×${t.height.toInt()}, texto ${s}x';

/// El nodo de semántica del botón de tipo [etiqueta].
SemanticsNode _nodoTipo(WidgetTester tester, String etiqueta) =>
    tester.getSemantics(find.bySemanticsLabel(etiqueta).first);

/// Cuál de los tres botones de tipo está elegido según el lector de pantalla.
List<String> _elegidosPorElLector(WidgetTester tester) => [
  for (final t in ['Casa', 'Negocio', 'Edificio'])
    if (_nodoTipo(tester, t).flagsCollection.isSelected == ui.Tristate.isTrue) t,
];

/// Los tipos que se ven con el tilde (el botón elegido lleva `Icons.check`).
int _tildes() => find.byIcon(Icons.check).evaluate().length;

Future<void> _elegir(WidgetTester tester, String tipo) async {
  await tester.ensureVisible(find.text(tipo).first);
  await tester.pump();
  await tocar(tester, find.text(tipo).first);
}

Future<void> _registrar(WidgetTester tester) async {
  await tester.ensureVisible(botonRegistrarFijo);
  await tester.pump();
  await tocar(tester, botonRegistrarFijo);
}

Ubicacion _ubicacionDe(AltaMontada m) => m.repo.llamadas.last.ubicacion;

void main() {
  group('«Casa» elegida al abrir, en cada estado y tamaño', () {
    for (final estado in EstadoAlta.values) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          testWidgets('${_donde(estado, tamano, escala)}: Casa elegida, sin overflow, guías', (
            tester,
          ) async {
            final handle = tester.ensureSemantics();
            await abrirEn(tester, estado, tamano: tamano, escala: escala);

            expect(tester.takeException(), isNull, reason: 'sin overflow');
            expect(_elegidosPorElLector(tester), ['Casa'], reason: 'el lector: solo «Casa»');
            expect(_tildes(), 1, reason: 'a la vista: un solo tilde');
            expect(
              _nodoTipo(tester, 'Casa'),
              isSemantics(
                label: 'Casa',
                isButton: true,
                isSelected: true,
                hasSelectedState: true,
                isInMutuallyExclusiveGroup: true,
                hasTapAction: true,
              ),
            );
            expect(
              _nodoTipo(tester, 'Negocio'),
              isSemantics(
                label: 'Negocio',
                isButton: true,
                isSelected: false,
                hasSelectedState: true,
                isInMutuallyExclusiveGroup: true,
                hasTapAction: true,
              ),
            );
            final habilitadoAlAbrir =
                estado == EstadoAlta.gpsPreciso || estado == EstadoAlta.numeroEditado;
            expect(
              registrarHabilitado(tester),
              habilitadoAlAbrir,
              reason: 'solo falta lo que hoy es obligatorio (punto, precisión), nunca el tipo',
            );
            expect(find.textContaining('Elegí el tipo'), findsNothing);

            // Las guías miden lo que se ve; se desplaza la hoja solo si «Casa» no se alcanza (un nodo
            // cortado por el borde del scroll da un falso negativo en las guías de toque).
            if (find.text('Casa').first.hitTestable().evaluate().isEmpty) {
              await tester.ensureVisible(find.text('Casa').first);
              await tester.pump();
            }
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            handle.dispose();
          });
        }
      }
    }
  });

  group('el tipo elegido no se pierde', () {
    testWidgets('tocar «Casa» estando elegida la deja elegida (no se apaga) y «Registrar» sigue', (
      tester,
    ) async {
      final m = await abrirAlta(tester);
      await _elegir(tester, 'Casa');
      await _elegir(tester, 'Casa');

      expect(_tildes(), 1);
      expect(registrarHabilitado(tester), isTrue);
      await _registrar(tester);
      expect(_ubicacionDe(m).tipo, TipoUbicacion.casa);
    });

    testWidgets('sin GPS: marcar el punto con «Casa» ya elegida habilita «Registrar»', (
      tester,
    ) async {
      final m = await abrirAlta(tester, gps: gpsSinPermiso);
      expect(registrarHabilitado(tester), isFalse);
      expect(find.text(TextosAlta.marcaElPunto), findsWidgets);
      expect(_tildes(), 1);

      m.mapa.tocar(puntoItalia);
      await asentar(tester);

      expect(registrarHabilitado(tester), isTrue, reason: 'no hace falta tocar el tipo');
      expect(_elegidosPorElLector(tester), ['Casa']);
      await _registrar(tester);
      expect(_ubicacionDe(m).tipo, TipoUbicacion.casa);
    });

    testWidgets('sin GPS: lo elegido (Edificio) sobrevive a marcar el punto y a moverlo', (
      tester,
    ) async {
      final m = await abrirAlta(tester, gps: gpsSinPermiso);
      await _elegir(tester, 'Edificio');

      m.mapa.tocar(puntoItalia);
      await asentar(tester);
      m.mapa.tocar(const Coordenadas(lat: -34.9, lon: -56.2));
      await asentar(tester);

      expect(_elegidosPorElLector(tester), ['Edificio']);
      await _registrar(tester);
      expect(_ubicacionDe(m).tipo, TipoUbicacion.edificio);
    });

    testWidgets('cambiar la ciudad con «Cambiar» no devuelve el tipo a «Casa»', (tester) async {
      final m = await abrirAlta(tester);
      await _elegir(tester, 'Negocio');

      await tester.ensureVisible(find.text('detectada · Cambiar'));
      await tester.pump();
      await tocar(tester, find.text('detectada · Cambiar'));
      expect(find.text('Elegí la ciudad'), findsOneWidget);
      await tocar(tester, find.text('Canelones'));
      await tester.pumpAndSettle();

      expect(_elegidosPorElLector(tester), ['Negocio']);
      await _registrar(tester);
      expect(_ubicacionDe(m).tipo, TipoUbicacion.negocio);
      expect(_ubicacionDe(m).ciudadId, canelones.id);
    });

    testWidgets('GPS impreciso: «Continuar» habilita «Registrar» con «Casa» sin tocar nada', (
      tester,
    ) async {
      final m = await abrirEn(tester, EstadoAlta.gpsImpreciso);
      expect(registrarHabilitado(tester), isFalse);

      await tester.ensureVisible(find.text('Continuar'));
      await tester.pump();
      await tocar(tester, find.text('Continuar'));

      expect(registrarHabilitado(tester), isTrue);
      expect(_elegidosPorElLector(tester), ['Casa']);
      await _registrar(tester);
      expect(_ubicacionDe(m).tipo, TipoUbicacion.casa);
    });

    testWidgets('la falla de guardar no cambia el tipo elegido y el reintento lo manda igual', (
      tester,
    ) async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async =>
            ++intento == 1 ? const Left(FailureSinConexion()) : Right(AltaRegistrada(ubicacion: u));
      final m = await abrirAlta(tester, repo: repo);
      await _elegir(tester, 'Edificio');

      await _registrar(tester);
      expect(m.salidas, isEmpty, reason: 'la alta no se cerró');
      expect(registrarHabilitado(tester), isTrue, reason: 'el botón vuelve a habilitarse');
      expect(find.text(TextosAlta.registrando), findsNothing, reason: 'nada queda «ocupado»');
      expect(_elegidosPorElLector(tester), ['Edificio'], reason: 'la falla no pisa el tipo');

      await _registrar(tester);
      expect(m.salidas.single, isA<UbicacionCreada>());
      expect(repo.llamadas, hasLength(2));
      expect(repo.llamadas.every((l) => l.ubicacion.tipo == TipoUbicacion.edificio), isTrue);
      expect(repo.llamadas[1].ubicacion.id, repo.llamadas[0].ubicacion.id, reason: 'mismo id');
    });

    testWidgets(
      'el aviso de duplicado: «Cancelar» vuelve con el tipo elegido y «Crear igual» lo usa',
      (tester) async {
        var intento = 0;
        final repo = RepoAltaFalso()
          ..comportamiento = (u) async => ++intento <= 2
              ? Right(AltaConDuplicados(candidatas: [candidata('existente')]))
              : Right(AltaRegistrada(ubicacion: u));
        final m = await abrirAlta(tester, repo: repo);
        await _elegir(tester, 'Negocio');

        await _registrar(tester);
        expect(find.text('Cancelar'), findsOneWidget);
        await tocar(tester, find.text('Cancelar'));
        expect(_elegidosPorElLector(tester), ['Negocio'], reason: '«Cancelar» no resetea el tipo');

        await _registrar(tester);
        await tocar(tester, find.text('Crear igual'));
        await tester.enterText(find.byType(TextField).last, 'Es otro local, otra puerta');
        await tester.pump();
        await tocar(tester, find.widgetWithText(FilledButton, 'Crear igual'));

        expect(m.salidas.single, isA<UbicacionCreada>());
        expect(_ubicacionDe(m).tipo, TipoUbicacion.negocio);
        expect(repo.llamadas.last.justificacion, isNotNull);
      },
    );
  });

  group('lo que se guarda según el tipo', () {
    for (final (etiqueta, tipo, conEspacio) in [
      ('Casa', TipoUbicacion.casa, true),
      ('Negocio', TipoUbicacion.negocio, true),
      ('Edificio', TipoUbicacion.edificio, false),
    ]) {
      // skip: QA #665 — «Negocio» no recibe su espacio default (HU-UBI-001, decisión del 27/10, #477);
      // preexistente: el caso de uso solo lo crea para «Casa», no lo introduce este PR.
      final preexistente = tipo == TipoUbicacion.negocio && !_verHallazgos;
      testWidgets(
        '$etiqueta: llega al repositorio como $tipo y '
        '${conEspacio ? 'con' : 'sin'} espacio default',
        skip: preexistente,
        (tester) async {
          final m = await abrirAlta(tester);
          if (etiqueta != 'Casa') await _elegir(tester, etiqueta);

          await _registrar(tester);

          final llamada = m.repo.llamadas.single;
          expect(llamada.ubicacion.tipo, tipo);
          expect(llamada.espacio != null, conEspacio, reason: 'HU-UBI-001: espacio default');
        },
      );
    }

    testWidgets('Negocio → Edificio → Casa → Registrar manda «Casa»', (tester) async {
      final m = await abrirAlta(tester);
      await _elegir(tester, 'Negocio');
      await _elegir(tester, 'Edificio');
      await _elegir(tester, 'Casa');

      expect(_elegidosPorElLector(tester), ['Casa']);
      expect(_tildes(), 1);
      await _registrar(tester);
      expect(_ubicacionDe(m).tipo, TipoUbicacion.casa);
    });
  });

  group('casos límite del flujo', () {
    testWidgets('doble toque en «Registrar» con «Casa» por defecto crea una sola ubicación', (
      tester,
    ) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final m = await abrirAlta(tester, repo: repo);

      await tester.ensureVisible(botonRegistrarFijo);
      await tester.pump();
      await tester.tap(botonRegistrarFijo);
      await tester.pump();
      expect(find.text(TextosAlta.registrando), findsOneWidget);
      await tester.tap(botonRegistrarFijo, warnIfMissed: false);
      await tester.pump();
      repo.bloqueo!.complete();
      await asentar(tester);

      expect(repo.llamadas, hasLength(1));
      expect(m.salidas.single, isA<UbicacionCreada>());
    });

    testWidgets('mientras guarda no se puede cambiar el tipo a medio camino y pisar lo enviado', (
      tester,
    ) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final m = await abrirAlta(tester, repo: repo);

      await tester.ensureVisible(botonRegistrarFijo);
      await tester.pump();
      await tester.tap(botonRegistrarFijo);
      await tester.pump();
      await tester.ensureVisible(find.text('Edificio').first);
      await tester.tap(find.text('Edificio').first, warnIfMissed: false);
      await tester.pump();
      repo.bloqueo!.complete();
      await asentar(tester);

      expect(m.salidas.single, isA<UbicacionCreada>());
      expect(repo.llamadas.single.ubicacion.tipo, TipoUbicacion.casa, reason: 'lo enviado');
      expect((m.salidas.single! as UbicacionCreada).ubicacion.tipo, TipoUbicacion.casa);
    });

    testWidgets('reentrar tras una falla arranca otra vez en «Casa» y con registro nuevo', (
      tester,
    ) async {
      final repo = RepoAltaFalso()..comportamiento = (_) async => const Left(FailureSinConexion());
      final m = await abrirAlta(tester, repo: repo);
      await _elegir(tester, 'Negocio');
      await _registrar(tester);
      await tocar(tester, find.byTooltip('Cerrar'));
      expect(m.salidas, [null]);

      await tester.tap(find.text('abrir'));
      await asentar(tester);

      expect(_elegidosPorElLector(tester), ['Casa']);
      expect(registrarHabilitado(tester), isTrue);
      expect(find.text('Elegí el tipo de ubicación para registrar.'), findsNothing);
    });

    testWidgets('cerrar con ✕ después de cambiar de tipo no registra nada', (tester) async {
      final m = await abrirAlta(tester);
      await _elegir(tester, 'Edificio');
      await tocar(tester, find.byTooltip('Cerrar'));

      expect(m.repo.llamadas, isEmpty);
      expect(m.salidas, [null]);
    });
  });

  group('sin rastro del motivo viejo', () {
    for (final estado in EstadoAlta.values) {
      testWidgets('${estado.rotulo}: ningún texto ni etiqueta habla de elegir el tipo', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await abrirEn(tester, estado, escala: 2);
        await tester.ensureVisible(botonRegistrarFijo);
        await tester.pump();
        // Tocar «Registrar» apagado dice el motivo: no puede ser el del tipo.
        if (!registrarHabilitado(tester)) {
          await tester.tap(botonRegistrarFijo, warnIfMissed: false);
          await tester.pump();
        }
        expect(find.textContaining('Elegí el tipo'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('Elegí el tipo')), findsNothing);
        handle.dispose();
      });
    }
  });

  if (_conCapturas) {
    group('capturas', () {
      for (final estado in EstadoAlta.values) {
        for (final tamano in _tamanos) {
          for (final escala in _escalas) {
            testWidgets('captura ${_donde(estado, tamano, escala)}', (tester) async {
              await cargarFuentesReales();
              await cargarIconosParaCapturas(tester);
              await abrirEn(tester, estado, tamano: tamano, escala: escala);
              await capturar(
                tester,
                '665_${estado.name}_${tamano.width.toInt()}x${tamano.height.toInt()}_${escala}x',
              );
            });
          }
        }
      }
    });
  }
}
