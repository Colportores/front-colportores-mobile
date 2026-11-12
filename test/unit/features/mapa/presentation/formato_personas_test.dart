// Cómo se escribe una persona y su espacio en las vistas de personas (HU-UBI-008).
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_personas.dart';
import 'package:test/test.dart';

import '../../../../helpers/persona_falsos.dart';

void main() {
  group('nombre e iniciales', () {
    test('dado nombre y apellido, cuando se escriben, salen juntos y con dos iniciales', () {
      final p = clienteDePersonas('p', 'ana', apellido: 'martínez').persona;

      expect(FormatoPersonas.nombreCompleto(p), 'ana martínez');
      expect(FormatoPersonas.iniciales(p), 'AM');
    });

    test('dado solo el nombre, cuando se escribe, no queda un espacio de más', () {
      final p = clienteDePersonas('p', 'Jorge').persona;

      expect(FormatoPersonas.nombreCompleto(p), 'Jorge');
      expect(FormatoPersonas.iniciales(p), 'J');
    });

    test('dado un nombre que empieza con un emoji, cuando se toman las iniciales, no se parte el '
        'carácter', () {
      final p = clienteDePersonas('p', '😀 Ana').persona;

      expect(FormatoPersonas.iniciales(p), '😀');
    });
  });

  group('editar (32C)', () {
    test('dado los campos que cambió, cuando se dicen, van separados con comas y una «y»', () {
      expect(TextosPersonas.cambiaste(['nombre']), 'Cambiaste nombre.');
      expect(TextosPersonas.cambiaste(['nombre', 'apellido']), 'Cambiaste nombre y apellido.');
      expect(
        TextosPersonas.cambiaste(['nombre', 'apellido', 'teléfono']),
        'Cambiaste nombre, apellido y teléfono.',
      );
    });

    test(
      'dado el cambio grande del canvas 32C·03, cuando se arma el aviso, es el texto literal',
      () {
        expect(
          TextosPersonas.otraPersona(
            campos: ['nombre', 'apellido', 'teléfono'],
            antes: 'María',
            despues: 'Roberto',
          ),
          'Cambiaste nombre, apellido y teléfono. Si es otra persona, conviene dar de baja a María '
          'y registrar a Roberto aparte, para no mezclar el historial.',
        );
      },
    );

    test('dado el canvas 32C, cuando se piden los textos, son los de las tres pantallas', () {
      expect(TextosPersonas.editarRotulo, 'EDITAR PERSONA');
      expect(TextosPersonas.editarTitulo, 'Editar persona');
      expect(TextosPersonas.guardarCambios, 'Guardar cambios');
      expect(TextosPersonas.guardarIgual, 'Guardar igual');
      expect(TextosPersonas.darDeBajaYCrearNueva, 'Dar de baja y crear nueva');
      expect(TextosPersonas.cambiosGuardados, 'Cambios guardados en tu teléfono.');
    });
  });

  group('teléfono tapado', () {
    test('dado un celular, cuando se tapa, deja el comienzo y el final', () {
      expect(FormatoPersonas.telefonoOculto('099 123 412'), 'Tel. 099 ••• 412');
      expect(FormatoPersonas.telefonoOculto('+598 99 123 456'), 'Tel. +598 ••• 456');
    });

    test('dado un teléfono corto o ninguno, cuando se tapa, no deja ver de más', () {
      expect(FormatoPersonas.telefonoOculto('1234'), 'Tel. ••• 34');
      expect(FormatoPersonas.telefonoOculto(null), 'Sin teléfono');
      expect(FormatoPersonas.telefonoOculto('  '), 'Sin teléfono');
    });

    test('dado un teléfono, cuando lo lee el lector de pantalla, solo dice el final', () {
      expect(FormatoPersonas.telefonoParaLector('099 123 412'), 'Teléfono terminado en 412');
      expect(FormatoPersonas.telefonoParaLector(null), 'Sin teléfono');
    });
  });

  group('espacio', () {
    test('dado un depto, cuando se titula, dice «Depto» y el número; sin número, «Sin número»', () {
      final u = ubicacionDePersonas();

      expect(FormatoPersonas.tituloEspacio(espacioDePersonas(numeroDepto: '3B'), u), 'Depto 3B');
      expect(FormatoPersonas.tituloEspacio(espacioDePersonas(numeroDepto: ' '), u), 'Sin número');
      expect(FormatoPersonas.tituloEspacio(espacioDePersonas(numeroDepto: null), u), 'Sin número');
    });

    test('dado una casa o un negocio, cuando se titula, dice el tipo', () {
      final casa = ubicacionDePersonas(tipo: TipoUbicacion.casa);

      expect(FormatoPersonas.tituloEspacio(espacioDePersonas(numeroDepto: null), casa), 'Casa');
    });

    test('dado el espacio, cuando se dice dónde está, la dirección va con el depto solo en un '
        'edificio', () {
      final e = espacioDePersonas(numeroDepto: '3B');

      expect(
        FormatoPersonas.dondeEstaElEspacio(e, ubicacionDePersonas()),
        'Mataojo 2044 · Depto 3B',
      );
      expect(
        FormatoPersonas.dondeEstaElEspacio(e, ubicacionDePersonas(tipo: TipoUbicacion.casa)),
        'Mataojo 2044',
      );
    });

    test('dado un piso, cuando se escribe, dice «Piso 1»; sin piso, nada', () {
      expect(FormatoPersonas.pisoDelEspacio(espacioDePersonas(piso: '1')), 'Piso 1');
      expect(FormatoPersonas.pisoDelEspacio(espacioDePersonas(piso: null)), isNull);
    });
  });
}
