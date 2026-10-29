import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../agenda/presentation/providers/entrevista_providers.dart';
import '../../../agenda/presentation/widgets/flujo_entrevista.dart';
import '../../../agenda/presentation/widgets/hoja_termino_entrevista.dart' show EntrevistaGuardada;
import '../../../auth/domain/entities/sesion.dart';
import '../../domain/entities/jornada.dart';
import '../../domain/jornada_sin_cerrar.dart';
import '../../domain/usecases/finalizar_jornada_use_case.dart';
import '../pages/corregir_jornada_page.dart';
import '../pages/resumen_jornada_page.dart';
import '../providers/jornada_actual_notifier.dart';
import '../providers/jornada_providers.dart';
import 'hoja_hora_inicio.dart';

/// El [instante] al minuto (sin segundos), menos [minutos].
DateTime menosMinutos(DateTime instante, int minutos) => DateTime(
  instante.year,
  instante.month,
  instante.day,
  instante.hour,
  instante.minute,
).subtract(Duration(minutes: minutos));

/// Cuántos minutos hacia atrás está [hora] del [ahora] mostrado (al minuto).
int minutosAtrasDe(DateTime ahora, DateTime hora) =>
    menosMinutos(ahora, 0).difference(hora).inMinutes;

/// Cuántos minutos hacia atrás se puede marcar el fin: hasta 30, sin pasar del inicio. 0 si la
/// jornada quedó abierta de un día anterior (HU-JOR-002, bug #118): el margen normal no
/// corresponde, hay que preguntar a qué hora terminó (el mismo criterio que usa el caso de uso,
/// [JornadaSinCerrar]). Cerca de la medianoche, con el margen todavía en el día del inicio, sí se
/// ofrece, y la hora elegida puede caer pasadas las 00:00 (#250). Con 0 el selector no se
/// muestra (la fila de fin queda sin toque con `maximo == 0`) y el botón "Cambiar" queda
/// deshabilitado; "Finalizar" llega con `hora: null` y el caso de uso devuelve
/// `FailureJornadaDeDiaAnterior`, que navega a `CorregirJornadaPage`.
int maximoAtrasFinDeJornada(Jornada jornada, DateTime ahora) {
  const margen = FinalizarJornadaUseCase.margenHaciaAtras;
  final quedoAbierta = JornadaSinCerrar.quedoAbierta(
    inicio: jornada.inicio,
    ahora: ahora,
    margen: margen,
  );
  if (quedoAbierta) return 0;
  final desdeInicio = menosMinutos(ahora, 0).difference(jornada.inicio).inMinutes;
  return desdeInicio.clamp(0, margen.inMinutes);
}

