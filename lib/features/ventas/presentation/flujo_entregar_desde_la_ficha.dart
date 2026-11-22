import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mapa/presentation/providers/personas_providers.dart';
import '../domain/entities/entrega_pendiente.dart';
import 'formato_entrega_diferida.dart';
import 'pages/marcar_entregado_page.dart';
import 'providers/entrega_providers.dart';
import 'widgets/hoja_que_entrega.dart';

/// «Registrar entrega» y «Entregar» de la ficha de la persona (vista 32, 32B·01, HU-VEN-005) hasta
/// «Marcar entregado» (vista 27, 27C·03, HU-VEN-003). Es lo que enchufa
/// `registrarEntregaDesdeLaFichaProvider` (decisiones del 30/10 por #602 y del 10/11 por el QA de #678).
///
/// - Con [ventaId] («Entregar» en la fila de una entrega pendiente) abre «Marcar entregado» de esa
///   venta, sin preguntar.
/// - Sin venta (el chip «Registrar entrega») lee lo pendiente de la persona en ese espacio: con **una**
///   venta abre «Marcar entregado» directo; con **varias** pregunta «¿Qué venta?» ([mostrarHojaQueEntrega],
///   como C·08 del cobro); sin ninguna (se entregó mientras la ficha estaba abierta) lo dice.
///
/// Devuelve `true` si se marcó algo. Todo es local: sin conexión funciona igual. Si no se puede leer lo
/// pendiente, lo dice con un aviso y no abre nada.
abstract final class FlujoEntregarDesdeLaFicha {
  static Future<bool> abrir(
    BuildContext context, {
    required String personaId,
    required String espacioId,
    String? ventaId,
    DateTime? fechaPrevista,
  }) async {
    // Con la fecha de la tarjeta se abre la entrega de esa cita (una venta puede tener una por cada
    // grupo de libros diferido, decisión de Cristian del 11/11, «Entrega cita»).
    if (ventaId != null) {
      return _marcar(context, CualEntrega(ventaId, fechaPrevista: fechaPrevista));
    }

    final contenedor = ProviderScope.containerOf(context, listen: false);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    List<EntregaPendiente> pendientes;
    try {
      final vinculo = await _vinculoDe(contenedor, espacioId, personaId);
      if (vinculo == null) {
        pendientes = const [];
      } else {
        // Del repositorio y no de un provider `autoDispose`: sin nadie mirando se libera a mitad de la
        // lectura.
        pendientes = await contenedor
            .read(entregaRepositoryProvider)
            .observarPendientes(espacioPersonaId: vinculo)
            .first
            .timeout(const Duration(seconds: 5));
      }
    } on Object {
      _avisar(mensajero, TextosEntregaDiferida.noPudimosLeer);
      return false;
    }
    if (!context.mounted) return false;
    switch (pendientes) {
      case []:
        _avisar(mensajero, TextosEntregaDiferida.sinPendientesDeLaPersona);
        return false;
      case [final unica]:
        return _marcar(context, CualEntrega.de(unica));
      default:
        final elegida = await mostrarHojaQueEntrega(context, pendientes: pendientes);
        if (elegida == null || !context.mounted) return false;
        return _marcar(context, CualEntrega.de(elegida));
    }
  }

  static Future<bool> _marcar(BuildContext context, CualEntrega cual) async {
    final hecho = await Navigator.of(context).push(MarcarEntregadoPage.rutaDe(cual));
    return hecho != null;
  }

  /// El vínculo (`espacio_persona.id`) de [personaId] en [espacioId], o `null` si ya no está.
  static Future<String?> _vinculoDe(
    ProviderContainer contenedor,
    String espacioId,
    String personaId,
  ) async {
    final personas = await contenedor
        .read(personaRepositoryProvider)
        .observarDelEspacio(espacioId)
        .first
        .timeout(const Duration(seconds: 5));
    for (final p in personas) {
      if (p.persona.id == personaId) return p.vinculo.id;
    }
    return null;
  }

  static void _avisar(ScaffoldMessengerState? mensajero, String texto) => mensajero
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(texto)));
}
