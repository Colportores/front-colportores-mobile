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
/// Calle y número se comparan con [normalizarDireccion] (sin espacios en los bordes y en
/// minúsculas, la misma normalización que el índice único de la opción (a) de D1,
/// backend-supabase#24). Si falta la calle o el número en alguna de las dos, solo cuenta la
/// distancia. En la DB queda lo que escribió el colportor.
///
/// Es un aviso, no un bloqueo, salvo lo que decida D1 para la misma dirección: ver
/// [mismaDireccionAdmiteConservarAmbos].
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

  /// **Punto único de la decisión D1** (backend-supabase#24): si dos ubicaciones con la misma
  /// dirección pueden quedar las dos ("Crear igual", "seguir igual", "Conservar ambos").
  ///
  /// - `true` (hoy, opción (c) y vistas 04/10): sí, como cualquier candidata.
  /// - `false` (opción (a), recomendada): no. El alta y la modificación con la misma dirección
  ///   solo ofrecen abrir la existente, y en el scan el par se resuelve marcando el duplicado.
  ///
  /// Cambiar la decisión es cambiar esta constante; los tests prueban los dos valores.
  static const mismaDireccionAdmiteConservarAmbosPorDefecto = true;

  /// Ver [mismaDireccionAdmiteConservarAmbosPorDefecto].
  final bool mismaDireccionAdmiteConservarAmbos;

  final bool _soloSinConservarAmbos;

  /// El criterio para un pedido que ya vio las candidatas y eligió seguir con las dos ("Crear
  /// igual", "seguir igual"): solo frenan las que no lo admiten. `null` si ninguna puede frenarlo
  /// (con la misma dirección admitida, no se busca nada).
  CriterioDuplicadoUbicacion? get alSeguirIgual => mismaDireccionAdmiteConservarAmbos
      ? null
      : const CriterioDuplicadoUbicacion._soloSinConservarAmbos();

  /// Si es el criterio de [alSeguirIgual] (para el log del alta y de la edición).
  bool get esSeguirIgual => _soloSinConservarAmbos;

  /// [existente] como candidata a duplicado de [nueva], o `null` si no lo es.
  CandidataDuplicado? comparar(Ubicacion nueva, Ubicacion existente) {
    if (existente.id == nueva.id || existente.estaBorrada) return null;
    final motivo = _motivo(nueva, existente);
    if (motivo == null) return null;
    final candidata = CandidataDuplicado(
      ubicacion: existente,
      motivo: motivo,
      distanciaMetros: nueva.coordenadas.distanciaMetrosA(existente.coordenadas),
      admiteConservarAmbos: _admiteConservarAmbos(motivo),
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
      final motivo = _motivo(x, y);
      if (motivo == null) return;
      final (a, b) = _masViejaPrimero(x, y);
      pares[clave] = ParDuplicado(
        a: a,
        b: b,
        motivo: motivo,
        distanciaMetros: a.coordenadas.distanciaMetrosA(b.coordenadas),
        admiteConservarAmbos: _admiteConservarAmbos(motivo),
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

  /// Calle o número para comparar: sin espacios en los bordes y en minúsculas.
  static String normalizarDireccion(String texto) => texto.trim().toLowerCase();

  static const _sinDiacriticos = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', //
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', //
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', //
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', //
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', //
    'ñ': 'n', 'ç': 'c',
  };

  static final _espacios = RegExp(r'\s+');

  /// [texto] en minúsculas, sin acentos ni diéresis, con `ñ → n` y los espacios colapsados. Es
  /// la de la búsqueda de la lista (`ArmadorListaUbicaciones`); los duplicados usan
  /// [normalizarDireccion].
  static String normalizar(String texto) {
    final minusculas = texto.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in minusculas.runes) {
      final caracter = String.fromCharCode(rune);
      buffer.write(_sinDiacriticos[caracter] ?? caracter);
    }
    return buffer.toString().trim().replaceAll(_espacios, ' ');
  }

  /// Metros por grado de latitud con el mismo radio que la haversine de
  /// `Coordenadas.distanciaMetrosA`: con la misma longitud, la distancia es exactamente esta.
  static const _metrosPorGradoLatitud = Coordenadas.radioTierraMetros * math.pi / 180;

  /// El barrido de [pares] corta con 1 % de margen sobre [radioMetros], para que el redondeo no
  /// deje afuera un par a 4,99 m.
  static const _cotaBarrido = radioMetros * 1.01;

  MotivoDuplicado? _motivo(Ubicacion x, Ubicacion y) {
    final direccion = _claveDireccion(x);
    final cerca = x.coordenadas.distanciaMetrosA(y.coordenadas) < radioMetros;
    if (direccion != null && direccion == _claveDireccion(y)) return MotivoDuplicado.mismaDireccion;
    return cerca ? MotivoDuplicado.cercania : null;
  }

  bool _admiteConservarAmbos(MotivoDuplicado motivo) =>
      motivo == MotivoDuplicado.cercania || mismaDireccionAdmiteConservarAmbos;

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
