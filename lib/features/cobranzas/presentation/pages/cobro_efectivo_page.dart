import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/presentation/flujo_agendar_visita.dart';
import '../../../agenda/presentation/formato_agendar_visita.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../mapa/domain/entities/persona_del_espacio.dart';
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../../mapa/presentation/textos_personas.dart' show FormatoPersonas;
import '../../../mapa/presentation/widgets/dialogos_modificar.dart'
    show confirmarDescartarLoEscrito;
import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../../../ventas/presentation/formato_venta.dart';
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/entities/venta_con_saldo.dart';
import '../../domain/usecases/registrar_cobro_efectivo_use_case.dart';
import '../providers/cobranzas_providers.dart';
import '../textos_cobro.dart';
import '../widgets/piezas_cobro.dart';

/// «Cobro en efectivo» (vista 28, HU-COB-001, artboards 28·01 a 28·09): la colportora registra lo que
/// le pagó el cliente de una venta —monto y fecha, por defecto hoy— y el saldo baja solo. Se abre ya
/// con la venta, la casa y la persona resueltas (contrato de navegación de la vista 39); no las
/// vuelve a pedir.
///
/// - **Monto vacío** (28·02): el botón está apagado y dice por qué.
/// - **Monto mayor al saldo** (28·03): el campo se marca con el saldo y el botón queda apagado. Se
///   rechaza, no hay saldo a favor (decisión del 23/10, P1 de #163).
/// - **Fecha de otro día** (28·04): una hoja con Hoy, Ayer, anteayer y «Otro día…», sin días antes de
///   la venta ni después de hoy.
/// - **Registrando** (28·05): el botón no admite otro toque y la pantalla no se cierra. El id del
///   cobro se genera una vez y se repite en los reintentos con los mismos datos: un doble toque o un
///   «Reintentar» no cobran dos veces.
/// - **Cobro parcial** (28·06) y **saldo en cero** (28·07): lo que quedó hecho y cómo sigue.
/// - **Error al guardar** (28·08): el formulario conserva lo escrito y el botón pasa a «Reintentar».
/// - **Sin conexión** (28·09): no hay estado propio. Todo es local y sube después.
///
/// Además lee la venta (cargando, ya no está, error de lectura) y, si ya no debe nada, lo dice.
///
/// Devuelve `true` si se registró un cobro, `false` si se cerró sin cobrar.
class CobroEfectivoPage extends ConsumerStatefulWidget {
  const CobroEfectivoPage({
    super.key,
    required this.ventaId,
    required this.colportorId,
    required this.espacioId,
    this.espacioPersonaId,
  });

  /// La venta que se cobra.
  final String ventaId;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  /// La casa o el depto de la venta.
  final String espacioId;

  /// El cliente, o `null` si la venta quedó sin persona.
  final String? espacioPersonaId;

  /// Abre la pantalla encima de la actual. `true` si se cobró.
  static Future<bool> abrir(
    BuildContext context, {
    required String ventaId,
    required String colportorId,
    required String espacioId,
    String? espacioPersonaId,
  }) async {
    final cobrado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CobroEfectivoPage(
          ventaId: ventaId,
          colportorId: colportorId,
          espacioId: espacioId,
          espacioPersonaId: espacioPersonaId,
        ),
      ),
    );
    return cobrado ?? false;
  }

  @override
  ConsumerState<CobroEfectivoPage> createState() => _CobroEfectivoPageState();
}

enum _Lectura { cargando, lista, ausente, conError }

class _CobroEfectivoPageState extends ConsumerState<CobroEfectivoPage> {
  final _monto = TextEditingController();
  final _scroll = ScrollController();

  var _lectura = _Lectura.cargando;
  VentaConSaldo? _venta;

  /// El día elegido para el cobro (sin hora, día de Montevideo); `null` = hoy.
  DateTime? _dia;

  /// Hay un guardado en curso: no admite otro toque, no deja salir y bloquea los campos.
  var _enviando = false;

