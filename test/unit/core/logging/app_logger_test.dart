import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  group('AppLogger.formatear', () {
    test('cuando hay contexto, produce [NIVEL][MÓDULO][OPERACIÓN] mensaje — {json}', () {
      final linea = AppLogger.formatear('INFO', LogModulo.sync, 'BATCH_END', 'sync completado', {
        'uploaded': 12,
        'duration_ms': 840,
      });

      expect(linea, '[INFO][SYNC][BATCH_END] sync completado — {"uploaded":12,"duration_ms":840}');
    });

    test('cuando no hay contexto, omite el separador', () {
      expect(
        AppLogger.formatear('WARN', LogModulo.auth, 'TOKEN_REFRESH', 'refrescando', const {}),
        '[WARN][AUTH][TOKEN_REFRESH] refrescando',
      );
    });
  });

  group('AppLogger', () {
    test('cuando loguea, cada nivel sale con su prefijo', () {
      final salida = _SalidaEnMemoria();
      final log = AppLogger(output: salida);

      log.debug(LogModulo.db, 'OPEN', 'abriendo');
      log.info(LogModulo.auth, 'LOGIN_OK', 'ok', {'user_id': 'uuid'});
      log.warn(LogModulo.net, 'RETRY', 'reintento', {'attempt': 2});
      log.error(LogModulo.sync, 'DEAD_LETTER', 'descartada', const {}, StateError('x'));

      expect(salida.lineas, [
        '[DEBUG][DB][OPEN] abriendo',
        '[INFO][AUTH][LOGIN_OK] ok — {"user_id":"uuid"}',
        '[WARN][NET][RETRY] reintento — {"attempt":2}',
        '[ERROR][SYNC][DEAD_LETTER] descartada',
        '  causa: Bad state: x',
      ]);
    });
  });
}
