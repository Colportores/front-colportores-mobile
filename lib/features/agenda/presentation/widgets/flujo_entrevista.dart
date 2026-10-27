import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/entrevista_en_curso.dart';
import '../../domain/usecases/finalizar_entrevista_use_case.dart';
import '../providers/agenda_providers.dart';
import '../providers/entrevista_providers.dart';
import '../providers/rotulo_entrevista_providers.dart';
import 'hoja_entrevista_en_curso.dart';
import 'hoja_termino_entrevista.dart';
import 'textos_entrevista.dart';

/// El recorrido de una entrevista en curso, de la hoja R·05 a «Terminó la entrevista» (R·06 / R·07).
/// Lo abren el aviso fijo del mapa, la hoja de la casa (#444) y el cierre de la jornada.
abstract final class FlujoEntrevista {
  /// R·05: abre «Entrevista en curso» de [colportorId] y, si toca «Finalizar entrevista», sigue a
  /// [terminar]. Sin entrevista en curso no hace nada.
  static Future<SalidaTerminoEntrevista?> abrir(
    BuildContext context,
    WidgetRef ref, {
    required String colportorId,
  }) async {
    final notificador = ref.read(entrevistaEnCursoProvider(colportorId).notifier);
    final estado = await notificador.esperarLectura();
    final entrevista = estado.entrevista;
    if (entrevista == null || !context.mounted) return null;
    final rotulo = await _rotulo(ref, entrevista);
    if (!context.mounted) return null;

    final finalizar = await mostrarHojaEntrevistaEnCurso(
      context,
      direccion: rotulo.direccion,
      persona: rotulo.persona,
      inicio: entrevista.inicio,
      notaInicial: estado.notaBorrador,
      alEscribirNota: notificador.escribirNota,
      reloj: ref.read(relojEntrevistaProvider),
    );
    if (finalizar != true || !context.mounted) return null;
    return terminar(context, ref, colportorId: colportorId, pedirSalida: estado.recuperada);
  }

  /// R·06: «Terminó la entrevista» de la que [colportorId] tiene en curso.
  ///
  /// La salida es «ahora» salvo que [pedirSalida]: si la app se cerró con la entrevista abierta o se
  /// termina la jornada con ella abierta, la hora de salida **no se inventa**, se le pide
  /// (decisión de Cristian, 23/10, #450). Devuelve cómo se cerró la hoja, o `null` si no había
  /// entrevista o se cerró sin elegir (la entrevista sigue en curso).
  static Future<SalidaTerminoEntrevista?> terminar(
    BuildContext context,
    WidgetRef ref, {
    required String colportorId,
    bool pedirSalida = false,
  }) async {
    final notificador = ref.read(entrevistaEnCursoProvider(colportorId).notifier);
    final estado = await notificador.esperarLectura();
    final entrevista = estado.entrevista;
    if (entrevista == null || !context.mounted) return null;
    final rotulo = await _rotulo(ref, entrevista);
    if (!context.mounted) return null;

    final reloj = ref.read(relojEntrevistaProvider);
    final salida = pedirSalida ? null : reloj();
    final mensajero = ScaffoldMessenger.maybeOf(context);
    // «Sin salida» (25/10): si la casa ya no está en el teléfono no hay dónde guardar la visita; la
    // entrevista se suelta y la hoja se cierra con un aviso, para no dejar trabado el cierre de la
    // jornada.
    var sinLugar = false;
    final resultado = await mostrarHojaTerminoEntrevista(
      context,
      direccion: rotulo.direccion,
      persona: rotulo.persona,
      entrada: entrevista.inicio,
      salida: salida,
      entradaInferida: false,
      reloj: reloj,
      alGuardar: (entrada, salida) async {
        final guardado = await notificador.finalizar(entrada: entrada, salida: salida);
        // `null`: ya había un guardado en curso (no pasa con la hoja, que lo impide).
        if (guardado == null) return const FailureInesperado();
        return guardado.fold<Failure?>((falla) {
          if (falla != entrevistaSinLugar) return falla;
          sinLugar = true;
          return null;
        }, (_) => null);
      },
    );
    if (resultado is EntrevistaGuardada) {
      mensajero?.showSnackBar(
        SnackBar(
          content: Text(
            sinLugar
                ? TextosEntrevista.sinLugar
                : TextosEntrevista.guardada(_lugar(rotulo.direccion)),
          ),
        ),
      );
    }
    return resultado;
  }

  /// R·07: «Terminó la entrevista» **sin inicio registrado**. La entrada es la hora de la visita
  /// anterior de la colportora (con el aviso de que se tomó de ahí) o, si no tiene ninguna, queda
  /// para elegir. La salida es «ahora». Los ids de la visita se fijan al abrir la hoja: reintentar
  /// tras una falla no la guarda dos veces.
  static Future<SalidaTerminoEntrevista?> terminarSinInicio(
    BuildContext context,
    WidgetRef ref, {
    required String colportorId,
    required String espacioId,
    required String espacioPersonaId,
    required String direccion,
    required String persona,
    String? agendaId,
    String? jornadaId,
  }) async {
    final notificador = ref.read(entrevistaEnCursoProvider(colportorId).notifier);
    final entrada = await notificador.horaDeLaVisitaAnterior();
    if (!context.mounted) return null;
    final reloj = ref.read(relojEntrevistaProvider);
    final ids = ref.read(registrarResultadoVisitaUseCaseProvider).nuevosIds();
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final resultado = await mostrarHojaTerminoEntrevista(
      context,
      direccion: direccion,
      persona: persona,
      entrada: entrada,
      salida: reloj(),
      entradaInferida: entrada != null,
      reloj: reloj,
      alGuardar: (entrada, salida) async {
        final guardado = await notificador.finalizarSinInicio(
          FinalizarEntrevistaParams(
            ids: ids,
            espacioId: espacioId,
            espacioPersonaId: espacioPersonaId,
            colportorId: colportorId,
            entrada: entrada,
            salida: salida,
            agendaId: agendaId,
            jornadaId: jornadaId,
            nota: ref.read(entrevistaEnCursoProvider(colportorId)).notaBorrador,
          ),
        );
        return guardado.fold<Failure?>((falla) => falla, (_) => null);
      },
    );
    if (resultado is EntrevistaGuardada) {
      mensajero?.showSnackBar(
        SnackBar(content: Text(TextosEntrevista.guardada(_lugar(direccion)))),
      );
    }
    return resultado;
  }

  static Future<RotuloEntrevista> _rotulo(WidgetRef ref, EntrevistaEnCurso entrevista) async {
    try {
      return await ref.read(rotuloDeEntrevistaProvider(entrevista).future);
    } on Object {
      return (direccion: '', persona: '');
    }
  }

  /// «Grecia 3307», o «La casa» si no se sabe la dirección.
  static String _lugar(String direccion) => direccion.isEmpty ? 'La casa' : direccion;
}
