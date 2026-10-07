// QA de la vista 06 (#199, HU-UBI-003): la pestaña «Mapa» dentro de la pantalla principal REAL, con
// la barra de arriba, la barra de abajo y la barra de estado de 24 dp. Los tests del PR montan la
// pestaña en un `Scaffold` sin esas barras (el mapa mide el alto entero de la pantalla): en el
// teléfono el mapa mide ~140 dp menos y es ahí donde el aviso de conexión, los botones flotantes,
// «Referencias» y la hoja se pisan.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_ubicaciones_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/situacion_mapa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/mapa_descargas_arnes.dart';
import 'mapa_ubicaciones_arnes.dart' show asentarLista, chipReferencias, tocarAsa;
import 'mapa_ubicaciones_page_test.dart' show canvas;

final _sesion = Sesion(
  usuarioId: 'col-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

/// La barra de estado del teléfono, en dp.
const barraDeEstado = 24.0;

/// Lo que dejó montado [montarEnPantallaPrincipal].
final class PantallaPrincipal {
  PantallaPrincipal({required this.mapa, required this.repo, required this.captura});

  final FabricaMapaFalsa mapa;
  final RepoListaFalso repo;

  /// El borde para sacar capturas de todo lo que se ve.
  final GlobalKey captura;
}

/// Abre la pestaña «Mapa» de la pantalla principal real (`InicioPage`) en un teléfono de [tamano]
/// con la barra de estado de [barra] dp y el texto a [escala].
Future<PantallaPrincipal> montarEnPantallaPrincipal(
  WidgetTester tester, {
  RepoListaFalso? repo,
  GpsFalso? gps,
  ArnesMapa? arnes,
  AmbitoTrabajo? ambito,
  Size tamano = const Size(360, 640),
  double escala = 1,
  double barra = barraDeEstado,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: barra);
  tester.view.viewPadding = FakeViewPadding(top: barra);
  addTearDown(tester.view.reset);
  final montaje = PantallaPrincipal(
    mapa: FabricaMapaFalsa(),
    repo: repo ?? RepoListaFalso(),
    captura: GlobalKey(),
  );
  // Sin esperar: con una descarga hecha, `cerrar()` no termina bajo el reloj falso del test.
  if (arnes != null) addTearDown(() => unawaited(arnes.cerrar()));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => DateTime(2026, 10, 6, 15)),
        ...overridesLista(repo: montaje.repo, gps: gps),
        montaje.mapa.override,
        if (arnes != null)
          ...arnes.overrides
        else
          situacionMapaProvider.overrideWith(
            (ref, _) => const SituacionMapa(fuente: FuenteMapa.sinTiles()),
          ),
        ambitoMapaUbicacionesProvider.overrideWith2(
          (_) => AmbitoFijo(ambito ?? const AmbitoTrabajo()),
        ),
      ],
      child: RepaintBoundary(
        key: montaje.captura,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
            child: child!,
          ),
          home: InicioPage(sesion: _sesion),
        ),
      ),
    ),
  );
  await asentarLista(tester);
  await tester.tap(find.byKey(const Key('inicio_pestana_mapa')));
  await asentarLista(tester);
  return montaje;
}

