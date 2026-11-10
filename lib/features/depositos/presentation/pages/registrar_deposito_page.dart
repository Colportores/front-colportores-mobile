import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../cobranzas/presentation/textos_cobro.dart' show FormatoCobro;
import '../../../cobranzas/presentation/widgets/piezas_cobro.dart'
    show AvisoDeCobroHecho, CampoDeFechaDelCobro;
import '../../../cobranzas/presentation/widgets/piezas_medio_de_cobro.dart' show SegmentadoDeCobro;
import '../../../cuenta/presentation/providers/cuenta_providers.dart';
import '../../../mapa/presentation/widgets/dialogos_modificar.dart'
    show confirmarDescartarLoEscrito;
import '../../../tickets/domain/services/captura_de_foto.dart';
import '../../../tickets/presentation/providers/tickets_providers.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../../../ventas/presentation/formato_venta.dart';
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/entities/deposito.dart';
import '../../domain/usecases/registrar_deposito_con_ticket_use_case.dart';
import '../providers/depositos_providers.dart';
import '../textos_deposito.dart';
import '../widgets/aviso_tickets_sin_subir.dart';
import '../widgets/piezas_deposito.dart';

/// «Registrar depósito» (vista 33 D, HU-CTA-004, #443): el colportor carga cuánto depositó, para qué
/// (casa editora o alquiler), dónde (banco, oficina o retiro por el coordinador) y cuándo, y el
/// efectivo pasa de «en mano» a «por validar».
///
/// - **Un solo paso con el ticket** (decisión «Paso ticket», 23/10): en el banco o en la oficina se
///   saca la foto del ticket acá mismo (las piezas de 38A) y el ticket y el depósito se guardan juntos;
///   el retiro por el coordinador no lleva foto. No hay «Cargar el ticket» después.
/// - **Sin elegir cobros** (decisión «Cobro en dep.», 28/10): solo el monto.
/// - **Más de lo que tiene en mano** (33D-02): el campo lo dice y el botón queda apagado, solo en la
///   pantalla (el caso de uso no compara contra «en mano», QA de #593).
/// - **Registrando** (33D-03): el botón no admite otro toque y la pantalla no se cierra. Los ids del
///   depósito y del ticket se generan una vez y se repiten en los reintentos con los mismos datos: un
///   doble toque o un «Reintentar» no registran dos veces.
/// - **Registrado** (33D-04): cuánto queda en mano y cuánto espera la validación (decisión «Acredita
///   V1»: no suma a «Depositado» hasta que el coordinador lo valide).
/// - **Error** (33D-05): el formulario conserva lo cargado y el botón pasa a «Reintentar».
/// - **Sin conexión** (33D-06): se registra igual en el teléfono y sube cuando vuelve la red.
///
/// Devuelve `true` si se registró un depósito.
class RegistrarDepositoPage extends ConsumerStatefulWidget {
  const RegistrarDepositoPage({super.key, required this.colportorId});

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  /// Abre la pantalla encima de la actual. `true` si se registró un depósito.
  static Future<bool> abrir(BuildContext context, {required String colportorId}) async {
    final registrado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RegistrarDepositoPage(colportorId: colportorId)),
    );
    return registrado ?? false;
  }

  @override
  ConsumerState<RegistrarDepositoPage> createState() => _RegistrarDepositoPageState();
}

/// Lo que se muestra en 33D-04: el depósito y cómo quedaron «en mano» y «por validar».
typedef _Registrado = ({
  Deposito deposito,
  int? enManoAntes,
  int? porValidarAntes,
  bool sinConexion,
});

class _RegistrarDepositoPageState extends ConsumerState<RegistrarDepositoPage> {
  final _monto = TextEditingController();
  final _referencia = TextEditingController();
  final _scroll = ScrollController();

  var _concepto = ConceptoDeDeposito.casaEditora;
  var _destino = DestinoDeDeposito.banco;

  /// El día elegido (sin hora, día de Montevideo); `null` = hoy.
  DateTime? _dia;

  /// La foto del ticket ya achicada; `null` si todavía no hay.
  Uint8List? _foto;
  var _preparandoFoto = false;
  String? _errorDeFoto;

  /// Lo que estaba «por validar» al abrir la pantalla (para 33D-04); `null` si no se pudo leer.
  int? _porValidarAntes;

  var _enviando = false;
  Failure? _falla;
  var _fechaRechazada = false;

  /// Se tocó «Registrar» con algo faltante: lo que falta se marca en rojo.
  var _intentoIncompleto = false;

  _Registrado? _registrado;

