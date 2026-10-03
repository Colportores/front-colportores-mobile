import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/config_supabase.dart';
import '../../data/datasources/asignacion_campania_data_source.dart';
import '../../data/datasources/fakes/asignacion_campania_en_memoria.dart';

/// Fuente de la campaña y la zona asignadas (vista 18, 18-A07, diferido por decisión de Cristian,
/// 02/10). Con Supabase todavía no hay de dónde (llega con #62): ver [AsignacionCampaniaSinFuente];
/// sin Supabase (tests, demo), en memoria.
final asignacionCampaniaDataSourceProvider = Provider<AsignacionCampaniaDataSource>(
  (ref) =>
      ConfigSupabase.configurada ? AsignacionCampaniaSinFuente() : AsignacionCampaniaEnMemoria(),
);

/// El reloj de la pantalla de espera («Última revisión: hoy a las 14:30»). Un test lo reemplaza.
final ahoraEsperaProvider = Provider<DateTime Function()>((ref) => DateTime.now);
