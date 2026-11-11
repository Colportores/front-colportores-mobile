// «Mapas offline» con la fuente REAL de dónde trabaja la colportora (HU-SYNC-010, #619): la zona, la
// ciudad y el departamento salen de las réplicas locales con la ciudad que resuelve el mismo
// `CiudadesParaAlta` del mapa de la vista 06. La fuente real (`FuenteLugarDeTrabajoLocal`) va sobre
// puertos en memoria: la lectura de Drift se prueba aparte (`fuente_lugar_de_trabajo_local_test`).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/campanias_del_colportor_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/lugar_de_trabajo_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/services/fuente_lugar_de_trabajo_local.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/fuente_lugar_de_trabajo.dart';
import 'package:colportores_mobile/features/tiles/presentation/pages/mapas_offline_page.dart';
import 'package:colportores_mobile/features/tiles/presentation/providers/mapas_offline_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_falsos.dart';
import '../helpers/logger_mudo.dart';
import '../helpers/mapa_descargas_arnes.dart';
import '../helpers/tiles_falsos.dart';

final class _Campanias implements CampaniasDelColportorLocalDataSource {
  _Campanias({this.zonaId, this.inscripciones});

  final String? zonaId;

  /// Si se da, reemplaza a la inscripción de [zonaId].
  final List<InscripcionDeCampania>? inscripciones;

  @override
  Future<CampaniasDelColportor?> leer(String usuarioId, {required String hoy}) async =>
      CampaniasDelColportor(
        inscripciones:
            inscripciones ??
            [
              (
                campaniaId: 'camp-1',
                zonaId: zonaId,
                ciudadDeLaZonaId: zonaId == null ? null : montevideo.id,
              ),
            ],
        ciudades: const [(id: 'ciu-mvd', nombre: 'Montevideo', lat: -34.9, lon: -56.16)],
      );
}

final class _Lugares implements LugarDeTrabajoLocalDataSource {
  _Lugares({this.departamento = 'San José'});

  final String? departamento;

  @override
  Future<DatosDelLugar> leer({required Set<String> zonaIds, required String ciudadId}) async =>
      (nombresDeZonas: {for (final id in zonaIds) id: 'Cerro Norte'}, departamento: departamento);
}

/// Una fuente que se cambia a mano: lo que hace la fuente real cuando el sync escribe las réplicas.
final class _FuenteCambiante extends Notifier<FuenteLugarDeTrabajo> {
  _FuenteCambiante(this._inicial);

  final FuenteLugarDeTrabajo _inicial;

  @override
  FuenteLugarDeTrabajo build() => _inicial;

