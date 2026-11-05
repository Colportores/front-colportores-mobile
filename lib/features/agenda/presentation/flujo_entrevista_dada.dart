import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../mapa/domain/entities/persona_de_la_entrevista.dart';
import '../../mapa/presentation/providers/hoja_casa_providers.dart'
    show ContextoDeEntrevista, VentaRegistradaEnLaCasa;
import '../domain/entities/entrevista_en_curso.dart';
import 'providers/entrevista_providers.dart';
import 'providers/rotulo_entrevista_providers.dart';
import 'widgets/flujo_entrevista.dart';
import 'widgets/hoja_termino_entrevista.dart';
import 'widgets/textos_entrevista.dart';

/// «Entrevista dada» de «¿Qué pasó?» (vista 39, R·04 → R·05): lo que sigue a «¿Con quién?». Es lo que
/// enchufa `entrevistaDadaDesdeLaCasaProvider` (#648).
///
/// 1. «Empezar entrevista»: guarda la entrevista en curso en el teléfono con la hora del toque (decisión
///    de Cristian, 04/11: el inicio es el toque, sin GPS de fondo). Un segundo toque, o volver a
///    «Empezar» con una ya en curso, no pisa la hora: devuelve la que estaba.
/// 2. R·05: abre «Entrevista en curso» sobre el mapa y sigue a «Finalizar entrevista» → R·06
///    («¿Hubo venta?») → la venta (vista 27) o «No, guardar y volver al mapa». Todo eso es
///    [FlujoEntrevista].
/// 3. Si «Empezar» no se pudo guardar (no hay entrevista en curso), no se pierde la entrevista: sigue
///    R·07, «Terminó la entrevista» sin inicio registrado, que toma la hora de la visita anterior con el
///    aviso «Revisala» (decisión del 23/10, #450).
///
/// Devuelve lo que espera el gancho: `true` si la entrevista quedó guardada o en curso (la hoja de la
/// casa se cierra: el mapa muestra el color nuevo o el aviso fijo), [VentaRegistradaEnLaCasa] si terminó
/// en una venta (la hoja de la casa sigue abierta, R·08) y `false` si no se hizo nada.
abstract final class FlujoEntrevistaDada {
  static Future<Object?> abrir(
    BuildContext context,
    ContextoDeEntrevista datos, {
    required String? colportorId,
  }) async {
    final colportor = colportorId?.trim();
    if (colportor == null || colportor.isEmpty) return false;
    // La entrevista en curso guarda con quién es: «Todavía no sé con quién» (persona `null`, #653) no
    // tiene dónde guardarse hasta que se decida cómo se modela (pendiente de decisión, no se inventa
    // a nadie ni se descarta en silencio: queda en el log y «¿Qué pasó?» sigue abierta).
    final persona = datos.persona;
    if (persona == null) {
      AppLogger.instance.warn(
        LogModulo.agenda,
        'ENTREVISTA_SIN_PERSONA',
        'la entrevista en curso todavía no admite «sin persona»; no se empezó',
      );
      return false;
    }
    final contenedor = ProviderScope.containerOf(context, listen: false);
    final empezada = await contenedor
        .read(entrevistaEnCursoProvider(colportor).notifier)
        .empezar(
          espacioId: datos.espacioId,
          espacioPersonaId: persona.espacioPersonaId,
          agendaId: datos.agendaId,
          jornadaId: datos.jornadaId,
        );
    final entrevista = empezada.fold<EntrevistaEnCurso?>((_) => null, (e) => e);
    if (entrevista == null) {
      // Decisión §2 (R6): la colportora no puede hacer nada con el detalle; sigue R·07 y el fallo
      // queda en el log, sin datos de personas.
      AppLogger.instance.warn(
        LogModulo.agenda,
        'ENTREVISTA_EMPEZAR',
        'no se pudo guardar el inicio de la entrevista; sigue R·07',
        {'falla': empezada.fold((f) => f.runtimeType.toString(), (_) => '')},
      );
      if (!context.mounted) return false;
      return _sinInicio(context, contenedor, colportor, datos, persona);
    }
    // Ya hay una entrevista en curso y es de otra casa, o de otra persona de esta casa: `empezar`
    // devolvió la vieja, y abrirla con «¿Con quién?» descartado dejaría la visita (y la venta) a
    // nombre de quien no se eligió. No se empieza otra encima.
    if (entrevista.espacioId != datos.espacioId ||
        entrevista.espacioPersonaId != persona.espacioPersonaId) {
      final aviso = await _avisoDeOtra(contenedor, entrevista);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(aviso)));
      }
      return false;
    }
    if (!context.mounted) return true;
    final salida = await FlujoEntrevista.abrirEn(context, contenedor, colportorId: colportor);
    return _resultado(salida);
  }

  /// Si [colportorId] ya tiene una entrevista en curso en una casa que no es [espacioId], el aviso que
  /// lo dice («Ya tenés una entrevista en curso en Grecia 3307. Terminala antes de empezar otra.»); si
  /// no, `null`. Lo usa «¿Qué pasó?» antes de preguntar «¿Con quién?», para no pedir un dato que no
  /// va a servir. Si no se puede leer, `null`: no se afirma lo que no se sabe.
  static Future<String?> avisoSiHayOtraEnCurso(
    ProviderContainer contenedor, {
    required String colportorId,
    required String espacioId,
  }) async {
    try {
      final estado = await contenedor
          .read(entrevistaEnCursoProvider(colportorId).notifier)
          .esperarLectura();
      final enCurso = estado.entrevista;
      if (enCurso == null || enCurso.espacioId == espacioId) return null;
      return await _avisoDeOtra(contenedor, enCurso);
    } on Object {
      return null;
    }
  }

  static Future<String> _avisoDeOtra(
    ProviderContainer contenedor,
    EntrevistaEnCurso enCurso,
  ) async {
    var direccion = '';
    try {
      direccion = (await contenedor.read(rotuloDeEntrevistaProvider(enCurso).future)).direccion;
    } on Object {
      // Sin dirección: el aviso dice «en otra casa».
    }
    return TextosEntrevista.yaHayUnaEnCurso(direccion);
  }

  static Future<Object?> _sinInicio(
    BuildContext context,
    ProviderContainer contenedor,
    String colportorId,
    ContextoDeEntrevista datos,
    PersonaDeLaEntrevista persona,
  ) async {
    final salida = await FlujoEntrevista.terminarSinInicioDeLaCasa(
      context,
      contenedor,
      colportorId: colportorId,
      espacioId: datos.espacioId,
      espacioPersonaId: persona.espacioPersonaId,
      agendaId: datos.agendaId,
      jornadaId: datos.jornadaId,
    );
    return switch (salida) {
      EntrevistaGuardada() => true,
      VentaGuardadaEnLaEntrevista() => const VentaRegistradaEnLaCasa(),
      // Cerró R·07 sin guardar, o la venta no se completó: no hay entrevista ni visita, y «¿Qué pasó?»
      // sigue abierta para elegir de nuevo.
      _ => false,
    };
  }

  /// La entrevista ya está en curso: salga como salga R·05 (la dejó abierta, la guardó, la llevó a la
  /// venta), «¿Qué pasó?» se resolvió.
  static Object? _resultado(SalidaTerminoEntrevista? salida) => switch (salida) {
    VentaGuardadaEnLaEntrevista() => const VentaRegistradaEnLaCasa(),
    _ => true,
  };
}
