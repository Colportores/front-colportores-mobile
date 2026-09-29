import 'package:equatable/equatable.dart';

import 'espacio.dart';
import 'ubicacion.dart';

/// Cómo terminó un pedido de alta de ubicación (HU-UBI-001) que no fue un error.
///
/// Además del alta hecha, hay dos resultados en los que el sistema **no crea** la ubicación y
/// espera una decisión del colportor: una lectura de GPS imprecisa y un duplicado. No son
/// `Failure`: son pasos normales del flujo, y un `switch` sobre esta clase sellada obliga a la
/// pantalla a contemplar los tres.
sealed class ResultadoAltaUbicacion extends Equatable {
  const ResultadoAltaUbicacion();
}

/// La ubicación quedó guardada en el teléfono (y, si es una casa, su espacio default). También es
/// lo que devuelve un segundo pedido con el mismo `id` (doble toque en "Registrar"): la ubicación
/// que ya estaba, sin crear otra.
final class AltaRegistrada extends ResultadoAltaUbicacion {
  const AltaRegistrada({required this.ubicacion, this.espacio});

  final Ubicacion ubicacion;

  /// El espacio default que se creó con la ubicación, o `null` si no corresponde (HU-UBI-001:
  /// solo para `CASA`) o si el alta ya estaba hecha.
  final Espacio? espacio;

  @override
  List<Object?> get props => [ubicacion, espacio];
}

/// La lectura del GPS tiene baja precisión (HU-UBI-001, "Alta con GPS impreciso"): no se creó
/// nada. La pantalla muestra [aviso] y, si el colportor sigue, repite el pedido con
/// `confirmaBajaPrecision: true`; si prefiere, marca el punto a mano.
final class AltaConBajaPrecision extends ResultadoAltaUbicacion {
  const AltaConBajaPrecision({required this.precisionMetros});

  /// Texto literal del criterio de aceptación.
  static const aviso =
      'Tu ubicación tiene baja precisión. ¿Querés ajustar manualmente o continuar?';

  final double precisionMetros;

  @override
  List<Object?> get props => [precisionMetros];
}

/// Hay ubicaciones activas que parecen la misma (HU-UBI-001, "Detección de duplicado"): no se creó
/// la nueva. La pantalla muestra la candidata con vista previa y "Reutilizar esta", "Crear igual"
/// (repite el pedido con una justificación) o "Cancelar".
final class AltaConDuplicados extends ResultadoAltaUbicacion {
  const AltaConDuplicados({required this.candidatas});

  /// De la más cercana a la más lejana; nunca vacía.
  final List<Ubicacion> candidatas;

  @override
  List<Object?> get props => [candidatas];
}
