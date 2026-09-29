import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/espacio.dart';
import '../entities/resultado_alta_ubicacion.dart';
import '../entities/ubicacion.dart';
import '../repositories/ubicacion_repository.dart';
import '../services/criterio_duplicado_ubicacion.dart';
import '../value_objects/punto_capturado.dart';

/// Parámetros de [RegistrarUbicacionUseCase].
final class RegistrarUbicacionParams extends Equatable {
  const RegistrarUbicacionParams({
    required this.colportorId,
    required this.tipo,
    required this.punto,
    this.ciudadId,
    this.calle,
    this.numero,
    this.id,
    this.confirmaBajaPrecision = false,
    this.justificacionDuplicado,
  });

  /// UUID del usuario con la sesión iniciada (`created_by`).
  final String colportorId;

  final TipoUbicacion tipo;

  /// La lectura del GPS o el marcador puesto a mano.
  final PuntoCapturado punto;

  /// `null` si la ciudad de las coordenadas no está en el catálogo: el alta no procede.
  final String? ciudadId;

  /// Opcionales (R-UB02). En blanco cuentan como no cargados.
  final String? calle;
  final String? numero;

  /// El `id` de esta alta. La pantalla lo genera una vez por formulario
  /// ([RegistrarUbicacionUseCase.nuevoId]) y lo repite en cada intento —confirmar la precisión,
  /// "Crear igual", un doble toque—: así el alta es idempotente. `null` genera uno nuevo.
  final String? id;

  /// El colportor ya vio el aviso de baja precisión y eligió continuar.
  final bool confirmaBajaPrecision;

  /// "Crear igual": el colportor vio las candidatas a duplicado y explica por qué crea otra. `null`
  /// valida duplicados; si viene, no puede estar en blanco.
  final String? justificacionDuplicado;

  /// La justificación es texto libre y puede nombrar personas: no se imprime nunca.
  @override
  bool get stringify => false;

  @override
  List<Object?> get props => [
    colportorId,
    tipo,
    punto,
    ciudadId,
    calle,
    numero,
    id,
    confirmaBajaPrecision,
    justificacionDuplicado,
  ];
}

/// HU-UBI-001 — Alta de ubicación con captura GPS.
///
/// En orden:
///
/// 1. Sin colportor, o con coordenadas en `(0, 0)` o fuera de rango: `Left(FailureValidacion)`.
/// 2. Sin `ciudad_id`: `Left(FailureCiudadRequerida)` ("no permite crear la ubicación sin
///    `ciudad_id`").
/// 3. "Crear igual" con la justificación en blanco: `Left(FailureValidacion)`.
/// 4. GPS con precisión peor que 50 m y sin confirmar: `Right(AltaConBajaPrecision)`, sin crear
///    nada.
/// 5. Si no, arma la ubicación —`id` UUID v7, `zona_id` en `null` (la asigna el servidor),
///    auditoría con el colportor como `created_by`— y, si es `CASA`, su espacio default (Supuesto
///    S13), y se los pasa al repositorio, que valida duplicados en la misma transacción en la que
///    guarda y encola el sync (salvo "Crear igual").
///
/// El estado inicial `house_status = "sin_visita"` es la **ausencia** de fila en `house_status`:
/// esa cache solo admite los 7 colores de §8.4 (ADR-003, `CHECK` de backend-supabase 0001) y se
/// escribe con la primera visita. Queda para confirmar en #192.
///
/// Todo es local: sin red el alta se completa igual y el sync queda en la cola (escenario
/// "Offline").
final class RegistrarUbicacionUseCase
    implements UseCase<ResultadoAltaUbicacion, RegistrarUbicacionParams> {
  /// [_generarId] y [_criterio] se pasan como `generarId:` y `criterio:` (parámetros nombrados
  /// privados, Dart ≥ 3.10).
  RegistrarUbicacionUseCase(
    this._repository, {
    required this._generarId,
    DateTime Function()? ahora,
    this._criterio = const CriterioDuplicadoUbicacion(),
  }) : _ahora = ahora ?? DateTime.now;

  final UbicacionRepository _repository;
  final String Function() _generarId;
  final DateTime Function() _ahora;
  final CriterioDuplicadoUbicacion _criterio;

  /// Un `id` nuevo para un formulario de alta (ver [RegistrarUbicacionParams.id]).
  String nuevoId() => _generarId();

  @override
  Future<Either<Failure, ResultadoAltaUbicacion>> call(RegistrarUbicacionParams params) async {
    final colportorId = params.colportorId.trim();
    if (colportorId.isEmpty) {
      return const Left(
        FailureValidacion(
          campos: {'colportorId': 'No hay un colportor para registrar la ubicación'},
        ),
      );
    }

    final coordenadas = params.punto.coordenadas;
    if (coordenadas.sonCero || !coordenadas.estanEnRango) {
      return const Left(
        FailureValidacion(campos: {'coordenadas': 'Marcá el punto de la ubicación en el mapa.'}),
      );
    }

    final ciudadId = _texto(params.ciudadId);
    if (ciudadId == null) return const Left(FailureCiudadRequerida());

    final crearIgual = params.justificacionDuplicado != null;
    if (crearIgual && _texto(params.justificacionDuplicado) == null) {
      return const Left(
        FailureValidacion(
          campos: {'justificacion': 'Contá por qué la registrás aunque se parezca a otra.'},
        ),
      );
    }

    final punto = params.punto;
    if (punto.esImpreciso && !params.confirmaBajaPrecision) {
      return Right(AltaConBajaPrecision(precisionMetros: punto.precisionMetros!));
    }

    final ahora = _ahora();
    final ubicacionId = _texto(params.id) ?? _generarId();
    final ubicacion = Ubicacion(
      id: ubicacionId,
      tipo: params.tipo,
      calle: _texto(params.calle),
      numero: _texto(params.numero),
      lat: coordenadas.lat,
      lon: coordenadas.lon,
      ciudadId: ciudadId,
      auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportorId),
    );
    final espacio = params.tipo == TipoUbicacion.casa
        ? Espacio(
            id: _generarId(),
            ubicacionId: ubicacionId,
            numeroDepto: Espacio.deptoPorDefecto,
            auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportorId),
          )
        : null;

    return _repository.registrar(
      ubicacion,
      espacio: espacio,
      origen: punto.origen,
      duplicados: crearIgual ? null : _criterio,
    );
  }

  /// [valor] sin espacios en los bordes, o `null` si queda vacío.
  static String? _texto(String? valor) {
    final limpio = valor?.trim();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }
}