/// Guarda lo que se ve en `.dart_tool/qa_capturas/<nombre>.png` (nunca se commitea).
Future<void> capturar(WidgetTester tester, PantallaPrincipal p, String nombre) async {
  await tester.runAsync(() async {
    final limite = p.captura.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 1.5);
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('.dart_tool/qa_capturas/$nombre.png')..parent.createSync(recursive: true);
    archivo.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Por qué [objetivo] no se puede tocar (con lo que hay encima), o `null` si se puede.
String? motivoInaccesible(WidgetTester tester, Finder objetivo) {
  if (objetivo.evaluate().length != 1) return 'no está (${objetivo.evaluate().length} veces)';
  final rect = tester.getRect(objetivo);
  final centro = rect.center;
  final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
  if (centro.dx < 0 || centro.dy < 0 || centro.dx > pantalla.width || centro.dy > pantalla.height) {
    return 'su centro $centro queda fuera de la pantalla $pantalla';
  }
  final camino = tester.hitTestOnBinding(centro).path.map((entrada) => entrada.target).toList();
  if (camino.contains(tester.renderObject(objetivo))) return null;
  return 'tapado en $rect por ${camino.isEmpty ? 'nada' : camino.first.runtimeType}';
}

/// Como [motivoInaccesible], pero si [objetivo] está dentro de algo que se desliza (la tarjeta del
/// aviso) lo desliza hasta ponerlo a la vista, en el sentido que haga falta: un botón fuera de la
/// vista pero al que se llega con el dedo no es un problema; uno que ni deslizando queda a la vista
/// y sin nada encima, sí. (Desplazar de a 120 dp hacia un solo lado no sirve de prueba: un botón
/// que quedó arriba por haber tocado el de abajo parece inalcanzable y no lo es, y en una tira de
/// 80 dp de alto un solo paso lo pasa de largo.)
Future<String?> motivoSinAlcance(WidgetTester tester, Finder objetivo) async {
  final motivo = motivoInaccesible(tester, objetivo);
  final desplazables = find.ancestor(of: objetivo, matching: find.byType(Scrollable));
  if (motivo == null || desplazables.evaluate().isEmpty) return motivo;
  await Scrollable.ensureVisible(tester.element(objetivo), alignment: .5);
  await tester.pump(const Duration(milliseconds: 300));
  return motivoInaccesible(tester, objetivo);
}

/// Cuáles de [objetivos] no se pueden tocar ni deslizando, con el motivo.
Future<List<String>> inaccesibles(WidgetTester tester, Map<String, Finder> objetivos) async => [
  for (final MapEntry(key: nombre, value: finder) in objetivos.entries)
    if (await motivoSinAlcance(tester, finder) case final motivo?) '$nombre: $motivo',
];

Finder get _descargar => find.widgetWithText(FilledButton, 'Descargar mapa');
Finder get _activarDatos => find.widgetWithText(OutlinedButton, 'Activar datos');
Finder get _minimizar => find.byTooltip('Minimizar aviso');
Finder get _descargarConPeso =>
    find.ancestor(of: find.textContaining('Descargar mapa ·'), matching: find.byType(FilledButton));
Finder get _ahoraNo => find.widgetWithText(TextButton, 'Ahora no');

typedef _Escena = ({
  String nombre,
  Future<PantallaPrincipal> Function(WidgetTester, Size, double) montar,
  Map<String, Finder> Function() botones,
});

ArnesMapa _sinConexion() =>
    ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);

final _avisos = <_Escena>[
  (
    nombre: 'sin conexión, con la ciudad conocida',
    montar: (t, tam, e) => montarEnPantallaPrincipal(
      t,
      repo: RepoListaFalso(canvas()),
      arnes: _sinConexion(),
      ambito: ambitoMontevideo,
      tamano: tam,
      escala: e,
    ),
    botones: () => {
      '«Descargar mapa»': _descargar,
      '«Activar datos»': _activarDatos,
      '✕ «Minimizar aviso»': _minimizar,
    },
  ),
  (
    nombre: 'sin conexión, sin la ciudad',
    montar: (t, tam, e) => montarEnPantallaPrincipal(
      t,
      repo: RepoListaFalso(canvas()),
      arnes: _sinConexion(),
      tamano: tam,
      escala: e,
    ),
    botones: () => {'«Activar datos»': _activarDatos, '✕ «Minimizar aviso»': _minimizar},
  ),
  (
    nombre: 'con datos móviles',
    montar: (t, tam, e) => montarEnPantallaPrincipal(
      t,
      repo: RepoListaFalso(canvas()),
      arnes: ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]),
      ambito: ambitoMontevideo,
      tamano: tam,
      escala: e,
    ),
    botones: () => {'«Descargar mapa · N MB»': _descargarConPeso, '«Ahora no»': _ahoraNo},
  ),
];

