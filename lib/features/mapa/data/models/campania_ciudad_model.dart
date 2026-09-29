import 'package:equatable/equatable.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import 'auditoria_json.dart';

/// Una fila de `campania_ciudad` del canal de catálogo (backend-supabase 0008): la ciudad
/// [ciudadId] incluida en la campaña [campaniaId].
///
/// [fromJson] lee la fila del delta del pull (todas las columnas de la tabla menos `xmin_w`) y
/// [toJson] la devuelve con los mismos nombres. [fromFila] y [aFila] la pasan de y a la tabla local
/// `CampaniasCiudad`. La app nunca la escribe por su cuenta: es una réplica.
final class CampaniaCiudadModel extends Equatable {
  const CampaniaCiudadModel({
    required this.id,
    required this.campaniaId,
    required this.ciudadId,
    required this.auditoria,
  });

  factory CampaniaCiudadModel.fromJson(Map<String, Object?> json) => CampaniaCiudadModel(
    id: json['id']! as String,
    campaniaId: json['campania_id']! as String,
    ciudadId: json['ciudad_id']! as String,
    auditoria: auditoriaDesdeJson(json),
  );

  factory CampaniaCiudadModel.fromFila(CampaniaCiudadFila fila) => CampaniaCiudadModel(
    id: fila.id,
    campaniaId: fila.campaniaId,
    ciudadId: fila.ciudadId,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  final String id;
  final String campaniaId;
  final String ciudadId;
  final Auditoria auditoria;

  CampaniaCiudadFila aFila() => CampaniaCiudadFila(
    id: id,
    campaniaId: campaniaId,
    ciudadId: ciudadId,
    createdAt: auditoria.createdAt,
    updatedAt: auditoria.updatedAt,
    createdBy: auditoria.createdBy,
    deletedAt: auditoria.deletedAt,
    syncVersion: auditoria.syncVersion,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'campania_id': campaniaId,
    'ciudad_id': ciudadId,
    ...auditoriaAJson(auditoria),
  };

  @override
  List<Object?> get props => [id, campaniaId, ciudadId, auditoria];
}
