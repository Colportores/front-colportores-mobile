import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/notificaciones/push_remotas.dart';
import '../entities/notificacion.dart';
import '../entities/push_remota.dart';
import '../repositories/auditoria_push_repository.dart';
import '../services/interpretador_push_remota.dart';
import 'historial_notificaciones_use_cases.dart';

/// Los textos de los avisos que nacen de una push remota (HU-NOT-003: «la app traduce al idioma
/// local»; el payload no trae texto).
abstract final class TextosPushRemota {
  /// El título del aviso de [tipo].
  static String titulo(TipoPushRemota tipo) => switch (tipo) {
    TipoPushRemota.pedidoAutorizado => 'Tu pedido fue autorizado',
  };
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
  const RecibirPushRemotaUseCase(this._registrar, this._auditoria, {required this._ahora});

  final RegistrarNotificacionUseCase _registrar;
  final AuditoriaPushRepository _auditoria;
  final DateTime Function() _ahora;

  Future<Either<Failure, ResultadoPush>> call(MensajePush mensaje) async {
    switch (InterpretadorPushRemota.leer(mensaje.datos)) {
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
          titulo: TextosPushRemota.titulo(push.tipo),
          recibidaEn: _ahora(),
        );
        final guardada = await _registrar(aviso);
        return guardada.map((esNueva) => esNueva ? PushNueva(aviso) : PushYaRecibida(aviso));
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
