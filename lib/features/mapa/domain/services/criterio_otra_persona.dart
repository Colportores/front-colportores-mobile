import '../entities/persona.dart';

/// Los datos que el colportor dejó en el formulario de edición, tal cual los escribió.
typedef DatosDePersona = ({String nombre, String apellido, String telefono});

/// Cuándo un cambio a una persona es «demasiado grande» y conviene preguntar «¿Es otra persona?»
/// (HU-UBI-010, caso borde; canvas 32C·03).
///
/// **Pendiente «Cristian §3: regla de negocio»**: la HU dice solo que «la UI sugiere usar baja + alta si
/// parece "otra persona"», y el canvas pregunta «¿Cuándo un cambio es "demasiado grande"? Propuesta:
/// cambian el nombre y el apellido a la vez. No está definido». Hasta que se decida, la única
/// implementación es [CriterioOtraPersonaSinDefinir]: no sugiere nada, así que el cambio se guarda
/// directo. Es el único lugar donde vive la regla: cuando se decida, se cambia el provider que la
/// entrega (`criterioOtraPersonaProvider`) y nada más.
abstract interface class CriterioOtraPersona {
  /// `true` si pasar de [antes] a [despues] parece otra persona y hay que sugerir dar de baja a la
  /// de antes y registrar a la nueva por separado.
  bool pareceOtraPersona(Persona antes, DatosDePersona despues);
}

/// Mientras la regla no esté decidida, ningún cambio parece «otra persona»: nunca se frena ni se
/// regaña a la colportora por un cambio que puede ser un arreglo legítimo.
final class CriterioOtraPersonaSinDefinir implements CriterioOtraPersona {
  const CriterioOtraPersonaSinDefinir();

  @override
  bool pareceOtraPersona(Persona antes, DatosDePersona despues) => false;
}
