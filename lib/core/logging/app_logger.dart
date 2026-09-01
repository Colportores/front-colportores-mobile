import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Módulos de log definidos en convenciones-desarrollo.md §7.3.
enum LogModulo { auth, sync, backup, db, map, push, venta, agenda, stock, net }

/// Logger del proyecto. Formato obligatorio (convenciones §7):
///
/// ```
/// [NIVEL][MÓDULO][OPERACIÓN] mensaje — {contexto_json}
/// ```
///
/// Reglas:
/// - **Sin PII**: nunca nombre, teléfono ni notas de clientes. Solo UUIDs y metadatos.
/// - El contexto debe ser serializable a JSON (`String`, `num`, `bool`, `null`, listas y mapas).
/// - Nivel mínimo: `--dart-define=LOG_LEVEL=debug|info|warn|error`. En release, `warn`.
class AppLogger {
  AppLogger({Logger? logger, LogOutput? output})
    : _logger =
          logger ??
          Logger(filter: _NivelFilter(_nivelMinimo()), printer: _PlanoPrinter(), output: output);

  static final AppLogger instance = AppLogger();

  final Logger _logger;

  void debug(LogModulo modulo, String op, String msg, [Map<String, Object?> ctx = const {}]) =>
      _logger.d(formatear('DEBUG', modulo, op, msg, ctx));

  void info(LogModulo modulo, String op, String msg, [Map<String, Object?> ctx = const {}]) =>
      _logger.i(formatear('INFO', modulo, op, msg, ctx));

  void warn(LogModulo modulo, String op, String msg, [Map<String, Object?> ctx = const {}]) =>
      _logger.w(formatear('WARN', modulo, op, msg, ctx));

  void error(
    LogModulo modulo,
    String op,
    String msg, [
    Map<String, Object?> ctx = const {},
    Object? causa,
    StackTrace? stack,
  ]) => _logger.e(formatear('ERROR', modulo, op, msg, ctx), error: causa, stackTrace: stack);

  /// Arma la línea con el formato del proyecto. Pública para poder testearla sin salida real.
  @visibleForTesting
  static String formatear(
    String nivel,
    LogModulo modulo,
    String op,
    String msg,
    Map<String, Object?> ctx,
  ) {
    final cabecera = '[$nivel][${modulo.name.toUpperCase()}][$op] $msg';
    return ctx.isEmpty ? cabecera : '$cabecera — ${jsonEncode(ctx)}';
  }

  static Level _nivelMinimo() {
    const definido = String.fromEnvironment('LOG_LEVEL');
    final nombre = definido.isNotEmpty ? definido : (kReleaseMode ? 'warn' : 'debug');
    return switch (nombre.toLowerCase()) {
      'debug' => Level.debug,
      'info' => Level.info,
      'warn' || 'warning' => Level.warning,
      'error' => Level.error,
      _ => Level.debug,
    };
  }
}

class _NivelFilter extends LogFilter {
  _NivelFilter(this._minimo);

  final Level _minimo;

  @override
  bool shouldLog(LogEvent event) => event.level.value >= _minimo.value;
}

/// Una línea por evento, sin cajas ni colores: el prefijo ya lleva nivel y módulo.
class _PlanoPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    final lineas = <String>['${event.message}'];
    if (event.error != null) lineas.add('  causa: ${event.error}');
    if (event.stackTrace != null) lineas.add('  ${event.stackTrace}');
    return lineas;
  }
}
