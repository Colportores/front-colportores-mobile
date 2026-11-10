import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agenda/presentation/providers/agenda_providers.dart';
import '../../mapa/presentation/flujo_registrar_visita.dart';
import '../../mapa/presentation/providers/hoja_casa_providers.dart';
import '../../mapa/presentation/providers/personas_providers.dart';
import 'pages/cobro_efectivo_page.dart';
import 'textos_que_venta.dart';
import 'widgets/dialogo_no_te_pago.dart';
import 'widgets/hoja_que_venta.dart';

/// «$ Cobrar» de la vista 39 (HU-COB-001, #440): desde la persona que debe en la hoja de la casa (C·01)
/// o desde «Cobranza» de «¿Qué pasó?» (C·06) hasta el cobro en efectivo (vista 28). Es lo que enchufa
/// `cobrarDesdeLaCasaProvider`.
///
/// 1. Lee las ventas con saldo de la persona. Con **una sola** salta directo al cobro; con **varias**
///    abre C·08 «¿Qué venta?» (ver [mostrarHojaQueVenta]); sin ninguna lo dice y no cobra.
/// 2. Abre [CobroEfectivoPage] con la venta, la casa y el cliente ya resueltos.
///
/// Devuelve:
/// - `true` si se registró un cobro (también uno parcial). **No escribe la visita**: «Cobranza» desde
///   «¿Qué pasó?» la guarda `FlujoRegistrarVisita` cuando esto devuelve `true` (decisión de P4 de #411),
///   y un cobro abierto desde la hoja de la casa no inventa una visita.
/// - [CobranzaAnotadaSinCobro] si no se cobró pero la colportora tocó «Cancelar» en C·08, contestó «Sí,
///   anotar la visita» a «¿María no te pagó?» y la visita «Cobranza» **ya quedó guardada** (decisión de
///   Cristian, 03/11, «Sin cobro»). La escribe este flujo —y no quien lo abrió— porque la pregunta nace
///   acá y la hoja de la casa también abre este flujo sin pasar por «¿Qué pasó?»; así hay un solo lugar
///   que la escribe, con `FlujoRegistrarVisita.anotarCobranzaSinCobro`. Va sin agenda: la cita de
///   cobranza que hubiera sigue `PROGRAMADA` (regla común de la vista 39, S37).
/// - `false` si no se cobró y no se anotó nada: «No, me equivoqué», atrás, cerrar sin elegir (tocar
///   afuera o atrás en C·08, «Cerrar» cuando ya no debe nada) o una venta que ya no debe nada. Ahí no
///   se escribe nada y se vuelve a donde estaba.
///
/// La pregunta es **solo** del «Cancelar» de C·08. Salir de la pantalla del cobro (vista 28) sin
/// cobrar no la hace (pendiente «Cristian §3»); y es local, sin red: sin conexión no cambia nada.
///
/// Lanza si no hay a dónde cobrar (la casa sin depto elegido o sin sesión): quien lo abre lo dice con
/// su propio aviso («No pudimos abrir «$ Cobrar». Probá de nuevo.»). Una falla al leer las ventas no
/// lanza: la hoja la dice con su «Reintentar».
abstract final class FlujoCobrarDesdeLaCasa {
  /// Abre el cobro para [datos]. [colportorId] es el usuario con la sesión iniciada.
  static Future<Object> abrir(
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

    final mensajero = ScaffoldMessenger.maybeOf(context);
    final salida = await salirDeHojaQueVenta(
      context,
      personaId: datos.personaId,
      nombre: persona?.nombre,
    );
    if (!context.mounted) return false;

    switch (salida) {
      case CerroQueVenta():
        return false;
      case CanceloQueVenta():
        return _preguntarSiNoPago(
          context,
          contenedor,
          mensajero,
          espacioId: espacioId,
          colportorId: colportor,
          persona: persona,
        );
      case VentaElegida(:final venta):
        return CobroEfectivoPage.abrir(
          context,
          ventaId: venta.ventaId,
          colportorId: colportor,
          espacioId: espacioId,
          espacioPersonaId: persona?.vinculoId,
        );
    }
  }

  /// «¿María no te pagó?» tras «Cancelar» (decisión de Cristian, 03/11). Con «Sí, anotar la visita» guarda
  /// la visita «Cobranza» sin cobro; con «No, me equivoqué» o atrás no escribe nada.
  static Future<Object> _preguntarSiNoPago(
    BuildContext context,
    ProviderContainer contenedor,
    ScaffoldMessengerState? mensajero, {
    required String espacioId,
    required String colportorId,
    required ({String nombre, String vinculoId})? persona,
  }) async {
    // Los ids se generan una vez por pregunta: un «Sí» tras una falla repite la misma visita, no otra.
    final ids = contenedor.read(registrarResultadoVisitaUseCaseProvider).nuevosIds();
    final anotada = await preguntarSiNoPago(
      context,
      nombre: persona?.nombre,
      alAnotar: () => FlujoRegistrarVisita.anotarCobranzaSinCobro(
        contenedor,
        ids: ids,
        espacioId: espacioId,
        espacioPersonaId: persona?.vinculoId,
        colportorId: colportorId,
      ),
    );
    if (!anotada) return false;
    mensajero
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(TextosQueVenta.visitaAnotada)));
    return const CobranzaAnotadaSinCobro();
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
