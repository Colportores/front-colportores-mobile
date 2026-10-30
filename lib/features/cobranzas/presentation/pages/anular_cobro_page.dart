import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../mapa/presentation/widgets/dialogos_modificar.dart'
    show confirmarDescartarLoEscrito;
import '../../../ventas/presentation/formato_venta.dart';
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/entities/cobranza.dart';
import '../../domain/entities/detalle_del_cobro.dart';
import '../../domain/usecases/anular_cobro_use_case.dart';
import '../../domain/usecases/registrar_cobro_use_case.dart';
import '../providers/cobranzas_providers.dart';
import '../textos_anular_cobro.dart';
import '../widgets/piezas_anular_cobro.dart';

/// Cómo se cerró «Anular cobro» cuando algo cambió: el detalle vuelve a leer el cobro.
enum SalidaDeAnular {
  /// El cobro quedó anulado (30B-05).
  anulada,

  /// No se anuló porque algo ya no es como se vio: pasaron las 72 h (30B-06) o el cobro ya no está.
  recargar,
}

/// «Anular cobro» (vista 30 B, HU-COB-006, artboards 30B-02, 30B-03, 30B-04 y 30B-08): la colportora
/// elige por qué anula un cobro que registró por error, confirma dos veces y el saldo de la venta
/// vuelve a lo que era. Se abre desde [DetalleDelCobroPage] con el cobro ya leído.
///
/// - **Motivo sin elegir** (30B-02): el botón está apagado y dice por qué. La lista es la del canvas
///   (decisión del orquestador, 23/10, precedente #226): «Monto equivocado», «Cliente equivocado», «Lo
///   registré dos veces» y «Otro».
/// - **«Otro»** (30B-03): pide «Contanos qué pasó», obligatorio. Ese texto queda en el teléfono (en el
///   `audit_log` local), no sube (decisión de Cristian, 23/10, «Anulación»).
/// - **Segunda confirmación** (30B-04): una hoja con lo que va a pasar y «Sí, anular» / «No, volver».
/// - **Anulando**: el botón no admite otro toque y la pantalla no se cierra.
/// - **Error al anular** (30B-08): el cobro sigue como estaba, lo elegido queda y el botón pasa a
///   «Reintentar».
/// - **Sin conexión**: no hay estado propio. Se anula en el teléfono y sube después.
///
/// Devuelve cómo se cerró ([SalidaDeAnular]) o `null` si se canceló sin anular nada.
class AnularCobroPage extends ConsumerStatefulWidget {
  const AnularCobroPage({super.key, required this.detalle, required this.colportorId});

  final DetalleDelCobro detalle;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  static Future<SalidaDeAnular?> abrir(
    BuildContext context, {
    required DetalleDelCobro detalle,
    required String colportorId,
  }) => Navigator.of(context).push<SalidaDeAnular>(
    MaterialPageRoute(
      builder: (_) => AnularCobroPage(detalle: detalle, colportorId: colportorId),
    ),
  );

  @override
  ConsumerState<AnularCobroPage> createState() => _AnularCobroPageState();
}

class _AnularCobroPageState extends ConsumerState<AnularCobroPage> {
  final _otro = TextEditingController();
  final _scroll = ScrollController();
  final _claveDelAviso = GlobalKey();

  MotivoDeAnulacion? _motivo;

  /// Hay una anulación en curso: no admite otro toque, no deja salir y bloquea los campos.
  var _enviando = false;

  /// La última falla al anular (30B-08); `null` si no hay.
  Failure? _falla;

  /// La hoja de la segunda confirmación está abierta: no admite otra encima.
  var _confirmando = false;

  /// La pantalla se está cerrando: un segundo toque no vuelve a hacer `pop`.
  var _cerrando = false;

  /// El aviso «¿Descartar lo que escribiste?» está abierto.
  var _preguntando = false;

