import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dónde terminan los encabezados que está mostrando la app, para que el aviso de una push con la app
/// abierta (24C·08) arranque debajo y nunca tape la fecha, el engranaje ni la campana (decisión del
/// 03/11, «P1 del QA»). Cada [AnclaAvisoPush] visible informa el borde de abajo de su contenido.
final anclasAvisoPushProvider = NotifierProvider<AnclasAvisoPush, Map<Object, double>>(
  AnclasAvisoPush.new,
);

class AnclasAvisoPush extends Notifier<Map<Object, double>> {
  @override
  Map<Object, double> build() => const {};

  void poner(Object clave, double abajo) {
    if (!ref.mounted) return;
    final actual = state[clave];
    if (actual != null && (actual - abajo).abs() < 0.5) return;
    state = {...state, clave: abajo};
  }

  void quitar(Object clave) {
    if (!ref.mounted || !state.containsKey(clave)) return;
    state = {...state}..remove(clave);
  }
}

/// El borde de abajo más bajo de los encabezados visibles, o `null` si ninguno informó.
double? bordeMasBajoDeLosEncabezados(Map<Object, double> anclas) =>
    anclas.values.fold<double?>(null, (a, b) => a == null ? b : math.max(a, b));

/// Marca el encabezado de una pantalla (lo que el aviso de una push no tiene que tapar). Solo cuenta
/// mientras la pantalla se ve: una ruta tapada o una pestaña oculta no informan.
///
/// Mide después de cada cuadro en que se arma, no escucha el scroll: pensado para encabezados fijos
/// arriba del contenido.
class AnclaAvisoPush extends ConsumerStatefulWidget {
  const AnclaAvisoPush({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AnclaAvisoPush> createState() => _AnclaAvisoPushState();
}

class _AnclaAvisoPushState extends ConsumerState<AnclaAvisoPush> {
  final _clave = Object();
  late final AnclasAvisoPush _anclas;

  @override
  void initState() {
    super.initState();
    _anclas = ref.read(anclasAvisoPushProvider.notifier);
  }

  @override
  void dispose() {
    // Fuera del desmontaje del árbol: avisarle a quien escucha en pleno `finalizeTree` es un error.
    final anclas = _anclas;
    final clave = _clave;
    scheduleMicrotask(() => anclas.quitar(clave));
    super.dispose();
  }

  void _informar(bool visible) {
    if (!mounted) return;
    if (!visible) {
      _anclas.quitar(_clave);
      return;
    }
    final caja = context.findRenderObject();
    if (caja is! RenderBox || !caja.attached || !caja.hasSize) return;
    _anclas.poner(_clave, caja.localToGlobal(Offset(0, caja.size.height)).dy);
  }

  @override
  Widget build(BuildContext context) {
    final visible = TickerMode.valuesOf(context).enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _informar(visible));
    return widget.child;
  }
}
