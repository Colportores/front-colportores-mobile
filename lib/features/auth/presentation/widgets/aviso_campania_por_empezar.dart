import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../domain/services/situacion_de_campania.dart';

/// Lo que se le dice al colportor cuya cuenta ya es activa pero cuya campaña todavía no empezó
/// (HU-AUTH-008, decisión de Cristian del 23/10, «Cuenta antes»).
abstract final class TextosCampaniaPorEmpezar {
  /// El texto de la decisión: cuándo empieza y qué se puede hacer mientras tanto.
  static String aviso(CampaniaPorEmpezar campania) =>
      'Tu campaña ${campania.nombre} empieza el ${campania.diaYMes}. '
      'Hasta entonces podés bajar el mapa y las casas; '
      'la jornada y las ventas se habilitan ese día.';
}

/// Cuánto dura el aviso al tocar una acción frenada: es largo (nombre de la campaña, fecha y qué sí
/// se puede), y con el texto al 200 % hace falta tiempo para leerlo.
const _duracionDelAviso = Duration(seconds: 8);

/// Avisa por qué la jornada o la venta no se habilitan todavía, sin acumular avisos si se toca varias
/// veces. Va por el [mensajero] (el del `ScaffoldMessenger`) y no por un `BuildContext` para poder
/// llamarlo desde un flujo que ya cambió de pantalla.
void avisarCampaniaPorEmpezar(ScaffoldMessengerState? mensajero, CampaniaPorEmpezar campania) {
  if (mensajero == null) return;
  // Con lector de pantalla o con el foco del teclado el aviso no se cierra solo (decisión del agente
  // de decisiones, P1 de #62, accesibilidad): se queda hasta que la persona lo cierra con la ✕.
  final sinPrisa =
      (MediaQuery.maybeAccessibleNavigationOf(mensajero.context) ?? false) ||
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
  mensajero
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        key: const Key('campania_por_empezar_aviso'),
        content: Text(TextosCampaniaPorEmpezar.aviso(campania)),
        duration: _duracionDelAviso,
        persist: sinPrisa,
        // Fijo y no flotante: el flotante no entra arriba de la barra de pestañas de «Inicio» (QA
        // ronda 1 de #62); el fijo se apoya sobre ella.
        behavior: SnackBarBehavior.fixed,
        showCloseIcon: true,
      ),
    );
}

/// Si el aviso con el texto de [campania] entra en el espacio de [pantalla] (la región de arriba de la
/// barra de «Inicio», donde se apoya) con el tamaño de letra de la persona. Con letra al 200 % en
/// 360×640 son 8 renglones y no entra: quien tiene el aviso fijo a la vista (la pantalla «Hoy») lleva
/// la vista hasta él en vez de repetirlo abajo ([llevarAlAvisoFijo]).
bool avisoEntraEnPantalla(BuildContext pantalla, CampaniaPorEmpezar campania) {
  final medidas = MediaQuery.of(pantalla);
  final disponible = (pantalla.size ?? medidas.size).height;
  final pintor = TextPainter(
    text: TextSpan(
      text: TextosCampaniaPorEmpezar.aviso(campania),
      style: Theme.of(pantalla).textTheme.bodyMedium,
    ),
    textDirection: Directionality.of(pantalla),
    textScaler: medidas.textScaler,
  )..layout(maxWidth: medidas.size.width - 100);
  final alto = pintor.height + 28;
  pintor.dispose();
  return alto <= disponible;
}

/// Lleva la vista hasta el aviso fijo de [contexto] (sin animación: respeta quitar movimiento) y lo
/// anuncia a quien usa lector de pantalla.
void llevarAlAvisoFijo(BuildContext avisoFijo, BuildContext pantalla, CampaniaPorEmpezar campania) {
  unawaited(Scrollable.ensureVisible(avisoFijo, duration: Duration.zero));
  unawaited(
    SemanticsService.sendAnnouncement(
      View.of(pantalla),
      TextosCampaniaPorEmpezar.aviso(campania),
      Directionality.of(pantalla),
    ),
  );
}
