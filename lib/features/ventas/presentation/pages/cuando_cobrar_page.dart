import 'dart:async';

import 'package:flutter/material.dart';

import '../../../agenda/presentation/formato_agendar_visita.dart';
import '../../../agenda/presentation/widgets/piezas_agendar_visita.dart'
    show mostrarHojaDiaYHora, pasoDeLaHora;
import '../formato_venta.dart';
import '../widgets/piezas_venta.dart';

/// Lo que la colportora contesta a «¿Cuándo volvés a cobrar?».
enum CuandoCobrar { hoy, manana, otroDia, sinFecha }

/// Lo que eligió: la opción y, salvo «Sin fecha», el día y la hora de la cobranza.
typedef EleccionCuandoCobrar = ({CuandoCobrar opcion, DateTime? fecha});

/// Los textos de «¿Cuándo volvés a cobrar?» (vista 42, 42B·01B y 42B·01C; decisión de Cristian, 23/10,
/// «Agenda cobro»: la cobranza no se agenda sola, Ana elige el día al guardar).
abstract final class TextosCuandoCobrar {
  static const titulo = '¿Cuándo volvés a cobrar?';
  static const hoy = 'Hoy';
  static const hoySub = 'Más tarde, en esta misma salida';
  static const manana = 'Mañana';
  static const otroDia = 'Otro día';
  static const otroDiaSub = 'Elegís el día y la hora';
  static const sinFecha = 'Sin fecha';
  static const sinFechaSub = 'Queda en tus cobranzas, sin día ni aviso';
  static const guardar = 'Guardar';

  /// «Pedro Gómez · saldo $ 800».
  static String personaYSaldo(String persona, int centavos) => persona.trim().isEmpty
      ? 'Saldo ${FormatoVenta.monto(centavos)}'
      : '${persona.trim()} · saldo ${FormatoVenta.monto(centavos)}';

  /// «Hoy» elegido: «Más tarde, en esta misma salida · 18:30».
  static String hoyALas(DateTime fecha) => '$hoySub · ${FormatoAgendarVisita.hora(fecha)}';

  /// «Sábado 26/10 · 12:30».
  static String diaYHora(DateTime fecha) =>
      '${FormatoAgendarVisita.diaLargo(fecha)} · ${FormatoAgendarVisita.hora(fecha)}';

  /// La venta quedó guardada pero la cita de cobranza no.
  static const noSePudoAgendar =
      'La venta se guardó, pero no pudimos agendar el cobro. Agendalo desde la casa.';
}

/// Las claves de la pantalla, para los tests y para quien la monta.
abstract final class ClavesCuandoCobrar {
  static const pagina = Key('cuando_cobrar_pagina');
  static const guardar = Key('cuando_cobrar_guardar');
  static Key opcion(CuandoCobrar o) => Key('cuando_cobrar_${o.name}');
}

/// «¿Cuándo volvés a cobrar?» (42B·01B): aparece cada vez que el hilo de la venta termina con saldo.
/// Cuatro opciones; «Guardar» se prende al elegir una.
///
/// - «Hoy» y «Mañana» piden la hora (la cita de la Agenda la necesita), con el día ya puesto.
/// - «Otro día» abre «Día y hora» sin los chips «Hoy» y «Mañana», que ya están en la pregunta (01C).
/// - «Sin fecha» no agenda nada: la venta queda en las cobranzas, sin día ni aviso.
/// - Atrás sin elegir es «Sin fecha» (lo que dibuja 01B): la venta ya está guardada y la pregunta no
///   la deshace.
///
/// Devuelve lo que eligió; nunca `null`.
class CuandoCobrarPage extends StatefulWidget {
  const CuandoCobrarPage({
    super.key,
    required this.numeroTalonario,
    required this.persona,
    required this.saldoCentavos,
    required this.reloj,
  });

  final String numeroTalonario;
  final String persona;
  final int saldoCentavos;

  /// La hora del teléfono, leída al elegir: de ahí salen «Hoy», «Mañana» y los días de «Día y hora»
  /// (si la pantalla queda abierta pasada la medianoche, «Mañana» sigue siendo mañana).
  final DateTime Function() reloj;

  /// Abre la pantalla encima de la actual.
  static Future<EleccionCuandoCobrar> abrir(
    BuildContext context, {
    required String numeroTalonario,
    required String persona,
    required int saldoCentavos,
    required DateTime Function() reloj,
  }) async {
    final elegida = await Navigator.of(context).push<EleccionCuandoCobrar>(
      MaterialPageRoute(
        builder: (_) => CuandoCobrarPage(
          numeroTalonario: numeroTalonario,
          persona: persona,
          saldoCentavos: saldoCentavos,
          reloj: reloj,
        ),
      ),
    );
    return elegida ?? (opcion: CuandoCobrar.sinFecha, fecha: null);
  }

  @override
  State<CuandoCobrarPage> createState() => _CuandoCobrarPageState();
}

class _CuandoCobrarPageState extends State<CuandoCobrarPage> {
  CuandoCobrar? _opcion;
  DateTime? _fecha;

  /// Hay una hoja de hora abierta: un doble toque no abre dos.
  var _eligiendo = false;

  /// Ya se fue: un doble toque en «Guardar» (o atrás casi a la vez) no cierra dos pantallas.
  var _saliendo = false;