  /// La última falla al guardar (28·08); `null` si no hay.
  Failure? _falla;

  /// La fecha no pasó la validación de quien guarda (28·04).
  var _fechaRechazada = false;

  /// El cobro registrado (28·06 y 28·07); `null` mientras se está cargando.
  CobroRegistrado? _registrado;

  /// Hay una hoja o una pantalla abierta desde acá: no admite otra encima.
  var _navegando = false;

  /// La pantalla se está cerrando: un segundo toque no vuelve a hacer `pop`.
  var _cerrando = false;

  /// El aviso «¿Descartar lo que escribiste?» está abierto: otro atrás no abre uno segundo.
  var _preguntando = false;

  /// El último intento de guardar: con los mismos datos se repite el id del cobro; con otros, es otro
  /// cobro.
  ({int montoCentavos, DateTime? dia, String id})? _intento;

  @override
  void initState() {
    super.initState();
    unawaited(_leerLaVenta());
  }

  @override
  void dispose() {
    _monto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  DateTime _ahora() => ref.read(relojCobroProvider)();

  /// Hoy, como fecha sin hora, en Montevideo.
  DateTime _hoy() => ReglasDeVenta.diaDeMontevideo(_ahora());

  DateTime get _diaElegido => _dia ?? _hoy();

  // --- Leer la venta -----------------------------------------------------------------------

  Future<void> _leerLaVenta({bool mostrarCarga = true}) async {
    if (mostrarCarga) setState(() => _lectura = _Lectura.cargando);
    try {
      final leida = await ref.read(cobranzaRepositoryProvider).ventaConSaldo(widget.ventaId);
      if (!mounted) return;
      leida.fold(
        (_) => _alNoPoderLeer(mostrarCarga),
        (venta) => setState(() {
          _venta = venta;
          _lectura = venta == null ? _Lectura.ausente : _Lectura.lista;
        }),
      );
    } on Object {
      if (mounted) _alNoPoderLeer(mostrarCarga);
    }
  }

  /// Sin poder leer la venta: si todavía no se había leído, el error de lectura con «Reintentar»; si
  /// ya se mostraba el formulario (se volvió a leer tras un rechazo), el aviso de «Reintentar».
  void _alNoPoderLeer(bool mostrarCarga) => setState(() {
    if (mostrarCarga || _venta == null) {
      _lectura = _Lectura.conError;
    } else {
      _falla = _generica;
    }
    _verElAviso();
  });

  // --- Lo que escribió ---------------------------------------------------------------------

  /// El monto escrito en centavos, o `null` si está vacío o no es un monto.
  int? get _centavos => FormatoVenta.parsearMonto(_monto.text);

  bool get _montoVacio => _monto.text.trim().isEmpty;

  /// Por qué el monto no sirve (28·03), o `null` si sirve o todavía no escribió nada.
  String? _errorDelMonto(VentaConSaldo venta) {
    if (_montoVacio) return null;
    final centavos = _centavos;
    if (centavos == null || centavos <= 0) return TextosCobro.montoInvalido;
    if (centavos > venta.saldoCentavos) {
      return TextosCobro.mayorAlSaldo(FormatoVenta.monto(venta.saldoCentavos));
    }
    return null;
  }

  bool _sePuedeRegistrar(VentaConSaldo venta) =>
      !_enviando && !_montoVacio && _centavos != null && _errorDelMonto(venta) == null;

  void _alEscribir(String _) => setState(() {
    // Lo escrito cambió: la falla de antes ya no habla de esto.
    _fechaRechazada = false;
  });

  // --- Fecha -------------------------------------------------------------------------------

  Future<void> _cambiarLaFecha(VentaConSaldo venta) async {
    if (_enviando || _navegando) return;
    _navegando = true;
    try {
      final elegido = await mostrarHojaFechaDelCobro(
        context,
        hoy: _hoy(),
        diaDeLaVenta: ReglasDeVenta.diaDeMontevideo(venta.fecha),
        elegido: _diaElegido,
      );
      if (elegido == null || !mounted) return;
      setState(() {
        _dia = _mismoDia(elegido, _hoy()) ? null : elegido;
        _fechaRechazada = false;
      });
    } finally {
      _navegando = false;
    }
  }

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // --- Registrar ---------------------------------------------------------------------------

  Future<void> _registrar() async {
    final venta = _venta;
    final centavos = _centavos;
    if (venta == null || centavos == null || !_sePuedeRegistrar(venta)) return;
    setState(() {
      _enviando = true;
      _falla = null;
      _fechaRechazada = false;
    });
    try {
      final dia = _dia;
      final previo = _intento;
      final id = previo != null && previo.montoCentavos == centavos && previo.dia == dia
          ? previo.id
          : ref.read(generadorIdCobroProvider)();
      _intento = (montoCentavos: centavos, dia: dia, id: id);
      final resultado = await ref.read(registrarCobroEfectivoUseCaseProvider)(
        RegistrarCobroEfectivoParams(
          cobroId: id,
          ventaId: venta.ventaId,
          montoCentavos: centavos,
          colportorId: widget.colportorId,
          fecha: dia == null ? null : FormatoCobro.alMediodia(dia),
        ),
      );
      if (!mounted) return;
      resultado.fold(_alFallar, _alRegistrar);
    } on Object {
      if (mounted) {
        setState(() => _falla = const FailureCobroNoGuardado(causa: 'excepcion'));
        _verElAviso();
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _alRegistrar(CobroRegistrado registrado) {
    // La confirmación empieza arriba, no donde estaba el formulario.
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _registrado = registrado);
  }

  /// El aviso de falla está arriba del formulario: con letra grande hay que subir para verlo.
  void _verElAviso() {
    if (!_scroll.hasClients || _scroll.offset == 0) return;
    unawaited(
      _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
    );
  }

  void _alFallar(Failure falla) {
    switch (falla) {
      case FailureCobroMayorAlSaldo():
        // El saldo cambió desde que se abrió (otro cobro): se lee de nuevo y el campo lo dice.
        unawaited(_leerLaVenta(mostrarCarga: false));
      case FailureCobroSinVenta():
        setState(() => _lectura = _Lectura.ausente);
      case FailureCobroFechaInvalida():
        setState(() => _fechaRechazada = true);
      case FailureCobroMontoInvalido():
        setState(() {});
      default:
        setState(() => _falla = falla is FailureCobroNoGuardado ? falla : _generica);
        _verElAviso();
    }
  }

  static const _generica = FailureCobroNoGuardado(causa: 'otra_falla');

  // --- Salir -------------------------------------------------------------------------------

  void _cerrar({required bool cobrado}) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(cobrado);
  }

  /// Hay algo escrito que se perdería al salir: un monto o un día distinto de hoy, antes de cobrar.
  bool get _hayLoEscrito => _registrado == null && (_monto.text.trim().isNotEmpty || _dia != null);

  Future<void> _atras() async {
    if (_enviando || _preguntando || _cerrando) return;
    if (_hayLoEscrito) {
      // Decisión de #439 (QA, P1): con algo escrito, «✕» y atrás preguntan; sin nada, cierran directo.
      _preguntando = true;
      bool descartar;
      try {
        descartar = await confirmarDescartarLoEscrito(context);
      } finally {
        _preguntando = false;
      }
      if (!mounted || !descartar || _enviando) return;
    }
    _cerrar(cobrado: _registrado != null);
  }

  Future<void> _agendarLaProxima() async {
    if (_navegando || _cerrando) return;
    _navegando = true;
    try {
      final agendada = await FlujoAgendarVisita.abrir(
        context,
        espacioId: widget.espacioId,
        espacioPersonaId: widget.espacioPersonaId,
        colportorId: widget.colportorId,
        tipo: TipoAgenda.cobranza,
      );
      if (agendada && mounted) _cerrar(cobrado: true);
    } finally {
      _navegando = false;
    }
  }

  // --- Dibujo ------------------------------------------------------------------------------

  /// «María Fernández · Mataojo 2044 · Depto 3B»: lo que se sepa de con quién y dónde.
  String? _subtitulo() {
    final partes = <String>[];
    final personaId = widget.espacioPersonaId;
    if (personaId != null) {
      final personas = ref.watch(personasDelEspacioProvider(widget.espacioId)).asData?.value;
      final persona = personas?.where((p) => p.vinculo.id == personaId).firstOrNull;
      final nombre = persona == null ? '' : _nombreDe(persona);
      if (nombre.isNotEmpty) partes.add(nombre);
    }
    final lugar = ref.watch(contextoEspacioProvider(widget.espacioId)).asData?.value;
    if (lugar != null) {
      partes.add(FormatoPersonas.dondeEstaElEspacio(lugar.espacio, lugar.ubicacion));
    }
    return partes.isEmpty ? null : partes.join(' · ');
  }

  static String _nombreDe(PersonaDelEspacio p) =>
      '${p.persona.nombre} ${p.persona.apellido}'.trim();

  @override
  Widget build(BuildContext context) {
    final subtitulo = _subtitulo();
    final venta = _venta;
    final Widget cuerpo;
    if (_registrado case final registrado?) {
      cuerpo = _exito(registrado, subtitulo);
    } else {
      cuerpo = switch (_lectura) {
        _Lectura.cargando => _marco(
          cabecera: _cabecera(subtitulo),
          hijos: const [EsqueletoDelCobro()],
        ),
        _Lectura.ausente => _marco(
          cabecera: _cabecera(subtitulo),
          hijos: const [AvisoDeVenta(key: Key('cobro_sin_venta'), texto: TextosCobro.sinLaVenta)],
          cta: _botonVolver(),
        ),
        _Lectura.conError => _marco(
          cabecera: _cabecera(subtitulo),
          hijos: [
            AvisoDeVenta(
              key: const Key('cobro_error_lectura'),
              texto: TextosCobro.errorDeLectura,
              textoAccion: TextosCobro.reintentar,
              alAccion: () => unawaited(_leerLaVenta()),
            ),
          ],
        ),
        _Lectura.lista when venta != null && !venta.tieneSaldo => _sinSaldo(venta, subtitulo),
        _Lectura.lista when venta != null => _formulario(venta, subtitulo),
        _ => _marco(cabecera: _cabecera(subtitulo), hijos: const [EsqueletoDelCobro()]),
      };
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) unawaited(_atras());
      },
      child: cuerpo,
    );
  }

