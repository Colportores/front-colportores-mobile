// Alta de una persona en un espacio (HU-UBI-008): validación, armado de las entidades y ids estables.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/registrar_persona_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/persona_falsos.dart';

void main() {
  final ahora = DateTime.utc(2026, 10, 22, 15, 30);
  late PersonaRepositorioFalso repositorio;
  late RegistrarPersonaUseCase casoDeUso;
  var contador = 0;

  setUp(() {
    contador = 0;
    repositorio = PersonaRepositorioFalso();
    casoDeUso = RegistrarPersonaUseCase(
      repositorio,
      generarId: () => 'id-${++contador}',
      ahora: () => ahora,
    );
  });

  RegistrarPersonaParams params({
    String nombre = 'Ana',
    String apellido = '',
    String telefono = '',
    String nota = '',
    String espacioId = 'esp-1',
    String colportorId = 'col-1',
    IdsAltaPersona? ids,
  }) => RegistrarPersonaParams(
    ids: ids ?? casoDeUso.nuevosIds(),
    espacioId: espacioId,
    colportorId: colportorId,
    nombre: nombre,
    apellido: apellido,
    telefono: telefono,
    nota: nota,
  );

  Map<String, String> camposDe(Either<Failure, Persona> resultado) {
    final izquierda = resultado.fold<Failure?>((f) => f, (_) => null);
    expect(izquierda, isA<FailureValidacion>());
    return (izquierda! as FailureValidacion).campos;
  }

  test(
    'dado solo el nombre, cuando se registra, guarda la persona y su vínculo, sin nota',
    () async {
      final resultado = await casoDeUso(params(nombre: '  Ana   María '));

      expect(resultado.isRight(), isTrue);
      final alta = repositorio.recibidas.single;
      expect(alta.persona.nombre, 'Ana María');
      expect(alta.persona.apellido, '');
      expect(alta.persona.telefono, isNull);
      expect(alta.vinculo.espacioId, 'esp-1');
      expect(alta.vinculo.personaId, alta.persona.id);
      expect(alta.nota, isNull);
    },
  );

  test('dado el formulario completo (A·01), cuando se registra, la nota queda atada a la persona y '
      'todo lleva el colportor y la hora', () async {
    await casoDeUso(
      params(
        nombre: 'Ana',
        apellido: ' Martínez ',
        telefono: '099 123 456',
        nota: '  Prefiere de tarde  ',
      ),
    );

    final alta = repositorio.recibidas.single;
    expect(alta.persona.apellido, 'Martínez');
    expect(alta.persona.telefono, '099 123 456');
    expect(alta.nota?.texto, 'Prefiere de tarde');
    expect(alta.nota?.personaId, alta.persona.id);
    for (final a in [alta.persona.auditoria, alta.vinculo.auditoria, alta.nota!.auditoria]) {
      expect(a.createdBy, 'col-1');
      expect(a.createdAt, ahora);
      expect(a.updatedAt, ahora);
    }
  });

  test('dado una nota en blanco, cuando se registra, no crea ninguna nota', () async {
    await casoDeUso(params(nota: '  \n  '));

    expect(repositorio.recibidas.single.nota, isNull);
  });

  test('dado un alta nueva, cuando se piden los ids, cada uno es distinto', () {
    final ids = casoDeUso.nuevosIds();

    expect({ids.persona, ids.vinculo, ids.nota}, hasLength(3));
  });

  test(
    'dado el mismo juego de ids en dos intentos, cuando se registra, la persona, el vínculo y la '
    'nota llevan los mismos ids',
    () async {
      final ids = casoDeUso.nuevosIds();

      await casoDeUso(params(nota: 'x', ids: ids));
      await casoDeUso(params(nota: 'x', ids: ids));

      final (primera, segunda) = (repositorio.recibidas[0], repositorio.recibidas[1]);
      expect(segunda.persona.id, primera.persona.id);
      expect(segunda.vinculo.id, primera.vinculo.id);
      expect(segunda.nota!.id, primera.nota!.id);
    },
  );

  group('validación (no toca el repositorio)', () {
    test(
      'dado un nombre vacío (A·03), cuando se registra, rechaza con el texto del canvas',
      () async {
        final campos = camposDe(await casoDeUso(params(nombre: '  ')));

        expect(campos['nombre'], 'Escribí al menos el nombre.');
        expect(repositorio.recibidas, isEmpty);
      },
    );

    test('dado un nombre de una letra, cuando se registra, rechaza', () async {
      final campos = camposDe(await casoDeUso(params(nombre: 'A')));

      expect(campos, contains('nombre'));
      expect(repositorio.recibidas, isEmpty);
    });

    test(
      'dado un teléfono incompleto (A·04), cuando se registra, rechaza con el texto del canvas',
      () async {
        final campos = camposDe(await casoDeUso(params(telefono: '099 12')));

        expect(campos['telefono'], 'Revisá el teléfono: le faltan números.');
        expect(repositorio.recibidas, isEmpty);
      },
    );

    test(
      'dado un nombre vacío y un teléfono malo, cuando se registra, informa los dos campos',
      () async {
        final campos = camposDe(await casoDeUso(params(nombre: '', telefono: 'abc')));

        expect(campos.keys, containsAll(['nombre', 'telefono']));
      },
    );

    test('dado que falta el espacio o el colportor, cuando se registra, rechaza', () async {
      expect(camposDe(await casoDeUso(params(espacioId: ' '))), contains('espacio'));
      expect(camposDe(await casoDeUso(params(colportorId: ''))), contains('colportorId'));
      expect(repositorio.recibidas, isEmpty);
    });
  });

  test('dado que el repositorio falla, cuando se registra, devuelve esa falla', () async {
    repositorio.resultados.add(const FailureInesperado(causa: 'x'));

    final resultado = await casoDeUso(params());

    expect(resultado.isLeft(), isTrue);
  });
}
