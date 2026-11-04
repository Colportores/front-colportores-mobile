import '../entities/push_remota.dart';

/// Qué salió de leer el `data` de una push remota.
sealed class LecturaDePush {
  const LecturaDePush();
}

/// Un payload válido de un tipo conocido.
final class PushLeida extends LecturaDePush {
  const PushLeida(this.push);

  final PushRemota push;
}

/// El payload trae algo que no es un tipo de evento ni un UUID (R-NO02, «Edge: payload con PII»).
/// Se descarta entero. [campos] son los NOMBRES de los campos sospechosos (nunca sus valores),
/// listos para el `audit_log` local.
final class PushConDatosPersonales extends LecturaDePush {
  const PushConDatosPersonales(this.campos);

  final List<String> campos;
}

/// Un payload sin problema de privacidad que la app no puede usar.
enum MotivoPushIgnorada {
  /// No trae `type`.
  sinTipo,

  /// El `type` es de un evento que esta versión de la app no conoce (el servidor va adelante).
  tipoDesconocido,

  /// Falta el UUID de la fila a la que apunta.
  sinEntidad,
}

final class PushIgnorada extends LecturaDePush {
  const PushIgnorada(this.motivo);

  final MotivoPushIgnorada motivo;
}

/// Lee el `data` de una push remota (HU-NOT-003, R-NO02). Dart puro.
///
/// El payload permitido es **cerrado**: `type` (un código en minúsculas), `event_id` y campos
/// `<algo>_id`, todos con un UUID como valor. Cualquier otro campo, o un campo `*_id` cuyo valor no
/// sea un UUID, cuenta como dato personal: se descarta el mensaje completo antes de mirar su tipo. El
/// texto del aviso no viaja nunca; lo arma la app con lo que tiene en el teléfono.
abstract final class InterpretadorPushRemota {
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _codigo = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final _campoDeId = RegExp(r'^[a-z][a-z0-9_]{0,40}_id$');
  static final _nombreSeguro = RegExp(r'^[A-Za-z0-9_.-]{1,40}$');

  /// Cuántos nombres de campo se guardan en la auditoría como máximo.
  static const maximoDeCamposAuditados = 10;

  static const _claveTipo = 'type';
  static const _claveEvento = 'event_id';

  /// [ahora] solo se usa para reconocer el evento de un tipo sin id y sin `event_id`.
  static LecturaDePush leer(Map<String, Object?> datos, {DateTime? ahora}) {
    final sospechosos = <String>{};
    for (final MapEntry(:key, :value) in datos.entries) {
      final valido = switch (key) {
        _claveTipo => value is String && _codigo.hasMatch(value),
        _claveEvento => _esUuid(value),
        _ when _campoDeId.hasMatch(key) => _esUuid(value),
        _ => false,
      };
      if (!valido) sospechosos.add(_nombreParaAuditar(key));
    }
    if (sospechosos.isNotEmpty) {
      final ordenados = sospechosos.toList()..sort();
      return PushConDatosPersonales(ordenados.take(maximoDeCamposAuditados).toList());
    }

    final codigo = datos[_claveTipo];
    if (codigo is! String) return const PushIgnorada(MotivoPushIgnorada.sinTipo);
    final tipo = TipoPushRemota.desdeCodigo(codigo);
    if (tipo == null) return const PushIgnorada(MotivoPushIgnorada.tipoDesconocido);

    String? entidadId;
    final claveId = tipo.claveId;
    if (claveId != null) {
      final entidad = datos[claveId];
      if (entidad is! String) return const PushIgnorada(MotivoPushIgnorada.sinEntidad);
      entidadId = entidad.toLowerCase();
    }
    final claveOpcional = tipo.claveIdOpcional;
    final opcional = claveOpcional == null ? null : datos[claveOpcional];
    final entidadOpcionalId = opcional is String ? opcional.toLowerCase() : null;

    // El ejemplo de la HU no trae `event_id`: sin él, el mismo evento se reconoce por su tipo y las
    // filas a las que apunta; un tipo sin id (`agenda_manana`), por el día en que llegó.
    final evento = datos[_claveEvento];
    final eventoId = evento is String
        ? evento.toLowerCase()
        : [
            tipo.codigo,
            ?entidadId,
            ?entidadOpcionalId,
            if (entidadId == null) _dia(ahora ?? DateTime.now()),
          ].join(':');
    return PushLeida(
      PushRemota(
        tipo: tipo,
        eventoId: eventoId,
        entidadId: entidadId,
        entidadOpcionalId: entidadOpcionalId,
      ),
    );
  }

  static String _dia(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static bool _esUuid(Object? valor) => valor is String && _uuid.hasMatch(valor);

  /// El nombre de un campo sospechoso, para la auditoría. Si el nombre mismo no parece un nombre de
  /// campo (podría ser texto de una persona), se guarda `?`.
  static String _nombreParaAuditar(String clave) => _nombreSeguro.hasMatch(clave) ? clave : '?';
}
