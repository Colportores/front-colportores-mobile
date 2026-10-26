/// Por qué la persistencia rechazó fijar o quitar la ubicación alternativa de cobranza de una persona
/// (HU-UBI-013).
///
/// Los decide la capa `data` dentro de la transacción (donde puede leer el estado real de la DB) y el
/// repositorio los traduce a un `FailureValidacion` con el [campo] y el [mensaje] de acá. Los
/// mensajes dicen qué pasa y qué hacer; la HU no escribe ninguno, así que van «a confirmar».
enum MotivoRechazoUbicacionAlternativa {
  /// La persona ya no está en ese espacio del teléfono (o su vínculo está de baja).
  vinculoInexistente(
    'persona',
    'La persona ya no está en este espacio de tu teléfono. Volvé atrás.',
  ),

  /// Una persona de baja es de solo lectura (HU-UBI-011): reactivarla es lo que la habilita.
  personaDeBaja('persona', 'La persona está dada de baja: reactivala para cambiar dónde cobrarle.'),
  espacioDeBaja(
    'espacio',
    'Espacio dado de baja: solo lectura. Restauralo para cambiar dónde cobrarle a sus clientes.',
  ),
  ubicacionDelEspacioDeBaja(
    'espacio',
    'La ubicación está dada de baja: reactivala para cambiar dónde cobrarle a sus clientes.',
  ),

  /// La elegida no existe en el teléfono: no se inventa una referencia a algo que no se puede mostrar.
  ubicacionInexistente(
    'ubicacionAlternativa',
    'Esa ubicación ya no está en tu teléfono. Elegí otra.',
  ),

  /// Solo se eligen ubicaciones registradas por quien cobra («también registrada por mí», HU-UBI-013).
  ubicacionAjena(
    'ubicacionAlternativa',
    'Solo podés elegir una ubicación que registraste vos. Elegí otra.',
  ),

  /// La referenciada tiene que estar activa (`deleted_at IS NULL`).
  ubicacionDeBaja(
    'ubicacionAlternativa',
    'Esa ubicación está dada de baja. Reactivala o elegí otra.',
  ),

  /// Caso borde de la HU: la propia ubicación del espacio de la persona como alternativa no tiene
  /// sentido.
  esLaDelEspacio(
    'ubicacionAlternativa',
    'Esa es la ubicación donde vive la persona. Elegí otra o quitá la alternativa.',
  );

  const MotivoRechazoUbicacionAlternativa(this.campo, this.mensaje);

  /// Campo del formulario al que se asocia el mensaje.
  final String campo;

  final String mensaje;
}
