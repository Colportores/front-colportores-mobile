import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/entities/estado_cuenta.dart';
import '../pages/esperando_asignacion_page.dart';

/// Lo que se le dice al colportor que toca un módulo bloqueado de la barra inferior (vista 18).
abstract final class TextosModuloBloqueado {
  /// Propuesta del diseño (18, nota al pie).
  static const pendiente = 'Disponible cuando tu coordinador te asigne a una campaña.';

  /// Literal de HU-AUTH-008 para la cuenta suspendida.
  static const suspendida = 'Tu cuenta está suspendida. Contactá al administrador.';

  /// Mientras «Reintentar» del aviso consulta la cuenta desde Configuración (#278).
  static const revisando = TextosEsperaAsignacion.revisando;

  /// El aviso para [estado]. Con [estado] `null` (nunca se pudo consultar la cuenta) la app no
  /// sabe si está pendiente: repite el aviso de la pantalla para la misma causa (decisión del
  /// orquestador, 02/10, #278): el de sin conexión si [sinConexion], el del error del servidor si
  /// no.
  static String para(EstadoCuenta? estado, {bool sinConexion = false}) => switch (estado) {
    EstadoCuenta.suspendida => suspendida,
    null =>
      sinConexion ? TextosEsperaAsignacion.sinConexionSinEstado : TextosEsperaAsignacion.sinEstado,
    _ => pendiente,
  };
}

/// Cuánto dura un aviso que ofrece «Reintentar»: hasta que la persona lo cierra o reintenta.
const _hastaQueLoCierren = Duration(days: 1);

/// Lo que devuelve `showSnackBar`: el aviso en pantalla (o en la cola).
typedef AvisoEnPantalla = ScaffoldFeatureController<SnackBar, SnackBarClosedReason>;

/// Avisa por qué el módulo no está disponible, sin acumular avisos si se toca varias veces.
///
/// Con [estado] `null` el aviso es el de la causa por la que no se conoce ([sinConexion] o error
/// del servidor), ver [TextosModuloBloqueado.para]. Si además hay [alReintentar], el aviso lleva
/// la acción «Reintentar» y no se va solo a los 4 s: queda hasta que la persona la toca o lo cierra
/// (decisión del agente de decisiones, #278; el texto del aviso manda a tocarla).
///
/// Devuelve el aviso: un `SnackBar` del `ScaffoldMessenger` de la app pasa de una pantalla a otra,
/// y quien lo muestra tiene que cerrarlo cuando deja de ser verdad o cuando se va
/// ([CierraSusAvisos]).
AvisoEnPantalla avisarModuloBloqueado(
  BuildContext context,
  EstadoCuenta? estado, {
  bool sinConexion = false,
  VoidCallback? alReintentar,
}) {
  final conAccion = estado == null && alReintentar != null;
  final mensajero = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return mensajero.showSnackBar(
    SnackBar(
      key: const Key('modulo_bloqueado_aviso'),
      content: Text(TextosModuloBloqueado.para(estado, sinConexion: sinConexion)),
      duration: conAccion ? _hastaQueLoCierren : const Duration(seconds: 4),
      showCloseIcon: conAccion ? true : null,
      action: conAccion
          ? SnackBarAction(
              key: const Key('modulo_bloqueado_reintentar'),
              label: TextosEsperaAsignacion.reintentar,
              onPressed: alReintentar,
            )
          : null,
    ),
  );
}

/// Para la pantalla que muestra avisos del módulo bloqueado: se acuerda del último y lo cierra
/// cuando deja de ser verdad (la consulta contestó, cambió la cuenta) y cuando la pantalla se va.
///
/// Sin esto el aviso con «Reintentar» (1 día) sobrevive a su pantalla: queda diciendo «sin
/// conexión» sobre un inicio ya verificado, y su acción llama al `State` descartado (#278).
mixin CierraSusAvisos<T extends StatefulWidget> on State<T> {
  // En `dispose` ya no se puede usar el `context`: el mensajero se guarda antes.
  ScaffoldMessengerState? _mensajero;
  AvisoEnPantalla? _aviso;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mensajero = ScaffoldMessenger.of(context);
  }

  /// Guarda [aviso] como el de esta pantalla; se olvida de él cuando se cierra solo.
  void recordarAviso(AvisoEnPantalla aviso) {
    _aviso = aviso;
    unawaited(
      aviso.closed.then<void>((_) {
        if (identical(_aviso, aviso)) _aviso = null;
      }),
    );
  }

  /// Cierra el aviso de esta pantalla, si sigue abierto. Se usa donde se puede tocar el mensajero
  /// (al contestar una consulta), no desde `dispose` ni `didUpdateWidget`: ver
  /// [cerrarAvisoAlTerminarElCuadro].
  ///
  /// Saca también lo que haya en la cola: el aviso puede estar esperando detrás de otro que se va
  /// y no hay otra forma de sacarlo de ahí.
  void cerrarAviso() {
    if (_aviso == null) return;
    _aviso = null;
    _mensajero?.clearSnackBars();
  }

  /// Lo mismo que [cerrarAviso], pero después del cuadro en curso: cerrarlo en `dispose` o en
  /// `didUpdateWidget` toca animaciones mientras el árbol está bloqueado (con TalkBack, el cierre
  /// es inmediato y falla).
  void cerrarAvisoAlTerminarElCuadro() {
    final aviso = _aviso;
    final mensajero = _mensajero;
    if (aviso == null || mensajero == null) return;
    scheduleMicrotask(() {
      if (!mensajero.mounted || !identical(_aviso, aviso)) return;
      _aviso = null;
      mensajero.clearSnackBars();
    });
  }

  @override
  void dispose() {
    final aviso = _aviso;
    final mensajero = _mensajero;
    if (aviso != null && mensajero != null) {
      scheduleMicrotask(() {
        if (mensajero.mounted) mensajero.clearSnackBars();
      });
    }
    _aviso = null;
    super.dispose();
  }
}
