import 'package:dartz/dartz.dart' show Either, Left;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../../domain/usecases/consultar_lista_ubicaciones_use_case.dart';
import '../../domain/value_objects/coordenadas.dart';
import 'alta_ubicacion_providers.dart';
import 'lista_ubicaciones_state.dart';

// Cableado de la lista de ubicaciones (HU-UBI-002, vista 05). Usa la misma base y los mismos
// puertos que el alta (`alta_ubicacion_providers`): lo que todavía no tiene fuente real (las
// ciudades de la campaña, #274) sigue siendo un `...SinFuente` que no inventa datos.

/// La lista del colportor, reactiva (§8.8): cualquier alta, baja o edición la vuelve a emitir.
final consultarListaUbicacionesUseCaseProvider = Provider<ConsultarListaUbicacionesUseCase>(
  (ref) => ConsultarListaUbicacionesUseCase(ref.watch(ubicacionRepositoryProvider)),
);

/// Qué se está armando en la hoja de filtros, para calcular los contadores y el «Ver N ubicaciones».
typedef BorradorFiltros = ({String colportorId, FiltrosLista filtros, Coordenadas? posicion});

/// Los contadores de lo que **quedaría** con los filtros del borrador de la hoja. Pide una sola
/// fila (`limite: 1`): solo importan los totales. Se descarta cuando la hoja se cierra.
final previsualizacionFiltrosProvider = StreamProvider.autoDispose
    .family<ListaUbicaciones, BorradorFiltros>((ref, borrador) {
      final consulta = borrador.filtros.consulta(
        colportorId: borrador.colportorId,
        posicion: borrador.posicion,
        limite: 1,
      );
      return ref.watch(consultarListaUbicacionesUseCaseProvider)(consulta);
    });

/// El reloj de la lista («hace 2 h», «ayer»); es el del alta. Un test lo reemplaza.
final relojListaUbicacionesProvider = Provider<DateTime Function()>(
  (ref) => ref.watch(relojAltaUbicacionProvider),
);

/// Las ciudades de la campaña del colportor, para el filtro «Ciudad» y el nombre de su chip. Nunca
/// termina en error: un puerto que lanza se traduce a una falla, y Riverpod no reintenta solo.
final ciudadesListaProvider = FutureProvider.autoDispose
    .family<Either<Failure, List<CiudadCatalogo>>, String>((ref, colportorId) async {
      try {
        return await ref.watch(ciudadesParaAltaProvider).deMiCampania(colportorId);
      } on Object {
        return const Left(FailureInesperado());
      }
    });
