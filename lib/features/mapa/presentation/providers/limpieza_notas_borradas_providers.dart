import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/datasources/notas_borradas_local_data_source_drift.dart';
import '../../data/repositories/limpieza_notas_borradas_repository_impl.dart';
import '../../domain/repositories/limpieza_notas_borradas_repository.dart';
import '../../domain/usecases/limpiar_notas_borradas_use_case.dart';

// Cableado de la limpieza de las notas de persona borradas hace más de 90 días (HU-UBI-012): corre al
// abrir la app y al volver a ella. Todo es local.

/// Sin DB abierta no hay notas que limpiar: pedirlo lanza, y quien lo pide lo deja en el log.
final limpiezaNotasBorradasRepositoryProvider = Provider<LimpiezaNotasBorradasRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return LimpiezaNotasBorradasRepositoryImpl(NotasBorradasLocalDataSourceDrift(db));
});

/// Con el reloj de la sesión, que no retrocede: atrasar la hora del teléfono no estira la vida de una
/// nota borrada. En el equipo `main.dart` lo sobreescribe con el que recuerda el instante más alto
/// visto; por defecto (tests), en memoria.
final limpiarNotasBorradasUseCaseProvider = Provider<LimpiarNotasBorradasUseCase>(
  (ref) => LimpiarNotasBorradasUseCase(
    ref.watch(limpiezaNotasBorradasRepositoryProvider),
    ahora: () => ref.read(relojSesionProvider).ahora(),
  ),
);

/// Pide limpiezas de a una: si llega un pedido mientras otra corre, se hace otra al terminar y nunca
/// dos a la vez.
final class LimpiadorSerie {
  LimpiadorSerie(this._limpiar);

  final Future<void> Function() _limpiar;
  bool _corriendo = false;
  bool _otraVez = false;

  Future<void> pedir() async {
    if (_corriendo) {
      _otraVez = true;
      return;
    }
    _corriendo = true;
    try {
      do {
        _otraVez = false;
        await _limpiar();
      } while (_otraVez);
    } finally {
      _corriendo = false;
    }
  }
}

/// Quien pide las limpiezas, o `null` sin DB abierta. Nunca lanza: si la limpieza falla (o el cableado
/// lo hace) la app sigue, las notas vencidas no se muestran igual (`RetencionNotasBorradas.vencida`) y
/// se reintenta la próxima vez que se abre la app.
final limpiadorNotasBorradasProvider = Provider<LimpiadorSerie?>((ref) {
  if (ref.watch(dbLocalProvider) == null) return null;
  return LimpiadorSerie(() async {
    if (!ref.mounted) return;
    try {
      final resultado = await ref.read(limpiarNotasBorradasUseCaseProvider)(const NoParams());
      resultado.fold(
        (falla) => AppLogger.instance.warn(
          LogModulo.db,
          'NOTAS_BORRADAS_LIMPIEZA',
          'no se pudo limpiar las notas borradas',
          {'codigo': falla.codigo},
        ),
        (_) {},
      );
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.db,
        'NOTAS_BORRADAS_LIMPIEZA',
        'no se pudo limpiar las notas borradas',
        {'error': e.runtimeType.toString()},
      );
    }
  });
});

/// Limpia las notas borradas vencidas al abrir la app y cada vez que se vuelve a ella. Lo mira la
/// pantalla principal (`_Principal`, en `app.dart`), con la DB ya abierta.
final limpiezaNotasBorradasProvider = Provider.autoDispose<void>((ref) {
  final limpiador = ref.watch(limpiadorNotasBorradasProvider);
  if (limpiador == null) return;
  final ciclo = AppLifecycleListener(onResume: () => unawaited(limpiador.pedir()));
  ref.onDispose(ciclo.dispose);
  unawaited(limpiador.pedir());
});
