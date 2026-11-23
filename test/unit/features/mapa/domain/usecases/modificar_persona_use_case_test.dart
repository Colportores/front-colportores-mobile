// Modificar una persona (HU-UBI-010): las mismas validaciones del alta, textos limpios hacia el
// repositorio y nada que escribir cuando nada cambia.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_edicion_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/modificar_persona_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/persona_falsos.dart';

void main() {
  final ahora = DateTime.utc(2026, 10, 26, 9, 30);
  late PersonaRepositorioFalso repositorio;
  late ModificarPersonaUseCase casoDeUso;

  setUp(() {
    repositorio = PersonaRepositorioFalso()
      ..contextos['per-1'] = ContextoEdicionPersona(
        persona: Persona(
          id: 'per-1',
          nombre: 'María',
          apellido: 'Fernández',
          telefono: '099 123 456',
          auditoria: auditoriaPersonas(),
        ),
        espacioId: 'esp-1',
      );
    casoDeUso = ModificarPersonaUseCase(repositorio, ahora: () => ahora);
  });

  ModificarPersonaParams params({
    String personaId = 'per-1',
    String nombre = 'María',
    String apellido = 'Fernández',
    String telefono = '099 123 456',
  }) => ModificarPersonaParams(
    personaId: personaId,
    nombre: nombre,
    apellido: apellido,
    telefono: telefono,
  );

  Map<String, String> camposDe(Either<Failure, ResultadoModificarPersona> resultado) {
    final izquierda = resultado.fold<Failure?>((f) => f, (_) => null);
    expect(izquierda, isA<FailureValidacion>());
    return (izquierda! as FailureValidacion).campos;
  }

  test('dado un teléfono nuevo, cuando se modifica, el repositorio recibe los textos limpios y la '
      'hora', () async {
    final resultado = await casoDeUso(
      params(nombre: '  María   José ', apellido: ' Fernández  ', telefono: ' 098  765 432 '),
    );

    expect(resultado.isRight(), isTrue);
    final edicion = repositorio.editadas.single;
    expect(edicion.personaId, 'per-1');
    expect(edicion.nombre, 'María José');
    expect(edicion.apellido, 'Fernández');
    expect(edicion.telefono, '098 765 432');
    expect(edicion.ahora, ahora);
  });

  test(
    'dado el apellido y el teléfono vaciados, cuando se modifica, llegan vacío y nulo',
    () async {
      await casoDeUso(params(apellido: '   ', telefono: ''));

      final edicion = repositorio.editadas.single;
      expect(edicion.apellido, '');
      expect(edicion.telefono, isNull);
    },
  );

  test('dado un nombre vacío, cuando se modifica, dice lo del canvas 32C·02 y no llega al '
      'repositorio', () async {
    final campos = camposDe(await casoDeUso(params(nombre: '   ')));

    expect(campos['nombre'], 'El nombre no puede quedar vacío.');
    expect(repositorio.editadas, isEmpty);
  });

  test('dado un nombre de una letra, cuando se modifica, pide al menos 2', () async {
    final campos = camposDe(await casoDeUso(params(nombre: 'M')));

    expect(campos['nombre'], 'El nombre necesita al menos 2 letras.');
    expect(repositorio.editadas, isEmpty);
  });

  test(
    'dado un teléfono inválido, cuando se modifica, marca el teléfono (32A·04) y no escribe',
    () async {
      final incompleto = camposDe(await casoDeUso(params(telefono: '099 12')));
      final letras = camposDe(await casoDeUso(params(telefono: 'abc123')));

      expect(incompleto['telefono'], 'Revisá el teléfono: le faltan números.');
      expect(letras.keys, ['telefono']);
      expect(repositorio.editadas, isEmpty);
    },
  );

  test('dado un nombre vacío y un teléfono inválido, cuando se modifica, marca los dos', () async {
    final campos = camposDe(await casoDeUso(params(nombre: '', telefono: 'abc')));

    expect(campos.keys, containsAll(['nombre', 'telefono']));
  });

  test('dado un número del exterior o un fijo, cuando se modifica, se acepta (S20: nunca se '
      'bloquea un número que puede ser real)', () async {
    for (final numero in ['+54 9 11 5555 1234', '2 412 3456']) {
      final r = await casoDeUso(params(telefono: numero));
      expect(r.isRight(), isTrue, reason: numero);
    }
  });

  test('dado un id en blanco, cuando se modifica, falla por la persona', () async {
    final campos = camposDe(await casoDeUso(params(personaId: '  ')));

    expect(campos.keys, ['persona']);
  });

  test('dado lo mismo que ya estaba, cuando se modifica, no hay cambios', () async {
    final resultado = await casoDeUso(params());

    expect(resultado.fold((_) => null, (r) => r.huboCambios), isFalse);
  });

  test(
    'dado un cambio, cuando se modifica, devuelve la persona como quedó y que hubo cambios',
    () async {
      final resultado = await casoDeUso(params(telefono: '098 765 432'));

      final r = resultado.getOrElse(() => throw StateError('falló'));
      expect(r.huboCambios, isTrue);
      expect(r.persona.telefono, '098 765 432');
    },
  );

  test('dado que el repositorio falla, cuando se modifica, devuelve esa falla', () async {
    repositorio.resultadosModificar.add(const FailureInesperado(causa: 'StateError'));

    final resultado = await casoDeUso(params(telefono: '098 765 432'));

    expect(resultado.fold((f) => f, (_) => null), isA<FailureInesperado>());
  });

  test('dado que los parámetros llevan datos personales, cuando se imprimen, no los muestran', () {
    final texto = '${params(nombre: 'Marta', telefono: '098 765 432')}';

    expect(texto, isNot(contains('Marta')));
    expect(texto, isNot(contains('098')));
  });
}
