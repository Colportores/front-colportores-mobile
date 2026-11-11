// La regla de los 90 días de las notas borradas (HU-UBI-012, decisión de Cristian del 27/10).
import 'package:colportores_mobile/features/mapa/domain/services/retencion_notas_borradas.dart';
import 'package:test/test.dart';

import '../../../../../helpers/nota_persona_falsos.dart';

void main() {
  final borrada = DateTime.utc(2026, 10, 26, 14, 20);

  group('RetencionNotasBorradas', () {
    test('dada una nota borrada, se va 90 días después', () {
      expect(RetencionNotasBorradas.seVaEl(borrada), DateTime.utc(2027, 1, 24, 14, 20));
    });

    test('dada una nota borrada hace 89 días, no está vencida', () {
      expect(
        RetencionNotasBorradas.vencida(borrada, borrada.add(const Duration(days: 89))),
        isFalse,
      );
    });

    test('dada una nota borrada hace justo 90 días, todavía está', () {
      expect(
        RetencionNotasBorradas.vencida(borrada, borrada.add(const Duration(days: 90))),
        isFalse,
      );
    });

    test('dada una nota borrada hace 90 días y un milisegundo, está vencida', () {
      final ahora = borrada.add(const Duration(days: 90, milliseconds: 1));
      expect(RetencionNotasBorradas.vencida(borrada, ahora), isTrue);
    });

    test('dado un reloj que está antes del borrado, la nota no está vencida', () {
      expect(
        RetencionNotasBorradas.vencida(borrada, borrada.subtract(const Duration(days: 400))),
        isFalse,
      );
    });

    test('el corte de la limpieza es 90 días antes de ahora', () {
      final ahora = DateTime.utc(2027, 1, 24, 14, 20);
      expect(RetencionNotasBorradas.corte(ahora), borrada);
    });

    test('estaEnBorradas: una activa no, una borrada reciente sí, una vencida no', () {
      final ahora = DateTime.utc(2026, 11, 1);
      final activa = notaDePrueba('a', 'Activa');
      final reciente = notaDePrueba('r', 'Reciente', borrada: DateTime.utc(2026, 10, 30));
      final vencida = notaDePrueba('v', 'Vencida', borrada: DateTime.utc(2026, 7, 1));

      expect(RetencionNotasBorradas.estaEnBorradas(activa, ahora), isFalse);
      expect(RetencionNotasBorradas.estaEnBorradas(reciente, ahora), isTrue);
      expect(RetencionNotasBorradas.estaEnBorradas(vencida, ahora), isFalse);
    });
  });
}
