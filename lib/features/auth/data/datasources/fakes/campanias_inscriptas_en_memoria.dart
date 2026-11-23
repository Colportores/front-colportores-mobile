import 'dart:async';

import '../../../domain/entities/campania_inscripta.dart';
import '../campanias_inscriptas_data_source.dart';

/// [CampaniasInscriptasDataSource] en memoria, para tests y la demo sin backend: arranca sin
/// campañas (no frena nada) y [publicar] simula que un pull terminó de escribir. **No es código de
/// producción.**
final class CampaniasInscriptasEnMemoria implements CampaniasInscriptasDataSource {
  CampaniasInscriptasEnMemoria([List<CampaniaInscripta>? iniciales = const []])
    : _actuales = iniciales == null ? null : List.of(iniciales);

  List<CampaniaInscripta>? _actuales;
  final _suscriptores = <StreamController<List<CampaniaInscripta>?>>[];

  /// Cuántas veces se suscribieron a [observar].
  int suscripciones = 0;

  /// Si no es `null`, [observar] emite este error en lugar de las campañas.
  Object? falla;

  @override
  Stream<List<CampaniaInscripta>?> observar(String usuarioId) {
    suscripciones++;
    final controlador = StreamController<List<CampaniaInscripta>?>();
    controlador.onCancel = () => _suscriptores.remove(controlador);
    _suscriptores.add(controlador);
    if (falla case final error?) {
      controlador.addError(error);
    } else {
      controlador.add(_copia());
    }
    return controlador.stream;
  }

  /// Simula un pull: las campañas pasan a ser [campanias] (`null` = todavía no se puede saber) y
  /// todos los suscriptores reciben el estado nuevo.
  void publicar(List<CampaniaInscripta>? campanias) {
    _actuales = campanias == null ? null : List.of(campanias);
    for (final suscriptor in List.of(_suscriptores)) {
      suscriptor.add(_copia());
    }
  }

  List<CampaniaInscripta>? _copia() => _actuales == null ? null : List.of(_actuales!);
}
