import 'dart:async';

import '../../../domain/entities/inscripcion_con_zona.dart';
import '../inscripciones_con_zona_data_source.dart';

/// [InscripcionesConZonaDataSource] en memoria, para tests y la demo sin backend: arranca sin
/// inscripciones (no hay avisos) y [publicar] simula que un pull terminó de escribir. **No es código
/// de producción.**
final class InscripcionesConZonaEnMemoria implements InscripcionesConZonaDataSource {
  InscripcionesConZonaEnMemoria([List<InscripcionConZona> iniciales = const []])
    : _actuales = List.of(iniciales);

  List<InscripcionConZona> _actuales;
  final _suscriptores = <StreamController<List<InscripcionConZona>>>[];

  /// Cuántas veces se suscribieron a [observar].
  int suscripciones = 0;

  /// Si no es `null`, [observar] emite este error en lugar de las inscripciones.
  Object? falla;

  @override
  Stream<List<InscripcionConZona>> observar(String usuarioId) {
    suscripciones++;
    final controlador = StreamController<List<InscripcionConZona>>();
    controlador.onCancel = () => _suscriptores.remove(controlador);
    _suscriptores.add(controlador);
    if (falla case final error?) {
      controlador.addError(error);
    } else {
      controlador.add(List.of(_actuales));
    }
    return controlador.stream;
  }

  /// Simula un pull: las inscripciones pasan a ser [inscripciones] y todos los suscriptores
  /// reciben el estado nuevo.
  void publicar(List<InscripcionConZona> inscripciones) {
    _actuales = List.of(inscripciones);
    for (final suscriptor in List.of(_suscriptores)) {
      suscriptor.add(List.of(_actuales));
    }
  }

  /// Simula una lectura que falla en medio de la sesión.
  void fallar(Object error) {
    for (final suscriptor in List.of(_suscriptores)) {
      suscriptor.addError(error);
    }
  }
}
