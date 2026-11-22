import 'package:flutter/material.dart';

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
void avisarCampaniaPorEmpezar(ScaffoldMessengerState? mensajero, CampaniaPorEmpezar campania) =>
    mensajero
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          key: const Key('campania_por_empezar_aviso'),
          content: Text(TextosCampaniaPorEmpezar.aviso(campania)),
          duration: _duracionDelAviso,
          showCloseIcon: true,
        ),
      );
