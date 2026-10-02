import 'dart:math' as math;

import '../entities/duplicado_ubicacion.dart';
import '../entities/ubicacion.dart';
import '../value_objects/coordenadas.dart';

/// Detector de posibles duplicados de ubicación (RF-UB08, HU-UBI-001 y HU-UBI-006). Es el único:
/// lo usan el alta y la modificación dentro de su transacción y el scan de "Posibles duplicados".
/// Dart puro, sin estado y offline.
///
/// Regla del 29/09 (#207, reemplaza a la de 30 m + Levenshtein): una ubicación **activa** (sin
/// baja) y **distinta** (otro `id`) es candidata si
///
/// - tiene la misma calle y el mismo número en la misma ciudad (`ciudad_id`), a cualquier
///   distancia ([MotivoDuplicado.mismaDireccion]); o
/// - está a menos de [radioMetros] ([MotivoDuplicado.cercania]), en cualquier ciudad y con
///   cualquier dirección.
///
/// Calle y número se comparan con [normalizarDireccion]: la normalización de la HU (sin espacios en
/// los bordes, espacios internos y raros juntados en uno, minúsculas y sin tildes), la misma que
/// hace `direccion_normalizada()` en el servidor (decisión 3 de #207, backend-supabase#24). Si
/// falta la calle o el número en alguna de las dos, solo cuenta la distancia. En la DB queda lo que
/// escribió el colportor.
///
/// Decisión D1 (Cristian, 29/09, backend-supabase#24): dos ubicaciones con la misma dirección a
/// **menos de [radioMismaDireccionMetros]** chocan y no pueden quedar las dos; a esa distancia o
/// más son dos lugares (dos casas con el mismo número en una calle larga) y se admiten, con el
/// aviso. Es un aviso, no un bloqueo, para el resto: ver [mismaDireccionAdmiteConservarAmbos].
final class CriterioDuplicadoUbicacion {
  const CriterioDuplicadoUbicacion({
    this.mismaDireccionAdmiteConservarAmbos = mismaDireccionAdmiteConservarAmbosPorDefecto,
  }) : _soloSinConservarAmbos = false;

  const CriterioDuplicadoUbicacion._soloSinConservarAmbos()
    : mismaDireccionAdmiteConservarAmbos = false,
      _soloSinConservarAmbos = true;

  /// "A menos de 5 m" (#207, vista 10): menos que el frente de una casa. Estricto: a 5 m justos
  /// no es candidata.
  static const radioMetros = 5.0;

  /// "A menos de 100 m" (D1, HU-UBI-001 y HU-UBI-006): la misma dirección a menos de esta distancia
  /// es la misma ubicación y no se puede conservar las dos. Estricto, como el servidor: a 100 m
  /// justos ya son dos lugares.
  static const radioMismaDireccionMetros = 100.0;

  /// **Punto único de la decisión D1** (backend-supabase#24): si dos ubicaciones con la misma
  /// dirección pueden quedar las dos ("Crear igual", "seguir igual", "Conservar ambos").
  ///
  /// - `false` (D1, por defecto): solo a [radioMismaDireccionMetros] o más. A menos de eso, el alta
  ///   y la modificación solo ofrecen abrir la existente, y en el scan el par se resuelve marcando
  ///   el duplicado. La de cercanía (otra dirección a menos de [radioMetros]) siempre se admite.
  /// - `true` (la regla anterior a D1, opción (c)): a cualquier distancia, como cualquier
  ///   candidata. Ya no es la decisión; queda para que los tests prueben los dos valores.
  static const mismaDireccionAdmiteConservarAmbosPorDefecto = false;

  /// Ver [mismaDireccionAdmiteConservarAmbosPorDefecto].
  final bool mismaDireccionAdmiteConservarAmbos;

  final bool _soloSinConservarAmbos;

  /// El criterio para un pedido que ya vio las candidatas y eligió seguir con las dos ("Crear
  /// igual", "seguir igual"): solo frenan las que no lo admiten (D1: la misma dirección a menos de
  /// [radioMismaDireccionMetros]). `null` si ninguna puede frenarlo (con la misma dirección
  /// admitida a cualquier distancia, no se busca nada).
  CriterioDuplicadoUbicacion? get alSeguirIgual => mismaDireccionAdmiteConservarAmbos
      ? null
      : const CriterioDuplicadoUbicacion._soloSinConservarAmbos();

  /// Si es el criterio de [alSeguirIgual] (para el log del alta y de la edición).
  bool get esSeguirIgual => _soloSinConservarAmbos;

