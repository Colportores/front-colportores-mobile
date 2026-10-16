import '../../../../core/domain/entities/auditoria.dart';
import '../../domain/entities/ubicacion.dart';

/// DTO de [Ubicacion]: la entidad más (de)serialización. Es lo único que cruza hacia los data
/// sources.
///
/// [toJson] usa los nombres de columna de `public.ubicacion` (`backend-supabase`, migración 0001)
/// y las fechas en ISO-8601 UTC: es el payload que se encola para el sync, la fila entera
/// (ADR-004: la dirección de la casa va al cloud; la persona no). El test del modelo fija la lista
/// exacta de claves para que no se cuele ninguna.
///
/// Como en `JornadaModel`, un [UbicacionModel] no es igual a una [Ubicacion] con los mismos datos
/// (Equatable compara el `runtimeType`): al dominio vuelve [toEntity].
final class UbicacionModel extends Ubicacion {
  const UbicacionModel({
    required super.id,
    required super.tipo,
    super.calle,
    super.numero,
    required super.lat,
    required super.lon,
    required super.ciudadId,
    super.zonaId,
    required super.auditoria,
  });

  factory UbicacionModel.fromEntity(Ubicacion ubicacion) => UbicacionModel(
    id: ubicacion.id,
    tipo: ubicacion.tipo,
    calle: ubicacion.calle,
    numero: ubicacion.numero,
    lat: ubicacion.lat,
    lon: ubicacion.lon,
    ciudadId: ubicacion.ciudadId,
    zonaId: ubicacion.zonaId,
    auditoria: ubicacion.auditoria,
  );

  factory UbicacionModel.fromJson(Map<String, Object?> json) => UbicacionModel(
    id: json['id']! as String,
    tipo: tipoDesdeCodigo(json['tipo']! as String),
    calle: json['calle'] as String?,
    numero: json['numero'] as String?,
    lat: (json['lat']! as num).toDouble(),
    lon: (json['lon']! as num).toDouble(),
    ciudadId: json['ciudad_id']! as String,
    zonaId: json['zona_id'] as String?,
    auditoria: Auditoria(
      createdAt: _fecha(json['created_at'])!,
      updatedAt: _fecha(json['updated_at'])!,
      createdBy: json['created_by'] as String?,
      deletedAt: _fecha(json['deleted_at']),
      syncVersion: json['sync_version']! as int,
    ),
  );

  /// El valor de `tipo` en la DB y en el cloud (`CASA`, `NEGOCIO`, `EDIFICIO`).
  static String codigoDeTipo(TipoUbicacion tipo) => tipo.name.toUpperCase();

  /// Inversa de [codigoDeTipo]. Lanza `ArgumentError` con un valor desconocido: el `CHECK` de la
  /// tabla no lo deja entrar, así que sería un bug.
  static TipoUbicacion tipoDesdeCodigo(String codigo) =>
      TipoUbicacion.values.byName(codigo.toLowerCase());

  Ubicacion toEntity() => Ubicacion(
    id: id,
    tipo: tipo,
    calle: calle,
    numero: numero,
    lat: lat,
    lon: lon,
    ciudadId: ciudadId,
    zonaId: zonaId,
    auditoria: auditoria,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'tipo': codigoDeTipo(tipo),
    'calle': calle,
    'numero': numero,
    'lat': lat,
    'lon': lon,
    'ciudad_id': ciudadId,
    'zona_id': zonaId,
    'created_at': auditoria.createdAt.toIso8601String(),
    'updated_at': auditoria.updatedAt.toIso8601String(),
    'created_by': auditoria.createdBy,
    'deleted_at': auditoria.deletedAt?.toIso8601String(),
    'sync_version': auditoria.syncVersion,
  };

  /// `timestamptz` llega con zona (`…Z` o `…+00:00`); `Auditoria` lo normaliza.
  static DateTime? _fecha(Object? valor) => valor == null ? null : DateTime.parse(valor as String);
}
