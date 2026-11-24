import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../cuenta/presentation/widgets/piezas_cuenta.dart'
    show AvisoSinConexionCuenta, BannerErrorCuenta;
import '../../../depositos/presentation/pages/registrar_deposito_page.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../../ventas/presentation/widgets/piezas_venta.dart' show BotonDeVenta, CabeceraVenta;
import '../../domain/entities/item_del_historial.dart';
import '../providers/tickets_providers.dart';
import '../textos_tickets.dart';
import '../widgets/piezas_tickets.dart';
import 'detalle_de_ticket_page.dart';

/// «Mis tickets» (vista 38B, HU-COB-009): el historial de lo que el colportor depositó o le retiró su
/// coordinador, con el estado de cada uno.
///
/// Todo sale del teléfono, así que se ve igual sin conexión (38B·06: los estados son los de la última
/// bajada, y lo que todavía no llegó dice «En cola»). Mientras se lee, un bloque gris por fila
/// (38B·05); si la base no se puede leer, el error con «Reintentar» (38B·07), nunca una lista vacía
/// que parezca que no hay tickets; sin ninguno, el vacío (38B·04). Los filtros (todos, por validar,
/// rechazados, alquiler) son de la pantalla: al volver a entrar arrancan en «Todos».
///
/// «+ Cargar ticket» abre el mismo formulario que «Registrar depósito» (vista 38A: desde «Paso ticket»
/// el ticket y el depósito se cargan juntos). Tocar una fila abre su detalle (38B·02, 38B·03).
class HistorialDeTicketsPage extends ConsumerStatefulWidget {
  const HistorialDeTicketsPage({super.key, required this.colportorId});

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  /// Abre «Mis tickets» encima de lo que se esté viendo.
  static Future<void> abrir(BuildContext context, {required String colportorId}) =>
      abrirEn(Navigator.of(context), colportorId: colportorId);

  /// Lo mismo con el navegador en la mano (cuando la pantalla que lo pide se acaba de cerrar).
  static Future<void> abrirEn(NavigatorState navegador, {required String colportorId}) =>
      navegador.push<void>(
        MaterialPageRoute(builder: (_) => HistorialDeTicketsPage(colportorId: colportorId)),
      );

  @override
  ConsumerState<HistorialDeTicketsPage> createState() => _HistorialDeTicketsPageState();
}

class _HistorialDeTicketsPageState extends ConsumerState<HistorialDeTicketsPage> {
  var _filtro = FiltroDeTickets.todos;

  /// Ya se está abriendo el detalle o el formulario: un segundo toque no abre otro encima.
  var _abriendo = false;

  Future<void> _abrirDetalle(ItemDelHistorial item) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await DetalleDeTicketPage.abrir(context, colportorId: widget.colportorId, item: item);
    } finally {
      _abriendo = false;
    }
  }

  Future<void> _cargarTicket() async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await RegistrarDepositoPage.abrir(
        context,
        colportorId: widget.colportorId,
        desdeMisTickets: true,
      );
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final historial = ref.watch(historialDeTicketsProvider);
    final sinConexion = ref.watch(conexionProvider).value == TipoConexion.sinConexion;
    final ahora = ref.read(relojTicketProvider)();

    final List<Widget> cuerpo;
    if (historial.isLoading && !historial.hasValue) {
      cuerpo = const [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
          sliver: SliverToBoxAdapter(child: EsqueletoDeTickets()),
        ),
      ];
    } else if (historial.hasError) {
      cuerpo = [
        SliverToBoxAdapter(
          child: BannerErrorCuenta(
            texto: TextosTickets.errorAlTraer,
            alReintentar: () => ref.invalidate(historialDeTicketsProvider),
          ),
        ),
      ];
    } else {
      cuerpo = _lista(historial.requireValue, sinConexion: sinConexion, ahora: ahora);
    }

    return Scaffold(
      key: const Key('tickets_pagina'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                key: const Key('tickets_lista'),
                slivers: [
                  SliverToBoxAdapter(
                    child: CabeceraVenta(
                      eyebrow: TextosTickets.eyebrow,
                      titulo: TextosTickets.titulo,
                      alVolver: () => Navigator.maybePop(context),
                    ),
                  ),
                  ...cuerpo,
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: BotonDeVenta(
                key: const Key('tickets_cargar'),
                texto: TextosTickets.cargarTicket,
                alPresionar: () => unawaited(_cargarTicket()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _lista(
    HistorialDeTickets historial, {
    required bool sinConexion,
    required DateTime ahora,
  }) {
    final items = [
      for (final i in historial.items)
        if (_filtro.acepta(i)) i,
    ];
    return [
      if (sinConexion)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          sliver: SliverToBoxAdapter(
            child: AvisoSinConexionCuenta(
              texto: TextosTickets.sinConexion(historial.bajadoEn, ahora),
            ),
          ),
        ),
      if (historial.items.isEmpty)
        const SliverToBoxAdapter(
          child: VacioDeTickets(
            key: Key('tickets_vacio'),
            titulo: TextosTickets.vacioTitulo,
            texto: TextosTickets.vacioTexto,
          ),
        )
      else ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          sliver: SliverToBoxAdapter(
            child: FiltrosDeTickets(elegido: _filtro, alElegir: (f) => setState(() => _filtro = f)),
          ),
        ),
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: VacioDeTickets(
              key: const Key('tickets_vacio_del_filtro'),
              titulo: TextosTickets.sinResultadosDelFiltro(_filtro),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => TarjetaDeTicket(
                key: Key('tickets_fila_${items[i].id}'),
                item: items[i],
                hoy: ahora,
                alAbrir: () => unawaited(_abrirDetalle(items[i])),
              ),
            ),
          ),
      ],
    ];
  }
}
