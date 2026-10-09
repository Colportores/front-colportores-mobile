import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/config_supabase.dart';
import '../../data/datasources/fakes/inscripciones_con_zona_en_memoria.dart';
import '../../data/datasources/inscripciones_con_zona_data_source.dart';
import '../../data/repositories/zonas_avisadas_repository_impl.dart';
import '../../domain/repositories/zonas_avisadas_repository.dart';

/// Fuente de las inscripciones con zona para el aviso de zona (HU-CAM-006, #251). Con Supabase
/// todavía no hay de dónde (llega con el motor, mobile#180, y la lectura del pull, mobile#274): ver
/// [InscripcionesConZonaSinFuente]; sin Supabase (tests, demo), en memoria y sin inscripciones.
final inscripcionesConZonaDataSourceProvider = Provider<InscripcionesConZonaDataSource>(
  (ref) => ConfigSupabase.configurada
      ? InscripcionesConZonaSinFuente()
      : InscripcionesConZonaEnMemoria(),
);

/// La zona de cada inscripción la última vez que se le avisó al colportor (#251). En el equipo,
/// `main.dart` lo sobreescribe con el almacén seguro; por defecto (tests), en memoria.
final zonasAvisadasRepositoryProvider = Provider<ZonasAvisadasRepository>(
  (ref) => ZonasAvisadasEnMemoria(),
);
