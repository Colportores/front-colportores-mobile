import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../textos_recuperacion.dart';

/// Abre la hoja «¿Empezar sin recuperar?» (HU-SYNC-006, #610, «Recup. luego»): avisa que el respaldo
/// se puede traer después desde Configuración, pero solo mientras el teléfono no tenga nada cargado.
/// Devuelve `true` si la persona confirma «Empezar sin recuperar»; `false` o `null` si toca «Volver»
/// o cierra la hoja.
Future<bool?> mostrarHojaEmpezarSinRecuperar(BuildContext context) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => const HojaEmpezarSinRecuperar(),
);

/// La hoja. «Volver» es la acción principal (la segura: no se pierde nada por volver); «Empezar sin
/// recuperar» sigue disponible como acción secundaria. Se contesta una sola vez: un doble toque no
/// saca también la pantalla de abajo.
class HojaEmpezarSinRecuperar extends StatefulWidget {
  const HojaEmpezarSinRecuperar({super.key});

  @override
  State<HojaEmpezarSinRecuperar> createState() => _HojaEmpezarSinRecuperarState();
}

class _HojaEmpezarSinRecuperarState extends State<HojaEmpezarSinRecuperar> {
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
        key: const Key('recuperacion_hoja_empezar'),
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
                TextosRecuperacion.tituloEmpezarSinRecuperar,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            Text(
              TextosRecuperacion.avisoEmpezarSinRecuperar,
              key: const Key('recuperacion_hoja_empezar_aviso'),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                FilledButton(
                  key: const Key('recuperacion_hoja_volver'),
                  onPressed: () => _contestar(empezar: false),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: forma,
                  ),
                  child: const Text(TextosRecuperacion.volver, textAlign: TextAlign.center),
                ),
                OutlinedButton(
                  key: const Key('recuperacion_hoja_confirmar'),
                  onPressed: () => _contestar(empezar: true),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: forma,
                    side: BorderSide(color: colores.bordeInput),
                  ),
                  child: const Text(
                    TextosRecuperacion.empezarSinRecuperar,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
