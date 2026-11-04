import '../entities/ciudad_consultable.dart';

/// Con qué ciudad abre Precios (decisión de Cristian, 23/10, «Precios GPS», que ajusta S55):
/// 1. **donde está la colportora**, si el GPS la ubica en una ciudad de alguna de sus campañas;
/// 2. sin eso, **la ciudad de su zona** (el aviso de 26·06);
/// 3. sin zona ni GPS, ninguna: **la elige ella**.
abstract final class SelectorDeCiudadInicial {
  /// [ciudadDelGpsId] es la `ciudad.id` en la que el GPS ubica a la colportora, o `null` si no hay
  /// GPS o no la ubica en ninguna ciudad de sus campañas.
  static CiudadInicial elegir({required ContextoDeCiudades contexto, String? ciudadDelGpsId}) {
    final porGps = contexto.deLaCiudad(ciudadDelGpsId);
    if (porGps != null) return CiudadInicial(porGps, OrigenDeLaCiudad.gps);
    final porZona = contexto.deLaCiudad(contexto.ciudadDeMiZonaId);
    if (porZona != null) return CiudadInicial(porZona, OrigenDeLaCiudad.zona);
    return const CiudadInicial.ninguna();
  }
}