  /// [existente] como candidata a duplicado de [nueva], o `null` si no lo es.
  CandidataDuplicado? comparar(Ubicacion nueva, Ubicacion existente) {
    if (existente.id == nueva.id || existente.estaBorrada) return null;
    final distancia = nueva.coordenadas.distanciaMetrosA(existente.coordenadas);
    final motivo = _motivo(nueva, existente, distancia);
    if (motivo == null) return null;
    final candidata = CandidataDuplicado(
      ubicacion: existente,
      motivo: motivo,
      distanciaMetros: distancia,
      admiteConservarAmbos: _admiteConservarAmbos(motivo, distancia),
    );
    return _soloSinConservarAmbos && candidata.admiteConservarAmbos ? null : candidata;
  }

  /// Las candidatas a duplicado de [nueva] entre [existentes], de la más cercana a la más lejana
  /// (vista 04: se rotulan A, B… en ese orden).
  List<CandidataDuplicado> candidatas(Ubicacion nueva, Iterable<Ubicacion> existentes) {
    final encontradas = [for (final existente in existentes) ?comparar(nueva, existente)];
    encontradas.sort((x, y) => x.distanciaMetros.compareTo(y.distanciaMetros));
    return encontradas;
  }

  /// Scan de HU-UBI-006: los pares de posibles duplicados entre [ubicaciones], cada par una sola
  /// vez. Las bajas no participan. Primero los de [MotivoDuplicado.mismaDireccion] y después los
  /// de [MotivoDuplicado.cercania] (el orden de la vista 10), y dentro de cada motivo del más
  /// cercano al más lejano. En cada par, `a` es la más vieja (ver [ParDuplicado]).
  ///
  /// Sin comparar todas contra todas: la misma dirección se agrupa por clave y la cercanía barre
  /// las ubicaciones ordenadas por latitud.
  List<ParDuplicado> pares(Iterable<Ubicacion> ubicaciones) {
    final activas = [
      for (final u in ubicaciones)
        if (!u.estaBorrada) u,
    ];
    final pares = <String, ParDuplicado>{};
    void agregar(Ubicacion x, Ubicacion y) {
      final clave = ParDuplicado.claveDe(x.id, y.id);
      if (x.id == y.id || pares.containsKey(clave)) return;
      final (a, b) = _masViejaPrimero(x, y);
      final distancia = a.coordenadas.distanciaMetrosA(b.coordenadas);
      final motivo = _motivo(a, b, distancia);
      if (motivo == null) return;
      pares[clave] = ParDuplicado(
        a: a,
        b: b,
        motivo: motivo,
        distanciaMetros: distancia,
        admiteConservarAmbos: _admiteConservarAmbos(motivo, distancia),
      );
    }

    final porDireccion = <String, List<Ubicacion>>{};
    for (final u in activas) {
      final clave = _claveDireccion(u);
      if (clave != null) (porDireccion[clave] ??= []).add(u);
    }
    for (final grupo in porDireccion.values) {
      for (var i = 0; i < grupo.length; i++) {
        for (var j = i + 1; j < grupo.length; j++) {
          agregar(grupo[i], grupo[j]);
        }
      }
    }

    final porLatitud = [...activas]..sort((x, y) => x.lat.compareTo(y.lat));
    for (var i = 0; i < porLatitud.length; i++) {
      for (var j = i + 1; j < porLatitud.length; j++) {
        // Más de [radioMetros] solo en latitud: ni esta ni las siguientes están cerca.
        if ((porLatitud[j].lat - porLatitud[i].lat) * _metrosPorGradoLatitud > _cotaBarrido) break;
        agregar(porLatitud[i], porLatitud[j]);
      }
    }

    return pares.values.toList()..sort((x, y) {
      final porMotivo = x.motivo.index.compareTo(y.motivo.index);
      return porMotivo != 0 ? porMotivo : x.distanciaMetros.compareTo(y.distanciaMetros);
    });
  }

  /// Calle o número para comparar duplicados: la normalización de la HU, la misma que
  /// `direccion_normalizada()` del servidor (migración 0017 de backend-supabase). Sin tildes (y
  /// `ñ → n`, `ç → c`, `æ → ae`, `ß → ss`…), cada espacio raro (tab, espacio duro, saltos de línea,
  /// los de [_espaciosUnicode]) pasa a un espacio común, los seguidos se juntan en uno, sin
  /// espacios en los bordes y en minúsculas: «  Av.  Itália » y «av. italia» dan lo mismo. Vacío
  /// si no queda nada.
  static String normalizarDireccion(String texto) =>
      _sinTildes(texto.toLowerCase()).replaceAll(_espaciosUnicode, ' ').trim();

