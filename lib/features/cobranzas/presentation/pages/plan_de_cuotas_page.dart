import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../../mapa/presentation/textos_personas.dart' show FormatoPersonas;
import '../../../mapa/presentation/widgets/dialogos_modificar.dart'
    show confirmarDescartarLoEscrito;
import '../../../ventas/presentation/formato_venta.dart';
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/entities/cuota.dart';
import '../../domain/services/reparto_de_cuotas.dart';
import '../../domain/usecases/armar_plan_de_cuotas_use_case.dart';
import '../providers/cobranzas_providers.dart';
import '../textos_cuotas.dart';
import '../widgets/piezas_cuotas.dart';
import '../widgets/piezas_medio_de_cobro.dart' show SegmentadoDeCobro;
import 'cuotas_de_la_venta_page.dart';

/// «Pagar en cuotas» (vista 30 A, HU-COB-004, artboards 30A-01, 30A-02, 30A-02B, 30A-02C, 30A-03 y
/// 30A-08): desde la venta con saldo, la colportora arma el plan —cuántas cuotas, cada cuánto y la
/// primera fecha—, ve el monto de cada cuota y lo puede cambiar. Al crearlo se agenda una cobranza
/// por cuota, con recordatorio, y se abre la lista de cuotas («Plan creado. Agendamos 3 cobranzas.»).
///
/// Se abre ya con la venta, la casa y la persona resueltas (contrato de navegación de la vista 39);
/// no las vuelve a pedir. Las reglas del plan son las de «Reparto» (Cristian, 23/10):
///
/// - **De 2 a 12 cuotas**, semanales o mensuales, en partes iguales con la diferencia del redondeo en
///   la última (30A-01 y 30A-02).
/// - **Cambiar una cuota** (30A-02B): las anteriores no se tocan y las que siguen se reparten lo que
///   queda, marcadas «Se ajustó».
/// - **Una cuota mayor al saldo** (30A-02C) o sin monto: el campo se marca y el botón queda apagado.
/// - **La primera cuota en el pasado** (30A-03): se marca y el botón queda apagado.
/// - **Creando**: el botón no admite otro toque y la pantalla no se cierra. Los ids de las citas se
///   generan una vez y se repiten en los reintentos: un doble toque o un «Reintentar» no agendan dos
///   veces.
/// - **Error al crear** (30A-08): el formulario conserva lo escrito y el botón pasa a «Reintentar».
/// - **Sin conexión**: no hay estado propio. Todo es local y sube después.
///
/// Además lee el plan (cargando, la venta ya no está, error de lectura) y, si la venta ya no debe
/// nada o ya tiene cuotas por cobrar, lo dice. Devuelve `true` si se creó el plan.
class PlanDeCuotasPage extends ConsumerStatefulWidget {
  const PlanDeCuotasPage({
    super.key,
    required this.ventaId,
    required this.colportorId,
    required this.espacioId,
    this.espacioPersonaId,
    this.abrirLaLista = true,
  });

  final String ventaId;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  /// La casa o el depto de la venta.
  final String espacioId;

  /// El cliente, o `null` si la venta quedó sin persona.
  final String? espacioPersonaId;

  /// Al crear el plan, deja en su lugar la lista de cuotas (30A-04). Si se la abrió desde esa lista,
  /// no: la lista que está abajo ya se actualiza sola.
  final bool abrirLaLista;

  /// Abre la pantalla encima de la actual. `true` si se creó el plan.
  static Future<bool> abrir(
    BuildContext context, {
    required String ventaId,
    required String colportorId,
    required String espacioId,
    String? espacioPersonaId,
    bool abrirLaLista = true,
  }) async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PlanDeCuotasPage(
          ventaId: ventaId,
          colportorId: colportorId,
          espacioId: espacioId,
          espacioPersonaId: espacioPersonaId,
          abrirLaLista: abrirLaLista,
        ),
      ),
    );
    return creado ?? false;
  }

  @override
  ConsumerState<PlanDeCuotasPage> createState() => _PlanDeCuotasPageState();
}

class _PlanDeCuotasPageState extends ConsumerState<PlanDeCuotasPage> {
  final _scroll = ScrollController();

  var _cantidad = 3;
  var _frecuencia = FrecuenciaDeCuotas.semanal;
  DateTime? _primera;

  /// El saldo con el que se armó el reparto; `null` hasta leer la venta.
  int? _saldo;
  var _montos = <int>[];
  var _controladores = <TextEditingController>[];
  var _ajustadas = <int>{};
  var _problemas = <int, ProblemaDeCuota>{};

  /// Alguna vez cambió algo a mano: hay algo que se perdería al salir.
  var _tocado = false;

