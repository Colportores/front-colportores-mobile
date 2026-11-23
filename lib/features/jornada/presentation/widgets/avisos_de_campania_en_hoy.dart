import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/dia_de_calendario.dart';
import '../../../auth/domain/entities/campania_inscripta.dart';
import '../../../auth/domain/services/situacion_de_campania.dart';
import '../../../auth/presentation/providers/campanias_inscriptas_providers.dart';
import '../../../auth/presentation/widgets/aviso_campania_por_empezar.dart';
import '../../domain/entities/jornada_rechazada.dart';
import '../providers/jornadas_rechazadas_providers.dart';
import 'aviso_jornada.dart';

/// Lo que dice el aviso de una jornada que el servidor no aceptó por empezar antes del inicio de la
/// campaña (decisión de Cristian del 27/10, backend-supabase#184): sin el error técnico, y diciendo
/// que no se borró nada.
abstract final class TextosJornadaRechazada {
  /// Cuando no se sabe cuál es la campaña (la réplica todavía no la trae).
  static const sinCampania = 'tu campaña todavía no empezó';

  /// El aviso de [jornada], con la [campania] que la frenó si se conoce, vista desde [hoy]
  /// (`AAAA-MM-DD`). Con más de una visita es el texto de la decisión; con una sola o con ninguna se
  /// ajusta el singular.
  static String aviso(
    JornadaRechazada jornada, {
    CampaniaInscripta? campania,
    required String hoy,
  }) {
    final causa = campania == null
        ? sinCampania
        : 'tu campaña ${campania.nombre} '
              '${campania.empezoA(hoy) ? 'empezó' : 'empieza'} el ${diaYMesDe(campania.fechaInicio)}';
    return switch (jornada.visitas) {
      0 => 'Esta jornada no se envió: $causa. No se borró nada; queda guardada en este teléfono.',
      1 =>
        'Esta jornada y su visita no se enviaron: $causa. '
            'No se borró nada; quedan guardadas en este teléfono.',
      final n =>
        'Esta jornada y sus $n visitas no se enviaron: $causa. '
            'No se borró nada; quedan guardadas en este teléfono.',
    };
  }
}

/// Los avisos de campaña de «Hoy» (HU-AUTH-008 y HU-JOR-001): arriba, por cada cosa que pasa.
///
/// - La **campaña por empezar** (decisión de Cristian, 23/10, «Cuenta antes»): cuándo empieza y que
///   hasta entonces no se inicia jornada ni se vende. No sale con una campaña en curso, sin campaña
///   por empezar o sin saber todavía cuál es.
/// - Cada **jornada que el servidor no aceptó** por haber empezado antes de que la campaña empiece
///   (decisión de Cristian, 27/10), con sus visitas bajo el mismo aviso.
///
/// Sin nada que avisar no ocupa lugar.
class AvisosDeCampaniaEnHoy extends ConsumerWidget {
  const AvisosDeCampaniaEnHoy({super.key, required this.usuarioId});

  final String usuarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoy = diaDeCalendario(ref.watch(relojCampaniaProvider)());
    final campanias = ref.watch(campaniasInscriptasProvider(usuarioId)).value;
    final porEmpezar = campanias == null
        ? null
        : SituacionDeCampania.porEmpezar(campanias, hoy: hoy);
    final rechazadas = ref.watch(jornadasRechazadasProvider(usuarioId)).value ?? const [];
    if (porEmpezar == null && rechazadas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          if (porEmpezar != null)
            AvisoJornada(
              key: const Key('jornada_campania_por_empezar'),
              texto: TextosCampaniaPorEmpezar.aviso(porEmpezar),
            ),
          for (final jornada in rechazadas)
            AvisoJornada(
              key: Key('jornada_rechazada_${jornada.id}'),
              texto: TextosJornadaRechazada.aviso(
                jornada,
                campania: campanias == null
                    ? null
                    : SituacionDeCampania.queFrenoElDia(campanias, diaDeCalendario(jornada.inicio)),
                hoy: hoy,
              ),
            ),
        ],
      ),
    );
  }
}
