import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../../core/logging/app_logger.dart';
import '../domain/entities/destino_notificacion.dart';
import '../domain/entities/notificacion.dart';
import '../domain/usecases/historial_notificaciones_use_cases.dart';
import 'pages/centro_notificaciones_page.dart';
import 'providers/historial_notificaciones_providers.dart';
import 'providers/push_remotas_providers.dart';
import 'widgets/textos_centro_notificaciones.dart';

/// Lo que une las push remotas con la navegación de la app (HU-NOT-003, R-NO05: «tap → deep link a
/// la pantalla correspondiente»). `main.dart` suma [enganches] a los overrides de la app; un test de
/// la app entera, también.
abstract final class EnganchesPushRemotas {
  static List<Override> enganches(GlobalKey<NavigatorState> navegador) => [
    abridorAvisoPushProvider.overrideWith(
      (ref) => (aviso) async {
        final contexto = navegador.currentContext;
        if (contexto == null) return;
        await abrirAvisoDePush(ref, contexto, aviso);
      },
    ),
  ];
}

/// Abre el centro de notificaciones si no es la pantalla que ya se está viendo.
void abrirCentroDeNotificaciones(BuildContext context) {
  final navegador = Navigator.of(context);
  var yaEsta = false;
  navegador.popUntil((ruta) {
    yaEsta = ruta.settings.name == CentroNotificacionesPage.nombreDeRuta;
    return true;
  });
  if (!yaEsta) unawaited(navegador.push(CentroNotificacionesPage.ruta()));
}

/// Tocar el aviso de una push (el aviso sutil de arriba o la notificación del sistema): lo marca como
/// leído, comprueba que su destino exista y lo abre. Lo mismo que hace tocar un aviso en el centro de
/// notificaciones, con los mismos textos.
///
/// Sin destino (el pedido, el ticket, la asignación, la cuota y la agenda de mañana no tienen
/// pantalla de detalle todavía) abre el centro de notificaciones con el aviso ya leído. Nunca
/// lanza: lo que falla se explica con un aviso de qué hacer.
Future<void> abrirAvisoDePush(Ref ref, BuildContext context, Notificacion aviso) async {
  void avisar(String texto) {
    if (!context.mounted) return;
    final mensajes = ScaffoldMessenger.maybeOf(context);
    mensajes
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  try {
    // Si no se pudo marcar, igual se abre: el aviso sigue «Nueva» en el centro.
    final marcada = await ref.read(marcarNotificacionLeidaUseCaseProvider)(aviso.id);
    marcada.fold(
      (_) => AppLogger.instance.warn(
        LogModulo.db,
        'NOTIF_LEER_FAIL',
        'no se pudo marcar el aviso como leído',
        {'id': aviso.id},
      ),
      (_) {},
    );
    final resuelto = await ref.read(resolverDestinoNotificacionUseCaseProvider)(aviso);
    if (!context.mounted) return;
    await resuelto.fold<Future<void>>(
      (_) async => avisar(TextosCentroNotificaciones.errorAlAbrir),
      (r) async {
        switch (r) {
          case SinDestino():
            // Sin pantalla de detalle no hay a dónde ir: se abre el centro con el aviso ya leído
            // (nunca un callejón sin salida), salvo que ya esté arriba.
            abrirCentroDeNotificaciones(context);
          case DestinoYaNoExiste(:final destino):
            avisar(switch (destino) {
              DestinoAgenda() => TextosCentroNotificaciones.agendaYaNoEsta,
            });
          case DestinoDisponible(:final destino):
            await ref.read(abridorDestinoNotificacionProvider)(context, destino);
        }
      },
    );
  } on Object catch (e) {
    AppLogger.instance.warn(
      LogModulo.push,
      'PUSH_ABRIR_FAIL',
      'no se pudo abrir el destino del aviso',
      {'tipo': e.runtimeType.toString()},
    );
    avisar(TextosCentroNotificaciones.errorAlAbrir);
  }
}
