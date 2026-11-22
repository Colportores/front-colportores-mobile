import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../logging/app_logger.dart';

/// Reinicia la raíz de la app por dentro: tira el `ProviderScope` entero y arma uno nuevo, como el
/// primer arranque (sin motor de sync, ni lecturas, ni estado de ninguna pantalla andando).
///
/// Lo arma `main.dart` con [ReiniciadorDeRaiz]. Por defecto no hace nada (tests de una pantalla suelta,
/// donde no hay raíz que reiniciar).
///
/// Lo usa «Recuperar mi respaldo» de Configuración (HU-SYNC-006, decisión de Cristian, 04/11,
/// «Motor vivo»): la recuperación reemplaza la base y no puede haber nada escuchándola, así que la app
/// vuelve a empezar y abre directo en el asistente (vista 34).
final reiniciarRaizProvider = Provider<void Function()>((ref) => () {});

/// La raíz de la app, que sabe reiniciarse: arma el `ProviderScope` con los `overrides` que da
/// [overrides] y, al reiniciar, lo tira entero y arma otro con `overrides` nuevos (cada arranque tiene su
/// `DatabaseHelper`, por ejemplo). Ya le pone a `reiniciarRaizProvider` el reinicio de esta raíz.
///
/// El reinicio tiene tres tiempos: primero se saca el árbol viejo (se cierra su `ProviderScope`), luego
/// se espera [alTirar] (cerrar lo que el `ProviderScope` no cierra: la base) y recién después se arma
/// el nuevo, así dos raíces nunca conviven con la misma base. Pedirlo dos veces seguidas reinicia una
/// sola vez.
class ReiniciadorDeRaiz extends StatefulWidget {
  const ReiniciadorDeRaiz({required this.overrides, required this.child, this.alTirar, super.key});

  /// Los `overrides` de cada arranque de la raíz.
  final List<Override> Function() overrides;

  /// Se espera después de sacar el árbol viejo y antes de armar el nuevo: acá se cierra la base de la
  /// raíz que se tiró (un `ProviderScope` no cierra lo que entra por `overrideWithValue`). Si lanza se
  /// registra y la raíz nueva arranca igual: la app no se queda en blanco por un cierre que falló.
  final Future<void> Function()? alTirar;

  /// Lo que cuelga del `ProviderScope`.
  final Widget child;

  @override
  State<ReiniciadorDeRaiz> createState() => _ReiniciadorDeRaizState();
}

class _ReiniciadorDeRaizState extends State<ReiniciadorDeRaiz> {
  late Widget _raiz = _armar();
  var _generacion = 0;
  var _reiniciando = false;

  Widget _armar() {
    final propios = <Override>[reiniciarRaizProvider.overrideWithValue(_reiniciar)];
    return ProviderScope(
      key: ValueKey(_generacion),
      overrides: [...widget.overrides(), ...propios],
      child: widget.child,
    );
  }

  void _reiniciar() {
    if (!mounted || _reiniciando) return;
    setState(() => _reiniciando = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_rearmar()));
  }

  Future<void> _rearmar() async {
    if (!mounted) return;
    final alTirar = widget.alTirar;
    if (alTirar != null) {
      try {
        await alTirar();
      } on Object catch (e, st) {
        AppLogger.instance.error(
          LogModulo.db,
          'REINICIO_RAIZ',
          'no se pudo cerrar la base de la raíz que se tiró; la nueva arranca igual',
          const {},
          e,
          st,
        );
      }
      if (!mounted) return;
    }
    setState(() {
      _generacion++;
      _raiz = _armar();
      _reiniciando = false;
    });
  }

  @override
  Widget build(BuildContext context) => _reiniciando ? const SizedBox.shrink() : _raiz;
}
