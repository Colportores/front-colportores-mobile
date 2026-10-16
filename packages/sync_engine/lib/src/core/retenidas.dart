import 'model.dart';
import 'queue.dart';
import 'spec.dart';

/// Las filas que el servidor no tiene porque su escritura quedó en espera
/// (§2.2), y la regla para saber si un job nombra alguna.
///
/// Es la misma regla que aplica el servidor (`sync.fila_en_espera`, 0017): un
/// job cuelga de una fila retenida si la nombra en su payload, **como su propia
/// PK o como referencia**. El servidor solo la aplica dentro del lote; el motor
/// la aplica antes de mandar cada lote, para que lo que cuelga de un alta en
/// conflicto no viaje en otro lote sin ella y vuelva `INVALID`.
class FilasRetenidas {
  FilasRetenidas(this._specs);

  final SpecRegistry _specs;

  /// PKs de filas cuyo alta el servidor no guardó: un insert en espera, o algo
  /// que a su vez cuelga de uno. Nombrarlas de cualquier forma es colgar.
  final Set<String> _sinServidor = {};

  /// `(entidad, pk)` de filas que el servidor sí tiene, pero con una
  /// corrección en espera (un update de dirección que chocó). Colgar de ellas
  /// es solo volver a escribirlas: referenciarlas no es problema, porque la
  /// fila existe.
  final Set<(String, String)> _corregidas = {};

  bool get isEmpty => _sinServidor.isEmpty && _corregidas.isEmpty;

  /// Arma el conjunto desde lo que la cola ya tiene en espera.
  factory FilasRetenidas.de(SpecRegistry specs, Iterable<QueuedJob> enEspera) {
    final r = FilasRetenidas(specs);
    for (final q in enEspera) {
      r.retener(q.job);
    }
    return r;
  }

  /// Suma la fila que escribe [job], que acaba de quedar en espera.
  void retener(SyncJob job) {
    final pk = pkDe(_specs, job);
    if (pk == null) return;
    if (job.op == Op.insert) {
      _sinServidor.add(pk);
    } else {
      _corregidas.add((job.entity, pk));
    }
  }

  /// La fila retenida que [job] nombra, o `null` si puede viajar.
  String? nombrada(SyncJob job) {
    if (isEmpty) return null;
    final pk = pkDe(_specs, job);
    if (pk != null &&
        (_sinServidor.contains(pk) || _corregidas.contains((job.entity, pk)))) {
      return pk;
    }
    return _buscar(job.payload);
  }

  String? _buscar(Object? valor) {
    switch (valor) {
      case String s when _sinServidor.contains(s):
        return s;
      case Map<Object?, Object?> m:
        for (final v in m.values) {
          if (_buscar(v) case final s?) return s;
        }
      case Iterable<Object?> l:
        for (final v in l) {
          if (_buscar(v) case final s?) return s;
        }
    }
    return null;
  }
}

/// La PK de la fila que escribe [job], según su `SyncSpec`, o `null` si el
/// payload no la trae (el servidor lo rechaza con `PK_FALTANTE`).
String? pkDe(SpecRegistry specs, SyncJob job) {
  final valor = job.payload[specs.of(job.entity).pk];
  return valor == null ? null : '$valor';
}