/// El cierre de la jornada con la hora de fin elegida por la persona (HU-JOR-002): lo comparten
/// «Hoy» (`JornadaPage`) y la pantalla de la cuenta restringida (#472), para que cerrarla diga lo
/// mismo, con los mismos topes y las mismas validaciones, desde cualquiera de las dos.
///
/// Quien lo usa pone [sesionDelFin], llama a [iniciarTic] en `initState` y a [detenerTic] en
/// `dispose`, asigna [ahoraMostrado] en cada `build`, y dibuja la fila de la hora de fin y el botón
/// con [finalizando], [errorFin] y [horaElegidaFin].
mixin FinDeJornada<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Refresca "Ahora · 14:35" y "Llevás 1 h 20 min" mientras la pantalla está abierta, al cambiar
  /// el minuto.
  Timer? _tic;

  /// La hora de fin elegida a mano (el instante que el colportor vio y confirmó), o `null` si es
  /// "ahora". Absoluta: no se corre si cambia el minuto; si con el tiempo quedó fuera de rango, el
  /// caso de uso la rechaza con el rango explícito (nunca se ajusta en silencio).
  DateTime? horaFin;
  bool finalizando = false;

  /// Mientras se termina la entrevista que estaba abierta (antes de cerrar la jornada): un segundo
  /// toque en el botón de cerrar no abre otra hoja encima.
  bool _terminandoEntrevista = false;
  String? errorFin;

  /// El "ahora" con el que se armó la pantalla que el colportor está viendo (lo actualiza cada
  /// `build`). La hora elegida se calcula con este instante y no con el del toque: si entre el
  /// último refresco y el toque cambió el minuto, se guardaría un minuto más que lo que mostraba la
  /// etiqueta (#102). Si la hora mostrada quedó fuera de rango, el caso de uso la rechaza con el
  /// rango explícito; nunca se ajusta en silencio.
  DateTime? ahoraMostrado;

  /// La sesión de quien cierra la jornada.
  Sesion get sesionDelFin;

  /// Se llama, dentro del `setState` del cierre, cuando la jornada quedó cerrada o corregida: la
  /// pantalla suelta lo suyo (avisos de inicio, bloqueos).
  void alCerrarLaJornada() {}

  /// Redibuja justo cuando cambia el minuto: así "Ahora · 14:35", la hora elegida y lo que se
  /// guarda (que sale del mismo instante, ver [ahoraMostrado]) nunca quedan un minuto atrás del
  /// reloj del teléfono (revisión de #107).
  void iniciarTic() {
    final ahora = ref.read(relojJornadaProvider)();
    final proximoMinuto = DateTime(
      ahora.year,
      ahora.month,
      ahora.day,
      ahora.hour,
      ahora.minute + 1,
    );
    final espera = proximoMinuto.difference(ahora);
    _tic = Timer(espera > Duration.zero ? espera : const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {});
      iniciarTic();
    });
  }

  void detenerTic() => _tic?.cancel();

  /// La hora de fin elegida a mano, o `null` si es "ahora". Absoluta, como la de inicio: no se
  /// corre si cambia el minuto.
  DateTime? horaElegidaFin(Jornada jornada, DateTime ahora) => horaFin;

  /// `true` si no hay una entrevista en curso o si la colportora la terminó (con «No, guardar y
  /// volver al mapa»); `false` si la dejó abierta o eligió registrar la venta, que sigue por su lado
  /// (R44: si la venta no se completa el resultado no se guarda).
  Future<bool> _terminarEntrevistaAbierta() async {
    final colportorId = sesionDelFin.usuarioId;
    final estado = await ref.read(entrevistaEnCursoProvider(colportorId).notifier).esperarLectura();
    if (!estado.hayEntrevista) return true;
    if (!mounted) return false;
    final salida = await FlujoEntrevista.terminar(
      context,
      ref,
      colportorId: colportorId,
      pedirSalida: true,
    );
    return salida is EntrevistaGuardada;
  }

  Future<void> finalizarJornada(Jornada jornada) async {
    if (finalizando || _terminandoEntrevista) return;
    // Una entrevista abierta se termina antes de cerrar la jornada, y su hora de salida se le pide a
    // la colportora: nunca se inventa (decisión de Cristian, 23/10, #450). Si no la termina, la
    // jornada sigue abierta y la entrevista también: no se pierde nada. Todavía no se muestra
    // «Finalizando…»: la hoja de la entrevista es lo que tiene la atención.
    _terminandoEntrevista = true;
    final bool entrevistaTerminada;
    try {
      entrevistaTerminada = await _terminarEntrevistaAbierta();
    } finally {
      _terminandoEntrevista = false;
    }
    if (!entrevistaTerminada || !mounted) return;

    final ahora = ahoraMostrado ?? ref.read(relojJornadaProvider)();
    setState(() {
      finalizando = true;
      errorFin = null;
    });

    final notifier = ref.read(jornadaActualProvider(sesionDelFin.usuarioId).notifier);
    final horaElegida = horaElegidaFin(jornada, ahora);
    var resultado = await notifier.finalizar(hora: horaElegida);

    if (!mounted) return;

    // La hora de fin que se eligió antes ya no vale y «Cambiar» no se puede usar (la jornada quedó
    // abierta de un día anterior y el selector del momento no corresponde): por ejemplo, 23:45
    // elegida antes de la medianoche y una jornada siguiente que empezó a las 23:30 (#339). Repetir
    // el mismo error en cada toque no lleva a ningún lado: se suelta esa hora y se vuelve a pedir
    // sin ella, que lleva a «¿A qué hora terminaste?» con el tope. Nada se cierra con una hora
    // inventada.
    final falloLaHoraVieja =
        horaElegida != null &&
        resultado.fold((failure) => failure is FailureHoraFueraDeRango, (_) => false) &&
        // `maximoAtrasFinDeJornada == 0` no alcanza: también vale 0 por el tope con el reloj a
        // minutos del inicio, y ahí repetir sin hora cerraría con «ahora» (un fin inventado). Solo
        // si la jornada de verdad quedó abierta de un día anterior.
        JornadaSinCerrar.quedoAbierta(
          inicio: jornada.inicio,
          ahora: ref.read(relojJornadaProvider)(),
          margen: FinalizarJornadaUseCase.margenHaciaAtras,
        );
    if (falloLaHoraVieja) {
      setState(() => horaFin = null);
      resultado = await notifier.finalizar();
      if (!mounted) return;
    }

    // Jornada de un día anterior (#109, HU-JOR-002 "jornada que quedó abierta"): no se corrige
    // acá mismo —cerrarla con la hora de hoy inventaría un fin—, se ofrece "¿A qué hora
    // terminaste?" en su propia pantalla. Si vuelve con la jornada ya cerrada, es el mismo cierre
    // exitoso de siempre.
    final failure = resultado.fold<Failure?>((failure) => failure, (_) => null);
    if (failure is FailureJornadaDeDiaAnterior) {
      setState(() => finalizando = false);
      final corregida = await Navigator.of(context).push<Jornada>(
        MaterialPageRoute(
          builder: (_) => CorregirJornadaPage(
            sesion: sesionDelFin,
            inicio: jornada.inicio,
            inicioSiguiente: failure.inicioSiguiente,
          ),
        ),
      );
      if (!mounted) return;
      if (corregida == null) {
        // Ya estaba cerrada (otro teléfono) o no había hora válida: la pantalla muestra lo guardado.
        setState(() => horaFin = null);
        return;
      }
      setState(() {
        horaFin = null;
        alCerrarLaJornada();
      });
      unawaited(_mostrarResumen(corregida));
      return;
    }

    Jornada? cerrada;
    setState(() {
      finalizando = false;
      resultado.fold<void>(
        (failure) => errorFin = switch (failure) {
          // La pantalla se relee y muestra lo que hay guardado. La hora de fin elegida era de esa
          // jornada (que cerró otro teléfono): no pasa a la próxima.
          FailureSinJornadaActiva() => () {
            horaFin = null;
            return null;
          }(),
          FailureHoraFueraDeRango(:final mensaje) => '$mensaje Elegí otra hora y volvé a intentar.',
          // Reloj atrasado: qué pasó y qué hacer (#102).
          FailureValidacion(:final mensaje) => mensaje,
          // No debería llegar acá: se maneja arriba con la navegación a CorregirJornadaPage.
          FailureJornadaDeDiaAnterior(:final mensaje) => mensaje,
          Failure() =>
            'No pudimos guardar el fin de tu jornada, que sigue abierta. Probá de nuevo; si sigue '
                'pasando, avisale a tu coordinador.',
        },
        (jornadaCerrada) {
          cerrada = jornadaCerrada;
          horaFin = null;
          alCerrarLaJornada();
        },
      );
    });
    if (cerrada case final cerrada?) unawaited(_mostrarResumen(cerrada));
  }

  /// El cierre a pantalla completa (vista 21): "Volver al inicio" vuelve a la pantalla de la que se
  /// cerró, ya sin jornada.
  Future<void> _mostrarResumen(Jornada cerrada) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => ResumenJornadaPage(jornada: cerrada)));

  Future<void> elegirHoraFin(DateTime ahora, int maximo) async {
    final actual = horaFin;
    final elegida = await mostrarHojaHoraInicio(
      context,
      ahora: ahora,
      margenMinutos: maximo,
      minutosAtras: actual == null ? 0 : minutosAtrasDe(ahora, actual).clamp(0, maximo),
      pregunta: '¿A qué hora terminaste?',
      etiquetaCampo: 'HORA DE FIN',
    );
    if (!mounted || elegida == null) return;
    setState(() {
      horaFin = elegida.esAhora ? null : elegida.hora;
      errorFin = null;
    });
  }
}
