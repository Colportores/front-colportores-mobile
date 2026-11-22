// Las casas «fuera del área» en el mapa (#713; HU-SYNC-011, R-UB12, contrato-sync-engine §2.1): el
// motor las marca y nunca las borra; el mapa las distingue con un aro ámbar y el colportor elige si las
// ve o las oculta, solo visual. Acá: la regla de qué se ve, los textos, el estilo MapLibre de la marca
// y la lectura reactiva de la base, con la prueba de que ocultarlas no borra ni encola nada.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_fuera_del_area.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/estilo_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/fuera_del_area_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../../../helpers/assets_de_lib_mapa.dart';
import '../../../../helpers/logger_mudo.dart';

const _montevideo = Coordenadas(lat: -34.88761, lon: -56.13024);
const _recursos = '/data/user/0/uy.colportores/files/mapa/basemaps-5.7.2-1';

/// Una base que ya está «abierta»: el provider solo necesita el `AppDatabase`.
class _DbFija extends DbLocalNotifier {
  _DbFija(this._base);

  final AppDatabase _base;

  @override
  AppDatabase? build() => _base;
}

ConfigVistaMapa _config(List<PuntoMapa> puntos, {bool agrupar = true}) => ConfigVistaMapa(
  fuente: const FuenteMapa.sinTiles(),
  camaraInicial: const CamaraMapa(centro: _montevideo, zoom: 16),
  zoomMinimo: 3,
  zoomMaximo: 19,
  interaccion: const InteraccionMapa(),
  dobleToqueZoom: true,
  fondo: ColoresMapa.fondo,
  colorNuevo: const Color(0xFF0B6E4F),
  puntos: puntos,
  agruparPuntos: agrupar,
  precision: null,
  cercania: null,
  puntosTocables: true,
);

Map<String, Object?> _ubicacion(String id) => {
  'id': id,
  'tipo': 'CASA',
  'calle': 'Av. Italia',
  'numero': '1234',
  'lat': -34.9,
  'lon': -56.16,
  'ciudad_id': 'ciu-1',
  'zona_id': null,
  'created_at': '2026-11-10T12:00:00.000Z',
  'updated_at': '2026-11-10T12:30:00.000Z',
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': 1,
};

