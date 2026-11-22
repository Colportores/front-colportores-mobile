// QA de #619 (PR #637): «Mapas offline» (vista 35, HU-SYNC-010) con la fuente REAL de dónde trabaja la
// colportora. A diferencia de los tests del implementador (puertos en memoria), acá la página lee
// de Drift en memoria, con el pull simulado y el resolvedor real de la ciudad: de la fila a la pantalla.
//
// Los tests que documentan un hallazgo van con `skip` (se corren con `--dart-define=QA_HALLAZGOS=true`).
// Las capturas solo con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/` (gitignored).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/campanias_del_colportor_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/lugar_de_trabajo_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/zona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/zona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/ciudades_para_alta_local.dart';
import 'package:colportores_mobile/features/mapa/data/services/fuente_lugar_de_trabajo_local.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart'
    show relojAltaUbicacionProvider;
import 'package:colportores_mobile/features/mapa/presentation/providers/lugar_de_trabajo_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/presentation/pages/mapas_offline_page.dart';
import 'package:colportores_mobile/features/tiles/presentation/providers/mapas_offline_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../helpers/logger_mudo.dart';
import '../helpers/mapa_descargas_arnes.dart';
import '../helpers/replica_de_campanias.dart';
import '../helpers/tiles_falsos.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');
const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

const _colportor = 'col-uuid-0619-secreto';
final _hoy = DateTime.utc(2026, 10, 27, 15);

final _raiz = GlobalKey();

/// La lectura del lugar que se puede romper la primera vez, frenar con una compuerta y contar.
final class _LugaresIntermitentes implements LugarDeTrabajoLocalDataSource {
  _LugaresIntermitentes(this._real);

  final LugarDeTrabajoLocalDataSource _real;
  int fallar = 0;
  int llamadas = 0;
  Completer<void>? compuerta;

  @override
  Future<DatosDelLugar> leer({required Set<String> zonaIds, required String ciudadId}) async {
    llamadas++;
    final espera = compuerta;
    if (espera != null) await espera.future;
    if (fallar > 0) {
      fallar--;
      throw StateError('disco roto en $ciudadId');
    }
    return _real.leer(zonaIds: zonaIds, ciudadId: ciudadId);
  }
}

PaqueteTiles _paquete(
  String id,
  NivelCobertura nivel,
  String? ambitoId,
  String nombre,
  int megas,
) => PaqueteTiles(
  id: id,
  nivel: nivel,
  ambitoId: ambitoId,
  nombre: nombre,
  version: 'v1',
  partes: [
    ParteTiles(
      origen: Uri.parse('https://tiles.test/$id.pmtiles'),
      tamanoBytes: megas * 1000 * 1000,
      sha256: 'a' * 64,
    ),
  ],
);

final _catalogo = [
  _paquete('zona-centro', NivelCobertura.zona, 'z-centro', 'Centro', 14),
  _paquete('ciudad-mvd', NivelCobertura.ciudad, 'ciu-mvd', 'Montevideo', 86),
  _paquete('depto-mvd', NivelCobertura.departamento, 'montevideo', 'Montevideo', 250),
  _paquete('depto-sj', NivelCobertura.departamento, 'san jose', 'San José', 250),
  _paquete('depto-tt', NivelCobertura.departamento, 'treinta y tres', 'Treinta y Tres', 250),
  _paquete('uruguay', NivelCobertura.uruguay, null, 'Todo Uruguay', 1200),
];

