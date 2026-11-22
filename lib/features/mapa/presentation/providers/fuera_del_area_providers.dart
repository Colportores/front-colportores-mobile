import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../datos/drift_local_store.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import 'mapa_ubicaciones_notifier.dart';

// Las casas «fuera del área» en el mapa (#713; HU-SYNC-011, R-UB12, contrato-sync-engine §2.1): el
// motor marca las filas que salieron del área del colportor en `sync_fuera_del_area` y nunca las
// borra. El mapa las distingue con una marca y el colportor elige si las ve o las oculta. La
// elección es **solo visual**: no toca la base ni encola nada.

Duration? _sinReintentos(int intento, Object error) => null;

/// La entidad del motor de la que salen las casas del mapa.
const _entidadUbicacion = 'ubicacion';

/// Los `id` de las ubicaciones que el motor marcó fuera del área (`DriftLocalStore.observarFueraDelArea`).
/// Reactivo: un pull que saca o devuelve una casa al área cambia el conjunto. Sin base abierta, ninguna.
/// Si la lectura falla, el mapa sigue como si no hubiera ninguna (la marca es una ayuda, no un dato que
/// se pueda perder).
final idsFueraDelAreaProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return Stream.value(const <String>{});
  // Solo se lee la marca: el conjunto de entidades que puede escribir el store no hace falta.
  return DriftLocalStore(db, entidades: const {}).observarFueraDelArea(_entidadUbicacion);
}, retry: _sinReintentos);

/// La elección del colportor: ver (por defecto) u ocultar en el mapa las casas fuera de su área.
///
/// Vive mientras la app está abierta (keepAlive) y no se guarda: al volver a abrir la app las casas se
/// ven de nuevo, con su marca. Así ninguna casa queda escondida sin que el colportor lo recuerde
/// (ante la duda, se ve).
final class VerFueraDelAreaNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  /// Las casas fuera del área se ven en el mapa, con su marca.
  void ver() => state = true;

  /// Las casas fuera del área no se dibujan en el mapa ni en «Cercanía». No se borra nada.
  void ocultar() => state = false;

  /// [ver] o [ocultar], según [valor] (el interruptor de «Referencias»).
  void elegir({required bool valor}) => state = valor;
}

/// Ver u ocultar las casas fuera del área (`true`: se ven).
final verFueraDelAreaProvider = NotifierProvider<VerFueraDelAreaNotifier, bool>(
  VerFueraDelAreaNotifier.new,
);

/// Lo que el mapa sabe de las casas fuera del área: cuáles de las suyas lo están y si se ven.
final class FueraDelAreaEnElMapa extends Equatable {
  const FueraDelAreaEnElMapa({this.ids = const {}, this.ver = true});

  /// Las ubicaciones del mapa (las activas del colportor) que quedaron fuera del área.
  final Set<String> ids;

  /// El colportor eligió verlas.
  final bool ver;

  /// Cuántas casas del mapa están fuera del área.
  int get cantidad => ids.length;

  /// Cuántas no se dibujan porque el colportor las ocultó (0 si las ve).
  int get ocultas => ver ? 0 : ids.length;

  /// La casa [id] se dibuja con la marca «fuera del área».
  bool marcada(String id) => ver && ids.contains(id);

  /// La casa [id] no se dibuja (ni en el mapa ni en «Cercanía»). La [elegida] nunca se oculta: si el
  /// colportor llegó a ella (desde otra pantalla, o la tenía abierta al ocultar) la sigue viendo.
  bool oculta(String id, {String? elegida}) => !ver && id != elegida && ids.contains(id);

  @override
  List<Object?> get props => [ids, ver];
}

/// Las casas fuera del área del mapa del colportor [colportorId]: las marcadas por el motor que son
/// de su mapa (las bajas no se dibujan, así que tampoco cuentan) y si el colportor las ve.
final fueraDelAreaEnElMapaProvider = Provider.autoDispose.family<FueraDelAreaEnElMapa, String>((
  ref,
  colportorId,
) {
  final ver = ref.watch(verFueraDelAreaProvider);
  final marcadas = ref.watch(idsFueraDelAreaProvider).value ?? const <String>{};
  if (marcadas.isEmpty) return FueraDelAreaEnElMapa(ver: ver);
  final lista = ref.watch(mapaUbicacionesProvider(colportorId).select((e) => e.lista));
  return FueraDelAreaEnElMapa(
    ids: {
      for (final item in lista?.items ?? const <ItemListaUbicacion>[])
        if (marcadas.contains(item.ubicacion.id)) item.ubicacion.id,
    },
    ver: ver,
  );
});
