import '../entities/persona.dart';
import 'criterio_duplicado_ubicacion.dart';

/// Los datos que el colportor dejó en el formulario de edición, tal cual los escribió.
typedef DatosDePersona = ({String nombre, String apellido, String telefono});

/// Cuándo un cambio a una persona parece «otra persona» y conviene preguntarlo (HU-UBI-010, caso
/// borde; canvas 32C·03). Es el único lugar donde vive la regla: la pantalla solo pregunta
/// [pareceOtraPersona] y muestra el aviso; siempre se puede «Guardar igual».
abstract interface class CriterioOtraPersona {
  /// `true` si pasar de [antes] a [despues] parece otra persona y hay que sugerir dar de baja a la
  /// de antes y registrar a la nueva por separado.
  bool pareceOtraPersona(Persona antes, DatosDePersona despues);
}

/// La regla que decidió Cristian el 27/10: el aviso sale cuando cambian el nombre **y** el apellido a
/// la vez.
///
/// - Se compara sin mayúsculas, sin tildes y sin espacios de más (la misma normalización que usa el
///   detector de duplicados): corregir «Fernandez» por «Fernández», en uno o en los dos campos, no
///   cuenta como cambio.
/// - Un apellido que estaba vacío y se completa no cuenta como cambio: es completar un dato, no
///   cambiar de persona. Por lo tanto, ese cambio, por grande que sea el nombre, no muestra el aviso.
/// - Corregir solo el nombre, solo el apellido o solo el teléfono no lo muestra. El teléfono no entra
///   en la regla.
final class CriterioOtraPersonaPorNombreYApellido implements CriterioOtraPersona {
  const CriterioOtraPersonaPorNombreYApellido();

  @override
  bool pareceOtraPersona(Persona antes, DatosDePersona despues) =>
      _cambio(antes.nombre, despues.nombre) &&
      _cambio(antes.apellido, despues.apellido, vacioNoCuenta: true);

  /// `true` si [despues] es otro texto que [antes] una vez normalizados. Con [vacioNoCuenta], un
  /// [antes] vacío (o solo espacios) nunca cuenta como cambiado.
  static bool _cambio(String antes, String despues, {bool vacioNoCuenta = false}) {
    final previo = CriterioDuplicadoUbicacion.normalizar(antes);
    if (vacioNoCuenta && previo.isEmpty) return false;
    return previo != CriterioDuplicadoUbicacion.normalizar(despues);
  }
}
