import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/tipo_notificacion.dart';
import 'textos_filtro_tipo_notificacion.dart';

const _azul = Color(0xFF002856);
const _fondoGlifo = Color(0xFFE6EEF8);
const _fondoActiva = Color(0xFFF2F6FB);

/// La fila «Tipo de aviso» de arriba de la lista del centro (24D·01 y 24D·03; HU-NOT-005, #484).
///
/// Sin filtro dice «Todos» y «Cambiar»; con un tipo elegido lo dice, lleva el borde marcado y suma
/// «✕ Quitar», que vuelve a «Todos». Tocar la fila abre la hoja para elegir el tipo (24D·02).
/// Para el lector de pantalla son dos botones: la fila («Tipo de aviso: Ticket validado. Cambiar») y,
/// con filtro, el de quitarlo.
class FilaTipoDeAviso extends StatelessWidget {
  const FilaTipoDeAviso({
    super.key,
    required this.tipo,
    required this.onCambiar,
    required this.onQuitar,
  });

  /// El tipo filtrado, o `null` para «Todos».
  final TipoNotificacion? tipo;
  final VoidCallback onCambiar;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final activa = tipo != null;
    // Con el texto muy grande, «Cambiar» y «Quitar» no entran al costado: bajan debajo del tipo.
    final grande = MediaQuery.textScalerOf(context).scale(14) > 20;
    final borde = activa
        ? const BorderSide(color: _azul, width: 2)
        : BorderSide(color: colores.borde);
    final quitar = !activa
        ? null
        : Semantics(
            button: true,
            label: TextosFiltroTipoNotificacion.quitarEtiqueta,
            onTap: onQuitar,
            excludeSemantics: true,
            child: InkWell(
              key: const Key('filtro_quitar'),
              onTap: onQuitar,
              borderRadius: BorderRadius.circular(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 54, minWidth: 48),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(grande ? 14 : 8, 10, 14, 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      Icon(Icons.close, size: 16, color: theme.colorScheme.primary),
                      Flexible(
                        child: Text(
                          TextosFiltroTipoNotificacion.quitar,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
    final cambiar = activa
        ? null
        : Text(
            TextosFiltroTipoNotificacion.cambiar,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          );
    final cuerpo = Semantics(
      button: true,
      container: true,
      label: TextosFiltroTipoNotificacion.etiquetaFila(tipo),
      onTap: onCambiar,
      excludeSemantics: true,
      child: InkWell(
        key: const Key('filtro_cambiar'),
        onTap: onCambiar,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              spacing: 12,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _fondoGlifo,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.filter_list, size: 18, color: theme.colorScheme.primary),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        TextosFiltroTipoNotificacion.rotuloFila,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colores.gris,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        TextosFiltroTipoNotificacion.nombre(tipo),
                        key: const Key('filtro_tipo_actual'),
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (grande && cambiar != null) cambiar,
                    ],
                  ),
                ),
                if (!grande && cambiar != null) cambiar,
              ],
            ),
          ),
        ),
      ),
    );
    return Material(
      key: const Key('filtro_fila'),
      color: activa ? _fondoActiva : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: borde),
      child: grande
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cuerpo,
                if (quitar != null) Align(alignment: Alignment.centerRight, child: quitar),
              ],
            )
          : Row(
              children: [
                Expanded(child: cuerpo),
                ?quitar,
              ],
            ),
    );
  }
}
