import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../agenda/presentation/formato_agendar_visita.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../cobranzas/domain/entities/cobranza.dart' show TipoTarjeta;
import '../../../cobranzas/presentation/textos_cobro.dart';
import '../../../cobranzas/presentation/textos_medio_de_cobro.dart';
import '../../../cobranzas/presentation/widgets/piezas_cobro.dart';
import '../../../cobranzas/presentation/widgets/piezas_medio_de_cobro.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../../../ventas/presentation/formato_venta.dart';
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/services/captura_de_foto.dart';
import '../../domain/services/politica_de_compresion.dart';
import '../../domain/services/reglas_de_ticket.dart';
import '../../domain/usecases/registrar_ticket_use_case.dart';
import '../providers/tickets_providers.dart';
import '../textos_ticket.dart';
import '../widgets/piezas_ticket.dart';

/// Cómo terminó el flujo de la foto del ticket.
enum ResultadoDelFlujoDeTicket {
  /// El ticket quedó guardado en el teléfono («Listo»): el cobro sigue su camino de vuelta a la casa.
  cargado,

  /// Se salió sin cargarlo («Después» de la pantalla sin permiso): el ticket queda para más tarde.
  despues,

  /// Se cerró la cámara sin sacar nada: el colportor sigue en el cobro registrado.
  cancelado,
}

/// «Foto del ticket de tarjeta» (vista 29, grupo C, HU-COB-007, artboards 29C-01 a 29C-08) más el paso
/// «Datos del ticket» (campos de 38A-01, decisión P2 de #169).
///
/// Se abre después del cobro con tarjeta (29A·03) con el cobro ya resuelto; no vuelve a pedir persona
/// ni venta. Los pasos:
/// - **Cámara** (29C·01): «Sacar foto» (y «Elegir de la galería»). **Sin permiso** (29C·07): «Abrir
///   ajustes», galería o «Después».
/// - **Vista previa** (29C·02): «¿Se lee bien el ticket?». «Se lee bien, subir» sigue; «Probar con más
///   calidad» (si queda un nivel más alto dentro de los 2 MiB) o «Sacar otra» si no.
/// - **Datos del ticket**: monto, fecha, número de autorización (obligatorio), débito o crédito y marca,
///   precargados con lo que guardó el cobro. Un monto que no coincide con el del cobro avisa y no
///   bloquea.
/// - **Enviado**: se guarda todo en el teléfono (el id del ticket se genera una vez: un doble toque o un
///   reintento no cargan dos tickets) y la pantalla sigue el estado de la subida: subiendo (29C·03),
///   subido (29C·04, con «Borrar» la copia del teléfono, 29C·08), sin conexión en cola (29C·05) o con
///   error y «Reintentar ahora» (29C·06).
class TicketDeTarjetaPage extends ConsumerStatefulWidget {
  const TicketDeTarjetaPage({
    super.key,
    required this.cobroId,
    required this.colportorId,
    required this.montoDelCobroCentavos,
    required this.fechaDelCobro,
    this.tarjetaTipo,
    this.tarjetaMarca,
    this.numeroAprobacion,
    this.subtitulo,
  });

  /// El cobro con tarjeta al que pertenece el ticket.
  final String cobroId;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  final int montoDelCobroCentavos;
  final DateTime fechaDelCobro;
  final TipoTarjeta? tarjetaTipo;
  final String? tarjetaMarca;
  final String? numeroAprobacion;

  /// «María Fernández · Mataojo 2044 · 3B»: lo que se sepa de con quién y dónde.
  final String? subtitulo;

  @override
  ConsumerState<TicketDeTarjetaPage> createState() => _TicketDeTarjetaPageState();
}

enum _Paso { camara, preparando, sinPermiso, vistaPrevia, datos, enviado }

enum _Envio { subiendo, subido, enCola, error, rechazada }

class _TicketDeTarjetaPageState extends ConsumerState<TicketDeTarjetaPage> {
  final _scroll = ScrollController();
  final _monto = TextEditingController();
  final _autorizacion = TextEditingController();
  final _marcaOtra = TextEditingController();

