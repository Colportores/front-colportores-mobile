import 'package:flutter/material.dart';

/// Colores del aviso con «Deshacer» (canvas 39, R·01): todos por encima de 4,5:1 sobre [fondo].
abstract final class ColoresAvisoDeshacer {
  static const fondo = Color(0xFF0E1A2B);
  static const texto = Colors.white;
  static const tilde = Color(0xFF9FD3AE);
  static const accion = Color(0xFFB9D3F2);
}

/// Claves del aviso, para los tests.
abstract final class ClavesAvisoDeshacer {
  static const tilde = Key('aviso_deshacer_tilde');
  static const texto = Key('aviso_deshacer_texto');
  static const deshacer = Key('aviso_deshacer_accion');
  static const cerrar = Key('aviso_deshacer_cerrar');
}

/// El aviso con «Deshacer» de la app: una tarjeta flotante de radio 14, con un «✓» verde antes del
/// texto y la acción en azul claro sobre tinta (R·01 de la vista 39; lo usan también «Guardado» de
/// «¿Qué pasó?» y «reactivada» de la lista, vista 09). Dura [duracion] (8 s) y, con un lector de
/// pantalla, no se cierra solo (WCAG 2.2.1): quien navega con TalkBack o VoiceOver no llega a
/// «Deshacer» a tiempo.
///
/// Reemplaza al aviso en pantalla. Con el texto al 130 % o más «Deshacer» va debajo del texto, no al
/// lado: Flutter mide la acción sin la escala del texto y la deja en una columna angosta que parte
/// el mensaje.
void mostrarAvisoConDeshacer(
  ScaffoldMessengerState mensajero, {
  required MediaQueryData mediaQuery,
  required String texto,
  required String etiquetaDeshacer,
  required Duration duracion,
  required VoidCallback alDeshacer,
}) {
  final textoGrande = mediaQuery.textScaler.scale(14) / 14 > 1.3;
  final accion = SnackBarAction(
    label: etiquetaDeshacer,
    textColor: ColoresAvisoDeshacer.accion,
    onPressed: alDeshacer,
  );
  // El «✓» es decoración: el lector lee solo el mensaje.
  const tilde = ExcludeSemantics(
    child: Text(
      '✓',
      key: ClavesAvisoDeshacer.tilde,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: ColoresAvisoDeshacer.tilde,
      ),
    ),
  );
  final mensaje = Text(
    texto,
    key: ClavesAvisoDeshacer.texto,
    style: const TextStyle(fontSize: 13.5, color: ColoresAvisoDeshacer.texto),
  );
  final contenido = textoGrande
      // Con el texto grande el «✓» no le quita ancho al mensaje (sumaría un renglón y el aviso
      // taparía más de un tercio de la pantalla): va a la izquierda de «Deshacer».
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            mensaje,
            // Si no entran juntos (pantalla chica y texto enorme) «Deshacer» baja a su propio renglón.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [tilde, accion],
              ),
            ),
          ],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tilde,
            const SizedBox(width: 10),
            Expanded(child: mensaje),
          ],
        );
  mensajero
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: duracion,
        persist: mediaQuery.accessibleNavigation,
        behavior: SnackBarBehavior.floating,
        backgroundColor: ColoresAvisoDeshacer.fondo,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: contenido,
        action: textoGrande ? null : accion,
      ),
    );
}

/// El mismo aviso con «Deshacer», pero dibujado DENTRO de una hoja (#473). Un `SnackBar` sale en el
/// `Scaffold` de la pantalla de abajo y una hoja modal lo tapa: la persona no vería ni oiría nada.
///
/// Mismos colores, mismo «✓» y misma regla del texto grande que [mostrarAvisoConDeshacer]: con el texto
/// al 130 % o más «Deshacer» va debajo del mensaje. Quien lo usa maneja el plazo (8 s, o sin plazo con un
/// lector de pantalla) y pasa [alCerrar] cuando no hay plazo, para que se pueda cerrar a mano.
///
/// Sin [alDeshacer] es un aviso a secas (el resultado de deshacer). El mensaje es región viva: el lector
/// lo dice al aparecer.
class AvisoDeshacerEnHoja extends StatelessWidget {
  const AvisoDeshacerEnHoja({
    super.key,
    required this.texto,
    this.etiquetaDeshacer,
    this.alDeshacer,
    this.alCerrar,
    this.etiquetaCerrar = 'Cerrar el aviso',
  });

  final String texto;
  final String? etiquetaDeshacer;

  /// `null`: sin «Deshacer», o apagado mientras se deshace.
  final VoidCallback? alDeshacer;

  /// Muestra la «✕» que lo cierra. `null`: no se puede cerrar a mano (se cierra solo).
  final VoidCallback? alCerrar;
  final String etiquetaCerrar;

  @override
  Widget build(BuildContext context) {
    final textoGrande = MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
    final accion = etiquetaDeshacer == null
        ? null
        : TextButton(
            key: ClavesAvisoDeshacer.deshacer,
            onPressed: alDeshacer,
            style: TextButton.styleFrom(
              foregroundColor: ColoresAvisoDeshacer.accion,
              disabledForegroundColor: ColoresAvisoDeshacer.accion.withValues(alpha: 0.6),
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: Text(etiquetaDeshacer!),
          );
    const tilde = ExcludeSemantics(
      child: Text(
        '✓',
        key: ClavesAvisoDeshacer.tilde,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 1.3,
          color: ColoresAvisoDeshacer.tilde,
        ),
      ),
    );
    final mensaje = Semantics(
      liveRegion: true,
      child: Text(
        texto,
        key: ClavesAvisoDeshacer.texto,
        style: const TextStyle(fontSize: 13.5, color: ColoresAvisoDeshacer.texto),
      ),
    );
    final cerrar = alCerrar == null
        ? null
        : IconButton(
            key: ClavesAvisoDeshacer.cerrar,
            tooltip: etiquetaCerrar,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: alCerrar,
            icon: const ExcludeSemantics(
              child: Text('✕', style: TextStyle(fontSize: 16, color: ColoresAvisoDeshacer.texto)),
            ),
          );
    final contenido = textoGrande
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              mensaje,
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [tilde, ?accion, ?cerrar],
                ),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              tilde,
              const SizedBox(width: 10),
              Expanded(child: mensaje),
              ?accion,
              ?cerrar,
            ],
          );
    return Material(
      color: ColoresAvisoDeshacer.fondo,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, textoGrande ? 12 : 4, cerrar == null ? 8 : 4, 4),
        child: contenido,
      ),
    );
  }
}
