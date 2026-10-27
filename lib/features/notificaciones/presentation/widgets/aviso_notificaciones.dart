import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';

/// Los textos de la vista 24, grupo A (permiso de notificaciones, HU-NOT-001).
///
/// Salen del canvas (`24 Notificaciones.dc.html`, 24A·01 a 24A·06) salvo los marcados «propuesta»:
/// el canvas no los dibuja y están para confirmar.
abstract final class TextosNotificaciones {
  /// 24A·01. El título es el de la HU; los tres motivos son del canvas.
  static const pedidoTitulo = 'Activá notificaciones para no perderte avisos importantes';
  static const motivoRecordatorios = 'Recordatorios de tus visitas';
  static const motivoRecordatoriosDetalle = 'Con la dirección y el tipo, sin el nombre del cliente';
  static const motivoPedidos = 'Pedidos y tickets revisados';
  static const motivoZona = 'Cambios de zona y de campaña';
  static const activar = 'Activar notificaciones';
  static const ahoraNo = 'Ahora no';

  /// El pedido no se pudo mostrar (falló la plataforma). Propuesta: el canvas no lo dibuja.
  static const pedidoFallo =
      'No pudimos pedir el permiso. Probá de nuevo, o tocá «Ahora no» y activalas después en '
      'Configuración.';

  /// Lo mismo, pero desde Configuración, donde no hay «Ahora no». Propuesta.
  static const activarFallo = 'No pudimos pedir el permiso. Probá de nuevo.';

  /// 24A·03. El texto es el de la HU; el canvas dice «Las notificaciones están apagadas. Podés
  /// activarlas en configuración.» y la diferencia va en el PR (manda la HU).
  static const avisoApagadas = 'Notificaciones desactivadas. Activá en Configuración.';
  static const avisoIrAConfiguracion = 'Ir a configuración';
  static const avisoCerrar = 'Cerrar aviso';

  /// 24A·04 y 24A·05.
  static const activadasToast = 'Notificaciones activadas.';
  static const activadasSinConexionToast =
      'Activadas. Los recordatorios ya funcionan; los avisos de tu coordinador empiezan a llegar '
      'cuando haya conexión.';

  /// 24A·06.
  static const bloqueadas =
      'Las notificaciones están bloqueadas en los ajustes del teléfono. Desde la app no las '
      'podemos activar.';
  static const abrirAjustes = 'Abrir ajustes del teléfono';

  /// Cuando el teléfono no pudo abrir la pantalla de ajustes. Propuesta: el canvas no lo dibuja.
  static const ajustesNoAbren =
      'No pudimos abrir los ajustes. Buscá «Colportaje» en los ajustes del teléfono, en '
      'Notificaciones.';

  /// 24B·04: Configuración › Notificaciones con el permiso del teléfono sin pedir.
  static const apagadas =
      'Las notificaciones están apagadas en el teléfono. Estas opciones valen cuando las actives.';
  static const activarCorto = 'Activar';

  /// No se pudo leer el estado. Propuesta.
  static const errorAlLeer = 'No pudimos revisar las notificaciones.';
  static const reintentar = 'Reintentar';

  static const filaConfiguracion = 'Notificaciones';

  // Vista 24, grupo B (preferencias, HU-NOT-004). Salen del canvas salvo los marcados «propuesta».
  static const seccionRecordatorios = 'RECORDATORIOS';
  static const recordatoriosTitulo = 'Recordatorios de agenda';
  static const recordatoriosDetalle = 'Antes de cada visita agendada';
  static const anticipacionTitulo = 'Anticipación';
  static const anticipacionMin = '5 min';
  static const anticipacionMax = '120 min';

  /// «30 min antes».
  static String anticipacionValor(int minutos) => '$minutos min antes';

  /// 24B·02.
  static const recordatoriosApagados =
      'Dejamos de programar los recordatorios, también los de las visitas que ya agendaste.';

  /// 24B·06.
  static const errorAlGuardar =
      'No pudimos guardar el cambio. El interruptor volvió a como estaba.';

  /// 24B·06 cuando lo que no se guardó es la anticipación, o más de un cambio (decidido el 27/10, mapa
  /// §2: el aviso dice lo que volvió; «Reintentar» repite todo).
  static const errorAlGuardarVarios = 'No pudimos guardar los cambios. Volvieron a como estaban.';

