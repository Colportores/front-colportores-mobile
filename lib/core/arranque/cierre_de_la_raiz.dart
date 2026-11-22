import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_helper.dart';
import '../logging/app_logger.dart';

/// Lo que hay que cerrar de verdad cuando se tira la raíz de la app para armar otra (HU-AUTH-006,
/// HU-SYNC-006, «Recuperar mi respaldo»).
///
/// Tirar un `ProviderScope` no cierra la base: el [DatabaseHelper] entra a la raíz por un
/// `overrideWithValue` (nadie lo crea ni lo suelta por ella) y deja abiertos el `AppDatabase`, su
/// isolate y la clave de la DB en claro. Sin esto, la raíz nueva abriría una segunda conexión al mismo
/// archivo con la clave vieja todavía viva.
///
/// Lo arma `main.dart` una vez, lo pasa a cada raíz (`cierreDeLaRaizProvider`, [adoptar]) y le da
/// [alTirar] a `ReiniciadorDeRaiz`, que lo espera DESPUÉS de sacar el árbol viejo y ANTES de armar el
/// nuevo.
final class CierreDeLaRaiz {
  CierreDeLaRaiz({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  /// El helper de la raíz que está andando; `null` si ninguna lo adoptó (o ya se cerró).
  DatabaseHelper? _vigente;

  final List<Future<void>> _pendientes = [];

  /// Anota [helper] como la base de la raíz que arranca y lo devuelve (para pasarlo al
  /// `overrideWithValue`). El anterior ya lo cerró [alTirar].
  DatabaseHelper adoptar(DatabaseHelper helper) => _vigente = helper;

  /// Anota un cierre que la raíz vieja dejó en vuelo (el del motor de sync, que espera a su ciclo en
  /// curso). [alTirar] espera a todos antes de cerrar la base. Nunca lanza: un cierre que falla se
  /// loguea y no frena a los demás.
  void registrar(Future<void> cierre) {
    late final Future<void> seguro;
    seguro = cierre
        .catchError((Object e, StackTrace st) {
          _log.warn(LogModulo.db, 'CIERRE_RAIZ_PENDIENTE', 'un cierre de la raíz vieja falló', {
            'error': e.runtimeType.toString(),
          });
        })
        .whenComplete(() => _pendientes.remove(seguro));
    _pendientes.add(seguro);
  }

  /// Espera a los cierres anotados con [registrar], también a los que se anoten mientras tanto.
  Future<void> esperarLosCierres() async {
    while (_pendientes.isNotEmpty) {
      await Future.wait(List.of(_pendientes));
    }
  }

  /// Lo que se hace entre sacar la raíz vieja y armar la nueva: esperar a lo que dejó en vuelo (el
  /// ciclo del motor) y recién entonces cerrar su base y destruir su clave.
  ///
  /// Lanza lo que lance `DatabaseHelper.cerrar` (`DbLocalException`): quien lo llama decide si sigue.
  /// El helper queda soltado igual: un segundo [alTirar] no lo vuelve a cerrar.
  Future<void> alTirar() async {
    await esperarLosCierres();
    final helper = _vigente;
    _vigente = null;
    if (helper == null) return;
    await helper.cerrar();
  }
}

/// El cierre de la raíz. Sin override (tests de una pantalla suelta) es uno propio, sin helper: lo que
/// se anota se espera y no hay base que cerrar. `main.dart` pasa el de la app.
final cierreDeLaRaizProvider = Provider<CierreDeLaRaiz>((ref) => CierreDeLaRaiz());
