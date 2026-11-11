import 'dart:async';

import 'package:flutter/material.dart';

import '../../../agenda/domain/entities/agenda.dart';
import '../../../agenda/presentation/formato_agendar_visita.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../flujo_cuando_cobrar.dart';
import '../formato_venta.dart';
import '../widgets/piezas_entrega.dart' show RenglonDeResumen;
import '../widgets/piezas_venta.dart';

/// Cómo quedó la entrega al cerrar la venta.
enum EntregaDelCierre {
  /// Entregó todo en el momento (27B·01).
  completa,

  /// Entregó una parte; el resto queda para otro día.
  parcial,

  /// No entregó nada ahora.
  otroDia,
}

/// Los textos de «Así quedó la venta» (vista 42, 42B·01D a 42B·01H).
abstract final class TextosCierreDeVenta {
  static const titulo = 'Así quedó la venta';
  static const volverAlMapa = 'Volver al mapa';
  static const entrega = 'Entrega';
  static const entregadaHoy = '✓ Entregada hoy';
  static const entregadaEnParte = '✓ Una parte hoy, el resto otro día';
  static const entregaOtroDia = '⇢ Otro día';
  static const cobro = 'Cobro';
  static const sinCobrar = 'Sin cobrar';
  static const saldo = 'Saldo';
  static const total = 'Total';
  static const completa = 'Venta completa: entregaste todo y está pagada.';
  static const cambiar = 'Cambiar';
  static const ponerFecha = 'Poner fecha';
  static const sinFecha = 'SIN FECHA';

  /// «Poner fecha» o «Cambiar» no pudo guardar la cita: la tarjeta sigue como estaba (el mismo texto
  /// que el grupo «Sin fecha» de la Agenda). Va en la tarjeta: un aviso abajo taparía el botón.
  static const noSePudoAgendar = 'No pudimos agendar el cobro. Probá de nuevo.';

  /// «✓ $ 400 en efectivo» (el cobro de la vista 28 es en efectivo).
  static String cobrado(int centavos) => '✓ ${FormatoVenta.monto(centavos)} en efectivo';

  /// «Pedro Gómez · Grecia 3307».
  static String personaYLugar(String persona, String direccion) =>
      [persona.trim(), direccion.trim()].where((t) => t.isNotEmpty).join(' · ');

  /// «SÁB 26/10 · 12:30».
  static String cuandoEnTarjeta(DateTime fecha) =>
      '${FormatoAgendarVisita.diaCortoYMes(fecha).toUpperCase()} · ${FormatoAgendarVisita.hora(fecha)}';

  /// «Cobranza agendada · Pedro».
  static String cobranzaAgendada(String persona) => _conNombre('Cobranza agendada', persona);

  /// «Cobranza · Pedro».
  static String cobranzaSinFecha(String persona) => _conNombre('Cobranza', persona);

  /// «SÁB 26/10»: el día de la entrega agendada (01F, 01G; el canvas no pone la hora).
  static String diaEnTarjeta(DateTime fecha) =>
      FormatoAgendarVisita.diaCortoYMes(fecha).toUpperCase();

  /// «Entrega agendada · Pedro».
  static String entregaAgendada(String persona) => _conNombre('Entrega agendada', persona);

  /// «Colección de 1 libro · con recordatorio»: qué se entrega y si va a sonar el aviso (sin aviso se
  /// dice, nunca se promete uno que no suena).
  static String detalleDeLaEntrega(String descripcion, {required bool conRecordatorio}) => [
    descripcion.trim(),
    if (conRecordatorio) 'con recordatorio' else 'sin recordatorio',
  ].where((t) => t.isNotEmpty).join(' · ');

  /// «Saldo $ 800 · en Grecia 3307».
  static String saldoEn(int centavos, String direccion) => direccion.trim().isEmpty
      ? 'Saldo ${FormatoVenta.monto(centavos)}'
      : 'Saldo ${FormatoVenta.monto(centavos)} · en ${direccion.trim()}';

  /// «Saldo $ 1.200 · queda en tus cobranzas, sin día».
  static String saldoSinDia(int centavos) =>
      'Saldo ${FormatoVenta.monto(centavos)} · queda en tus cobranzas, sin día';

  static String _conNombre(String que, String persona) {
    final nombre = persona.trim().split(RegExp(r'\s+')).first;
    return nombre.isEmpty ? que : '$que · $nombre';
  }

  // 42B·01H: el aviso en el mapa al volver.
  /// «Venta 0039 guardada. Entregada y pagada.»
  static String avisoEntregadaYPagada(String numero) =>
      'Venta $numero guardada. Entregada y pagada.';

