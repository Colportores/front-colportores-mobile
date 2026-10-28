import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../datos/drift_sync_meta.dart';
import '../../../mapa/domain/services/ciudades_para_alta.dart';
import '../../../mapa/domain/value_objects/coordenadas.dart';
import '../../../mapa/presentation/providers/alta_ubicacion_providers.dart'
    show ciudadesParaAltaProvider, proveedorGpsProvider;
import '../../data/repositories/fecha_de_los_precios_sync_meta.dart';
import '../../data/services/fuentes_sin_adaptador_precios.dart';
import '../../domain/entities/catalogo_local.dart';
import '../../domain/entities/ciudad_consultable.dart';
import '../../domain/entities/item_de_precio.dart';
import '../../domain/repositories/consulta_de_precios_repository.dart';
import '../../domain/repositories/fecha_de_los_precios.dart';
import '../../domain/repositories/fuente_de_ciudades_para_precios.dart';
import '../../domain/services/antiguedad_de_precios.dart';
import '../../domain/services/selector_de_ciudad_inicial.dart';

// Cableado de la consulta de precios (HU-CAT-006, vista 26): de dónde salen las ciudades, el
// catálogo y la fecha de los precios, y lo que la colportora fue eligiendo en la pantalla.

/// El catálogo de ventas replicado en el teléfono. Sin réplica (#180 todavía no está en `develop`)
/// [ConsultaDePreciosSinFuente] emite el error de 26·10: la app no sale a producción así.
final consultaDePreciosRepositoryProvider = Provider<ConsultaDePreciosRepository>(
  (ref) => ConsultaDePreciosSinFuente(),
);

/// Las ciudades y campañas de la colportora. Sin réplica (#274) [FuenteDeCiudadesParaPreciosSinFuente]
/// devuelve la falla de lectura: la app no sale a producción así.
final fuenteDeCiudadesParaPreciosProvider = Provider<FuenteDeCiudadesParaPrecios>(
  (ref) => FuenteDeCiudadesParaPreciosSinFuente(),
);

/// Cuándo bajó el teléfono por última vez los precios: la última bajada del motor. Sin DB abierta no
/// se sabe.
final fechaDeLosPreciosProvider = Provider<FechaDeLosPrecios>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return const FechaDeLosPreciosDesconocida();
  return FechaDeLosPreciosSyncMeta(DriftSyncMeta(db));
});

/// Los días del aviso fuerte de precios viejos. Mientras `parametro_global` no baje al teléfono
/// (backend-supabase 0070), los 15 por defecto.
final diasDeAntiguedadDePreciosProvider = Provider<DiasDeAntiguedadDePrecios>(
  (ref) => const DiasDeAntiguedadPorDefecto(AntiguedadDePrecios.diasPorDefecto),
);

/// El reloj de la pantalla («cuántos días tienen los precios», el día que rige); un test lo reemplaza.
final relojPreciosProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Cuánto se espera al GPS antes de abrir con la ciudad de la zona: abrir Precios no puede quedar
/// colgado en una lectura que no llega. Un test lo reemplaza.
final esperaDelGpsPreciosProvider = Provider<Duration>((ref) => const Duration(seconds: 8));

/// Riverpod 3 reintenta 10 veces lo que falla: la pantalla muestra el error enseguida (26·10) y el
/// «Reintentar» es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

/// Con qué ciudad abre Precios.
class AperturaDePrecios {
  const AperturaDePrecios({required this.contexto, required this.inicial});

  final ContextoDeCiudades contexto;

  /// La ciudad de entrada y de dónde sale; sin ciudad si hay que elegirla.
  final CiudadInicial inicial;
}

/// Lee las ciudades de la colportora [colportorId] y decide con cuál abre Precios (decisión de
/// Cristian, 23/10, «Precios GPS»). Un error de lectura sale como estado de error (26·10).
final aperturaDePreciosProvider = FutureProvider.autoDispose.family<AperturaDePrecios, String>((
  ref,
  colportorId,
) async {
  final leido = await ref.watch(fuenteDeCiudadesParaPreciosProvider).leer(colportorId);
  final contexto = leido.fold<ContextoDeCiudades>((falla) => throw falla, (contexto) => contexto);
  if (contexto.ciudades.isEmpty) {
    return AperturaDePrecios(contexto: contexto, inicial: const CiudadInicial.ninguna());
  }
  final ciudadDelGps = await _ciudadDelGps(ref, colportorId);
  return AperturaDePrecios(
    contexto: contexto,
    inicial: SelectorDeCiudadInicial.elegir(contexto: contexto, ciudadDelGpsId: ciudadDelGps),
  );
}, retry: _sinReintentos);

