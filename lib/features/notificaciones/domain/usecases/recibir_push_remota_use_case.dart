import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/notificaciones/push_remotas.dart';
import '../entities/notificacion.dart';
import '../entities/push_remota.dart';
import '../repositories/auditoria_push_repository.dart';
import '../repositories/datos_locales_de_push_repository.dart';
import '../services/interpretador_push_remota.dart';
import 'historial_notificaciones_use_cases.dart';

/// Los textos de los avisos que nacen de una push remota (HU-NOT-003: «la app traduce al idioma
/// local»; el payload no trae texto). Los de ticket, pedido y cuota son fijos; los de asignación y
/// agenda llevan un dato de la base local (el canvas 24 gana sobre la HU; los que el canvas no dibuja
/// siguen su voz). Cuando el dato todavía no bajó con el sync, el texto lo dice sin inventarlo.
abstract final class TextosPushRemota {
  static const pedidoAutorizado = 'Tu pedido fue autorizado';
  static const ticketValidado = 'Tu ticket fue validado';
  static const ticketRechazado = 'Tu ticket fue rechazado';
  static const cuotaPendiente = 'Tenés una cuota pendiente de cobro';
  static const asignacionSinNombre = 'Te asignaron a una campaña.';
  static const agendaMananaSinCuenta = 'Mañana tenés visitas agendadas';

  static String asignacionConZona(String zona, String campania) =>
      'Te asignaron la zona $zona en $campania.';

  static String asignacionSinZona(String campania) => 'Te asignaron a la campaña $campania.';

  static String agendaManana(int visitas) =>
      visitas == 1 ? 'Mañana tenés 1 visita agendada' : 'Mañana tenés $visitas visitas agendadas';
}

/// Qué pasó con una push recibida.
sealed class ResultadoPush {
  const ResultadoPush();
}

/// Un aviso nuevo: quedó en el historial y corresponde mostrarlo.
final class PushNueva extends ResultadoPush {
  const PushNueva(this.aviso);

  final Notificacion aviso;
}

/// El mismo evento ya se había recibido (idempotencia por `event_id`): no se guarda ni se muestra
/// otra vez. [aviso] es el aviso del evento, por si quien la recibió lo necesita (el toque sobre la
/// notificación del sistema lo abre igual).
final class PushYaRecibida extends ResultadoPush {
  const PushYaRecibida(this.aviso);

  final Notificacion aviso;
}

/// La push se descartó sin guardar nada. [porDatosPersonales]: traía un campo prohibido y quedó en
/// la auditoría local.
final class PushDescartada extends ResultadoPush {
  const PushDescartada({required this.porDatosPersonales});

  final bool porDatosPersonales;
}

/// Recibe una push remota (HU-NOT-003): la lee, la descarta si trae datos personales, y si es
/// válida la guarda en el historial (idempotente por evento) con el texto que arma la app.
///
/// **Nunca lanza.** El mensaje llega de afuera y no es confiable: lo que no se pueda usar se descarta
/// y queda en el log (sin valores).
final class RecibirPushRemotaUseCase {
  const RecibirPushRemotaUseCase(
    this._registrar,
    this._auditoria,
    this._datosLocales, {
    required this._ahora,
  });

  final RegistrarNotificacionUseCase _registrar;
  final AuditoriaPushRepository _auditoria;
  final DatosLocalesDePushRepository _datosLocales;
  final DateTime Function() _ahora;

  Future<Either<Failure, ResultadoPush>> call(MensajePush mensaje) async {
    switch (InterpretadorPushRemota.leer(mensaje.datos, ahora: _ahora())) {
      case PushConDatosPersonales(:final campos):
        await _dejarConstancia(campos);
        return const Right(PushDescartada(porDatosPersonales: true));
      case PushIgnorada(:final motivo):
        AppLogger.instance.warn(LogModulo.push, 'PUSH_IGNORADA', 'push sin uso', {
          'motivo': motivo.name,
        });
        return const Right(PushDescartada(porDatosPersonales: false));
      case PushLeida(:final push):
        final aviso = Notificacion(
          id: 'push-${push.eventoId}',
          tipo: push.tipo.tipoDeAviso,
          titulo: await _titulo(push),
          recibidaEn: _ahora(),
        );
        final guardada = await _registrar(aviso);
        return guardada.map((esNueva) => esNueva ? PushNueva(aviso) : PushYaRecibida(aviso));
    }
  }

  /// El título del aviso. Si la base local no se deja leer, queda el texto sin el dato: la push no
  /// se pierde por eso.
  Future<String> _titulo(PushRemota push) async {
    try {
      switch (push.tipo) {
        case TipoPushRemota.pedidoAutorizado:
          return TextosPushRemota.pedidoAutorizado;
        case TipoPushRemota.ticketValidado:
          return TextosPushRemota.ticketValidado;
        case TipoPushRemota.ticketRechazado:
          return TextosPushRemota.ticketRechazado;
        case TipoPushRemota.cuotaPendiente:
          return TextosPushRemota.cuotaPendiente;
        case TipoPushRemota.asignacionCampania:
          final campania = await _datosLocales.nombreDeCampania(push.entidadId!);
          if (campania == null) return TextosPushRemota.asignacionSinNombre;
          final zonaId = push.entidadOpcionalId;
          final zona = zonaId == null ? null : await _datosLocales.nombreDeZona(zonaId);
          return zona == null
              ? TextosPushRemota.asignacionSinZona(campania)
              : TextosPushRemota.asignacionConZona(zona, campania);
        case TipoPushRemota.agendaManana:
          final visitas = await _datosLocales.visitasProgramadasParaManana(_ahora());
          return visitas <= 0
              ? TextosPushRemota.agendaMananaSinCuenta
              : TextosPushRemota.agendaManana(visitas);
      }
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.db,
        'PUSH_TEXTO_FAIL',
        'no se pudo leer el dato del aviso',
        {'tipo': e.runtimeType.toString()},
      );
      return switch (push.tipo) {
        TipoPushRemota.asignacionCampania => TextosPushRemota.asignacionSinNombre,
        _ => TextosPushRemota.agendaMananaSinCuenta,
      };
    }
  }

  Future<void> _dejarConstancia(List<String> campos) async {
    AppLogger.instance.warn(LogModulo.push, 'PUSH_PII_DETECTED', 'push con datos no permitidos', {
      'campos': campos,
    });
    try {
      await _auditoria.registrarDatosPersonales(campos: campos, ahora: _ahora());
    } on Object catch (e) {
      // Sin la constancia la push se descarta igual: lo importante es que no se muestre.
      AppLogger.instance.warn(LogModulo.db, 'PUSH_AUDITORIA_FAIL', 'no se pudo dejar constancia', {
        'error': e.runtimeType.toString(),
      });
    }
  }
}
