import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/entities/transferencia.dart';
import '../../domain/usecases/cancelar_transferencia_use_case.dart';
import '../providers/transferencias_providers.dart';
import '../textos_transferencias.dart';
import '../widgets/lectura_de_transferencias.dart';
import '../widgets/piezas_transferencias.dart';
import 'pedir_transferencia_page.dart';

/// Cómo se cerró el detalle cuando algo cambió: la lista lo avisa.
enum SalidaDelDetalle {
  /// La colportora canceló la transferencia (40B·04).
  cancelada,
}

/// El detalle de una transferencia (vista 40 B, 40B·02 a 40B·07), para quien la pidió y para quien la
/// entrega:
///
/// - **Por autorizar, la pedí yo** (40B·02): «Tu coordinadora todavía no la autorizó.» y «Cancelar
///   transferencia» (decisión «Cancelar tr.»: solo quien la pidió, solo mientras está por autorizar).
/// - **Cancelar** (40B·03): una hoja con lo que pasa y «Cancelar transferencia» / «Volver».
/// - **Autorizada** (40B·05), **Rechazada** con el motivo de la coordinadora y «Pedir otra» (40B·06),
///   **Cancelada**.
/// - **Me piden a mí** (40B·07): lo que ve quien entrega, con lo que tiene hoy; sin botones (la decide la
///   coordinadora; quien entrega solo la ve).
/// - **En cola**: todavía no salió del teléfono.
///
/// Se lee de la lista de transferencias: si la coordinadora la decide mientras se mira, el detalle cambia
/// solo. Una acción en curso no admite otro toque y, si falla, el botón vuelve a habilitarse.
class DetalleDeTransferenciaPage extends ConsumerStatefulWidget {
  const DetalleDeTransferenciaPage({
    super.key,
    required this.colportorId,
    required this.transferenciaId,
  });

  final String colportorId;
  final String transferenciaId;

  static Future<SalidaDelDetalle?> abrir(
    BuildContext context, {
    required String colportorId,
    required String transferenciaId,
  }) => Navigator.of(context).push<SalidaDelDetalle>(
    MaterialPageRoute(
      builder: (_) =>
          DetalleDeTransferenciaPage(colportorId: colportorId, transferenciaId: transferenciaId),
    ),
  );

  @override
  ConsumerState<DetalleDeTransferenciaPage> createState() => _DetalleDeTransferenciaPageState();
}

class _DetalleDeTransferenciaPageState extends ConsumerState<DetalleDeTransferenciaPage> {
  /// Hay una cancelación en curso: no admite otro toque.
  var _cancelando = false;

  /// La hoja de confirmación está abierta o por abrirse.
  var _confirmando = false;

  var _cerrando = false;

  /// La última falla al cancelar; `null` si no hay.
  Failure? _falla;

