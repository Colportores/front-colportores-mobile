/// Dónde queda la nota que la colportora escribe mientras la entrevista sigue en curso (vista 39,
/// R·05; decisión de Cristian, 25/10, front-colportores-mobile#450, «Nota entrev.»): **en el
/// teléfono, cifrada** (la base local), junto a la entrevista abierta. Si cierra la app, la
/// encuentra al volver; al guardar la visita pasa a ser su nota; **nunca sube**.
///
/// Las operaciones **lanzan** si la base falla: quien las llama las traduce (la nota sigue en memoria).
abstract interface class BorradorDeNotaDeEntrevista {
  /// El texto guardado de la nota [notaId], o `''` si no hay (o está en blanco).
  Future<String> leer(String notaId);

  /// Guarda [texto] como el borrador de la nota [notaId], que será la de la visita [visitaId] (los
  /// ids los fijó la entrevista al empezar). En blanco, borra el borrador: no queda una nota vacía.
  Future<void> guardar({
    required String notaId,
    required String visitaId,
    required String colportorId,
    required String texto,
    required DateTime ahora,
  });

  /// Borra el borrador [notaId] (la entrevista se descartó).
  Future<void> borrar(String notaId);
}
