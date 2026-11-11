import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../domain/entities/nueva_venta.dart';
import '../formato_venta.dart';
import '../textos_venta_que_crece.dart';
import '../widgets/piezas_venta.dart';

/// Cuándo se entrega lo vendido (27A·14).
enum MomentoDeEntrega { ahora, otroDia }

/// Lo que eligió en «¿Y ahora?».
final class SeguimientoDeLaVenta {
  const SeguimientoDeLaVenta({
    this.entrega,
    this.cobrarAhora = false,
    this.modificarCuotas = false,
  });

  final MomentoDeEntrega? entrega;
  final bool cobrarAhora;

  /// «Modificar cuotas» (30A·09) con el saldo nuevo, tras sumar a una venta con plan (42B·09D).
  final bool modificarCuotas;
}

/// Lo que cambia en «¿Y ahora?» cuando se sumó un libro a una venta abierta (42B·09D): el título,
/// la línea de abajo, el rótulo de la entrega, el detalle del cobro y, con un plan de cuotas en
/// curso, «Modificar cuotas».
final class TextosDelCierreQueCrece {
  const TextosDelCierreQueCrece({
    required this.eyebrow,
    required this.titulo,
    required this.subtitulo,
    required this.rotuloEntrega,
    required this.detalleCobro,
    this.detalleModificarCuotas,
  });

  final String eyebrow;
  final String titulo;
  final String subtitulo;
  final String rotuloEntrega;
  final String detalleCobro;

  /// La línea de «Modificar cuotas»; `null` = la venta no tiene cuotas abiertas y no se ofrece.
  final String? detalleModificarCuotas;
}

/// «Venta registrada: ¿y ahora?» (27A·14): encadena la entrega y el cobro de lo que se acaba de
/// vender.
///
/// Cada opción se muestra solo si su destino existe: «Entregar ahora» ([conEntregarAhora], la vista
/// 27B, HU-VEN-002), «Entregar otro día» ([conEntregarOtroDia], 27C, HU-VEN-003) y «Cobrar ahora»
/// ([conCobro], la vista 28). Ofrecer un botón que no lleva a ningún lado sería mentir (decisión P7 de
/// #158). El grupo ENTREGA aparece con que haya una de sus dos opciones; sin ninguna opción queda solo
/// la confirmación, con un botón.
class VentaRegistradaPage extends StatefulWidget {
  const VentaRegistradaPage({
    super.key,
    required this.guardada,
    required this.nombreDelCliente,
    required this.alContinuar,
    required this.alTerminar,
    this.conEntregarAhora = false,
    this.conEntregarOtroDia = false,
    this.conCobro = false,
    this.crece,
  });

  final VentaGuardada guardada;

  /// Se sumó un libro a una venta abierta (42B·09D); `null` = una venta nueva (27A·14).
  final TextosDelCierreQueCrece? crece;
  final String nombreDelCliente;
  final bool conEntregarAhora;
  final bool conEntregarOtroDia;
  final bool conCobro;
  final ValueChanged<SeguimientoDeLaVenta> alContinuar;
  final VoidCallback alTerminar;

  @override
  State<VentaRegistradaPage> createState() => _VentaRegistradaPageState();
}

class _VentaRegistradaPageState extends State<VentaRegistradaPage> {
  MomentoDeEntrega? _entrega;
  var _cobrar = false;
  var _modificarCuotas = false;
  var _enCurso = false;

  bool get _conModificarCuotas => widget.crece?.detalleModificarCuotas != null;

  /// Sin entrega ni cobro todavía (sus pantallas no existen) no hay nada que elegir: queda la
  /// confirmación con un solo botón que vuelve (decisión P7 de #158).
  bool get _sinSeguimiento =>
      !widget.conEntregarAhora &&
      !widget.conEntregarOtroDia &&
      !widget.conCobro &&
      !_conModificarCuotas;

  void _continuar() {
    if (_enCurso) return;
    _enCurso = true;
    widget.alContinuar(
      SeguimientoDeLaVenta(
        entrega: _entrega,
        cobrarAhora: _cobrar,
        modificarCuotas: _modificarCuotas,
      ),
    );
  }

  void _terminar() {
    if (_enCurso) return;
    _enCurso = true;
    widget.alTerminar();
  }

  @override
  Widget build(BuildContext context) {
    final venta = widget.guardada.venta;
    final crece = widget.crece;
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('venta_registrada_pagina'),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  children: [
                    CabeceraVenta(
                      eyebrow:
                          crece?.eyebrow ?? TextosVenta.eyebrowTalonario(venta.numeroTalonario),
                      titulo: crece?.titulo ?? TextosVenta.tituloRegistrada,
                      subtitulo:
                          crece?.subtitulo ??
                          TextosVenta.clienteYMonto(
                            widget.nombreDelCliente,
                            FormatoVenta.monto(venta.montoTotalCentavos),
                          ),
                    ),
                    if (widget.conEntregarAhora || widget.conEntregarOtroDia) ...[
                      RotuloDeSeccion(crece?.rotuloEntrega ?? TextosVenta.entrega),
                      const SizedBox(height: 7),
                      if (widget.conEntregarAhora)
                        FilaElegible(
                          titulo: TextosVenta.entregarAhora,
                          detalle: TextosVenta.entregarAhoraSub,
                          elegida: _entrega == MomentoDeEntrega.ahora,
                          alPresionar: () => setState(() => _entrega = MomentoDeEntrega.ahora),
                        ),
                      if (widget.conEntregarAhora && widget.conEntregarOtroDia)
                        const SizedBox(height: 8),
                      if (widget.conEntregarOtroDia)
                        FilaElegible(
                          titulo: TextosVenta.entregarOtroDia,
                          detalle: TextosVenta.entregarOtroDiaSub,
                          elegida: _entrega == MomentoDeEntrega.otroDia,
                          alPresionar: () => setState(() => _entrega = MomentoDeEntrega.otroDia),
                        ),
                    ],
                    if (widget.conCobro || _conModificarCuotas) ...[
                      const RotuloDeSeccion(TextosVenta.cobro),
                      const SizedBox(height: 7),
                      if (widget.conCobro)
                        FilaElegible(
                          titulo: TextosVenta.cobrarAhora,
                          detalle: crece?.detalleCobro ?? TextosVenta.cobrarAhoraSub,
                          elegida: _cobrar,
                          alPresionar: () => setState(() => _cobrar = !_cobrar),
                        ),
                      if (widget.conCobro && _conModificarCuotas) const SizedBox(height: 8),
                      if (crece?.detalleModificarCuotas case final detalle?)
                        FilaElegible(
                          key: const Key('venta_modificar_cuotas'),
                          titulo: TextosVentaQueCrece.modificarCuotas,
                          detalle: detalle,
                          elegida: _modificarCuotas,
                          alPresionar: () => setState(() => _modificarCuotas = !_modificarCuotas),
                        ),
                    ],
                  ],
                ),
              ),
              if (_sinSeguimiento)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: BotonDeVenta(
                    key: const Key('venta_terminar'),
                    texto: TextosVenta.listo,
                    alPresionar: _terminar,
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: BotonDeVenta(texto: TextosVenta.continuar, alPresionar: _continuar),
                ),
                TextButton(
                  key: const Key('venta_terminar'),
                  onPressed: _terminar,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text(
                    TextosVenta.terminarSinNada,
                    style: TextStyle(fontWeight: FontWeight.w600, color: ColoresAgenda.azul),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