  /// Los ids de las citas, uno por cuota; se generan una vez y se repiten en los reintentos.
  final _ids = <String>[];

  var _enviando = false;
  var _navegando = false;
  var _cerrando = false;
  var _preguntando = false;
  Failure? _falla;

  @override
  void dispose() {
    for (final c in _controladores) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  DateTime _ahora() => ref.read(relojCobroProvider)();

  DateTime _hoy() {
    final a = _ahora();
    return DateTime(a.year, a.month, a.day);
  }

  DateTime get _diaDeLaPrimera => _primera ?? _hoy();

  /// Lo más que admite el servidor por venta (12) menos lo que la venta ya tiene.
  int _maximo(PlanDeCuotas plan) {
    final cabe = RepartoDeCuotas.maximo - plan.cuotas.length;
    return cabe.clamp(RepartoDeCuotas.minimo, RepartoDeCuotas.maximo);
  }

  // --- Reparto -----------------------------------------------------------------------------

  /// Arma el reparto en partes iguales de [saldo] entre [_cantidad] cuotas (y borra lo cambiado).
  void _repartir(int saldo) {
    _saldo = saldo;
    _montos = RepartoDeCuotas.partesIguales(saldo, _cantidad);
    for (final c in _controladores) {
      c.dispose();
    }
    _controladores = [for (final m in _montos) TextEditingController(text: FormatoVenta.monto(m))];
    _ajustadas = {};
    _problemas = {};
  }

  void _alCambiarLaCantidad(int cantidad) {
    if (_enviando || cantidad == _cantidad) return;
    setState(() {
      _cantidad = cantidad;
      _tocado = true;
      _falla = null;
      _repartir(_saldo ?? 0);
    });
  }

  void _alCambiarLaFrecuencia(FrecuenciaDeCuotas frecuencia) {
    if (_enviando || frecuencia == _frecuencia) return;
    setState(() {
      _frecuencia = frecuencia;
      _tocado = true;
      _falla = null;
    });
  }

  void _alEditar(int indice, String texto) {
    final saldo = _saldo;
    if (saldo == null || _enviando) return;
    final monto = FormatoVenta.parsearMonto(texto) ?? 0;
    final r = RepartoDeCuotas.reajustar(
      montos: _montos,
      indice: indice,
      nuevoMonto: monto,
      saldo: saldo,
    );
    setState(() {
      _montos = r.montos;
      _ajustadas = r.ajustadas;
      _problemas = r.problemas;
      _tocado = true;
      _falla = null;
      // Las que siguen muestran su monto nuevo; la que se está escribiendo no se toca.
      for (var j = indice + 1; j < _controladores.length; j++) {
        _controladores[j].text = FormatoVenta.monto(_montos[j]);
      }
    });
  }

  Future<void> _elegirLaFecha() async {
    if (_enviando || _navegando) return;
    _navegando = true;
    try {
      final hoy = _hoy();
      final elegido = await showDatePicker(
        context: context,
        initialDate: _diaDeLaPrimera,
        firstDate: DateTime(hoy.year - 1, hoy.month, hoy.day),
        lastDate: DateTime(hoy.year + 1, hoy.month, hoy.day),
        helpText: TextosCuotas.primeraCuota,
      );
      if (elegido == null || !mounted) return;
      setState(() {
        _primera = DateTime(elegido.year, elegido.month, elegido.day);
        _tocado = true;
        _falla = null;
      });
    } finally {
      _navegando = false;
    }
  }

  bool get _primeraEnElPasado => _diaDeLaPrimera.isBefore(_hoy());

  bool _sePuedeCrear() =>
      !_enviando &&
      !_primeraEnElPasado &&
      _problemas.isEmpty &&
      _saldo != null &&
      RepartoDeCuotas.montosValidos(_montos, _saldo!);

  // --- Crear -------------------------------------------------------------------------------

  Future<void> _crear() async {
    if (!_sePuedeCrear()) return;
    setState(() {
      _enviando = true;
      _falla = null;
    });
    try {
      final generar = ref.read(generadorIdCobroProvider);
      while (_ids.length < _montos.length) {
        _ids.add(generar());
      }
      final lugar = ref.read(contextoEspacioProvider(widget.espacioId)).asData?.value;
      final resultado = await ref.read(armarPlanDeCuotasUseCaseProvider)(
        ArmarPlanParams(
          ventaId: widget.ventaId,
          colportorId: widget.colportorId,
          frecuencia: _frecuencia,
          primeraCuota: _diaDeLaPrimera,
          montosCentavos: _montos,
          idsDeLasCitas: _ids.take(_montos.length).toList(),
          direccion: lugar == null
              ? ''
              : FormatoPersonas.dondeEstaElEspacio(lugar.espacio, lugar.ubicacion),
        ),
      );
      if (!mounted) return;
      resultado.fold(_alFallar, _alCrear);
    } on Object {
      if (mounted) {
        setState(() => _falla = const FailurePlanNoGuardado(causa: 'excepcion'));
        _verElAviso();
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _alCrear(PlanArmado armado) {
    if (_cerrando) return;
    _cerrando = true;
    if (!widget.abrirLaLista) {
      Navigator.of(context).pop(true);
      return;
    }
    // Vuelve a quien abrió el plan con `true`; en su lugar queda la lista de cuotas con su aviso.
    unawaited(
      Navigator.of(context).pushReplacement<bool, bool>(
        MaterialPageRoute(
          builder: (_) => CuotasDeLaVentaPage(
            ventaId: widget.ventaId,
            colportorId: widget.colportorId,
            espacioId: widget.espacioId,
            espacioPersonaId: widget.espacioPersonaId,
            avisoInicial: TextosCuotas.planCreado(armado.plan.cuotas.length),
          ),
        ),
        result: true,
      ),
    );
  }

  void _alFallar(Failure falla) {
    setState(() => _falla = falla);
    _verElAviso();
  }

  void _verElAviso() {
    if (!_scroll.hasClients || _scroll.offset == 0) return;
    _scroll.jumpTo(0);
  }

  // --- Salir -------------------------------------------------------------------------------

  void _cerrar({required bool creado}) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(creado);
  }

  Future<void> _atras() async {
    if (_enviando || _preguntando || _cerrando) return;
    if (_tocado) {
      _preguntando = true;
      bool descartar;
      try {
        descartar = await confirmarDescartarLoEscrito(context);
      } finally {
        _preguntando = false;
      }
      if (!mounted || !descartar || _enviando) return;
    }
    _cerrar(creado: false);
  }

  // --- Dibujo ------------------------------------------------------------------------------

  String? _persona() {
    final id = widget.espacioPersonaId;
    if (id == null) return null;
    final personas = ref.watch(personasDelEspacioProvider(widget.espacioId)).asData?.value;
    final p = personas?.where((x) => x.vinculo.id == id).firstOrNull;
    if (p == null) return null;
    final nombre = '${p.persona.nombre} ${p.persona.apellido}'.trim();
    return nombre.isEmpty ? null : nombre;
  }

  Widget _cabecera(String? subtitulo, {bool conSalida = true}) => CabeceraVenta(
    eyebrow: TextosCuotas.eyebrowPlan,
    titulo: TextosCuotas.tituloPlan,
    subtitulo: subtitulo,
    cerrar: true,
    alVolver: conSalida && !_enviando ? () => unawaited(_atras()) : null,
  );

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planDeLaVentaProvider(widget.ventaId));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (volvio, _) {
        if (!volvio) unawaited(_atras());
      },
      child: plan.when(
        loading: () => MarcoDeCuotas(
          key: const Key('cuotas_plan_pagina'),
          cabecera: _cabecera(null),
          hijos: const [EsqueletoDeCuotas()],
        ),
        error: (_, _) => MarcoDeCuotas(
          key: const Key('cuotas_plan_pagina'),
          cabecera: _cabecera(null),
          hijos: [
            AvisoDeVenta(
              key: const Key('cuotas_error_lectura'),
              texto: TextosCuotas.errorDeLectura,
              textoAccion: TextosCuotas.reintentar,
              alAccion: () => ref.invalidate(planDeLaVentaProvider(widget.ventaId)),
            ),
          ],
        ),
        data: (datos) => datos == null ? _ausente() : _contenido(datos),
      ),
    );
  }

