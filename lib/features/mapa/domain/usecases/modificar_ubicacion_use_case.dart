import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/instante.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/resultado_modificacion_ubicacion.dart';
import '../entities/ubicacion.dart';
import '../repositories/ubicacion_repository.dart';
import '../services/criterio_duplicado_ubicacion.dart';
import '../services/ubicador_zona.dart';
import '../value_objects/coordenadas.dart';

/// Parámetros de [ModificarUbicacionUseCase]: **los valores con los que tiene que quedar** la
/// ubicación (el formulario parte de los actuales), no un delta. `calle` y `numero` en blanco o
/// `null` los dejan sin cargar (R-UB02).
final class ModificarUbicacionParams extends Equatable {
  const ModificarUbicacionParams({
    required this.id,
    required this.colportorId,
    required this.tipo,
    required this.coordenadas,
    required this.baseUpdatedAt,
    this.ciudadId,
    this.calle,
    this.numero,
    this.confirmadas = const {},
    this.justificacionDuplicado,
  });

  /// La ubicación que se modifica.
  final String id;

  /// UUID del usuario con la sesión iniciada: quien la mueve. Una ubicación que registró otro
  /// colportor solo se puede mover dentro de sus zonas (backend-supabase 0010).
  final String colportorId;

  final TipoUbicacion tipo;
  final Coordenadas coordenadas;

  /// El `updated_at` de la ubicación **tal como la pantalla la cargó** para editarla, no el de
  /// ahora: es la base del control de edición concurrente. Si mientras el colportor editaba el
  /// pull trajo un cambio (una corrección del coordinador), la fila ya no tiene este valor y el
  /// guardado se rechaza con [FailureUbicacionCambio] en vez de pisarlo.
  final DateTime baseUpdatedAt;

  /// Obligatorio: `null` o en blanco da [FailureCiudadRequerida].
  final String? ciudadId;
  final String? calle;
  final String? numero;

  /// Las confirmaciones que el colportor ya dio, en respuesta a un
  /// [ModificacionRequiereConfirmacion].
  final Set<ConfirmacionModificacion> confirmadas;

  /// "Seguir igual" ante candidatas a duplicado, con el motivo. `null` valida duplicados; si viene,
  /// no puede estar en blanco.
  final String? justificacionDuplicado;

  /// La justificación es texto libre y puede nombrar personas: no se imprime nunca.
  @override
  bool get stringify => false;

  @override
  List<Object?> get props => [
    id,
    colportorId,
    tipo,
    coordenadas,
    baseUpdatedAt,
    ciudadId,
    calle,
    numero,
    confirmadas,
    justificacionDuplicado,
  ];
}

