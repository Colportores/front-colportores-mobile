// Test de dominio: Dart puro. Lo que el teléfono recuerda del reenvío de la verificación: candados de
// una hora y esperas de 60 s por dirección, y que ninguno dura más que su tope (HU-AUTH-002;
// decisión del orquestador, 08/10, #325).
import 'package:colportores_mobile/features/auth/domain/entities/reenvios_guardados.dart';
import 'package:test/test.dart';

void main() {
  final ahora = DateTime.utc(2026, 10, 8, 10);
  const hora = Duration(minutes: 60);
  const minuto = Duration(seconds: 60);

  test('los topes son una hora para el candado y 60 s para la espera', () {
    expect(bloqueoReenvioVerificacion, hora);
    expect(esperaReenvioVerificacion, minuto);
  });

  test('vacío está vacío; con una espera o un candado, no', () {
    expect(ReenviosGuardados.vacio.estaVacio, isTrue);
    expect(ReenviosGuardados.vacio.conEspera('a@b.com', ahora).estaVacio, isFalse);
    expect(ReenviosGuardados.vacio.conBloqueo('a@b.com', ahora).estaVacio, isFalse);
  });

  group('vigentesA', () {
    test('lo que vence a la hora exacta ya no está; un milisegundo antes, sí', () {
      final guardados = ReenviosGuardados(
        bloqueos: {'a@b.com': ahora.add(hora)},
        esperas: {'a@b.com': ahora.add(minuto)},
      );

      final justo = guardados.vigentesA(ahora.add(minuto));
      expect(justo.esperas, isEmpty);
      expect(justo.bloqueos, isNotEmpty);

      final antes = guardados.vigentesA(
        ahora.add(minuto).subtract(const Duration(milliseconds: 1)),
      );
      expect(antes.esperas, isNotEmpty);

      expect(guardados.vigentesA(ahora.add(hora)).estaVacio, isTrue);
    });

    test('un vencimiento más lejos que su tope se recorta al tope contado desde ahora', () {
      final guardados = ReenviosGuardados(
        bloqueos: {'a@b.com': ahora.add(const Duration(hours: 4))},
        esperas: {'a@b.com': ahora.add(const Duration(minutes: 5))},
      );

      final vigentes = guardados.vigentesA(ahora);

      expect(vigentes.bloqueos['a@b.com'], ahora.add(hora));
      expect(vigentes.esperas['a@b.com'], ahora.add(minuto));
    });

    test('un vencimiento justo en su tope no se acorta', () {
      final guardados = ReenviosGuardados(
        bloqueos: {'a@b.com': ahora.add(hora)},
        esperas: {'a@b.com': ahora.add(minuto)},
      );

      expect(guardados.vigentesA(ahora), guardados);
    });

    test('compara instantes: una hora local y una UTC del mismo instante dan lo mismo', () {
      final guardados = ReenviosGuardados(bloqueos: {'a@b.com': ahora.add(hora)});

      expect(guardados.vigentesA(ahora.toLocal()), guardados);
    });

    test('lo vencido se va de cada dirección y de cada tipo', () {
      final guardados = ReenviosGuardados(
        bloqueos: {'vieja@b.com': ahora.add(const Duration(minutes: 10))},
        esperas: {'nueva@b.com': ahora.add(const Duration(seconds: 50))},
      );

      final vigentes = guardados.vigentesA(ahora.add(const Duration(minutes: 30)));

      expect(vigentes.bloqueos, isEmpty);
      expect(vigentes.esperas, isEmpty);
    });
  });

  group('con y sin', () {
    test('conBloqueo y conEspera guardan en UTC y reemplazan por dirección, sin tocar el otro', () {
      final local = ahora.add(hora).toLocal();

      final a = ReenviosGuardados.vacio.conBloqueo('a@b.com', local).conEspera('a@b.com', ahora);
      final b = a.conBloqueo('a@b.com', ahora.add(const Duration(minutes: 5)));

      expect(a.bloqueos['a@b.com']!.isUtc, isTrue);
      expect(a.bloqueos['a@b.com'], ahora.add(hora));
      expect(b.bloqueos, {'a@b.com': ahora.add(const Duration(minutes: 5))});
      expect(b.esperas, {'a@b.com': ahora});
    });

    test('sin quita las dos cosas de esa dirección y deja las demás', () {
      final guardados = ReenviosGuardados(
        bloqueos: {'a@b.com': ahora, 'c@d.com': ahora},
        esperas: {'a@b.com': ahora, 'e@f.com': ahora},
      );

      final sin = guardados.sin('a@b.com');

      expect(sin.bloqueos.keys, ['c@d.com']);
      expect(sin.esperas.keys, ['e@f.com']);
    });
  });
}
