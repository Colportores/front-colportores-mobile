import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/entities/transferencia.dart';
import '../providers/transferencias_providers.dart';
import '../textos_transferencias.dart';
import '../widgets/lectura_de_transferencias.dart';
import '../widgets/piezas_transferencias.dart';
import 'detalle_de_transferencia_page.dart';
import 'pedir_transferencia_page.dart';

/// Qué transferencias se ven (los chips de 40B·01).
enum FiltroDeTransferencias {
  todas(TextosTransferencias.filtroTodas),
  porAutorizar(TextosTransferencias.filtroPorAutorizar),
  autorizadas(TextosTransferencias.filtroAutorizadas),
  cerradas(TextosTransferencias.filtroCerradas);

  const FiltroDeTransferencias(this.texto);

  final String texto;

  /// «Cerradas» son las que ya no esperan ni se cumplieron: rechazadas y canceladas.
  bool deja(EstadoDeTransferencia e) => switch (this) {
    todas => true,
    porAutorizar => e == EstadoDeTransferencia.porAutorizar,
    autorizadas => e == EstadoDeTransferencia.autorizada,
    cerradas => e == EstadoDeTransferencia.rechazada || e == EstadoDeTransferencia.cancelada,
  };
}

/// «Transferencias» (vista 40 B, HU-STK-005, #512): una sola lista para las dos puntas con lo que la
/// colportora pidió, lo que le piden y lo que armó su coordinadora, cada una con su estado (40B·01, 40B·04,
/// 40B·08 a 40B·11).
///
/// Todo sale del teléfono, así que sin conexión se ve igual con un aviso de cuándo es lo que se ve
/// (40B·11). Mientras se lee, tres bloques grises (40B·09); si no se puede leer, el error con «Reintentar»
/// (40B·10), nunca «todavía no hay transferencias». Las que esperan en la cola de este teléfono dicen «En
/// cola» (40A·07). «+ Pedir transferencia» abre 40A; una fila abre su detalle.
class TransferenciasPage extends ConsumerStatefulWidget {
  const TransferenciasPage({super.key, required this.colportorId});

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  static Future<void> abrir(BuildContext context, {required String colportorId}) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => TransferenciasPage(colportorId: colportorId)));

  @override
  ConsumerState<TransferenciasPage> createState() => _TransferenciasPageState();
}

class _TransferenciasPageState extends ConsumerState<TransferenciasPage> {
  var _filtro = FiltroDeTransferencias.todas;

  /// Ya se está abriendo otra pantalla: un segundo toque no abre otra encima.
  var _abriendo = false;

  Future<void> _pedir() async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await PedirTransferenciaPage.abrir(context, colportorId: widget.colportorId);
    } finally {
      _abriendo = false;
    }
  }

  Future<void> _abrirDetalle(Transferencia t) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      final salida = await DetalleDeTransferenciaPage.abrir(
        context,
        colportorId: widget.colportorId,
        transferenciaId: t.id,
      );
      if (salida == SalidaDelDetalle.cancelada && mounted) {
        // 40B·04: el aviso de que quedó cancelada; la fila ya dice «Cancelada».
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text(TextosTransferencias.transferenciaCancelada)),
          );
      }
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.colportorId;
    final transferencias = ref.watch(transferenciasProvider(id));
    final sinConexion = ref.watch(conexionProvider).value == TipoConexion.sinConexion;
    final lectura = LecturaDeTransferencias(
      colportorId: id,
      nombresDeProductos: ref.watch(nombresDeProductosProvider).value ?? const {},
      companieros: ref.watch(companierosDeCampaniaProvider(id)).value?.fold((_) => null, (l) => l),
    );
    final ahora = ref.read(relojTransferenciaProvider)();

    final List<Widget> cuerpo;
    if (transferencias.isLoading && !transferencias.hasValue) {
      cuerpo = const [EsqueletoDeTransferencias()];
    } else if (transferencias.hasError) {
      cuerpo = [
        BannerDeTransferencia(
          key: const Key('transferencias_error'),
          texto: TextosTransferencias.errorAlTraer,
          tipo: TipoDeBanner.error,
          textoAccion: TextosTransferencias.reintentar,
          alAccion: () => ref.invalidate(transferenciasProvider(id)),
        ),
      ];
    } else {
      final todas = transferencias.requireValue;
      final visibles = [
        for (final t in todas)
          if (_filtro.deja(t.estado)) t,
      ];
      cuerpo = [
        if (sinConexion) ...[
          BannerDeTransferencia(
            key: const Key('transferencias_sin_conexion'),
            texto: TextosTransferencias.sinConexionLista(
              ref.watch(ultimaBajadaDeTransferenciasProvider).value,
              ahora,
            ),
            tipo: TipoDeBanner.sinConexion,
          ),
          const SizedBox(height: 8),
        ],
        if (todas.isEmpty)
          const HeroDeTransferencias(
            key: Key('transferencias_vacio'),
            glifo: '⇄',
            titulo: TextosTransferencias.sinTransferenciasTitulo,
            texto: TextosTransferencias.sinTransferenciasTexto,
          )
        else ...[
          Wrap(
            spacing: 8,
            children: [
              for (final f in FiltroDeTransferencias.values)
                ChipDeVenta(
                  key: Key('transferencias_filtro_${f.name}'),
                  texto: f.texto,
                  elegido: f == _filtro,
                  alPresionar: () => setState(() => _filtro = f),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (visibles.isEmpty)
            const Padding(
              key: Key('transferencias_filtro_vacio'),
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                TextosTransferencias.sinEnElFiltro,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: Color(0xFF5B6B82)),
              ),
            )
          else
            for (final t in visibles)
              Padding(
                key: Key('transferencia_${t.id}'),
                padding: const EdgeInsets.only(bottom: 8),
                child: TarjetaDeTransferencia(
                  estado: t.estado,
                  arriba: TextosTransferencias.lineaDeArriba(
                    t.pedidaEl,
                    ahora,
                    lectura.contraparte(t),
                    CaraDeLaTransferencia.de(t, id),
                  ),
                  titulo: lectura.resumen(t),
                  etiquetaDelEstado: TextosTransferencias.estado(t.estado, enCola: t.enCola),
                  alPresionar: () => unawaited(_abrirDetalle(t)),
                ),
              ),
        ],
      ];
    }

    return Scaffold(
      key: const Key('transferencias_pagina'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                children: [
                  CabeceraVenta(
                    eyebrow: TextosTransferencias.eyebrowLista,
                    titulo: TextosTransferencias.tituloLista,
                    alVolver: () => Navigator.of(context).maybePop(),
                  ),
                  ...cuerpo,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: BotonDeVenta(
                texto: TextosTransferencias.pedirOtra,
                alPresionar: () => unawaited(_pedir()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
