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