  var _paso = _Paso.camara;

  /// El id del ticket: se genera una vez y se repite en los reintentos.
  late final String _ticketId;

  /// La foto tal como salió de la cámara y la que se va a subir (achicada).
  Uint8List? _original;
  FotoComprimida? _foto;

  /// Ya se probó con más calidad y no hay otro nivel que entre en 2 MiB.
  var _sinMasCalidad = false;

  /// Hay una captura, una compresión o un «más calidad» en curso: no admite otro toque.
  var _ocupado = false;

  /// Lo que pasó al sacar la foto (la cámara falló, la foto no sirve).
  String? _avisoDeCaptura;

  // --- Datos del ticket ---
  var _credito = false;
  String? _marca;
  DateTime? _dia;
  var _montoTocado = false;
  var _fechaRechazada = false;
  var _autorizacionRechazada = false;
  var _registrando = false;
  Failure? _falla;

  // --- Después de guardar ---
  var _reintentando = false;
  var _borrando = false;
  String? _avisoDeCopia;

  var _navegando = false;
  var _cerrando = false;

  @override
  void initState() {
    super.initState();
    _ticketId = ref.read(generadorIdTicketProvider)();
    _monto.text = FormatoVenta.montoParaEditar(widget.montoDelCobroCentavos);
    _autorizacion.text = String.fromCharCodes(
      (widget.numeroAprobacion ?? '').runes.take(ReglasDeTicket.largoMaximoTexto),
    );
    _credito = widget.tarjetaTipo == TipoTarjeta.credito;
    final marca = widget.tarjetaMarca;
    if (marca != null) {
      if (TextosMedioDeCobro.marcas.contains(marca)) {
        _marca = marca;
      } else {
        _marca = TextosMedioDeCobro.marcaOtra;
        if (marca != TextosMedioDeCobro.marcaOtra) {
          _marcaOtra.text = String.fromCharCodes(marca.runes.take(ReglasDeTicket.largoMaximoTexto));
        }
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _monto.dispose();
    _autorizacion.dispose();
    _marcaOtra.dispose();
    super.dispose();
  }

  DateTime _ahora() => ref.read(relojTicketProvider)();
  DateTime _hoy() => ReglasDeVenta.diaDeMontevideo(_ahora());
  DateTime get _diaDelCobro => ReglasDeVenta.diaDeMontevideo(widget.fechaDelCobro);
  DateTime get _diaElegido => _dia ?? _diaDelCobro;

  // --- Sacar la foto -----------------------------------------------------------------------

  Future<void> _capturar({required bool galeria}) async {
    if (_ocupado) return;
    final capturador = ref.read(capturadorDeFotoProvider);
    if (capturador == null) return;
    setState(() {
      _ocupado = true;
      _avisoDeCaptura = null;
    });
    try {
      final ResultadoDeCaptura resultado = galeria
          ? await capturador.elegirDeLaGaleria()
          : await capturador.sacarFoto();
      if (!mounted) return;
      switch (resultado) {
        case FotoCapturada(:final bytes):
          await _preparar(bytes);
        case CapturaCancelada():
          setState(() => _paso = _Paso.camara);
        case CapturaSinPermiso():
          setState(() => _paso = _Paso.sinPermiso);
        case CapturaFallida():
          setState(() {
            _paso = _Paso.camara;
            _avisoDeCaptura = galeria ? TextosTicket.galeriaFallo : TextosTicket.camaraFallo;
          });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _paso = _Paso.camara;
          _avisoDeCaptura = galeria ? TextosTicket.galeriaFallo : TextosTicket.camaraFallo;
        });
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Achica la foto y pasa a la vista previa; si no se puede, vuelve a la cámara con el aviso.
  Future<void> _preparar(Uint8List bytes) async {
    setState(() => _paso = _Paso.preparando);
    FotoComprimida? comprimida;
    try {
      comprimida = await ref.read(politicaDeCompresionProvider).comprimir(bytes);
    } on Object {
      comprimida = null;
    }
    if (!mounted) return;
    setState(() {
      if (comprimida == null) {
        _paso = _Paso.camara;
        _avisoDeCaptura = TextosTicket.fotoIlegible;
      } else {
        _original = bytes;
        _foto = comprimida;
        _sinMasCalidad = false;
        _paso = _Paso.vistaPrevia;
      }
    });
  }

  Future<void> _conMasCalidad() async {
    final original = _original;
    final actual = _foto;
    if (_ocupado || original == null || actual == null) return;
    setState(() => _ocupado = true);
    try {
      final mejor = await ref.read(politicaDeCompresionProvider).conMasCalidad(original, actual);
      if (!mounted) return;
      setState(() {
        if (mejor == null) {
          _sinMasCalidad = true;
        } else {
          _foto = mejor;
        }
      });
    } on Object {
      if (mounted) setState(() => _sinMasCalidad = true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _sacarOtra() {
    if (_ocupado) return;
    setState(() {
      _original = null;
      _foto = null;
      _avisoDeCaptura = null;
      _paso = _Paso.camara;
    });
  }

  Future<void> _abrirLosAjustes() async {
    if (_ocupado) return;
    final capturador = ref.read(capturadorDeFotoProvider);
    if (capturador == null) return;
    setState(() => _ocupado = true);
    try {
      await capturador.abrirLosAjustes();
    } on Object {
      // Sin ajustes que abrir, el colportor igual puede volver a intentarlo.
    } finally {
      if (mounted) {
        // Al volver de los ajustes la pantalla está lista para intentarlo otra vez.
        setState(() {
          _ocupado = false;
          _paso = _Paso.camara;
        });
      }
    }
  }

  // --- Datos del ticket --------------------------------------------------------------------

  int? get _centavos => FormatoVenta.parsearMonto(_monto.text);

  bool get _montoVacio => _monto.text.trim().isEmpty;

  bool get _montoValido {
    final c = _centavos;
    return c != null && ReglasDeTicket.montoValido(c);
  }

  bool get _hayAutorizacion => ReglasDeTicket.limpio(_autorizacion.text) != null;

  String? get _errorDelMonto {
    if (!_montoTocado) return null;
    if (_montoVacio) return TextosTicket.ingresaElMonto;
    return _montoValido ? null : TextosCobro.montoInvalido;
  }

  bool get _sePuedeEnviar => !_registrando && _montoValido && _hayAutorizacion;

  /// El aviso de que el monto no coincide con el del cobro (no bloquea).
  String? get _avisoDeMonto {
    final c = _centavos;
    if (c == null || !_montoValido) return null;
    if (!ReglasDeTicket.montoDistintoDelCobro(
      montoDelTicket: c,
      montoDelCobro: widget.montoDelCobroCentavos,
    )) {
      return null;
    }
    return TextosTicket.montoDistinto(
      FormatoVenta.monto(c),
      FormatoVenta.monto(widget.montoDelCobroCentavos),
    );
  }

  Future<void> _cambiarLaFecha() async {
    if (_registrando || _navegando) return;
    _navegando = true;
    try {
      final elegido = await mostrarHojaFechaDelCobro(
        context,
        hoy: _hoy(),
        // La HU solo pide que no sea futura; hasta un año atrás para no inventar otro límite.
        diaDeLaVenta: FormatoCobro.diasAntes(_hoy(), 365),
        elegido: _diaElegido,
        titulo: TextosTicket.hojaDeLaFecha,
        pista: TextosTicket.fechaPista,
      );
      if (elegido == null || !mounted) return;
      setState(() {
        _dia = FormatoAgendarVisita.mismoDia(elegido, _diaDelCobro) ? null : elegido;
        _fechaRechazada = false;
      });
    } finally {
      _navegando = false;
    }
  }

  ({TipoDeTarjeta tipo, String? marca}) _tarjeta() => (
    tipo: _credito ? TipoDeTarjeta.credito : TipoDeTarjeta.debito,
    marca: _marca == TextosMedioDeCobro.marcaOtra
        ? ReglasDeTicket.limpio(_marcaOtra.text) ?? TextosMedioDeCobro.marcaOtra
        : _marca,
  );

  Future<void> _enviar() async {
    final foto = _foto;
    final centavos = _centavos;
    if (foto == null || centavos == null || !_sePuedeEnviar) return;
    setState(() {
      _registrando = true;
      _falla = null;
      _fechaRechazada = false;
      _autorizacionRechazada = false;
    });
    try {
      final t = _tarjeta();
      final dia = _diaElegido;
      final resultado = await ref.read(registrarTicketUseCaseProvider)(
        RegistrarTicketParams(
          ticketId: _ticketId,
          colportorId: widget.colportorId,
          tipo: TipoDeTicket.cobroTarjeta,
          montoCentavos: centavos,
          foto: foto.bytes,
          tipoDeImagen: TipoDeImagen.jpeg,
          fecha: FormatoAgendarVisita.mismoDia(dia, _hoy()) ? null : _alMediodia(dia),
          numeroAutorizacion: _autorizacion.text,
          tarjetaTipo: t.tipo,
          tarjetaMarca: t.marca,
          cobroId: widget.cobroId,
        ),
      );
      if (!mounted) return;
      resultado.fold(_alFallar, (_) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
        setState(() => _paso = _Paso.enviado);
      });
    } on Object {
      if (mounted) {
        setState(() => _falla = const FailureTicketNoGuardado(causa: 'excepcion'));
        _verElAviso();
      }
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  /// El instante de un día pasado: el mediodía de Montevideo (UTC-3), así no cae en otro día.
  static DateTime _alMediodia(DateTime dia) => DateTime.utc(dia.year, dia.month, dia.day, 15);

  void _alFallar(Failure falla) {
    switch (falla) {
      case FailureTicketFechaInvalida():
        setState(() => _fechaRechazada = true);
      case FailureTicketSinAutorizacion():
        setState(() => _autorizacionRechazada = true);
      case FailureTicketMontoInvalido():
        setState(() => _montoTocado = true);
      case FailureTicketFotoInvalida():
        // La foto no entra en lo que acepta el servidor: se saca otra.
        setState(() {
          _original = null;
          _foto = null;
          _paso = _Paso.camara;
          _avisoDeCaptura = TextosTicket.fotoIlegible;
        });
      default:
        setState(() => _falla = falla);
        _verElAviso();
    }
  }

  /// El aviso está arriba del formulario: con letra grande hay que subir para verlo.
  void _verElAviso() {
    if (!_scroll.hasClients || _scroll.offset == 0) return;
    _scroll.jumpTo(0);
  }

  // --- Después de guardar ------------------------------------------------------------------

  Future<void> _reintentarAhora() async {
    if (_reintentando) return;
    setState(() => _reintentando = true);
    try {
      await ref.read(subirFotosDeTicketsUseCaseProvider)(const NoParams());
    } on Object {
      // La próxima pasada de la cola vuelve a intentarlo; el estado lo dice el ticket guardado.
    } finally {
      if (mounted) setState(() => _reintentando = false);
    }
  }

  Future<void> _borrarLaCopia() async {
    if (_borrando || _navegando) return;
    _navegando = true;
    try {
      final confirmo = await mostrarHojaBorrarCopia(context);
      if (confirmo != true || !mounted) return;
      setState(() {
        _borrando = true;
        _avisoDeCopia = null;
      });
      final resultado = await ref.read(borrarCopiaLocalDeTicketUseCaseProvider)(_ticketId);
      if (!mounted) return;
      resultado.fold(
        (falla) => setState(
          () => _avisoDeCopia = falla is FailureTicketCopiaSinSubir
              ? TextosTicket.copiaSinSubir
              : TextosTicket.noSePudoBorrar,
        ),
        (_) => setState(() {
          // La copia ya no está en el teléfono: tampoco se queda en la memoria de la pantalla.
          _original = null;
          _foto = null;
          _avisoDeCopia = TextosTicket.copiaBorrada;
        }),
      );
    } on Object {
      if (mounted) setState(() => _avisoDeCopia = TextosTicket.noSePudoBorrar);
    } finally {
      _navegando = false;
      if (mounted) setState(() => _borrando = false);
    }
  }

  // --- Salir -------------------------------------------------------------------------------

  void _cerrar(ResultadoDelFlujoDeTicket resultado) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(resultado);
  }

  void _atras() {
    if (_cerrando) return;
    switch (_paso) {
      case _Paso.camara:
      case _Paso.sinPermiso:
        if (_ocupado) return;
        _cerrar(ResultadoDelFlujoDeTicket.cancelado);
      case _Paso.preparando:
        return;
      case _Paso.vistaPrevia:
        _sacarOtra();
      case _Paso.datos:
        if (_registrando) return;
        setState(() => _paso = _Paso.vistaPrevia);
      case _Paso.enviado:
        _cerrar(ResultadoDelFlujoDeTicket.cargado);
    }
  }

  // --- Dibujo ------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Widget cuerpo = switch (_paso) {
      _Paso.camara => _camara(),
      _Paso.preparando => _marco(
        cabecera: _cabecera(TextosTicket.preparando, atras: false),
        hijos: const [CargandoDelTicket(texto: TextosTicket.preparando)],
      ),
      _Paso.sinPermiso => _sinPermiso(),
      _Paso.vistaPrevia => _vistaPrevia(),
      _Paso.datos => _datos(),
      _Paso.enviado => _enviado(),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _atras();
      },
      child: cuerpo,
    );
  }

  Widget _cabecera(String titulo, {bool atras = true, bool cerrar = false}) => CabeceraVenta(
    eyebrow: TextosTicket.eyebrow,
    titulo: titulo,
    subtitulo: widget.subtitulo,
    cerrar: cerrar,
    alVolver: atras ? _atras : null,
  );

  Widget _marco({required Widget cabecera, required List<Widget> hijos, Widget? cta}) {
    return Scaffold(
      key: const Key('ticket_pagina'),
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

  /// Un botón principal con botones de texto debajo.
  Widget _acciones(Widget principal, [List<Widget> debajo = const []]) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [principal, ...debajo],
  );

  // 29C-01
  Widget _camara() => _marco(
    cabecera: _cabecera(TextosTicket.sacarFotoDelTicket, cerrar: true),
    hijos: [
      if (_avisoDeCaptura != null) ...[
        AvisoDeVenta(key: const Key('ticket_aviso_captura'), texto: _avisoDeCaptura!),
        const SizedBox(height: 9),
      ],
      const MarcoDeEncuadre(),
    ],
    cta: _acciones(
      BotonDeVenta(
        key: const Key('ticket_sacar_foto'),
        texto: TextosTicket.sacarFoto,
        ocupado: _ocupado,
        alPresionar: () => unawaited(_capturar(galeria: false)),
      ),
      [
        BotonSecundarioDeTicket(
          key: const Key('ticket_galeria'),
          texto: TextosTicket.elegirDeLaGaleria,
          alPresionar: _ocupado ? null : () => unawaited(_capturar(galeria: true)),
        ),
      ],
    ),
  );

  // 29C-07
  Widget _sinPermiso() => _marco(
    cabecera: _cabecera(TextosTicket.sinCamaraTitulo, cerrar: true),
    hijos: const [
      Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(TextosTicket.sinCamara, style: TextStyle(fontSize: 15, height: 1.45)),
      ),
    ],
    cta: _acciones(
      BotonDeVenta(
        key: const Key('ticket_abrir_ajustes'),
        texto: TextosTicket.abrirAjustes,
        ocupado: _ocupado,
        alPresionar: () => unawaited(_abrirLosAjustes()),
      ),
      [
        BotonSecundarioDeTicket(
          key: const Key('ticket_galeria'),
          texto: TextosTicket.elegirDeLaGaleria,
          alPresionar: _ocupado ? null : () => unawaited(_capturar(galeria: true)),
        ),
        BotonSecundarioDeTicket(
          key: const Key('ticket_despues'),
          texto: TextosTicket.despues,
          alPresionar: _ocupado ? null : () => _cerrar(ResultadoDelFlujoDeTicket.despues),
        ),
      ],
    ),
  );

  // 29C-02
  Widget _vistaPrevia() {
    final foto = _foto;
    final puedeMasCalidad = foto != null && foto.indiceDelPaso > 0 && !_sinMasCalidad;
    return _marco(
      cabecera: _cabecera(TextosTicket.seLeeBien),
      hijos: [
        if (foto != null) FotoDelTicket(bytes: foto.bytes),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(
            TextosTicket.revisa,
            style: TextStyle(fontSize: 13, color: ColoresAgenda.gris, height: 1.4),
          ),
        ),
      ],
      cta: _acciones(
        BotonDeVenta(
          key: const Key('ticket_se_lee_bien'),
          texto: TextosTicket.seLeeBienSubir,
          alPresionar: _ocupado ? null : () => setState(() => _paso = _Paso.datos),
        ),
        [
          if (puedeMasCalidad)
            BotonSecundarioDeTicket(
              key: const Key('ticket_mas_calidad'),
              texto: TextosTicket.masCalidad,
              alPresionar: _ocupado ? null : () => unawaited(_conMasCalidad()),
            ),
          BotonSecundarioDeTicket(
            key: const Key('ticket_sacar_otra'),
            texto: TextosTicket.sacarOtra,
            alPresionar: _ocupado ? null : _sacarOtra,
          ),
        ],
      ),
    );
  }

  // Datos del ticket (campos de 38A-01)
  Widget _datos() {
    final foto = _foto;
    final montoError = _errorDelMonto;
    final avisoDeMonto = _avisoDeMonto;
    return _marco(
      cabecera: _cabecera(TextosTicket.datosTitulo, atras: !_registrando),
      hijos: [
        if (_falla != null) ...[
          AvisoDeVenta(key: const Key('ticket_error'), texto: _textoDeLaFalla(_falla!)),
          const SizedBox(height: 9),
        ],
        if (foto != null)
          FotoDelTicket(
            bytes: foto.bytes,
            alto: 120,
            alTocar: _registrando ? null : () => setState(() => _paso = _Paso.vistaPrevia),
          ),
        const SizedBox(height: 10),
        CampoDeVenta(
          key: const Key('ticket_monto'),
          rotulo: TextosTicket.monto,
          controlador: _monto,
          alCambiar: (_) => setState(() => _montoTocado = true),
          hint: TextosTicket.montoHint,
          error: montoError,
          teclado: const TextInputType.numberWithOptions(decimal: true),
          maxLargo: 14,
          habilitado: !_registrando,
        ),
        if (avisoDeMonto != null) ...[
          const SizedBox(height: 9),
          AvisoDeVenta(key: const Key('ticket_aviso_monto'), error: false, texto: avisoDeMonto),
        ],
        const SizedBox(height: 10),
        CampoDeFechaDelCobro(
          texto: FormatoCobro.dia(_diaElegido, _hoy()),
          alCambiar: _registrando ? null : () => unawaited(_cambiarLaFecha()),
          error: _fechaRechazada ? TextosTicket.fechaFutura : null,
        ),
        const SizedBox(height: 10),
        CampoDeVenta(
          key: const Key('ticket_autorizacion'),
          rotulo: TextosTicket.autorizacion,
          controlador: _autorizacion,
          alCambiar: (_) => setState(() => _autorizacionRechazada = false),
          hint: TextosTicket.autorizacionHint,
          error: _autorizacionRechazada ? TextosTicket.faltaLaAutorizacion : null,
          maxLargo: ReglasDeTicket.largoMaximoTexto,
          habilitado: !_registrando,
          autocorregir: false,
        ),
        const SizedBox(height: 10),
        _bloqueDeTarjeta(),
      ],
      cta: BotonDeVenta(
        key: const Key('ticket_enviar'),
        texto: _falla != null ? TextosTicket.reintentar : TextosTicket.enviarTicket,
        textoOcupado: TextosTicket.enviando,
        ocupado: _registrando,
        nota: _registrando
            ? null
            : !_montoValido
            ? TextosTicket.ingresaElMonto
            : !_hayAutorizacion
            ? TextosTicket.faltaLaAutorizacion
            : null,
        alPresionar: _sePuedeEnviar ? () => unawaited(_enviar()) : null,
      ),
    );
  }

  String _textoDeLaFalla(Failure falla) => switch (falla) {
    FailureTicketCobroInvalido() => TextosTicket.cobroConTicket,
    _ => TextosTicket.errorAlGuardar,
  };

  Widget _bloqueDeTarjeta() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SegmentadoDeCobro(
        rotulo: TextosTicket.tarjeta,
        etiqueta: TextosTicket.tipoDeTarjeta,
        opciones: const [TextosMedioDeCobro.debito, TextosMedioDeCobro.credito],
        elegida: _credito ? 1 : 0,
        alElegir: (i) => setState(() => _credito = i == 1),
        prefijoDeClave: 'ticket_tipo',
        habilitado: !_registrando,
      ),
      const SizedBox(height: 12),
      Semantics(
        container: true,
        explicitChildNodes: true,
        label: TextosTicket.marca,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child: Text(
                TextosTicket.marca,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10.5,
                  letterSpacing: 1.6,
                  color: ColoresAgenda.gris,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 8,
              children: [
                for (final texto in [...TextosMedioDeCobro.marcas, TextosMedioDeCobro.marcaOtra])
                  ChipDeVenta(
                    key: Key('ticket_marca_$texto'),
                    texto: texto,
                    elegido: _marca == texto,
                    // Tocar la marca elegida la quita: es opcional.
                    alPresionar: _registrando
                        ? () {}
                        : () => setState(() => _marca = _marca == texto ? null : texto),
                  ),
              ],
            ),
          ],
        ),
      ),
      if (_marca == TextosMedioDeCobro.marcaOtra) ...[
        const SizedBox(height: 4),
        CampoDeVenta(
          key: const Key('ticket_marca_otra'),
          rotulo: TextosTicket.marcaOtraRotulo,
          controlador: _marcaOtra,
          alCambiar: (_) => setState(() {}),
          hint: TextosTicket.marcaOtraHint,
          maxLargo: ReglasDeTicket.largoMaximoTexto,
          habilitado: !_registrando,
          autocorregir: false,
        ),
      ],
    ],
  );

  // Después de guardar: 29C-03, 04, 05 y 06
  Widget _enviado() {
    final observado = ref.watch(ticketObservadoProvider(_ticketId));
    final sinRed = ref.watch(conexionProvider).asData?.value == TipoConexion.sinConexion;
    return observado.when(
      loading: () => _marco(
        cabecera: _cabecera(TextosTicket.enColaTitulo, atras: false),
        hijos: const [CargandoDelTicket(texto: TextosTicket.cargandoElTicket)],
      ),
      error: (_, _) => _marco(
        cabecera: _cabecera(TextosTicket.enColaTitulo, atras: false),
        hijos: const [
          AvisoDeVenta(key: Key('ticket_error_lectura'), texto: TextosTicket.errorDeLectura),
        ],
        cta: _botonListo(),
      ),
      data: (registrado) {
        if (registrado == null) {
          return _marco(
            cabecera: _cabecera(TextosTicket.enColaTitulo, atras: false),
            hijos: const [CargandoDelTicket(texto: TextosTicket.cargandoElTicket)],
          );
        }
        return switch (_envioDe(registrado, sinRed: sinRed)) {
          _Envio.subiendo => _subiendo(),
          _Envio.subido => _subido(registrado),
          _Envio.enCola => _enCola(registrado),
          _Envio.error => _conError(),
          _Envio.rechazada => _rechazada(),
        };
      },
    );
  }

  static _Envio _envioDe(TicketRegistrado r, {required bool sinRed}) {
    if (r.foto.estado == EstadoDeSubida.subida || r.ticket.fotoSubida) return _Envio.subido;
    if (r.foto.estado == EstadoDeSubida.rechazada) return _Envio.rechazada;
    if (sinRed) return _Envio.enCola;
    if (r.foto.ultimoError != null) return _Envio.error;
    return _Envio.subiendo;
  }

  Widget _botonListo() => BotonDeVenta(
    key: const Key('ticket_listo'),
    texto: TextosTicket.listo,
    alPresionar: () => _cerrar(ResultadoDelFlujoDeTicket.cargado),
  );

  // 29C-03: sin «%», la subida no informa avance (pendiente del PR).
  Widget _subiendo() {
    final foto = _foto;
    return _marco(
      cabecera: _cabecera(TextosTicket.subiendoTitulo, atras: false),
      hijos: [if (foto != null) FotoDelTicket(bytes: foto.bytes)],
      cta: const BotonDeVenta(
        key: Key('ticket_subiendo'),
        texto: TextosTicket.subiendo,
        textoOcupado: TextosTicket.subiendo,
        ocupado: true,
        alPresionar: null,
      ),
    );
  }

  // 29C-04 y 29C-08
  Widget _subido(TicketRegistrado r) {
    final titulo = r.ticket.loRevisaAdministracion
        ? TextosTicket.loRevisaAdministracion
        : r.ticket.llegoAlServidor
        ? TextosTicket.subidoTuCoordinador
        : TextosTicket.ticketEnviado;
    return _marco(
      cabecera: _cabecera(TextosTicket.subidoTitulo, atras: false),
      hijos: [
        MensajeDeResultado(titulo: titulo, texto: TextosTicket.subidoAvisamos),
        if (r.foto.hayCopiaLocal)
          TarjetaDeTicket(
            titulo: TextosTicket.copiaEnElTelefono,
            detalle: TextosTicket.peso(r.foto.bytes),
            accion: TextosTicket.borrar,
            alAccion: _borrando ? null : () => unawaited(_borrarLaCopia()),
          ),
        if (_avisoDeCopia != null) ...[
          const SizedBox(height: 9),
          AvisoDeVenta(
            key: const Key('ticket_aviso_copia'),
            error: _avisoDeCopia != TextosTicket.copiaBorrada,
            texto: _avisoDeCopia!,
          ),
        ],
      ],
      cta: _botonListo(),
    );
  }

  // 29C-05
  Widget _enCola(TicketRegistrado r) {
    final dia = ReglasDeVenta.diaDeMontevideo(r.ticket.fecha);
    return _marco(
      cabecera: _cabecera(TextosTicket.enColaTitulo, atras: false),
      hijos: [
        const AvisoDeVenta(
          key: Key('ticket_sin_conexion'),
          error: false,
          texto: TextosTicket.sinConexion,
        ),
        const SizedBox(height: 12),
        TarjetaDeTicket(
          titulo: TextosTicket.ticketDel(
            FormatoAgendarVisita.diaYMes(dia),
            FormatoVenta.monto(r.ticket.montoCentavos),
          ),
          detalle: TextosTicket.esperandoConexion,
          etiqueta: TextosTicket.enCola,
        ),
      ],
      cta: _botonListo(),
    );
  }

  // 29C-06
  Widget _conError() {
    final foto = _foto;
    return _marco(
      cabecera: _cabecera(TextosTicket.noSePudoSubir, atras: false),
      hijos: [
        AvisoDeVenta(
          key: const Key('ticket_error_subida'),
          texto: TextosTicket.errorAlSubir,
          textoAccion: _reintentando ? TextosTicket.reintentando : TextosTicket.reintentarAhora,
          alAccion: _reintentando ? null : () => unawaited(_reintentarAhora()),
        ),
        const SizedBox(height: 12),
        if (foto != null) FotoDelTicket(bytes: foto.bytes),
      ],
      cta: _botonListo(),
    );
  }

  Widget _rechazada() => _marco(
    cabecera: _cabecera(TextosTicket.rechazadaTitulo, atras: false),
    hijos: const [AvisoDeVenta(key: Key('ticket_rechazada'), texto: TextosTicket.rechazada)],
    cta: _botonListo(),
  );
}
