import 'package:flutter/material.dart';

import 'pages/ficha_persona_page.dart';
import 'providers/hoja_casa_providers.dart';

/// Tocar una persona de la pestaña Personas de la hoja de la casa (vista 39 C·02) abre su ficha (vista
/// 32 B, HU-UBI-009, #650). Es lo que enchufa `fichaDePersonaDesdeLaCasaProvider`.
///
/// La ficha se empuja sobre el navegador de la app: la hoja de la casa queda abajo, tal cual estaba
/// (pestaña, desplazamiento y altura), y al volver —con «Volver» o con atrás del sistema— sigue abierta.
/// Todo se lee del teléfono: funciona igual sin conexión.
///
/// Lanza si no hay a dónde abrir (sin sesión iniciada): la hoja lo dice con su propio aviso («No pudimos
/// abrir la ficha. Probá de nuevo.») y la fila vuelve a quedar habilitada. Una persona o un depto de
/// baja **no** es un error: la ficha se abre en solo lectura con su aviso (#563).
abstract final class FlujoFichaDesdeLaCasa {
  /// Abre la ficha de [datos] y espera a que se cierre. [colportorId] es el usuario con la sesión
  /// iniciada (`created_by` de las notas nuevas de la ficha).
  static Future<void> abrir(
    BuildContext context,
    ContextoDeFicha datos, {
    required String? colportorId,
  }) {
    final colportor = colportorId?.trim() ?? '';
    if (colportor.isEmpty) {
      throw StateError('La ficha necesita una sesión iniciada');
    }
    return FichaPersonaPage.abrir(
      context,
      personaId: datos.personaId,
      espacioId: datos.espacioId,
      colportorId: colportor,
      nombre: datos.nombre,
    );
  }
}
