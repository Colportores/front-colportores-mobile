// QA de #428 (R·08): la hoja de la casa que ya estaba abierta cuando se registró la venta tiene que
// mostrar lo que la persona debe ahora, sin cerrarla y volver a abrirla. Las dobles son las del test
// del caso de uso.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/lector_entrevistas_de_personas.dart';
import 'package:colportores_mobile/features/mapa/domain/services/lector_notas_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/services/saldos_de_personas.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/observar_contexto_de_la_casa_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/persona_falsos.dart';

final class _Espacios implements EspacioRepository {
  _Espacios(this.respuesta);

  Either<Failure, List<Espacio>> respuesta;
  final consultadas = <String>[];

  @override
  Future<Either<Failure, List<Espacio>>> listar(
    String ubicacionId, {
    bool incluirBajas = false,
  }) async {
    consultadas.add(ubicacionId);
    return respuesta;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Personas implements PersonaRepository {
  final controladores = <String, StreamController<List<PersonaDelEspacio>>>{};

  StreamController<List<PersonaDelEspacio>> de(String espacioId) =>
      controladores.putIfAbsent(espacioId, StreamController<List<PersonaDelEspacio>>.broadcast);

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) => de(espacioId).stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Saldos implements SaldosDePersonas {
  Map<String, int> respuesta = const {};
  Object? falla;
  Completer<void>? compuerta;
  final pedidos = <List<String>>[];

  @override
  Future<Map<String, int>> saldosPendientes(Iterable<String> personaIds) async {
    pedidos.add(personaIds.toList());
    await compuerta?.future;
    final error = falla;
    if (error != null) throw error;
    return respuesta;
  }
}

final class _Entrevistas implements LectorEntrevistasDePersonas {
  Map<String, DateTime> respuesta = const {};
  Object? falla;
  final pedidos = <List<String>>[];

  @override
  Future<Map<String, DateTime>> ultimaEntrevistaDe(Iterable<String> vinculoIds) async {
    pedidos.add(vinculoIds.toList());
    final error = falla;
    if (error != null) throw error;
    return respuesta;
  }
}

final class _Notas implements LectorNotasDelLugar {
  final controlador = StreamController<NotaDelLugar?>.broadcast();
  final consultadas = <String>[];

  @override
  Stream<NotaDelLugar?> observarMasReciente(String ubicacionId) {
    consultadas.add(ubicacionId);
    return controlador.stream;
  }
}

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  test(
    'dado la hoja de la casa abierta, cuando se registra una venta con saldo, entonces el contexto '
    'vuelve a emitir con lo que debe (R·08)',
    () async {
      final espacio = espacioDePersonas(numeroDepto: null);
      final ana = clienteDePersonas('p-1', 'Ana', apellido: 'Rey');
      final espacios = _Espacios(Right([espacio]));
      final personas = _Personas();
      final saldos = _Saldos();
      final notas = _Notas();
      final caso = ObservarContextoDeLaCasaUseCase(
        espacios: espacios,
        personas: personas,
        saldos: saldos,
        notas: notas,
        entrevistas: _Entrevistas(),
      );
      final emitidos = <ContextoDeLaCasa>[];
      final suscripcion = caso(ubicacionId: 'ub-1', tipo: TipoUbicacion.casa).listen(emitidos.add);
      addTearDown(suscripcion.cancel);
      await pumpEventQueue();
      personas.de(espacio.id).add([ana]);
      notas.controlador.add(null);
      await pumpEventQueue();
      expect(emitidos.last.saldoDe('p-1'), anyOf(isNull, 0));

      // Se registra la venta: la persona pasa a deber $ 3.000. Las personas no cambiaron.
      saldos.respuesta = {'p-1': 300000};
      await pumpEventQueue(times: 50);

      expect(emitidos.last.saldoDe('p-1'), 300000);
    },
    // skip: QA #428: la hoja de la casa abierta no refresca «Debe $ X» tras la venta; lee los saldos solo al cambiar las personas (mismo hallazgo de #569)
    skip: !_verHallazgos,
  );
}
