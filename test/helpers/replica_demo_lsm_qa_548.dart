// QA de #274 / PR #548: los datos de la demo del 31/10 tal como los baja `sync_pull` del proyecto
// Supabase dev (las cuentas colportor.demo y colportor2.demo): la ciudad Libertador San Martín, sus
// tres zonas RADIAL (con el `poligono_geojson` que manda el servidor) y las inscripciones.
import 'dart:math' as math;

import 'replica_de_campanias.dart';

const ciudadLsmId = 'dede0000-0000-7000-8002-000000000001';
const ciudadMvdId = '01a117a9-0619-7d34-bbfc-058f61d81448';
const campaniaMvdId = 'dede0000-0000-7000-8003-000000000001';
const campaniaLsmId = 'dede0000-0000-7000-8003-000000000002';
const campaniaCiudadLsmId = 'dede0000-0000-7000-8009-000000000002';

/// No está en el servidor hoy: la campaña de Montevideo (demo) no tiene `campania_ciudad` visible.
const campaniaCiudadMvdId = 'dede0000-0000-7000-8009-000000000001';
const zonaCentroId = 'dede0000-0000-7000-8004-000000000002';
const zonaUapId = 'dede0000-0000-7000-8004-000000000003';
const zonaPuiggariId = 'dede0000-0000-7000-8004-000000000004';
const colportorDemoId = 'dede0000-0000-7000-8000-0000000000c2';
const colportor2DemoId = 'dede0000-0000-7000-8000-0000000000c3';

/// Dentro de «Zona UAP» (centro -32.0715, -60.469, radio 380 m).
const lat1Uap = -32.0715;
const lon1Uap = -60.469;

/// Dentro de «Zona Centro» (centro -32.0775, -60.464, radio 380 m).
const lat1Centro = -32.0775;
const lon1Centro = -60.464;

/// La Plaza Independencia de Montevideo.
const latMvd = -34.9065;
const lonMvd = -56.2;

const _creada = '2026-10-01T12:00:00+00:00';

Map<String, Object?> _auditoria({String? deBaja}) => {
  'created_at': _creada,
  'updated_at': _creada,
  'created_by': null,
  'deleted_at': deBaja,
  'sync_version': 1,
  'xmin_w': '1',
};

/// Una zona `RADIAL` como la manda el servidor: centro, radio y el polígono que lo aproxima.
Map<String, Object?> filaZonaRadial(
  String id,
  String nombre, {
  required String campaniaCiudad,
  required double centroLat,
  required double centroLon,
  required int radioM,
}) {
  final anillo = <List<double>>[];
  for (var i = 0; i <= 32; i++) {
    final a = 2 * math.pi * (i % 32) / 32;
    anillo.add([
      centroLon + radioM * math.cos(a) / (111320 * math.cos(centroLat * math.pi / 180)),
      centroLat + radioM * math.sin(a) / 110574,
    ]);
  }
  return {
    'id': id,
    'nombre': nombre,
    'campania_ciudad_id': campaniaCiudad,
    'tipo_forma': 'RADIAL',
    'centro_lat': centroLat,
    'centro_lon': centroLon,
    'radio_m': radioM,
    'poligono_geojson': {
      'type': 'Polygon',
      'coordinates': [anillo],
    },
    'color': '#336699',
    ..._auditoria(),
  };
}

