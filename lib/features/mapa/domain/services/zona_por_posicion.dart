import '../entities/zona_ubicable.dart';
import '../value_objects/coordenadas.dart';

/// En qué zona cae un punto (regla 4 del cambio de modelo del 29/09). Es la misma regla que el
/// servidor, `zona_de_posicion()` de backend-supabase 0010:
///
/// - **Candidatas**: las `zonas` (vivas) de la ciudad del punto, de una campaña vigente
///   (`campaniasVigentes`), que lo cubren con el borde incluido (`GeometriaZona.cubre`).
/// - **Desempate**: primero las de la campaña que aparece antes en `campaniasPreferidas` (D2); las
///   de una campaña que no está ahí, al final. Después, la de **menor id**: el UUID como texto en
///   minúsculas, el mismo orden que `uuid` en Postgres. Así un punto sobre la calle que separa dos
///   zonas queda en la más vieja (UUID v7), y una zona nueva no le saca los bordes a la vecina.
/// - Si ninguna lo cubre, `null`: fuera de toda zona (el colportor puede registrar fuera de su
///   zona, R-CM04).
///
/// La app la calcula para mostrarla en el momento, también sin conexión. El servidor la vuelve a
/// calcular en cada alta o movimiento y **gana**: `ubicacion.zona_id` es una columna del servidor.
final class ZonaPorPosicion {
  const ZonaPorPosicion();

  String? zonaDe(
    Coordenadas punto, {
    required String ciudadId,
    required Iterable<ZonaUbicable> zonas,
    required Set<String> campaniasVigentes,
    required List<String> campaniasPreferidas,
  }) {
    final preferidas = [for (final id in campaniasPreferidas) id.toLowerCase()];
    int rango(ZonaUbicable zona) {
      final posicion = preferidas.indexOf(zona.campaniaId.toLowerCase());
      return posicion < 0 ? preferidas.length : posicion;
    }

    ZonaUbicable? elegida;
    for (final zona in zonas) {
      if (zona.ciudadId != ciudadId || !campaniasVigentes.contains(zona.campaniaId)) continue;
      if (!zona.geometria.cubre(punto)) continue;
      if (elegida == null || _antes(zona, elegida, rango)) elegida = zona;
    }
    return elegida?.zonaId;
  }

  static bool _antes(ZonaUbicable a, ZonaUbicable b, int Function(ZonaUbicable) rango) {
    final porCampania = rango(a).compareTo(rango(b));
    if (porCampania != 0) return porCampania < 0;
    return a.zonaId.toLowerCase().compareTo(b.zonaId.toLowerCase()) < 0;
  }
}
