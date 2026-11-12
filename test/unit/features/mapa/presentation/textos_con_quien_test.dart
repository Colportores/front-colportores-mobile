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

  group('el nombre repetido', () {
    final padre = clienteDePersonas('padre', 'Pedro', apellido: 'Gómez', telefono: '099 123 412');
    final hijo = clienteDePersonas('hijo', 'Pedro', apellido: 'Gómez', minutos: 5);
    final ana = clienteDePersonas('ana', 'Ana', apellido: 'Gómez');

    test(
      'dadas dos con el mismo nombre (sin mirar mayúsculas ni espacios), solo ellas cuentan',
      () {
        final tocaya = clienteDePersonas('t', ' pedro ', apellido: 'GÓMEZ');
        expect(TextosConQuien.conNombreRepetido([padre, hijo, ana]), {'padre', 'hijo'});
        expect(TextosConQuien.conNombreRepetido([padre, tocaya]), {'padre', 't'});
        expect(TextosConQuien.conNombreRepetido([padre, ana]), isEmpty);
        expect(TextosConQuien.conNombreRepetido(const []), isEmpty);
      },
    );

    test('con teléfono se ve enmascarado; sin teléfono, «Cargada el» con día y mes', () {
      expect(TextosConQuien.paraDistinguir(padre.persona), 'Tel. 099 ••• 412');
      expect(TextosConQuien.paraDistinguir(hijo.persona), 'Cargada el 22/10');
    });

    test('el lector suma el dato que distingue antes del saldo, y solo si el nombre se repite', () {
      expect(
        TextosConQuien.filaParaLector(padre, 120000, nombreRepetido: true),
        'Pedro Gómez. Teléfono terminado en 412. Saldo \$ 1.200',
      );
      expect(
        TextosConQuien.filaParaLector(hijo, null, nombreRepetido: true),
        'Pedro Gómez. Cargada el 22/10',
      );
      expect(TextosConQuien.filaParaLector(hijo, null), 'Pedro Gómez');
    });
  });
  group('el nombre repetido y también la segunda línea', () {
    final padre = clienteDePersonas(
      'padre',
      'Pedro',
      apellido: 'Gómez',
      creada: DateTime(2026, 10, 23, 15, 40),
    );
    final hijo = clienteDePersonas(
      'hijo',
      'Pedro',
      apellido: 'Gómez',
      creada: DateTime(2026, 10, 23, 9, 5),
    );
    final conTelA = clienteDePersonas(
      'a',
      'Pedro',
      apellido: 'Gómez',
      telefono: '099 123 412',
      creada: DateTime(2026, 10, 23, 15, 40),
    );
    final conTelB = clienteDePersonas(
      'b',
      'Pedro',
      apellido: 'Gómez',
      telefono: '099 777 412',
      creada: DateTime(2026, 10, 24, 8, 0),
    );
    final otro = clienteDePersonas('otro', 'Pedro', apellido: 'Gómez', minutos: 3);

    test('dos sin teléfono cargados el mismo día suman la hora de alta (hora local, HH:mm)', () {
      expect(TextosConQuien.conSegundaLineaRepetida([padre, hijo]), {'padre', 'hijo'});
      expect(
        TextosConQuien.paraDistinguir(padre.persona, conHora: true),
        'Cargada el 23/10 a las 15:40',
      );
      expect(
        TextosConQuien.paraDistinguir(hijo.persona, conHora: true),
        'Cargada el 23/10 a las 09:05',
      );
    });

    test('con el mismo teléfono enmascarado, la hora va después de «Tel. 099 ••• 412 · »', () {
      expect(TextosConQuien.conSegundaLineaRepetida([conTelA, conTelB]), {'a', 'b'});
      expect(
        TextosConQuien.paraDistinguir(conTelB.persona, conHora: true),
        'Tel. 099 ••• 412 · Cargada el 24/10 a las 08:00',
      );
    });

    test('solo suman la hora las filas cuya línea se repite, no las que ya se distinguen', () {
      // padre e hijo comparten «Cargada el 23/10»; «otro» (con teléfono propio) ya se distingue.
      final conTel = clienteDePersonas('t', 'Pedro', apellido: 'Gómez', telefono: '098 555 111');
      expect(TextosConQuien.conSegundaLineaRepetida([padre, hijo, conTel]), {'padre', 'hijo'});
      expect(TextosConQuien.conSegundaLineaRepetida([padre, conTel]), isEmpty);
      expect(TextosConQuien.conSegundaLineaRepetida([padre, otro]), isEmpty);
    });

    test('un nombre único, o ninguno, no suma nada', () {
      final ana = clienteDePersonas('ana', 'Ana', apellido: 'Gómez');
      expect(TextosConQuien.conSegundaLineaRepetida([padre, ana]), isEmpty);
      expect(TextosConQuien.conSegundaLineaRepetida(const []), isEmpty);
    });

    test('el lector lee lo mismo que ve la pantalla', () {
      expect(
        TextosConQuien.filaParaLector(padre, null, nombreRepetido: true, conHora: true),
        'Pedro Gómez. Cargada el 23/10 a las 15:40',
      );
      expect(
        TextosConQuien.filaParaLector(conTelB, 120000, nombreRepetido: true, conHora: true),
        'Pedro Gómez. Teléfono terminado en 412. Cargada el 24/10 a las 08:00. Saldo \$ 1.200',
      );
      expect(TextosConQuien.filaParaLector(padre, null, conHora: true), 'Pedro Gómez');
    });
  });
}