  Widget _ausente() => MarcoDeCuotas(
    key: const Key('cuotas_plan_pagina'),
    cabecera: _cabecera(null),
    hijos: const [AvisoDeVenta(key: Key('cuotas_sin_venta'), texto: TextosCuotas.ventaAusente)],
    cta: BotonDeVenta(texto: TextosCuotas.volver, alPresionar: () => _cerrar(creado: false)),
  );

  Widget _contenido(PlanDeCuotas plan) {
    final subtitulo = TextosCuotas.subtituloPlan(_persona(), plan.venta.saldoCentavos);
    if (!plan.venta.tieneSaldo) {
      return MarcoDeCuotas(
        key: const Key('cuotas_plan_pagina'),
        cabecera: _cabecera(subtitulo),
        hijos: const [MarcaDeSinSaldo()],
        cta: BotonDeVenta(texto: TextosCuotas.volver, alPresionar: () => _cerrar(creado: false)),
      );
    }
    if (plan.tieneCuotasAbiertas) {
      // Ya hay cuotas por cobrar: se modifican desde la lista, no se arma otro plan.
      return MarcoDeCuotas(
        key: const Key('cuotas_plan_pagina'),
        cabecera: _cabecera(subtitulo),
        hijos: const [
          AvisoDeVenta(
            key: Key('cuotas_ya_armado'),
            error: false,
            texto: 'Esta venta ya tiene cuotas por cobrar. Modificalas desde la lista de cuotas.',
          ),
        ],
        cta: BotonDeVenta(
          texto: TextosCuotas.verLasCuotas,
          alPresionar: () => unawaited(
            Navigator.of(context).pushReplacement<bool, bool>(
              MaterialPageRoute(
                builder: (_) => CuotasDeLaVentaPage(
                  ventaId: widget.ventaId,
                  colportorId: widget.colportorId,
                  espacioId: widget.espacioId,
                  espacioPersonaId: widget.espacioPersonaId,
                ),
              ),
              result: false,
            ),
          ),
        ),
      );
    }
    // La primera lectura (o un cobro que cambió el saldo mientras no se había tocado nada) reparte.
    if (_saldo == null || (!_tocado && _saldo != plan.venta.saldoCentavos)) {
      _cantidad = _cantidad.clamp(RepartoDeCuotas.minimo, _maximo(plan));
      _repartir(plan.venta.saldoCentavos);
    }
    return _formulario(plan, subtitulo);
  }

