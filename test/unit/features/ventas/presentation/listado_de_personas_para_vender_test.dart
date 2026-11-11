// «¿A quién le vendés?» (#546): cómo se busca y se ordena la lista de personas de la pestaña Ventas.
import 'package:colportores_mobile/features/ventas/presentation/listado_de_personas_para_vender.dart';
import 'package:test/test.dart';

import '../../../../helpers/personas_para_vender_falsos.dart';

void main() {
  final ana = personaParaVender('1', nombre: 'Ana', apellido: 'Zapata', calle: 'Mataojo');
  final beatriz = personaParaVender(
    '2',
    nombre: 'Beatriz',
    apellido: 'Álvarez',
    calle: 'Av. Italia',
    numero: '1234',
    depto: '101',
  );
  final carlos = personaParaVender(
    '3',
    nombre: 'Carlos',
    apellido: 'Mataojo',
    calle: 'Rivadavia',
    numero: '55',
    depto: null,
  );

  List<String> ids(Iterable<FilaDePersonaParaVender> filas) => [
    for (final f in filas) f.espacioPersonaId,
  ];

  group('sin búsqueda', () {
    test(
      'dadas las personas desordenadas, cuando se arma la lista, van de la A a la Z por nombre',
      () {
        final filas = ListadoDePersonasParaVender.armar([carlos, ana, beatriz]);

        expect(ids(filas), ['ep-1', 'ep-2', 'ep-3']);
      },
    );

    test('dada una lista vacía, cuando se arma, queda vacía', () {
      expect(ListadoDePersonasParaVender.armar(const []), isEmpty);
    });

    test('dadas dos personas con el mismo nombre, cuando se arma, desempata por dirección', () {
      final a = personaParaVender('a', nombre: 'Ana', apellido: 'Gómez', calle: 'Zorrilla');
      final b = personaParaVender('b', nombre: 'Ana', apellido: 'Gómez', calle: 'Artigas');

      expect(ids(ListadoDePersonasParaVender.armar([a, b])), ['ep-b', 'ep-a']);
    });

    test('dadas personas con tilde y mayúsculas, cuando se ordena, no se distinguen', () {
      final alvaro = personaParaVender('1', nombre: 'Álvaro', apellido: 'Pérez');
      final bruno = personaParaVender('2', nombre: 'bruno', apellido: 'Díaz');
      final abel = personaParaVender('3', nombre: 'Abel', apellido: 'Sosa');

      expect(ids(ListadoDePersonasParaVender.armar([bruno, alvaro, abel])), [
        'ep-3',
        'ep-1',
        'ep-2',
      ]);
    });

    test('dada una persona sin apellido ni depto, cuando se arma, escribe solo lo que tiene', () {
      final sola = personaParaVender('9', nombre: 'Rosa', apellido: '', depto: null);

      final fila = ListadoDePersonasParaVender.armar([sola]).single;

      expect(fila.nombre, 'Rosa');
      expect(fila.direccion, 'Mataojo 2044');
    });

    test('dada una persona de un edificio, cuando se arma, la dirección lleva el depto', () {
      final fila = ListadoDePersonasParaVender.armar([ana]).single;

      expect(fila.nombre, 'Ana Zapata');
      expect(fila.direccion, 'Mataojo 2044 · Depto 3B');
    });
  });

  group('con búsqueda', () {
    test('dada una búsqueda por nombre, cuando se arma, solo quedan las que la tienen', () {
      expect(ids(ListadoDePersonasParaVender.armar([ana, beatriz, carlos], busqueda: 'bea')), [
        'ep-2',
      ]);
    });

    test('dada una búsqueda por dirección, cuando se arma, encuentra por calle y número', () {
      expect(
        ids(ListadoDePersonasParaVender.armar([ana, beatriz, carlos], busqueda: 'italia 12')),
        ['ep-2'],
      );
    });

    test(
      'dada una búsqueda con tilde o mayúsculas distintas, cuando se arma, la encuentra igual',
      () {
        expect(
          ids(ListadoDePersonasParaVender.armar([ana, beatriz, carlos], busqueda: 'ALVAREZ')),
          ['ep-2'],
        );
        expect(
          ids(ListadoDePersonasParaVender.armar([ana, beatriz, carlos], busqueda: 'álvarez')),
          ['ep-2'],
        );
      },
    );

    test('dada una búsqueda con las palabras en otro orden, cuando se arma, la encuentra', () {
      expect(ids(ListadoDePersonasParaVender.armar([ana, beatriz], busqueda: 'zapata ana')), [
        'ep-1',
      ]);
    });

    test('dada una búsqueda con espacios de más, cuando se arma, se ignoran', () {
      expect(ids(ListadoDePersonasParaVender.armar([ana, beatriz], busqueda: '   ana   ')), [
        'ep-1',
      ]);
    });

    test('dada una búsqueda solo de espacios, cuando se arma, es como no buscar', () {
      expect(ids(ListadoDePersonasParaVender.armar([beatriz, ana], busqueda: '   ')), [
        'ep-1',
        'ep-2',
      ]);
    });

    test('dada una búsqueda que no coincide con nadie, cuando se arma, queda vacía', () {
      expect(ListadoDePersonasParaVender.armar([ana, beatriz], busqueda: 'xyz'), isEmpty);
    });

    test('dada una búsqueda con una palabra que no está, cuando se arma, no entra', () {
      expect(ListadoDePersonasParaVender.armar([ana], busqueda: 'ana pérez'), isEmpty);
    });

    test('dada una búsqueda, cuando se arma, primero van las que empiezan con lo escrito y después '
        'las demás, cada grupo de la A a la Z', () {
      // «mat»: el apellido de Carlos y la calle de Ana (Mataojo) empiezan así; nadie más lo tiene.
      final dora = personaParaVender(
        '4',
        nombre: 'Dora',
        apellido: 'Gómez',
        calle: 'Tomás Gomensoro',
        numero: '10',
      );
      final elena = personaParaVender(
        '5',
        nombre: 'Elena',
        apellido: 'Matos',
        calle: 'Rivera',
        numero: '9',
      );
      final fabian = personaParaVender(
        '6',
        nombre: 'Fabián',
        apellido: 'Lima',
        calle: 'Hnos. Matos',
        numero: '3',
      );

      final filas = ListadoDePersonasParaVender.armar([
        fabian,
        elena,
        dora,
        carlos,
        ana,
      ], busqueda: 'mat');

      // Empiezan con «mat»: Ana (calle Mataojo), Carlos (apellido Mataojo), Elena (apellido Matos).
      // Solo lo contienen: Fabián (calle «Hnos. Matos»). Dora no lo tiene.
      expect(ids(filas), ['ep-1', 'ep-3', 'ep-5', 'ep-6']);
    });

    test('dada una búsqueda por el apellido, cuando se arma, cuenta como «empieza con»', () {
      final a = personaParaVender('a', nombre: 'Luis', apellido: 'Fernández', calle: 'Zelmar');
      final b = personaParaVender('b', nombre: 'Ana', apellido: 'Rey', calle: 'Fernández Crespo');
      final c = personaParaVender('c', nombre: 'Berta', apellido: 'De Fernández', calle: 'Larra');

      final filas = ListadoDePersonasParaVender.armar([c, b, a], busqueda: 'fernández');

      // a (apellido) y b (calle) empiezan con «fernández»; c solo lo contiene.
      expect(ids(filas), ['ep-b', 'ep-a', 'ep-c']);
    });
  });

  test('dada la misma persona en dos espacios, cuando se arma, hay una fila por vínculo', () {
    final enOtroDepto = personaParaVender('1b', nombre: 'Ana', apellido: 'Zapata', depto: '4C');

    final filas = ListadoDePersonasParaVender.armar([ana, enOtroDepto]);

    expect(filas.map((f) => f.direccion), ['Mataojo 2044 · Depto 3B', 'Mataojo 2044 · Depto 4C']);
  });
}
