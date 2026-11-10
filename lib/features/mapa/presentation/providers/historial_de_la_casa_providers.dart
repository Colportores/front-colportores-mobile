import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../data/datasources/historial_de_la_casa_local_data_source_drift.dart';
import '../../domain/entities/evento_de_la_casa.dart';
import '../../domain/services/historial_de_la_casa.dart';

// Cableado de la pestaña Historial de la hoja de la casa (vista 39, C·03 y C·04). Todo sale de la DB
// local: las visitas, las ventas y los cobros viven en el teléfono, así que sin conexión funciona igual.

/// Riverpod 3 reintenta 10 veces lo que falla: la pestaña muestra el error enseguida y el
/// «Reintentar» es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

/// De dónde sale el historial de la casa: la DB local. Sin DB abierta no hay dónde leer: lanza, y la
/// pestaña lo muestra como «No pudimos leer el historial de esta casa en tu teléfono.».
final historialDeLaCasaFuenteProvider = Provider<HistorialDeLaCasa>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return HistorialDeLaCasaLocalDataSourceDrift(db);
});

/// Lo que pasó en el espacio [espacioId], el más nuevo primero, al día cuando se registra una visita,
/// una venta o un cobro. Una falla de lectura es el error del provider.
final historialDeLaCasaProvider = StreamProvider.autoDispose.family<List<EventoDeLaCasa>, String>(
  (ref, espacioId) => ref.watch(historialDeLaCasaFuenteProvider).observar(espacioId),
  retry: _sinReintentos,
);

/// A dónde lleva tocar un cobro del Historial de la casa (el detalle del cobro y «Anular cobro», vista
/// 30 B, HU-COB-006): recibe el `id` del cobro y devuelve cuando se cerró. Igual que en la ficha de la
/// persona (decisión de Cristian, 30/10, casilla de #168 en #446). **Sin destino**: mientras sea `null`
/// la fila del cobro no se puede tocar y no lleva «›» (HU-UBI-003: un botón sin destino no se
/// muestra). Lo engancha `main.dart` cuando `DetalleDelCobroPage` esté en `develop` (PR #585).
final verCobroDesdeLaCasaProvider = Provider<FutureOr<Object?> Function(String cobranzaId)?>(
  (ref) => null,
);

/// A dónde lleva «Ver la venta» del detalle de una venta (vista 39, C·04): recibe el `id` de la venta
/// y devuelve cuando se cerró. **Sin destino**: mientras sea `null` el detalle no ofrece el botón. Hoy
/// no existe una pantalla que muestre una venta ya registrada (el canvas no la dibuja: pendiente en
/// `front-colportores-mobile-446-impl-261110-1000.md`).
final verVentaDesdeLaCasaProvider = Provider<FutureOr<Object?> Function(String ventaId)?>(
  (ref) => null,
);
