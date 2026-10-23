// Los textos del paso «¿Con quién?» de la vista 39 (R·04 y C·07): los del canvas, tal cual.
import 'package:colportores_mobile/features/mapa/presentation/textos_con_quien.dart';
import 'package:test/test.dart';

import '../../../../helpers/persona_falsos.dart';

void main() {
  group('los del canvas', () {
    test('R·04 y C·07 dicen lo que dibuja la 39', () {
      expect(TextosConQuien.tituloSinPersonas, '¿Con quién es la entrevista?');
      expect(TextosConQuien.tituloConPersonas, '¿Con quién fue la entrevista?');
      expect(TextosConQuien.empezar, 'Empezar entrevista');
      expect(TextosConQuien.volver, 'Volver');
      expect(TextosConQuien.alguienNuevo, '+ Alguien nuevo');
      expect(TextosConQuien.alguienNuevoAyuda, 'Con el nombre alcanza');
    });

    test('dado el lugar, cuando se arma la ayuda de R·04, queda «Grecia 3307 · con el nombre '
        'alcanza»', () {
      expect(TextosConQuien.ayudaSinPersonas('Grecia 3307'), 'Grecia 3307 · con el nombre alcanza');
      expect(TextosConQuien.ayudaSinPersonas('Mataojo 2044 · Depto 3B'), contains('Depto 3B'));
    });

    test('dado que todavía no se leyó el lugar, la ayuda no queda con un « · » suelto', () {
      expect(TextosConQuien.ayudaSinPersonas(null), 'Con el nombre alcanza');
    });
  });

  group('el saldo', () {
    test('dado pesos justos, cuando se escribe, lleva punto de miles y sin decimales', () {
      expect(TextosConQuien.saldo(120000), 'Saldo \$ 1.200');
      expect(TextosConQuien.saldo(24000), 'Saldo \$ 240');
      expect(TextosConQuien.saldo(100000000), 'Saldo \$ 1.000.000');
    });

    test('dado centavos sueltos, cuando se escribe, los muestra con coma', () {
      expect(TextosConQuien.saldo(123456), 'Saldo \$ 1.234,56');
      expect(TextosConQuien.saldo(5), 'Saldo \$ 0,05');
    });

    test(
      'dado el lector de pantalla, cuando lee una fila, junta nombre y saldo y no inventa uno',
      () {
        final pedro = clienteDePersonas('pedro', 'Pedro', apellido: 'Gómez');
        final jorge = clienteDePersonas('jorge', 'Jorge');

        expect(TextosConQuien.filaParaLector(pedro, 120000), 'Pedro Gómez. Saldo \$ 1.200');
        expect(TextosConQuien.filaParaLector(jorge, null), 'Jorge');
      },
    );
  });
}
