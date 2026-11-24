import 'package:flutter/material.dart';

import '../../../mapa/presentation/textos_registrar_visita.dart';
import '../../../mapa/presentation/widgets/piezas_alta.dart' show AvisoAlta, ColoresAlta;
import '../textos_que_venta.dart';

/// La pregunta al cancelar «$ Cobrar» (decisión de Cristian, 03/11, «Sin cobro»): «¿María no te pagó?»
/// con «Sí, anotar la visita» y «No, me equivoqué».
///
/// Devuelve `true` si [alAnotar] guardó la visita («Sí»); `false` con «No, me equivoqué» o con atrás:
/// en esos casos no se escribe nada. [alAnotar] corre **dentro** del diálogo: mientras guarda, los dos
/// botones esperan; si falla, el diálogo lo dice, los botones vuelven y la colportora puede reintentar
/// o salir con «No». Es local: no hay red en el flujo.
Future<bool> preguntarSiNoPago(
  BuildContext context, {
  required String? nombre,
  required Future<bool> Function() alAnotar,
}) async {
  final anotada = await showDialog<bool>(
    context: context,
    // Una decisión con efecto (queda una visita en el historial): no se resuelve con un toque afuera.
    barrierDismissible: false,
    builder: (_) => DialogoNoTePago(nombre: nombre, alAnotar: alAnotar),
  );
  return anotada ?? false;
}

/// El diálogo de [preguntarSiNoPago].
class DialogoNoTePago extends StatefulWidget {
  const DialogoNoTePago({super.key, required this.nombre, required this.alAnotar});

  /// El nombre de pila de quien debe; `null` si la persona ya no está en la casa.
  final String? nombre;

  /// Guarda la visita; `true` si quedó guardada.
  final Future<bool> Function() alAnotar;

  @override
  State<DialogoNoTePago> createState() => _DialogoNoTePagoState();
}

class _DialogoNoTePagoState extends State<DialogoNoTePago> {
  /// La visita se está guardando: ningún toque hace nada más y atrás espera.
  var _anotando = false;

  /// Ya se cerró con un resultado: un segundo toque (o un segundo `performAction` del lector) no cierra
  /// otra vez ni saca la pantalla de abajo.
  var _cerrando = false;

  /// El último intento de guardar falló.
  var _fallo = false;

  Future<void> _anotar() async {
    if (_anotando || _cerrando) return;
    // La guarda va antes del `setState`: dos toques en el mismo cuadro no lanzan dos guardados.
    _anotando = true;
    setState(() => _fallo = false);
    var guardada = false;
    try {
      guardada = await widget.alAnotar();
    } on Object {
      // Nada del error al mensaje: puede traer datos de la casa (convenciones §7.5).
      guardada = false;
    }
    if (!mounted) return;
    if (guardada) {
      _cerrando = true;
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _anotando = false;
      _fallo = true;
    });
  }

  void _noMeEquivoque() {
    if (_anotando || _cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // Atrás, mientras se guarda, espera; después es «No, me equivoqué»: nada se escribe.
      canPop: !_anotando && !_cerrando,
      onPopInvokedWithResult: (salio, _) {
        if (salio) _cerrando = true;
      },
      child: AlertDialog(
        scrollable: true,
        // Lo primero que lee el lector al abrirse: la pregunta, no «Alerta».
        semanticLabel: TextosQueVenta.noTePago(widget.nombre),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Semantics(
          header: true,
          child: Text(TextosQueVenta.noTePago(widget.nombre), style: theme.textTheme.titleLarge),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_anotando)
              Semantics(
                liveRegion: true,
                label: TextosQueVenta.anotandoLaVisita,
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      spacing: 12,
                      children: [
                        const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        Expanded(
                          child: Text(
                            TextosQueVenta.anotandoLaVisita,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_fallo && !_anotando)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: AvisoAlta(
                  key: ClavesNoTePago.error,
                  color: ColoresAlta.rojo,
                  glyph: '!',
                  texto: TextosRegistrarVisita.noPudimosGuardar,
                ),
              ),
            FilledButton(
              key: ClavesNoTePago.anotar,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: _anotando ? null : _anotar,
              child: const Text(TextosQueVenta.anotarLaVisita, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: ClavesNoTePago.noMeEquivoque,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                foregroundColor: ColoresAlta.tinta,
                side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
              ),
              onPressed: _anotando ? null : _noMeEquivoque,
              child: const Text(TextosQueVenta.meEquivoque, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

/// Las claves de la pregunta (para los tests y la QA).
abstract final class ClavesNoTePago {
  static const anotar = Key('no_te_pago_anotar');
  static const noMeEquivoque = Key('no_te_pago_no_me_equivoque');
  static const error = Key('no_te_pago_error');
}
