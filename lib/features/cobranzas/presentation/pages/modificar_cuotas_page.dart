import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../../mapa/presentation/widgets/dialogos_modificar.dart'
    show confirmarDescartarLoEscrito;
import '../../../ventas/presentation/formato_venta.dart';
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/entities/cuota.dart';
import '../../domain/services/reparto_de_cuotas.dart';
import '../../domain/usecases/modificar_cuotas_use_case.dart';
import '../providers/cobranzas_providers.dart';
import '../textos_cuotas.dart';
import '../widgets/piezas_cuotas.dart';

/// «Modificar cuotas» (vista 30 A, HU-COB-004, artboard 30A-09): la colportora cambia el monto de las
/// cuotas que no están pagadas. Las pagadas se muestran y no cambian («Ya está pagada: no cambia.»).
/// Como al armar el plan, al cambiar una cuota las que siguen se reparten lo que queda («Se
/// ajustó»); ninguna supera lo que falta repartir ni baja de lo ya cobrado de ella. Al guardar se
/// reprograman las cobranzas de esas cuotas: cada cita se actualiza y sube con el resto.
///
/// - **Guardando**: el botón no admite otro toque. Si falla, conserva lo escrito y pasa a «Reintentar».
/// - **Sin cuotas abiertas** (todas pagadas): lo dice.
/// - Cargando, la venta ya no está y error de lectura, como la lista de cuotas.
///
/// Devuelve `true` si se guardaron cambios.
class ModificarCuotasPage extends ConsumerStatefulWidget {
  const ModificarCuotasPage({
    super.key,
    required this.ventaId,
    required this.espacioId,
    this.espacioPersonaId,
  });

  final String ventaId;
  final String espacioId;
  final String? espacioPersonaId;

  /// Abre la pantalla encima de la actual. `true` si se guardaron cambios.
  static Future<bool> abrir(
    BuildContext context, {
    required String ventaId,
    required String espacioId,
    String? espacioPersonaId,
  }) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ModificarCuotasPage(
          ventaId: ventaId,
          espacioId: espacioId,
          espacioPersonaId: espacioPersonaId,
        ),
      ),
    );
    return guardado ?? false;
  }

  @override
  ConsumerState<ModificarCuotasPage> createState() => _ModificarCuotasPageState();
}

class _ModificarCuotasPageState extends ConsumerState<ModificarCuotasPage> {
  final _scroll = ScrollController();

  /// Las cuotas abiertas con que se armó el formulario.
  var _abiertas = <Cuota>[];
  var _montos = <int>[];
  var _controladores = <TextEditingController>[];
  var _ajustadas = <int>{};
  var _problemas = <int, ProblemaDeCuota>{};
  var _porRepartir = 0;
  var _tocado = false;
  var _armado = false;

  var _enviando = false;
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

  void _armar(PlanDeCuotas plan) {
    for (final c in _controladores) {
      c.dispose();
    }
    _abiertas = plan.abiertas;
    _montos = [for (final c in _abiertas) c.montoCentavos];
    _controladores = [for (final m in _montos) TextEditingController(text: FormatoVenta.monto(m))];
    _porRepartir =
        plan.venta.saldoCentavos + _abiertas.fold<int>(0, (a, c) => a + c.pagadoCentavos);
    _ajustadas = {};
    _problemas = {};
    _armado = true;
  }

  void _alEditar(int indice, String texto) {
    if (_enviando) return;
    final monto = FormatoVenta.parsearMonto(texto) ?? 0;
    final r = RepartoDeCuotas.reajustar(
      montos: _montos,
      indice: indice,
      nuevoMonto: monto,
      saldo: _porRepartir,
      pagados: [for (final c in _abiertas) c.pagadoCentavos],
    );
    setState(() {
      _montos = r.montos;
      _ajustadas = r.ajustadas;
      _problemas = r.problemas;
      _tocado = true;
      _falla = null;
      for (var j = indice + 1; j < _controladores.length; j++) {
        _controladores[j].text = FormatoVenta.monto(_montos[j]);
      }
    });
  }

  bool get _hayCambios {
    for (var i = 0; i < _abiertas.length; i++) {
      if (_montos[i] != _abiertas[i].montoCentavos) return true;
    }
    return false;
  }

  bool _sePuedeGuardar() => !_enviando && _problemas.isEmpty && _hayCambios;

