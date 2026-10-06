import '../domain/entities/ubicacion.dart';
import '../domain/value_objects/coordenadas.dart';

/// Textos de ubicaciones que comparten las vistas del mapa (03, 04, y las que siguen).
abstract final class FormatoUbicaciones {
  static String tipo(TipoUbicacion tipo) => switch (tipo) {
    TipoUbicacion.casa => 'Casa',
    TipoUbicacion.negocio => 'Negocio',
    TipoUbicacion.edificio => 'Edificio',
  };

  /// «12 m», o «1,2 km» desde el kilómetro. Nunca «0 m»: lo que está a menos de 1 m se ve como «1 m».
  /// Entre el número y la unidad va un espacio duro ([espacioDuro]): en un renglón angosto la unidad
  /// no queda sola.
  static String distancia(double metros) {
    if (!metros.isFinite || metros < 0) return '';
    if (metros >= 1000) {
      return '${(metros / 1000).toStringAsFixed(1).replaceAll('.', ',')}${espacioDuro}km';
    }
    final redondeado = metros.round();
    return '${redondeado < 1 ? 1 : redondeado}${espacioDuro}m';
  }

  /// El espacio que no deja partir el renglón (U+00A0).
  static const espacioDuro = '\u00A0';

  /// El rótulo de la candidata número [indice] (desde 0) de la vista 04: «A» … «Z», «AA», «AB» …,
  /// como las columnas de una planilla. Lo usan la lista, el pin del mapa, la leyenda y la etiqueta
  /// para el lector de pantalla, para que digan lo mismo con cualquier cantidad de candidatas.
  static String rotuloCandidata(int indice) {
    if (indice < 0) return '';
    final letras = <int>[];
    var resto = indice;
    do {
      letras.add(65 + resto % 26);
      resto = resto ~/ 26 - 1;
    } while (resto >= 0);
    return String.fromCharCodes(letras.reversed);
  }

  /// «Av. Italia 1234»; solo la calle o solo el número si falta uno; «Sin dirección» si no hay
  /// ninguno.
  static String direccion(Ubicacion u) {
    final partes = [
      for (final p in [u.calle, u.numero])
        if (p != null && p.trim().isNotEmpty) p.trim(),
    ];
    return partes.isEmpty ? 'Sin dirección' : partes.join(' ');
  }

  /// «-34.88761, -56.13024» (5 decimales: cerca del metro).
  static String coordenadas(Coordenadas c) =>
      '${c.lat.toStringAsFixed(5)}, ${c.lon.toStringAsFixed(5)}';

  /// «hace 3 días»: cuánto pasó entre [desde] y [hasta].
  static String hace(DateTime desde, DateTime hasta) {
    final d = hasta.difference(desde);
    if (d.isNegative || d.inMinutes < 1) return 'hace un momento';
    if (d.inMinutes < 60) return d.inMinutes == 1 ? 'hace 1 minuto' : 'hace ${d.inMinutes} minutos';
    if (d.inHours < 24) return d.inHours == 1 ? 'hace 1 hora' : 'hace ${d.inHours} horas';
    if (d.inDays < 30) return d.inDays == 1 ? 'hace 1 día' : 'hace ${d.inDays} días';
    final meses = d.inDays ~/ 30;
    if (meses < 12) return meses == 1 ? 'hace 1 mes' : 'hace $meses meses';
    final anios = d.inDays ~/ 365;
    return anios <= 1 ? 'hace 1 año' : 'hace $anios años';
  }
}
