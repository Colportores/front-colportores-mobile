// Lo que la hoja de la casa (vista 39, C·01) lee de una ubicación: su espacio, las personas, lo que
// deben y la nota más reciente.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
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

final class _Notas implements LectorNotasDelLugar {
  final controlador = StreamController<NotaDelLugar?>.broadcast();
  final consultadas = <String>[];

  @override
  Stream<NotaDelLugar?> observarMasReciente(String ubicacionId) {
    consultadas.add(ubicacionId);
    return controlador.stream;
  }
}

void main() {
  late _Espacios espacios;
  late _Personas personas;
  late _Saldos saldos;
  late _Notas notas;
  late ObservarContextoDeLaCasaUseCase caso;

  final espacio = espacioDePersonas(numeroDepto: null);
  final ana = clienteDePersonas('p-1', 'Ana', apellido: 'Rey');
  final nota = NotaDelLugar(
    id: 'n-1',
    texto: 'Perro suelto: tocar timbre y esperar.',
    creadaEl: DateTime.utc(2026, 10, 24),
  );

  setUp(() {
    espacios = _Espacios(Right([espacio]));
    personas = _Personas();
    saldos = _Saldos();
    notas = _Notas();
    caso = ObservarContextoDeLaCasaUseCase(
      espacios: espacios,
      personas: personas,
      saldos: saldos,
      notas: notas,
    );
  });

  /// Escucha, deja correr la lectura inicial y devuelve lo emitido y los errores.
  Future<(List<ContextoDeLaCasa>, List<Object>)> escuchar(TipoUbicacion tipo) async {
    final emitidos = <ContextoDeLaCasa>[];
    final errores = <Object>[];
    final suscripcion = caso(
      ubicacionId: 'ub-1',
      tipo: tipo,
    ).listen(emitidos.add, onError: errores.add);
    addTearDown(suscripcion.cancel);
    await pumpEventQueue();
    return (emitidos, errores);
  }

  test('una casa: emite el espacio, las personas, sus saldos y la nota cuando llegan', () async {
    saldos.respuesta = {'p-1': 120000};
    final (emitidos, errores) = await escuchar(TipoUbicacion.casa);
    expect(emitidos, isEmpty, reason: 'todavía faltan las personas y la nota');

    personas.de(espacio.id).add([ana]);
    await pumpEventQueue();
    expect(emitidos, isEmpty, reason: 'falta la nota (aunque sea null)');

    notas.controlador.add(nota);
    await pumpEventQueue();

    expect(errores, isEmpty);
    expect(emitidos, hasLength(1));
    expect(emitidos.single.espacioId, espacio.id);
    expect(emitidos.single.personas, [ana]);
    expect(emitidos.single.saldoDe('p-1'), 120000);
    expect(emitidos.single.nota, nota);
    expect(espacios.consultadas, ['ub-1']);
    expect(notas.consultadas, ['ub-1']);
    expect(saldos.pedidos, [
      ['p-1'],
    ]);
  });

  test('sin nota emite el contexto con nota null', () async {
    final (emitidos, _) = await escuchar(TipoUbicacion.negocio);
    personas.de(espacio.id).add([ana]);
    notas.controlador.add(null);
    await pumpEventQueue();

    expect(emitidos.single.nota, isNull);
    expect(emitidos.single.personaDestacada, ana);
  });

  test('un edificio no tiene espacio: sin personas y sin consultar los espacios', () async {
    final (emitidos, _) = await escuchar(TipoUbicacion.edificio);
    notas.controlador.add(nota);
    await pumpEventQueue();

    expect(emitidos.single.espacioId, isNull);
    expect(emitidos.single.personas, isEmpty);
    expect(emitidos.single.nota, nota);
    expect(espacios.consultadas, isEmpty);
    expect(personas.controladores, isEmpty);
  });

  test('una casa sin ningún espacio activo emite sin personas', () async {
    espacios.respuesta = const Right([]);
    final (emitidos, _) = await escuchar(TipoUbicacion.casa);
    notas.controlador.add(null);
    await pumpEventQueue();

    expect(emitidos.single.espacioId, isNull);
    expect(emitidos.single.personas, isEmpty);
  });

  test('un saldo que no se puede leer no frena nada: la persona queda sin saldo', () async {
    saldos.falla = StateError('sin ventas');
    final (emitidos, errores) = await escuchar(TipoUbicacion.casa);
    personas.de(espacio.id).add([ana]);
    notas.controlador.add(nota);
    await pumpEventQueue();

    expect(errores, isEmpty);
    expect(emitidos.single.personas, [ana]);
    expect(emitidos.single.saldosCentavos, isEmpty);
  });

  test('si cambian las personas o la nota vuelve a emitir con lo nuevo', () async {
    final beto = clienteDePersonas('p-2', 'Beto', apellido: 'Paz', minutos: 1);
    final (emitidos, _) = await escuchar(TipoUbicacion.casa);
    personas.de(espacio.id).add([ana]);
    notas.controlador.add(nota);
    await pumpEventQueue();

    personas.de(espacio.id).add([ana, beto]);
    await pumpEventQueue();
    final otra = NotaDelLugar(id: 'n-2', texto: 'Otra', creadaEl: DateTime.utc(2026, 10, 25));
    notas.controlador.add(otra);
    await pumpEventQueue();

    expect(emitidos.map((c) => c.personas.length), [1, 2, 2]);
    expect(emitidos.last.nota, otra);
  });

  test('la respuesta de saldos de una lista vieja no pisa a la lista nueva', () async {
    final beto = clienteDePersonas('p-2', 'Beto', apellido: 'Paz', minutos: 1);
    final compuerta = Completer<void>();
    saldos.compuerta = compuerta;
    final (emitidos, _) = await escuchar(TipoUbicacion.casa);
    notas.controlador.add(null);
    personas.de(espacio.id).add([ana]);
    await pumpEventQueue();

    saldos.compuerta = null;
    personas.de(espacio.id).add([ana, beto]);
    await pumpEventQueue();
    compuerta.complete();
    await pumpEventQueue();

    expect(emitidos, hasLength(1));
    expect(emitidos.single.personas, [ana, beto]);
  });

  test('si no se puede leer el espacio, el error sale por el Stream', () async {
    espacios.respuesta = const Left(FailureDatosLocalesIlegibles());
    final (emitidos, errores) = await escuchar(TipoUbicacion.casa);

    expect(emitidos, isEmpty);
    expect(errores, hasLength(1));
    expect(errores.single, isA<FailureDatosLocalesIlegibles>());
  });

  test('si falla la lectura de las personas o de la nota, sale por el Stream', () async {
    final (_, errores) = await escuchar(TipoUbicacion.casa);
    personas.de(espacio.id).addError(StateError('personas'));
    notas.controlador.addError(StateError('nota'));
    await pumpEventQueue();

    expect(errores, hasLength(2));
  });

  test('al cancelar se sueltan las suscripciones y no llega nada más', () async {
    final emitidos = <ContextoDeLaCasa>[];
    final suscripcion = caso(ubicacionId: 'ub-1', tipo: TipoUbicacion.casa).listen(emitidos.add);
    await pumpEventQueue();
    await suscripcion.cancel();

    personas.de(espacio.id).add([ana]);
    notas.controlador.add(nota);
    await pumpEventQueue();

    expect(emitidos, isEmpty);
    expect(personas.de(espacio.id).hasListener, isFalse);
    expect(notas.controlador.hasListener, isFalse);
  });
}
