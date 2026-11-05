// Dobles del GPS único del colportor (#651): el que pide el mapa y leen todas las demás vistas.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_state.dart'
    show EstadoGpsLista;
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' show WidgetTester, find;

import 'alta_ubicacion_falsos.dart' show GpsFalso;

/// El GPS del colportor **después de que el mapa lo pidió**: apenas se arma lee del [GpsFalso] como
/// lo haría `alAbrirPestana` de la pestaña Mapa. Sirve para probar la Lista, el alta y Modificar
/// como las ve el colportor que ya pasó por el mapa (la única vista que pide el permiso).
final class UbicacionColportorYaAbierta extends UbicacionColportorNotifier {
  @override
  UbicacionColportorState build() {
    final inicial = super.build();
    scheduleMicrotask(() {
      if (ref.mounted) unawaited(alAbrirPestana());
    });
    return inicial;
  }
}

/// El GPS del colportor con el estado que el test dice, sin leer nada (ni abrir el permiso).
final class UbicacionColportorFija extends UbicacionColportorNotifier {
  UbicacionColportorFija(this.inicial);

  final UbicacionColportorState inicial;

  @override
  UbicacionColportorState build() => inicial;
}

/// El GPS del colportor ya abierto por el mapa: apenas se arma lee del `GpsFalso` de los overrides.
Override ubicacionColportorYaAbierta() =>
    ubicacionColportorProvider.overrideWith(UbicacionColportorYaAbierta.new);

/// El GPS del colportor tal como lo dejó [gps] la última vez que el mapa lo leyó (su `respuesta`
/// actual), sin volver a leerlo. Con [mapaAbierto] `false`, como si el mapa no se hubiera abierto
/// todavía (`sinPedir`).
Override ubicacionColportorDeGps(GpsFalso gps, {bool mapaAbierto = true}) {
  final estado = !mapaAbierto
      ? const UbicacionColportorState()
      : gps.respuesta.fold(
          (falla) => UbicacionColportorState(
            gps: EstadoGpsLista.sinGps,
            motivoSinGps: falla is FailureGpsNoDisponible ? falla.motivo : MotivoSinGps.sinSenal,
          ),
          (lectura) => UbicacionColportorState(gps: EstadoGpsLista.conLectura, lectura: lectura),
        );
  return ubicacionColportorProvider.overrideWith(() => UbicacionColportorFija(estado));
}

/// El colportor tocó «Mi ubicación» en el mapa: el GPS único vuelve a leer y todas las vistas lo ven.
Future<void> refrescarGpsDelColportor(WidgetTester tester) async {
  final contenedor = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  await contenedor.read(ubicacionColportorProvider.notifier).refrescar();
}

/// El Mapa activó el GPS (lo que hace «Activar GPS» una vez que se está en esa pestaña).
Future<void> activarGpsDelColportor(WidgetTester tester) async {
  final contenedor = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  await contenedor.read(ubicacionColportorProvider.notifier).activarGps();
}
