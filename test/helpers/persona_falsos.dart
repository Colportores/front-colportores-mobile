// Dobles de las personas de un espacio (HU-UBI-008) para los tests del caso de uso y de las pantallas.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_edicion_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:dartz/dartz.dart';

/// Un alta que le llegó al repositorio.
typedef AltaRecibida = ({Persona persona, EspacioPersona vinculo, NotaPersona? nota});

/// Una edición que le llegó al repositorio (HU-UBI-010).
typedef EdicionRecibida = ({
  String personaId,
  String nombre,
  String apellido,
  String? telefono,
  DateTime ahora,
});

/// [PersonaRepository] en memoria. Cada llamada a [registrar] toma el siguiente resultado de
/// [resultados] (si no queda, éxito con la persona recibida); si [compuerta] no es `null`, espera a que
/// se complete antes de contestar (para tener un guardado «en curso»). Las altas exitosas se agregan a
/// las personas que [observarDelEspacio] emite.
///
/// La edición (HU-UBI-010): [contextos] son las personas que [leerParaEditar] sabe leer (por `id`);
/// cada [modificar] toma el siguiente de [resultadosModificar] (`null` = éxito), espera a
/// [compuertaModificar] si hay una, anota la edición en [editadas] y, si salió bien, deja la persona
/// cambiada en [contextos] (así volver a abrirla la lee ya cambiada).
class PersonaRepositorioFalso implements PersonaRepository {
  PersonaRepositorioFalso({List<Failure?>? resultados, this.compuerta})
    : resultados = resultados ?? [];

  /// `null` = éxito; una [Failure] = ese fallo.
  final List<Failure?> resultados;
  Completer<void>? compuerta;

  final recibidas = <AltaRecibida>[];

  final contextos = <String, ContextoEdicionPersona>{};
  final resultadosModificar = <Failure?>[];
  Completer<void>? compuertaModificar;
  final editadas = <EdicionRecibida>[];

  /// Si no es `null`, [leerParaEditar] falla con esto (una vez, y se limpia).
  Failure? fallaAlLeerParaEditar;

  /// Si no es `null`, [leerParaEditar] espera a que se complete antes de contestar (el «cargando»).
  Completer<void>? compuertaLeer;
  var lecturasParaEditar = 0;

  final _guardadas = <PersonaDelEspacio>[];
  final _cambios = StreamController<List<PersonaDelEspacio>>.broadcast();

  @override
  Future<Either<Failure, Persona>> registrar({
    required Persona persona,
    required EspacioPersona vinculo,
    NotaPersona? nota,
  }) async {
    recibidas.add((persona: persona, vinculo: vinculo, nota: nota));
    await compuerta?.future;
    final resultado = resultados.isEmpty ? null : resultados.removeAt(0);
    if (resultado != null) return Left(resultado);
    if (!_guardadas.any((g) => g.persona.id == persona.id)) {
      _guardadas.add(PersonaDelEspacio(persona: persona, vinculo: vinculo));
      _cambios.add(List.unmodifiable(_guardadas));
    }
    return Right(persona);
  }

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) async* {
    yield List.unmodifiable(_guardadas.where((g) => g.vinculo.espacioId == espacioId));
    yield* _cambios.stream.map(
      (l) => List.unmodifiable(l.where((g) => g.vinculo.espacioId == espacioId)),
    );
  }

  /// Deja la lista inicial de personas, sin pasar por [registrar].
  void sembrar(List<PersonaDelEspacio> personas) => _guardadas.addAll(personas);

  @override
  Future<Either<Failure, ContextoEdicionPersona?>> leerParaEditar(String personaId) async {
    lecturasParaEditar += 1;
    await compuertaLeer?.future;
    final falla = fallaAlLeerParaEditar;
    if (falla != null) {
      fallaAlLeerParaEditar = null;
      return Left(falla);
    }
    return Right(contextos[personaId]);
  }

  @override
  Future<Either<Failure, ResultadoModificarPersona>> modificar({
    required String personaId,
    required String nombre,
    required String apellido,
    required String? telefono,
    required DateTime ahora,
  }) async {
    editadas.add((
      personaId: personaId,
      nombre: nombre,
      apellido: apellido,
      telefono: telefono,
      ahora: ahora,
    ));
    await compuertaModificar?.future;
    final resultado = resultadosModificar.isEmpty ? null : resultadosModificar.removeAt(0);
    if (resultado != null) return Left(resultado);
    final actual = contextos[personaId]!;
    final antes = actual.persona;
    if (antes.nombre == nombre && antes.apellido == apellido && antes.telefono == telefono) {
      return Right((persona: antes, huboCambios: false));
    }
    final despues = Persona(
      id: antes.id,
      nombre: nombre,
      apellido: apellido,
      telefono: telefono,
      notasGlobales: antes.notasGlobales,
      auditoria: antes.auditoria.copyWith(updatedAt: ahora),
    );
    contextos[personaId] = ContextoEdicionPersona(persona: despues, espacioId: actual.espacioId);
    return Right((persona: despues, huboCambios: true));
  }
}

