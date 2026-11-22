import 'package:flutter/material.dart';

import '../../domain/entities/nota_ubicacion.dart';
import '../../domain/usecases/notas_ubicacion_use_cases.dart';
import '../providers/notas_ubicacion_providers.dart';
import 'formulario_de_nota_page.dart';

/// Lo que devuelve el formulario de una nota de un lugar: la nota guardada y si era nueva o una
/// edición.
typedef NotaDelLugarGuardada = NotaGuardadaDe<NotaUbicacion>;

/// «Nueva nota» y «Editar nota» de un lugar (vista 39, C·05; las pantallas son las de la vista 32E,
/// E·02 y E·07): el [FormularioDeNotaPage] con los casos de uso de las notas de un lugar. Todo se
/// guarda en el teléfono —la nota no se sincroniza—.
///
/// Devuelve la [NotaDelLugarGuardada] (o `null` si se cerró sin guardar).
class NotaUbicacionFormPage extends StatelessWidget {
  const NotaUbicacionFormPage({
    super.key,
    required this.ubicacionId,
    required this.colportorId,
    this.nota,
  });

  /// El lugar dueño de la nota.
  final String ubicacionId;

  /// UUID del usuario con la sesión iniciada (`created_by` de una nota nueva).
  final String colportorId;

  /// La nota que se edita, o `null` para una nueva.
  final NotaUbicacion? nota;

  /// Abre el formulario encima de la pantalla actual.
  static Future<NotaDelLugarGuardada?> abrir(
    BuildContext context, {
    required String ubicacionId,
    required String colportorId,
    NotaUbicacion? nota,
  }) => Navigator.of(context).push<NotaDelLugarGuardada>(
    MaterialPageRoute(
      builder: (_) =>
          NotaUbicacionFormPage(ubicacionId: ubicacionId, colportorId: colportorId, nota: nota),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final original = nota;
    return FormularioDeNotaPage<NotaUbicacion>(
      colportorId: colportorId,
      nota: original,
      camposDelMotivo: const ['ubicacion', 'nota'],
      guardar: (ref, texto, id) => original != null
          ? ref.read(editarNotaUbicacionUseCaseProvider)(
              EditarNotaUbicacionParams(notaId: original.id, texto: texto),
            )
          : ref.read(agregarNotaUbicacionUseCaseProvider)(
              AgregarNotaUbicacionParams(
                id: id,
                ubicacionId: ubicacionId,
                colportorId: colportorId,
                texto: texto,
              ),
            ),
    );
  }
}