/// Lo que el pull le baja a un colportor de la demo en Libertador San Martín.
Map<String, List<Map<String, Object?>>> pullDemoLsm({
  required String usuario,
  required String inscripcion,
  required String? zona,
}) => {
  'ciudad': [
    filaCiudad(ciudadLsmId, 'Libertador San Martín', lat: -32.0736, lon: -60.4619),
    filaCiudad(ciudadMvdId, 'Montevideo', lat: -34.9011, lon: -56.1645),
  ],
  'campania': [
    filaCampania(
      campaniaLsmId,
      'Campaña Libertador San Martín (demo)',
      inicio: '2026-09-01',
      fin: '2027-03-31',
    ),
  ],
  'campania_ciudad': [
    filaCampaniaCiudad(campaniaCiudadLsmId, campania: campaniaLsmId, ciudad: ciudadLsmId),
  ],
  'zona': [
    filaZonaRadial(
      zonaCentroId,
      'Zona Centro',
      campaniaCiudad: campaniaCiudadLsmId,
      centroLat: -32.0775,
      centroLon: -60.464,
      radioM: 380,
    ),
    filaZonaRadial(
      zonaUapId,
      'Zona UAP',
      campaniaCiudad: campaniaCiudadLsmId,
      centroLat: -32.0715,
      centroLon: -60.469,
      radioM: 380,
    ),
    filaZonaRadial(
      zonaPuiggariId,
      'Zona Puiggari',
      campaniaCiudad: campaniaCiudadLsmId,
      centroLat: -32.054,
      centroLon: -60.4474,
      radioM: 700,
    ),
  ],
  'campania_colportor': [
    filaInscripcion(inscripcion, campania: campaniaLsmId, usuario: usuario, zona: zona),
  ],
};

/// Además, la campaña «Montevideo (demo)» (sin fecha de fin) con su ciudad, y la inscripción del
/// colportor en ella (viva o dada de baja, como la dejó la demo hoy).
Map<String, List<Map<String, Object?>>> sumarMontevideo(
  Map<String, List<Map<String, Object?>>> base, {
  required String usuario,
  bool inscripcionDeBaja = false,
  bool conCiudad = true,
}) => {
  ...base,
  'campania': [
    ...base['campania']!,
    filaCampania(campaniaMvdId, 'Campaña Montevideo (demo)', inicio: '2026-09-01', fin: null),
  ],
  'campania_ciudad': [
    ...base['campania_ciudad']!,
    if (conCiudad)
      filaCampaniaCiudad(campaniaCiudadMvdId, campania: campaniaMvdId, ciudad: ciudadMvdId),
  ],
  'campania_colportor': [
    ...base['campania_colportor']!,
    filaInscripcion(
      'dede0000-0000-7000-800b-000000000001',
      campania: campaniaMvdId,
      usuario: usuario,
      deBaja: inscripcionDeBaja,
    ),
  ],
};

/// El `catalogo.json` del bucket `mapas` del proyecto dev el 28/10 (lo que baja «Descargar mapa»).
const catalogoRealDeLaDemo = '''
{
  "version": 1,
  "generado_en": "2026-10-28T12:04:11Z",
  "paquetes": [
    {
      "id": "ciudad-libertador-san-martin",
      "nivel": "ciudad",
      "ambito_id": "dede0000-0000-7000-8002-000000000001",
      "nombre": "Libertador San Martín",
      "bbox": [-60.495, -32.095, -60.43, -32.04],
      "zoom_min": 0,
      "zoom_max": 15,
      "tamano_bytes": 673064,
      "version": "79a5d0ba1bdb59183bcfea50fb3b42d182ae701d5951b79cf7c2461e17e2908d",
      "partes": [
        {
          "archivo": "paquetes/ciudad/libertador-san-martin.79a5d0ba1bdb.pmtiles",
          "tamano_bytes": 673064,
          "sha256": "79a5d0ba1bdb59183bcfea50fb3b42d182ae701d5951b79cf7c2461e17e2908d",
          "bbox": [-60.495, -32.095, -60.43, -32.04]
        }
      ]
    },
    {
      "id": "ciudad-montevideo",
      "nivel": "ciudad",
      "ambito_id": "01a117a9-0619-7d34-bbfc-058f61d81448",
      "nombre": "Montevideo",
      "bbox": [-56.433, -34.945, -55.948, -34.701],
      "zoom_min": 0,
      "zoom_max": 15,
      "tamano_bytes": 10920295,
      "version": "97694b7a6c56069d73493fe50be44ef05605736d3eb44ca24f29440759057b52",
      "partes": [
        {
          "archivo": "paquetes/ciudad/montevideo.97694b7a6c56.pmtiles",
          "tamano_bytes": 10920295,
          "sha256": "97694b7a6c56069d73493fe50be44ef05605736d3eb44ca24f29440759057b52",
          "bbox": [-56.433, -34.945, -55.948, -34.701]
        }
      ]
    }
  ],
  "retirados": []
}
''';
