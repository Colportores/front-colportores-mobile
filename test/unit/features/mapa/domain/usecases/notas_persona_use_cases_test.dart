// Los casos de uso de las notas de una persona (HU-UBI-012), contra un repositorio en memoria.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/notas_persona_use_cases.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/nota_persona_falsos.dart';

void main() {
  final reloj = DateTime.utc(2026, 10, 22, 17, 30);
  late NotaPersonaRepositorioFalso repo;

  setUp(() => repo = NotaPersonaRepositorioFalso());

  NotaPersona exito(Either<Failure, NotaPersona> r) => r.fold((f) => fail('falló: $f'), (n) => n);

  Map<String, String> campos(Either<Failure, NotaPersona> r) =>
      r.fold((f) => (f as FailureValidacion).campos, (_) => fail('debía fallar'));

  group('AgregarNotaPersonaUseCase', () {
    late AgregarNotaPersonaUseCase agregar;
    setUp(() => agregar = AgregarNotaPersonaUseCase(repo, ahora: () => reloj));

    AgregarNotaPersonaParams params({
      String id = 'nota-1',
      String persona = 'per-1',
      String colportor = 'col-1',
      String texto = 'Le interesa Caminos de la Vida',
    }) =>
        AgregarNotaPersonaParams(id: id, personaId: persona, colportorId: colportor, texto: texto);

    test(
      'dado un texto, cuando agrego la primera nota, se crea con mi user_id como autor',
      () async {
        final nota = exito(await agregar(params()));

        expect(nota.id, 'nota-1');
        expect(nota.personaId, 'per-1');
        expect(nota.texto, 'Le interesa Caminos de la Vida');
        expect(nota.auditoria.createdBy, 'col-1');
        expect(nota.auditoria.createdAt, reloj);
        expect(nota.auditoria.updatedAt, reloj);
        expect(nota.estaBorrada, isFalse);
        expect(repo.notas, [nota]);
      },
    );

    test(
      'dado un texto con espacios y saltos en los bordes, cuando agrego, se guarda sin ellos',
      () async {
        final nota = exito(await agregar(params(texto: '  \n Prefiere de tarde \n ')));

        expect(nota.texto, 'Prefiere de tarde');
      },
    );

    test(
      'dado un texto vacío o en blanco, cuando agrego, falla por el campo texto y no toca el repositorio',
      () async {
        for (final texto in ['', '   ', '\n\n', '​']) {
          final r = await agregar(params(texto: texto));

          expect(campos(r).keys, ['texto'], reason: 'texto: "$texto"');
          expect(campos(r)['texto'], 'Escribí la nota para poder guardarla.');
        }
        expect(repo.llamadas, isEmpty);
      },
    );

    test(
      'dado que falta el id, la persona o el colportor, cuando agrego, falla por cada uno',
      () async {
        final r = await agregar(params(id: ' ', persona: '', colportor: ' '));

        expect(campos(r).keys, containsAll(['id', 'persona', 'colportorId']));
        expect(repo.llamadas, isEmpty);
      },
    );

    test('dado más de 5000 caracteres, cuando agrego, se guarda igual (límite blando)', () async {
      final nota = exito(await agregar(params(texto: 'a' * 6000)));

      expect(nota.texto.length, 6000);
    });

    test(
      'dado el mismo id repetido (doble toque o reintento), cuando agrego dos veces, queda una sola nota',
      () async {
        await agregar(params());
        await agregar(params());

        expect(repo.notas, hasLength(1));
      },
    );

    test('dado que el repositorio rechaza, cuando agrego, devuelve esa falla', () async {
      repo.resultados['agregar'] = [const FailureInesperado()];

      final r = await agregar(params());

      expect(r.isLeft(), isTrue);
    });

    test('dado un params, cuando se lo imprime, no muestra el texto de la nota', () {
      expect(params(texto: 'secreto').toString(), isNot(contains('secreto')));
    });
  });

  group('EditarNotaPersonaUseCase', () {
    late EditarNotaPersonaUseCase editar;
    setUp(() => editar = EditarNotaPersonaUseCase(repo, ahora: () => reloj));

    test(
      'dado una nota mía, cuando la edito, cambia el texto y updated_at; created_at y created_by quedan',
      () async {
        final original = notaDePrueba('nota-1', 'Vieja', creada: DateTime.utc(2026, 10, 1, 12));
        repo = NotaPersonaRepositorioFalso(notas: [original]);
        editar = EditarNotaPersonaUseCase(repo, ahora: () => reloj);

        final nota = exito(
          await editar(const EditarNotaPersonaParams(notaId: 'nota-1', texto: 'Nueva')),
        );

        expect(nota.texto, 'Nueva');
        expect(nota.auditoria.updatedAt, reloj);
        expect(nota.auditoria.createdAt, original.auditoria.createdAt);
        expect(nota.auditoria.createdBy, 'col-1');
      },
    );

    test(
      'dado un texto en blanco, cuando edito, falla por el campo texto y no toca el repositorio',
      () async {
        final r = await editar(const EditarNotaPersonaParams(notaId: 'nota-1', texto: '  '));

        expect(campos(r).keys, ['texto']);
        expect(repo.llamadas, isEmpty);
      },
    );

    test('dado que falta el id, cuando edito, falla por el campo id', () async {
      final r = await editar(const EditarNotaPersonaParams(notaId: ' ', texto: 'algo'));

      expect(campos(r).keys, ['id']);
    });

    test('dado un texto con espacios en los bordes, cuando edito, se guarda limpio', () async {
      repo = NotaPersonaRepositorioFalso(notas: [notaDePrueba('nota-1', 'Vieja')]);
      editar = EditarNotaPersonaUseCase(repo, ahora: () => reloj);

      await editar(const EditarNotaPersonaParams(notaId: 'nota-1', texto: '  Nueva \n'));

      expect(repo.textosRecibidos, ['Nueva']);
    });
  });

  group('BorrarNotaPersonaUseCase y RestaurarNotaPersonaUseCase', () {
    test('dado una nota, cuando la borro, setea deleted_at; y al restaurarla vuelve', () async {
      repo = NotaPersonaRepositorioFalso(notas: [notaDePrueba('nota-1', 'Algo')]);
      final borrar = BorrarNotaPersonaUseCase(repo, ahora: () => reloj);
      final restaurar = RestaurarNotaPersonaUseCase(repo, ahora: () => reloj);

      final borrada = exito(await borrar('nota-1'));
      expect(borrada.auditoria.deletedAt, reloj);
      expect(borrada.estaBorrada, isTrue);

      final vuelta = exito(await restaurar('nota-1'));
      expect(vuelta.estaBorrada, isFalse);
      expect(vuelta.texto, 'Algo');
    });

    test(
      'dado un id en blanco, cuando borro o restauro, falla por el campo id sin tocar el repositorio',
      () async {
        final borrar = BorrarNotaPersonaUseCase(repo);
        final restaurar = RestaurarNotaPersonaUseCase(repo);

        expect(campos(await borrar(' ')).keys, ['id']);
        expect(campos(await restaurar('')).keys, ['id']);
        expect(repo.llamadas, isEmpty);
      },
    );

    test('dado que el repositorio falla, cuando borro, devuelve esa falla', () async {
      repo = NotaPersonaRepositorioFalso(notas: [notaDePrueba('nota-1', 'Algo')]);
      repo.resultados['borrar'] = [const FailureInesperado()];

      expect((await BorrarNotaPersonaUseCase(repo)('nota-1')).isLeft(), isTrue);
    });
  });
}