  @override
  void dispose() {
    _otro.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _pideTexto => _motivo == MotivoDeAnulacion.otro;

  bool get _hayTexto => RegistrarCobroUseCase.limpiar(_otro.text) != null;

  bool get _sePuedeAnular => !_enviando && _motivo != null && (!_pideTexto || _hayTexto);

  String? get _nota {
    if (_enviando) return null;
    if (_motivo == null) return TextosAnularCobro.eligeElMotivo;
    if (_pideTexto && !_hayTexto) return TextosAnularCobro.cuentanosParaSeguir;
    return null;
  }

  void _elegir(MotivoDeAnulacion motivo) {
    if (_enviando || motivo == _motivo) return;
    setState(() {
      _motivo = motivo;
      // Lo elegido cambió: la falla de antes ya no habla de esto y se vuelve a confirmar.
      _falla = null;
    });
  }

  // --- Anular -----------------------------------------------------------------------------

  Future<void> _alPresionar() async {
    if (!_sePuedeAnular || _confirmando || _cerrando) return;
    if (_falla != null) {
      // «Reintentar»: ya confirmó, no se le vuelve a preguntar.
      await _anular();
      return;
    }
    _confirmando = true;
    bool confirmo;
    try {
      final d = widget.detalle;
      confirmo = await mostrarHojaConfirmarAnulacion(
        context,
        titulo: TextosAnularCobro.confirmarTitulo(FormatoVenta.monto(d.cobranza.montoCentavos)),
        texto: TextosAnularCobro.confirmarTexto(
          FormatoVenta.monto(FormatoAnulacion.saldoSinElCobro(d)),
          FormatoVenta.monto(d.cobranza.montoCentavos),
          d.cobranza.medio,
        ),
      );
    } finally {
      _confirmando = false;
    }
    if (!confirmo || !mounted) return;
    await _anular();
  }

  Future<void> _anular() async {
    if (_enviando || _cerrando || !_sePuedeAnular) return;
    setState(() {
      _enviando = true;
      _falla = null;
    });
    try {
      final resultado = await ref.read(anularCobroUseCaseProvider)(
        AnularCobroParams(
          cobranzaId: widget.detalle.cobranza.id,
          colportorId: widget.colportorId,
          motivo: _motivo,
          justificacion: _pideTexto ? _otro.text : null,
        ),
      );
      if (!mounted) return;
      resultado.fold(_alFallar, (_) => _cerrar(SalidaDeAnular.anulada));
    } on Object {
      if (mounted) _fallo(const FailureCobroNoAnulado(causa: 'excepcion'));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _alFallar(Failure falla) {
    switch (falla) {
      case FailureAnulacionFueraDePlazo() || FailureCobroAusente():
        // Lo que se vio ya no es así: el detalle lo vuelve a leer y lo dice (30B-06).
        _cerrar(SalidaDeAnular.recargar);
      default:
        _fallo(falla);
    }
  }

  void _fallo(Failure falla) {
    setState(() => _falla = falla);
    // El aviso está debajo de las opciones: con letra grande hay que bajar para verlo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _claveDelAviso.currentContext;
      if (contexto != null && contexto.mounted) {
        unawaited(Scrollable.ensureVisible(contexto, duration: Duration.zero));
      }
    });
  }

  // --- Salir ------------------------------------------------------------------------------

  void _cerrar(SalidaDeAnular? salida) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(salida);
  }

  Future<void> _atras() async {
    if (_enviando || _preguntando || _confirmando || _cerrando) return;
    if (_pideTexto && _hayTexto) {
      _preguntando = true;
      bool descartar;
      try {
        descartar = await confirmarDescartarLoEscrito(context);
      } finally {
        _preguntando = false;
      }
      if (!mounted || !descartar || _enviando) return;
    }
    _cerrar(null);
  }

  // --- Dibujo -----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final d = widget.detalle;
    final c = d.cobranza;
    final ahora = ref.read(relojCobroProvider)();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) unawaited(_atras());
      },
      child: Scaffold(
        key: const Key('anular_cobro_pagina'),
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    CabeceraVenta(
                      eyebrow: TextosAnularCobro.eyebrowAnular,
                      titulo: TextosAnularCobro.tituloAnular,
                      subtitulo: TextosAnularCobro.subtituloAnular(
                        FormatoVenta.monto(c.montoCentavos),
                        TextosAnularCobro.fechaEnLaLinea(c.fecha, ahora),
                        d.cliente,
                      ),
                      cerrar: true,
                      alVolver: _enviando ? null : () => unawaited(_atras()),
                    ),
                    const RotuloDeSeccion(TextosAnularCobro.motivo),
                    const SizedBox(height: 6),
                    for (final m in MotivoDeAnulacion.values)
                      Padding(
                        key: Key('anular_cobro_motivo_${m.name}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FilaElegible(
                          titulo: TextosAnularCobro.motivoDe(m),
                          elegida: m == _motivo,
                          alPresionar: () => _elegir(m),
                        ),
                      ),
                    if (_pideTexto) ...[
                      const SizedBox(height: 4),
                      CampoDeVenta(
                        key: const Key('anular_cobro_otro'),
                        rotulo: TextosAnularCobro.contanosQuePaso,
                        controlador: _otro,
                        alCambiar: (_) => setState(() => _falla = null),
                        hint: TextosAnularCobro.contanosHint,
                        maxLargo: AnularCobroUseCase.maximoJustificacion,
                        lineas: 3,
                        habilitado: !_enviando,
                        autofocus: true,
                      ),
                    ],
                    if (_falla != null) ...[
                      const SizedBox(height: 8),
                      KeyedSubtree(
                        key: _claveDelAviso,
                        child: const AvisoDeVenta(
                          key: Key('anular_cobro_error'),
                          texto: TextosAnularCobro.errorAlAnular,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: BotonDeVenta(
                  texto: _falla != null
                      ? TextosAnularCobro.reintentar
                      : TextosAnularCobro.anularCobro,
                  textoOcupado: TextosAnularCobro.anulando,
                  ocupado: _enviando,
                  peligro: _motivo != null,
                  nota: _nota,
                  alPresionar: _sePuedeAnular ? () => unawaited(_alPresionar()) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