  Widget _cabecera(
    String? subtitulo, {
    String titulo = TextosCobro.titulo,
    bool conSalida = true,
  }) => CabeceraVenta(
    eyebrow: TextosCobro.eyebrow,
    titulo: titulo,
    subtitulo: subtitulo,
    cerrar: true,
    alVolver: conSalida && !_enviando ? () => unawaited(_atras()) : null,
  );

  Widget _botonVolver() =>
      BotonDeVenta(texto: TextosCobro.volver, alPresionar: () => _cerrar(cobrado: false));

  Widget _marco({required Widget cabecera, required List<Widget> hijos, Widget? cta}) {
    return Scaffold(
      key: const Key('cobro_pagina'),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [cabecera, ...hijos],
              ),
            ),
            if (cta != null) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: cta),
          ],
        ),
      ),
    );
  }

  Widget _resumen(VentaConSaldo venta) => ResumenDeLaVenta(
    titulo: TextosCobro.ventaDel(venta.numeroTalonario, ReglasDeVenta.diaDeMontevideo(venta.fecha)),
    totalCentavos: venta.montoTotalCentavos,
    cobradoCentavos: venta.cobradoCentavos,
    saldoCentavos: venta.saldoCentavos,
  );

  /// 28·01 a 28·05, 28·08 y 28·09: el formulario.
  Widget _formulario(VentaConSaldo venta, String? subtitulo) {
    final errorDelMonto = _errorDelMonto(venta);
    final puede = _sePuedeRegistrar(venta);
    return _marco(
      cabecera: _cabecera(subtitulo),
      hijos: [
        if (_falla != null) ...[
          const AvisoDeVenta(key: Key('cobro_error'), texto: TextosCobro.errorAlGuardar),
          const SizedBox(height: 9),
        ],
        _resumen(venta),
        const SizedBox(height: 12),
        CampoDeVenta(
          key: const Key('cobro_monto'),
          rotulo: TextosCobro.monto,
          controlador: _monto,
          alCambiar: _alEscribir,
          hint: TextosCobro.montoHint,
          error: errorDelMonto,
          teclado: const TextInputType.numberWithOptions(decimal: true),
          maxLargo: 14,
          habilitado: !_enviando,
          autofocus: true,
        ),
        const SizedBox(height: 12),
        CampoDeFechaDelCobro(
          texto: FormatoCobro.dia(_diaElegido, _hoy()),
          alCambiar: _enviando ? null : () => unawaited(_cambiarLaFecha(venta)),
          error: _fechaRechazada
              ? TextosCobro.fechaFueraDeRango(
                  FormatoAgendarVisita.diaYMes(ReglasDeVenta.diaDeMontevideo(venta.fecha)),
                )
              : null,
        ),
      ],
      cta: BotonDeVenta(
        texto: _falla != null ? TextosCobro.reintentar : TextosCobro.registrarCobro,
        textoOcupado: TextosCobro.registrando,
        ocupado: _enviando,
        nota: _montoVacio && !_enviando ? TextosCobro.ingresaElMonto : null,
        alPresionar: puede ? () => unawaited(_registrar()) : null,
      ),
    );
  }

  /// La venta ya no debe nada (se cobró todo antes de entrar): no hay nada que cobrar.
  Widget _sinSaldo(VentaConSaldo venta, String? subtitulo) => _marco(
    cabecera: _cabecera(subtitulo),
    hijos: [
      const MarcaDeVentaPagada(titulo: TextosCobro.ventaPagada, texto: TextosCobro.sinSaldo),
      _resumen(venta),
    ],
    cta: _botonVolver(),
  );

  /// 28·06 y 28·07: el cobro quedó registrado.
  Widget _exito(CobroRegistrado registrado, String? subtitulo) {
    final venta = registrado.venta;
    if (registrado.ventaPagada) {
      return _marco(
        cabecera: _cabecera(subtitulo, titulo: TextosCobro.tituloRegistrado, conSalida: false),
        hijos: [
          const MarcaDeVentaPagada(titulo: TextosCobro.ventaPagada, texto: TextosCobro.saldoEnCero),
          _resumen(venta),
        ],
        cta: BotonDeVenta(
          key: const Key('cobro_volver_al_mapa'),
          texto: TextosCobro.volverAlMapa,
          alPresionar: () => _cerrar(cobrado: true),
        ),
      );
    }
    return _marco(
      cabecera: _cabecera(subtitulo, titulo: TextosCobro.tituloRegistrado, conSalida: false),
      hijos: [
        _resumen(venta),
        const SizedBox(height: 12),
        AvisoDeCobroHecho(
          texto: TextosCobro.sumamos(FormatoVenta.monto(registrado.cobranza.montoCentavos)),
        ),
      ],
      cta: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BotonDeVenta(
            texto: TextosCobro.agendarLaProxima,
            alPresionar: () => unawaited(_agendarLaProxima()),
          ),
          TextButton(
            key: const Key('cobro_listo'),
            onPressed: () => _cerrar(cobrado: true),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text(
              TextosCobro.listo,
              style: TextStyle(fontWeight: FontWeight.w600, color: ColoresAgenda.azul),
            ),
          ),
        ],
      ),
    );
  }
}
