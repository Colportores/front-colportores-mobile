// HU-UBI-003 · vista 06 (#199): cada estado de la vista a 360x640 y 412x915, con el texto a 1.0 y
// a 2.0 (`textScaler`): sin desbordes, con las guías de accesibilidad de Flutter (objetivo táctil de
// 48 dp, nombres, contraste) y con el lector de pantalla diciendo lo que corresponde.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_descargas_arnes.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas, gpsSinPermiso;

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

    testWidgets('«Mi ubicación» sin GPS se anuncia como no disponible', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gpsSinPermiso());

      final nodo = tester.getSemantics(botonMiUbicacion);
      expect(nodo.label, contains('Mi ubicación'));
      expect(nodo.hint, contains('No disponible'));
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      semantica.dispose();
    });

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
