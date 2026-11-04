import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/estado_agenda.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/usecases/cancelar_agenda_use_case.dart';
import '../textos_cancelar_agenda.dart';
import 'hoja_cancelar_agenda.dart';

/// El enlace «Cancelar agenda» al pie del detalle de una visita (vista 23, 23C·01) y todo lo que
/// sigue (HU-VIS-004): la hoja de confirmación (23C·04), la cancelación y el aviso «Agenda
/// cancelada.» (23C·05).
///
/// Lo monta el detalle (#409) con la agenda que muestra; no lee ni escribe nada por su cuenta salvo
/// por la hoja. Va «lejos del botón principal» (nota de 23C·01): el que lo monta lo pone al pie.
///
/// - Solo se ve con la agenda `PROGRAMADA`: una cumplida, no cumplida o cancelada no se cancela
///   (23C·06 lo explica con su aviso, que es del detalle). Cuando el detalle se repinta con la
///   agenda ya cancelada, el enlace desaparece.
/// - Un doble toque abre una sola hoja.
/// - Al cancelar, muestra el aviso (con la advertencia si el teléfono no pudo sacar el recordatorio)
///   y llama a [alCancelar]; sin [alCancelar] cierra el detalle y vuelve a la lista (23C·05).
/// - Si la hoja se cierra sin cancelar llama a [alVolverSinCancelar]: la agenda pudo cambiar mientras
///   estaba abierta (se cumplió, 23C·06) y quien la muestra la vuelve a leer.
class EnlaceCancelarAgenda extends StatefulWidget {
  const EnlaceCancelarAgenda({
    super.key,
    required this.agendaId,
    required this.tipo,
    required this.estado,
    this.alCancelar,
    this.alVolverSinCancelar,
  });

  final String agendaId;
  final TipoAgenda tipo;
  final EstadoAgenda estado;

  /// Se llama con lo que dejó la cancelación, después del aviso. Sin esto, se cierra la pantalla
  /// que lo muestra (`Navigator.maybePop`).
  final ValueChanged<ResultadoCancelarAgenda>? alCancelar;

  /// Se llama cuando la hoja se cerró y no se canceló nada («Volver», atrás, o la agenda ya no se
  /// podía cancelar).
  final VoidCallback? alVolverSinCancelar;

  @override
  State<EnlaceCancelarAgenda> createState() => _EnlaceCancelarAgendaState();
}

class _EnlaceCancelarAgendaState extends State<EnlaceCancelarAgenda> {
  /// La hoja está abierta: un segundo toque (o un toque mientras vuelve) no abre otra.
  var _abierta = false;

  Future<void> _tocar() async {
    if (_abierta) return;
    _abierta = true;
    // El aviso se pide antes de esperar: la pantalla que lo mostró puede cerrarse en el medio.
    final mensajero = ScaffoldMessenger.maybeOf(context);
    ResultadoCancelarAgenda? resultado;
    try {
      resultado = await mostrarHojaCancelarAgenda(
        context,
        agendaId: widget.agendaId,
        tipo: widget.tipo,
      );
    } finally {
      _abierta = false;
    }
    if (resultado == null) {
      if (mounted) widget.alVolverSinCancelar?.call();
      return;
    }
    mensajero
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            resultado.recordatorioCancelado
                ? TextosCancelarAgenda.cancelada
                : TextosCancelarAgenda.canceladaConRecordatorio,
          ),
          duration: Duration(seconds: resultado.recordatorioCancelado ? 4 : 8),
        ),
      );
    if (!mounted) return;
    final alCancelar = widget.alCancelar;
    if (alCancelar != null) {
      alCancelar(resultado);
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.estado != EstadoAgenda.programada) return const SizedBox.shrink();
    return Center(
      child: TextButton(
        onPressed: () => unawaited(_tocar()),
        style: TextButton.styleFrom(
          foregroundColor: ColoresColportaje.unica.gris,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
        child: const Text(TextosCancelarAgenda.cancelarAgenda, textAlign: TextAlign.center),
      ),
    );
  }
}
