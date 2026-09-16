// Helper compartido por los tests que reciben un AppLogger inyectado.
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:logger/logger.dart';

/// Logger mudo para no ensuciar la salida de los tests.
AppLogger loggerMudo() => AppLogger(logger: Logger(level: Level.off));