  void cambiarA(FuenteLugarDeTrabajo nueva) => state = nueva;
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

final _zona14 = _paquete('zona-cerro-norte', NivelCobertura.zona, 'z-1', 'Cerro Norte', 14);
final _ciudad86 = _paquete('ciudad-mvd', NivelCobertura.ciudad, 'ciu-mvd', 'Montevideo', 86);
final _depto250 = _paquete(
  'depto-san-jose',
  NivelCobertura.departamento,
  'san jose',
  'San José',
  250,
);
final _uruguay1200 = _paquete('uruguay', NivelCobertura.uruguay, null, 'Todo Uruguay', 1200);

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Finder _clave(String clave) => find.byKey(Key(clave));

Future<void> _montar(
  WidgetTester tester, {
  required List<PaqueteTiles> catalogo,
  String? zonaId,
  String? departamento = 'San José',
  CiudadesFalsas? ciudades,
  List<InscripcionDeCampania>? inscripciones,
  double escala = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final arnes = ArnesMapa(catalogo: catalogo, servirPaqueteMontevideo: false);
  addTearDown(() => unawaited(arnes.cerrar()));
  final fuente = FuenteLugarDeTrabajoLocal(
    colportorId: 'col-1',
    ciudades: ciudades ?? CiudadesFalsas(),
    campanias: _Campanias(zonaId: zonaId, inscripciones: inscripciones),
    lugares: _Lugares(departamento: departamento),
    logger: loggerMudo(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...arnes.overrides,
        fuenteLugarDeTrabajoProvider.overrideWithValue(fuente),
        medidorEspacioDiscoProvider.overrideWithValue(EspacioFalso()..libres = 4000 * 1000 * 1000),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const MapasOfflinePage(),
      ),
    ),
  );
  await _asentar(tester);
}

void main() {
  group('35-01 · con la fuente real', () {
    testWidgets('«Mi zona», «Mi ciudad» y «Mi departamento» se ofrecen con su peso', (
      tester,
    ) async {
      await _montar(tester, catalogo: [_zona14, _ciudad86, _depto250, _uruguay1200], zonaId: 'z-1');

      expect(find.text('Mi zona'), findsOneWidget);
      expect(find.text('Mi ciudad'), findsOneWidget);
      expect(find.text('Mi departamento'), findsOneWidget);
      expect(find.text('Cerro Norte · 14 MB'), findsOneWidget);
      expect(find.text('Montevideo · 86 MB'), findsOneWidget);
      expect(find.text('San José · 250 MB'), findsOneWidget);
      expect(find.text('Todo Uruguay'), findsOneWidget);
      // Ya no dice que no sabe dónde trabaja.
      expect(_clave('mapas_offline_sin_lugar'), findsNothing);
      expect(find.text('No tenés zona asignada'), findsNothing);
    });

    testWidgets('sin zona asignada ofrece la ciudad y el departamento, y dice que no tiene zona', (
      tester,
    ) async {
      await _montar(tester, catalogo: [_zona14, _ciudad86, _depto250, _uruguay1200]);

      expect(find.text('No tenés zona asignada'), findsOneWidget);
      expect(find.text('Montevideo · 86 MB'), findsOneWidget);
      expect(find.text('San José · 250 MB'), findsOneWidget);
      expect(_clave('mapas_offline_sin_lugar'), findsNothing);
    });

    testWidgets('sin departamento cargado en la ciudad no se ofrece el mapa del departamento', (
      tester,
    ) async {
      await _montar(tester, catalogo: [_ciudad86, _depto250, _uruguay1200], departamento: null);

      expect(find.text('Montevideo · 86 MB'), findsOneWidget);
      expect(find.text('San José · 250 MB'), findsNothing);
      expect(find.text('Todo Uruguay'), findsOneWidget);
    });

    testWidgets('sin zona ni ciudad sigue el aviso de siempre, con «Reintentar», y Uruguay', (
      tester,
    ) async {
      await _montar(
        tester,
        catalogo: [_ciudad86, _depto250, _uruguay1200],
        ciudades: CiudadesFalsas()..fallaPropuesta = const FailureCiudadesNoDisponibles(),
      );

      expect(
        find.text('No pudimos saber en qué zona y ciudad trabajás. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(_clave('mapas_offline_sin_lugar'), findsOneWidget);
      expect(find.text('Todo Uruguay'), findsOneWidget);
      expect(find.text('No tenés zona asignada'), findsNothing);
    });

    testWidgets('varias ciudades y sin zona: dice la causa, sin «Reintentar», y deja Uruguay', (
      tester,
    ) async {
      await _montar(
        tester,
        catalogo: [_ciudad86, _uruguay1200],
        ciudades: CiudadesFalsas(propone: (_) => const FaltaElPunto()),
      );

      expect(_clave('mapas_offline_sin_ciudad_elegible'), findsOneWidget);
      expect(
        find.textContaining('Todavía no tenés zona y tu campaña tiene varias ciudades'),
        findsOneWidget,
      );
      expect(find.textContaining('podés bajar el mapa de todo Uruguay'), findsOneWidget);
      // Reintentar no cambiaría nada: no hay botón, ni el aviso de falla de lectura.
      expect(find.text('Reintentar'), findsNothing);
      expect(_clave('mapas_offline_sin_lugar'), findsNothing);
      expect(find.text('Montevideo · 86 MB'), findsNothing);
      expect(find.text('Todo Uruguay'), findsOneWidget);
    });

    testWidgets('zonas en más de una ciudad: no dice que le falta la zona', (tester) async {
      await _montar(
        tester,
        catalogo: [_ciudad86, _uruguay1200],
        ciudades: CiudadesFalsas(propone: (_) => const FaltaElPunto()),
        inscripciones: [
          (campaniaId: 'camp-1', zonaId: 'z-1', ciudadDeLaZonaId: 'ciu-mvd'),
          (campaniaId: 'camp-2', zonaId: 'z-2', ciudadDeLaZonaId: 'ciu-can'),
        ],
      );

      expect(find.textContaining('Tenés zonas en más de una ciudad'), findsOneWidget);
      expect(find.textContaining('Todavía no tenés zona'), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('cuando la zona llega por el sync, la pantalla se vuelve a leer sola', (
      tester,
    ) async {
      final sinZona = FuenteLugarDeTrabajoLocal(
        colportorId: 'col-1',
        ciudades: CiudadesFalsas(propone: (_) => const FaltaElPunto()),
        campanias: _Campanias(),
        lugares: _Lugares(),
        logger: loggerMudo(),
      );
      final conZona = FuenteLugarDeTrabajoLocal(
        colportorId: 'col-1',
        ciudades: CiudadesFalsas(),
        campanias: _Campanias(zonaId: 'z-1'),
        lugares: _Lugares(),
        logger: loggerMudo(),
      );
      final actual = NotifierProvider<_FuenteCambiante, FuenteLugarDeTrabajo>(
        () => _FuenteCambiante(sinZona),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final arnes = ArnesMapa(catalogo: [_zona14, _ciudad86], servirPaqueteMontevideo: false);
      addTearDown(() => unawaited(arnes.cerrar()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...arnes.overrides,
            fuenteLugarDeTrabajoProvider.overrideWith((ref) => ref.watch(actual)),
            medidorEspacioDiscoProvider.overrideWithValue(
              EspacioFalso()..libres = 4000 * 1000 * 1000,
            ),
          ],
          child: MaterialApp(theme: temaClaro(), home: const MapasOfflinePage()),
        ),
      );
      await _asentar(tester);
      expect(_clave('mapas_offline_sin_ciudad_elegible'), findsOneWidget);

      // El sync trae la zona: la fuente real se reconstruye.
      final contenedor = ProviderScope.containerOf(tester.element(find.byType(MapasOfflinePage)));
      contenedor.read(actual.notifier).cambiarA(conZona);
      await _asentar(tester);

      expect(_clave('mapas_offline_sin_ciudad_elegible'), findsNothing);
      expect(find.text('Cerro Norte · 14 MB'), findsOneWidget);
      expect(find.text('Montevideo · 86 MB'), findsOneWidget);
    });

    testWidgets('a 2× de letra los tres lugares siguen a la vista de la lista', (tester) async {
      await _montar(
        tester,
        catalogo: [_zona14, _ciudad86, _depto250, _uruguay1200],
        zonaId: 'z-1',
        escala: 2,
      );

      expect(find.text('Mi zona'), findsOneWidget);
      expect(_clave('mapas_offline_sin_lugar'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
