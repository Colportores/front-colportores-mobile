/// Los motivos de la baja de una ubicación (HU-UBI-005, canvas 09·01, «MOTIVO · OBLIGATORIO»).
///
/// El motivo que se guarda es el texto mismo: uno de los tres rápidos o, con «Otro», lo que el
/// colportor escribió (o «Otro» si no escribió nada). Va al `audit_log` local (R-UB09) y a la fila de
/// la Lista y de la hoja de reactivar; **nunca** a los logs ni a la telemetría.
abstract final class MotivosBaja {
  static const yaNoExiste = 'Ya no existe';
  static const estaDeshabitada = 'Está deshabitada';
  static const noQuiereVisitas = 'No quiere visitas';
  static const otro = 'Otro';

  /// Los que se eligen con un toque, en el orden del canvas.
  static const rapidos = [yaNoExiste, estaDeshabitada, noQuiereVisitas];

  /// Cuántos caracteres puede tener el texto de «Otro».
  static const maximoOtro = 120;

  /// El prefijo del motivo de una baja por unión de duplicados (`duplicado_de_A`, HU-UBI-006): no es
  /// un texto para el colportor, así que la Lista y la hoja de reactivar no lo muestran.
  static const prefijoDuplicado = 'duplicado_de_';

  /// El motivo como se guarda: el texto recortado, o `null` si no hay (un motivo vacío no se guarda).
  static String? paraGuardar(String? motivo) {
    final recortado = motivo?.trim();
    return recortado == null || recortado.isEmpty ? null : recortado;
  }

  /// El motivo como se muestra en la Lista y en la hoja de reactivar: `null` si no hay o si es el de
  /// una unión de duplicados.
  static String? paraMostrar(String? guardado) {
    final motivo = paraGuardar(guardado);
    if (motivo == null || motivo.startsWith(prefijoDuplicado)) return null;
    return motivo;
  }
}
