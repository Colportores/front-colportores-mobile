import 'dart:convert';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/data/models/campania_ciudad_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/zona_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/zona_vertice_model.dart';
import 'package:test/test.dart';

/// Filas como las arma `sync.pull` (backend-supabase 0002): todas las columnas menos `xmin_w`, los
/// `timestamptz` en ISO-8601 con zona y el `jsonb` como objeto.
const _campaniaCiudadDelta = '''
{"id": "0192a3b4-0000-7000-8000-000000000001",
 "campania_id": "0192a3b4-0000-7000-8000-0000000000c1",
 "ciudad_id": "0192a3b4-0000-7000-8000-0000000000d1",
 "created_at": "2026-09-29T22:00:00.123456+00:00",
 "updated_at": "2026-09-29T22:05:00+00:00",
 "created_by": "0192a3b4-0000-7000-8000-0000000000a1",
 "deleted_at": null,
 "sync_version": 0}
''';

const _zonaDelta = '''
{"id": "0192a3b4-0000-7000-8000-000000000002",
 "nombre": "Centro",
 "poligono_geojson": {"type": "Polygon", "coordinates": [[[-56.2, -34.95], [-56.1, -34.95],
   [-56.1, -34.85], [-56.2, -34.85], [-56.2, -34.95]]]},
 "created_at": "2026-09-29T22:00:00Z",
 "updated_at": "2026-09-29T22:00:00Z",
 "created_by": null,
 "deleted_at": "2026-09-30T10:00:00+00:00",
 "sync_version": 2,
 "campania_ciudad_id": "0192a3b4-0000-7000-8000-000000000001",
 "tipo_forma": "RADIAL",
 "centro_lat": -34.9,
 "centro_lon": -56.15,
 "radio_m": 400,
 "color": "#1A2B3C"}
''';

const _verticeDelta = '''
{"id": "0192a3b4-0000-7000-8000-000000000003",
 "zona_id": "0192a3b4-0000-7000-8000-000000000002",
 "orden": 1,
 "lat": -34.9,
 "lon": -56,
 "calle_a": "Av. Italia",
 "calle_b": null,
 "created_at": "2026-09-29T22:00:00+00:00",
 "updated_at": "2026-09-29T22:00:00+00:00",
 "created_by": null,
 "deleted_at": null,
 "sync_version": 0}
''';

Map<String, Object?> _json(String texto) => jsonDecode(texto) as Map<String, Object?>;

