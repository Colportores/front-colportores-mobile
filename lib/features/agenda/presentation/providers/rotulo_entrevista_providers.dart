import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../mapa/presentation/formato_ubicaciones.dart';
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../domain/entities/entrevista_en_curso.dart';

/// Con qué lugar y con quién es una entrevista, para los títulos de las hojas y el aviso del mapa:
/// «Grecia 3307» y «Pedro Gómez». Se leen de la DB al mostrarlos (la entrevista guarda solo ids). Un
/// dato que ya no está en el teléfono (el espacio o la persona dados de baja) queda vacío: la
/// pantalla dice lo que sabe y no inventa el resto.
typedef RotuloEntrevista = ({String direccion, String persona});

final rotuloDeEntrevistaProvider = FutureProvider.autoDispose
    .family<RotuloEntrevista, EntrevistaEnCurso>((ref, entrevista) async {
      var direccion = '';
      var persona = '';
      try {
        final contexto = await ref.watch(contextoEspacioProvider(entrevista.espacioId).future);
        if (contexto != null) {
          direccion = FormatoUbicaciones.direccionPropia(contexto.ubicacion);
        }
      } on Object {
        // Sin dirección: el título dice «Entrevista en curso» a secas.
      }
      try {
        final personas = await ref.watch(personasDelEspacioProvider(entrevista.espacioId).future);
        for (final p in personas) {
          if (p.vinculo.id == entrevista.espacioPersonaId) {
            persona = [
              p.persona.nombre,
              p.persona.apellido,
            ].where((t) => t.trim().isNotEmpty).join(' ');
            break;
          }
        }
      } on Object {
        // Sin nombre: idem.
      }
      return (direccion: direccion, persona: persona);
    });