/// [PersonaRepository] cuya lectura falla (error al leer los clientes).
final class PersonaRepositorioQueNoLee implements PersonaRepository {
  @override
  Future<Either<Failure, Persona>> registrar({
    required Persona persona,
    required EspacioPersona vinculo,
    NotaPersona? nota,
  }) async => Right(persona);

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) =>
      Stream.error(StateError('no se pudo leer'));

  @override
  Future<Either<Failure, ContextoEdicionPersona?>> leerParaEditar(String personaId) async =>
      const Left(FailureInesperado(causa: 'StateError'));

  @override
  Future<Either<Failure, ResultadoModificarPersona>> modificar({
    required String personaId,
    required String nombre,
    required String apellido,
    required String? telefono,
    required DateTime ahora,
  }) async => const Left(FailureInesperado(causa: 'StateError'));
}

/// [EspacioRepository] que solo sabe [buscar].
final class EspacioRepositorioParaPersonas implements EspacioRepository {
  EspacioRepositorioParaPersonas(this.contexto, {this.falla});

  final EspacioConUbicacion? contexto;
  final Failure? falla;

  @override
  Future<Either<Failure, EspacioConUbicacion?>> buscar(String id) async =>
      falla != null ? Left(falla!) : Right(contexto);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _t0 = DateTime.utc(2026, 10, 22, 12);

Auditoria auditoriaPersonas({DateTime? deletedAt}) =>
    Auditoria(createdAt: _t0, updatedAt: _t0, createdBy: 'col-1', deletedAt: deletedAt);

Ubicacion ubicacionDePersonas({
  TipoUbicacion tipo = TipoUbicacion.edificio,
  String calle = 'Mataojo',
  String numero = '2044',
  DateTime? deletedAt,
}) => Ubicacion(
  id: 'ub-1',
  tipo: tipo,
  calle: calle,
  numero: numero,
  lat: -34.89,
  lon: -56.16,
  ciudadId: 'mvd',
  auditoria: auditoriaPersonas(deletedAt: deletedAt),
);

Espacio espacioDePersonas({String? numeroDepto = '101', String? piso = '1', DateTime? deletedAt}) =>
    Espacio(
      id: 'esp-1',
      ubicacionId: 'ub-1',
      numeroDepto: numeroDepto,
      piso: piso,
      auditoria: auditoriaPersonas(deletedAt: deletedAt),
    );

PersonaDelEspacio clienteDePersonas(
  String id,
  String nombre, {
  String apellido = '',
  String? telefono,
  int minutos = 0,
  DateTime? creada,
}) {
  final momento = creada ?? _t0.add(Duration(minutes: minutos));
  final a = Auditoria(createdAt: momento, updatedAt: momento, createdBy: 'col-1');
  return PersonaDelEspacio(
    persona: Persona(id: id, nombre: nombre, apellido: apellido, telefono: telefono, auditoria: a),
    vinculo: EspacioPersona(id: 'ep-$id', espacioId: 'esp-1', personaId: id, auditoria: a),
  );
}

/// La persona que se edita en los tests de la vista 32C: «María Fernández», 098 765 432, activa.
ContextoEdicionPersona contextoDeEdicion({
  String id = 'per-1',
  String nombre = 'María',
  String apellido = 'Fernández',
  String? telefono = '098 765 432',
  String? espacioId = 'esp-1',
  CausaSoloLectura? causa,
  DateTime? bajaDesde,
  String? numeroDepto,
  String? direccion,
}) => ContextoEdicionPersona(
  persona: Persona(
    id: id,
    nombre: nombre,
    apellido: apellido,
    telefono: telefono,
    auditoria: auditoriaPersonas(deletedAt: bajaDesde),
  ),
  espacioId: espacioId,
  causa: causa,
  bajaDesde: bajaDesde,
  numeroDepto: numeroDepto,
  direccion: direccion,
);
