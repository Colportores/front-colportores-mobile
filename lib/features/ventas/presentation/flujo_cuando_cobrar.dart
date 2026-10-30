import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agenda/domain/entities/agenda.dart';
import '../../agenda/domain/entities/franja_horaria.dart';
import '../../agenda/domain/entities/tipo_agenda.dart';
import '../../agenda/domain/usecases/agendar_visita_use_case.dart';
import '../../agenda/presentation/formato_agendar_visita.dart';
import '../../agenda/presentation/providers/agenda_providers.dart';
import '../../agenda/presentation/textos_agendar_visita.dart';
import '../../agenda/presentation/widgets/piezas_agendar_visita.dart';
import '../domain/entities/nueva_venta.dart';
import 'widgets/hoja_cuando_cobrar.dart';

/// Lo que se hace al guardar una venta con saldo (decisión de Cristian, 23/10, «Agenda cobro»: «Ana
/// elige el día al guardar»): pregunta «¿Cuándo volvés a cobrar?» (hoy, mañana, otro día o sin fecha) y,
/// con fecha, agenda la cobranza de esa persona en esa casa. La cita es una agenda `COBRANZA` común: se
/// ve en la hoja de la casa y en la Agenda, y se cambia desde su detalle.
///
/// La venta **ya está guardada** cuando esto corre: nada de lo que pase acá la deshace. Si la cita no
/// se pudo guardar, el aviso lo dice y dice qué hacer.
abstract final class FlujoCuandoCobrar {
  /// Pregunta y agenda. Devuelve `true` si quedó una cobranza agendada.
  ///
  /// No pregunta nada si la venta no deja saldo (por ejemplo, una venta de misioneros a \$ 0).
  /// Cerrar la hoja de día y hora sin confirmar vuelve a la pregunta; «Sin fecha» siempre es una
  /// salida. [persona] es el nombre de quien debe, para el texto de la pregunta.
  ///
  /// [saldoCentavos] es lo que queda por cobrar: sin él, el total de la venta. Después de «Cobrar
  /// ahora» (27A·14) es lo que quedó sin cobrar, y si ya no queda nada no se pregunta. [alAgendar]
  /// recibe la cobranza que quedó agendada, para que quien llama la muestre (R·08).
  static Future<bool> preguntar(
    BuildContext context,
    ProviderContainer ref, {
    required VentaGuardada guardada,
    required String espacioId,
    required String espacioPersonaId,
    required String colportorId,
    required String persona,
    required String direccion,
    int? saldoCentavos,
    void Function(Agenda agenda)? alAgendar,
  }) async {
    final saldo = saldoCentavos ?? guardada.totalCentavos;
    if (saldo <= 0) return false;
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final agendar = ref.read(agendarVisitaUseCaseProvider);
    final reloj = ref.read(relojVisitaProvider);
    // Los ids de la cita se fijan una vez: un reintento tras una falla no la guarda dos veces.
    final ids = agendar.nuevosIds();

    while (true) {
      if (!context.mounted) return false;
      final opcion = await mostrarHojaCuandoCobrar(context, saldoCentavos: saldo, persona: persona);
      if (opcion == CuandoCobrar.sinFecha || !context.mounted) return false;

      final ahora = reloj();
      final DateTime? dia = switch (opcion) {
        CuandoCobrar.hoy => FormatoAgendarVisita.soloDia(ahora),
        CuandoCobrar.manana => DateTime(ahora.year, ahora.month, ahora.day + 1),
        CuandoCobrar.otroDia => await showDatePicker(
          context: context,
          initialDate: DateTime(ahora.year, ahora.month, ahora.day + 2),
          firstDate: FormatoAgendarVisita.soloDia(ahora),
          lastDate: DateTime(ahora.year, ahora.month, ahora.day + 366),
        ),
        CuandoCobrar.sinFecha => null,
      };
      if (dia == null || !context.mounted) continue;

      final elegido = await mostrarHojaDiaYHora(
        context,
        inicial: _horaSugerida(dia, ahora),
        ahora: ahora,
      );
      if (elegido == null || !context.mounted) continue;

      var confirmoHoraPasada = false;
      while (true) {
        final resultado = await _agendar(
          ref,
          agendar,
          ids: ids,
          espacioId: espacioId,
          espacioPersonaId: espacioPersonaId,
          colportorId: colportorId,
          fecha: elegido,
          direccion: direccion,
          confirmoHoraPasada: confirmoHoraPasada,
        );
        switch (resultado) {
          case VisitaAgendada(:final agenda):
            alAgendar?.call(agenda);
            // Reemplaza al «Venta 0039 guardada.» (que sigue a la vista abajo de la hoja) en vez de
            // quedar en la cola detrás de él, y lo repite.
            mensajero
              ?..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    TextosCuandoCobrar.agendada(
                      guardada.venta.numeroTalonario,
                      FormatoAgendarVisita.cuando(elegido, reloj()),
                    ),
                  ),
                ),
              );
            return true;
          case HoraPasadaSinConfirmar(ahora: final ahoraDelAviso):
            if (!context.mounted) return false;
            final decision = await mostrarHojaHoraPasada(
              context,
              texto: TextosAgendarVisita.horaPasadaTexto(
                FormatoAgendarVisita.cuandoEnFrase(elegido, ahoraDelAviso),
                FormatoAgendarVisita.hora(ahoraDelAviso),
              ),
            );
            if (decision != true) break;
            confirmoHoraPasada = true;
            continue;
          case null:
            mensajero
              ?..clearSnackBars()
              ..showSnackBar(const SnackBar(content: Text(TextosCuandoCobrar.noSePudoAgendar)));
            return false;
        }
        // «Cambiar la hora» (o cerrar sin elegir): vuelve a la pregunta.
        break;
      }
    }
  }

  /// La hora con la que se abre «Día y hora»: mañana y los demás días a las 10:00 (media mañana, como
  /// «Agendar visita»); hoy, el próximo múltiplo de 5 minutos (siempre en el futuro).
  static DateTime _horaSugerida(DateTime dia, DateTime ahora) {
    if (!FormatoAgendarVisita.mismoDia(dia, ahora)) {
      return DateTime(dia.year, dia.month, dia.day, 10);
    }
    final minutos = ahora.hour * 60 + ahora.minute;
    final siguiente = (minutos ~/ pasoDeLaHora + 1) * pasoDeLaHora;
    // Pasada la medianoche no hay un «más tarde hoy»: se queda en el último minuto del día.
    final acotado = siguiente >= 24 * 60 ? 24 * 60 - 1 : siguiente;
    return DateTime(dia.year, dia.month, dia.day, acotado ~/ 60, acotado % 60);
  }

  static Future<ResultadoAgendar?> _agendar(
    ProviderContainer ref,
    AgendarVisitaUseCase agendar, {
    required IdsAgendarVisita ids,
    required String espacioId,
    required String espacioPersonaId,
    required String colportorId,
    required DateTime fecha,
    required String direccion,
    required bool confirmoHoraPasada,
  }) async {
    try {
      final respuesta = await agendar(
        AgendarVisitaParams(
          ids: ids,
          espacioId: espacioId,
          espacioPersonaId: espacioPersonaId,
          colportorId: colportorId,
          tipo: TipoAgenda.cobranza,
          fechaProgramada: fecha,
          franja: FranjaHoraria.sugeridaPara(fecha.hour * 60 + fecha.minute),
          direccion: direccion,
          confirmoHoraPasada: confirmoHoraPasada,
        ),
      );
      return respuesta.fold((_) => null, (r) => r);
    } on Object {
      // Nada del error al aviso: puede traer datos de la persona (convenciones §7.5).
      return null;
    }
  }
}
