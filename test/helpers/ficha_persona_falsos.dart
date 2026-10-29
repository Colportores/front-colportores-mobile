// Dobles de la ficha de una persona (HU-UBI-009) para los tests del caso de uso y de la pantalla.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ficha_persona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/marcador_de_telefono.dart';
import 'package:colportores_mobile/features/mapa/domain/services/movimientos_de_cuenta_de_persona.dart';
import 'package:dartz/dartz.dart';

import 'persona_falsos.dart';

/// María Pérez en el depto 3B de Mataojo 2044, con el teléfono del canvas.
Persona mariaDePrueba({String? telefono = '099123456', DateTime? baja}) {
  final base = clienteDePersonas('per-1', 'María', apellido: 'Pérez', telefono: telefono).persona;
  if (baja == null) return base;
  return Persona(
    id: base.id,
    nombre: base.nombre,
    apellido: base.apellido,
    telefono: base.telefono,
    auditoria: base.auditoria.copyWith(updatedAt: baja, deletedAt: baja),
  );
}

VisitaEnFicha visitaEnFicha(
  String id,
  DateTime fecha, {
  TipoResultadoVisita resultado = TipoResultadoVisita.entrevista,
}) => VisitaEnFicha(id: id, fecha: fecha, resultado: resultado);

/// [FichaPersonaRepository] en memoria: emite la lectura que se le pone con [poner]; cuenta las
/// llamadas registradas.
class FichaPersonaRepositorioFalso implements FichaPersonaRepository {
  FichaPersonaRepositorioFalso({Persona? persona, List<MovimientoDeFicha> historial = const []}) {
    if (persona != null) {
      _actual = LecturaDeFicha(persona: persona, historial: historial);
    }
  }

  LecturaDeFicha? _actual;
  var _hayActual = true;
  final _cambios = StreamController<LecturaDeFicha?>.broadcast();

  /// Si no es `null`, [registrarLlamada] responde con esta falla.
  Failure? fallaAlLlamar;

  /// Si no es `null`, [registrarLlamada] espera a que se complete.
  Completer<void>? compuertaLlamada;

  /// Las llamadas registradas: `(personaId, ahora)`.
  final llamadas = <({String personaId, DateTime ahora})>[];

  /// Cuántas veces se pidió observar.
  var observaciones = 0;

  /// Si no es `null`, [observar] falla con esto (una lectura que no sale).
  Object? errorAlObservar;

  /// La lectura que nunca llega (el estado «cargando»).
  void sinLectura() => _hayActual = false;

  void poner(LecturaDeFicha? lectura) {
    _actual = lectura;
    _hayActual = true;
    _cambios.add(lectura);
  }

  @override
  Stream<LecturaDeFicha?> observar(String personaId) async* {
    observaciones += 1;
    final error = errorAlObservar;
    if (error != null) throw error;
    if (_hayActual) yield _actual;
    yield* _cambios.stream;
  }

  @override
  Future<Either<Failure, Unit>> registrarLlamada({
    required String personaId,
    required DateTime ahora,
  }) async {
    llamadas.add((personaId: personaId, ahora: ahora));
    await compuertaLlamada?.future;
    final falla = fallaAlLlamar;
    return falla == null ? const Right(unit) : Left(falla);
  }
}

/// [MarcadorDeTelefono] que anota los números con los que lo llamaron.
class MarcadorFalso implements MarcadorDeTelefono {
  MarcadorFalso({this.abre = true, this.lanza});

  bool abre;
  Object? lanza;
  Completer<void>? compuerta;
  final numeros = <String>[];

  @override
  Future<bool> marcar(String numero) async {
    numeros.add(numero);
    await compuerta?.future;
    final error = lanza;
    if (error != null) throw error;
    return abre;
  }
}

/// [MovimientosDeCuentaDeLaPersona] con una lista que se puede cambiar.
class MovimientosFalsos implements MovimientosDeCuentaDeLaPersona {
  MovimientosFalsos([List<MovimientoDeFicha> inicial = const []]) : _lista = inicial;

  List<MovimientoDeFicha> _lista;
  final _cambios = StreamController<List<MovimientoDeFicha>>.broadcast();

  void poner(List<MovimientoDeFicha> lista) {
    _lista = lista;
    _cambios.add(lista);
  }

  @override
  Stream<List<MovimientoDeFicha>> observar(String personaId) async* {
    yield _lista;
    yield* _cambios.stream;
  }
}
