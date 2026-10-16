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
  /// un texto para el colportor; la Lista y la hoja de reactivar muestran [unidaAOtra] en su lugar.
  static const prefijoDuplicado = 'duplicado_de_';

  /// Lo que dice la Lista en el lugar del motivo de una baja por unión de duplicados (HU-UBI-005,
  /// «Reactivar»; decisión del orquestador, 09/10, front-colportores-mobile#205): nunca el código
  /// ni el uuid.
  static const unidaAOtra = 'Unida a otra ubicación';

  /// El motivo como se guarda: el texto recortado, o `null` si no hay (un motivo vacío no se guarda).
  static String? paraGuardar(String? motivo) {
    final recortado = motivo?.trim();
    return recortado == null || recortado.isEmpty ? null : recortado;
  }

  /// Si [guardado] es el motivo de una baja por unión de duplicados (empieza con
  /// [prefijoDuplicado]). Una baja así no se reactiva: la unión es definitiva.
  static bool esUnion(String? guardado) =>
      paraGuardar(guardado)?.startsWith(prefijoDuplicado) ?? false;

  /// El uuid de la ubicación que se conservó, si [guardado] es el motivo de una unión
  /// (`duplicado_de_<A>` -> `<A>`); `null` si no es una unión o no trae uuid.
  static String? conservadaDe(String? guardado) {
    final motivo = paraGuardar(guardado);
    if (motivo == null || !esUnion(motivo)) return null;
    final id = motivo.substring(prefijoDuplicado.length).trim();
    return id.isEmpty ? null : id;
  }

  /// El motivo como se muestra en la Lista y en la hoja de reactivar: `null` si no hay y
  /// [unidaAOtra] si es el de una unión de duplicados.
  static String? paraMostrar(String? guardado) {
    final motivo = paraGuardar(guardado);
    if (motivo == null) return null;
    return esUnion(motivo) ? unidaAOtra : motivo;
  }
}
