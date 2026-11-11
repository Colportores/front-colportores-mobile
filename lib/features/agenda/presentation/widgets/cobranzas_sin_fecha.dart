import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ventas/presentation/flujo_cuando_cobrar.dart';
import '../../../ventas/presentation/formato_venta.dart';
import '../../domain/entities/cobranza_por_agendar.dart';
import 'piezas_agenda.dart';

/// Los textos del grupo «Sin fecha» de la Agenda (42B·01G; decisión del 10/11, P4 del PR #681).
abstract final class TextosSinFecha {
  /// «SIN FECHA (2)».
  static String rotulo(int cuantas) => 'SIN FECHA ($cuantas)';

  /// «Cobranza · Pedro Gómez».
  static String titulo(String persona) => persona.isEmpty ? 'Cobranza' : 'Cobranza · $persona';

  /// «Saldo $ 1.200 · Grecia 3307».
  static String detalle(int saldoCentavos, String direccion) => direccion.isEmpty
      ? 'Saldo ${FormatoVenta.monto(saldoCentavos)} · sin día'
      : 'Saldo ${FormatoVenta.monto(saldoCentavos)} · $direccion';

  static const ponerFecha = 'Poner fecha';

  /// Elegir el día sí funcionó pero la cita no se guardó: la cobranza sigue en el grupo.
  static const noSePudoAgendar = 'No pudimos agendar el cobro. Probá de nuevo.';
}

/// Las claves del grupo, para los tests.
abstract final class ClavesSinFecha {
  static const grupo = Key('agenda_sin_fecha');
  static Key fila(String ventaId) => Key('agenda_sin_fecha_$ventaId');
  static Key ponerFecha(String ventaId) => Key('agenda_sin_fecha_poner_$ventaId');
}

/// El grupo «Sin fecha» del final de la Agenda: las ventas con saldo que no tienen ninguna cobranza
/// agendada, cada una con «Poner fecha», que pregunta «¿Cuándo volvés a cobrar?» (42B·01B) y la agenda.
/// Al agendarla, la cita aparece en su día y la fila sale de acá sola (la lectura es reactiva).
///
/// Una a la vez: mientras una pregunta está abierta, los demás «Poner fecha» no hacen nada.
class GrupoCobranzasSinFecha extends ConsumerStatefulWidget {
  const GrupoCobranzasSinFecha({super.key, required this.colportorId, required this.cobranzas});

  final String colportorId;
  final List<CobranzaPorAgendar> cobranzas;

  @override
  ConsumerState<GrupoCobranzasSinFecha> createState() => _GrupoCobranzasSinFechaState();
}

class _GrupoCobranzasSinFechaState extends ConsumerState<GrupoCobranzasSinFecha> {
  /// La venta cuya pregunta está abierta.
  String? _poniendo;

  Future<void> _ponerFecha(CobranzaPorAgendar cobranza) async {
    if (_poniendo != null) return;
    setState(() => _poniendo = cobranza.ventaId);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    // Un aviso anterior («No pudimos agendar…») taparía «Guardar» de la pregunta.
    mensajero?.hideCurrentSnackBar();
    try {
      final quedo = await FlujoCuandoCobrar.preguntar(
        context,
        ProviderScope.containerOf(context, listen: false),
        numeroTalonario: cobranza.numeroTalonario,
        espacioId: cobranza.espacioId,
        espacioPersonaId: cobranza.espacioPersonaId,
        colportorId: widget.colportorId,
        persona: cobranza.nombrePersona,
        direccion: cobranza.direccion,
        saldoCentavos: cobranza.saldoCentavos,
      );
      if (quedo is CobranzaNoAgendada) {
        mensajero?.showSnackBar(const SnackBar(content: Text(TextosSinFecha.noSePudoAgendar)));
      }
    } on Object {
      mensajero?.showSnackBar(const SnackBar(content: Text(TextosSinFecha.noSePudoAgendar)));
    } finally {
      if (mounted) setState(() => _poniendo = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ClavesSinFecha.grupo,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RotuloDeDia(texto: TextosSinFecha.rotulo(widget.cobranzas.length)),
          for (final c in widget.cobranzas)
            _Fila(
              key: ClavesSinFecha.fila(c.ventaId),
              cobranza: c,
              alPonerFecha: _poniendo == null ? () => unawaited(_ponerFecha(c)) : null,
            ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({super.key, required this.cobranza, required this.alPonerFecha});

  final CobranzaPorAgendar cobranza;

  /// `null` mientras otra pregunta está abierta.
  final VoidCallback? alPonerFecha;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ColoresAgenda.bordeChip),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                TextosSinFecha.titulo(cobranza.nombrePersona),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                TextosSinFecha.detalle(cobranza.saldoCentavos, cobranza.direccion),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: ColoresAgenda.tinta,
                ),
              ),
            ],
          ),
          TextButton(
            key: ClavesSinFecha.ponerFecha(cobranza.ventaId),
            onPressed: alPonerFecha,
            style: TextButton.styleFrom(
              foregroundColor: ColoresAgenda.azul,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text(TextosSinFecha.ponerFecha),
          ),
        ],
      ),
    );
  }
}
