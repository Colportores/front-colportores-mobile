import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/espacio.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/services/agrupador_espacios.dart';
import '../../domain/usecases/agregar_espacio_use_case.dart';
import '../../domain/usecases/dar_de_baja_espacio_use_case.dart';
import '../../domain/usecases/listar_espacios_use_case.dart';
import '../../domain/usecases/modificar_espacio_use_case.dart';
import '../../domain/usecases/restaurar_espacio_use_case.dart';
import 'alta_ubicacion_providers.dart';
import 'personas_providers.dart';

// Cableado de la gestión de espacios (HU-UBI-007, vista 11): la lista de deptos de un edificio, el
// alta, la edición y la baja. El repositorio, el contador de personas y el reloj son los de las
// demás pantallas; un test los reemplaza.

/// Generador de UUID v7 del alta de un espacio; un test lo reemplaza para fijar los ids.
final generadorIdEspacioProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// Reloj de la gestión de espacios; un test lo reemplaza.
final relojEspaciosProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final agregarEspacioUseCaseProvider = Provider<AgregarEspacioUseCase>(
  (ref) => AgregarEspacioUseCase(
    ref.watch(espacioRepositoryProvider),
    generarId: ref.watch(generadorIdEspacioProvider),
    ahora: ref.watch(relojEspaciosProvider),
  ),
);

final modificarEspacioUseCaseProvider = Provider<ModificarEspacioUseCase>(
  (ref) => ModificarEspacioUseCase(
    ref.watch(espacioRepositoryProvider),
    ahora: ref.watch(relojEspaciosProvider),
  ),
);

final darDeBajaEspacioUseCaseProvider = Provider<DarDeBajaEspacioUseCase>(
  (ref) => DarDeBajaEspacioUseCase(
    ref.watch(espacioRepositoryProvider),
    ref.watch(contadorPersonasEspacioProvider),
    ahora: ref.watch(relojEspaciosProvider),
  ),
);

/// Restaurar un depto dado de baja («Reactivar» de «Dados de baja», #473).
final restaurarEspacioUseCaseProvider = Provider<RestaurarEspacioUseCase>(
  (ref) => RestaurarEspacioUseCase(
    ref.watch(espacioRepositoryProvider),
    ahora: ref.watch(relojEspaciosProvider),
  ),
);

final listarEspaciosUseCaseProvider = Provider<ListarEspaciosUseCase>(
  (ref) => ListarEspaciosUseCase(ref.watch(espacioRepositoryProvider)),
);

/// Sin reintento automático: con el que trae Riverpod 3 por defecto (10 intentos con espera creciente)
/// la hoja se quedaría en «Cargando…» y el aviso de error con «Reintentar» tardaría minutos en salir.
Duration? _sinReintentos(int intento, Object error) => null;

/// Los espacios activos de [ubicacionId]. Una falla de lectura sale como error del provider (la
/// hoja muestra «No pudimos leer…» con «Reintentar»); después de cada alta, edición o baja la
/// pantalla lo invalida para volver a leer.
final espaciosDeUbicacionProvider = FutureProvider.autoDispose.family<List<Espacio>, String>((
  ref,
  ubicacionId,
) async {
  final lectura = await ref.watch(listarEspaciosUseCaseProvider)(
    ListarEspaciosParams(ubicacionId: ubicacionId),
  );
  return lectura.fold((Failure falla) => throw falla, (espacios) => espacios);
}, retry: _sinReintentos);

/// Los espacios dados de baja de [ubicacionId], en el orden de la lista (por piso y por número): lo que
/// muestra «Dados de baja» al pie de la hoja del edificio (#473). Se invalida junto con
/// [espaciosDeUbicacionProvider] cuando un depto pasa de un lado al otro.
final espaciosDadosDeBajaProvider = FutureProvider.autoDispose.family<List<Espacio>, String>((
  ref,
  ubicacionId,
) async {
  final lectura = await ref.watch(listarEspaciosUseCaseProvider)(
    ListarEspaciosParams(ubicacionId: ubicacionId, incluirBajas: true),
  );
  return lectura.fold((Failure falla) => throw falla, (todos) {
    final bajas = [
      for (final espacio in todos)
        if (espacio.estaBorrada) espacio,
    ];
    return [for (final grupo in AgrupadorEspacios.porPiso(bajas)) ...grupo.espacios];
  });
}, retry: _sinReintentos);

/// La ubicación [ubicacionId] (la dirección y el tipo que encabezan la hoja), o `null` si ya no está
/// en el teléfono. Una falla de lectura sale como error del provider.
final ubicacionDeLaHojaProvider = FutureProvider.autoDispose.family<Ubicacion?, String>((
  ref,
  ubicacionId,
) async {
  final lectura = await ref.watch(ubicacionRepositoryProvider).obtener(ubicacionId);
  return lectura.fold((Failure falla) => throw falla, (ubicacion) => ubicacion);
}, retry: _sinReintentos);
