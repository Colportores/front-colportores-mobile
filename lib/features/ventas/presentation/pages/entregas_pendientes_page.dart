import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show HeroAgenda;
import '../../../inicio/presentation/widgets/barra_pestanas_inicio.dart';
import '../../domain/entities/entrega_pendiente.dart';
import '../formato_entrega_diferida.dart';
import '../providers/entrega_diferida_providers.dart';
import '../providers/ventas_providers.dart';
import '../widgets/piezas_entrega_diferida.dart';
import '../widgets/piezas_venta.dart';
import 'entregar_otro_dia_page.dart';
import 'marcar_entregado_page.dart';

/// «Entregas pendientes» (vista 27, grupo C, HU-VEN-003, 27C·02, 27C·05, 27C·06 y 27C·07): todo lo que
/// la colportora todavía tiene que entregar, en tres grupos —atrasadas, próximas y sin fecha—, desde la
/// pestaña Ventas. Tocar una abre «Marcar entregado» (27C·03); la que no tiene fecha además ofrece
/// «Poner fecha».
///
/// Todo sale del teléfono: funciona sin conexión (27C·08) y se repinta sola cuando se marca una entrega
/// o se mueve su fecha. Si se sale por la barra de pestañas devuelve la pestaña elegida; con «volver»,
/// `null`.
class EntregasPendientesPage extends ConsumerStatefulWidget {
  const EntregasPendientesPage({super.key, required this.colportorId});

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  static Route<PestanaInicio> ruta({required String colportorId}) =>
      MaterialPageRoute<PestanaInicio>(
        builder: (_) => EntregasPendientesPage(colportorId: colportorId),
      );

  @override
  ConsumerState<EntregasPendientesPage> createState() => _EntregasPendientesPageState();
}

class _EntregasPendientesPageState extends ConsumerState<EntregasPendientesPage> {
  /// Hay una pantalla abierta desde la lista: un segundo toque (o dos tarjetas seguidas) no abre otra
  /// encima.
  var _abriendo = false;

  Future<void> _abrir(Future<void> Function() abrir) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await abrir();
    } finally {
      _abriendo = false;
    }
  }

  Future<void> _marcar(EntregaPendiente entrega) => _abrir(() async {
    await Navigator.of(context).push(MarcarEntregadoPage.ruta(ventaId: entrega.ventaId));
  });

  Future<void> _ponerFecha(EntregaPendiente entrega) => _abrir(() async {
    await Navigator.of(
      context,
    ).push(EntregarOtroDiaPage.rutaPonerFecha(colportorId: widget.colportorId, pendiente: entrega));
  });

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(entregasPendientesProvider);
    return Scaffold(
      key: const Key('entregas_pagina'),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            CabeceraVenta(
              eyebrow: TextosEntregaDiferida.eyebrowVentas,
              titulo: TextosEntregaDiferida.tituloPendientes,
              alVolver: () => unawaited(Navigator.of(context).maybePop()),
            ),
            Expanded(
              child: lista.when(
                loading: () => const SingleChildScrollView(child: EsqueletoDeEntregas()),
                error: (_, _) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  children: [
                    AvisoDeVenta(
                      texto: TextosEntregaDiferida.noPudimosLeer,
                      textoAccion: TextosEntregaDiferida.reintentar,
                      alAccion: () => ref.invalidate(entregasPendientesProvider),
                    ),
                  ],
                ),
                data: (entregas) => entregas.isEmpty
                    ? const HeroAgenda(glifo: '✓', titulo: TextosEntregaDiferida.sinPendientes)
                    : _Grupos(entregas: entregas, alMarcar: _marcar, alPonerFecha: _ponerFecha),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BarraPestanasInicio(
        seleccionada: PestanaInicio.ventas,
        onSeleccionar: (pestana) => Navigator.of(context).pop(pestana),
      ),
    );
  }
}

/// Atrasadas, próximas y sin fecha, cada grupo con su rótulo y solo si tiene tarjetas.
class _Grupos extends ConsumerWidget {
  const _Grupos({required this.entregas, required this.alMarcar, required this.alPonerFecha});

  final List<EntregaPendiente> entregas;
  final ValueChanged<EntregaPendiente> alMarcar;
  final ValueChanged<EntregaPendiente> alPonerFecha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = ref.read(relojVentaProvider)();
    final nombres = ref.watch(nombresDeLosPendientesProvider).value;
    final atrasadas = [
      for (final e in entregas)
        if (e.estaAtrasada(ahora)) e,
    ];
    final proximas = [
      for (final e in entregas)
        if (!e.sinFecha && !e.estaAtrasada(ahora)) e,
    ];
    final sinFecha = [
      for (final e in entregas)
        if (e.sinFecha) e,
    ];

    Widget grupo(String rotulo, TonoDeEntrega tono, List<EntregaPendiente> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RotuloDeSeccion(rotulo),
        const SizedBox(height: 7),
        for (final entrega in items) ...[
          _Tarjeta(
            entrega: entrega,
            tono: tono,
            nombres: nombres,
            alAbrir: () => alMarcar(entrega),
            alPonerFecha: tono == TonoDeEntrega.sinFecha ? () => alPonerFecha(entrega) : null,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );

    return ListView(
      key: const Key('entregas_lista'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      children: [
        if (atrasadas.isNotEmpty)
          grupo(TextosEntregaDiferida.atrasadas, TonoDeEntrega.atrasada, atrasadas),
        if (proximas.isNotEmpty)
          grupo(TextosEntregaDiferida.proximas, TonoDeEntrega.proxima, proximas),
        if (sinFecha.isNotEmpty)
          grupo(TextosEntregaDiferida.sinFecha, TonoDeEntrega.sinFecha, sinFecha),
      ],
    );
  }
}

class _Tarjeta extends ConsumerWidget {
  const _Tarjeta({
    required this.entrega,
    required this.tono,
    required this.nombres,
    required this.alAbrir,
    this.alPonerFecha,
  });

  final EntregaPendiente entrega;
  final TonoDeEntrega tono;
  final Map<String, String>? nombres;
  final VoidCallback alAbrir;
  final VoidCallback? alPonerFecha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rotulo = ref
        .watch(
          rotuloDeEntregaProvider((
            espacioId: entrega.espacioId,
            espacioPersonaId: entrega.espacioPersonaId,
          )),
        )
        .value;
    final persona = rotulo?.persona ?? '';
    final fecha = entrega.fechaPrevista;
    return TarjetaDeEntregaPendiente(
      tono: tono,
      dia: fecha == null ? null : FormatoEntregaDiferida.rotuloDeLaTarjeta(fecha),
      persona: persona.isEmpty ? TextosEntregaDiferida.personaSinNombre : persona,
      detalle: FormatoEntregaDiferida.detalleDeLaTarjeta(
        entrega,
        direccion: rotulo?.direccion ?? '',
        nombres: nombres,
      ),
      alAbrir: alAbrir,
      alPonerFecha: alPonerFecha,
    );
  }
}
