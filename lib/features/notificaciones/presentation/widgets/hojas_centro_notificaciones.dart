import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import 'textos_centro_notificaciones.dart';

const _rojo = Color(0xFFA8312A);
const _fondoRojo = Color(0xFFFBEDEC);

/// Lo que se eligió en el menú del encabezado (24C·02).
enum AccionMenuCentro { marcarTodas, borrarTodas }

/// Cierra la hoja una sola vez: un segundo toque antes de que termine de bajar no tiene que sacar
/// también la pantalla de atrás.
void _cerrarHoja<T>(BuildContext context, [T? resultado]) {
  if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).pop(resultado);
}

ShapeBorder get _formaDeLaHoja =>
    const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24)));

/// El menú «⋯» del centro (24C·02): marcar todas como leídas o borrarlas. Devuelve lo elegido o
/// `null` si se cerró. Sin avisos sin leer, «Marcar todas como leídas» se ve apagada y dice por qué.
Future<AccionMenuCentro?> mostrarMenuCentroNotificaciones(
  BuildContext context, {
  required bool haySinLeer,
}) => showModalBottomSheet<AccionMenuCentro>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Colors.white,
  shape: _formaDeLaHoja,
  builder: (_) => _MenuCentro(haySinLeer: haySinLeer),
);

/// La confirmación de «Borrar todas» (24C·03). [borrar] hace el borrado y dice si salió bien: con
/// `false` la hoja sigue abierta con el aviso de qué hacer y «Borrar todas» vuelve a estar
/// disponible. Devuelve `true` si se borró y `null` si se canceló.
Future<bool?> mostrarHojaBorrarTodasLasNotificaciones(
  BuildContext context, {
  required int cantidad,
  required Future<bool> Function() borrar,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  showDragHandle: false,
  backgroundColor: Colors.white,
  shape: _formaDeLaHoja,
  builder: (_) => HojaBorrarTodasLasNotificaciones(cantidad: cantidad, borrar: borrar),
);

class _MarcoDeLaHoja extends StatelessWidget {
  const _MarcoDeLaHoja({required this.hijos});

  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Align(
              child: ExcludeSemantics(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colores.bordeInput,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            ...hijos,
          ],
        ),
      ),
    );
  }
}

class _MenuCentro extends StatelessWidget {
  const _MenuCentro({required this.haySinLeer});

  final bool haySinLeer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _MarcoDeLaHoja(
      hijos: [
        Semantics(
          header: true,
          child: Text(TextosCentroNotificaciones.titulo, style: theme.textTheme.headlineSmall),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            _OpcionMenu(
              clave: const Key('centro_menu_marcar_todas'),
              icono: Icons.check,
              texto: TextosCentroNotificaciones.marcarTodas,
              apagada: !haySinLeer,
              motivo: haySinLeer ? null : TextosCentroNotificaciones.nadaParaMarcar,
              onTap: () => _cerrarHoja(context, AccionMenuCentro.marcarTodas),
            ),
            _OpcionMenu(
              clave: const Key('centro_menu_borrar_todas'),
              icono: Icons.close,
              texto: TextosCentroNotificaciones.borrarTodas,
              peligro: true,
              onTap: () => _cerrarHoja(context, AccionMenuCentro.borrarTodas),
            ),
          ],
        ),
        BotonPildora(
          clave: const Key('centro_menu_cerrar'),
          texto: TextosCentroNotificaciones.cerrar,
          estilo: EstiloBotonPildora.secundario,
          onPressed: () => _cerrarHoja<AccionMenuCentro>(context),
        ),
      ],
    );
  }
}

class _OpcionMenu extends StatelessWidget {
  const _OpcionMenu({
    required this.clave,
    required this.icono,
    required this.texto,
    required this.onTap,
    this.peligro = false,
    this.apagada = false,
    this.motivo,
  });

  final Key clave;
  final IconData icono;
  final String texto;
  final bool peligro;
  final bool apagada;

