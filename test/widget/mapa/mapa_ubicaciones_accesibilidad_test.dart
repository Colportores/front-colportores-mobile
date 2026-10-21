// HU-UBI-003 · vista 06 (#199): cada estado de la vista a 360x640 y 412x915, con el texto a 1.0 y
// a 2.0 (`textScaler`): sin desbordes, con las guías de accesibilidad de Flutter (objetivo táctil de
// 48 dp, nombres, contraste) y con el lector de pantalla diciendo lo que corresponde.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart' show GpsFalso;
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_descargas_arnes.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas, gpsSinPermiso;

/// Cuántos nodos de semántica leen [texto] (en la etiqueta, la pista o el valor): cada uno es una lectura
/// del lector de pantalla. Un nodo que se funde en su padre ya va dentro de la etiqueta del padre: no
/// cuenta aparte.
int _lecturasDe(WidgetTester tester, String texto) {
  var lecturas = 0;
  void visitar(SemanticsNode nodo) {
    final d = nodo.getSemanticsData();
    if (!nodo.isMergedIntoParent && [d.label, d.hint, d.value].any((t) => t.contains(texto))) {
      lecturas++;
    }
    nodo.visitChildren((hijo) {
      visitar(hijo);
      return true;
    });
  }

  visitar(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return lecturas;
}

typedef _Escena =
    Future<MontajeMapaUbicaciones> Function(WidgetTester tester, Size tamano, double escala);

/// Cada estado de la vista, armado como lo vería el colportor.
final _escenas = <String, _Escena>{
  'hoja minimizada': (t, tam, e) =>
      montarMapaUbicaciones(t, repo: RepoListaFalso(canvas()), tamano: tam, escala: e),
  'hoja a 1/3': (t, tam, e) async {
    final m = await montarMapaUbicaciones(
      t,
      repo: RepoListaFalso(canvas()),
      tamano: tam,
      escala: e,
    );
    await tocarAsa(t);
    return m;
  },
  'hoja a 1/2': (t, tam, e) async {
    final m = await montarMapaUbicaciones(
      t,
      repo: RepoListaFalso(canvas()),
      tamano: tam,
      escala: e,
    );
    await tocarAsa(t, 2);
    return m;
  },
  'vista previa': (t, tam, e) async {
    final m = await montarMapaUbicaciones(
      t,
      repo: RepoListaFalso(canvas()),
      tamano: tam,
      escala: e,
    );
    m.mapa.tocarPunto('a');
    await asentarLista(t);
    return m;
  },
  'vista previa con una dirección larguísima': (t, tam, e) async {
    final repo = RepoListaFalso([
      filaLista(
        'larga',
        tipo: TipoUbicacion.edificio,
        calle: 'Avenida General Don José Gervasio Artigas y Camino Maldonado ' * 3,
        numero: '1234567890',
        metrosAlNorte: 30,
        espacios: 12,
      ),
    ]);
    final m = await montarMapaUbicaciones(t, repo: repo, tamano: tam, escala: e);
    m.mapa.tocarPunto('larga');
    await asentarLista(t);
    return m;
  },
  'lista con direcciones largas': (t, tam, e) async {
    final repo = RepoListaFalso([
      for (var i = 0; i < 6; i++)
        filaLista(
          'l$i',
          calle: 'Avenida General Don José Gervasio Artigas y Camino Maldonado $i',
          numero: '${1000 + i}',
          metrosAlNorte: 30.0 * (i + 1),
          espacios: 3,
        ),
    ]);
    final m = await montarMapaUbicaciones(t, repo: repo, tamano: tam, escala: e);
    await tocarAsa(t, 2);
    return m;
  },
  'cargando': (t, tam, e) async {
    final repo = RepoListaFalso(canvas())..bloqueo = Completer<void>();
    final m = await montarMapaUbicaciones(t, repo: repo, tamano: tam, escala: e);
    await tocarAsa(t);
    return m;
  },
  'sin ubicaciones': (t, tam, e) =>
      montarMapaUbicaciones(t, repo: RepoListaFalso(), tamano: tam, escala: e),
  'solo bajas': (t, tam, e) => montarMapaUbicaciones(
    t,
    repo: RepoListaFalso([filaLista('z', baja: DateTime.utc(2026, 9, 12))]),
    tamano: tam,
    escala: e,
  ),
  'error de lectura': (t, tam, e) => montarMapaUbicaciones(
    t,
    repo: RepoListaFalso(canvas())..fallaAlSuscribir = true,
    tamano: tam,
    escala: e,
  ),
  'sin GPS': (t, tam, e) async {
    final m = await montarMapaUbicaciones(
      t,
      repo: RepoListaFalso(canvas()),
      gps: gpsSinPermiso(),
      tamano: tam,
      escala: e,
    );
    await tocarAsa(t);
    return m;
  },
  'aviso sin conexión, con la ciudad conocida': (t, tam, e) => montarMapaUbicaciones(
    t,
    repo: RepoListaFalso(canvas()),
    arnes: ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]),
    ambito: ambitoMontevideo,
    tamano: tam,
    escala: e,
  ),
  'aviso sin conexión, sin ciudad': (t, tam, e) => montarMapaUbicaciones(
    t,
    repo: RepoListaFalso(canvas()),
    arnes: ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]),
    tamano: tam,
    escala: e,
  ),
  'píldora «Sin conexión · Descargar mapa»': (t, tam, e) async {
    final m = await montarMapaUbicaciones(
      t,
      repo: RepoListaFalso(canvas()),
      arnes: ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]),
      ambito: ambitoMontevideo,
      tamano: tam,
      escala: e,
    );
    await t.tap(find.byTooltip('Minimizar aviso'));
    await asentarLista(t);
    return m;
  },
  'aviso de datos móviles': (t, tam, e) => montarMapaUbicaciones(
    t,
    repo: RepoListaFalso(canvas()),
    arnes: ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]),
    ambito: ambitoMontevideo,
    tamano: tam,
    escala: e,
  ),
  'leyenda «Referencias»': (t, tam, e) async {
    final m = await montarMapaUbicaciones(
      t,
      repo: RepoListaFalso(canvas()),
      tamano: tam,
      escala: e,
    );
    await t.tap(chipReferencias);
    await asentarLista(t);
    return m;
  },
};

