import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../textos_recuperacion.dart';

/// Abre la hoja «Recuperar tu respaldo» (vista 16, 16G·02 «Antes de empezar»; #691): antes de que
/// la app se reinicie para abrir el asistente de recuperación (vista 34), dice de qué cuenta de Drive
/// se trae el respaldo y que solo se puede mientras el teléfono no tenga nada cargado.
///
/// Devuelve `true` si la persona toca «Empezar»; `false` o `null` si toca «Ahora no» o cierra la
/// hoja.
Future<bool?> mostrarHojaRecuperarRespaldo(BuildContext context, {required String cuentaDrive}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => HojaRecuperarRespaldo(cuentaDrive: cuentaDrive),
    );

/// La hoja de 16G·02. «Empezar» es la acción principal y «Ahora no» la secundaria, como en el
/// canvas. Se contesta una sola vez: un doble toque no saca también la pantalla de abajo.
class HojaRecuperarRespaldo extends StatefulWidget {
  const HojaRecuperarRespaldo({required this.cuentaDrive, super.key});

  /// El correo de la cuenta de Google donde está el respaldo. Solo se muestra; no va a los logs.
  final String cuentaDrive;

  @override
  State<HojaRecuperarRespaldo> createState() => _HojaRecuperarRespaldoState();
}

class _HojaRecuperarRespaldoState extends State<HojaRecuperarRespaldo> {
  bool _contestada = false;

  void _contestar({required bool empezar}) {
    if (_contestada) return;
    _contestada = true;
    Navigator.of(context).pop(empezar);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final grande = MediaQuery.textScalerOf(context).scale(15) > 20;
    final forma = grande
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
        : const StadiumBorder();
    return SingleChildScrollView(
      child: Padding(
        key: const Key('configuracion_hoja_recuperar'),
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Align(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colores.bordeInput,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Semantics(
              header: true,
              child: Text(
                TextosRecuperacion.tituloHojaRecuperar,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            Text(
              TextosRecuperacion.textoHojaRecuperar(widget.cuentaDrive),
              key: const Key('configuracion_hoja_recuperar_texto'),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                FilledButton(
                  key: const Key('configuracion_hoja_recuperar_empezar'),
                  onPressed: () => _contestar(empezar: true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: forma,
                  ),
                  child: const Text(TextosRecuperacion.empezar, textAlign: TextAlign.center),
                ),
                OutlinedButton(
                  key: const Key('configuracion_hoja_recuperar_ahora_no'),
                  onPressed: () => _contestar(empezar: false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: forma,
                    side: BorderSide(color: colores.bordeInput),
                  ),
                  child: const Text(TextosRecuperacion.ahoraNo, textAlign: TextAlign.center),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
