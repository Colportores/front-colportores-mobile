// La entrevista en curso vive en el almacén seguro como un JSON por colportora, con solo ids y la
// hora de inicio (vista 39, R·05; decisión de Cristian del 23/10 en #450).
import 'dart:convert';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/entrevista_en_curso_repository_almacen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/entrevista_falsos.dart';

/// Almacén donde escribir tarda, para probar el orden.
final class _AlmacenLento implements AlmacenSeguro {
  final AlmacenSeguroEnMemoria real = AlmacenSeguroEnMemoria();

  @override
  Future<String?> leer(ClaveSegura clave) => real.leer(clave);

  @override
  Future<void> escribir(ClaveSegura clave, String valor) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return real.escribir(clave, valor);
  }

  @override
  Future<void> borrar(ClaveSegura clave) => real.borrar(clave);

  @override
  Future<void> borrarTodo() => real.borrarTodo();
}

void main() {
  late AlmacenSeguroEnMemoria almacen;
  late EntrevistaEnCursoRepositoryAlmacen repo;

  Map<String, dynamic> guardado() =>
      jsonDecode(almacen.contenido[ClaveSegura.entrevistaEnCurso]!) as Map<String, dynamic>;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    repo = EntrevistaEnCursoRepositoryAlmacen(almacen);
  });

  test('sin nada guardado, no hay entrevista en curso', () async {
    expect(await repo.leer('col-1'), isNull);
  });

  test(
    'guarda la entrevista con la hora de inicio y la lee una app que se abre de nuevo',
    () async {
      final entrevista = entrevistaDePrueba(agendaId: 'age-1', jornadaId: 'jor-1');
      await repo.guardar(entrevista);

      final otraApp = EntrevistaEnCursoRepositoryAlmacen(almacen);
      expect(await otraApp.leer('col-1'), entrevista);
      expect((await otraApp.leer('col-1'))!.inicio, entrevista.inicio);
    },
  );

  test('guarda solo ids y la hora de inicio: ningún nombre ni dirección', () async {
    await repo.guardar(entrevistaDePrueba());

    final fila = guardado()['col-1'] as Map<String, dynamic>;
    expect(
      fila.keys,
      unorderedEquals(<String>[
        'espacioId',
        'espacioPersonaId',
        'visitaId',
        'notaId',
        'inicio',
        'agendaId',
        'jornadaId',
      ]),
    );
    expect(almacen.contenido.keys, [ClaveSegura.entrevistaEnCurso]);
  });

  test('dos colportoras en el mismo teléfono no se mezclan ni se pisan', () async {
    await repo.guardar(entrevistaDePrueba(colportorId: 'col-1', visitaId: 'v1'));
    await repo.guardar(entrevistaDePrueba(colportorId: 'col-2', visitaId: 'v2'));

    expect((await repo.leer('col-1'))!.ids.visita, 'v1');
    expect((await repo.leer('col-2'))!.ids.visita, 'v2');

    await repo.borrar('col-1');
    expect(await repo.leer('col-1'), isNull);
    expect((await repo.leer('col-2'))!.ids.visita, 'v2');
  });

  test('guardar de nuevo reemplaza la entrevista de esa colportora', () async {
    await repo.guardar(entrevistaDePrueba(visitaId: 'v1'));
    await repo.guardar(entrevistaDePrueba(visitaId: 'v2'));

    expect((await repo.leer('col-1'))!.ids.visita, 'v2');
  });

  test('borrar con el id de otra visita no borra la entrevista en curso', () async {
    await repo.guardar(entrevistaDePrueba(visitaId: 'v2'));

    await repo.borrar('col-1', idVisita: 'v1');
    expect(await repo.leer('col-1'), isNotNull);

    await repo.borrar('col-1', idVisita: 'v2');
    expect(await repo.leer('col-1'), isNull);
  });

  test('al borrar la última entrevista, la clave desaparece del almacén', () async {
    await repo.guardar(entrevistaDePrueba());
    await repo.borrar('col-1');

    expect(almacen.contenido, isEmpty);
  });

  test('borrar sin entrevista no escribe nada', () async {
    await repo.borrar('col-1');
    expect(almacen.contenido, isEmpty);
  });

  test('un JSON roto cuenta como «sin entrevista» y el siguiente guardado lo reemplaza', () async {
    await almacen.escribir(ClaveSegura.entrevistaEnCurso, '{no es json');
    expect(await repo.leer('col-1'), isNull);

    await repo.guardar(entrevistaDePrueba());
    expect(await repo.leer('col-1'), isNotNull);
  });

  test(
    'una entrada incompleta o con una hora que no se entiende se ignora, sin tocar las demás',
    () async {
      await almacen.escribir(
        ClaveSegura.entrevistaEnCurso,
        jsonEncode({
          'col-1': {'espacioId': 'e', 'espacioPersonaId': 'p', 'visitaId': 'v', 'notaId': 'n'},
          'col-2': {
            'espacioId': 'e',
            'espacioPersonaId': 'p',
            'visitaId': 'v',
            'notaId': 'n',
            'inicio': 'ayer',
          },
          'col-3': 'cualquier cosa',
        }),
      );

      expect(await repo.leer('col-1'), isNull);
      expect(await repo.leer('col-2'), isNull);
      expect(await repo.leer('col-3'), isNull);

      await repo.guardar(entrevistaDePrueba(colportorId: 'col-4'));
      expect(guardado().keys, containsAll(<String>['col-1', 'col-4']));
    },
  );

  test('dos guardados seguidos de colportoras distintas salen en orden y no se pisan', () async {
    final lento = _AlmacenLento();
    final repoLento = EntrevistaEnCursoRepositoryAlmacen(lento);

    final a = repoLento.guardar(entrevistaDePrueba(colportorId: 'col-1'));
    final b = repoLento.guardar(entrevistaDePrueba(colportorId: 'col-2'));
    await Future.wait([a, b]);

    expect(await repoLento.leer('col-1'), isNotNull);
    expect(await repoLento.leer('col-2'), isNotNull);
  });

  test('una lectura pedida con un guardado en vuelo ve lo nuevo', () async {
    final lento = _AlmacenLento();
    final repoLento = EntrevistaEnCursoRepositoryAlmacen(lento);

    final guardando = repoLento.guardar(entrevistaDePrueba());
    final leida = repoLento.leer('col-1');
    await guardando;

    expect(await leida, isNotNull);
  });

  test('si el almacén falla, la operación lanza y la cola no queda trabada', () async {
    almacen.simularFalla = true;
    await expectLater(repo.guardar(entrevistaDePrueba()), throwsA(isA<AlmacenSeguroException>()));
    almacen.simularFalla = false;

    expect(await repo.leer('col-1'), isNull);
    await repo.guardar(entrevistaDePrueba());
    expect(await repo.leer('col-1'), isNotNull);
  });
}
