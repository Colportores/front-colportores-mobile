import 'package:flutter/material.dart';

import '../../domain/entities/nota_persona.dart';
import '../../domain/usecases/notas_persona_use_cases.dart';
import '../providers/notas_persona_providers.dart';
import 'formulario_de_nota_page.dart';

/// Lo que devuelve el formulario de una nota de una persona: la nota guardada y si era nueva o una
/// edición.
typedef NotaGuardada = NotaGuardadaDe<NotaPersona>;

/// «Nueva nota» y «Editar nota» de una persona (HU-UBI-012, vista 32E, artboards E·02 y E·07): el
/// [FormularioDeNotaPage] con los casos de uso de las notas de una persona. Todo se guarda en el
/// teléfono —la nota no se sincroniza—.
///
/// Devuelve la [NotaGuardada] (o `null` si se cerró sin guardar).
class NotaPersonaFormPage extends StatelessWidget {
  const NotaPersonaFormPage({
    super.key,
    required this.personaId,
    required this.colportorId,
    this.nota,
  });

  /// La persona dueña de la nota.
  final String personaId;

  /// UUID del usuario con la sesión iniciada (`created_by` de una nota nueva).
  final String colportorId;

  /// La nota que se edita, o `null` para una nueva.
  final NotaPersona? nota;

  /// Abre el formulario encima de la pantalla actual.
  static Future<NotaGuardada?> abrir(
    BuildContext context, {
    required String personaId,
    required String colportorId,
    NotaPersona? nota,
  }) => Navigator.of(context).push<NotaGuardada>(
    MaterialPageRoute(
      builder: (_) =>
          NotaPersonaFormPage(personaId: personaId, colportorId: colportorId, nota: nota),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final original = nota;
    return FormularioDeNotaPage<NotaPersona>(
      colportorId: colportorId,
      nota: original,
      camposDelMotivo: const ['persona', 'nota'],
      guardar: (ref, texto, id) => original != null
          ? ref.read(editarNotaPersonaUseCaseProvider)(
              EditarNotaPersonaParams(notaId: original.id, texto: texto),
            )
          : ref.read(agregarNotaPersonaUseCaseProvider)(
              AgregarNotaPersonaParams(
                id: id,
                personaId: personaId,
                colportorId: colportorId,
                texto: texto,
              ),
            ),
    );
  }
}
