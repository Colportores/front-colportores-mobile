import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:test/test.dart';

void main() {
  final sesion = Sesion(
    usuarioId: '01920000-0000-7000-8000-000000000001',
    email: 'ana@example.com',
    accessToken: 'jwt',
    expiraEn: DateTime.utc(2026, 9, 1, 12),
  );

  group('SesionModel', () {
    test('cuando serializa y deserializa, conserva los datos', () {
      final json = SesionModel.fromEntity(sesion).toJson();

      expect(json['expira_en'], '2026-09-01T12:00:00.000Z');
      expect(SesionModel.fromJson(json).toEntity(), sesion);
    });

    test('un SesionModel y una Sesion con los mismos datos NO son iguales (Equatable)', () {
      // Documenta el comportamiento que obliga a los repositorios a devolver toEntity().
      expect(SesionModel.fromEntity(sesion) == sesion, isFalse);
      expect(SesionModel.fromEntity(sesion).toEntity(), sesion);
    });

    test('cuando deserializa una fecha con zona horaria, la normaliza a UTC', () {
      final model = SesionModel.fromJson({
        'usuario_id': sesion.usuarioId,
        'email': sesion.email,
        'access_token': sesion.accessToken,
        'expira_en': '2026-09-01T09:00:00.000-03:00',
      });

      expect(model.expiraEn, DateTime.utc(2026, 9, 1, 12));
      expect(model.expiraEn.isUtc, isTrue);
    });

    test('un SesionModel es una Sesion (herencia, no copia)', () {
      expect(SesionModel.fromEntity(sesion), isA<Sesion>());
    });
  });
}