  Widget _formulario(PlanDeCuotas plan, String? subtitulo) {
    final saldo = plan.venta.saldoCentavos;
    final fechas = RepartoDeCuotas.fechas(
      primera: _diaDeLaPrimera,
      cantidad: _cantidad,
      frecuencia: _frecuencia,
    );
    return MarcoDeCuotas(
      key: const Key('cuotas_plan_pagina'),
      scroll: _scroll,
      cabecera: _cabecera(subtitulo),
      hijos: [
        if (_falla != null) ...[
          AvisoDeVenta(
            key: const Key('cuotas_error'),
            texto: _falla is FailurePlanNoGuardado ? TextosCuotas.errorAlCrear : _falla!.mensaje,
          ),
          const SizedBox(height: 11),
        ],
        ContadorDeCuotas(
          cantidad: _cantidad,
          minimo: RepartoDeCuotas.minimo,
          maximo: _maximo(plan),
          alCambiar: _alCambiarLaCantidad,
          habilitado: !_enviando,
        ),
        const SizedBox(height: 11),
        SegmentadoDeCobro(
          rotulo: TextosCuotas.cadaCuanto,
          etiqueta: TextosCuotas.cadaCuanto,
          opciones: const [TextosCuotas.semanal, TextosCuotas.mensual],
          elegida: _frecuencia.index,
          alElegir: (i) => _alCambiarLaFrecuencia(FrecuenciaDeCuotas.values[i]),
          prefijoDeClave: 'cuotas_frecuencia',
          habilitado: !_enviando,
        ),
        const SizedBox(height: 11),
        CampoDeDiaDeCuota(
          rotulo: TextosCuotas.primeraCuota,
          texto: TextosCuotas.diaDeLaPrimera(_diaDeLaPrimera),
          alTocar: _enviando ? null : () => unawaited(_elegirLaFecha()),
          error: _primeraEnElPasado ? TextosCuotas.primeraEnElPasado : null,
        ),
        const SizedBox(height: 11),
        const RotuloDeCuotas(TextosCuotas.cuotasRotulo),
        for (var i = 0; i < _cantidad; i++) ...[
          FilaDeCuotaEditable(
            key: Key('cuotas_fila_$i'),
            rotulo: TextosCuotas.rotuloDeCuota(i + 1, fechas[i]),
            controlador: _controladores[i],
            alCambiar: (t) => _alEditar(i, t),
            ayuda: _ajustadas.contains(i) ? TextosCuotas.seAjusto : null,
            error: _problemas[i] == null ? null : TextosCuotas.problema(_problemas[i]!, saldo),
            habilitado: !_enviando,
          ),
          const SizedBox(height: 11),
        ],
        const Text(
          TextosCuotas.seAgendan,
          style: TextStyle(fontSize: 12.5, color: ColoresAgenda.gris),
        ),
      ],
      cta: BotonDeVenta(
        texto: _falla != null ? TextosCuotas.reintentar : TextosCuotas.crearPlan,
        textoOcupado: TextosCuotas.creando,
        ocupado: _enviando,
        alPresionar: _sePuedeCrear() ? () => unawaited(_crear()) : null,
      ),
    );
  }
}
