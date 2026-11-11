import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/usecases/jornadas_por_cerrar_use_case.dart';
import 'jornada_providers.dart';

/// Riverpod 3 reintenta solo un provider que falla: la lectura de las jornadas se muestra con su
/// error y no se repite en silencio.
Duration? _sinReintentos(int intento, Object error) => null;

/// Las jornadas abiertas de [colportorId] que tienen otra después (HU-JOR-002, «Jornada que quedó
/// abierta»), la más vieja primero: después de recuperar los datos de otro teléfono, cada una pasa
/// por «¿A qué hora terminaste?» antes de llegar a Hoy. Vacío casi siempre. Si no se pudo leer, el
/// estado queda en error con la falla como causa.
final jornadasPorCerrarProvider = FutureProvider.autoDispose.family<List<JornadaPorCerrar>, String>(
  (ref, colportorId) async {
    final resultado = await ref.watch(jornadasPorCerrarUseCaseProvider)(
      JornadasPorCerrarParams(colportorId: colportorId),
    );
    return resultado.fold((falla) => throw falla, (lista) => lista);
  },
  retry: _sinReintentos,
);