/// HU-UBI-004 — Modificar ubicación.
///
/// Se pueden editar `tipo`, `calle`, `numero`, `coords` y `ciudad_id`; nada más (la auditoría la
/// lleva el caso de uso). En orden:
///
/// 1. Sin `id` o sin colportor, con coordenadas en `(0, 0)` o fuera de rango, o una justificación
///    en blanco: `Left(FailureValidacion)`. Sin `ciudad_id`: `Left(FailureCiudadRequerida)`.
/// 2. La ubicación no está: `Left(FailureUbicacionInexistente)`.
/// 3. Nada cambió: `Right(ModificacionSinCambios)`, sin escribir ni encolar. Si además la fila ya
///    no tiene [ModificarUbicacionParams.baseUpdatedAt] pero tiene **exactamente** los valores
///    pedidos (doble toque en "Guardar": el primero entró), es un éxito idempotente:
///    `Right(UbicacionModificada)` con la fila tal cual, sin escribir ni encolar.
///    Si no es ese caso y la fila cambió desde que se cargó la pantalla: `Left(FailureUbicacionCambio)`.
/// 4. `EDIFICIO` → `CASA`/`NEGOCIO` con **dos o más** espacios activos:
///    `Left(FailureUbicacionConEspacios)` (S17). Es un bloqueo, no una confirmación. Con un solo
///    espacio activo se permite (decisión de Cristian, 07/10): ese depto pasa a ser el espacio de
///    la casa y en la misma transacción se le quita el `numero_depto`; con ninguno, no hay nada
///    más que hacer. Solo cuentan los activos. Al revés (`CASA`/`NEGOCIO` → `EDIFICIO`) no se
///    toca ningún espacio: el de la casa ya tiene `numero_depto` nulo y pasa a ser el primer
///    depto, que la lista de deptos muestra «Sin número» (HU-UBI-007).
/// 5. Si se mueve (cambia el punto o la ciudad), la zona pasa a ser la que contiene el punto nuevo,
///    o `null` fuera de toda zona ([UbicadorZona]); si no se mueve, conserva la que tenía. Si la
///    ubicación la registró otro colportor y la zona nueva no es una de las de quien la mueve:
///    `Left(FailureUbicacionAjenaFueraDeZona)`, otro bloqueo (el servidor la rechazaría, 0010).
/// 6. Faltan confirmaciones —reactivar una baja (S18), cambiar de ciudad, mover el punto más de
///    [umbralDesplazamientoMetros]—: `Right(ModificacionRequiereConfirmacion)` con **todas** las
///    que faltan, sin escribir.
/// 7. Se escribe con `updated_at` = ahora (y `deleted_at` en `null` si se reactivó). El
///    repositorio, en la misma transacción, re-valida duplicados si cambió la calle, el número, el
///    punto, la ciudad o se reactiva (salvo con justificación), verifica que la fila no haya
///    cambiado desde que se leyó y encola el `update`.
///
/// **Versión para el sync.** El caso de uso no toca `sync_version`: el `update` sube la versión
/// que la fila ya tiene y el servidor compara contra ella (compare-and-swap, backend-supabase
/// 0002) y es quien la incrementa y fija `updated_at`. Sumarle 1 acá haría rechazar todo cambio
/// como conflicto. La HU dice "incrementa `sync_version`": para confirmar en #201.
///
/// **Auditoría.** `ubicacion` no tiene `updated_by`: `updated_at` es todo lo que se puede dejar
/// (el servidor reescribe `updated_at` al aceptar). Para confirmar en #201.
///
/// Todo es local: sin red la modificación se aplica igual y el sync queda en la cola.
final class ModificarUbicacionUseCase
    implements UseCase<ResultadoModificacionUbicacion, ModificarUbicacionParams> {
  /// [_ubicador] y [_criterio] se pasan como `ubicador:` y `criterio:`.
  ModificarUbicacionUseCase(
    this._repository, {
    required this._ubicador,
    DateTime Function()? ahora,
    this._criterio = const CriterioDuplicadoUbicacion(),
  }) : _ahora = ahora ?? DateTime.now;

  /// "Cambio de `coords` con desplazamiento > 100m → advertir" (HU-UBI-004).
  static const umbralDesplazamientoMetros = 100.0;

  final UbicacionRepository _repository;
  final UbicadorZona _ubicador;
  final DateTime Function() _ahora;
  final CriterioDuplicadoUbicacion _criterio;

  @override
  Future<Either<Failure, ResultadoModificacionUbicacion>> call(
    ModificarUbicacionParams params,
  ) async {
    final id = params.id.trim();
    if (id.isEmpty) {
      return const Left(
        FailureValidacion(campos: {'id': 'Falta la ubicación que se quiere modificar'}),
      );
    }
    if (params.colportorId.trim().isEmpty) {
      return const Left(
        FailureValidacion(
          campos: {'colportorId': 'No hay un colportor para modificar la ubicación'},
        ),
      );
    }
    if (params.coordenadas.sonCero || !params.coordenadas.estanEnRango) {
      return const Left(
        FailureValidacion(campos: {'coordenadas': 'Marcá el punto de la ubicación en el mapa.'}),
      );
    }
    final ciudadId = _texto(params.ciudadId);
    if (ciudadId == null) return const Left(FailureCiudadRequerida());
    final seguirIgual = params.justificacionDuplicado != null;
    if (seguirIgual && _texto(params.justificacionDuplicado) == null) {
      return const Left(
        FailureValidacion(
          campos: {'justificacion': 'Contá por qué la dejás aunque se parezca a otra.'},
        ),
      );
    }

    final leida = await _repository.obtener(id);
    return leida.fold<Future<Either<Failure, ResultadoModificacionUbicacion>>>(
      (falla) async => Left(falla),
      (actual) async {
        if (actual == null) return const Left(FailureUbicacionInexistente());
        return _modificar(actual, params, ciudadId, seguirIgual);
      },
    );
  }

  Future<Either<Failure, ResultadoModificacionUbicacion>> _modificar(
    Ubicacion actual,
    ModificarUbicacionParams params,
    String ciudadId,
    bool seguirIgual,
  ) async {
    final calle = _texto(params.calle);
    final numero = _texto(params.numero);
    final coordenadas = params.coordenadas;

    final cambioPunto = coordenadas != actual.coordenadas;
    final cambioCiudad = ciudadId != actual.ciudadId;
    final cambioDireccion = calle != actual.calle || numero != actual.numero;
    final cambioTipo = params.tipo != actual.tipo;
    final filaCambio = actual.auditoria.updatedAt != instanteMs(params.baseUpdatedAt);
    if (!cambioPunto && !cambioCiudad && !cambioDireccion && !cambioTipo) {
      return Right(
        filaCambio
            ? UbicacionModificada(ubicacion: actual)
            : ModificacionSinCambios(ubicacion: actual),
      );
    }
    if (filaCambio) return const Left(FailureUbicacionCambio());

    // S17: el repositorio vuelve a contar dentro de la transacción (un espacio puede aparecer entre
    // esta lectura y la escritura); acá se corta antes, para que el bloqueo salga antes que las
    // confirmaciones.
    final dejaDeSerEdificio =
        actual.tipo == TipoUbicacion.edificio && params.tipo != TipoUbicacion.edificio;
    if (dejaDeSerEdificio) {
      final espacios = await _repository.contarEspaciosActivos(actual.id);
      final bloqueo = espacios.fold<Failure?>(
        (falla) => falla,
        (cantidad) => cantidad > 1 ? FailureUbicacionConEspacios(cantidadEspacios: cantidad) : null,
      );
      if (bloqueo != null) return Left(bloqueo);
    }

    var zonaId = actual.zonaId;
    if (cambioPunto || cambioCiudad) {
      final colportorId = params.colportorId.trim();
      final zona = await _ubicador.ubicar(
        coordenadas,
        colportorId: colportorId,
        ciudadId: ciudadId,
      );
      final bloqueo = zona.fold<Failure?>((falla) => falla, (zona) {
        zonaId = zona.zonaId;
        final ajena = actual.auditoria.createdBy != colportorId;
        return ajena && !zona.esDeMisZonas ? const FailureUbicacionAjenaFueraDeZona() : null;
      });
      if (bloqueo != null) return Left(bloqueo);
    }

    final desplazamiento = cambioPunto ? actual.coordenadas.distanciaMetrosA(coordenadas) : 0.0;
    final pendientes = {
      if (actual.estaBorrada && !params.confirmadas.contains(ConfirmacionModificacion.reactivar))
        ConfirmacionModificacion.reactivar,
      if (cambioCiudad && !params.confirmadas.contains(ConfirmacionModificacion.cambioCiudad))
        ConfirmacionModificacion.cambioCiudad,
      if (desplazamiento > umbralDesplazamientoMetros &&
          !params.confirmadas.contains(ConfirmacionModificacion.desplazamiento))
        ConfirmacionModificacion.desplazamiento,
    };
    if (pendientes.isNotEmpty) {
      return Right(
        ModificacionRequiereConfirmacion(
          pendientes: pendientes,
          desplazamientoMetros: pendientes.contains(ConfirmacionModificacion.desplazamiento)
              ? desplazamiento
              : null,
        ),
      );
    }

    final reactiva = actual.estaBorrada;
    final nueva = Ubicacion(
      id: actual.id,
      tipo: params.tipo,
      calle: calle,
      numero: numero,
      lat: coordenadas.lat,
      lon: coordenadas.lon,
      ciudadId: ciudadId,
      zonaId: zonaId,
      auditoria: actual.auditoria.copyWith(
        updatedAt: _ahora(),
        deletedAt: reactiva ? null : actual.auditoria.deletedAt,
      ),
    );

    // Solo lo que cambia el criterio de duplicado (ciudad, dirección, punto) —o volver a estar
    // activa— justifica volver a buscar. "Seguir igual" solo pasa las candidatas que lo admiten.
    final buscaDuplicados = cambioPunto || cambioCiudad || cambioDireccion || reactiva;
    final resultado = await _repository.modificar(
      nueva,
      baseUpdatedAt: params.baseUpdatedAt,
      duplicados: !buscaDuplicados
          ? null
          : seguirIgual
          ? _criterio.alSeguirIgual
          : _criterio,
      dejaDeSerEdificio: dejaDeSerEdificio,
    );
    return resultado.map(
      (r) => r is UbicacionModificada
          ? UbicacionModificada(ubicacion: r.ubicacion, reactivada: reactiva)
          : r,
    );
  }

  /// [valor] sin espacios en los bordes, o `null` si queda vacío.
  static String? _texto(String? valor) {
    final limpio = valor?.trim();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }
}