void main() {
  const telefonos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

  group('QA #199 · el aviso de conexión sobre la pantalla principal real', () {
    for (final MapEntry(key: tam, value: tamano) in telefonos.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final aviso in _avisos) {
          final caso = 'aviso:${aviso.nombre}:$tam:$escala:0';
          testWidgets(
            'con la hoja minimizada, cada botón de «${aviso.nombre}» se puede tocar (o se llega '
            'deslizando la tarjeta) · $tam · texto $escala',
            (tester) async {
              await aviso.montar(tester, tamano, escala);

              expect(tester.takeException(), isNull);
              expect(await inaccesibles(tester, aviso.botones()), isEmpty, reason: caso);
            },
          );
        }
      }
    }

    for (final MapEntry(key: tam, value: tamano) in telefonos.entries) {
      for (final altura in [(1, 'a 1/3'), (2, 'a 1/2')]) {
        for (final aviso in _avisos) {
          final caso = 'aviso:${aviso.nombre}:$tam:1.0:${altura.$1}';
          testWidgets(
            'con la hoja ${altura.$2}, cada botón de «${aviso.nombre}» se puede tocar · $tam',
            (tester) async {
              await aviso.montar(tester, tamano, 1);
              await tocarAsa(tester, altura.$1);

              expect(tester.takeException(), isNull);
              expect(await inaccesibles(tester, aviso.botones()), isEmpty, reason: caso);
            },
          );
        }
      }
    }

    for (final MapEntry(key: tam, value: tamano) in telefonos.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final altura in [(0, 'minimizada'), (2, 'a 1/2')]) {
          final caso = 'pildora:$tam:$escala:${altura.$1}';
          testWidgets(
            'la píldora «Sin conexión · Descargar mapa» con la hoja ${altura.$2} se puede tocar · '
            '$tam · texto $escala',
            (tester) async {
              await _avisos.first.montar(tester, tamano, escala);
              await tester.tap(_minimizar);
              await asentarLista(tester);
              if (altura.$1 > 0) await tocarAsa(tester, altura.$1);

              expect(tester.takeException(), isNull);
              expect(
                await inaccesibles(tester, {'píldora': find.byKey(ClavesAvisoMapa.pildora)}),
                isEmpty,
                reason: caso,
              );
            },
          );
        }
      }
    }

    testWidgets('sin la ciudad no se ofrece «Descargar mapa», ni en la tarjeta ni en la píldora', (
      tester,
    ) async {
      await _avisos[1].montar(tester, telefonos['360x640']!, 1);
      expect(find.textContaining('Descargar mapa'), findsNothing);

      await tester.tap(_minimizar);
      await asentarLista(tester);
      expect(find.byKey(ClavesAvisoMapa.pildora), findsOneWidget);
      expect(find.textContaining('Descargar mapa'), findsNothing);
    });
  });

  group('QA #199 · los botones flotantes y «Referencias» sobre la pantalla principal real', () {
    for (final MapEntry(key: tam, value: tamano) in telefonos.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final altura in [(0, 'minimizada'), (1, 'a 1/3'), (2, 'a 1/2')]) {
          final caso = 'flotantes:$tam:$escala:${altura.$1}';
          testWidgets(
            '«Referencias», «Mi ubicación» y «Nueva» con la hoja ${altura.$2} se pueden tocar y no '
            'se tapan entre sí · $tam · texto $escala',
            (tester) async {
              await montarEnPantallaPrincipal(
                tester,
                repo: RepoListaFalso(canvas()),
                tamano: tamano,
                escala: escala,
              );
              if (altura.$1 > 0) await tocarAsa(tester, altura.$1);

              expect(tester.takeException(), isNull);
              expect(
                await inaccesibles(tester, {
                  '«Referencias»': chipReferencias,
                  '«Mi ubicación»': find.byKey(ClavesMapaUbicaciones.miUbicacion),
                  '«Nueva»': find.byKey(ClavesMapaUbicaciones.nueva),
                  'el asa': find.byKey(ClavesMapaUbicaciones.asa),
                }),
                isEmpty,
                reason: caso,
              );
              final chip = tester.getRect(chipReferencias);
              final miUbicacion = tester.getRect(find.byKey(ClavesMapaUbicaciones.miUbicacion));
              expect(
                chip.overlaps(miUbicacion),
                isFalse,
                reason: '$caso: «Referencias» $chip pisa a «Mi ubicación» $miUbicacion',
              );
            },
          );
        }
      }
    }
  });

  group('QA #199 · sin ubicaciones y con error de lectura en la pantalla principal real', () {
    for (final MapEntry(key: tam, value: tamano) in telefonos.entries) {
      for (final escala in [1.0, 2.0]) {
        final vacio = 'vacio:$tam:$escala';
        testWidgets(
          'el vacío deja «Registrar tu primera ubicación» al alcance (a la vista o deslizando) · '
          '$tam · texto $escala',
          (tester) async {
            await montarEnPantallaPrincipal(tester, tamano: tamano, escala: escala);

            expect(tester.takeException(), isNull);
            expect(
              await inaccesibles(tester, {
                '«Registrar tu primera ubicación»': find.byKey(
                  ClavesMapaUbicaciones.registrarPrimera,
                ),
              }),
              isEmpty,
              reason: vacio,
            );
          },
        );

        final error = 'error:$tam:$escala';
        testWidgets(
          'el error de lectura deja «Reintentar» al alcance (a la vista o deslizando) · $tam · '
          'texto $escala',
          (tester) async {
            await montarEnPantallaPrincipal(
              tester,
              repo: RepoListaFalso(canvas())..fallaAlSuscribir = true,
              tamano: tamano,
              escala: escala,
            );

            expect(tester.takeException(), isNull);
            expect(
              await inaccesibles(tester, {
                '«Reintentar»': find.byKey(ClavesMapaUbicaciones.reintentar),
              }),
              isEmpty,
              reason: error,
            );
          },
        );
      }
    }
  });
}