/// La `ciudad.id` en la que el GPS ubica a la colportora, o `null` si no hay GPS (apagado, sin
/// permiso, sin señal, lectura que no llega) o no la ubica en ninguna zona de sus campañas. Nunca
/// lanza: sin GPS Precios abre igual, con la ciudad de su zona.
Future<String?> _ciudadDelGps(Ref ref, String colportorId) async {
  try {
    final espera = ref.read(esperaDelGpsPreciosProvider);
    final lectura = await ref.read(proveedorGpsProvider).posicionActual().timeout(espera);
    final Coordenadas? punto = lectura.fold<Coordenadas?>((_) => null, (l) {
      final c = l.coordenadas;
      return c.sonCero || !c.estanEnRango ? null : c;
    });
    if (punto == null) return null;
    final propuesta = await ref
        .read(ciudadesParaAltaProvider)
        .proponer(colportorId: colportorId, punto: punto);
    return propuesta.fold<String?>(
      (_) => null,
      (propuesta) => switch (propuesta) {
        CiudadPropuesta(:final ciudad, origen: OrigenPropuesta.detectada) => ciudad.id,
        _ => null,
      },
    );
  } on Object {
    return null;
  }
}

/// La ciudad que la colportora eligió en «Ver otra ciudad» (26·04), o `null` si mira la de entrada.
/// Elegir una ciudad es solo de esta consulta: no cambia lo que se descarga ni con qué precios se
/// vende (HU-CAT-006).
final class CiudadElegidaNotifier extends Notifier<CiudadConsultable?> {
  CiudadElegidaNotifier(this.colportorId);

  final String colportorId;

  @override
  CiudadConsultable? build() => null;

  void elegir(CiudadConsultable? ciudad) => state = ciudad;
}

final ciudadElegidaDePreciosProvider = NotifierProvider.autoDispose
    .family<CiudadElegidaNotifier, CiudadConsultable?, String>(CiudadElegidaNotifier.new);

/// El catálogo de la ciudad de la campaña [campaniaCiudadId], reactivo: un cambio que baja el pull
/// o el Realtime se ve sin tocar nada.
final catalogoDePreciosProvider = StreamProvider.autoDispose.family<CatalogoLocal, String>(
  (ref, campaniaCiudadId) =>
      ref.watch(consultaDePreciosRepositoryProvider).observar(campaniaCiudadId),
  retry: _sinReintentos,
);

/// Cuándo bajaron los precios (26·09). `null` = no se sabe.
final ultimaBajadaDePreciosProvider = FutureProvider.autoDispose<DateTime?>(
  (ref) => ref.watch(fechaDeLosPreciosProvider).ultimaBajada(),
  retry: _sinReintentos,
);

/// Los N días a partir de los cuales el aviso de precios viejos se pone fuerte.
final diasDelAvisoFuerteProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(diasDeAntiguedadDePreciosProvider).dias(),
  retry: _sinReintentos,
);

/// La pestaña y la búsqueda de la pantalla.
class FiltrosDePrecios {
  const FiltrosDePrecios({this.categoria = CategoriaDePrecios.colecciones, this.busqueda = ''});

  final CategoriaDePrecios categoria;
  final String busqueda;

  /// Solo los productos se buscan: las colecciones no llevan buscador (26·01).
  bool get conBuscador => categoria != CategoriaDePrecios.colecciones;

  bool get estaBuscando => conBuscador && busqueda.trim().isNotEmpty;
}

final class FiltrosDePreciosNotifier extends Notifier<FiltrosDePrecios> {
  FiltrosDePreciosNotifier(this.colportorId);

  final String colportorId;

  @override
  FiltrosDePrecios build() => const FiltrosDePrecios();

  /// Al cambiar de pestaña la búsqueda se limpia: lo que se escribió buscaba en otra lista.
  void elegirCategoria(CategoriaDePrecios categoria) {
    if (categoria == state.categoria) return;
    state = FiltrosDePrecios(categoria: categoria);
  }

  void buscar(String texto) =>
      state = FiltrosDePrecios(categoria: state.categoria, busqueda: texto);
}

final filtrosDePreciosProvider = NotifierProvider.autoDispose
    .family<FiltrosDePreciosNotifier, FiltrosDePrecios, String>(FiltrosDePreciosNotifier.new);
