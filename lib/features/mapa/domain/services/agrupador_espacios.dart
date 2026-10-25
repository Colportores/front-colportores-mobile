import 'package:equatable/equatable.dart';

import '../entities/espacio.dart';

/// Los espacios de un edificio que comparten piso (vista 11·01, «PISO 1», «SIN PISO»).
final class GrupoDePiso extends Equatable {
  const GrupoDePiso({required this.piso, required this.espacios});

  /// El piso tal como se escribió (el del primer espacio del grupo); `null` en «Sin piso».
  final String? piso;

  /// En el orden en que se ven: con número, de menor a mayor, y después los sin número, en el orden
  /// en que se dieron de alta.
  final List<Espacio> espacios;

  bool get sinPiso => piso == null;

  @override
  List<Object?> get props => [piso, espacios];
}

/// Arma los grupos de la lista de deptos de un edificio (vista 11·01).
///
/// - Los pisos van en orden natural («2» antes que «10»): primero «PB» (la planta baja, con o sin
///   mayúsculas), después los números y después los otros textos de la A a la Z; «Sin piso» al final.
/// - «1», « 1 » y «1» son el mismo piso; «pb» y «PB» también. Del piso el guion sí cuenta («-1» es el
///   subsuelo, no el piso 1).
/// - Dentro de un piso, los deptos con número van en orden natural («2B» antes que «10A») y, después,
///   los que no tienen número, en el orden en que se dieron de alta (HU-UBI-007: «todos como “Sin
///   número”, en el orden en que se dieron de alta», sin contador).
abstract final class AgrupadorEspacios {
  static List<GrupoDePiso> porPiso(Iterable<Espacio> espacios) {
    final grupos = <String, List<Espacio>>{};
    final nombres = <String, String>{};
    final sinPiso = <Espacio>[];
    for (final espacio in espacios) {
      final piso = espacio.piso?.trim();
      final clave = _clavePiso(piso);
      if (piso == null || clave == null) {
        sinPiso.add(espacio);
        continue;
      }
      grupos.putIfAbsent(clave, () => []).add(espacio);
      nombres.putIfAbsent(clave, () => piso);
    }
    final claves = grupos.keys.toList()..sort(_compararPisos);
    return [
      for (final clave in claves)
        GrupoDePiso(piso: nombres[clave], espacios: _ordenar(grupos[clave]!)),
      if (sinPiso.isNotEmpty) GrupoDePiso(piso: null, espacios: _ordenar(sinPiso)),
    ];
  }

  /// La clave de un piso: sin espacios y sin distinguir mayúsculas; `null` si no hay piso.
  static String? _clavePiso(String? piso) {
    final limpio = piso?.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }

  /// Planta baja.
  static const _clavePlantaBaja = 'pb';

  /// «PB» antes que cualquier otro piso; el resto, en orden natural.
  static int _compararPisos(String a, String b) {
    final aPb = a == _clavePlantaBaja;
    final bPb = b == _clavePlantaBaja;
    if (aPb != bPb) return aPb ? -1 : 1;
    return _compararNatural(a, b);
  }

  static List<Espacio> _ordenar(List<Espacio> espacios) {
    final conNumero = espacios.where((e) => !e.sinNumero).toList()
      ..sort((a, b) {
        final c = _compararNatural(a.clave!, b.clave!);
        return c != 0 ? c : _porAlta(a, b);
      });
    final sinNumero = espacios.where((e) => e.sinNumero).toList()..sort(_porAlta);
    return [...conNumero, ...sinNumero];
  }

  static int _porAlta(Espacio a, Espacio b) {
    final c = a.auditoria.createdAt.compareTo(b.auditoria.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  /// Compara por trozos: los números por valor y el resto por texto; un trozo numérico va antes que
  /// uno de texto («1» antes que «PB»).
  static int _compararNatural(String a, String b) {
    final ta = _trozos(a);
    final tb = _trozos(b);
    for (var i = 0; i < ta.length && i < tb.length; i++) {
      final x = ta[i];
      final y = tb[i];
      final xNumero = _esNumero(x);
      final yNumero = _esNumero(y);
      final int c;
      if (xNumero && yNumero) {
        c = _compararNumeros(x, y);
      } else if (xNumero != yNumero) {
        c = xNumero ? -1 : 1;
      } else {
        c = x.compareTo(y);
      }
      if (c != 0) return c;
    }
    return ta.length.compareTo(tb.length);
  }

  static final _patron = RegExp(r'\d+|\D+');

  static List<String> _trozos(String texto) => [for (final m in _patron.allMatches(texto)) m[0]!];

  static bool _esNumero(String trozo) => trozo.codeUnitAt(0) >= 48 && trozo.codeUnitAt(0) <= 57;

  /// Compara dos números de cualquier largo sin pasarlos a `int`: sin ceros de la izquierda, el más
  /// largo es el mayor.
  static int _compararNumeros(String a, String b) {
    final x = a.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final y = b.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return x.length != y.length ? x.length.compareTo(y.length) : x.compareTo(y);
  }
}
