import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/acompaniante.dart';
import '../entities/tendencia_de_la_jornada.dart';

/// El acompañamiento de la jornada (HU-JOR-003) y cómo va contra la anterior (vista 21): todo local, sin
/// red (offline-first); lo que se anota sube con la jornada.
abstract interface class AcompaniamientoRepository {
  /// Los coordinadores que se ofrecen en «¿Quién te acompaña?», con lo que ya bajó con la sincronización.
  ///
  /// [campaniaIds] son las campañas de la jornada; `null` si el teléfono no sabe cuál es (se ofrecen los de
  /// todas en las que está inscripta: el pull solo trae esas). Quedan afuera los que dejaron de contar
  /// (`out_of_area` de `campania_coordinador`, contrato §2.1), los dados de baja y la propia colportora
  /// ([colportorId]). Sin repetidos por persona, ordenados por nombre.
  Stream<List<CoordinadorDeCampania>> observarLista({
    required String colportorId,
    Set<String>? campaniaIds,
  });

  /// Quienes acompañan la [jornadaId] hoy, en el orden en que se anotaron.
  Stream<List<Acompaniante>> observarDe(String jornadaId);

  /// Deja como acompañantes de la jornada exactamente a [usuarioIds]: suma a los nuevos, da de baja a los
  /// que ya no están y no toca ni vuelve a subir a los que siguen. Idempotente: repetirla con el mismo
  /// conjunto no cambia nada. Todo o nada.
  Future<Either<Failure, Unit>> guardar({
    required String jornadaId,
    required String colportorId,
    required Set<String> usuarioIds,
  });

  /// La tendencia de la jornada [jornadaId] contra la última cerrada de la misma campaña, que se mira
  /// dentro de [campania] (días `AAAA-MM-DD`, `hasta` en `null` si la campaña no termina). Con la campaña
  /// desconocida (`null`) no se sabe contra cuál comparar y no hay tendencia (`null`, que no es «primera»).
  /// [fin] en `null` es una jornada en curso. Reactiva: cambia cuando la colportora visita una casa o
  /// registra una venta.
  Stream<TendenciaDeLaJornada?> observarTendencia({
    required String colportorId,
    required String jornadaId,
    required DateTime inicio,
    DateTime? fin,
    ({String desde, String? hasta})? campania,
  });
}
