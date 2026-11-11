// Los casos de uso de las notas de un lugar (vista 39, C·05), contra un repositorio en memoria.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/notas_ubicacion_use_cases.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/nota_ubicacion_falsos.dart';

void main() {
  final reloj = DateTime.utc(2026, 10, 22, 17, 30);
  late NotaUbicacionRepositorioFalso repo;

  setUp(() => repo = NotaUbicacionRepositorioFalso());

  NotaUbicacion exito(Either<Failure, NotaUbicacion> r) =>
      r.fold((f) => fail('falló: $f'), (n) => n);

  Map<String, String> campos(Either<Failure, NotaUbicacion> r) =>
      r.fold((f) => (f as FailureValidacion).campos, (_) => fail('debía fallar'));

  group('AgregarNotaUbicacionUseCase', () {
    late AgregarNotaUbicacionUseCase agregar;
    setUp(() => agregar = AgregarNotaUbicacionUseCase(repo, ahora: () => reloj));

    AgregarNotaUbicacionParams params({
      String id = 'nota-1',
      String ubicacion = 'ubi-1',
      String colportor = 'col-1',
      String texto = 'El portón no cierra',
    }) => AgregarNotaUbicacionParams(
      id: id,
      ubicacionId: ubicacion,
      colportorId: colportor,
      texto: texto,
    );

    test('dado un texto, cuando agrego una nota, se crea con mi user_id y el reloj', () async {
      final nota = exito(await agregar(params()));

      expect(nota.id, 'nota-1');
      expect(nota.ubicacionId, 'ubi-1');
      expect(nota.texto, 'El portón no cierra');
      expect(nota.auditoria.createdBy, 'col-1');
      expect(nota.auditoria.createdAt, reloj);
      expect(nota.auditoria.updatedAt, reloj);
      expect(nota.estaBorrada, isFalse);
    });

    test('dado varias notas para el mismo lugar, cuando agrego, caben todas', () async {
      await agregar(params(id: 'a'));
      await agregar(params(id: 'b', texto: 'Otra'));

      expect(repo.notas, hasLength(2));
    });

    test('dado un texto con espacios y saltos en los bordes, se guarda sin ellos', () async {
      final nota = exito(await agregar(params(texto: '  \n Perro suelto \n ')));

      expect(nota.texto, 'Perro suelto');
    });

    test('dado un texto en blanco, falla por el campo texto y no toca el repositorio', () async {
      for (final vacio in ['', '   ', '\n\t ']) {
        expect(campos(await agregar(params(texto: vacio))).keys, ['texto']);
      }
      expect(repo.llamadas, isEmpty);
    });

    test('dado faltantes (id, lugar, colportor), falla por cada campo', () async {
      final r = await agregar(params(id: ' ', ubicacion: '', colportor: ' '));

      expect(campos(r).keys, containsAll(['id', 'ubicacion', 'colportorId']));
      expect(repo.llamadas, isEmpty);
    });

    test('dado 6000 caracteres, se guarda entera (el límite de 5000 es blando)', () async {
      final nota = exito(await agregar(params(texto: 'a' * 6000)));

      expect(nota.texto.length, 6000);
    });

    test('dado el mismo id dos veces (doble toque), queda una sola nota', () async {
      await agregar(params());
      await agregar(params(texto: 'Distinto'));

      expect(repo.notas, hasLength(1));
      expect(repo.notas.single.texto, 'El portón no cierra');
    });

    test('dado que el repositorio falla, devuelve esa falla', () async {
      repo.resultados['agregar'] = [const FailureInesperado(causa: 'x')];

      expect((await agregar(params())).isLeft(), isTrue);
    });
  });

  group('EditarNotaUbicacionUseCase', () {
    late EditarNotaUbicacionUseCase editar;
    setUp(() {
      repo = NotaUbicacionRepositorioFalso(notas: [notaDeLugar('n1', 'Original')]);
      editar = EditarNotaUbicacionUseCase(repo, ahora: () => reloj);
    });

    test(
      'dado un texto nuevo, cuando edito, cambia el texto y updated_at pero no created_at',
      () async {
        final nota = exito(
          await editar(const EditarNotaUbicacionParams(notaId: 'n1', texto: ' Nuevo ')),
        );

        expect(nota.texto, 'Nuevo');
        expect(nota.auditoria.updatedAt, reloj);
        expect(nota.auditoria.createdAt.toUtc(), DateTime(2026, 10, 22, 14, 20).toUtc());
      },
    );

    test('dado un texto en blanco o un id vacío, falla sin tocar el repositorio', () async {
      expect(
        campos(await editar(const EditarNotaUbicacionParams(notaId: 'n1', texto: '  '))).keys,
        ['texto'],
      );
      expect(campos(await editar(const EditarNotaUbicacionParams(notaId: ' ', texto: 'x'))).keys, [
        'id',
      ]);
      expect(repo.llamadas, isEmpty);
    });
  });

  group('Borrar y restaurar', () {
    setUp(() => repo = NotaUbicacionRepositorioFalso(notas: [notaDeLugar('n1', 'Texto')]));

    test('dado una nota, cuando la borro, queda con deleted_at y no se pierde', () async {
      final nota = exito(await BorrarNotaUbicacionUseCase(repo, ahora: () => reloj)('n1'));

      expect(nota.estaBorrada, isTrue);
      expect(repo.notas, hasLength(1));
    });

    test('dado una nota borrada, cuando la restauro, vuelve a estar activa', () async {
      await BorrarNotaUbicacionUseCase(repo, ahora: () => reloj)('n1');

      final nota = exito(await RestaurarNotaUbicacionUseCase(repo, ahora: () => reloj)('n1'));

      expect(nota.estaBorrada, isFalse);
      expect(nota.texto, 'Texto');
    });

    test('dado un id vacío, borrar y restaurar fallan por el campo id', () async {
      expect(campos(await BorrarNotaUbicacionUseCase(repo)(' ')).keys, ['id']);
      expect(campos(await RestaurarNotaUbicacionUseCase(repo)('')).keys, ['id']);
      expect(repo.llamadas, isEmpty);
    });
  });

  test('dado una nota, cuando se la imprime, no muestra su texto', () {
    expect(notaDeLugar('n1', 'Secreto del lugar').toString(), isNot(contains('Secreto')));
    expect(
      const AgregarNotaUbicacionParams(
        id: 'a',
        ubicacionId: 'u',
        colportorId: 'c',
        texto: 'Secreto del lugar',
      ).toString(),
      isNot(contains('Secreto')),
    );
  });
}