  /// Los caracteres que el servidor trata como espacio al normalizar una dirección:
  /// `[\u0009-\u000d \u0085    -     　﻿]+`.
  static final _espaciosUnicode = RegExp('[\u0009-\u000d \u0085   -     　﻿]+');

  /// Cada letra sin tilde y las que la reemplazan (todas en minúscula: el texto ya lo está).
  /// Latin-1 y Latin Extended-A, el alfabeto de las calles de la región; el resto pasa igual.
  static const _gruposSinTildes = {
    'a': 'àáâãäåāăąǎ',
    'c': 'çćĉċč',
    'd': 'ďđ',
    'e': 'èéêëēĕėęě',
    'g': 'ĝğġģ',
    'h': 'ĥħ',
    'i': 'ìíîïĩīĭį',
    'j': 'ĵ',
    'k': 'ķ',
    'l': 'ĺļľŀł',
    'n': 'ñńņň',
    'o': 'òóôõöøōŏő',
    'r': 'ŕŗř',
    's': 'śŝşš',
    't': 'ţťŧ',
    'u': 'ùúûüũūŭůűų',
    'w': 'ŵ',
    'y': 'ýÿŷ',
    'z': 'źżž',
    'ae': 'æ',
    'oe': 'œ',
    'ss': 'ß',
    'ij': 'ĳ',
  };

  static final Map<int, String> _sinTildesPorLetra = {
    for (final MapEntry(key: base, value: letras) in _gruposSinTildes.entries)
      for (final letra in letras.runes) letra: base,
  };

  /// [texto] (ya en minúsculas) sin tildes ni diéresis. También saca las marcas combinantes
  /// (U+0300 a U+036F): «i» más «◌́» (un teclado que escribe la tilde aparte) da «i».
  static String _sinTildes(String texto) {
    final buffer = StringBuffer();
    for (final rune in texto.runes) {
      if (rune >= 0x0300 && rune <= 0x036f) continue;
      buffer.write(_sinTildesPorLetra[rune] ?? String.fromCharCode(rune));
    }
    return buffer.toString();
  }

  static final _espacios = RegExp(r'\s+');

  /// [texto] en minúsculas, sin acentos ni diéresis, con `ñ → n` y los espacios colapsados: la
  /// normalización de [normalizarDireccion], la de la búsqueda de la lista
  /// (`ArmadorListaUbicaciones`).
  static String normalizar(String texto) =>
      _sinTildes(texto.toLowerCase()).trim().replaceAll(_espacios, ' ');

  /// Metros por grado de latitud con el mismo radio que la haversine de
  /// `Coordenadas.distanciaMetrosA`: con la misma longitud, la distancia es exactamente esta.
  static const _metrosPorGradoLatitud = Coordenadas.radioTierraMetros * math.pi / 180;

  /// El barrido de [pares] corta con 1 % de margen sobre [radioMetros], para que el redondeo no
  /// deje afuera un par a 4,99 m.
  static const _cotaBarrido = radioMetros * 1.01;

  MotivoDuplicado? _motivo(Ubicacion x, Ubicacion y, double distanciaMetros) {
    final direccion = _claveDireccion(x);
    if (direccion != null && direccion == _claveDireccion(y)) return MotivoDuplicado.mismaDireccion;
    return distanciaMetros < radioMetros ? MotivoDuplicado.cercania : null;
  }

  /// D1: la de cercanía siempre; la de misma dirección solo a [radioMismaDireccionMetros] o más
  /// (o con [mismaDireccionAdmiteConservarAmbos], la regla anterior).
  bool _admiteConservarAmbos(MotivoDuplicado motivo, double distanciaMetros) =>
      motivo == MotivoDuplicado.cercania ||
      mismaDireccionAdmiteConservarAmbos ||
      distanciaMetros >= radioMismaDireccionMetros;

  /// Ciudad, calle y número normalizados, o `null` si falta la calle o el número.
  static String? _claveDireccion(Ubicacion u) {
    final calle = u.calle, numero = u.numero;
    if (calle == null || numero == null) return null;
    final c = normalizarDireccion(calle), n = normalizarDireccion(numero);
    if (c.isEmpty || n.isEmpty) return null;
    // Separador que no aparece en un texto escrito a mano.
    return '${u.ciudadId}\u0000$c\u0000$n';
  }

  static (Ubicacion, Ubicacion) _masViejaPrimero(Ubicacion x, Ubicacion y) {
    final porFecha = x.auditoria.createdAt.compareTo(y.auditoria.createdAt);
    final xPrimero = porFecha != 0 ? porFecha < 0 : x.id.compareTo(y.id) <= 0;
    return xPrimero ? (x, y) : (y, x);
  }
}
