// Las personas a las que se les puede vender desde la pestaña Ventas (#546) para los tests: un armador
// de `PersonaParaVender` y un lector en memoria con el que el test controla cuándo y qué se emite.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/persona_para_vender.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/lector_de_personas_para_vender.dart';

final _instante = DateTime.utc(2026, 10, 1, 12);

Auditoria _auditoria() => Auditoria(createdAt: _instante, updatedAt: _instante, createdBy: 'col-1');

/// «María Fernández» en «Mataojo 2044 · Depto 3B» (edificio), o en una casa si [depto] es `null`.
///
/// [id] arma los ids de la persona (`per-<id>`), del vínculo (`ep-<id>`) y del espacio (`esp-<id>`).
PersonaParaVender personaParaVender(
  String id, {
  String nombre = 'María',
  String apellido = 'Fernández',
  String? calle = 'Mataojo',
  String? numero = '2044',
  String? depto = '3B',
  String? telefono,
}) {
  final ubicacion = Ubicacion(
    id: 'ub-$id',
    tipo: depto == null ? TipoUbicacion.casa : TipoUbicacion.edificio,
    calle: calle,
    numero: numero,
    lat: -34.9,
    lon: -56.16,
    ciudadId: 'mvd',
    auditoria: _auditoria(),
  );
  return PersonaParaVender(
    persona: Persona(
      id: 'per-$id',
      nombre: nombre,
      apellido: apellido,
      telefono: telefono,
      auditoria: _auditoria(),
    ),
    espacioPersonaId: 'ep-$id',
    espacio: Espacio(
      id: 'esp-$id',
      ubicacionId: ubicacion.id,
      numeroDepto: depto,
      auditoria: _auditoria(),
    ),
    ubicacion: ubicacion,
  );
}

/// [LectorDePersonasParaVender] en memoria: al suscribirse emite [actuales] (salvo que haya una
/// [compuerta] sin completar) y después lo que el test emita con [emitir] / [fallar].
final class LectorDePersonasParaVenderFalso implements LectorDePersonasParaVender {
  LectorDePersonasParaVenderFalso([List<PersonaParaVender> iniciales = const []])
    : actuales = List.of(iniciales);

  List<PersonaParaVender> actuales;

  /// Si no es `null`, la primera emisión espera a que se complete (la lectura «en curso»).
  Completer<void>? compuerta;

  /// Si no es `null`, la próxima suscripción termina con este error en vez de emitir.
  Object? error;

  var suscripciones = 0;
  final _cambios = StreamController<List<PersonaParaVender>>.broadcast();

  void emitir(List<PersonaParaVender> personas) {
    actuales = List.of(personas);
    _cambios.add(actuales);
  }

  @override
  Stream<List<PersonaParaVender>> observar(String colportorId) async* {
    suscripciones++;
    final falla = error;
    if (falla != null) {
      error = null;
      throw falla;
    }
    await compuerta?.future;
    yield actuales;
    yield* _cambios.stream;
  }
}
