import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../mapa/presentation/widgets/piezas_alta.dart' show AvisoAlta, ColoresAlta;
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/usecases/cancelar_agenda_use_case.dart';
import '../providers/cancelar_agenda_providers.dart';
import '../textos_cancelar_agenda.dart';

/// Abre la hoja «¿Cancelar la entrevista?» (vista 23, 23C·04) de la agenda [agendaId]. Devuelve lo que
/// dejó la cancelación, o `null` si la colportora cerró sin cancelar.
///
/// La abre quien tiene la agenda delante: el detalle de la visita (23C·01, #409), con
/// `EnlaceCancelarAgenda`. La hoja escribe ella misma (`CancelarAgendaUseCase`): un cierre con
/// resultado es una agenda ya cancelada.
Future<ResultadoCancelarAgenda?> mostrarHojaCancelarAgenda(
  BuildContext context, {
  required String agendaId,
  required TipoAgenda tipo,
}) => showModalBottomSheet<ResultadoCancelarAgenda>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Sin arrastrar para cerrar: mientras la cancelación se escribe la hoja no se puede cerrar de
  // costado (el arrastre no pasa por el `PopScope`). Las salidas son «Volver», el atrás y el toque
  // afuera.
  enableDrag: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaCancelarAgenda(agendaId: agendaId, tipo: tipo),
);

/// La hoja de cancelar una agenda (23C·04): el título según el tipo, lo que pasa al cancelar y dos
/// salidas, «Cancelar agenda» y «Volver».
///
/// - Mientras se escribe, «Cancelando…» y nada se puede tocar ni cerrar. Un doble toque escribe una
///   sola vez.
/// - Si falla, el aviso rojo (la agenda sigue como estaba) y el botón pasa a «Reintentar», otra vez
///   habilitado.
/// - Si la agenda ya no se puede cancelar (se cumplió, o ya no está), el aviso dice por qué y queda
///   solo «Volver»: reintentar no cambiaría nada.
class HojaCancelarAgenda extends ConsumerStatefulWidget {
  const HojaCancelarAgenda({super.key, required this.agendaId, required this.tipo});

  final String agendaId;
  final TipoAgenda tipo;

  @override
  ConsumerState<HojaCancelarAgenda> createState() => _HojaCancelarAgendaState();
}

class _HojaCancelarAgendaState extends ConsumerState<HojaCancelarAgenda> {
  var _enviando = false;
  String? _falla;

  /// La falla fue de validación (la agenda ya no se puede cancelar): no tiene sentido reintentar.
  var _sinReintento = false;

  /// Hubo un intento que falló: el botón dice «Reintentar».
  var _fallo = false;

  Future<void> _cancelar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _falla = null;
    });
    Failure? falla;
    ResultadoCancelarAgenda? resultado;
    try {
      final r = await ref.read(cancelarAgendaUseCaseProvider)(
        CancelarAgendaParams(agendaId: widget.agendaId),
      );
      r.fold((f) => falla = f, (x) => resultado = x);
    } on Object catch (e) {
      falla = FailureInesperado(causa: e.runtimeType.toString());
    }
    if (!mounted) return;
    final hecho = resultado;
    if (hecho != null) {
      Navigator.of(context).pop<ResultadoCancelarAgenda>(hecho);
      return;
    }
    final motivo = falla;
    setState(() {
      _enviando = false;
      _fallo = true;
      if (motivo is FailureValidacion) {
        _sinReintento = true;
        _falla = motivo.campos.isNotEmpty
            ? motivo.campos.values.first
            : TextosCancelarAgenda.yaNoSePuedeCancelar;
      } else {
        _falla = TextosCancelarAgenda.noPudimosCancelar;
      }
    });
  }

  void _cerrar() {
    if (!_enviando) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Mientras la cancelación se escribe no se sale: el resultado se perdería.
      canPop: !_enviando,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF90A0B7),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          TextosCancelarAgenda.titulo(widget.tipo),
                          style: const TextStyle(
                            fontFamily: 'SourceSerif4',
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        TextosCancelarAgenda.cuerpo(widget.tipo),
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: ColoresAlta.tinta, height: 1.5),
                      ),
                      if (_falla != null) ...[
                        const SizedBox(height: 12),
                        AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: _falla!),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (!_sinReintento) _principal(),
              const SizedBox(height: 4),
              _secundario(),
            ],
          ),
        ),
      ),
    );
  }

  /// «Cancelar agenda» en rojo. Trabajando, «Cancelando…» y sin otro toque; tras una falla,
  /// «Reintentar».
  Widget _principal() {
    final etiqueta = _fallo ? TextosCancelarAgenda.reintentar : TextosCancelarAgenda.cancelarAgenda;
    return FilledButton(
      onPressed: _enviando ? null : () => unawaited(_cancelar()),
      style: FilledButton.styleFrom(
        backgroundColor: ColoresAlta.rojo,
        disabledBackgroundColor: ColoresAlta.rojo.withValues(alpha: .85),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
      ),
      child: _enviando
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                ),
                Flexible(child: Text(TextosCancelarAgenda.cancelando, textAlign: TextAlign.center)),
              ],
            )
          : Text(etiqueta, textAlign: TextAlign.center),
    );
  }

  Widget _secundario() => OutlinedButton(
    onPressed: _enviando ? null : _cerrar,
    style: OutlinedButton.styleFrom(
      foregroundColor: ColoresAlta.tinta,
      side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
      minimumSize: const Size.fromHeight(52),
      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
    ),
    child: const Text(TextosCancelarAgenda.volver, textAlign: TextAlign.center),
  );
}
