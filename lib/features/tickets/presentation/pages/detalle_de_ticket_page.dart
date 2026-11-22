import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../catalogo/presentation/formato_precios.dart' show FormatoPrecios;
import '../../../cuenta/presentation/textos_cuenta.dart' show FormatoCuenta;
import '../../../depositos/presentation/pages/registrar_deposito_page.dart';
import '../../../ventas/presentation/widgets/piezas_venta.dart' show BotonDeVenta, CabeceraVenta;
import '../../domain/entities/item_del_historial.dart';
import '../../domain/services/visor_de_fotos.dart';
import '../providers/tickets_providers.dart';
import '../textos_tickets.dart';
import '../widgets/piezas_tickets.dart';

/// El detalle de un ticket de «Mis tickets» (vista 38B·02 y 38B·03, HU-COB-009): el monto, el estado
/// con lo que pasó (el motivo del rechazo, quién y cuándo lo validó), la foto y los datos.
///
/// - **Rechazado** (38B·02): el motivo con las palabras del coordinador y «Cargar de nuevo», que abre
///   el formulario con lo mismo cargado (hay que sacar la foto otra vez). El ticket rechazado no se
///   edita ni se borra: queda en el historial.
/// - **Validado** (38B·03): cuándo se validó y a qué se acreditó.
/// - **Por validar** y **en cola**: lo que falta para que se acredite.
///
/// La foto sale de la copia del teléfono si sigue ahí y, si no, se pide a la nube (se conserva 4
/// meses: después se dice que ya no está y los datos siguen). Un retiro por el coordinador no lleva
/// ticket ni foto. El estado se actualiza solo con cada bajada del servidor.
class DetalleDeTicketPage extends ConsumerStatefulWidget {
  const DetalleDeTicketPage({super.key, required this.colportorId, required this.item});

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  /// La fila que se abrió; si el historial ya no la trae (poco probable), se sigue mostrando esta.
  final ItemDelHistorial item;

  /// Abre el detalle encima de la lista.
  static Future<void> abrir(
    BuildContext context, {
    required String colportorId,
    required ItemDelHistorial item,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => DetalleDeTicketPage(colportorId: colportorId, item: item),
    ),
  );

  @override
  ConsumerState<DetalleDeTicketPage> createState() => _DetalleDeTicketPageState();
}

class _DetalleDeTicketPageState extends ConsumerState<DetalleDeTicketPage> {
  /// Ya se está abriendo el formulario: un segundo toque no abre otro encima.
  var _abriendo = false;

  Future<void> _cargarDeNuevo(ItemDelHistorial item) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      final registrado = await RegistrarDepositoPage.abrir(
        context,
        colportorId: widget.colportorId,
        copiaDe: item,
        desdeMisTickets: true,
      );
      // Cargado el nuevo, el rechazado ya no hace falta a la vista: se vuelve a la lista, que lo trae.
      if (registrado && mounted) Navigator.of(context).pop();
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final historial = ref.watch(historialDeTicketsProvider).value;
    final item = historial?.items.where((i) => i.id == widget.item.id).firstOrNull ?? widget.item;
    final ticketId = item.ticketId;

    return Scaffold(
      key: const Key('ticket_detalle'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                key: const Key('ticket_detalle_lista'),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                children: [
                  CabeceraVenta(
                    eyebrow: TextosTickets.eyebrowDelDetalle(item.fecha),
                    titulo: FormatoPrecios.monto(item.montoCentavos),
                    subtitulo: TextosTickets.subtituloDelDetalle(item),
                    alVolver: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(height: 4),
                  _aviso(item),
                  if (ticketId != null) ...[const SizedBox(height: 12), _foto(item, ticketId)],
                  const SizedBox(height: 8),
                  ..._datos(item),
                ],
              ),
            ),
            if (item.sePuedeCargarDeNuevo)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: BotonDeVenta(
                  key: const Key('ticket_cargar_de_nuevo'),
                  texto: TextosTickets.cargarDeNuevo,
                  alPresionar: () => unawaited(_cargarDeNuevo(item)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Lo que pasó con el ticket, arriba de todo.
  Widget _aviso(ItemDelHistorial item) {
    final sinTicket = item.ticketId == null;
    final (texto, tipo) = switch (item.estado) {
      EstadoDelItem.rechazado => (TextosTickets.rechazado(item.motivoRechazo), TipoDeAviso.error),
      EstadoDelItem.validado => (TextosTickets.validado(item), TipoDeAviso.ok),
      EstadoDelItem.porValidar => (
        sinTicket ? TextosTickets.porValidarSinTicket : TextosTickets.porValidarConTicket,
        TipoDeAviso.info,
      ),
      EstadoDelItem.enCola => (TextosTickets.enColaDelDetalle, TipoDeAviso.sinConexion),
    };
    return KeyedSubtree(
      key: Key('ticket_aviso_${item.estado.name}'),
      child: AvisoDeTicket(texto: texto, tipo: tipo),
    );
  }

  Widget _foto(ItemDelHistorial item, String ticketId) {
    final clave = (ticketId: ticketId, subida: item.fotoSubida);
    final foto = ref.watch(fotoDelTicketProvider(clave));
    final FotoParaVer? lectura = foto.isLoading && !foto.hasValue
        ? null
        : foto.hasError
        ? const FotoNoDisponible()
        : foto.requireValue;
    return FotoDelDetalle(
      foto: lectura,
      rechazada: item.fotoRechazada,
      alReintentar: () => ref.invalidate(fotoDelTicketProvider(clave)),
    );
  }

  /// Fecha, autorización y tarjeta: lo que el canvas pone en la tabla de abajo (38B·02, 38B·03).
  List<Widget> _datos(ItemDelHistorial item) {
    final lleva = item.ticketId != null;
    return [
      FilaDeDatoDelTicket(rotulo: TextosTickets.filaFecha, valor: FormatoCuenta.fecha(item.fecha)),
      if (item.numeroAutorizacion != null)
        FilaDeDatoDelTicket(
          rotulo: TextosTickets.filaAutorizacion,
          valor: item.numeroAutorizacion!,
        ),
      // «No» también se dice (38B·02): el ticket de un depósito en efectivo no es de tarjeta.
      if (lleva && item.lugar != LugarDelTicket.cobroConTarjeta)
        FilaDeDatoDelTicket(
          rotulo: TextosTickets.filaTarjeta,
          valor: TextosTickets.tarjeta(item.tarjetaTipo),
        ),
      if (lleva && item.lugar == LugarDelTicket.cobroConTarjeta && item.tarjetaTipo != null)
        FilaDeDatoDelTicket(
          rotulo: TextosTickets.filaTarjeta,
          valor: TextosTickets.tarjeta(item.tarjetaTipo),
        ),
    ];
  }
}
