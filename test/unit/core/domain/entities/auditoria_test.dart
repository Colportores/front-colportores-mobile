// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:test/test.dart';

void main() {
  final ahora = DateTime(2026, 9, 18, 10, 0);

  Auditoria construir({DateTime? deletedAt, int syncVersion = 0, String? createdBy}) => Auditoria(
    createdAt: ahora,
    updatedAt: ahora,
    createdBy: createdBy,
    deletedAt: deletedAt,
    syncVersion: syncVersion,
  );

  group('Auditoria', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir(createdBy: 'u1');
      final b = construir(createdBy: 'u1');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que syncVersion difiere, cuando se comparan dos instancias, no son iguales', () {
      final a = construir(syncVersion: 1);
      final b = construir(syncVersion: 2);

      expect(a, isNot(equals(b)));
    });

    test('dado que deletedAt es null, cuando se consulta estaBorrada, es false', () {
      expect(construir().estaBorrada, isFalse);
    });

    test('dado que deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      expect(construir(deletedAt: ahora).estaBorrada, isTrue);
    });

    test('dado que no se pasa syncVersion, cuando se construye, el default es 0', () {
      final a = Auditoria(createdAt: ahora, updatedAt: ahora);
      expect(a.syncVersion, equals(0));
    });
  });

  group('Auditoria.copyWith', () {
    test('dado que solo cambia syncVersion, cuando se copia, el resto de los campos se conserva '
        '(es lo que hace el sync engine al aceptar un push)', () {
      final original = construir(createdBy: 'u1', deletedAt: ahora, syncVersion: 3);

      final copia = original.copyWith(syncVersion: 4);

      expect(copia.syncVersion, equals(4));
      expect(copia.createdAt, equals(original.createdAt));
      expect(copia.updatedAt, equals(original.updatedAt));
      expect(copia.createdBy, equals('u1'));
      expect(copia.deletedAt, equals(original.deletedAt));
    });

    test('dado que no se pasa ningun campo, cuando se copia, la copia es igual al original', () {
      final original = construir(createdBy: 'u1', deletedAt: ahora, syncVersion: 2);

      expect(original.copyWith(), equals(original));
    });

    test('dado un soft delete, cuando se copia con deletedAt, queda borrada y la fecha en UTC', () {
      final borrada = construir().copyWith(deletedAt: DateTime(2026, 9, 20, 8, 0));

      expect(borrada.estaBorrada, isTrue);
      expect(borrada.deletedAt!.isUtc, isTrue);
    });

    test('dado una fila borrada, cuando se copia con deletedAt null explicito, se revierte el '
        'borrado', () {
      final restaurada = construir(deletedAt: ahora).copyWith(deletedAt: null);

      expect(restaurada.estaBorrada, isFalse);
      expect(restaurada.deletedAt, isNull);
    });

    test('dado un createdBy, cuando se copia con createdBy null explicito, queda en null', () {
      expect(construir(createdBy: 'u1').copyWith(createdBy: null).createdBy, isNull);
    });

    test('dado un createdBy nuevo, cuando se copia, reemplaza al anterior', () {
      expect(construir(createdBy: 'u1').copyWith(createdBy: 'u2').createdBy, equals('u2'));
    });

    test('dado fechas nuevas en hora local, cuando se copia, quedan normalizadas a UTC', () {
      final copia = construir().copyWith(
        createdAt: DateTime(2026, 1, 2, 3, 4),
        updatedAt: DateTime(2026, 1, 2, 3, 5),
      );

      expect(copia.createdAt.isUtc, isTrue);
      expect(copia.updatedAt.isUtc, isTrue);
    });
  });
}
