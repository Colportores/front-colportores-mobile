import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/notificacion.dart';
import '../../domain/entities/tipo_notificacion.dart';
import '../formato_centro_notificaciones.dart';
import 'textos_centro_notificaciones.dart';

const _azulSinLeer = Color(0xFF002856);
const _fondoGlifoSinLeer = Color(0xFFE6EEF8);
const _fondoSinLeer = Colors.white;
const _fondoLeida = Color(0xFFFAFAF7);
const _textoLeida = Color(0xFF2A3A52);

/// El rótulo de un día de la lista («HOY», «AYER», «LUNES 21»).
class RotuloDiaNotificaciones extends StatelessWidget {
  const RotuloDiaNotificaciones({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return Semantics(
      header: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
        child: Text(
          texto,
          style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.4, color: colores.gris),
        ),
      ),
    );
  }
}

/// Un aviso del centro (24C·01): la hora, el título, la segunda línea y, si no se leyó, la marca
/// «Nueva» y un fondo más claro. Tocarlo lo abre. Para el lector de pantalla es un solo botón que lo
/// dice todo: «Nueva. 15:30. Cobranza a las 16:00. Av. Italia 2810».
class FilaNotificacion extends StatelessWidget {
  const FilaNotificacion({super.key, required this.notificacion, required this.onAbrir});

  final Notificacion notificacion;
  final VoidCallback onAbrir;

  IconData get _icono => switch (notificacion.tipo) {
    TipoNotificacion.recordatorioVisita => Icons.event_note_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final sinLeer = !notificacion.leida;
    final hora = horaDelAviso(notificacion.recibidaEn);
    final detalle = notificacion.detalle;
    final etiqueta = [
      if (sinLeer) TextosCentroNotificaciones.nueva,
      hora,
      notificacion.titulo,
      if (detalle != null && detalle.isNotEmpty) detalle,
    ].join('. ');

    return Semantics(
      button: true,
      container: true,
      label: etiqueta,
      onTap: onAbrir,
      excludeSemantics: true,
      child: Material(
        color: sinLeer ? _fondoSinLeer : _fondoLeida,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colores.borde),
        ),
        child: InkWell(
          onTap: onAbrir,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                spacing: 12,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: sinLeer ? _fondoGlifoSinLeer : colores.rellenoSuave,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_icono, size: 18, color: sinLeer ? _azulSinLeer : colores.gris),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          hora,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colores.gris,
                            letterSpacing: .4,
                          ),
                        ),
                        Text(
                          notificacion.titulo,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: sinLeer ? theme.colorScheme.onSurface : _textoLeida,
                          ),
                        ),
                        if (detalle != null && detalle.isNotEmpty)
                          Text(
                            detalle,
                            style: theme.textTheme.bodySmall?.copyWith(color: _textoLeida),
                          ),
                        if (sinLeer)
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _fondoGlifoSinLeer,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              TextosCentroNotificaciones.nueva,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colores.gris),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
