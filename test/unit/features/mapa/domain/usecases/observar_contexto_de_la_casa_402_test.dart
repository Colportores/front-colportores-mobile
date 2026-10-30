// La hoja de la casa al día después de cada cobro (vista 39, HU-COB-005, #402): el saldo y la cuota que
// toca de cada persona se vuelven a leer cuando algo de lo que se debe cambia, sin recargar la hoja.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuotas_de_personas.dart';
import 'package:colportores_mobile/features/mapa/domain/services/lector_notas_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/services/saldos_de_personas.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/observar_contexto_de_la_casa_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/persona_falsos.dart';

final class _Espacios implements EspacioRepository {
  _Espacios(this.espacio);

  final Espacio espacio;

  @override
  Future<Either<Failure, List<Espacio>>> listar(
    String ubicacionId, {
    bool incluirBajas = false,
  }) async => Right([espacio]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Personas implements PersonaRepository {
  final controlador = StreamController<List<PersonaDelEspacio>>.broadcast();

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) => controlador.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Notas implements LectorNotasDelLugar {
  final controlador = StreamController<NotaDelLugar?>.broadcast();

  @override
  Stream<NotaDelLugar?> observarMasReciente(String ubicacionId) => controlador.stream;
}

/// Lo que se debe, que el test cambia como lo haría un cobro. [compuerta] frena la próxima lectura.
final class _Saldos implements SaldosDePersonas {
  Map<String, int> respuesta = const {};
  Object? falla;
  Completer<void>? compuerta;
  var lecturas = 0;

  @override
  Future<Map<String, int>> saldosPendientes(Iterable<String> personaIds) async {
    lecturas++;
    final espera = compuerta;
    final devuelve = {...respuesta};
    if (espera != null) await espera.future;
    final error = falla;
    if (error != null) throw error;
    return devuelve;
  }
}

final class _Cuotas implements CuotasDePersonas {
  Map<String, DateTime> respuesta = const {};
  Object? falla;
  final pedidos = <List<String>>[];

  @override
  Future<Map<String, DateTime>> proximaCuotaDe(Iterable<String> personaIds) async {
    pedidos.add(personaIds.toList());
    final error = falla;
    if (error != null) throw error;
    return respuesta;
  }
}

void main() {
  late _Personas personas;
  late _Notas notas;
  late _Saldos saldos;
  late _Cuotas cuotas;
  late StreamController<void> cambios;
  late List<ContextoDeLaCasa> emitidos;
  late List<Object> errores;

  final espacio = espacioDePersonas(numeroDepto: null);
  final pedro = clienteDePersonas('p-1', 'Pedro', apellido: 'Gómez');
  final ana = clienteDePersonas('p-2', 'Ana', apellido: 'Gómez', minutos: 1);
  final sabado = DateTime(2026, 10, 26);

  setUp(() {
    personas = _Personas();
    notas = _Notas();
    saldos = _Saldos();
    cuotas = _Cuotas();
    cambios = StreamController<void>.broadcast();
    emitidos = [];
    errores = [];
  });

  /// Empieza a escuchar la casa y deja llegar las personas y la nota.
  Future<void> abrir({List<PersonaDelEspacio>? lista}) async {
    final caso = ObservarContextoDeLaCasaUseCase(
      espacios: _Espacios(espacio),
      personas: personas,
      saldos: saldos,
      notas: notas,
      cuotas: cuotas,
      cambios: () => cambios.stream,
    );
    final suscripcion = caso(
      ubicacionId: 'ub-1',
      tipo: TipoUbicacion.casa,
    ).listen(emitidos.add, onError: errores.add);
    addTearDown(suscripcion.cancel);
    await pumpEventQueue();
    personas.controlador.add(lista ?? [pedro, ana]);
    notas.controlador.add(null);
    await pumpEventQueue();
  }

  /// Un cobro: cambia lo que se debe y la base avisa.
  Future<void> cobrar(Map<String, int> nuevoSaldo) async {
    saldos.respuesta = nuevoSaldo;
    cambios.add(null);
    await pumpEventQueue();
  }

  group('la cuota que toca', () {
    test('sale por persona, junto con el saldo, en la misma lectura', () async {
      saldos.respuesta = {'p-1': 120000};
      cuotas.respuesta = {'p-1': sabado};

      await abrir();

      expect(emitidos, hasLength(1));
      expect(emitidos.single.proximaCuotaDe, {'p-1': sabado});
      expect(emitidos.single.cuotaQueTocaDe('p-1'), sabado);
      expect(cuotas.pedidos, [
        ['p-1', 'p-2'],
      ]);
    });

    test('quien no debe nada no muestra cuota aunque el plan la traiga', () async {
      saldos.respuesta = {'p-1': 120000};
      cuotas.respuesta = {'p-1': sabado, 'p-2': sabado};

      await abrir();

      expect(emitidos.single.cuotaQueTocaDe('p-2'), isNull);
      expect(emitidos.single.cuotaQueTocaDe('p-1'), sabado);
    });

    test('si no se pueden leer las cuotas, la fila queda con el saldo y sin cuota', () async {
      saldos.respuesta = {'p-1': 120000};
      cuotas.falla = StateError('la agenda no responde');

      await abrir();

      expect(errores, isEmpty);
      expect(emitidos.single.saldoDe('p-1'), 120000);
      expect(emitidos.single.proximaCuotaDe, isEmpty);
    });

    test('sin fuente de cuotas (todavía no hay planes) nadie tiene cuota', () async {
      saldos.respuesta = {'p-1': 120000};
      final caso = ObservarContextoDeLaCasaUseCase(
        espacios: _Espacios(espacio),
        personas: personas,
        saldos: saldos,
        notas: notas,
      );
      final llegados = <ContextoDeLaCasa>[];
      final suscripcion = caso(ubicacionId: 'ub-1', tipo: TipoUbicacion.casa).listen(llegados.add);
      addTearDown(suscripcion.cancel);
      await pumpEventQueue();
      personas.controlador.add([pedro]);
      notas.controlador.add(null);
      await pumpEventQueue();

      expect(llegados.single.proximaCuotaDe, isEmpty);
    });
  });

  group('al día sin recargar (HU-COB-005)', () {
    test('venta de 1.500 con un cobro de 500: otro de 300 deja el saldo en 700', () async {
      saldos.respuesta = {'p-1': 100000};
      await abrir();
      expect(emitidos.last.saldoDe('p-1'), 100000);

      await cobrar({'p-1': 70000});

      expect(emitidos, hasLength(2));
      expect(emitidos.last.saldoDe('p-1'), 70000);
      expect(errores, isEmpty);
    });

    test('el último cobro: sin saldo la persona deja de deber y la cuota se va con él', () async {
      saldos.respuesta = {'p-1': 30000};
      cuotas.respuesta = {'p-1': sabado};
      await abrir();
      expect(emitidos.last.cuotaQueTocaDe('p-1'), sabado);

      saldos.respuesta = const {};
      cuotas.respuesta = const {};
      cambios.add(null);
      await pumpEventQueue();

      expect(emitidos.last.saldoDe('p-1'), isNull);
      expect(emitidos.last.cuotaQueTocaDe('p-1'), isNull);
    });

    test('el cobro de una cuota mueve la cuota que toca a la siguiente', () async {
      saldos.respuesta = {'p-1': 120000};
      cuotas.respuesta = {'p-1': sabado};
      await abrir();

      cuotas.respuesta = {'p-1': DateTime(2026, 11, 2)};
      cambios.add(null);
      await pumpEventQueue();

      expect(emitidos.last.cuotaQueTocaDe('p-1'), DateTime(2026, 11, 2));
      expect(emitidos.last.saldoDe('p-1'), 120000);
    });

    test(
      'un aviso que no cambia nada no vuelve a emitir (el aviso llega también al abrir)',
      () async {
        saldos.respuesta = {'p-1': 120000};
        await abrir();

        cambios.add(null);
        await pumpEventQueue();
        cambios.add(null);
        await pumpEventQueue();

        expect(emitidos, hasLength(1));
      },
    );

    test('dos cobros seguidos: queda el saldo del último, sin pisar ni perder ninguno', () async {
      saldos.respuesta = {'p-1': 100000};
      await abrir();
      final compuerta = Completer<void>();
      saldos.compuerta = compuerta;

      // El primer aviso se queda leyendo; antes de que termine llega el del segundo cobro.
      saldos.respuesta = {'p-1': 70000};
      cambios.add(null);
      await pumpEventQueue();
      saldos.respuesta = {'p-1': 40000};
      saldos.compuerta = null;
      cambios.add(null);
      await pumpEventQueue();
      compuerta.complete();
      await pumpEventQueue();

      expect(emitidos.last.saldoDe('p-1'), 40000);
      expect(emitidos.map((c) => c.saldoDe('p-1')).toSet().difference({100000, 40000}), isEmpty);
    });

    test(
      'un aviso antes de que lleguen las personas no lee nada: la lista ya lee lo último',
      () async {
        saldos.respuesta = {'p-1': 100000};
        final caso = ObservarContextoDeLaCasaUseCase(
          espacios: _Espacios(espacio),
          personas: personas,
          saldos: saldos,
          notas: notas,
          cambios: () => cambios.stream,
        );
        final suscripcion = caso(
          ubicacionId: 'ub-1',
          tipo: TipoUbicacion.casa,
        ).listen(emitidos.add);
        addTearDown(suscripcion.cancel);
        await pumpEventQueue();

        cambios.add(null);
        await pumpEventQueue();
        expect(saldos.lecturas, 0);

        personas.controlador.add([pedro]);
        notas.controlador.add(null);
        await pumpEventQueue();
        expect(emitidos.single.saldoDe('p-1'), 100000);
      },
    );

    test(
      'un cobro que llega mientras se lee la lista de personas se vuelve a leer al final',
      () async {
        saldos.respuesta = {'p-1': 100000};
        final compuerta = Completer<void>();
        saldos.compuerta = compuerta;
        final caso = ObservarContextoDeLaCasaUseCase(
          espacios: _Espacios(espacio),
          personas: personas,
          saldos: saldos,
          notas: notas,
          cambios: () => cambios.stream,
        );
        final suscripcion = caso(
          ubicacionId: 'ub-1',
          tipo: TipoUbicacion.casa,
        ).listen(emitidos.add);
        addTearDown(suscripcion.cancel);
        await pumpEventQueue();
        personas.controlador.add([pedro]);
        notas.controlador.add(null);
        await pumpEventQueue();

        // La lectura de la lista ya tomó 1.000; mientras espera, se cobran 300 y la base avisa.
        saldos.respuesta = {'p-1': 70000};
        cambios.add(null);
        saldos.compuerta = null;
        compuerta.complete();
        await pumpEventQueue();

        expect(emitidos.last.saldoDe('p-1'), 70000);
      },
    );

    test(
      'si al volver a leer falla, la persona queda sin saldo (no se afirma lo que no se sabe)',
      () async {
        saldos.respuesta = {'p-1': 100000};
        await abrir();

        saldos.falla = StateError('la base no responde');
        cambios.add(null);
        await pumpEventQueue();

        expect(errores, isEmpty);
        expect(emitidos.last.saldoDe('p-1'), isNull);
      },
    );

    test('un aviso que falla no rompe la hoja: queda con lo último que leyó', () async {
      saldos.respuesta = {'p-1': 100000};
      await abrir();

      cambios.addError(StateError('el aviso se cayó'));
      await pumpEventQueue();

      expect(errores, isEmpty);
      expect(emitidos, hasLength(1));
    });

    test('cuando llega otra lista de personas lee de nuevo y no se mezcla con el aviso', () async {
      saldos.respuesta = {'p-1': 100000};
      await abrir(lista: [pedro]);

      saldos.respuesta = {'p-1': 70000, 'p-2': 5000};
      personas.controlador.add([pedro, ana]);
      await pumpEventQueue();

      expect(emitidos.last.personas, [pedro, ana]);
      expect(emitidos.last.saldoDe('p-1'), 70000);
      expect(emitidos.last.saldoDe('p-2'), 5000);
    });

    test('al cancelar se suelta también el aviso y no se lee más', () async {
      saldos.respuesta = {'p-1': 100000};
      final caso = ObservarContextoDeLaCasaUseCase(
        espacios: _Espacios(espacio),
        personas: personas,
        saldos: saldos,
        notas: notas,
        cambios: () => cambios.stream,
      );
      final suscripcion = caso(ubicacionId: 'ub-1', tipo: TipoUbicacion.casa).listen(emitidos.add);
      await pumpEventQueue();
      personas.controlador.add([pedro]);
      notas.controlador.add(null);
      await pumpEventQueue();
      final lecturasAntes = saldos.lecturas;
      await suscripcion.cancel();

      expect(cambios.hasListener, isFalse);
      cambios.add(null);
      await pumpEventQueue();
      expect(saldos.lecturas, lecturasAntes);
    });
  });
}
