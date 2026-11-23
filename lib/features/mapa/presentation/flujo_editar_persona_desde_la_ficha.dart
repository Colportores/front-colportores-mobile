import 'package:flutter/material.dart';

import 'pages/alta_persona_page.dart';
import 'pages/modificar_persona_page.dart';
import 'providers/ficha_persona_providers.dart';
import 'textos_baja_persona.dart';
import 'textos_personas.dart';
import 'widgets/hoja_baja_persona.dart';
import 'widgets/piezas_notas.dart' show mostrarAvisoDeNota;

/// «Editar persona» de la ficha (vista 32 B, HU-UBI-009) y «Agregar» teléfono: abre la edición (vista
/// 32 C, HU-UBI-010) y, si ahí se elige «Dar de baja y crear nueva» (canvas 32C·03), sigue como decidió
/// el agente de decisiones el 26/10 (regla R6, #405):
///
/// 1. abre el alta de persona (HU-UBI-008) en el mismo espacio, con el nombre, el apellido y el
///    teléfono ya escritos;
/// 2. solo cuando la persona nueva quedó guardada, abre la baja de la original (vista 32 D, #143), con
///    sus reglas (la cuenta, las dos confirmaciones);
/// 3. si la colportora cancela el alta, no cambia nada; si la baja no se hace (cerró la hoja o falló),
///    la nueva queda registrada y el aviso dice que la original sigue y que se la da de baja desde su
///    ficha.
///
/// Nunca queda la original de baja sin la nueva: la baja se pide **después** del alta.
///
/// Es lo que enchufa `editarPersonaDesdeLaFichaProvider`. Todo se lee y se escribe en el teléfono.
/// Lanza si no hay sesión iniciada (la ficha deja la fila habilitada).
abstract final class FlujoEditarPersonaDesdeLaFicha {
  static Future<void> abrir(
    BuildContext context,
    ContextoDeEdicionDeLaFicha datos, {
    required String? colportorId,
  }) async {
    final colportor = colportorId?.trim() ?? '';
    if (colportor.isEmpty) {
      throw StateError('Editar a una persona necesita una sesión iniciada');
    }
    // Se leen antes de esperar: cuando terminen las pantallas, `context` puede ya no ser el mismo.
    final mensajero = ScaffoldMessenger.of(context);
    final mediaQuery = MediaQuery.of(context);

    // La edición muestra por sí sola «Cambios guardados en tu teléfono.» (32C·04) al guardar.
    final resultado = await ModificarPersonaPage.abrir(
      context,
      personaId: datos.personaId,
      colportorId: colportor,
    );
    if (resultado is! DarDeBajaYCrearNuevaElegido || !context.mounted) return;

    final nueva = await AltaPersonaPage.abrir(
      context,
      espacioId: datos.espacioId,
      colportorId: colportor,
      nombreInicial: resultado.nombre,
      apellidoInicial: resultado.apellido,
      telefonoInicial: resultado.telefono,
    );
    // Cancelar el alta no cambia nada: la original sigue como estaba.
    if (nueva == null || !context.mounted) return;

    final baja = await mostrarHojaBajaPersona(context, persona: resultado.original);
    if (!mensajero.mounted) return;
    mostrarAvisoDeNota(
      mensajero,
      mediaQuery: mediaQuery,
      texto: baja is PersonaBajaRealizada
          ? TextosPersonas.guardada(nueva.persona.nombre)
          : TextosPersonas.nuevaGuardadaSinLaBaja(
              nueva: nueva.persona.nombre,
              original: FormatoBajaPersona.nombreDePila(resultado.original),
            ),
    );
  }
}