  /// Los textos de esta sección que el canvas no dibuja (el singular, el «Guardado: …» sin visitas y
  /// el error al leer) quedaron decididos el 27/10 (mapa §2).
  ///
  /// 24B·03, con la cantidad real: «Reprogramamos 4 recordatorios: te avisamos 60 min antes.».
  /// Con uno, en singular. Sin ninguno (no hay visitas agendadas) no hay nada que contar: propuesta.
  static String anticipacionCambiada({required int reprogramados, required int minutos}) {
    if (reprogramados == 0) return 'Guardado: te avisamos $minutos min antes.';
    final recordatorios = reprogramados == 1 ? '1 recordatorio' : '$reprogramados recordatorios';
    return 'Reprogramamos $recordatorios: te avisamos $minutos min antes.';
  }

  /// No se pudieron leer las preferencias. Propuesta: el canvas no lo dibuja.
  static const errorAlLeerPreferencias = 'No pudimos leer tus preferencias de recordatorios.';
}

enum TonoAviso { info, advertencia, error }

/// Recuadro de aviso de la vista 24 (los `banner` del canvas): un ícono, el texto, una acción
/// opcional y una ✕ opcional. El lector de pantalla lo anuncia al aparecer (región viva).
class AvisoNotificaciones extends StatelessWidget {
  const AvisoNotificaciones({
    super.key,
    required this.tono,
    required this.texto,
    this.textoAccion,
    this.onAccion,
    this.onCerrar,
    this.textoKey,
    this.accionKey,
    this.cerrarKey,
  });

  final TonoAviso tono;
  final String texto;

  /// El rótulo de la acción. Sin él no hay acción. Con [onAccion] `null` la acción se ve apagada
  /// (mientras una anterior sigue en curso).
  final String? textoAccion;
  final VoidCallback? onAccion;

  /// La ✕. Sin él, el aviso no se cierra.
  final VoidCallback? onCerrar;

  final Key? textoKey;
  final Key? accionKey;
  final Key? cerrarKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final esquema = theme.colorScheme;
    final (borde, fondo, icono) = switch (tono) {
      TonoAviso.info => (esquema.onSurfaceVariant, esquema.surfaceContainerHighest, Icons.info),
      TonoAviso.advertencia => (const Color(0xFFA98330), const Color(0xFFFFFDF6), Icons.error),
      TonoAviso.error => (esquema.error, esquema.surfaceContainerHighest, Icons.error),
    };
    final escala = MediaQuery.textScalerOf(context).scale(14);
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fondo,
          border: Border.all(color: borde, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(14, 12, onCerrar == null ? 14 : 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: ExcludeSemantics(child: Icon(icono, size: 20, color: borde)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      texto,
                      key: textoKey,
                      style: theme.textTheme.bodyMedium?.copyWith(color: esquema.onSurface),
                    ),
                    if (textoAccion != null)
                      TextButton(
                        key: accionKey,
                        onPressed: onAccion,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: EdgeInsets.symmetric(horizontal: escala > 20 ? 4 : 0),
                          alignment: AlignmentDirectional.centerStart,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(textoAccion!),
                      ),
                  ],
                ),
              ),
              if (onCerrar != null)
                IconButton(
                  key: cerrarKey,
                  tooltip: TextosNotificaciones.avisoCerrar,
                  onPressed: onCerrar,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: Icon(Icons.close, size: 20, color: colores.gris),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El toast de «Notificaciones activadas.» (24A·04) o, sin conexión, el de 24A·05.
///
/// Se muestra en el mensajero de la app, que sobrevive al cambio de pantalla: sirve tanto desde el
/// pedido del primer ingreso (que se va al activar) como desde Configuración.
void avisarNotificacionesActivadas(ScaffoldMessengerState mensajero, {required bool sinConexion}) {
  mensajero
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        key: const Key('notificaciones_activadas_aviso'),
        duration: Duration(seconds: sinConexion ? 8 : 4),
        content: Row(
          spacing: 12,
          children: [
            const ExcludeSemantics(child: Icon(Icons.check, color: Color(0xFF9FD3AE))),
            Expanded(
              child: Text(
                sinConexion
                    ? TextosNotificaciones.activadasSinConexionToast
                    : TextosNotificaciones.activadasToast,
              ),
            ),
          ],
        ),
      ),
    );
}
