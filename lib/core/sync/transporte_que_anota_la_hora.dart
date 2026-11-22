import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';

import 'hora_del_servidor.dart';

/// Un [SyncTransport] que, sin cambiar nada de lo que hace [_interno], anota la `server_time` de cada
/// push y de cada pull que el servidor contestó ([HoraDelServidor.registrar]).
///
/// No anota la de un push donde algún job volvió con `CS003` (lote demasiado grande, sin partir): en
/// ese caso `SupabaseRpcTransport` arma el resultado él mismo con el reloj del equipo, no con el del
/// servidor. Si anotar falla no se nota: el motor ve el mismo resultado o la misma falla de siempre.
final class TransporteQueAnotaLaHora implements SyncTransport {
  const TransporteQueAnotaLaHora(this._interno, this._hora);

  final SyncTransport _interno;
  final HoraDelServidor _hora;

  @override
  Future<PushResult> push(PushBatch batch) async {
    final resultado = await _interno.push(batch);
    final armadoPorElCliente = resultado.results.any((r) => r.code == kRpcLoteDemasiadoGrande);
    if (!armadoPorElCliente) await _anotar(resultado.serverTime);
    return resultado;
  }

  @override
  Future<PullDelta> pull({required List<String> entities, String? watermark, int? limit}) async {
    final delta = await _interno.pull(entities: entities, watermark: watermark, limit: limit);
    await _anotar(delta.serverTime);
    return delta;
  }

  Future<void> _anotar(DateTime serverTime) async {
    try {
      await _hora.registrar(serverTime);
    } on Object {
      // `HoraDelServidorEnDb` ya lo deja en el log; otra implementación no debe tumbar el ciclo.
    }
  }
}
