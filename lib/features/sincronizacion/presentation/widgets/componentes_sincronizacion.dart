import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/presentation/widgets/borde_discontinuo.dart';
import '../../../auth/presentation/widgets/icono_sin_conexion.dart';

/// El ámbar de las operaciones que esperan (canvas `#A98330`), oscurecido para que el número blanco
/// llegue a 4,5:1 (AA); el mismo que la marca de pendientes de «¿Cerrar sesión?».
const colorPendientes = Color(0xFF8A6A22);

/// El verde de lo que está al día.
const _verdeAlDia = Color(0xFF1F6E3A);
const _fondoAlDia = Color(0xFFDDE8D3);

/// Cómo se ve el cuadrado de la izquierda de una tarjeta.
enum GlifoTarjeta { alDia, pendientes, error, actualizando }

/// Una tarjeta de la pantalla (los `card` del canvas): un cuadrado con un símbolo, un título, un
/// detalle y, si se la puede abrir, una flecha. [alTocar] `null` la deja como información.
class TarjetaSincronizacion extends StatelessWidget {
  const TarjetaSincronizacion({
    super.key,
    required this.glifo,
    required this.titulo,
    this.detalle,
    this.cantidad,
    this.alTocar,
    this.tituloKey,
    this.detalleKey,
  });

  final GlifoTarjeta glifo;
  final String titulo;
  final String? detalle;

  /// El número que va dentro del cuadrado de [GlifoTarjeta.pendientes].
  final int? cantidad;
  final VoidCallback? alTocar;
  final Key? tituloKey;
  final Key? detalleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final cuerpo = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        spacing: 12,
        children: [
          _Cuadrado(glifo: glifo, cantidad: cantidad),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  titulo,
                  key: tituloKey,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (detalle != null)
                  Text(
                    detalle!,
                    key: detalleKey,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
          if (alTocar != null)
            ExcludeSemantics(child: Icon(Icons.chevron_right, color: colores.gris)),
        ],
      ),
    );
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: glifo == GlifoTarjeta.error ? theme.colorScheme.error : colores.borde,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: alTocar == null
            ? Semantics(container: true, child: cuerpo)
            : Semantics(
                button: true,
                child: InkWell(onTap: alTocar, child: cuerpo),
              ),
      ),
    );
  }
}

class _Cuadrado extends StatelessWidget {
  const _Cuadrado({required this.glifo, required this.cantidad});

  final GlifoTarjeta glifo;
  final int? cantidad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (fondo, frente) = switch (glifo) {
      GlifoTarjeta.alDia => (_fondoAlDia, _verdeAlDia),
      GlifoTarjeta.pendientes => (colorPendientes, Colors.white),
      GlifoTarjeta.error => (theme.colorScheme.error, theme.colorScheme.onError),
      GlifoTarjeta.actualizando => (theme.colorScheme.surface, theme.colorScheme.primary),
    };
    final Widget contenido = switch (glifo) {
      GlifoTarjeta.alDia => Icon(Icons.check, size: 20, color: frente),
      GlifoTarjeta.pendientes => Text(
        '${cantidad ?? ''}',
        style: TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, color: frente),
      ),
      GlifoTarjeta.error => Text(
        '!',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: frente),
      ),
      GlifoTarjeta.actualizando => SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(
          key: const Key('sincronizacion_actualizando_giro'),
          strokeWidth: 2.5,
          color: frente,
          semanticsLabel: 'Actualizando',
        ),
      ),
    };
    return ExcludeSemantics(
      excluding: glifo != GlifoTarjeta.actualizando,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(10)),
        child: contenido,
      ),
    );
  }
}

/// Las cifras de la pantalla (el `kv` del canvas): un renglón por dato, con el rótulo a la
/// izquierda y el valor a la derecha. A texto grande el valor baja debajo del rótulo en vez de
/// apretarse.
class FilasDeCifras extends StatelessWidget {
  const FilasDeCifras({super.key, required this.filas});

  final List<FilaDeCifras> filas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: colores.borde),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < filas.length; i++) ...[
              if (i > 0) Divider(height: 1, color: colores.borde),
              _Fila(fila: filas[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Un dato de [FilasDeCifras].
class FilaDeCifras {
  const FilaDeCifras({
    required this.rotulo,
    required this.valor,
    required this.clave,
    this.numero = false,
    this.destacada = false,
    this.alerta = false,
  });

  final String rotulo;
  final String valor;
  final Key clave;

  /// El valor es una cifra (se escribe en la tipografía de números).
  final bool numero;

  /// El valor llama la atención (hay algo que esperar), en ámbar.
  final bool destacada;

  /// El valor es un problema (no hay respaldo), en rojo.
  final bool alerta;
}

class _Fila extends StatelessWidget {
  const _Fila({required this.fila});

  final FilaDeCifras fila;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final escala = MediaQuery.textScalerOf(context).scale(14);
    final color = fila.alerta
        ? theme.colorScheme.error
        : fila.destacada
        ? colorPendientes
        : theme.colorScheme.onSurface;
    final rotulo = Text(
      fila.rotulo,
      style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
    );
    final valor = Text(
      fila.valor,
      key: fila.clave,
      textAlign: escala > 22 ? TextAlign.start : TextAlign.end,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: color,
        fontWeight: fila.destacada || fila.alerta ? FontWeight.w600 : FontWeight.w500,
        fontFamily: fila.numero ? 'JetBrainsMono' : null,
      ),
    );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: escala > 22
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [rotulo, valor],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                spacing: 12,
                children: [
                  Expanded(child: rotulo),
                  Flexible(flex: 2, child: valor),
                ],
              ),
      ),
    );
  }
}

