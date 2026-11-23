import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../data/datasources/jornadas_rechazadas_data_source.dart';
import '../../domain/entities/jornada_rechazada.dart';

/// De dónde salen las jornadas que el servidor no aceptó por empezar antes del inicio de la campaña:
/// la cola de sync de la DB local ([JornadasRechazadasLocal]); sin la DB abierta, ninguna.
final jornadasRechazadasDataSourceProvider = Provider<JornadasRechazadasDataSource>(
  (ref) => JornadasRechazadasLocal(ref.watch(dbLocalProvider)),
);

/// Las jornadas de [colportorId] que el servidor no aceptó por empezar antes del inicio de la
/// campaña, con sus visitas (decisión de Cristian del 27/10, backend-supabase#184). Reactivo.
final jornadasRechazadasProvider = StreamProvider.family<List<JornadaRechazada>, String>(
  (ref, colportorId) => ref.watch(jornadasRechazadasDataSourceProvider).observar(colportorId),
);