  /// «Venta 0039 guardada. Cobranza agendada: sáb 26/10 · 12:30.»
  static String avisoCobranzaAgendada(String numero, DateTime fecha) =>
      'Venta $numero guardada. Cobranza agendada: '
      '${FormatoAgendarVisita.diaCortoYMes(fecha).toLowerCase()} · '
      '${FormatoAgendarVisita.hora(fecha)}.';

  /// «Venta 0039 guardada. Cobranza sin fecha.»
  static String avisoCobranzaSinFecha(String numero) =>
      'Venta $numero guardada. Cobranza sin fecha.';

  /// 01F: «Venta 0039 guardada. Entrega agendada: sáb 26/10.»
  static String avisoEntregaAgendada(String numero, DateTime entrega) =>
      'Venta $numero guardada. Entrega agendada: ${_dia(entrega)}.';

  /// 01G: «Venta 0039 guardada. Entrega: sáb 26/10. Cobranza sin fecha.»
  static String avisoEntregaYCobranzaSinFecha(String numero, DateTime entrega) =>
      'Venta $numero guardada. Entrega: ${_dia(entrega)}. Cobranza sin fecha.';

  /// La entrega y la cobranza con fecha (el canvas no lo dibuja; se arma como 01E y 01G): «Venta 0039
  /// guardada. Entrega: sáb 26/10. Cobranza agendada: lun 28/10 · 10:00.»
  static String avisoEntregaYCobranzaAgendada(String numero, DateTime entrega, DateTime cobro) =>
      'Venta $numero guardada. Entrega: ${_dia(entrega)}. Cobranza agendada: '
      '${_dia(cobro)} · ${FormatoAgendarVisita.hora(cobro)}.';

  static String _dia(DateTime fecha) => FormatoAgendarVisita.diaCortoYMes(fecha).toLowerCase();
}

/// Las claves de la pantalla, para los tests.
abstract final class ClavesCierreDeVenta {
  static const pagina = Key('cierre_venta_pagina');
  static const completa = Key('cierre_venta_completa');
  static const tarjetaCobranza = Key('cierre_venta_cobranza');
  static const tarjetaEntrega = Key('cierre_venta_entrega');
  static const accionCobranza = Key('cierre_venta_cobranza_accion');
  static const fallaCobranza = Key('cierre_venta_cobranza_falla');
  static const volver = Key('cierre_venta_volver');
}

/// «Así quedó la venta» (vista 42, 42B·01D a 42B·01G): el cierre único del hilo de la venta, después
/// de la entrega, el cobro y «¿Cuándo volvés a cobrar?». Reemplaza a 27B·03 y 27B·04 en la venta.
///
/// Muestra lo vendido, la entrega, el cobro y el saldo; sin saldo y con todo entregado, «Venta
/// completa» (01D). Con saldo, la tarjeta de la cobranza: con fecha y «Cambiar» (01E), o «Sin fecha»
/// y «Poner fecha» (01G). Con la entrega agendada en «Entregar otro día» (27C, #435), su tarjeta
/// «Entrega agendada» va antes que la de la cobranza (01F, 01G).
///
/// No tiene atrás: la venta ya está guardada. El atrás del sistema hace lo mismo que el botón. Devuelve
/// cómo quedó la cobranza (con lo que haya cambiado acá).
class AsiQuedoLaVentaPage extends StatefulWidget {
  const AsiQuedoLaVentaPage({
    super.key,
    required this.numeroTalonario,
    required this.persona,
    required this.direccion,
    required this.descripcion,
    required this.totalCentavos,
    required this.entrega,
    required this.cobradoCentavos,
    required this.saldoCentavos,
    required this.cobranza,
    this.alCambiar,
    this.alPonerFecha,
    this.entregaAgendada,
    this.textoBoton = TextosCierreDeVenta.volverAlMapa,
  });

  final String numeroTalonario;
  final String persona;
  final String direccion;

  /// Lo vendido en una línea («Colección de 1 libro»); vacío si no se sabe.
  final String descripcion;
  final int totalCentavos;
  final EntregaDelCierre entrega;
  final int cobradoCentavos;
  final int saldoCentavos;
  final CobranzaDeLaVenta cobranza;

  /// «Cambiar» de la cobranza agendada (22C·02): devuelve la cita como quedó, o `null` si no cambió.
  final Future<Agenda?> Function(Agenda agenda)? alCambiar;

  /// «Poner fecha» de la cobranza sin fecha: vuelve a preguntar «¿Cuándo volvés a cobrar?».
  final Future<CobranzaDeLaVenta> Function()? alPonerFecha;

  /// La entrega que quedó agendada en «Entregar otro día» (27C·01): cuándo (local) y si va a sonar el
  /// recordatorio; `null` si no se agendó ninguna.
  final ({DateTime fecha, bool conRecordatorio})? entregaAgendada;