/// El teléfono: la base real en memoria, el pull simulado y la fuente real armada encima.
final class _Telefono {
  _Telefono() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
    lugares = _LugaresIntermitentes(LugarDeTrabajoLocalDataSourceDrift(db));
  }

  late final AppDatabase db;
  late final ReplicaDeCampanias replica;
  late final _LugaresIntermitentes lugares;
  AppLogger logger = loggerMudo();

  FuenteLugarDeTrabajoLocal get fuente => FuenteLugarDeTrabajoLocal(
    colportorId: _colportor,
    ciudades: CiudadesParaAltaLocal(
      campanias: CampaniasDelColportorLocalDataSourceDrift(db),
      zonas: ZonaRepositoryImpl(ZonaLocalDataSourceDrift(db), logger: loggerMudo()),
      ahora: () => _hoy,
      logger: loggerMudo(),
    ),
    campanias: CampaniasDelColportorLocalDataSourceDrift(db),
    lugares: lugares,
    ahora: () => _hoy,
    logger: logger,
  );

  Map<String, Object?> _zona(String id, String nombre, String campaniaCiudad) => filaZona(
    id,
    nombre,
    campaniaCiudad: campaniaCiudad,
    latSur: -34.92,
    latNorte: -34.88,
    lonOeste: -56.20,
    lonEste: -56.15,
  );

  /// El pull completo: [ciudades] ya con su departamento, una campaña y, si [zonaAsignada], su zona.
  Future<void> bajar({
    String? zonaAsignada,
    bool conCanelones = false,
    bool zonasEnDosCiudades = false,
    String? departamento = 'Montevideo',
    String zonaNombre = 'Centro',
    String ciudadNombre = 'Montevideo',
  }) async {
    final dos = zonasEnDosCiudades;
    conCanelones = conCanelones || dos;
    await replica.bajar({
      'ciudad': [
        filaCiudad(
          'ciu-mvd',
          ciudadNombre,
          lat: -34.9011,
          lon: -56.1645,
          departamento: departamento,
        ),
        if (conCanelones)
          filaCiudad(
            'ciu-can',
            'Canelones',
            lat: -34.5228,
            lon: -56.2778,
            departamento: 'Canelones',
          ),
      ],
      'campania': [
        filaCampania('camp-1', 'Verano 2026'),
        if (dos) filaCampania('camp-2', 'Primavera 2026'),
      ],
      'campania_ciudad': [
        filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
        if (conCanelones)
          filaCampaniaCiudad('cc-can', campania: dos ? 'camp-2' : 'camp-1', ciudad: 'ciu-can'),
      ],
      'zona': [
        _zona('z-centro', zonaNombre, 'cc-mvd'),
        if (conCanelones) _zona('z-norte', 'Norte', 'cc-can'),
      ],
      'campania_colportor': [
        filaInscripcion('insc-1', campania: 'camp-1', usuario: _colportor, zona: zonaAsignada),
        if (dos)
          filaInscripcion('insc-2', campania: 'camp-2', usuario: _colportor, zona: 'z-norte'),
      ],
    });
    await replica.terminoUnPull();
  }
}

/// Deja correr la base (futuros reales) y los cuadros.
Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _cargarFuentes(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++, dir = dir.parent) {
    final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
      break;
    }
  }
});

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/619_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Widget _app({required _Telefono tel, required ArnesMapa arnes, double escala = 1}) => ProviderScope(
  overrides: [
    ...arnes.overrides,
    fuenteLugarDeTrabajoProvider.overrideWith((ref) => tel.fuente),
    medidorEspacioDiscoProvider.overrideWithValue(EspacioFalso()..libres = 4000 * 1000 * 1000),
  ],
  child: MaterialApp(
    theme: temaClaro(),
    builder: (context, child) => RepaintBoundary(
      key: _raiz,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
    ),
    home: const MapasOfflinePage(),
  ),
);

/// Monta la página con el teléfono [tel] y devuelve el arnés (para cerrarlo).
Future<ArnesMapa> _montar(
  WidgetTester tester,
  _Telefono tel, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  List<PaqueteTiles>? catalogo,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (_conCapturas) await _cargarFuentes(tester);
  final arnes = ArnesMapa(catalogo: catalogo ?? _catalogo, servirPaqueteMontevideo: false);
  addTearDown(() => unawaited(arnes.cerrar()));
  await tester.pumpWidget(_app(tel: tel, arnes: arnes, escala: escala));
  await _asentar(tester);
  return arnes;
}