void main() {
  group('CampaniaCiudadModel', () {
    test('fromJson lee la fila del delta y toJson la devuelve con las mismas claves', () {
      final m = CampaniaCiudadModel.fromJson(_json(_campaniaCiudadDelta));

      expect(m.id, '0192a3b4-0000-7000-8000-000000000001');
      expect(m.campaniaId, '0192a3b4-0000-7000-8000-0000000000c1');
      expect(m.ciudadId, '0192a3b4-0000-7000-8000-0000000000d1');
      expect(m.auditoria.createdAt, DateTime.utc(2026, 9, 29, 22, 0, 0, 123));
      expect(m.auditoria.updatedAt, DateTime.utc(2026, 9, 29, 22, 5));
      expect(m.auditoria.createdBy, '0192a3b4-0000-7000-8000-0000000000a1');
      expect(m.auditoria.deletedAt, isNull);
      expect(m.toJson().keys, unorderedEquals(_json(_campaniaCiudadDelta).keys));
      expect(CampaniaCiudadModel.fromJson(m.toJson()), m);
    });

    test('pasa a la fila local y vuelve igual', () {
      final m = CampaniaCiudadModel.fromJson(_json(_campaniaCiudadDelta));

      expect(CampaniaCiudadModel.fromFila(m.aFila()), m);
    });

    test('dos filas con los mismos datos son iguales; con otra campaña, no', () {
      final a = CampaniaCiudadModel.fromJson(_json(_campaniaCiudadDelta));
      final b = CampaniaCiudadModel.fromJson(_json(_campaniaCiudadDelta));
      final otra = CampaniaCiudadModel(
        id: a.id,
        campaniaId: 'otra',
        ciudadId: a.ciudadId,
        auditoria: a.auditoria,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(otra, isNot(a));
    });
  });

  group('ZonaModel', () {
    test(
      'fromJson lee la fila del delta, con la forma como objeto, y toJson la devuelve igual',
      () {
        final json = _json(_zonaDelta);
        final m = ZonaModel.fromJson(json);

        expect(m.id, '0192a3b4-0000-7000-8000-000000000002');
        expect(m.nombre, 'Centro');
        expect(m.campaniaCiudadId, '0192a3b4-0000-7000-8000-000000000001');
        expect(m.tipoForma, 'RADIAL');
        expect((m.centroLat, m.centroLon, m.radioM), (-34.9, -56.15, 400));
        expect(m.color, '#1A2B3C');
        expect(m.poligonoGeojson['type'], 'Polygon');
        expect(m.auditoria.deletedAt, DateTime.utc(2026, 9, 30, 10));
        expect(m.auditoria.createdBy, isNull);
        expect(m.auditoria.syncVersion, 2);
        expect(m.toJson().keys, unorderedEquals(json.keys));
        expect(jsonEncode(m.toJson()['poligono_geojson']), jsonEncode(json['poligono_geojson']));
        expect(ZonaModel.fromJson(m.toJson()), m);
      },
    );

    test('dado una zona ESQUINAS sin centro, radio ni color, los deja en null', () {
      final json = {
        ..._json(_zonaDelta),
        'tipo_forma': 'ESQUINAS',
        'centro_lat': null,
        'centro_lon': null,
        'radio_m': null,
        'color': null,
      };

      final m = ZonaModel.fromJson(json);

      expect((m.centroLat, m.centroLon, m.radioM, m.color), (null, null, null, null));
    });

    test('dado el GeoJSON serializado como texto, lo decodifica; si no es un objeto, falla', () {
      final original = _json(_zonaDelta);
      final comoTexto = {...original, 'poligono_geojson': jsonEncode(original['poligono_geojson'])};

      expect(ZonaModel.fromJson(comoTexto), ZonaModel.fromJson(original));
      expect(
        () => ZonaModel.fromJson({...original, 'poligono_geojson': 3}),
        throwsA(isA<FormatException>()),
      );
    });

    test('pasa a la fila local y vuelve igual', () {
      final m = ZonaModel.fromJson(_json(_zonaDelta));

      expect(ZonaModel.fromFila(m.aFila()), m);
    });

    test('dos zonas con los mismos datos son iguales; con otro nombre, no', () {
      final a = ZonaModel.fromJson(_json(_zonaDelta));
      final b = ZonaModel.fromJson(_json(_zonaDelta));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(ZonaModel.fromJson({..._json(_zonaDelta), 'nombre': 'Norte'}), isNot(a));
    });
  });

  group('ZonaVerticeModel', () {
    test('fromJson lee la fila del delta y toJson la devuelve con las mismas claves', () {
      final json = _json(_verticeDelta);
      final m = ZonaVerticeModel.fromJson(json);

      expect(m.id, '0192a3b4-0000-7000-8000-000000000003');
      expect(m.zonaId, '0192a3b4-0000-7000-8000-000000000002');
      expect(m.orden, 1);
      expect((m.lat, m.lon), (-34.9, -56.0));
      expect((m.calleA, m.calleB), ('Av. Italia', null));
      expect(m.auditoria.updatedAt, DateTime.utc(2026, 9, 29, 22));
      expect(m.toJson().keys, unorderedEquals(json.keys));
      expect(ZonaVerticeModel.fromJson(m.toJson()), m);
    });

    test('pasa a la fila local y vuelve igual', () {
      final m = ZonaVerticeModel.fromJson(_json(_verticeDelta));

      expect(ZonaVerticeModel.fromFila(m.aFila()), m);
    });

    test('dos esquinas con los mismos datos son iguales; con otro orden, no', () {
      final a = ZonaVerticeModel.fromJson(_json(_verticeDelta));
      final b = ZonaVerticeModel(
        id: a.id,
        zonaId: a.zonaId,
        orden: 2,
        lat: a.lat,
        lon: a.lon,
        calleA: a.calleA,
        auditoria: Auditoria(createdAt: a.auditoria.createdAt, updatedAt: a.auditoria.updatedAt),
      );

      expect(a, ZonaVerticeModel.fromJson(_json(_verticeDelta)));
      expect(a.hashCode, ZonaVerticeModel.fromJson(_json(_verticeDelta)).hashCode);
      expect(b, isNot(a));
    });
  });
}