/// El interruptor «Modo ahorro de datos» (HU-SYNC-008).
class InterruptorModoAhorro extends StatelessWidget {
  const InterruptorModoAhorro({
    super.key,
    required this.titulo,
    required this.detalle,
    required this.activo,
    required this.alCambiar,
  });

  final String titulo;
  final String detalle;
  final bool activo;

  /// `null` mientras se guarda el cambio anterior: el interruptor no admite otro toque.
  final ValueChanged<bool>? alCambiar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: colores.borde),
    );
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: forma,
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        key: const Key('sincronizacion_modo_ahorro'),
        value: activo,
        onChanged: alCambiar,
        shape: forma,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(
          titulo,
          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          detalle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

enum TonoAvisoSincronizacion { info, advertencia, error, sinConexion }

/// Un aviso de la pantalla (los `banner` del canvas): un ícono, el texto y, si hay, una acción. El
/// lector de pantalla lo anuncia al aparecer. El de «sin conexión» es neutro: gris y de trazos, como
/// en el resto de la app (no es un error de la cuenta).
class AvisoSincronizacion extends StatelessWidget {
  const AvisoSincronizacion({
    super.key,
    required this.tono,
    required this.texto,
    this.textoAccion,
    this.alAccionar,
    this.textoKey,
    this.accionKey,
  });

  final TonoAvisoSincronizacion tono;
  final String texto;
  final String? textoAccion;
  final VoidCallback? alAccionar;
  final Key? textoKey;
  final Key? accionKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final esquema = theme.colorScheme;
    final (borde, fondo) = switch (tono) {
      TonoAvisoSincronizacion.info => (esquema.onSurfaceVariant, esquema.surfaceContainerHighest),
      TonoAvisoSincronizacion.advertencia => (colorPendientes, const Color(0xFFFFFDF6)),
      TonoAvisoSincronizacion.error => (esquema.error, esquema.surfaceContainerHighest),
      TonoAvisoSincronizacion.sinConexion => (colores.gris, esquema.surfaceContainerHighest),
    };
    final Widget icono = tono == TonoAvisoSincronizacion.sinConexion
        ? const IconoSinConexion()
        : ExcludeSemantics(
            child: Icon(
              tono == TonoAvisoSincronizacion.info ? Icons.info : Icons.error,
              size: 22,
              color: borde,
            ),
          );
    final escala = MediaQuery.textScalerOf(context).scale(14);
    Widget caja = DecoratedBox(
      decoration: BoxDecoration(
        color: fondo,
        border: tono == TonoAvisoSincronizacion.sinConexion
            ? null
            : Border.all(color: borde, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            icono,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    texto,
                    key: textoKey,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: esquema.onSurface,
                      height: 1.45,
                    ),
                  ),
                  if (textoAccion != null)
                    TextButton(
                      key: accionKey,
                      onPressed: alAccionar,
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
          ],
        ),
      ),
    );
    if (tono == TonoAvisoSincronizacion.sinConexion) {
      caja = BordeDiscontinuo(color: borde, radio: 14, child: caja);
    }
    return Semantics(liveRegion: true, container: true, child: caja);
  }
}

/// El botón grande del pie: «Actualizar ahora» y sus variantes. [alTocar] `null` lo deja apagado; con
/// [trabajando] muestra el giro y el texto de espera.
class BotonActualizar extends StatelessWidget {
  const BotonActualizar({
    super.key,
    required this.texto,
    required this.alTocar,
    this.trabajando = false,
  });

  final String texto;
  final VoidCallback? alTocar;
  final bool trabajando;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final color = esquema.onPrimary;
    return FilledButton(
      key: const Key('sincronizacion_actualizar'),
      onPressed: trabajando ? null : alTocar,
      style: trabajando
          ? FilledButton.styleFrom(
              disabledBackgroundColor: esquema.primary.withValues(alpha: .85),
              disabledForegroundColor: color,
              minimumSize: const Size.fromHeight(56),
            )
          : FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      child: trabajando
          ? Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    key: const Key('sincronizacion_boton_giro'),
                    strokeWidth: 2,
                    color: color,
                    backgroundColor: color.withValues(alpha: .35),
                  ),
                ),
                Flexible(child: Text(texto)),
              ],
            )
          : Text(texto, textAlign: TextAlign.center),
    );
  }
}