  DateTime get _hoy => FormatoAgendarVisita.soloDia(widget.reloj());

  DateTime _masDias(int n) => DateTime(_hoy.year, _hoy.month, _hoy.day + n);

  /// La hora con la que se abre la hoja: hoy, el próximo múltiplo de 5 minutos; los demás días, las
  /// 10:00 (media mañana, como «Agendar visita»).
  DateTime _horaSugerida(DateTime dia, DateTime ahora) {
    if (!FormatoAgendarVisita.mismoDia(dia, ahora)) {
      return DateTime(dia.year, dia.month, dia.day, 10);
    }
    final minutos = ahora.hour * 60 + ahora.minute;
    final siguiente = (minutos ~/ pasoDeLaHora + 1) * pasoDeLaHora;
    // Pasada la medianoche no hay un «más tarde hoy»: se queda en el último minuto del día.
    final acotado = siguiente >= 24 * 60 ? 24 * 60 - 1 : siguiente;
    return DateTime(dia.year, dia.month, dia.day, acotado ~/ 60, acotado % 60);
  }

  Future<void> _elegir(CuandoCobrar opcion) async {
    if (_eligiendo || _saliendo) return;
    if (opcion == CuandoCobrar.sinFecha) {
      setState(() {
        _opcion = opcion;
        _fecha = null;
      });
      return;
    }
    _eligiendo = true;
    try {
      // Si ya la había elegido, la hoja abre con lo que eligió.
      final previa = _opcion == opcion ? _fecha : null;
      final ahora = widget.reloj();
      final dia = switch (opcion) {
        CuandoCobrar.hoy => _hoy,
        CuandoCobrar.manana => _masDias(1),
        _ => _masDias(2),
      };
      final elegida = await mostrarHojaDiaYHora(
        context,
        inicial: previa ?? _horaSugerida(dia, ahora),
        ahora: ahora,
        conDia: opcion == CuandoCobrar.otroDia,
        sinHoyNiManana: opcion == CuandoCobrar.otroDia,
      );
      // Cerrar la hoja sin «Listo» deja lo que estaba elegido.
      if (elegida == null || !mounted) return;
      setState(() {
        _opcion = opcion;
        _fecha = elegida;
      });
    } finally {
      _eligiendo = false;
    }
  }

  void _salir(EleccionCuandoCobrar eleccion) {
    if (_saliendo) return;
    _saliendo = true;
    Navigator.of(context).pop(eleccion);
  }

  void _guardar() {
    final opcion = _opcion;
    if (opcion == null) return;
    _salir((opcion: opcion, fecha: opcion == CuandoCobrar.sinFecha ? null : _fecha));
  }

  /// Lo que dice cada opción: lo que eligió, si la eligió; si no, la ayuda del canvas.
  String _ayuda(CuandoCobrar opcion) {
    final fecha = _opcion == opcion ? _fecha : null;
    return switch (opcion) {
      CuandoCobrar.hoy =>
        fecha == null ? TextosCuandoCobrar.hoySub : TextosCuandoCobrar.hoyALas(fecha),
      CuandoCobrar.manana =>
        fecha == null
            ? FormatoAgendarVisita.diaLargo(_masDias(1))
            : TextosCuandoCobrar.diaYHora(fecha),
      CuandoCobrar.otroDia =>
        fecha == null ? TextosCuandoCobrar.otroDiaSub : TextosCuandoCobrar.diaYHora(fecha),
      CuandoCobrar.sinFecha => TextosCuandoCobrar.sinFechaSub,
    };
  }

  @override
  Widget build(BuildContext context) {
    const sinFecha = (opcion: CuandoCobrar.sinFecha, fecha: null);
    return PopScope(
      canPop: false,
      // Atrás (el del sistema o el de la cabecera) sin elegir: queda «sin fecha» (42B·01B).
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _salir(sinFecha);
      },
      child: Scaffold(
        key: ClavesCuandoCobrar.pagina,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                // Cuatro opciones: todas construidas, así el lector y `ensureVisible` llegan a todas.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CabeceraVenta(
                        eyebrow: TextosVenta.eyebrowTalonario(widget.numeroTalonario),
                        titulo: TextosCuandoCobrar.titulo,
                        subtitulo: TextosCuandoCobrar.personaYSaldo(
                          widget.persona,
                          widget.saldoCentavos,
                        ),
                        alVolver: () => _salir(sinFecha),
                      ),
                      for (final (i, opcion) in CuandoCobrar.values.indexed) ...[
                        if (i > 0) const SizedBox(height: 8),
                        FilaElegible(
                          key: ClavesCuandoCobrar.opcion(opcion),
                          titulo: switch (opcion) {
                            CuandoCobrar.hoy => TextosCuandoCobrar.hoy,
                            CuandoCobrar.manana => TextosCuandoCobrar.manana,
                            CuandoCobrar.otroDia => TextosCuandoCobrar.otroDia,
                            CuandoCobrar.sinFecha => TextosCuandoCobrar.sinFecha,
                          },
                          detalle: _ayuda(opcion),
                          elegida: _opcion == opcion,
                          alPresionar: () => unawaited(_elegir(opcion)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: BotonDeVenta(
                  key: ClavesCuandoCobrar.guardar,
                  texto: TextosCuandoCobrar.guardar,
                  alPresionar: _opcion == null ? null : _guardar,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
