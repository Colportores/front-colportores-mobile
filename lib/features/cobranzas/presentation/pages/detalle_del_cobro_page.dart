import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ventas/presentation/formato_venta.dart';
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/entities/detalle_del_cobro.dart';
import '../providers/cobranzas_providers.dart';
import '../textos_anular_cobro.dart';
import '../textos_cobro.dart';
import '../widgets/piezas_anular_cobro.dart';
import '../widgets/piezas_cobro.dart';
import 'anular_cobro_page.dart';

/// «Detalle del cobro» (vista 30 B, HU-COB-006, artboards 30B-01, 30B-05, 30B-06 y 30B-07): lo que se
/// cobró, hasta cuándo se puede anular y, si hace falta, «Anular cobro». Se abre desde un cobro del
/// historial (la ficha de la persona o la hoja de la casa) con el id del cobro; la vista 39 no vuelve
/// a pedir nada. Al terminar o cancelar vuelve a donde estaba; cancelar no anula nada.
///
/// - **Detalle** (30B-01): fecha, medio y estado, con «Podés anularlo hasta …» (72 h desde el cobro).
/// - **Anulado** (30B-05): el estado dice «Anulado · motivo», el resumen muestra el saldo que volvió y no
///   hay botón. Recién anulado, un aviso lo dice; al volver a entrar, el cobro sigue anulado.
/// - **Pasaron las 72 h** (30B-06): ya no se puede anular, ni siquiera por el coordinador (decisión de
///   Cristian, 23/10, «Anular 72 h»).
/// - **Ticket validado** (30B-07): con el ticket de la tarjeta validado por el coordinador, la
///   colportora no anula sola: se lo pide a él (decisión de Cristian, 23/10). Hasta que llegue el ticket
///   local (HU-COB-007, #169), [ticketValidadoDelCobroProvider] responde «no» y lo cuida el servidor.
/// - Además lee el cobro: cargando, ya no está y error de lectura con «Reintentar».
///
/// Devuelve `true` si en esta visita se anuló el cobro y `false` si no.
class DetalleDelCobroPage extends ConsumerStatefulWidget {
  const DetalleDelCobroPage({super.key, required this.cobranzaId, required this.colportorId});

  final String cobranzaId;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  /// Abre la pantalla encima de la actual. `true` si se anuló el cobro.
  static Future<bool> abrir(
    BuildContext context, {
    required String cobranzaId,
    required String colportorId,
  }) async {
    final anulo = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DetalleDelCobroPage(cobranzaId: cobranzaId, colportorId: colportorId),
      ),
    );
    return anulo ?? false;
  }

  @override
  ConsumerState<DetalleDelCobroPage> createState() => _DetalleDelCobroPageState();
}

enum _Lectura { cargando, lista, ausente, conError }

class _DetalleDelCobroPageState extends ConsumerState<DetalleDelCobroPage> {
  var _lectura = _Lectura.cargando;
  DetalleDelCobro? _detalle;

  /// Se anuló en esta visita: el aviso de 30B-05 se muestra una vez.
  var _recienAnulado = false;

  /// Se anuló en esta visita (lo que devuelve la pantalla).
  var _anulo = false;

  /// Hay una pantalla abierta desde acá: no admite otra encima.
  var _navegando = false;

  /// La pantalla se está cerrando: un segundo toque no vuelve a hacer `pop`.
  var _cerrando = false;

  @override
  void initState() {
    super.initState();
    unawaited(_leer());
  }

  DateTime _ahora() => ref.read(relojCobroProvider)();

  Future<void> _leer({bool mostrarCarga = true}) async {
    if (mostrarCarga) setState(() => _lectura = _Lectura.cargando);
    try {
      final leido = await ref.read(anulacionDeCobroRepositoryProvider).detalle(widget.cobranzaId);
      if (!mounted) return;
      leido.fold(
        (_) => setState(() => _lectura = _Lectura.conError),
        (detalle) => setState(() {
          _detalle = detalle;
          _lectura = detalle == null ? _Lectura.ausente : _Lectura.lista;
        }),
      );
    } on Object {
      if (mounted) setState(() => _lectura = _Lectura.conError);
    }
  }

  void _cerrar() {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(_anulo);
  }

  Future<void> _anular(DetalleDelCobro detalle) async {
    if (_navegando || _cerrando) return;
    if (!detalle.dentroDelPlazo(_ahora())) {
      // Pasaron las 72 h mientras tenía la pantalla abierta: se redibuja como 30B-06.
      setState(() {});
      return;
    }
    _navegando = true;
    try {
      final salida = await AnularCobroPage.abrir(
        context,
        detalle: detalle,
        colportorId: widget.colportorId,
      );
      if (salida == null || !mounted) return;
      if (salida == SalidaDeAnular.anulada) _anulo = true;
      await _leer(mostrarCarga: false);
      if (mounted) setState(() => _recienAnulado = salida == SalidaDeAnular.anulada);
    } finally {
      _navegando = false;
    }
  }

