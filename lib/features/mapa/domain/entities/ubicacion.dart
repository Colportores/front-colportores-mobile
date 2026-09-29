import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../value_objects/coordenadas.dart';

/// Tipo de ubicación (HU-UBI-001: enum `CASA | NEGOCIO | EDIFICIO`).
enum TipoUbicacion { casa, negocio, edificio }

/// Dirección física (esquema-datos.md §Modelo de Espacio, tabla `ubicacion`).
///
/// Son las columnas de `public.ubicacion` (backend-supabase 0001), que la app sube enteras
/// (ADR-004: la frontera de privacidad es la persona, no la casa). Sin datos de persona.
///
/// La duplicación **no** es una restricción de unicidad: RF-UB08 es una advertencia del cliente
/// que ofrece "crear igual con justificación" (ADR-004, esquema-datos.md §`ubicacion`), así que ni
/// la DB local ni el cloud tienen un índice único sobre `(ciudad_id, calle, numero)`. La heurística
/// vive en `CriterioDuplicadoUbicacion`.
class Ubicacion extends Equatable {
  const Ubicacion({
    required this.id,
    required this.tipo,
    this.calle,
    this.numero,
    required this.lat,
    required this.lon,
    required this.ciudadId,
    this.zonaId,
    required this.auditoria,
  });

  /// UUID v7 generado en el dispositivo (esquema-datos.md §Principios 2).
  final String id;

  final TipoUbicacion tipo;

  /// Opcional (R-UB02): el alta por marcador manual puede no conocerla. Se guarda tal cual la
  /// escribió el colportor, con `Ñ` y acentos; la normalización es solo para comparar duplicados.
  final String? calle;

  /// Opcional (R-UB02). Texto: en la práctica aparece "1234 bis" o "S/N".
  final String? numero;

  final double lat;
  final double lon;

  /// FK a `ciudad.id` (catálogo Admin). Obligatoria (HU-UBI-001).
  final String ciudadId;

  /// FK a `zona.id`. Nullable como en el cloud, donde es server-authoritative (backend-supabase
  /// 0001, regla 6): el alta la deja en `null`.
  final String? zonaId;

  final Auditoria auditoria;

  Coordenadas get coordenadas => Coordenadas(lat: lat, lon: lon);

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [id, tipo, calle, numero, lat, lon, ciudadId, zonaId, auditoria];
}
