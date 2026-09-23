// Test de la capa data: Dart puro.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:test/test.dart';

void main() {
  Jornada completa() => Jornada(
    id: 'jor-1',
    colportorId: 'u-1',
    inicio: DateTime.utc(2026, 9, 22, 12, 15),
    fin: DateTime.utc(2026, 9, 22, 20),
    acompananteId: 'u-2',
    tipoAcompanamiento: 'tipo-x',
    totalVisitas: 14,
    totalVentas: 3,
    auditoria: Auditoria(
      createdAt: DateTime.utc(2026, 9, 22, 12, 15),
      updatedAt: DateTime.utc(2026, 9, 22, 20),
      createdBy: 'u-1',
      deletedAt: DateTime.utc(2026, 9, 23),
      syncVersion: 7,
    ),
  );

  Jornada recienIniciada() => Jornada(
    id: 'jor-2',
    colportorId: 'u-1',
    inicio: DateTime.utc(2026, 9, 22, 12, 15),
    auditoria: Auditoria(
      createdAt: DateTime.utc(2026, 9, 22, 12, 15),
      updatedAt: DateTime.utc(2026, 9, 22, 12, 15),
    ),
  );

  group('JornadaModel', () {
    test('dado una jornada, cuando se serializa, las claves son exactamente las columnas de la '
        'tabla jornada del cloud (sin PII)', () {
      final json = JornadaModel.fromEntity(completa()).toJson();

      expect(json.keys, [
        'id',
        'colportor_id',
        'inicio',
        'fin',
        'acompaniante_id',
        'tipo_acompaniamiento',
        'total_visitas',
        'total_ventas',
        'created_at',
        'updated_at',
        'created_by',
        'deleted_at',
        'sync_version',
      ]);
    });

    test('dado una jornada, cuando se serializa, las fechas van en ISO-8601 UTC', () {
      final json = JornadaModel.fromEntity(completa()).toJson();

      expect(json['inicio'], '2026-09-22T12:15:00.000Z');
      expect(json['fin'], '2026-09-22T20:00:00.000Z');
      expect(json['created_at'], '2026-09-22T12:15:00.000Z');
      expect(json['updated_at'], '2026-09-22T20:00:00.000Z');
      expect(json['deleted_at'], '2026-09-23T00:00:00.000Z');
    });

    test('dado una jornada con todos los campos, cuando va y vuelve por JSON, toEntity es igual a '
        'la original', () {
      final original = completa();

      final vuelta = JornadaModel.fromJson(JornadaModel.fromEntity(original).toJson()).toEntity();

      expect(vuelta, original);
      expect(vuelta.runtimeType, Jornada);
    });

    test('dado una jornada recién iniciada, cuando va y vuelve por JSON, los opcionales siguen '
        'en null', () {
      final original = recienIniciada();

      final json = JornadaModel.fromEntity(original).toJson();
      final vuelta = JornadaModel.fromJson(json).toEntity();

      expect(json['fin'], isNull);
      expect(json['acompaniante_id'], isNull);
      expect(json['created_by'], isNull);
      expect(json['deleted_at'], isNull);
      expect(vuelta, original);
      expect(vuelta.estaAbierta, isTrue);
    });

    test('dado un JSON con fechas en offset +00:00 (timestamptz de Postgres), cuando se '
        'deserializa, quedan en UTC', () {
      final json = JornadaModel.fromEntity(recienIniciada()).toJson()
        ..['inicio'] = '2026-09-22T12:15:00+00:00'
        ..['created_at'] = '2026-09-22T09:15:00-03:00';

      final modelo = JornadaModel.fromJson(json);

      expect(modelo.inicio, DateTime.utc(2026, 9, 22, 12, 15));
      expect(modelo.inicio.isUtc, isTrue);
      expect(modelo.auditoria.createdAt, DateTime.utc(2026, 9, 22, 12, 15));
      expect(modelo.auditoria.createdAt.isUtc, isTrue);
    });

    test('dado un modelo, cuando se compara con la entidad, no es igual (Equatable compara el '
        'runtimeType) pero toEntity sí', () {
      final jornada = completa();
      final modelo = JornadaModel.fromEntity(jornada);

      expect(modelo, isNot(equals(jornada)));
      expect(modelo.toEntity(), jornada);
    });
  });
}