  final String textoBoton;

  static Future<CobranzaDeLaVenta> abrir(BuildContext context, AsiQuedoLaVentaPage pagina) async {
    final quedo = await Navigator.of(
      context,
    ).push<CobranzaDeLaVenta>(MaterialPageRoute(builder: (_) => pagina));
    return quedo ?? pagina.cobranza;
  }

  @override
  State<AsiQuedoLaVentaPage> createState() => _AsiQuedoLaVentaPageState();
}

class _AsiQuedoLaVentaPageState extends State<AsiQuedoLaVentaPage> {
  late CobranzaDeLaVenta _cobranza = widget.cobranza;
  var _ocupado = false;
  var _saliendo = false;

  /// La última «Poner fecha» o «Cambiar» no pudo guardar la cita.
  var _fallo = false;

  void _salir() {
    if (_saliendo || _ocupado) return;
    _saliendo = true;
    Navigator.of(context).pop(_cobranza);
  }

  /// «Cambiar» o «Poner fecha»: una a la vez, y lo que vuelva reemplaza a la tarjeta.
  Future<void> _accion(Future<CobranzaDeLaVenta?> Function() accion) async {
    if (_ocupado || _saliendo) return;
    setState(() {
      _ocupado = true;
      _fallo = false;
    });
    try {
      final nueva = await accion();
      if (!mounted) return;
      if (nueva is CobranzaAgendada) setState(() => _cobranza = nueva);
      // «Poner fecha» eligió un día pero la cita no se guardó: se dice acá, la tarjeta sigue sin fecha.
      if (nueva is CobranzaNoAgendada) setState(() => _fallo = true);
    } on Object {
      // La tarjeta queda como estaba: la cita (si había) sigue guardada.
      if (mounted) setState(() => _fallo = true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saldo = widget.saldoCentavos;
    final completa = saldo <= 0 && widget.entrega == EntregaDelCierre.completa;
    final tarjeta = _tarjetaDeCobranza();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _salir();
      },
      child: Scaffold(
        key: ClavesCierreDeVenta.pagina,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CabeceraVenta(
                        eyebrow: TextosVenta.eyebrowTalonario(widget.numeroTalonario),
                        titulo: TextosCierreDeVenta.titulo,
                        subtitulo: TextosCierreDeVenta.personaYLugar(
                          widget.persona,
                          widget.direccion,
                        ),
                      ),
                      RenglonDeResumen(
                        rotulo: widget.descripcion.trim().isEmpty
                            ? TextosCierreDeVenta.total
                            : widget.descripcion.trim(),
                        valor: FormatoVenta.monto(widget.totalCentavos),
                        cifra: true,
                      ),
                      RenglonDeResumen(
                        rotulo: TextosCierreDeVenta.entrega,
                        valor: switch (widget.entrega) {
                          EntregaDelCierre.completa => TextosCierreDeVenta.entregadaHoy,
                          EntregaDelCierre.parcial => TextosCierreDeVenta.entregadaEnParte,
                          EntregaDelCierre.otroDia => TextosCierreDeVenta.entregaOtroDia,
                        },
                      ),
                      RenglonDeResumen(
                        rotulo: TextosCierreDeVenta.cobro,
                        valor: widget.cobradoCentavos > 0
                            ? TextosCierreDeVenta.cobrado(widget.cobradoCentavos)
                            : TextosCierreDeVenta.sinCobrar,
                      ),
                      RenglonDeResumen(
                        rotulo: TextosCierreDeVenta.saldo,
                        valor: FormatoVenta.monto(saldo < 0 ? 0 : saldo),
                        cifra: true,
                      ),
                      const SizedBox(height: 14),
                      if (completa) const _CartelCompleta(),
                      if (widget.entregaAgendada case final entrega?) ...[
                        _TarjetaDeCobranza(
                          clave: ClavesCierreDeVenta.tarjetaEntrega,
                          glifo: '⇢',
                          colorGlifo: ColoresAgenda.gris,
                          antes: TextosCierreDeVenta.diaEnTarjeta(entrega.fecha),
                          titulo: TextosCierreDeVenta.entregaAgendada(widget.persona),
                          detalle: TextosCierreDeVenta.detalleDeLaEntrega(
                            widget.descripcion,
                            conRecordatorio: entrega.conRecordatorio,
                          ),
                          accion: null,
                          alAccion: null,
                        ),
                        if (tarjeta != null) const SizedBox(height: 10),
                      ],
                      ?tarjeta,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: BotonDeVenta(
                  key: ClavesCierreDeVenta.volver,
                  texto: widget.textoBoton,
                  ocupado: _ocupado,
                  alPresionar: _salir,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _tarjetaDeCobranza() {
    if (widget.saldoCentavos <= 0) return null;
    final cambiar = widget.alCambiar;
    final ponerFecha = widget.alPonerFecha;
    switch (_cobranza) {
      case CobranzaAgendada(:final agenda):
        final fecha = agenda.fechaProgramada.toLocal();
        return _TarjetaDeCobranza(
          antes: TextosCierreDeVenta.cuandoEnTarjeta(fecha),
          titulo: TextosCierreDeVenta.cobranzaAgendada(widget.persona),
          detalle: TextosCierreDeVenta.saldoEn(widget.saldoCentavos, widget.direccion),
          fallo: _fallo,
          accion: cambiar == null ? null : TextosCierreDeVenta.cambiar,
          alAccion: cambiar == null || _ocupado
              ? null
              : () => unawaited(
                  _accion(() async {
                    final nueva = await cambiar(agenda);
                    return nueva == null ? null : CobranzaAgendada(nueva);
                  }),
                ),
        );
      case CobranzaSinFecha() || CobranzaNoAgendada() || SinSaldoQueCobrar():
        return _TarjetaDeCobranza(
          antes: TextosCierreDeVenta.sinFecha,
          titulo: TextosCierreDeVenta.cobranzaSinFecha(widget.persona),
          detalle: TextosCierreDeVenta.saldoSinDia(widget.saldoCentavos),
          fallo: _fallo,
          accion: ponerFecha == null ? null : TextosCierreDeVenta.ponerFecha,
          alAccion: ponerFecha == null || _ocupado ? null : () => unawaited(_accion(ponerFecha)),
        );
    }
  }
}

/// 42B·01D: «Venta completa: entregaste todo y está pagada.»
class _CartelCompleta extends StatelessWidget {
  const _CartelCompleta();

  static const _verde = Color(0xFF1F6E3A);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: ClavesCierreDeVenta.completa,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFDDE8D3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _verde, width: 1.5),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Text(
                '★',
                style: TextStyle(fontSize: 16, color: _verde, fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                TextosCierreDeVenta.completa,
                style: TextStyle(fontSize: 14, height: 1.4, color: _verde),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La tarjeta de la cobranza: «SÁB 26/10 · 12:30», «Cobranza agendada · Pedro», «Saldo $ 800 · en
/// Grecia 3307» y «Cambiar» (01E); o «SIN FECHA» y «Poner fecha» (01G).
class _TarjetaDeCobranza extends StatelessWidget {
  const _TarjetaDeCobranza({
    this.clave = ClavesCierreDeVenta.tarjetaCobranza,
    this.glifo = r'$',
    this.colorGlifo = ColoresAgenda.azul,
    required this.antes,
    required this.titulo,
    required this.detalle,
    required this.accion,
    required this.alAccion,
    this.fallo = false,
  });

  final Key clave;
  final String glifo;
  final Color colorGlifo;
  final String antes;
  final String titulo;
  final String detalle;
  final String? accion;
  final VoidCallback? alAccion;
  final bool fallo;

  @override
  Widget build(BuildContext context) {
    final escala = MediaQuery.textScalerOf(context).scale(1);
    final glifo = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colorGlifo, borderRadius: BorderRadius.circular(6)),
      child: ExcludeSemantics(
        child: Text(
          this.glifo,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          antes,
          style: TextStyle(
            fontSize: 11.5,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: colorGlifo,
          ),
        ),
        Text(titulo, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        Text(detalle, style: const TextStyle(fontSize: 12.5, color: ColoresAgenda.gris)),
        if (fallo)
          Semantics(
            liveRegion: true,
            container: true,
            child: const Padding(
              key: ClavesCierreDeVenta.fallaCobranza,
              padding: EdgeInsets.only(top: 6),
              child: Text(
                TextosCierreDeVenta.noSePudoAgendar,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: ColoresAgenda.rojo,
                ),
              ),
            ),
          ),
      ],
    );
    final boton = accion == null
        ? null
        : TextButton(
            key: ClavesCierreDeVenta.accionCobranza,
            onPressed: alAccion,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(
              accion!,
              style: const TextStyle(fontWeight: FontWeight.w700, color: ColoresAgenda.azul),
            ),
          );
    return Container(
      key: clave,
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E7EE)),
      ),
      // Con la letra grande el botón baja debajo del texto: al costado no entra.
      child: escala > 1.5
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    glifo,
                    const SizedBox(width: 10),
                    Expanded(child: textos),
                  ],
                ),
                ?boton,
              ],
            )
          : Row(
              children: [
                glifo,
                const SizedBox(width: 10),
                Expanded(child: textos),
                ?boton,
              ],
            ),
    );
  }
}