  var _navegando = false;
  var _cerrando = false;
  var _preguntando = false;

  /// El último intento: con los mismos datos se repiten los ids; con otros, es otro depósito.
  ({String datos, String depositoId, String ticketId})? _intento;

  @override
  void initState() {
    super.initState();
    unawaited(_leerLoPorValidar());
  }

  @override
  void dispose() {
    _monto.dispose();
    _referencia.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _leerLoPorValidar() async {
    try {
      final totales = await ref.read(depositoRepositoryProvider).totales();
      if (!mounted) return;
      totales.fold((_) {}, (t) => _porValidarAntes = t.porValidarCentavos);
    } on Object {
      // Sin la base no hay «antes»: 33D-04 muestra solo lo que sabe.
    }
  }

  DateTime _ahora() => ref.read(relojDepositoProvider)();

  /// Hoy, como fecha sin hora, en Montevideo.
  DateTime _hoy() => ReglasDeVenta.diaDeMontevideo(_ahora().toUtc());

  DateTime get _diaElegido => _dia ?? _hoy();

  // --- Lo que hay ----------------------------------------------------------------------------

  // Lo que viene de afuera, leído en cada `build` (los toques usan lo último que se dibujó).

  /// «En mano» del colportor, si ya se calculó.
  int? _enMano;

  /// La campaña del alquiler: `AsyncData(null)` si no está en ninguna en curso.
  AsyncValue<String?> _campania = const AsyncLoading();

  /// Hay cámara y galería para la foto del ticket.
  var _fotoDisponible = false;

  var _sinConexion = false;

  void _leerLoDeAfuera() {
    _enMano = ref
        .watch(resumenDeCuentaProvider(widget.colportorId))
        .asData
        ?.value
        .enMano
        .totalCentavos;
    _campania = ref.watch(campaniaDelAlquilerProvider(widget.colportorId));
    _fotoDisponible = ref.watch(fotoDelTicketDisponibleProvider);
    _sinConexion = ref.watch(conexionProvider).value == TipoConexion.sinConexion;
  }

  int? get _centavos => FormatoVenta.parsearMonto(_monto.text);

  bool get _montoVacio => _monto.text.trim().isEmpty;

  bool get _faltaLaFoto => _destino.llevaTicket && _foto == null;

  /// Por qué el monto no sirve (33D-02 si pasa lo que tiene en mano), o `null`.
  String? _errorDelMonto(int? enMano) {
    if (_montoVacio) return null;
    final centavos = _centavos;
    if (centavos == null || centavos <= 0) return TextosDeposito.montoInvalido;
    if (enMano != null && centavos > enMano) return TextosDeposito.tenesEnMano(enMano);
    return null;
  }

  /// Algo que no depende de lo escrito impide registrar: alquiler sin campaña en curso (o sin saber
  /// todavía cuál es), o banco/oficina en un teléfono sin cámara.
  bool _bloqueado() {
    if (_concepto == ConceptoDeDeposito.alquiler) {
      final campania = _campania;
      if (!campania.hasValue || campania.value == null) return true;
    }
    return _destino.llevaTicket && !_fotoDisponible;
  }

  bool _sePuedeRegistrar(int? enMano) =>
      !_enviando &&
      !_preparandoFoto &&
      !_montoVacio &&
      _centavos != null &&
      _errorDelMonto(enMano) == null &&
      !_faltaLaFoto &&
      !_bloqueado();

  /// La nota bajo el botón apagado (38A-04): qué falta.
  String? _nota() {
    if (_enviando) return null;
    if (_montoVacio && _faltaLaFoto && _fotoDisponible) return TextosDeposito.faltanFotoYMonto;
    if (_montoVacio) return TextosDeposito.faltaElMonto;
    if (_faltaLaFoto && _fotoDisponible) return TextosDeposito.faltaLaFoto;
    return null;
  }

  void _alEscribir(String _) => setState(() => _fechaRechazada = false);

  void _elegirConcepto(int i) {
    if (_enviando) return;
    setState(() => _concepto = ConceptoDeDeposito.values[i]);
  }

  void _elegirDestino(int i) {
    if (_enviando) return;
    setState(() {
      _destino = DestinoDeDeposito.values[i];
      _errorDeFoto = null;
    });
  }

  // --- La foto -------------------------------------------------------------------------------

  Future<void> _cargarLaFoto() async {
    final capturador = ref.read(capturadorDeFotoProvider);
    if (capturador == null || _enviando || _navegando || _preparandoFoto) return;
    _navegando = true;
    try {
      final origen = await mostrarHojaOrigenDeLaFoto(context);
      if (origen == null || !mounted) return;
      final resultado = switch (origen) {
        OrigenDeLaFoto.camara => await capturador.sacarFoto(),
        OrigenDeLaFoto.galeria => await capturador.elegirDeLaGaleria(),
      };
      if (!mounted) return;
      switch (resultado) {
        case FotoCapturada(:final bytes):
          await _prepararLaFoto(bytes);
        case CapturaCancelada():
          break;
        case CapturaSinPermiso():
          setState(() => _errorDeFoto = TextosDeposito.sinPermisoDeCamara);
        case CapturaFallida():
          setState(() => _errorDeFoto = TextosDeposito.capturaFallida);
      }
    } finally {
      _navegando = false;
    }
  }

  /// Achica la foto con la política del ticket (S42). Si no se puede leer, la de antes sigue.
  Future<void> _prepararLaFoto(Uint8List original) async {
    setState(() {
      _preparandoFoto = true;
      _errorDeFoto = null;
    });
    try {
      final comprimida = await ref.read(politicaDeCompresionProvider).comprimir(original);
      if (!mounted) return;
      setState(() {
        if (comprimida == null) {
          _errorDeFoto = TextosDeposito.fotoIlegible;
        } else {
          _foto = comprimida.bytes;
        }
      });
    } on Object {
      if (mounted) setState(() => _errorDeFoto = TextosDeposito.fotoIlegible);
    } finally {
      if (mounted) setState(() => _preparandoFoto = false);
    }
  }

  // --- Fecha ---------------------------------------------------------------------------------

  Future<void> _cambiarLaFecha() async {
    if (_enviando || _navegando) return;
    _navegando = true;
    try {
      final hoy = _hoy();
      final elegido = await showDatePicker(
        context: context,
        initialDate: _diaElegido,
        firstDate: DateTime(hoy.year - 1, hoy.month, hoy.day),
        lastDate: hoy,
        helpText: TextosDeposito.cuandoDepositaste,
      );
      if (elegido == null || !mounted) return;
      final dia = DateTime(elegido.year, elegido.month, elegido.day);
      setState(() {
        _dia = _mismoDia(dia, _hoy()) ? null : dia;
        _fechaRechazada = false;
      });
    } finally {
      _navegando = false;
    }
  }

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // --- Registrar -----------------------------------------------------------------------------

  /// Toca «Registrar depósito» con el botón apagado por algo que falta: lo marca, no hace nada más.
  void _marcarLoQueFalta() {
    if (_enviando) return;
    setState(() => _intentoIncompleto = true);
  }

  Future<void> _registrar() async {
    final enMano = _enMano;
    final centavos = _centavos;
    if (centavos == null || !_sePuedeRegistrar(enMano)) return;
    final campaniaId = _concepto == ConceptoDeDeposito.alquiler ? _campania.value : null;
    final foto = _destino.llevaTicket ? _foto : null;
    final referencia = _destino.llevaTicket ? _referencia.text.trim() : '';
    final sinConexion = _sinConexion;
    final porValidarAntes = _porValidarAntes;
    setState(() {
      _enviando = true;
      _falla = null;
      _fechaRechazada = false;
    });
    try {
      final dia = _dia;
      final datos = [
        centavos,
        dia?.toIso8601String(),
        _destino.name,
        _concepto.name,
        campaniaId,
        foto == null ? null : identityHashCode(foto),
        referencia,
      ].join('|');
      final previo = _intento;
      final ids = previo != null && previo.datos == datos
          ? (depositoId: previo.depositoId, ticketId: previo.ticketId)
          : (
              depositoId: ref.read(generadorIdDepositoProvider)(),
              ticketId: ref.read(generadorIdTicketProvider)(),
            );
      _intento = (datos: datos, depositoId: ids.depositoId, ticketId: ids.ticketId);
      final resultado = await ref.read(registrarDepositoConTicketUseCaseProvider)(
        RegistrarDepositoConTicketParams(
          depositoId: ids.depositoId,
          ticketId: ids.ticketId,
          colportorId: widget.colportorId,
          montoCentavos: centavos,
          destino: _destino,
          concepto: _concepto,
          fecha: dia == null ? null : FormatoCobro.alMediodia(dia),
          campaniaId: campaniaId,
          foto: foto,
          referencia: referencia.isEmpty ? null : referencia,
        ),
      );
      if (!mounted) return;
      resultado.fold(
        _alFallar,
        (ok) => _alRegistrar((
          deposito: ok.deposito,
          enManoAntes: enMano,
          porValidarAntes: porValidarAntes,
          sinConexion: sinConexion,
        )),
      );
    } on Object {
      if (mounted) {
        setState(() => _falla = const FailureDepositoNoGuardado(causa: 'excepcion'));
        _verElAviso();
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _alRegistrar(_Registrado registrado) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _registrado = registrado);
  }

  void _alFallar(Failure falla) {
    if (falla is FailureDepositoFechaInvalida) {
      setState(() => _fechaRechazada = true);
      return;
    }
    setState(() => _falla = falla);
    _verElAviso();
  }

  /// El aviso de falla está arriba: con letra grande hay que subir para verlo (y que el lector lo
  /// anuncie, QA #164).
  void _verElAviso() {
    if (!_scroll.hasClients || _scroll.offset == 0) return;
    _scroll.jumpTo(0);
  }

  // --- Salir ---------------------------------------------------------------------------------

  void _cerrar() {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(_registrado != null);
  }

  bool get _hayLoEscrito =>
      _registrado == null &&
      (_monto.text.trim().isNotEmpty ||
          _referencia.text.trim().isNotEmpty ||
          _dia != null ||
          _foto != null);

  Future<void> _atras() async {
    if (_enviando || _preguntando || _cerrando) return;
    if (_hayLoEscrito) {
      _preguntando = true;
      bool descartar;
      try {
        descartar = await confirmarDescartarLoEscrito(context);
      } finally {
        _preguntando = false;
      }
      if (!mounted || !descartar || _enviando) return;
    }
    _cerrar();
  }

  // --- Dibujo --------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _leerLoDeAfuera();
    final registrado = _registrado;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) unawaited(_atras());
      },
      child: registrado == null ? _formulario() : _exito(registrado),
    );
  }

  Widget _marco({required Widget cabecera, required List<Widget> hijos, required Widget cta}) {
    return Scaffold(
      key: const Key('deposito_pagina'),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                key: const Key('deposito_lista'),
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [cabecera, ...hijos],
              ),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: cta),
          ],
        ),
      ),
    );
  }

  /// 33D-01, 02, 03, 05 y 06.
  Widget _formulario() {
    final enMano = _enMano;
    final errorDelMonto = _errorDelMonto(enMano);
    final puede = _sePuedeRegistrar(enMano);
    final campania = _campania;
    final alquilerSinCampania =
        _concepto == ConceptoDeDeposito.alquiler && campania.hasValue && campania.value == null;
    final nota = _nota();
    return _marco(
      cabecera: CabeceraVenta(
        eyebrow: TextosDeposito.eyebrow,
        titulo: TextosDeposito.titulo,
        subtitulo: enMano == null ? null : TextosDeposito.enMano(enMano),
        cerrar: true,
        alVolver: _enviando ? null : () => unawaited(_atras()),
      ),
      hijos: [
        if (_falla case final falla?) ...[
          AvisoDeVenta(key: const Key('deposito_error'), texto: falla.mensaje),
          const SizedBox(height: 9),
        ] else if (_sinConexion) ...[
          const AvisoDeVenta(
            key: Key('deposito_sin_conexion'),
            error: false,
            texto: TextosDeposito.sinConexion,
          ),
          const SizedBox(height: 9),
        ],
        // 38A-08: un ticket de un depósito anterior no pudo subir su foto.
        const AvisoDeTicketsSinSubir(margen: EdgeInsets.only(bottom: 9)),
        const SizedBox(height: 4),
        CampoDeVenta(
          key: const Key('deposito_monto'),
          rotulo: TextosDeposito.monto,
          controlador: _monto,
          alCambiar: _alEscribir,
          hint: TextosDeposito.montoHint,
          error:
              errorDelMonto ??
              (_intentoIncompleto && _montoVacio ? TextosDeposito.faltaElMonto : null),
          teclado: const TextInputType.numberWithOptions(decimal: true),
          maxLargo: 14,
          habilitado: !_enviando,
          autofocus: true,
        ),
        const SizedBox(height: 12),
        SegmentadoDeCobro(
          rotulo: TextosDeposito.paraQue,
          etiqueta: TextosDeposito.paraQueEtiqueta,
          opciones: const [TextosDeposito.casaEditora, TextosDeposito.alquiler],
          elegida: _concepto.index,
          alElegir: _elegirConcepto,
          prefijoDeClave: 'deposito_concepto',
          habilitado: !_enviando,
        ),
        if (alquilerSinCampania)
          const AyudaDeDeposito(
            key: Key('deposito_sin_campania'),
            texto: TextosDeposito.sinCampaniaParaElAlquiler,
            error: true,
          ),
        const SizedBox(height: 12),
        SegmentadoDeCobro(
          rotulo: TextosDeposito.donde,
          etiqueta: TextosDeposito.dondeEtiqueta,
          opciones: const [TextosDeposito.banco, TextosDeposito.oficina, TextosDeposito.retiro],
          elegida: _destino.index,
          alElegir: _elegirDestino,
          prefijoDeClave: 'deposito_destino',
          habilitado: !_enviando,
        ),
        const SizedBox(height: 12),
        ..._ticket(),
        CampoDeFechaDelCobro(
          texto: FormatoCobro.dia(_diaElegido, _hoy()),
          alCambiar: _enviando ? null : () => unawaited(_cambiarLaFecha()),
          error: _fechaRechazada ? const FailureDepositoFechaInvalida().mensaje : null,
        ),
      ],
      // Apagado por algo que falta, el toque marca qué falta (38A-04) en vez de no hacer nada.
      cta: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: puede || _enviando ? null : _marcarLoQueFalta,
        child: BotonDeVenta(
          key: const Key('deposito_cta'),
          texto: _falla != null ? TextosDeposito.reintentar : TextosDeposito.registrar,
          textoOcupado: TextosDeposito.registrando,
          ocupado: _enviando,
          nota: nota,
          alPresionar: puede ? () => unawaited(_registrar()) : null,
        ),
      ),
    );
  }

  /// La foto del ticket y el número de operación (banco u oficina), o la línea del retiro.
  List<Widget> _ticket() {
    if (!_destino.llevaTicket) {
      return const [
        AyudaDeDeposito(key: Key('deposito_retiro_sin_foto'), texto: TextosDeposito.retiroSinFoto),
        SizedBox(height: 12),
      ];
    }
    if (!_fotoDisponible) {
      return const [
        AyudaDeDeposito(
          key: Key('deposito_sin_camara'),
          texto: TextosDeposito.sinCamara,
          error: true,
        ),
        SizedBox(height: 12),
      ];
    }
    return [
      FotoDelTicketDeDeposito(
        foto: _foto,
        preparando: _preparandoFoto,
        error: _errorDeFoto,
        marcarFalta: _intentoIncompleto,
        alTocar: _enviando || _preparandoFoto ? null : () => unawaited(_cargarLaFoto()),
      ),
      const SizedBox(height: 12),
      CampoDeVenta(
        key: const Key('deposito_referencia'),
        rotulo: TextosDeposito.referencia,
        controlador: _referencia,
        alCambiar: _alEscribir,
        hint: TextosDeposito.referenciaHint,
        maxLargo: 40,
        habilitado: !_enviando,
      ),
      const SizedBox(height: 12),
    ];
  }

  /// 33D-04.
  Widget _exito(_Registrado r) {
    final monto = r.deposito.montoCentavos;
    final enManoAntes = r.enManoAntes;
    final porValidarAntes = r.porValidarAntes;
    final filas = [
      if (enManoAntes != null)
        FilaAntesYDespues(
          key: const Key('deposito_fila_en_mano'),
          rotulo: TextosDeposito.filaEnMano,
          antes: enManoAntes,
          despues: enManoAntes - monto < 0 ? 0 : enManoAntes - monto,
        ),
      if (porValidarAntes != null)
        FilaAntesYDespues(
          key: const Key('deposito_fila_por_validar'),
          rotulo: TextosDeposito.filaPorValidar,
          antes: porValidarAntes,
          despues: porValidarAntes + monto,
        ),
    ];
    return _marco(
      cabecera: const CabeceraVenta(
        eyebrow: TextosDeposito.eyebrow,
        titulo: TextosDeposito.tituloRegistrado,
      ),
      hijos: [
        const SizedBox(height: 4),
        if (filas.isNotEmpty) ...[CuadroAntesYDespues(filas: filas), const SizedBox(height: 12)],
        AvisoDeCobroHecho(
          texto: r.deposito.destino.llevaTicket
              ? TextosDeposito.quedaPorValidarTicket
              : TextosDeposito.quedaPorValidarRetiro,
        ),
        if (r.sinConexion) ...[
          const SizedBox(height: 9),
          const AvisoDeVenta(
            key: Key('deposito_se_envia_al_volver'),
            error: false,
            texto: TextosDeposito.seEnviaAlVolver,
          ),
        ],
      ],
      cta: BotonDeVenta(
        key: const Key('deposito_listo'),
        texto: TextosDeposito.listo,
        alPresionar: _cerrar,
      ),
    );
  }
}