  void _cerrar(SalidaDelDetalle? salida) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(salida);
  }

  Future<void> _alCancelar(Transferencia t, LecturaDeTransferencias lectura) async {
    if (_cancelando || _confirmando || _cerrando) return;
    _confirmando = true;
    bool confirmo;
    try {
      confirmo = await mostrarHojaCancelarTransferencia(context, quien: lectura.contraparte(t));
    } finally {
      _confirmando = false;
    }
    if (!confirmo || !mounted) return;
    setState(() {
      _cancelando = true;
      _falla = null;
    });
    try {
      final resultado = await ref.read(cancelarTransferenciaUseCaseProvider)(
        CancelarTransferenciaParams(transferenciaId: t.id, colportorId: widget.colportorId),
      );
      if (!mounted) return;
      resultado.fold(
        (falla) => setState(() => _falla = falla),
        (_) => _cerrar(SalidaDelDetalle.cancelada),
      );
    } on Object {
      if (mounted) {
        setState(() => _falla = const FailureTransferenciaNoCancelada(causa: 'excepcion'));
      }
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  Future<void> _pedirOtra() async {
    if (_cerrando) return;
    final verLista = await PedirTransferenciaPage.abrir(context, colportorId: widget.colportorId);
    // «Ver transferencias» de 40A·06: la lista está debajo de este detalle.
    if (verLista == true && mounted) _cerrar(null);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.colportorId;
    final transferencias = ref.watch(transferenciasProvider(id));
    final lectura = LecturaDeTransferencias(
      colportorId: id,
      nombresDeProductos: ref.watch(nombresDeProductosProvider).value ?? const {},
      companieros: ref.watch(companierosDeCampaniaProvider(id)).value?.fold((_) => null, (l) => l),
    );
    final ahora = ref.read(relojTransferenciaProvider)();
    final t = transferencias.value?.where((e) => e.id == widget.transferenciaId).firstOrNull;

    final Widget cuerpo;
    if (t == null) {
      if (transferencias.isLoading && !transferencias.hasValue) {
        cuerpo = const EsqueletoDeTransferencias();
      } else if (transferencias.hasError) {
        cuerpo = BannerDeTransferencia(
          key: const Key('detalle_transferencia_error'),
          texto: TextosTransferencias.errorAlTraer,
          tipo: TipoDeBanner.error,
          textoAccion: TextosTransferencias.reintentar,
          alAccion: () => ref.invalidate(transferenciasProvider(id)),
        );
      } else {
        cuerpo = const BannerDeTransferencia(
          key: Key('detalle_transferencia_ausente'),
          texto: TextosTransferencias.sinLaTransferencia,
          tipo: TipoDeBanner.info,
        );
      }
    } else {
      cuerpo = _Cuerpo(
        t: t,
        lectura: lectura,
        ahora: ahora,
        falla: _falla,
        stockPropio: _stockDe(t),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio && !_cancelando && !_confirmando) _cerrar(null);
      },
      child: Scaffold(
        key: const Key('detalle_transferencia_pagina'),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  children: [
                    CabeceraVenta(
                      eyebrow: t == null
                          ? TextosTransferencias.eyebrowDetalle
                          : TextosTransferencias.eyebrowDelDetalle(t.pedidaEl, ahora),
                      titulo: t == null ? TextosTransferencias.tituloLista : lectura.resumen(t),
                      subtitulo: t == null
                          ? null
                          : TextosTransferencias.subtituloDelDetalle(
                              t,
                              quien: lectura.contraparte(t),
                              cara: CaraDeLaTransferencia.de(t, id),
                            ),
                      alVolver: _cancelando ? null : () => _cerrar(null),
                    ),
                    cuerpo,
                  ],
                ),
              ),
              if (t != null && t.laPuedeCancelar(id))
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: _BotonCancelar(
                    cancelando: _cancelando,
                    alPresionar: () => unawaited(_alCancelar(t, lectura)),
                  ),
                )
              else if (t != null && t.estado == EstadoDeTransferencia.rechazada && t.laPidio(id))
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: BotonDeVenta(
                    texto: TextosTransferencias.pedirOtraTransferencia,
                    alPresionar: () => unawaited(_pedirOtra()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Lo que la colportora tiene hoy del primer material de la transferencia (para 40B·07).
  int? _stockDe(Transferencia t) {
    if (t.lineas.isEmpty) return null;
    final materiales = ref.watch(materialesDeTransferenciaProvider(widget.colportorId)).value;
    return materiales?.where((m) => m.id == t.lineas.first.productoId).firstOrNull?.tengo;
  }
}

class _Cuerpo extends StatelessWidget {
  const _Cuerpo({
    required this.t,
    required this.lectura,
    required this.ahora,
    required this.falla,
    required this.stockPropio,
  });

  final Transferencia t;
  final LecturaDeTransferencias lectura;
  final DateTime ahora;
  final Failure? falla;
  final int? stockPropio;

  @override
  Widget build(BuildContext context) {
    final yo = lectura.colportorId;
    final cara = CaraDeLaTransferencia.de(t, yo);
    final entregaYo = t.origenId == yo;
    final (String, TipoDeBanner) aviso = switch (t.estado) {
      EstadoDeTransferencia.porAutorizar when t.enCola => (
        TextosTransferencias.enColaEnElDetalle,
        TipoDeBanner.sinConexion,
      ),
      EstadoDeTransferencia.porAutorizar when entregaYo && !t.laPidio(yo) => (
        TextosTransferencias.teLaPidenPorAutorizar(stockPropio),
        TipoDeBanner.info,
      ),
      EstadoDeTransferencia.porAutorizar => (
        TextosTransferencias.porAutorizarPedida,
        TipoDeBanner.info,
      ),
      EstadoDeTransferencia.autorizada => (
        cara == CaraDeLaTransferencia.lePediste
            ? TextosTransferencias.autorizada(lectura.contraparte(t))
            : TextosTransferencias.autorizadaSinPedirla,
        TipoDeBanner.ok,
      ),
      EstadoDeTransferencia.rechazada => (
        TextosTransferencias.rechazada(t.motivoRechazo),
        TipoDeBanner.error,
      ),
      EstadoDeTransferencia.cancelada => (TextosTransferencias.canceladaAviso, TipoDeBanner.info),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BannerDeTransferencia(
          key: const Key('detalle_transferencia_aviso'),
          texto: aviso.$1,
          tipo: aviso.$2,
        ),
        const SizedBox(height: 10),
        if (falla != null) ...[
          BannerDeTransferencia(
            key: const Key('detalle_transferencia_falla'),
            texto: falla is FailureTransferenciaNoCancelable
                ? TextosTransferencias.yaNoSePuedeCancelar
                : falla!.mensaje,
            tipo: TipoDeBanner.error,
          ),
          const SizedBox(height: 10),
        ],
        FilasDeLaTransferencia(
          datos: [
            if (t.lineas.length > 1)
              for (final (i, (nombre, cantidad)) in lectura.lineasConNombre(t).indexed)
                DatoDeTransferencia(
                  clave: 'detalle_transferencia_linea_$i',
                  rotulo: nombre,
                  valor: '× $cantidad',
                ),
            DatoDeTransferencia(
              clave: 'detalle_transferencia_pide',
              rotulo: TextosTransferencias.pide,
              valor: lectura.punta(t.destinoId),
            ),
            DatoDeTransferencia(
              clave: 'detalle_transferencia_entrega',
              rotulo: TextosTransferencias.entrega,
              valor: lectura.punta(t.origenId),
            ),
            DatoDeTransferencia(
              clave: 'detalle_transferencia_pedida',
              rotulo: TextosTransferencias.pedida,
              valor: TextosTransferencias.cuando(t.pedidaEl, ahora),
            ),
          ],
        ),
      ],
    );
  }
}

/// El botón rojo «Cancelar transferencia» del detalle (40B·02): apagado mientras cancela.
class _BotonCancelar extends StatelessWidget {
  const _BotonCancelar({required this.cancelando, required this.alPresionar});

  final bool cancelando;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const Key('detalle_transferencia_cancelar'),
      onPressed: cancelando ? null : alPresionar,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        foregroundColor: ColoresAgenda.rojo,
        disabledForegroundColor: ColoresAgenda.gris,
        side: const BorderSide(color: ColoresAgenda.rojo, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        cancelando ? TextosTransferencias.cancelando : TextosTransferencias.cancelarTransferencia,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}
