import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 13, 45, 10, 123);
  final auditoria = Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1');

  final ubicacion = Ubicacion(
    id: 'ub-1',
    tipo: TipoUbicacion.edificio,
    calle: 'Av. Italia',
    numero: '1234',
    lat: -34.891,
    lon: -56.125,
    ciudadId: 'mvd',
    auditoria: auditoria,
  );
  final espacio = Espacio(id: 'esp-1', ubicacionId: 'ub-1', piso: '3', auditoria: auditoria);

  group('UbicacionModel', () {
    test('toJson usa exactamente las columnas de public.ubicacion (backend-supabase 0001): la fila '
        'entera, sin nada de persona', () {
      expect(UbicacionModel.fromEntity(ubicacion).toJson().keys.toSet(), {
        'id',
        'tipo',
        'calle',
        'numero',
        'lat',
        'lon',
        'ciudad_id',
        'zona_id',
        'created_at',
        'updated_at',
        'created_by',
        'deleted_at',
        'sync_version',
      });
    });

    test('toJson manda el tipo con los valores del cloud y las fechas en ISO-8601 UTC al '
        'milisegundo', () {
      final json = UbicacionModel.fromEntity(ubicacion).toJson();

      expect(json['tipo'], 'EDIFICIO');
      expect(json['created_at'], '2026-09-29T13:45:10.123Z');
      expect(json['zona_id'], isNull);
      expect(json['deleted_at'], isNull);
    });

    test('dado el JSON de toJson, cuando se lee con fromJson, vuelve la misma ubicación', () {
      final ida = UbicacionModel.fromEntity(ubicacion).toJson();

      expect(UbicacionModel.fromJson(ida).toEntity(), ubicacion);
    });

    test('dado una fila del cloud con offset y lat entera, cuando se lee, normaliza a UTC y a '
        'double', () {
      final leida = UbicacionModel.fromJson({
        ...UbicacionModel.fromEntity(ubicacion).toJson(),
        'lat': -34,
        'created_at': '2026-09-29T10:45:10.123-03:00',
        'deleted_at': '2026-09-30T00:00:00+00:00',
        'sync_version': 7,
      });

      expect(leida.lat, -34.0);
      expect(leida.auditoria.createdAt, t0);
      expect(leida.auditoria.deletedAt, DateTime.utc(2026, 9, 30));
      expect(leida.auditoria.syncVersion, 7);
    });

    for (final tipo in TipoUbicacion.values) {
      test('el código de ${tipo.name} va y vuelve', () {
        expect(UbicacionModel.tipoDesdeCodigo(UbicacionModel.codigoDeTipo(tipo)), tipo);
      });
    }

    test('un modelo no es igual a la entidad (Equatable compara el tipo): al dominio va '
        'toEntity', () {
      final modelo = UbicacionModel.fromEntity(ubicacion);

      expect(modelo == ubicacion, isFalse);
      expect(modelo.toEntity(), ubicacion);
    });
  });

  group('EspacioModel', () {
    test('toJson usa exactamente las columnas de public.espacio (backend-supabase 0001)', () {
      expect(EspacioModel.fromEntity(espacio).toJson().keys.toSet(), {
        'id',
        'ubicacion_id',
        'numero_depto',
        'piso',
        'descripcion',
        'created_at',
        'updated_at',
        'created_by',
        'deleted_at',
        'sync_version',
      });
    });

    test('dado el JSON de toJson, cuando se lee con fromJson, vuelve el mismo espacio', () {
      final ida = EspacioModel.fromEntity(espacio).toJson();

      expect(EspacioModel.fromJson(ida).toEntity(), espacio);
      expect(
        EspacioModel.fromJson({...ida, 'deleted_at': '2026-09-30T00:00:00Z'}).auditoria.deletedAt,
        DateTime.utc(2026, 9, 30),
      );
    });
  });
}
