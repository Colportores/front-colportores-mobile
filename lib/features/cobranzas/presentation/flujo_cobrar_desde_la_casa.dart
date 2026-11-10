import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mapa/presentation/providers/hoja_casa_providers.dart';
import '../../mapa/presentation/providers/personas_providers.dart';
import 'pages/cobro_efectivo_page.dart';
import 'widgets/hoja_que_venta.dart';

/// «$ Cobrar» de la vista 39 (HU-COB-001, #440): desde la persona que debe en la hoja de la casa (C·01)
/// o desde «Cobranza» de «¿Qué pasó?» (C·06) hasta el cobro en efectivo (vista 28). Es lo que enchufa
/// `cobrarDesdeLaCasaProvider`.
///
/// 1. Lee las ventas con saldo de la persona. Con **una sola** salta directo al cobro; con **varias**
///    abre C·08 «¿Qué venta?» (ver [mostrarHojaQueVenta]); sin ninguna lo dice y no cobra.
/// 2. Abre [CobroEfectivoPage] con la venta, la casa y el cliente ya resueltos.
///
/// Devuelve `true` si se registró un cobro (también uno parcial) y `false` si no: «Cancelar», cerrar
/// sin cobrar o una venta que ya no debe nada. **No escribe la visita**: «Cobranza» desde «¿Qué pasó?»
/// la guarda `FlujoRegistrarVisita` cuando esto devuelve `true` (decisión de P4 de #411), y un cobro
/// abierto desde la hoja de la casa no inventa una visita. Si el cobro no se completa no se toca nada,
/// así que la agenda de cobranza que hubiera queda `PROGRAMADA` (regla común de la vista 39, S37).
///
/// Lanza si no hay a dónde cobrar (la casa sin depto elegido o sin sesión): quien lo abre lo dice con
/// su propio aviso («No pudimos abrir «$ Cobrar». Probá de nuevo.»). Una falla al leer las ventas no
/// lanza: la hoja la dice con su «Reintentar».
abstract final class FlujoCobrarDesdeLaCasa {
  /// Abre el cobro para [datos]. [colportorId] es el usuario con la sesión iniciada.
  static Future<bool> abrir(
    BuildContext context,
    ContextoDeCobro datos, {
    required String? colportorId,
  }) async {
    final espacioId = datos.espacioId;
    final colportor = colportorId?.trim() ?? '';
    if (espacioId == null || colportor.isEmpty) {
      // Un edificio sin depto elegido o una sesión que se perdió: no hay dónde registrar el cobro.
      throw StateError('El cobro necesita una casa o un depto y una sesión iniciada');
    }
    final contenedor = ProviderScope.containerOf(context, listen: false);
    final persona = await _personaDe(contenedor, espacioId, datos.personaId);
    if (!context.mounted) return false;

    final venta = await mostrarHojaQueVenta(
      context,
      personaId: datos.personaId,
      nombre: persona?.nombre,
    );
    if (venta == null || !context.mounted) return false;

    return CobroEfectivoPage.abrir(
      context,
      ventaId: venta.ventaId,
      colportorId: colportor,
      espacioId: espacioId,
      espacioPersonaId: persona?.vinculoId,
    );
  }

  /// El nombre de pila y el vínculo con la casa de [personaId], o `null` si ya no está en [espacioId]
  /// o no se pudo leer: el cobro no depende de eso (el título pierde el nombre y el cliente queda
  /// sin vínculo, como una venta sin persona).
  static Future<({String nombre, String vinculoId})?> _personaDe(
    ProviderContainer contenedor,
    String espacioId,
    String personaId,
  ) async {
    try {
      // Del repositorio y no de un provider `autoDispose`: sin nadie mirando se libera a mitad de la
      // lectura.
      final personas = await contenedor
          .read(personaRepositoryProvider)
          .observarDelEspacio(espacioId)
          .first;
      for (final p in personas) {
        if (p.persona.id == personaId) {
          return (nombre: p.persona.nombre, vinculoId: p.vinculo.id);
        }
      }
    } on Object {
      return null;
    }
    return null;
  }
}
