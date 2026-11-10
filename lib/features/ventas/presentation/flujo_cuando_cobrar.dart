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
import 'pages/cuando_cobrar_page.dart';

/// Cómo quedó la cobranza después de «¿Cuándo volvés a cobrar?».
sealed class CobranzaDeLaVenta {
  const CobranzaDeLaVenta();
}

/// No queda saldo: no se preguntó nada.
final class SinSaldoQueCobrar extends CobranzaDeLaVenta {
  const SinSaldoQueCobrar();
}

/// «Sin fecha» (o atrás sin elegir): la venta queda en las cobranzas, sin día ni aviso.
final class CobranzaSinFecha extends CobranzaDeLaVenta {
  const CobranzaSinFecha();
}

/// Quedó agendada la cobranza [agenda].
final class CobranzaAgendada extends CobranzaDeLaVenta {
  const CobranzaAgendada(this.agenda);

  final Agenda agenda;
}

/// Eligió un día pero la cita no se pudo guardar: ya se avisó; la venta queda como «sin fecha».
final class CobranzaNoAgendada extends CobranzaDeLaVenta {
  const CobranzaNoAgendada();
}

/// Lo que se hace cuando el hilo de una venta termina con saldo (vista 42, 42B·01B; decisión de
/// Cristian, 23/10, «Agenda cobro»: la cobranza no se agenda sola): pregunta «¿Cuándo volvés a cobrar?»
/// (hoy, mañana, otro día o sin fecha) y, con fecha, agenda la cobranza de esa persona en esa casa. La
/// cita es una agenda `COBRANZA` común: se ve en la hoja de la casa y en la Agenda, y se cambia desde su
/// detalle.
///
/// La venta **ya está guardada** cuando esto corre: nada de lo que pase acá la deshace. Si la cita no
/// se pudo guardar, el aviso lo dice y dice qué hacer. El aviso de lo que quedó agendado lo da quien
/// llama, al cerrar todo (42B·01H).
abstract final class FlujoCuandoCobrar {
  /// Pregunta y agenda. Sin saldo ([saldoCentavos] 0 o menos) no pregunta nada.
  static Future<CobranzaDeLaVenta> preguntar(
    BuildContext context,
    ProviderContainer ref, {
    required String numeroTalonario,
    required String espacioId,
    required String espacioPersonaId,
    required String colportorId,
    required String persona,
    required String direccion,
    required int saldoCentavos,
  }) async {
    if (saldoCentavos <= 0) return const SinSaldoQueCobrar();
    final agendar = ref.read(agendarVisitaUseCaseProvider);
    final reloj = ref.read(relojVisitaProvider);
    // Los ids de la cita se fijan una vez: un reintento tras una falla no la guarda dos veces.
    final ids = agendar.nuevosIds();

    while (true) {
      if (!context.mounted) return const CobranzaSinFecha();
      final eleccion = await CuandoCobrarPage.abrir(
        context,
        numeroTalonario: numeroTalonario,
        persona: persona,
        saldoCentavos: saldoCentavos,
        reloj: reloj,
      );
      final fecha = eleccion.fecha;
      if (eleccion.opcion == CuandoCobrar.sinFecha || fecha == null) {
        return const CobranzaSinFecha();
      }

      var confirmoHoraPasada = false;
      while (true) {
        final resultado = await _agendar(
          ref,
          agendar,
          ids: ids,
          espacioId: espacioId,
          espacioPersonaId: espacioPersonaId,
          colportorId: colportorId,
          fecha: fecha,
          direccion: direccion,
          confirmoHoraPasada: confirmoHoraPasada,
        );
        switch (resultado) {
          case VisitaAgendada(:final agenda):
            return CobranzaAgendada(agenda);
          case HoraPasadaSinConfirmar(ahora: final ahoraDelAviso):
            if (!context.mounted) return const CobranzaSinFecha();
            final decision = await mostrarHojaHoraPasada(
              context,
              texto: TextosAgendarVisita.horaPasadaTexto(
                FormatoAgendarVisita.cuandoEnFrase(fecha, ahoraDelAviso),
                FormatoAgendarVisita.hora(ahoraDelAviso),
              ),
            );
            if (decision != true) break;
            confirmoHoraPasada = true;
            continue;
          case null:
            // El aviso sale en el mapa al volver (42B·01H): acá taparía «Así quedó la venta».
            return const CobranzaNoAgendada();
        }
        // «Cambiar la hora» (o cerrar sin elegir): vuelve a la pregunta.
        break;
      }
    }
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