void main() {
  group('qué se ve (FueraDelAreaEnElMapa)', () {
    const tres = FueraDelAreaEnElMapa(ids: {'a', 'b', 'c'});

    test('por defecto se ven, con su marca: ninguna oculta', () {
      expect(tres.ver, isTrue);
      expect(tres.cantidad, 3);
      expect(tres.ocultas, 0);
      expect(tres.marcada('a'), isTrue);
      expect(tres.marcada('z'), isFalse, reason: 'una casa del área no lleva marca');
      expect(tres.oculta('a'), isFalse);
    });

    test('ocultas: no se dibujan ni llevan marca, y se cuentan', () {
      const ocultas = FueraDelAreaEnElMapa(ids: {'a', 'b', 'c'}, ver: false);

      expect(ocultas.ocultas, 3);
      expect(ocultas.oculta('a'), isTrue);
      expect(ocultas.marcada('a'), isFalse);
      expect(ocultas.oculta('z'), isFalse, reason: 'ocultar solo toca las de fuera del área');
    });

    test('la elegida nunca se oculta', () {
      const ocultas = FueraDelAreaEnElMapa(ids: {'a', 'b'}, ver: false);

      expect(ocultas.oculta('a', elegida: 'a'), isFalse);
      expect(ocultas.oculta('b', elegida: 'a'), isTrue);
    });

    test('sin casas fuera del área, ocultar no cambia nada', () {
      const nada = FueraDelAreaEnElMapa(ver: false);

      expect(nada.cantidad, 0);
      expect(nada.ocultas, 0);
      expect(nada.oculta('a'), isFalse);
    });
  });

  group('textos', () {
    test('singular y plural', () {
      expect(FormatoFueraDelArea.ocultas(1), '1 casa fuera de tu área oculta');
      expect(FormatoFueraDelArea.ocultas(3), '3 casas fuera de tu área ocultas');
      expect(FormatoFueraDelArea.ocultasLector(2), '2 casas fuera de tu área ocultas. Ver');
      expect(
        FormatoFueraDelArea.detalleInterruptor(1),
        '1 casa. Ocultarlas solo cambia lo que ves en el mapa: no se borra nada.',
      );
    });

    test('lo que suma al nombre del mapa: nada sin casas, la marca o las ocultas', () {
      expect(FormatoFueraDelArea.paraElLector(0, ver: true), isNull);
      expect(FormatoFueraDelArea.paraElLector(0, ver: false), isNull);
      expect(
        FormatoFueraDelArea.paraElLector(2, ver: true),
        '2 casas fuera de tu área, con un aro ámbar',
      );
      expect(FormatoFueraDelArea.paraElLector(1, ver: false), '1 casa fuera de tu área oculta');
    });
  });

  group('la marca en el estilo MapLibre', () {
    late String estiloBase;
    setUpAll(() => estiloBase = estiloDeLibMapa());

    Map<String, dynamic> construir(ConfigVistaMapa config, {bool conRecursos = true}) =>
        jsonDecode(
              conRecursos
                  ? ConstructorEstiloMapa.construir(
                      estiloBase: estiloBase,
                      directorioRecursos: _recursos,
                      config: config,
                    )
                  : ConstructorEstiloMapa.construirSinRecursos(
                      estiloBase: estiloBase,
                      config: config,
                    ),
            )
            as Map<String, dynamic>;

    List<Map<String, dynamic>> capas(Map<String, dynamic> estilo) => [
      for (final capa in estilo['layers'] as List<dynamic>) capa as Map<String, dynamic>,
    ];

    Map<String, dynamic> propiedades(Map<String, dynamic> coleccion, String id) =>
        ((coleccion['features'] as List<dynamic>).cast<Map<String, dynamic>>().singleWhere(
              (f) => (f['properties'] as Map<String, dynamic>)['id'] == id,
            )['properties']
            as Map<String, dynamic>);

    test('la casa fuera del área lleva `fuera: true`; las demás no llevan la propiedad', () {
      final puntos = [
        const PuntoMapa(id: 'a', coordenadas: _montevideo, fueraDelArea: true),
        const PuntoMapa(id: 'b', coordenadas: _montevideo),
        const PuntoMapa(
          id: 'c',
          coordenadas: _montevideo,
          estilo: EstiloPunto.seleccionado,
          fueraDelArea: true,
        ),
      ];
      final agrupables = ConstructorEstiloMapa.coleccionPuntos(puntos);
      final libres = ConstructorEstiloMapa.coleccionPuntosLibres(puntos);

      expect(propiedades(agrupables, 'a')['fuera'], isTrue);
      expect(propiedades(agrupables, 'b').containsKey('fuera'), isFalse);
      expect(propiedades(libres, 'c')['fuera'], isTrue);
    });

    test('un aro por fuente, debajo de todos los marcadores y sin recibir toques', () {
      for (final conRecursos in [true, false]) {
        final ids = [
          for (final c in capas(construir(_config(const []), conRecursos: conRecursos))) c['id'],
        ];
        final aro = ids.indexOf(ConstructorEstiloMapa.capaFueraDelArea);
        final aroLibres = ids.indexOf(ConstructorEstiloMapa.capaFueraDelAreaLibres);

        expect(aro, isNonNegative, reason: 'con recursos: $conRecursos');
        expect(aroLibres, isNonNegative);
        for (final marcador in [
          ConstructorEstiloMapa.capaContexto,
          ConstructorEstiloMapa.capaEstadoRespaldo,
          ConstructorEstiloMapa.capaGrupos,
          ConstructorEstiloMapa.capaSeleccionado,
          ConstructorEstiloMapa.capaCuadradoRespaldo,
          ConstructorEstiloMapa.capaGps,
        ]) {
          expect(aro, lessThan(ids.indexOf(marcador)), reason: '$marcador tapa el aro');
          expect(aroLibres, lessThan(ids.indexOf(marcador)), reason: '$marcador tapa el aro');
        }
        expect(
          ids.indexOf(ConstructorEstiloMapa.capaZonaPropiaBorde),
          lessThan(aro),
          reason: 'las zonas siguen por debajo de todo',
        );
      }
      expect(
        ConstructorEstiloMapa.capasTocables,
        isNot(contains(ConstructorEstiloMapa.capaFueraDelArea)),
      );
      expect(
        ConstructorEstiloMapa.capasTocablesLargo,
        isNot(contains(ConstructorEstiloMapa.capaFueraDelAreaLibres)),
      );
    });

    test('el aro es ámbar, filtra por `fuera` y nunca se dibuja sobre un grupo', () {
      final estilo = construir(_config(const []));
      for (final id in [
        ConstructorEstiloMapa.capaFueraDelArea,
        ConstructorEstiloMapa.capaFueraDelAreaLibres,
      ]) {
        final capa = capas(estilo).singleWhere((c) => c['id'] == id);
        final pintura = capa['paint'] as Map<String, dynamic>;
        final filtro = jsonEncode(capa['filter']);

        expect(capa['type'], 'circle');
        expect(pintura['circle-stroke-color'], '#7A5A12');
        expect(filtro, contains('"fuera"'));
        expect(filtro, contains('["!",["has","point_count"]]'));
      }
      expect(
        capas(
          estilo,
        ).singleWhere((c) => c['id'] == ConstructorEstiloMapa.capaFueraDelArea)['source'],
        ConstructorEstiloMapa.fuentePuntos,
      );
      expect(
        capas(
          estilo,
        ).singleWhere((c) => c['id'] == ConstructorEstiloMapa.capaFueraDelAreaLibres)['source'],
        ConstructorEstiloMapa.fuentePuntosLibres,
      );
    });

    test('el aro se atenúa con su casa (06C·03): sigue la opacidad del marcador', () {
      final capa = capas(
        construir(_config(const [])),
      ).singleWhere((c) => c['id'] == ConstructorEstiloMapa.capaFueraDelArea);
      final pintura = capa['paint'] as Map<String, dynamic>;

      expect(jsonEncode(pintura['circle-stroke-opacity']), contains('"atenuado"'));
    });
  });

  group('la lectura de la base y ocultar (solo visual)', () {
    late AppDatabase db;
    late DriftLocalStore store;
    late ProviderContainer contenedor;

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
      contenedor = ProviderContainer(overrides: [dbLocalProvider.overrideWith(() => _DbFija(db))]);
    });
    tearDown(() async {
      contenedor.dispose();
      await db.close();
    });

    Future<void> bajar(List<String> ids, {List<String> afuera = const []}) => store.applyDelta(
      {'ubicacion': ids.map(_ubicacion).toList()},
      scope: 'replica',
      watermark: 'w-${ids.length}-${afuera.length}',
      notices: PullNotices(outOfArea: {if (afuera.isNotEmpty) 'ubicacion': afuera}),
    );

    /// Espera la próxima lectura de [idsFueraDelAreaProvider] que cumpla [condicion].
    Future<Set<String>> leer(bool Function(Set<String>) condicion) async {
      final listo = Completer<Set<String>>();
      final sub = contenedor.listen(idsFueraDelAreaProvider, (_, valor) {
        final ids = valor.value;
        if (ids != null && condicion(ids) && !listo.isCompleted) listo.complete(ids);
      }, fireImmediately: true);
      try {
        return await listo.future.timeout(const Duration(seconds: 5));
      } finally {
        sub.close();
      }
    }

    test('sin base abierta no hay ninguna', () async {
      // Sin sesión la base no está abierta (`DbLocalNotifier` arranca en `null`).
      final sinBase = ProviderContainer();
      addTearDown(sinBase.dispose);
      final listo = Completer<Set<String>>();
      sinBase.listen(idsFueraDelAreaProvider, (_, v) {
        if (v.hasValue && !listo.isCompleted) listo.complete(v.value);
      }, fireImmediately: true);

      expect(await listo.future.timeout(const Duration(seconds: 5)), isEmpty);
    });

    test('lee las marcadas por el motor y sigue a los pulls (sale y vuelve al área)', () async {
      await bajar(['u1', 'u2']);
      expect(await leer((ids) => ids.isEmpty), isEmpty);

      await bajar(const [], afuera: ['u1']);
      expect(await leer((ids) => ids.isNotEmpty), {'u1'});

      // La casa vuelve a bajar: deja de estar afuera.
      await bajar(['u1']);
      expect(await leer((ids) => ids.isEmpty), isEmpty);
    });

    test('ocultar y volver a ver no borra ni encola nada', () async {
      await bajar(['u1', 'u2', 'u3']);
      await bajar(const [], afuera: ['u1', 'u3']);
      expect(await leer((ids) => ids.length == 2), {'u1', 'u3'});

      Future<Map<String, int>> cuentas() async => {
        for (final tabla in ['ubicacion', 'sync_queue', 'sync_fuera_del_area', 'audit_log'])
          tabla: (await db.customSelect('SELECT COUNT(*) AS n FROM $tabla').getSingle()).read<int>(
            'n',
          ),
      };
      final antes = await cuentas();
      final ubicacionesAntes = await db.select(db.ubicaciones).get();

      contenedor.read(verFueraDelAreaProvider.notifier).ocultar();
      expect(contenedor.read(verFueraDelAreaProvider), isFalse);
      await pumpEventQueue();
      contenedor.read(verFueraDelAreaProvider.notifier).ver();
      contenedor.read(verFueraDelAreaProvider.notifier).elegir(valor: false);
      await pumpEventQueue();

      expect(await cuentas(), antes);
      expect(antes['ubicacion'], 3);
      expect(antes['sync_queue'], 0, reason: 'nada se encola');
      expect(await db.select(db.ubicaciones).get(), ubicacionesAntes);
      expect(await leer((ids) => ids.length == 2), {'u1', 'u3'}, reason: 'la marca sigue igual');
    });
  });
}