void main() {
  const tamanos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

  for (final MapEntry(key: nombreTamano, value: tamano) in tamanos.entries) {
    for (final escala in [1.0, 2.0]) {
      for (final MapEntry(key: nombre, value: armar) in _escenas.entries) {
        testWidgets('$nombre · $nombreTamano · texto $escala: sin desbordes y accesible', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await armar(tester, tamano, escala);

          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }
  }

  group('objetivos táctiles de 48 dp', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('los botones y el asa miden al menos 48 x 48 con el texto a $escala', (
        tester,
      ) async {
        await montarMapaUbicaciones(
          tester,
          repo: RepoListaFalso(canvas()),
          tamano: const Size(360, 640),
          escala: escala,
        );

        for (final (nombre, buscar) in [
          ('asa', asa),
          ('Mi ubicación', botonMiUbicacion),
          ('Nueva', botonNueva),
          ('Referencias', chipReferencias),
        ]) {
          final tam = tester.getSize(buscar);
          expect(tam.width, greaterThanOrEqualTo(48), reason: nombre);
          expect(tam.height, greaterThanOrEqualTo(48), reason: nombre);
        }
        expect(tester.getSize(asa).height, AlturaHoja.altoAsa);
      });
    }

    testWidgets('la ✕ de la vista previa, «Reintentar» y «Activar GPS» también', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas()),
        gps: gpsSinPermiso(),
        tamano: const Size(360, 640),
      );
      await tocarAsa(tester);
      for (final (nombre, buscar) in [
        ('Activar GPS', find.byKey(ClavesMapaUbicaciones.activarGps)),
      ]) {
        final tam = tester.getSize(buscar);
        expect(tam.width, greaterThanOrEqualTo(48), reason: nombre);
        expect(tam.height, greaterThanOrEqualTo(48), reason: nombre);
      }

      m.mapa.tocarPunto('a');
      await asentarLista(tester);
      final cerrar = tester.getSize(cerrarVistaPrevia);
      expect(cerrar.width, greaterThanOrEqualTo(48));
      expect(cerrar.height, greaterThanOrEqualTo(48));
    });

    testWidgets('«Reintentar» mide al menos 48 dp', (tester) async {
      await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas())..fallaAlSuscribir = true,
        tamano: const Size(360, 640),
        escala: 2,
      );

      final tam = tester.getSize(find.byKey(ClavesMapaUbicaciones.reintentar));
      expect(tam.width, greaterThanOrEqualTo(48));
      expect(tam.height, greaterThanOrEqualTo(48));
    });
  });

  group('lector de pantalla', () {
    testWidgets('el asa dice la altura y deja subir y bajar la hoja', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      final asaSemantica = find.semantics.byLabel('Cambiar altura de la hoja');

      final minimizada = asaSemantica.evaluate().single;
      expect(minimizada.value, 'Minimizada');
      expect(minimizada.increasedValue, 'A un tercio de la pantalla');

      tester.semantics.performAction(asaSemantica, SemanticsAction.increase);
      await asentarLista(tester, 6);
      expect(altoHoja(tester), closeTo(844 / 3, 1));

      expect(asaSemantica.evaluate().single.value, 'A un tercio de la pantalla');
      tester.semantics.performAction(asaSemantica, SemanticsAction.decrease);
      await asentarLista(tester, 6);
      expect(altoHoja(tester), AlturaHoja.altoMinimizada(TextScaler.noScaling));
      semantica.dispose();
    });

    // #359 (seguimiento de #355): el motivo va en la ETIQUETA del botón apagado y la pista queda vacía,
    // igual en Android y en iOS: con «Hablar pistas» apagado en VoiceOver una pista no se leería.
    testWidgets(
      '«Mi ubicación» sin GPS dice «Mi ubicación. No disponible: no hay GPS.» en la etiqueta, sin '
      'pista, y el motivo se lee una sola vez',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gpsSinPermiso());
        await tocarAsa(tester);

        final nodo = tester.getSemantics(botonMiUbicacion).getSemanticsData();
        expect(nodo.label, 'Mi ubicación. No disponible: no hay GPS.');
        expect(nodo.hint, isEmpty, reason: 'sin pista: con «Hablar pistas» apagado no se leería');
        expect(nodo.hasAction(SemanticsAction.tap), isFalse, reason: 'apagado no se toca');
        expect(_lecturasDe(tester, 'No disponible'), 1, reason: 'el motivo se lee una sola vez');
        expect(_lecturasDe(tester, 'Mi ubicación'), 1, reason: 'el nombre también');
        semantica.dispose();
      },
      variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}),
    );

    testWidgets(
      '«Mi ubicación» con GPS dice solo «Mi ubicación», sin motivo ni pista, y se puede tocar',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

        final nodo = tester.getSemantics(botonMiUbicacion).getSemanticsData();
        expect(nodo.label, 'Mi ubicación');
        expect(nodo.hint, isEmpty);
        expect(nodo.hasAction(SemanticsAction.tap), isTrue);
        expect(_lecturasDe(tester, 'No disponible'), 0);
        expect(_lecturasDe(tester, 'Mi ubicación'), 1);
        semantica.dispose();
      },
      variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}),
    );

    // Decisión de Cristian/mapa §2 (16/10, PR #378): mientras busca el GPS todavía no se sabe si hay, así que
    // el lector no dice «no hay GPS»: dice que está buscando.
    testWidgets(
      '«Mi ubicación» buscando el GPS dice «Mi ubicación. No disponible: buscando GPS…», sin pista y '
      'sin «no hay GPS»',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final gps = GpsFalso()..bloqueo = Completer<void>();
        await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gps);

        final nodo = tester.getSemantics(botonMiUbicacion).getSemanticsData();
        expect(nodo.label, 'Mi ubicación. No disponible: buscando GPS…');
        expect(nodo.hint, isEmpty);
        expect(nodo.hasAction(SemanticsAction.tap), isFalse, reason: 'apagado no se toca');
        expect(_lecturasDe(tester, 'buscando GPS'), 1, reason: 'el motivo se lee una sola vez');
        expect(_lecturasDe(tester, 'no hay GPS'), 0, reason: 'no se afirma lo que no se sabe');
        gps.bloqueo!.complete();
        await asentarLista(tester);
        semantica.dispose();
      },
      variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}),
    );

    testWidgets(
      '«Mi ubicación» pasa de «buscando GPS…» a «Mi ubicación» cuando llega la lectura y no queda el '
      'motivo viejo',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final gps = GpsFalso()..bloqueo = Completer<void>();
        await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gps);

        expect(
          tester.getSemantics(botonMiUbicacion).label,
          'Mi ubicación. No disponible: buscando GPS…',
          reason: 'mientras no hay lectura, el botón está apagado y dice por qué',
        );

        gps.bloqueo!.complete();
        await asentarLista(tester);

        final nodo = tester.getSemantics(botonMiUbicacion).getSemanticsData();
        expect(nodo.label, 'Mi ubicación');
        expect(nodo.hint, isEmpty);
        expect(nodo.hasAction(SemanticsAction.tap), isTrue);
        expect(_lecturasDe(tester, 'No disponible'), 0);
        semantica.dispose();
      },
    );

    testWidgets(
      '«Mi ubicación» pasa de «buscando GPS…» a «no hay GPS» cuando la lectura falla y no queda el '
      'motivo viejo',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final gps = gpsSinPermiso()..bloqueo = Completer<void>();
        await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gps);

        expect(
          tester.getSemantics(botonMiUbicacion).label,
          'Mi ubicación. No disponible: buscando GPS…',
        );

        gps.bloqueo!.complete();
        await asentarLista(tester);

        final nodo = tester.getSemantics(botonMiUbicacion).getSemanticsData();
        expect(nodo.label, 'Mi ubicación. No disponible: no hay GPS.');
        expect(nodo.hint, isEmpty);
        expect(nodo.hasAction(SemanticsAction.tap), isFalse);
        expect(_lecturasDe(tester, 'buscando GPS'), 0);
        expect(_lecturasDe(tester, 'No disponible'), 1);
        semantica.dispose();
      },
    );

    for (final escala in [1.0, 2.0, 3.0]) {
      testWidgets('«Mi ubicación» sin GPS, con el texto a ${escala}x: la misma etiqueta y el botón '
          'sigue en 48 dp o más', (tester) async {
        final semantica = tester.ensureSemantics();
        await montarMapaUbicaciones(
          tester,
          repo: RepoListaFalso(canvas()),
          gps: gpsSinPermiso(),
          tamano: const Size(360, 640),
          escala: escala,
        );

        expect(
          tester.getSemantics(botonMiUbicacion).label,
          'Mi ubicación. No disponible: no hay GPS.',
        );
        final tam = tester.getSize(botonMiUbicacion);
        expect(tam.width, greaterThanOrEqualTo(48));
        expect(tam.height, greaterThanOrEqualTo(48));
        semantica.dispose();
      });
    }

    testWidgets('la cuenta de la pestaña se lee «Cercanía, 6 ubicaciones»', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      expect(find.bySemanticsLabel('Cercanía, 6 ubicaciones'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('el mapa tiene nombre y cada fila se lee con dirección, estado y distancia', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await tocarAsa(tester);

      expect(find.bySemanticsLabel('Mapa de ubicaciones'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Av\. Italia 1234\. Cobranza pendiente · 2 espacios\. 40')),
        findsOneWidget,
      );
      semantica.dispose();
    });
  });
}
