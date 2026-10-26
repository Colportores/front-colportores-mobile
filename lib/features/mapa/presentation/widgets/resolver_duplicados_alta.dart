import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/duplicado_ubicacion.dart';
import '../providers/alta_ubicacion_notifier.dart';
import '../providers/alta_ubicacion_providers.dart';
import '../salida_alta_ubicacion.dart';
import 'hoja_duplicado_alta.dart';

/// Los nombres de las ciudades de la campaña por id, para decir en qué ciudad está cada candidata de la
/// vista 04. Si no se pueden leer, la hoja las muestra sin ciudad: nunca frena el aviso.
Future<Map<String, String>> nombresDeCiudadesDelAlta(WidgetRef ref, String colportorId) async {
  try {
    final r = await ref.read(ciudadesParaAltaProvider).deMiCampania(colportorId);
    return r.fold<Map<String, String>>(
      (_) => const {},
      (ciudades) => {for (final c in ciudades) c.id: c.nombre},
    );
  } on Object {
    return const {};
  }
}

/// Abre la vista 04 (posible duplicado) sobre el alta de [parametros] y devuelve cómo terminó:
/// [UbicacionReutilizada] si la colportora eligió «Reutilizar esta» / «Abrir la existente»,
/// [UbicacionCreada] si eligió «Crear igual» y quedó registrada, o `null` si cerró la hoja (el alta
/// sigue como estaba). Lo comparten el alta de la vista 03 y la de la vista 39 (N·02).
Future<SalidaAltaUbicacion?> resolverDuplicadosDelAlta(
  BuildContext context,
  WidgetRef ref, {
  required ParametrosAlta parametros,
  required List<CandidataDuplicado> candidatas,
}) async {
  final proveedor = altaUbicacionProvider(parametros);
  final punto = ref.read(proveedor).punto;
  if (punto == null) return null;
  final nombres = await nombresDeCiudadesDelAlta(ref, parametros.colportorId);
  if (!context.mounted) return null;
  final decision = await mostrarHojaDuplicado(
    context,
    candidatas: candidatas,
    puntoNuevo: punto,
    nombresCiudad: nombres,
    ambito: ref.read(proveedor).ambitoMapa,
    crearIgual: (justificacion) =>
        ref.read(proveedor.notifier).registrar(justificacion: justificacion),
    ahora: ref.read(relojAltaUbicacionProvider),
  );
  return switch (decision) {
    DecisionReutilizar(:final ubicacionId) => UbicacionReutilizada(ubicacionId),
    DecisionCreada(:final ubicacion) => UbicacionCreada(ubicacion),
    null => null,
  };
}
