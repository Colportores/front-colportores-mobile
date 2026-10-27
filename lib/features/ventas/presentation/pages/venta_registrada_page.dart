import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../domain/entities/nueva_venta.dart';
import '../formato_venta.dart';
import '../widgets/piezas_venta.dart';

/// Cuándo se entrega lo vendido (27A·14).
enum MomentoDeEntrega { ahora, otroDia }

/// Lo que eligió en «¿Y ahora?».
final class SeguimientoDeLaVenta {
  const SeguimientoDeLaVenta({this.entrega, this.cobrarAhora = false});

  final MomentoDeEntrega? entrega;
  final bool cobrarAhora;
}

/// «Venta registrada: ¿y ahora?» (27A·14): encadena la entrega y el cobro de lo que se acaba de
/// vender.
///
/// Los grupos ENTREGA y COBRO se muestran solo si [conEntrega] / [conCobro]: sus destinos (la
/// entrega, HU-VEN-002; el cobro, la vista 28) todavía no existen, y ofrecer un botón que no lleva a
/// ningún lado sería mentir. Sin ninguno de los dos, la pantalla no se usa.
class VentaRegistradaPage extends StatefulWidget {
  const VentaRegistradaPage({
    super.key,
    required this.guardada,
    required this.nombreDelCliente,
    required this.alContinuar,
    required this.alTerminar,
    this.conEntrega = false,
    this.conCobro = false,
  });

  final VentaGuardada guardada;
  final String nombreDelCliente;
  final bool conEntrega;
  final bool conCobro;
  final ValueChanged<SeguimientoDeLaVenta> alContinuar;
  final VoidCallback alTerminar;

  @override
  State<VentaRegistradaPage> createState() => _VentaRegistradaPageState();
}

class _VentaRegistradaPageState extends State<VentaRegistradaPage> {
  MomentoDeEntrega? _entrega;
  var _cobrar = false;
  var _enCurso = false;

  void _continuar() {
    if (_enCurso) return;
    _enCurso = true;
    widget.alContinuar(SeguimientoDeLaVenta(entrega: _entrega, cobrarAhora: _cobrar));
  }

  void _terminar() {
    if (_enCurso) return;
    _enCurso = true;
    widget.alTerminar();
  }

  @override
  Widget build(BuildContext context) {
    final venta = widget.guardada.venta;
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
                      eyebrow: TextosVenta.eyebrowTalonario(venta.numeroTalonario),
                      titulo: TextosVenta.tituloRegistrada,
                      subtitulo: TextosVenta.clienteYMonto(
                        widget.nombreDelCliente,
                        FormatoVenta.monto(venta.montoTotalCentavos),
                      ),
                    ),
                    if (widget.conEntrega) ...[
                      const RotuloDeSeccion(TextosVenta.entrega),
                      const SizedBox(height: 7),
                      FilaElegible(
                        titulo: TextosVenta.entregarAhora,
                        detalle: TextosVenta.entregarAhoraSub,
                        elegida: _entrega == MomentoDeEntrega.ahora,
                        alPresionar: () => setState(() => _entrega = MomentoDeEntrega.ahora),
                      ),
                      const SizedBox(height: 8),
                      FilaElegible(
                        titulo: TextosVenta.entregarOtroDia,
                        detalle: TextosVenta.entregarOtroDiaSub,
                        elegida: _entrega == MomentoDeEntrega.otroDia,
                        alPresionar: () => setState(() => _entrega = MomentoDeEntrega.otroDia),
                      ),
                    ],
                    if (widget.conCobro) ...[
                      const RotuloDeSeccion(TextosVenta.cobro),
                      const SizedBox(height: 7),
                      FilaElegible(
                        titulo: TextosVenta.cobrarAhora,
                        detalle: TextosVenta.cobrarAhoraSub,
                        elegida: _cobrar,
                        alPresionar: () => setState(() => _cobrar = !_cobrar),
                      ),
                    ],
                  ],
                ),
              ),
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
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
