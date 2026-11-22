// QA de «la cuota que toca» al día sin recargar (HU-COB-005, #591, PR #634): casos límite del caso de uso
// de la hoja de la casa que mezclan avisos de cambio, lecturas lentas, fallas y cancelaciones.
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
  @override
  Stream<NotaDelLugar?> observarMasReciente(String ubicacionId) => Stream.value(null);
}

/// Un saldo y una cuota que cambian como lo haría la base. Cada lectura toma su foto al EMPEZAR y recién
/// responde cuando se abre su compuerta (una lectura lenta que ve lo de antes del cobro).
final class _Cuentas implements SaldosDePersonas, CuotasDePersonas {
  Map<String, int> saldos = {};
  Map<String, DateTime> cuotas = {};
  Object? fallaSaldos;
  Object? fallaCuotas;
  final compuertas = <Completer<void>>[];
  var lecturasDeSaldos = 0;

  @override
  Future<Map<String, int>> saldosPendientes(Iterable<String> personaIds) async {
    lecturasDeSaldos++;
    final foto = {...saldos};
    final falla = fallaSaldos;
    if (compuertas.isNotEmpty) await compuertas.removeAt(0).future;
    if (falla != null) throw falla;
    return foto;
  }

  @override
  Future<Map<String, DateTime>> proximaCuotaDe(Iterable<String> personaIds) async {
    final foto = {...cuotas};
    final falla = fallaCuotas;
    if (falla != null) throw falla;
    return foto;
  }
}