  // --- Dibujo -----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final detalle = _detalle;
    final cuerpo = switch (_lectura) {
      _Lectura.cargando => _marco(
        cabecera: _cabecera(),
        hijos: const [EsqueletoDelCobro(etiqueta: TextosAnularCobro.cargando)],
      ),
      _Lectura.ausente => _marco(
        cabecera: _cabecera(),
        hijos: const [
          AvisoDeVenta(key: Key('detalle_cobro_ausente'), texto: TextosAnularCobro.sinElCobro),
        ],
        cta: BotonDeVenta(texto: TextosAnularCobro.volver, alPresionar: _cerrar),
      ),
      _Lectura.conError => _marco(
        cabecera: _cabecera(),
        hijos: [
          AvisoDeVenta(
            key: const Key('detalle_cobro_error_lectura'),
            texto: TextosAnularCobro.errorDeLectura,
            textoAccion: TextosAnularCobro.reintentar,
            alAccion: () => unawaited(_leer()),
          ),
        ],
      ),
      _Lectura.lista when detalle != null => _detalleListo(detalle),
      _ => _marco(
        cabecera: _cabecera(),
        hijos: const [EsqueletoDelCobro(etiqueta: TextosAnularCobro.cargando)],
      ),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _cerrar();
      },
      child: cuerpo,
    );
  }

  Widget _cabecera([DetalleDelCobro? d]) => CabeceraVenta(
    eyebrow: TextosAnularCobro.eyebrowDetalle,
    titulo: d == null
        ? TextosAnularCobro.tituloGenerico
        : TextosAnularCobro.titulo(FormatoVenta.monto(d.cobranza.montoCentavos), d.cobranza.medio),
    subtitulo: d == null
        ? null
        : TextosAnularCobro.subtituloDetalle(d.cliente, d.venta.numeroTalonario),
    alVolver: _cerrar,
  );

  Widget _marco({required Widget cabecera, required List<Widget> hijos, Widget? cta}) {
    return Scaffold(
      key: const Key('detalle_cobro_pagina'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                children: [cabecera, ...hijos],
              ),
            ),
            if (cta != null) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: cta),
          ],
        ),
      ),
    );
  }

  Widget _detalleListo(DetalleDelCobro d) {
    final c = d.cobranza;
    final ahora = _ahora();
    final anulado = c.estaAnulado;
    final enPlazo = d.dentroDelPlazo(ahora);
    final ticketValidado =
        !anulado && (ref.watch(ticketValidadoDelCobroProvider(c.id)).asData?.value ?? false);
    final sePuedeAnular = !anulado && enPlazo && !ticketValidado;
    return _marco(
      cabecera: _cabecera(d),
      hijos: [
        if (_recienAnulado && anulado) ...[
          AvisoDeCobroHecho(
            texto: TextosAnularCobro.anulado(FormatoVenta.monto(d.venta.saldoCentavos)),
          ),
          const SizedBox(height: 10),
        ],
        if (ticketValidado) ...[
          const AvisoDeVenta(
            key: Key('detalle_cobro_ticket_validado'),
            error: false,
            texto: '${TextosAnularCobro.ticketValidado} ${TextosAnularCobro.pedirleAlCoordinador}',
          ),
          const SizedBox(height: 10),
        ],
        FilasDelCobro(
          datos: [
            DatoDelCobro(
              clave: 'detalle_cobro_fecha',
              rotulo: TextosAnularCobro.fecha,
              valor: TextosAnularCobro.fechaDelCobro(c.fecha, ahora),
            ),
            DatoDelCobro(
              clave: 'detalle_cobro_medio',
              rotulo: TextosAnularCobro.medio,
              valor: TextosAnularCobro.medioDe(c.medio),
            ),
            DatoDelCobro(
              clave: 'detalle_cobro_estado',
              rotulo: TextosAnularCobro.estado,
              valor: anulado
                  ? TextosAnularCobro.estadoAnulado(c.motivoAnulacion)
                  : TextosAnularCobro.registrado,
              rojo: anulado,
            ),
          ],
        ),
        if (anulado) ...[
          const SizedBox(height: 12),
          ResumenDeLaVenta(
            titulo: TextosCobro.ventaDel(
              d.venta.numeroTalonario,
              FormatoAnulacion.aMontevideo(d.venta.fecha),
            ),
            totalCentavos: d.venta.montoTotalCentavos,
            cobradoCentavos: d.venta.cobradoCentavos,
            saldoCentavos: d.venta.saldoCentavos,
          ),
        ],
        if (!anulado && !enPlazo) ...[
          const SizedBox(height: 12),
          const AvisoInformativo(texto: TextosAnularCobro.fueraDePlazo),
        ],
      ],
      cta: sePuedeAnular
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BotonAnularCobro(alPresionar: () => unawaited(_anular(d))),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    TextosAnularCobro.hastaCuando(d.puedeAnularseHasta),
                    key: const Key('detalle_cobro_plazo'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6B82)),
                  ),
                ),
              ],
            )
          : null,
    );
  }
}