  /// Por qué está apagada: va en la etiqueta y debajo del texto.
  final String? motivo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final colorTexto = peligro ? _rojo : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      enabled: !apagada,
      container: true,
      label: motivo == null ? texto : '$texto. $motivo',
      onTap: apagada ? null : onTap,
      excludeSemantics: true,
      child: Material(
        key: clave,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colores.borde),
        ),
        child: InkWell(
          onTap: apagada ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                spacing: 12,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: peligro ? _fondoRojo : const Color(0xFFE6EEF8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icono,
                      size: 18,
                      color: peligro ? _rojo : theme.colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          texto,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: apagada ? colores.gris : colorTexto,
                          ),
                        ),
                        if (motivo != null)
                          Text(
                            motivo!,
                            style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Fase { confirmar, borrando, error }

/// Hoja «¿Borrar las N notificaciones?» (24C·03). Mientras borra no se puede cancelar ni cerrar; si
/// falla, queda abierta con qué hacer y se puede volver a tocar «Borrar todas».
class HojaBorrarTodasLasNotificaciones extends StatefulWidget {
  const HojaBorrarTodasLasNotificaciones({super.key, required this.cantidad, required this.borrar});

  final int cantidad;
  final Future<bool> Function() borrar;

  @override
  State<HojaBorrarTodasLasNotificaciones> createState() => _HojaBorrarTodasLasNotificacionesState();
}

class _HojaBorrarTodasLasNotificacionesState extends State<HojaBorrarTodasLasNotificaciones> {
  _Fase _fase = _Fase.confirmar;

  Future<void> _borrar() async {
    if (_fase == _Fase.borrando) return; // Doble toque: se borra una sola vez.
    setState(() => _fase = _Fase.borrando);
    var salioBien = false;
    try {
      salioBien = await widget.borrar();
    } on Object {
      salioBien = false;
    }
    if (!mounted) return;
    if (salioBien) {
      _cerrarHoja(context, true);
    } else {
      setState(() => _fase = _Fase.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borrando = _fase == _Fase.borrando;
    return PopScope(
      canPop: !borrando,
      child: _MarcoDeLaHoja(
        hijos: [
          Semantics(
            header: true,
            child: Text(
              TextosCentroNotificaciones.borrarTitulo(widget.cantidad),
              key: const Key('centro_borrar_titulo'),
              style: theme.textTheme.headlineSmall,
            ),
          ),
          Text(
            TextosCentroNotificaciones.borrarTexto,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          if (_fase == _Fase.error)
            Semantics(
              liveRegion: true,
              container: true,
              child: Text(
                TextosCentroNotificaciones.errorAlBorrar,
                key: const Key('centro_borrar_error'),
                style: theme.textTheme.bodyMedium?.copyWith(color: _rojo, height: 1.45),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              BotonPildora(
                clave: const Key('centro_borrar_confirmar'),
                texto: TextosCentroNotificaciones.borrarTodas,
                estilo: EstiloBotonPildora.peligro,
                cargando: borrando,
                onPressed: borrando ? null : _borrar,
              ),
              BotonPildora(
                clave: const Key('centro_borrar_cancelar'),
                texto: TextosCentroNotificaciones.cancelar,
                estilo: EstiloBotonPildora.secundario,
                onPressed: borrando ? null : () => _cerrarHoja<bool>(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum EstiloBotonPildora { principal, peligro, secundario }

/// Botón de las hojas: de 52 dp para arriba, redondo y, con el texto muy grande, de esquinas más
/// chicas para que el rótulo entre. Con [cargando] muestra el giro y queda apagado sin perder el
/// color.
class BotonPildora extends StatelessWidget {
  const BotonPildora({
    super.key,
    this.clave,
    required this.texto,
    required this.estilo,
    required this.onPressed,
    this.cargando = false,
  });

  final Key? clave;
  final String texto;
  final EstiloBotonPildora estilo;
  final bool cargando;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final escala = MediaQuery.textScalerOf(context).scale(15);
    final forma = escala > 20
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
        : const StadiumBorder();
    const minimo = Size.fromHeight(52);
    final contenido = cargando
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 10,
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              Flexible(child: Text(texto, textAlign: TextAlign.center)),
            ],
          )
        : Text(texto, textAlign: TextAlign.center);
    if (estilo == EstiloBotonPildora.secundario) {
      return OutlinedButton(
        key: clave,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: minimo,
          shape: forma,
          side: BorderSide(
            color: (tema.extension<ColoresColportaje>() ?? ColoresColportaje.unica).bordeInput,
          ),
        ),
        child: contenido,
      );
    }
    final fondo = estilo == EstiloBotonPildora.peligro ? _rojo : tema.colorScheme.primary;
    return FilledButton(
      key: clave,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: minimo,
        shape: forma,
        backgroundColor: fondo,
        disabledBackgroundColor: fondo.withValues(alpha: .85),
        disabledForegroundColor: Colors.white,
      ),
      child: contenido,
    );
  }
}
