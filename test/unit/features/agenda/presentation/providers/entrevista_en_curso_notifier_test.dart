// El estado de la entrevista en curso de una colportora (vista 39, R·05; #450): lo que sobrevive a
// cerrar la app, el doble toque y los casos en que el almacén falla.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/entrevista_en_curso.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart'
    show TipoResultadoVisita;
import 'package:colportores_mobile/features/agenda/domain/services/destino_de_entrevista.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/cerrar_entrevista_con_venta_use_case.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/finalizar_entrevista_use_case.dart'
    show entrevistaSinLugar;
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/entrevista_falsos.dart';

void main() {
  late MontajeEntrevista montaje;
  late ProviderContainer contenedor;

  ProviderContainer crear() {
    final c = ProviderContainer(overrides: montaje.overrides);
    addTearDown(c.dispose);
    return c;
  }

  EntrevistaEnCursoNotifier notificador() =>
      contenedor.read(entrevistaEnCursoProvider('col-1').notifier);

  EstadoEntrevista estado() => contenedor.read(entrevistaEnCursoProvider('col-1'));

  setUp(() {
    montaje = MontajeEntrevista();
    contenedor = crear();
  });

  group('al arrancar la app', () {
    test('sin entrevista guardada: no hay entrevista y no se recuperó nada', () async {
      final e = await notificador().esperarLectura();

      expect(e.cargando, isFalse);
      expect(e.entrevista, isNull);
      expect(e.recuperada, isFalse);
    });

    test('con una guardada de antes: sigue en curso, con su hora de inicio, y cuenta como '
        'recuperada (la salida no se supone)', () async {
      await montaje.almacen.guardar(entrevistaDePrueba());

      final e = await notificador().esperarLectura();

      expect(e.entrevista!.inicio, inicioEntrevista.toUtc());
      expect(e.recuperada, isTrue);
    });

    test('mientras lee, está cargando', () {
      expect(estado().cargando, isTrue);
      expect(estado().entrevista, isNull);
    });

    test('la guardada de otra colportora no aparece', () async {
      await montaje.almacen.guardar(entrevistaDePrueba(colportorId: 'col-2'));

      final e = await notificador().esperarLectura();

      expect(e.entrevista, isNull);
    });

    test('si el almacén no se puede leer, no hay entrevista y la pantalla no se rompe', () async {
      montaje.rota.fallaAlLeer = true;

      final e = await notificador().esperarLectura();

      expect(e.cargando, isFalse);
      expect(e.entrevista, isNull);
    });
  });

  group('empezar', () {
    Future<Object?> empezar() async => (await notificador().empezar(
      espacioId: 'esp-1',
      espacioPersonaId: 'ep-1',
    )).fold<Object?>((f) => f, (e) => e);

    test('queda en curso, guardada, y no cuenta como recuperada', () async {
      await notificador().esperarLectura();

      final r = await empezar();

      expect(r, isNotNull);
      expect(estado().entrevista, isNotNull);
      expect(estado().recuperada, isFalse);
      expect(await montaje.almacen.leer('col-1'), estado().entrevista);
    });

    test('dos toques seguidos esperan el mismo guardado: una sola hora de inicio', () async {
      await notificador().esperarLectura();

      final a = notificador().empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
      final b = notificador().empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
      final resultados = await Future.wait([a, b]);

      expect(resultados[0], resultados[1]);
      expect(montaje.almacen.guardadas.values.single, estado().entrevista);
      expect(estado().entrevista!.ids.visita, 'id-1');
    });

    test('si falla al guardar, no queda en curso y se puede volver a intentar', () async {
      await notificador().esperarLectura();
      montaje.rota.fallaAlGuardar = true;

      final r = await notificador().empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
      expect(r.isLeft(), isTrue);
      expect(estado().entrevista, isNull);

      montaje.rota.fallaAlGuardar = false;
      final otra = await notificador().empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
      expect(otra.isRight(), isTrue);
      expect(estado().entrevista, isNotNull);
    });

    test('empezar antes de que termine la lectura no pierde la entrevista', () async {
      final r = await notificador().empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
      expect(r.isRight(), isTrue);

      final e = await notificador().esperarLectura();
      expect(e.entrevista, isNotNull);
      expect(e.recuperada, isFalse);
    });
  });

  group('finalizar', () {
    final entrada = DateTime(2026, 10, 23, 14, 23);
    final salida = DateTime(2026, 10, 23, 14, 41);

    Future<void> conEntrevista() async {
      await montaje.almacen.guardar(entrevistaDePrueba());
      await notificador().esperarLectura();
    }

    test('guarda la visita y la entrevista deja de estar en curso (también la nota)', () async {
      await conEntrevista();
      notificador().escribirNota('perro suelto');

      final r = await notificador().finalizar(entrada: entrada, salida: salida);

      expect(r!.isRight(), isTrue);
      expect(estado().entrevista, isNull);
      expect(estado().notaBorrador, isEmpty);
      expect(montaje.agenda.recibidas.single.nota!.texto, 'perro suelto');
      expect(montaje.almacen.guardadas, isEmpty);
    });

    test('dos toques seguidos guardan una sola visita', () async {
      await conEntrevista();
      montaje.agenda.compuerta = Completer<void>();

      final a = notificador().finalizar(entrada: entrada, salida: salida);
      final b = notificador().finalizar(entrada: entrada, salida: salida);
      montaje.agenda.compuerta!.complete();
      final resultados = await Future.wait([a, b]);

      expect(resultados.where((r) => r == null), hasLength(1));
      expect(montaje.agenda.recibidas, hasLength(1));
    });

    test(
      'si falla, la entrevista sigue en curso con su nota y el guardado vuelve a estar libre',
      () async {
        await conEntrevista();
        notificador().escribirNota('perro suelto');
        montaje.agenda.falla = const FailureInesperado();

        final r = await notificador().finalizar(entrada: entrada, salida: salida);
        expect(r!.isLeft(), isTrue);
        expect(estado().entrevista, isNotNull);
        expect(estado().notaBorrador, 'perro suelto');

        montaje.agenda.falla = null;
        final otra = await notificador().finalizar(entrada: entrada, salida: salida);
        expect(otra!.isRight(), isTrue);
      },
    );

    test('con las horas mal puestas dice qué corregir y no guarda nada', () async {
      await conEntrevista();

      final r = await notificador().finalizar(entrada: salida, salida: entrada);

      expect(r!.swap().getOrElse(() => throw StateError('x')), isA<FailureValidacion>());
      expect(montaje.agenda.recibidas, isEmpty);
      expect(estado().entrevista, isNotNull);
    });

    test('sin entrevista en curso devuelve el aviso, no lanza', () async {
      await notificador().esperarLectura();

      final r = await notificador().finalizar(entrada: entrada, salida: salida);

      expect(r!.swap().getOrElse(() => throw StateError('x')), sinEntrevistaEnCurso);
    });

    test('volver a empezar después de terminar es una entrevista nueva, con otra hora', () async {
      await conEntrevista();
      await notificador().finalizar(entrada: entrada, salida: salida);
      montaje.reloj = () => DateTime(2026, 10, 23, 16);

      final r = await notificador().empezar(espacioId: 'esp-2', espacioPersonaId: 'ep-2');

      final nueva = r.getOrElse(() => throw StateError('x'));
      expect(nueva.inicio, DateTime(2026, 10, 23, 16).toUtc());
      expect(nueva.ids.visita, isNot('vis-1'));
    });
  });

  group('la visita anterior (R·07)', () {
    test('devuelve la hora de la última visita', () async {
      montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 10);

      expect(await notificador().horaDeLaVisitaAnterior(), DateTime(2026, 10, 23, 14, 10));
    });

    test(
      'sin visita anterior o con la DB sin poder leerse, devuelve null: nunca inventa',
      () async {
        expect(await notificador().horaDeLaVisitaAnterior(), isNull);

        montaje.ultimaVisita
          ..fecha = DateTime(2026, 10, 23, 14, 10)
          ..falla = true;
        expect(await notificador().horaDeLaVisitaAnterior(), isNull);
      },
    );
  });

  test('la nota se guarda en el estado mientras dura la entrevista', () async {
    await notificador().esperarLectura();

    notificador().escribirNota('hola');
    expect(estado().notaBorrador, 'hola');
  });

  group('la nota cifrada en el teléfono («Nota entrev.», 25/10)', () {
    Future<void> asentar() => Future<void>.delayed(Duration.zero);

    Future<EntrevistaEnCurso> empezada() async {
      await notificador().esperarLectura();
      final r = await notificador().empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
      return r.getOrElse(() => throw StateError('falló'));
    }

    test('lo que escribe queda en la base con los ids de la visita y de la nota', () async {
      final entrevista = await empezada();

      notificador().escribirNota('perro suelto, tocar timbre');
      await asentar();

      expect(montaje.borrador.textos[entrevista.ids.nota], 'perro suelto, tocar timbre');
    });

    test('al cerrar la app y volver, la nota sigue ahí junto a la entrevista', () async {
      await montaje.almacen.guardar(entrevistaDePrueba());
      montaje.borrador.textos['not-1'] = 'perro suelto, tocar timbre';

      final e = await notificador().esperarLectura();

      expect(e.recuperada, isTrue);
      expect(e.notaBorrador, 'perro suelto, tocar timbre');
    });

    test('lo que escribió antes de que termine la lectura no se pisa con lo guardado', () async {
      await montaje.almacen.guardar(entrevistaDePrueba());
      montaje.borrador.textos['not-1'] = 'vieja';

      final lectura = notificador().esperarLectura();
      notificador().escribirNota('nueva');
      final e = await lectura;

      expect(e.notaBorrador, 'nueva');
    });

    test('si la nota no se puede leer, la entrevista vuelve igual y sin nota', () async {
      await montaje.almacen.guardar(entrevistaDePrueba());
      montaje.borrador.fallaAlLeer = true;

      final e = await notificador().esperarLectura();

      expect(e.entrevista, isNotNull);
      expect(e.notaBorrador, isEmpty);
    });

    test('escribir y borrar todo no deja una nota vacía en la base', () async {
      final entrevista = await empezada();

      notificador().escribirNota('hola');
      await asentar();
      notificador().escribirNota('');
      await asentar();

      expect(montaje.borrador.textos.containsKey(entrevista.ids.nota), isFalse);
    });

    test(
      'teclear seguido guarda en orden y la última queda: una vieja nunca pisa a una nueva',
      () async {
        final entrevista = await empezada();
        montaje.borrador.compuerta = Completer<void>();

        notificador()
          ..escribirNota('a')
          ..escribirNota('ab')
          ..escribirNota('abc');
        await asentar();
        expect(montaje.borrador.escrituras, isEmpty, reason: 'la primera escritura está en vuelo');

        montaje.borrador.compuerta!.complete();
        await asentar();
        await asentar();

        expect(montaje.borrador.escrituras.last, 'abc');
        expect(montaje.borrador.textos[entrevista.ids.nota], 'abc');
      },
    );

    test(
      'si la base falla, la nota sigue en memoria y se vuelve a guardar con lo próximo',
      () async {
        final entrevista = await empezada();
        montaje.borrador.fallaAlGuardar = true;

        notificador().escribirNota('hola');
        await asentar();
        expect(estado().notaBorrador, 'hola');
        expect(montaje.borrador.textos, isEmpty);

        montaje.borrador.fallaAlGuardar = false;
        notificador().escribirNota('hola mundo');
        await asentar();
        expect(montaje.borrador.textos[entrevista.ids.nota], 'hola mundo');
      },
    );

    test('sin entrevista en curso la nota queda solo en memoria (R·07)', () async {
      await notificador().esperarLectura();

      notificador().escribirNota('hola');
      await asentar();

      expect(montaje.borrador.escrituras, isEmpty);
    });

    test('al guardar la visita, su nota es el texto final y la entrevista se suelta', () async {
      final entrevista = await empezada();
      notificador().escribirNota('perro suelto');
      // Sin esperar la escritura: el guardado la espera antes de seguir.
      final r = await notificador().finalizar(
        entrada: DateTime(2026, 10, 23, 14, 23),
        salida: DateTime(2026, 10, 23, 14, 41),
      );

      expect(r!.isRight(), isTrue);
      expect(montaje.agenda.recibidas.single.nota!.id, entrevista.ids.nota);
      expect(montaje.agenda.recibidas.single.nota!.texto, 'perro suelto');
      expect(estado().notaBorrador, isEmpty);
      await asentar();
      // Nada más se escribió después de guardar la visita.
      expect(montaje.borrador.escrituras, ['perro suelto']);
    });

    test('lo que se escribe mientras se guarda la visita no pisa su nota', () async {
      await empezada();
      montaje.agenda.compuerta = Completer<void>();
      notificador().escribirNota('final');

      final guardando = notificador().finalizar(
        entrada: DateTime(2026, 10, 23, 14, 23),
        salida: DateTime(2026, 10, 23, 14, 41),
      );
      await asentar();
      notificador().escribirNota('tarde');
      await asentar();
      montaje.agenda.compuerta!.complete();
      await guardando;

      expect(montaje.agenda.recibidas.single.nota!.texto, 'final');
      expect(montaje.borrador.escrituras, ['final']);
    });

    test('si guardar la visita falla, la nota sigue en el borrador y en el estado', () async {
      final entrevista = await empezada();
      notificador().escribirNota('perro suelto');
      montaje.agenda.falla = const FailureInesperado();

      final r = await notificador().finalizar(
        entrada: DateTime(2026, 10, 23, 14, 23),
        salida: DateTime(2026, 10, 23, 14, 41),
      );

      expect(r!.isLeft(), isTrue);
      expect(estado().notaBorrador, 'perro suelto');
      expect(montaje.borrador.textos[entrevista.ids.nota], 'perro suelto');
      expect(estado().hayEntrevista, isTrue);
    });
  });

  group('«Sin salida» (25/10)', () {
    Future<void> empezada() async {
      await notificador().esperarLectura();
      await notificador().empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
    }

    test('la persona dada de baja: se guarda sin persona y la entrevista se suelta', () async {
      await empezada();
      montaje.destino.destino = const DestinoDeEntrevista(espacioId: 'esp-1');

      final r = await notificador().finalizar(
        entrada: DateTime(2026, 10, 23, 14, 23),
        salida: DateTime(2026, 10, 23, 14, 41),
      );

      expect(r!.isRight(), isTrue);
      expect(montaje.agenda.recibidas.single.visita.espacioPersonaId, isNull);
      expect(estado().hayEntrevista, isFalse);
    });

    test('sin casa donde guardarla: devuelve el aviso y la entrevista deja de estar en curso '
        '(el cierre de la jornada no queda trabado)', () async {
      await empezada();
      montaje.destino.sinDestino = true;
      notificador().escribirNota('perro suelto');

      final r = await notificador().finalizar(
        entrada: DateTime(2026, 10, 23, 14, 23),
        salida: DateTime(2026, 10, 23, 14, 41),
      );

      expect(r, const Left<Failure, Object?>(entrevistaSinLugar));
      expect(estado().hayEntrevista, isFalse);
      expect(estado().notaBorrador, isEmpty);
      expect(montaje.agenda.recibidas, isEmpty);
      expect(montaje.borrador.textos, isEmpty);
    });
  });

  group('«Sí, registrar la venta» (#428)', () {
    Future<void> enCurso() async {
      await notificador().esperarLectura();
      await notificador().empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
    }

    Future<VentaDeLaEntrevista> preparar() async {
      final r = await notificador().prepararVenta(
        entrada: inicioEntrevista,
        salida: ahoraEntrevista,
      );
      return r.getOrElse(() => throw StateError('debía poder prepararse'));
    }

    test('preparar no guarda la visita ni suelta la entrevista, que sigue en curso', () async {
      await enCurso();

      final venta = await preparar();

      expect(venta.visita.resultado, TipoResultadoVisita.venta);
      expect(montaje.agenda.recibidas, isEmpty);
      expect(estado().entrevista, isNotNull);
      expect(montaje.almacen.guardadas, hasLength(1));
    });

    test('preparar lleva la nota que está escrita', () async {
      await enCurso();
      notificador().escribirNota('volver con la esposa');

      final venta = await preparar();

      expect(venta.visita.nota, 'volver con la esposa');
    });

    test('sin entrevista en curso no hay venta que preparar', () async {
      await notificador().esperarLectura();

      final r = await notificador().prepararVenta(
        entrada: inicioEntrevista,
        salida: ahoraEntrevista,
      );

      expect(r.swap().getOrElse(() => throw StateError('debía fallar')), sinEntrevistaEnCurso);
    });

    test('si la casa ya no está, devuelve el aviso y la entrevista sigue en curso', () async {
      await enCurso();
      montaje.destino.sinDestino = true;

      final r = await notificador().prepararVenta(
        entrada: inicioEntrevista,
        salida: ahoraEntrevista,
      );

      expect(r.swap().getOrElse(() => throw StateError('debía fallar')), ventaSinLugar);
      expect(estado().entrevista, isNotNull);
    });

    test('guardar la visita de la venta la registra como VENTA', () async {
      await enCurso();
      final venta = await preparar();

      await notificador().guardarVisitaDeLaVenta(venta);

      expect(montaje.agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.venta);
      expect(estado().entrevista, isNotNull, reason: 'recién se suelta con la venta guardada');
    });

    test('soltar tras la venta deja el estado sin entrevista ni nota y borra el almacén', () async {
      await enCurso();
      notificador().escribirNota('una nota');
      final venta = await preparar();

      final r = await notificador().soltarTrasLaVenta(venta);

      expect(r.isRight(), isTrue);
      expect(estado().entrevista, isNull);
      expect(estado().notaBorrador, '');
      expect(estado().recuperada, isFalse);
      expect(montaje.almacen.guardadas, isEmpty);
    });

    test(
      'si el almacén falla al soltar, devuelve la falla y la entrevista sigue en curso',
      () async {
        await enCurso();
        final venta = await preparar();
        montaje.rota.fallaAlBorrar = true;

        final r = await notificador().soltarTrasLaVenta(venta);

        expect(r.isLeft(), isTrue);
        expect(estado().entrevista, isNotNull);
      },
    );
  });
}