void main() {
  late _Personas personas;
  late _Cuentas cuentas;
  late StreamController<void> cambios;
  late List<ContextoDeLaCasa> emitidos;
  late List<Object> errores;

  final espacio = espacioDePersonas(numeroDepto: null);
  final pedro = clienteDePersonas('p-1', 'Pedro', apellido: 'Gómez');
  final ana = clienteDePersonas('p-2', 'Ana', apellido: 'Gómez', minutos: 1);
  final sabado = DateTime(2026, 10, 24, 12, 30);
  final lunes = DateTime(2026, 10, 26, 12, 30);

  setUp(() {
    personas = _Personas();
    cuentas = _Cuentas();
    cambios = StreamController<void>.broadcast();
    emitidos = [];
    errores = [];
  });

  Future<StreamSubscription<ContextoDeLaCasa>> abrir({
    List<PersonaDelEspacio>? lista,
    bool llegan = true,
  }) async {
    final caso = ObservarContextoDeLaCasaUseCase(
      espacios: _Espacios(espacio),
      personas: personas,
      saldos: cuentas,
      notas: _Notas(),
      cuotas: cuentas,
      cambios: () => cambios.stream,
    );
    final suscripcion = caso(
      ubicacionId: 'ub-1',
      tipo: TipoUbicacion.casa,
    ).listen(emitidos.add, onError: errores.add);
    addTearDown(suscripcion.cancel);
    await pumpEventQueue();
    if (llegan) {
      personas.controlador.add(lista ?? [pedro, ana]);
      await pumpEventQueue();
    }
    return suscripcion;
  }

  group('casos límite del refresco sin recargar', () {
    test('un cobro que llega mientras se hace la PRIMERA lectura no se pierde', () async {
      cuentas.saldos = {'p-1': 120000};
      cuentas.cuotas = {'p-1': sabado};
      // La primera lectura toma la foto con $ 1.200 y se queda esperando.
      cuentas.compuertas.add(Completer<void>());
      final compuerta = cuentas.compuertas.first;
      await abrir();

      // Mientras tanto se cobra todo y la base avisa.
      cuentas
        ..saldos = {}
        ..cuotas = {};
      cambios.add(null);
      await pumpEventQueue();
      compuerta.complete();
      await pumpEventQueue();

      expect(errores, isEmpty);
      expect(emitidos.last.saldosCentavos, isEmpty, reason: 'quedó el «Debe» de antes del cobro');
      expect(emitidos.last.proximaCuotaDe, isEmpty);
    });

    test('una ráfaga de 25 avisos deja el último valor y emite una sola vez más', () async {
      cuentas.saldos = {'p-1': 120000};
      cuentas.cuotas = {'p-1': sabado};
      await abrir();
      final antes = emitidos.length;

      cuentas
        ..saldos = {'p-1': 70000}
        ..cuotas = {'p-1': lunes};
      for (var i = 0; i < 25; i++) {
        cambios.add(null);
      }
      await pumpEventQueue();

      expect(errores, isEmpty);
      expect(emitidos.length, antes + 1);
      expect(emitidos.last.saldoDe('p-1'), 70000);
      expect(emitidos.last.cuotaQueTocaDe('p-1'), lunes);
    });

    test('avisos que no mueven nada no emiten (la hoja no parpadea)', () async {
      cuentas.saldos = {'p-1': 120000};
      cuentas.cuotas = {'p-1': sabado};
      await abrir();
      final antes = emitidos.length;

      for (var i = 0; i < 5; i++) {
        cambios.add(null);
        await pumpEventQueue();
      }

      expect(emitidos.length, antes);
    });

    test(
      'un aviso antes de que lleguen las personas no rompe nada y después sale con cuota',
      () async {
        cuentas.saldos = {'p-1': 120000};
        cuentas.cuotas = {'p-1': sabado};
        await abrir(llegan: false);

        cambios.add(null);
        await pumpEventQueue();
        expect(emitidos, isEmpty);

        personas.controlador.add([pedro, ana]);
        await pumpEventQueue();

        expect(errores, isEmpty);
        expect(emitidos.last.cuotaQueTocaDe('p-1'), sabado);
      },
    );

    test(
      'la cuota que no se puede leer deja el saldo y se recupera con el aviso siguiente',
      () async {
        cuentas.saldos = {'p-1': 120000};
        cuentas.cuotas = {'p-1': sabado};
        await abrir();
        expect(emitidos.last.cuotaQueTocaDe('p-1'), sabado);

        cuentas.fallaCuotas = StateError('la agenda no responde');
        cambios.add(null);
        await pumpEventQueue();
        expect(errores, isEmpty);
        expect(emitidos.last.saldoDe('p-1'), 120000, reason: 'el saldo no depende de la cuota');

        cuentas.fallaCuotas = null;
        cambios.add(null);
        await pumpEventQueue();
        expect(emitidos.last.cuotaQueTocaDe('p-1'), sabado);
      },
    );

    test('llega una persona nueva con plan: entra con su cuota, la de antes no cambia', () async {
      cuentas.saldos = {'p-1': 120000};
      cuentas.cuotas = {'p-1': sabado};
      await abrir(lista: [pedro]);

      cuentas
        ..saldos = {'p-1': 120000, 'p-2': 50000}
        ..cuotas = {'p-1': sabado, 'p-2': lunes};
      personas.controlador.add([pedro, ana]);
      await pumpEventQueue();

      expect(emitidos.last.cuotaQueTocaDe('p-1'), sabado);
      expect(emitidos.last.cuotaQueTocaDe('p-2'), lunes);
    });

    test('cancelar con una relectura en vuelo no emite ni lanza después', () async {
      cuentas.saldos = {'p-1': 120000};
      cuentas.cuotas = {'p-1': sabado};
      final suscripcion = await abrir();
      final antes = emitidos.length;

      cuentas.compuertas.add(Completer<void>());
      final compuerta = cuentas.compuertas.first;
      cuentas.saldos = {'p-1': 70000};
      cambios.add(null);
      await pumpEventQueue();
      await suscripcion.cancel();
      compuerta.complete();
      await pumpEventQueue();

      expect(emitidos.length, antes);
      expect(errores, isEmpty);
    });

    test('dos relecturas lentas que terminan al revés: queda la de la foto más nueva', () async {
      cuentas.saldos = {'p-1': 120000};
      cuentas.cuotas = {'p-1': sabado};
      await abrir();

      final lenta = Completer<void>();
      final rapida = Completer<void>();
      cuentas.compuertas.addAll([lenta, rapida]);
      cuentas.saldos = {'p-1': 100000};
      cambios.add(null); // foto $ 1.000, lenta
      await pumpEventQueue();
      cuentas.saldos = {'p-1': 70000};
      cambios.add(null); // foto $ 700, rápida
      await pumpEventQueue();

      rapida.complete();
      await pumpEventQueue();
      lenta.complete();
      await pumpEventQueue();

      expect(emitidos.last.saldoDe('p-1'), 70000);
    });
  });
}