  Future<void> _guardar() async {
    if (!_sePuedeGuardar()) return;
    setState(() {
      _enviando = true;
      _falla = null;
    });
    try {
      final resultado = await ref.read(modificarCuotasUseCaseProvider)(
        ModificarCuotasParams(
          ventaId: widget.ventaId,
          montosPorCuota: {
            for (var i = 0; i < _abiertas.length; i++) _abiertas[i].agendaId: _montos[i],
          },
        ),
      );
      if (!mounted) return;
      resultado.fold((falla) {
        setState(() => _falla = falla);
        if (_scroll.hasClients && _scroll.offset != 0) _scroll.jumpTo(0);
      }, (_) => _cerrar(guardado: true));
    } on Object {
      if (mounted) setState(() => _falla = const FailureCuotasNoGuardadas(causa: 'excepcion'));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _cerrar({required bool guardado}) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(guardado);
  }

  Future<void> _atras() async {
    if (_enviando || _preguntando || _cerrando) return;
    if (_tocado && _hayCambios) {
      _preguntando = true;
      bool descartar;
      try {
        descartar = await confirmarDescartarLoEscrito(context);
      } finally {
        _preguntando = false;
      }
      if (!mounted || !descartar || _enviando) return;
    }
    _cerrar(guardado: false);
  }

  String? _persona() {
    final id = widget.espacioPersonaId;
    if (id == null) return null;
    final personas = ref.watch(personasDelEspacioProvider(widget.espacioId)).asData?.value;
    final p = personas?.where((x) => x.vinculo.id == id).firstOrNull;
    if (p == null) return null;
    final nombre = '${p.persona.nombre} ${p.persona.apellido}'.trim();
    return nombre.isEmpty ? null : nombre;
  }

  Widget _cabecera(String? subtitulo) => CabeceraVenta(
    eyebrow: TextosCuotas.eyebrowPlan,
    titulo: TextosCuotas.tituloModificar,
    subtitulo: subtitulo,
    cerrar: true,
    alVolver: _enviando ? null : () => unawaited(_atras()),
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
          key: const Key('cuotas_modificar_pagina'),
          cabecera: _cabecera(null),
          hijos: const [EsqueletoDeCuotas()],
        ),
        error: (_, _) => MarcoDeCuotas(
          key: const Key('cuotas_modificar_pagina'),
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
        data: (datos) {
          if (datos == null) {
            return MarcoDeCuotas(
              key: const Key('cuotas_modificar_pagina'),
              cabecera: _cabecera(null),
              hijos: const [
                AvisoDeVenta(key: Key('cuotas_sin_venta'), texto: TextosCuotas.ventaAusente),
              ],
            );
          }
          // Sin nada escrito, el formulario sigue al plan (un cobro que llega cambia lo pagado).
          final mismas =
              _armado &&
              _abiertas.length == datos.abiertas.length &&
              [
                for (var i = 0; i < _abiertas.length; i++) _abiertas[i] == datos.abiertas[i],
              ].every((x) => x);
          if (!_armado || (!_tocado && !mismas)) _armar(datos);
          return _formulario(datos);
        },
      ),
    );
  }

  Widget _formulario(PlanDeCuotas plan) {
    final subtitulo = TextosCuotas.subtituloPlan(_persona(), plan.venta.saldoCentavos);
    if (_abiertas.isEmpty) {
      return MarcoDeCuotas(
        key: const Key('cuotas_modificar_pagina'),
        cabecera: _cabecera(subtitulo),
        hijos: const [
          AvisoDeVenta(
            key: Key('cuotas_todas_pagadas'),
            error: false,
            texto: TextosCuotas.noHayCuotasAbiertas,
          ),
        ],
        cta: BotonDeVenta(texto: TextosCuotas.volver, alPresionar: () => _cerrar(guardado: false)),
      );
    }
    var abierta = 0;
    return MarcoDeCuotas(
      key: const Key('cuotas_modificar_pagina'),
      scroll: _scroll,
      cabecera: _cabecera(subtitulo),
      hijos: [
        if (_falla != null) ...[
          AvisoDeVenta(key: const Key('cuotas_error'), texto: _falla!.mensaje),
          const SizedBox(height: 11),
        ],
        const RotuloDeCuotas(TextosCuotas.cuotas),
        for (final cuota in plan.cuotas) ...[
          if (cuota.sePuedeModificar)
            Builder(
              builder: (_) {
                final i = abierta++;
                return FilaDeCuotaEditable(
                  key: Key('cuotas_fila_${cuota.numero}'),
                  rotulo: TextosCuotas.rotuloDeCuota(cuota.numero, cuota.fecha),
                  controlador: _controladores[i],
                  alCambiar: (t) => _alEditar(i, t),
                  ayuda: _ajustadas.contains(i) ? TextosCuotas.seAjusto : null,
                  error: _problemas[i] == null
                      ? null
                      : TextosCuotas.problema(_problemas[i]!, _porRepartir),
                  habilitado: !_enviando,
                );
              },
            )
          else
            FilaDeCuotaEditable(
              key: Key('cuotas_fila_${cuota.numero}'),
              rotulo: TextosCuotas.rotuloDeCuota(cuota.numero, cuota.fecha),
              valorFijo: FormatoVenta.monto(cuota.montoCentavos),
              ayuda: TextosCuotas.yaEstaPagada,
              cerrada: true,
            ),
          const SizedBox(height: 11),
        ],
        const Text(
          TextosCuotas.notaModificar,
          style: TextStyle(fontSize: 12.5, color: ColoresAgenda.gris),
        ),
      ],
      cta: BotonDeVenta(
        texto: _falla != null ? TextosCuotas.reintentar : TextosCuotas.guardarCuotas,
        textoOcupado: TextosCuotas.guardando,
        ocupado: _enviando,
        alPresionar: _sePuedeGuardar() ? () => unawaited(_guardar()) : null,
      ),
    );
  }
}
