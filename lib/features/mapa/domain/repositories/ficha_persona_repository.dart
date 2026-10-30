import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/ficha_de_persona.dart';
import '../entities/persona.dart';

/// Lo que la base local sabe de una persona para armar su ficha: ella y lo que le pasó (visitas y
/// ventas). Las notas, el lugar y la cuenta los suman otros puertos.
class LecturaDeFicha {
  const LecturaDeFicha({required this.persona, required this.historial});

  final Persona persona;

  /// Las visitas y las ventas de la persona (de todos sus vínculos), la más nueva primero.
  final List<MovimientoDeFicha> historial;

  // Lleva datos personales: no tiene `toString` propio, así que nunca los imprime.
}

/// Lectura de la ficha de una persona (HU-UBI-009, vista 32B) y el registro de las llamadas.
///
/// Todo es local (offline-first): nada sale del teléfono.
abstract interface class FichaPersonaRepository {
  /// La persona [personaId] con su historial de visitas y ventas, al día cuando cambia algo de eso: sale
  /// un valor nuevo cuando se registra una visita, una venta, o cambia la persona o su lugar. `null` si
  /// la persona ya no está en el teléfono. Un error de lectura sale por el `Stream`.
  Stream<LecturaDeFicha?> observar(String personaId);

  /// Deja el evento `click_to_call` en la auditoría local (HU-UBI-009), **sin el número**: solo el
  /// `id` de la persona. Es local: no se encola nada al sync.
  Future<Either<Failure, Unit>> registrarLlamada({
    required String personaId,
    required DateTime ahora,
  });
}
