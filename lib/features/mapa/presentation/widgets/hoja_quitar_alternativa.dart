import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/hoja_inferior.dart';
import '../../domain/usecases/ubicacion_alternativa_use_cases.dart';
import '../providers/ubicacion_alternativa_providers.dart';
import '../textos_baja_persona.dart' show mensajeDeFallaDePersona;
import '../textos_ubicacion_alternativa.dart';
import 'piezas_alta.dart';
import 'piezas_ubicacion_alternativa.dart';

/// Abre «¿Quitar …?» (HU-UBI-013, vista 22A·07). Devuelve `true` si la alternativa se quitó, y `null` si
/// se cerró sin hacer nada.
///
/// [titulo] nombra la ubicación que se quita; [cuerpo] dice a dónde van las próximas cobranzas. Las ya
/// agendadas no cambian. Quitar también sirve cuando la alternativa está dada de baja o no está en el
/// teléfono: es justo lo que hay que hacer entonces.
Future<bool?> mostrarHojaQuitarAlternativa(
  BuildContext context, {
  required String personaId,
  required String espacioId,
  required String nombre,
  required String titulo,
  required String cuerpo,
}) => mostrarHojaInferior<bool>(
  context: context,
  isScrollControlled: true,
  // Sin arrastrar para cerrar: mientras se escribe la hoja no se puede cerrar de costado.
  enableDrag: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaQuitarAlternativa(
    personaId: personaId,
    espacioId: espacioId,
    nombre: nombre,
    titulo: titulo,
    cuerpo: cuerpo,
  ),
);

/// La hoja de quitar la ubicación alternativa (22A·07): «Quitar» escribe; «Cancelar» cierra sin tocar
/// nada. Mientras se escribe, «Quitando…» y nada se puede tocar ni cerrar; si falla, el aviso rojo con
/// lo que pasó y el botón vuelve a quedar habilitado.
class HojaQuitarAlternativa extends ConsumerStatefulWidget {
  const HojaQuitarAlternativa({
    super.key,
    required this.personaId,
    required this.espacioId,
    required this.nombre,
    required this.titulo,
    required this.cuerpo,
  });

  final String personaId;
  final String espacioId;
  final String nombre;
  final String titulo;
  final String cuerpo;

  @override
  ConsumerState<HojaQuitarAlternativa> createState() => _HojaQuitarAlternativaState();
}

class _HojaQuitarAlternativaState extends ConsumerState<HojaQuitarAlternativa> {
  var _quitando = false;
  String? _falla;

  Future<void> _quitar() async {
    if (_quitando) return;
    setState(() {
      _quitando = true;
      _falla = null;
    });
    Failure? falla;
    var quitada = false;
    try {
      final r = await ref.read(quitarUbicacionAlternativaUseCaseProvider)(
        QuitarUbicacionAlternativaParams(personaId: widget.personaId, espacioId: widget.espacioId),
      );
      r.fold((f) => falla = f, (_) => quitada = true);
    } on Object catch (e) {
      falla = FailureInesperado(causa: e.runtimeType.toString());
    }
    if (!mounted) return;
    if (quitada) {
      // El guard no se suelta: la hoja se va y ningún toque más la cierra dos veces.
      Navigator.of(context).pop<bool>(true);
      return;
    }
    setState(() {
      _quitando = false;
      _falla = mensajeDeFallaDePersona(
        falla ?? const FailureInesperado(),
        TextosUbicacionAlternativa.noPudimosQuitar(widget.nombre),
      );
    });
  }

  void _cancelar() {
    if (!_quitando) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Mientras la baja del vínculo se escribe no se sale: el resultado se perdería.
      canPop: !_quitando,
      child: SafeArea(
        key: ClavesAlternativa.hojaQuitar,
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
                        liveRegion: true,
                        child: Text(
                          widget.titulo,
                          style: const TextStyle(
                            fontFamily: 'SourceSerif4',
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.cuerpo,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: ColoresAlta.tinta, height: 1.5),
                      ),
                      if (_falla != null) ...[
                        const SizedBox(height: 12),
                        KeyedSubtree(
                          key: ClavesAlternativa.hojaQuitarError,
                          child: AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: _falla!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                key: ClavesAlternativa.hojaQuitarConfirmar,
                onPressed: _quitando ? null : () => unawaited(_quitar()),
                style: FilledButton.styleFrom(
                  backgroundColor: ColoresAlta.rojo,
                  disabledBackgroundColor: ColoresAlta.rojo.withValues(alpha: .85),
                  disabledForegroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _quitando
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
                          Flexible(
                            child: Text(
                              TextosUbicacionAlternativa.quitando,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        TextosUbicacionAlternativa.quitarAccion,
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(height: 4),
              TextButton(
                key: ClavesAlternativa.hojaQuitarCancelar,
                onPressed: _quitando ? null : _cancelar,
                style: TextButton.styleFrom(
                  foregroundColor: ColoresAlta.azul,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text(TextosUbicacionAlternativa.cancelar, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