/// Como `main.dart`: la página sobre `fuenteLugarDeTrabajoLocalProvider` (sesión, base abierta y el
/// aviso de que el pull escribió las réplicas), sin la fuente armada a mano.
Future<ArnesMapa> _montarConCadenaReal(
  WidgetTester tester,
  _Telefono tel, {
  List<PaqueteTiles>? catalogo,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final arnes = ArnesMapa(catalogo: catalogo ?? _catalogo, servirPaqueteMontevideo: false);
  addTearDown(() => unawaited(arnes.cerrar()));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...arnes.overrides,
        dbLocalProvider.overrideWith(() => _DbFija(tel.db)),
        sesionProvider.overrideWith(() => _SesionFija(_colportor)),
        relojAltaUbicacionProvider.overrideWithValue(() => _hoy),
        fuenteLugarDeTrabajoProvider.overrideWith(
          (ref) => ref.watch(fuenteLugarDeTrabajoLocalProvider),
        ),
        medidorEspacioDiscoProvider.overrideWithValue(EspacioFalso()..libres = 4000 * 1000 * 1000),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(key: _raiz, child: child),
        home: const MapasOfflinePage(),
      ),
    ),
  );
  await _asentar(tester);
  return arnes;
}

Future<void> _cerrar(WidgetTester tester, _Telefono tel) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(tel.db.close);
}

Finder _clave(String clave) => find.byKey(Key(clave));

/// Los avisos de «no se sabe dónde trabaja», para la matriz de tamaños.
final class _EstadoSinLugar {
  const _EstadoSinLugar(
    this.id,
    this.nombre,
    this.clave,
    this.preparar, {
    required this.conReintentar,
  });

  final String id;
  final String nombre;
  final String clave;
  final Future<void> Function(_Telefono) preparar;
  final bool conReintentar;
}

final _estadosSinLugar = [
  _EstadoSinLugar(
    'sin_zona_varias',
    'sin zona y varias ciudades',
    'mapas_offline_sin_ciudad_elegible',
    (t) => t.bajar(conCanelones: true),
    conReintentar: false,
  ),
  _EstadoSinLugar(
    'zonas_varias',
    'zonas en varias ciudades',
    'mapas_offline_sin_ciudad_elegible',
    (t) => t.bajar(zonasEnDosCiudades: true, zonaAsignada: 'z-centro'),
    conReintentar: false,
  ),
  _EstadoSinLugar('falla_lectura', 'falla de lectura', 'mapas_offline_sin_lugar', (t) async {
    await t.bajar(zonaAsignada: 'z-centro');
    t.lugares.fallar = 1;
  }, conReintentar: true),
];

