import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/config_supabase.dart';
import '../../../../core/database/database_providers.dart';
import '../../data/datasources/fakes/inscripciones_con_zona_en_memoria.dart';
import '../../data/datasources/inscripciones_con_zona_data_source.dart';
import '../../data/datasources/inscripciones_con_zona_local_data_source.dart';
import '../../data/repositories/zonas_avisadas_repository_impl.dart';
import '../../domain/repositories/zonas_avisadas_repository.dart';

/// Fuente de las inscripciones con zona para el aviso de zona (HU-CAM-006, #251). Con Supabase, las
/// réplicas locales del pull de catálogos ([InscripcionesConZonaLocal], mobile#274); sin Supabase
/// (tests, demo), en memoria y sin inscripciones.
final inscripcionesConZonaDataSourceProvider = Provider<InscripcionesConZonaDataSource>(
  (ref) => ConfigSupabase.configurada
      ? InscripcionesConZonaLocal(
          ref.watch(dbLocalProvider),
          ahora: ref.watch(relojAvisosZonaProvider),
        )
      : InscripcionesConZonaEnMemoria(),
);

/// El reloj con el que se decide si una campaña ya terminó. Un test lo reemplaza.
final relojAvisosZonaProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// La zona de cada inscripción la última vez que se le avisó al colportor (#251). En el equipo,
/// `main.dart` lo sobreescribe con el almacén seguro; por defecto (tests), en memoria.
final zonasAvisadasRepositoryProvider = Provider<ZonasAvisadasRepository>(
  (ref) => ZonasAvisadasEnMemoria(),
);
