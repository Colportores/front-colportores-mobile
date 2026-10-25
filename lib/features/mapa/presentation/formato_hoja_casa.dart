import '../domain/entities/lista_ubicaciones.dart';
import 'formato_baja.dart';
import 'formato_mapa_ubicaciones.dart';
import 'formato_ubicaciones.dart';
import 'widgets/estados_hoja_casa.dart';

/// Los textos de la hoja de la casa (vista 39, C·01 «Tocar una casa: resumen»). Los del canvas van
/// letra por letra; los que el canvas no dibuja están marcados «a confirmar» y se listan en el PR.
abstract final class TextosHojaCasa {
  // Del canvas (C·01).
  static const notaDelLugar = 'NOTA DEL LUGAR';
  static const registrarVisita = 'Registrar visita';
  static const cobrar = r'$ Cobrar';

  /// El tilde del botón, que el canvas escribe delante del rótulo con dos espacios: «✓  Registrar
  /// visita». Es decoración: el lector de pantalla solo dice [registrarVisita].
  static const tildeDelBoton = '✓';

  /// A confirmar (mapa §2: texto): lo que dice la hoja si el destino de «Registrar visita» o de
  /// «$ Cobrar» no se pudo abrir. El canvas no dibuja el error.
  static const noPudimosAbrirVisita = 'No pudimos abrir «Registrar visita». Probá de nuevo.';
  static const noPudimosAbrirCobro = 'No pudimos abrir «\$ Cobrar». Probá de nuevo.';

  /// Lo que lee el lector de pantalla del botón de cobrar de [nombre]: lleva el rótulo visible
  /// «$ Cobrar» y a quién (hay una fila por persona).
  static String cobrarA(String nombre) => '$cobrar a $nombre';

  /// «Debe $ 1.200» (el canvas no usa «$U» en la 39).
  static String debe(int centavos) => 'Debe ${monto(centavos)}';

  /// «$ 1.200»: pesos con punto de miles y, si no son pesos justos, coma decimal.
  static String monto(int centavos) => FormatoBaja.monto(centavos).replaceFirst(r'$U', r'$');
}

/// Cómo se escribe la hoja de la casa a partir de la ubicación y su contexto.
abstract final class FormatoHojaCasa {
  /// La línea chica debajo de la dirección (canvas: «Casa · Cobranza pendiente · a 20 m de vos»): el
  /// tipo, el estado si se sabe (nunca uno que no se sabe) y la distancia si hay GPS. Una casa dada de
  /// baja dice «Casa · dada de baja el 18/10» y no su estado (E·04).
  static String subtitulo(ItemListaUbicacion item, DateTime ahora) {
    final ubicacion = item.ubicacion;
    final baja = ubicacion.auditoria.deletedAt;
    if (item.esBaja && baja != null) {
      return TextosEstadosHojaCasa.subtituloDeBaja(ubicacion.tipo, baja);
    }
    final estado = item.estado;
    final distancia = item.distanciaMetros;
    final partes = [
      FormatoUbicaciones.tipo(ubicacion.tipo),
      if (estado != null)
        FormatoMapaUbicaciones.estadoVistaPrevia(estado, item.proximaEntrevista, ahora),
      if (distancia != null && FormatoUbicaciones.distancia(distancia).isNotEmpty)
        'a ${FormatoUbicaciones.distancia(distancia)} de vos',
    ];
    return partes.join(' · ');
  }
}