const _avisoDeHoy = 'No pudimos saber en qué zona y ciudad trabajás. Probá de nuevo.';
const _tamanos = [Size(360, 640), Size(412, 915)];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late _Telefono tel;

  setUp(() => tel = _Telefono());

  group('35-01 · elegir cobertura, de la fila a la pantalla', () {
    testWidgets(
      'con zona asignada: «Mi zona», «Mi ciudad», «Mi departamento» y Uruguay, con su peso',
      (tester) async {
        await tester.runAsync(() => tel.bajar(zonaAsignada: 'z-centro'));
        await _montar(tester, tel);

        expect(find.text('Mi zona'), findsOneWidget);
        expect(find.text('Mi ciudad'), findsOneWidget);
        expect(find.text('Mi departamento'), findsOneWidget);
        expect(find.text('Centro · 14 MB'), findsOneWidget);
        expect(find.text('Montevideo · 86 MB'), findsOneWidget);
        expect(find.text('Montevideo · 250 MB'), findsOneWidget);
        expect(find.text('Todo Uruguay'), findsOneWidget);
        expect(_clave('mapas_offline_sin_lugar'), findsNothing);
        expect(tester.takeException(), isNull);
        await _capturar(tester, 'con_zona_390');
        await _cerrar(tester, tel);
      },
    );

    testWidgets(
      'sin zona y una sola ciudad: dice «No tenés zona asignada» y ofrece ciudad y depto',
      (tester) async {
        await tester.runAsync(() => tel.bajar(departamento: 'San José'));
        await _montar(tester, tel);

        expect(find.text('No tenés zona asignada'), findsOneWidget);
        expect(find.text('Montevideo · 86 MB'), findsOneWidget);
        expect(find.text('San José · 250 MB'), findsOneWidget);
        expect(_clave('mapas_offline_sin_lugar'), findsNothing);
        await _capturar(tester, 'sin_zona_390');
        await _cerrar(tester, tel);
      },
    );

    testWidgets('el departamento escrito con tilde, mayúsculas y espacios de más se encuentra', (
      tester,
    ) async {
      await tester.runAsync(() => tel.bajar(departamento: '  SAN   JOSÉ '));
      await _montar(tester, tel);

      expect(find.text('San José · 250 MB'), findsOneWidget);
      await _cerrar(tester, tel);
    });

    testWidgets('departamento de dos palabras («Treinta y Tres») y ciudad homónima del depto', (
      tester,
    ) async {
      await tester.runAsync(() => tel.bajar(departamento: 'Treinta y Tres'));
      await _montar(tester, tel);
      expect(find.text('Treinta y Tres · 250 MB'), findsOneWidget);
      await _cerrar(tester, tel);
    });

    testWidgets('«Montevideo» ciudad y «Montevideo» departamento se distinguen por el rótulo', (
      tester,
    ) async {
      await tester.runAsync(() => tel.bajar(zonaAsignada: 'z-centro'));
      await _montar(tester, tel);

      final semantica = tester.ensureSemantics();
      expect(find.text('Montevideo · 86 MB'), findsOneWidget);
      expect(find.text('Montevideo · 250 MB'), findsOneWidget);
      expect(find.text('Mi ciudad'), findsOneWidget);
      expect(find.text('Mi departamento'), findsOneWidget);
      semantica.dispose();
      await _cerrar(tester, tel);
    });

    testWidgets('sin departamento cargado no se ofrece el mapa del departamento (ni uno vacío)', (
      tester,
    ) async {
      await tester.runAsync(() => tel.bajar(departamento: null));
      await _montar(tester, tel);

      // La fila sigue (el canvas dibuja los cuatro niveles) pero apagada y sin nombre de depto.
      expect(find.text('Montevideo · 250 MB'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('mapas_offline_nivel_departamento')),
          matching: find.text('Todavía no está disponible'),
        ),
        findsOneWidget,
      );
      expect(find.text('Mi ciudad'), findsOneWidget);
      expect(find.text('Todo Uruguay'), findsOneWidget);
      await _cerrar(tester, tel);
    });

    testWidgets(
      'textos límite: zona con emoji y 60 letras, a 360×640 con letra 2,0×, sin overflow',
      (tester) async {
        final larga = '${'Zona Cerro Norte Oeste ' * 3}🌳🌳';
        await tester.runAsync(() => tel.bajar(zonaAsignada: 'z-centro', zonaNombre: larga));
        await _montar(
          tester,
          tel,
          tamano: const Size(360, 640),
          escala: 2,
          catalogo: [
            _paquete('zona-centro', NivelCobertura.zona, 'z-centro', larga, 14),
            ..._catalogo.skip(1),
          ],
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Mi zona'), findsOneWidget);
        await _cerrar(tester, tel);
      },
    );
  });

  group('35-01 · tamaños y accesibilidad con la fuente real', () {
    for (final tamano in _tamanos) {
      for (final escala in [1.0, 2.0]) {
        final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()} · letra $escala×';

        testWidgets('con zona · $etiqueta: sin overflow y con las guías de toque', (tester) async {
          await tester.runAsync(() => tel.bajar(zonaAsignada: 'z-centro'));
          final semantica = tester.ensureSemantics();
          await _montar(tester, tel, tamano: tamano, escala: escala);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await _capturar(tester, 'con_zona_${tamano.width.toInt()}_x$escala');
          semantica.dispose();
          await _cerrar(tester, tel);
        });

        for (final estado in _estadosSinLugar) {
          testWidgets('${estado.nombre} · $etiqueta: sin overflow y guías de toque', (
            tester,
          ) async {
            await tester.runAsync(() => estado.preparar(tel));
            final semantica = tester.ensureSemantics();
            await _montar(tester, tel, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull);
            expect(_clave(estado.clave), findsOneWidget);
            expect(find.text('Reintentar'), estado.conReintentar ? findsWidgets : findsNothing);
            await tester.ensureVisible(_clave(estado.clave));
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await _capturar(tester, '${estado.id}_${tamano.width.toInt()}_x$escala');
            semantica.dispose();
            await _cerrar(tester, tel);
          });
        }
      }
    }
  });

  group('lo que no se sabe: avisos, salidas y recuperación', () {
    testWidgets(
      'P1 · sin zona y con varias ciudades: el aviso dice la causa, sin «Reintentar», y Uruguay a mano',
      (tester) async {
        await tester.runAsync(() => tel.bajar(conCanelones: true));
        await _montar(tester, tel);

        expect(
          find.text(
            'Todavía no tenés zona y tu campaña tiene varias ciudades, así que no sabemos cuál '
            'bajar. Cuando la coordinación te asigne una zona, vas a poder bajar tu ciudad. '
            'Mientras tanto podés bajar el mapa de todo Uruguay.',
          ),
          findsOneWidget,
        );
        expect(find.text(_avisoDeHoy), findsNothing);
        expect(_clave('mapas_offline_sin_lugar'), findsNothing);
        expect(find.text('Reintentar'), findsNothing);
        // No se adivina una ciudad: ninguna fila nombra Montevideo ni Canelones.
        expect(find.textContaining('Montevideo ·'), findsNothing);
        expect(find.textContaining('Canelones ·'), findsNothing);
        expect(find.text('Todo Uruguay'), findsOneWidget);
        await tester.tap(find.text('Todo Uruguay'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        await _cerrar(tester, tel);
      },
    );

    testWidgets(
      'zonas asignadas en dos ciudades: no dice «No tenés zona asignada» (sería falso) ni deja «Reintentar»',
      (tester) async {
        await tester.runAsync(() => tel.bajar(zonasEnDosCiudades: true, zonaAsignada: 'z-centro'));
        await _montar(tester, tel);

        expect(_clave('mapas_offline_sin_ciudad_elegible'), findsOneWidget);
        expect(find.text('No tenés zona asignada'), findsNothing);
        expect(find.text(_avisoDeHoy), findsNothing);
        expect(find.text('Reintentar'), findsNothing);
        expect(find.text('Todo Uruguay'), findsOneWidget);
        await _cerrar(tester, tel);
      },
    );

    testWidgets(
      'la falla real de lectura (disco) sigue con el aviso genérico y «Reintentar» recupera',
      (tester) async {
        await tester.runAsync(() => tel.bajar(zonaAsignada: 'z-centro'));
        tel.lugares.fallar = 1;
        await _montar(tester, tel);

        expect(find.text(_avisoDeHoy), findsOneWidget);
        expect(find.text('Centro · 14 MB'), findsNothing);

        await tester.tap(find.text('Reintentar').first);
        await _asentar(tester);

        expect(find.text(_avisoDeHoy), findsNothing);
        expect(find.text('Centro · 14 MB'), findsOneWidget);
        await _cerrar(tester, tel);
      },
    );

    testWidgets(
      'la zona llega por el sync con la pantalla abierta: se actualiza sola, sin tocar nada',
      (tester) async {
        await tester.runAsync(() => tel.bajar(conCanelones: true));
        await _montarConCadenaReal(tester, tel);
        expect(_clave('mapas_offline_sin_ciudad_elegible'), findsOneWidget);

        // La coordinación le asigna la zona de Montevideo; el pull la baja.
        await tester.runAsync(() => tel.bajar(conCanelones: true, zonaAsignada: 'z-centro'));
        await _asentar(tester);

        expect(_clave('mapas_offline_sin_ciudad_elegible'), findsNothing);
        expect(find.text('Centro · 14 MB'), findsOneWidget);
        expect(find.text('Montevideo · 86 MB'), findsOneWidget);
        expect(find.text('Reintentar'), findsNothing);
        expect(tester.takeException(), isNull);
        await _cerrar(tester, tel);
      },
    );

    /// «Todo Uruguay» pedido sin zona (la única opción) y la zona llega por el sync: la pantalla se relee.
    /// [antesDeLosEncabezados]: el servidor todavía no contestó (hasta 30 s sin ningún `DescargaEnCurso`).
    Future<void> descargaYLlegaLaZona(
      WidgetTester tester, {
      required bool antesDeLosEncabezados,
    }) async {
      final uruguay = paqueteDe(
        bytesDePrueba(5500),
        id: 'uruguay',
        nivel: NivelCobertura.uruguay,
        ambitoId: null,
      );
      await tester.runAsync(() => tel.bajar(conCanelones: true));
      final arnes = await _montarConCadenaReal(
        tester,
        tel,
        catalogo: [..._catalogo.where((p) => p.id != 'uruguay'), uruguay],
      );
      arnes.servidor.archivos[uruguay.partes.first.origen] = bytesDePrueba(5500);
      final compuerta = arnes.servidor.esperaAntesDeContestar = Completer<void>();
      await tester.tap(find.byKey(const Key('mapas_offline_descargar')));
      await _asentar(tester);
      expect(find.text('Descargando'), findsWidgets);

      await tester.runAsync(() => tel.bajar(conCanelones: true, zonaAsignada: 'z-centro'));
      await _asentar(tester);
      if (!antesDeLosEncabezados) {
        compuerta.complete();
        await _asentar(tester);
      }

      expect(_clave('mapas_offline_sin_ciudad_elegible'), findsNothing);
      // Sigue la pantalla 02 (la descarga a la vista), no la elección 01.
      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(find.text('MAPAS OFFLINE · 01'), findsNothing);
      expect(tester.takeException(), isNull);
      if (antesDeLosEncabezados) compuerta.complete();
      await _asentar(tester);
      await _cerrar(tester, tel);
    }

    testWidgets(
      'una descarga de «Todo Uruguay» en marcha sigue a la vista cuando la zona llega y ya hay bytes',
      (tester) => descargaYLlegaLaZona(tester, antesDeLosEncabezados: false),
    );

    // skip: QA #619 — con la descarga pedida y sin encabezados, al releer por la zona la pantalla vuelve a
    // la elección (01) y no muestra la descarga hasta que llega el primer byte (placeholder perdido en `cargar`).
    testWidgets(
      'una descarga de «Todo Uruguay» recién pedida sigue a la vista cuando la zona llega',
      (tester) => descargaYLlegaLaZona(tester, antesDeLosEncabezados: true),
      skip: !_conHallazgos,
    );

    testWidgets(
      'el pull escribe y no hay novedad (sigue sin zona): el aviso se queda, sin apilarse',
      (tester) async {
        await tester.runAsync(() => tel.bajar(conCanelones: true));
        await _montarConCadenaReal(tester, tel);

        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() => tel.bajar(conCanelones: true));
          await _asentar(tester);
        }

        expect(_clave('mapas_offline_sin_ciudad_elegible'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _cerrar(tester, tel);
      },
    );

    testWidgets('con el lugar ya leído, un pull posterior no pisa la cobertura que ella eligió', (
      tester,
    ) async {
      await tester.runAsync(() => tel.bajar(zonaAsignada: 'z-centro'));
      await _montarConCadenaReal(tester, tel);
      await tester.tap(find.text('Mi ciudad'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.runAsync(() => tel.bajar(zonaAsignada: 'z-centro'));
      await _asentar(tester);

      expect(find.text('Montevideo · 86 MB'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _cerrar(tester, tel);
    });

    testWidgets(
      'doble toque en «Reintentar» con la lectura en curso: queda un solo estado coherente',
      (tester) async {
        await tester.runAsync(() => tel.bajar(zonaAsignada: 'z-centro'));
        tel.lugares.fallar = 1;
        await _montar(tester, tel);
        expect(find.text(_avisoDeHoy), findsOneWidget);

        tel.lugares.compuerta = Completer<void>();
        final antes = tel.lugares.llamadas;
        await tester.tap(find.text('Reintentar').first);
        await tester.pump(const Duration(milliseconds: 50));
        // Con la lectura frenada el botón puede estar o no; si está, un segundo toque no rompe nada.
        final otra = find.text('Reintentar');
        if (otra.evaluate().isNotEmpty) await tester.tap(otra.first, warnIfMissed: false);
        tel.lugares.compuerta!.complete();
        await _asentar(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Centro · 14 MB'), findsOneWidget);
        expect(find.text(_avisoDeHoy), findsNothing);
        expect(
          tel.lugares.llamadas - antes,
          lessThanOrEqualTo(2),
          reason: 'a lo sumo dos lecturas',
        );
        await _cerrar(tester, tel);
      },
    );

    testWidgets('sin sesión ni base abierta: aviso con «Reintentar» y Uruguay a mano, sin lanzar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final arnes = ArnesMapa(catalogo: _catalogo, servirPaqueteMontevideo: false);
      addTearDown(() => unawaited(arnes.cerrar()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...arnes.overrides,
            fuenteLugarDeTrabajoProvider.overrideWithValue(
              FuenteLugarDeTrabajoLocal.sinFuente(logger: loggerMudo()),
            ),
            medidorEspacioDiscoProvider.overrideWithValue(
              EspacioFalso()..libres = 4000 * 1000 * 1000,
            ),
          ],
          child: MaterialApp(theme: temaClaro(), home: const MapasOfflinePage()),
        ),
      );
      await _asentar(tester);

      expect(find.text(_avisoDeHoy), findsOneWidget);
      expect(find.text('Reintentar'), findsWidgets);
      expect(find.text('Todo Uruguay'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _cerrar(tester, tel);
    });

    testWidgets('salir y volver a entrar lee de nuevo y toma la zona que llegó mientras tanto', (
      tester,
    ) async {
      await tester.runAsync(() => tel.bajar(conCanelones: true));
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final arnes = ArnesMapa(catalogo: _catalogo, servirPaqueteMontevideo: false);
      addTearDown(() => unawaited(arnes.cerrar()));
      final abierta = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...arnes.overrides,
            fuenteLugarDeTrabajoProvider.overrideWith((ref) => tel.fuente),
            medidorEspacioDiscoProvider.overrideWithValue(
              EspacioFalso()..libres = 4000 * 1000 * 1000,
            ),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: ValueListenableBuilder<bool>(
              valueListenable: abierta,
              builder: (_, v, _) => v ? const MapasOfflinePage() : const Scaffold(),
            ),
          ),
        ),
      );
      await _asentar(tester);
      expect(_clave('mapas_offline_sin_ciudad_elegible'), findsOneWidget);

      abierta.value = false;
      await tester.pump();
      await tester.runAsync(() => tel.bajar(conCanelones: true, zonaAsignada: 'z-centro'));
      abierta.value = true;
      await _asentar(tester);

      expect(_clave('mapas_offline_sin_ciudad_elegible'), findsNothing);
      expect(find.text('Centro · 14 MB'), findsOneWidget);
      await _cerrar(tester, tel);
    });
  });

  group('cableado de main.dart: fuenteLugarDeTrabajoLocalProvider', () {
    ProviderContainer contenedor({AppDatabase? base, bool conSesion = true}) {
      final c = ProviderContainer(
        overrides: [
          dbLocalProvider.overrideWith(() => _DbFija(base)),
          sesionProvider.overrideWith(() => _SesionFija(conSesion ? _colportor : null)),
          relojAltaUbicacionProvider.overrideWithValue(() => _hoy),
        ],
      );
      return c;
    }

    test('con sesión y base abierta lee de verdad la zona, la ciudad y el departamento', () async {
      await tel.bajar(zonaAsignada: 'z-centro', departamento: 'San José');
      final c = contenedor(base: tel.db);
      await c.read(sesionProvider.future);

      final r = await c.read(fuenteLugarDeTrabajoLocalProvider).leer();
      final lugar = r.getOrElse(() => throw StateError('falló: $r'));
      expect(lugar.ciudadNombre, 'Montevideo');
      expect(lugar.zonaNombre, 'Centro');
      expect(lugar.ambito.departamentoId, 'san jose');
      c.dispose();
      await tel.db.close();
    });

    test('sin sesión contesta «no sé» sin lanzar', () async {
      final c = contenedor(base: tel.db, conSesion: false);
      await c.read(sesionProvider.future);
      final r = await c.read(fuenteLugarDeTrabajoLocalProvider).leer();
      expect(r.isLeft(), isTrue);
      c.dispose();
      await tel.db.close();
    });

    test('con la base cerrada (sin abrir) contesta «no sé» sin lanzar', () async {
      final c = contenedor();
      await c.read(sesionProvider.future);
      final r = await c.read(fuenteLugarDeTrabajoLocalProvider).leer();
      expect(r.isLeft(), isTrue);
      c.dispose();
      await tel.db.close();
    });
  });

  group('privacidad', () {
    test(
      'los logs de «no se pudo saber» y de la falla de lectura no llevan el id ni los nombres',
      () async {
        final salida = MemoryOutput();
        tel.logger = AppLogger(
          logger: Logger(level: Level.all, printer: SimplePrinter(), output: salida),
        );
        await tel.bajar(conCanelones: true, zonaNombre: 'Zona-Secreta-619');
        await tel.fuente.leer(); // varias ciudades, sin zona
        await tel.bajar(zonaAsignada: 'z-centro', zonaNombre: 'Zona-Secreta-619');
        tel.lugares.fallar = 1;
        await tel.fuente.leer(); // disco roto
        await FuenteLugarDeTrabajoLocal.sinFuente(logger: tel.logger).leer();

        final logs = salida.buffer.expand((e) => e.lines).join('\n');
        expect(logs, contains('LUGAR_'));
        expect(logs, isNot(contains(_colportor)));
        expect(logs, isNot(contains('Zona-Secreta-619')));
        await tel.db.close();
      },
    );

    test('toString del lugar y de la fuente no llevan el id de la colportora', () async {
      await tel.bajar(zonaAsignada: 'z-centro');
      final lugar = (await tel.fuente.leer()).getOrElse(() => throw StateError('falló'));
      expect('$lugar${tel.fuente}', isNot(contains(_colportor)));
      await tel.db.close();
    });
  });
}

class _DbFija extends DbLocalNotifier {
  _DbFija(this._base);

  final AppDatabase? _base;

  @override
  AppDatabase? build() => _base;
}

class _SesionFija extends SesionNotifier {
  _SesionFija(this._usuario);

  final String? _usuario;

  @override
  Future<Sesion?> build() async => _usuario == null
      ? null
      : Sesion(
          usuarioId: _usuario,
          email: 'ana@example.com',
          accessToken: 'jwt',
          expiraEn: DateTime.utc(2030),
        );
}
