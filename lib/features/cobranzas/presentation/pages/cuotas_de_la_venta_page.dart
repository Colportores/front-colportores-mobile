import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/presentation/flujo_agendar_visita.dart';
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/entities/cuota.dart';
import '../../domain/services/reparto_de_cuotas.dart';
import '../providers/cobranzas_providers.dart';
import '../textos_cobro.dart';
import '../textos_cuotas.dart';
import '../widgets/piezas_cobro.dart' show AvisoDeCobroHecho, ResumenDeLaVenta;
import '../widgets/piezas_cuotas.dart';
import 'modificar_cuotas_page.dart';
import 'plan_de_cuotas_page.dart';

/// «Cuotas» de una venta (vista 30 A, HU-COB-004, artboards 30A-04, 30A-06 y 30A-07): las cuotas del
/// plan, cada una pagada, parcial, agendada o vencida, al día después de cada cobro.
///
/// - **Con plan** (30A-04): el resumen de la venta, «PLAN · 3 CUOTAS SEMANALES» y una tarjeta por
///   cuota. Si se llega recién creado el plan, lo dice («Plan creado. Agendamos 3 cobranzas.»).
///   «Modificar cuotas» abre 30A-09 mientras quede alguna sin pagar.
/// - **Cuota vencida** (30A-06): un aviso con «Agendar cobranza», que abre «Agendar una visita» ya
///   de cobranza.
/// - **Sin saldo** (30A-07): no hay plan que armar; lo dice.
/// - **Sin plan, con saldo** (A confirmar): los pagos son libres; ofrece «Pagar en cuotas».
/// - **Cargando** y **error al leer**: el patrón de la vista 32 (32B-06 y 32B-07); «Reintentar» vuelve
///   a leer.
///
/// Devuelve `true` si se armó o se modificó el plan mientras estuvo abierta.
class CuotasDeLaVentaPage extends ConsumerStatefulWidget {
  const CuotasDeLaVentaPage({
    super.key,
    required this.ventaId,
    required this.colportorId,
    required this.espacioId,
    this.espacioPersonaId,
    this.avisoInicial,
  });

  final String ventaId;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  /// La casa o el depto de la venta.
  final String espacioId;

  /// El cliente, o `null` si la venta quedó sin persona.
  final String? espacioPersonaId;

  /// El aviso verde de arriba («Plan creado. Agendamos 3 cobranzas.»), si se llega recién creado.
  final String? avisoInicial;

  /// Abre la pantalla encima de la actual. `true` si se armó o se modificó el plan.
  static Future<bool> abrir(
    BuildContext context, {
    required String ventaId,
    required String colportorId,
    required String espacioId,
    String? espacioPersonaId,
  }) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CuotasDeLaVentaPage(
          ventaId: ventaId,
          colportorId: colportorId,
          espacioId: espacioId,
          espacioPersonaId: espacioPersonaId,
        ),
      ),
    );
    return cambio ?? false;
  }

  @override
  ConsumerState<CuotasDeLaVentaPage> createState() => _CuotasDeLaVentaPageState();
}

class _CuotasDeLaVentaPageState extends ConsumerState<CuotasDeLaVentaPage> {
  late String? _aviso = widget.avisoInicial;

  /// Se armó o se modificó el plan desde esta pantalla (lo que devuelve al cerrarla).
  late var _cambio = widget.avisoInicial != null;
  var _navegando = false;
  var _cerrando = false;

  void _cerrar() {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(_cambio);
  }

  Future<void> _pagarEnCuotas() async {
    if (_navegando) return;
    _navegando = true;
    try {
      final creado = await PlanDeCuotasPage.abrir(
        context,
        ventaId: widget.ventaId,
        colportorId: widget.colportorId,
        espacioId: widget.espacioId,
        espacioPersonaId: widget.espacioPersonaId,
        abrirLaLista: false,
      );
      if (!mounted || !creado) return;
      final plan = ref.read(planDeLaVentaProvider(widget.ventaId)).asData?.value;
      setState(() {
        _cambio = true;
        _aviso = TextosCuotas.planCreado(plan?.cuotas.length ?? 0);
      });
    } finally {
      _navegando = false;
    }
  }

  Future<void> _modificar() async {
    if (_navegando) return;
    _navegando = true;
    try {
      final guardado = await ModificarCuotasPage.abrir(
        context,
        ventaId: widget.ventaId,
        espacioId: widget.espacioId,
        espacioPersonaId: widget.espacioPersonaId,
      );
      if (mounted && guardado) setState(() => _cambio = true);
    } finally {
      _navegando = false;
    }
  }

  Future<void> _agendarCobranza() async {
    if (_navegando) return;
    _navegando = true;
    try {
      await FlujoAgendarVisita.abrir(
        context,
        espacioId: widget.espacioId,
        espacioPersonaId: widget.espacioPersonaId,
        colportorId: widget.colportorId,
        tipo: TipoAgenda.cobranza,
      );
    } finally {
      _navegando = false;
    }
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

  Widget _cabecera(String eyebrow, {String? subtitulo}) => CabeceraVenta(
    eyebrow: eyebrow,
    titulo: TextosCuotas.tituloCuotas,
    subtitulo: subtitulo,
    alVolver: _cerrar,
  );

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planDeLaVentaProvider(widget.ventaId));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (volvio, _) {
        if (!volvio) _cerrar();
      },
      child: plan.when(
        loading: () => MarcoDeCuotas(
          key: const Key('cuotas_lista_pagina'),
          cabecera: _cabecera(TextosCuotas.eyebrowPlan),
          hijos: const [EsqueletoDeCuotas()],
        ),
        error: (_, _) => MarcoDeCuotas(
          key: const Key('cuotas_lista_pagina'),
          cabecera: _cabecera(TextosCuotas.eyebrowPlan),
          hijos: [
            AvisoDeVenta(
              key: const Key('cuotas_error_lectura'),
              texto: TextosCuotas.errorDeLectura,
              textoAccion: TextosCuotas.reintentar,
              alAccion: () => ref.invalidate(planDeLaVentaProvider(widget.ventaId)),
            ),
          ],
        ),
        data: (datos) => datos == null
            ? MarcoDeCuotas(
                key: const Key('cuotas_lista_pagina'),
                cabecera: _cabecera(TextosCuotas.eyebrowPlan),
                hijos: const [
                  AvisoDeVenta(key: Key('cuotas_sin_venta'), texto: TextosCuotas.ventaAusente),
                ],
              )
            : _lista(datos),
      ),
    );
  }

  Widget _lista(PlanDeCuotas plan) {
    final venta = plan.venta;
    final ahora = ref.read(relojCobroProvider)();
    final primeraVencida = plan.abiertas
        .where((c) => c.situacion(ahora) == SituacionDeCuota.vencida)
        .firstOrNull;
    return MarcoDeCuotas(
      key: const Key('cuotas_lista_pagina'),
      cabecera: _cabecera(TextosCuotas.eyebrowVenta(venta.numeroTalonario), subtitulo: _persona()),
      hijos: [
        if (_aviso != null) ...[AvisoDeCobroHecho(texto: _aviso!), const SizedBox(height: 9)],
        if (primeraVencida != null) ...[
          AvisoDeVenta(
            key: const Key('cuotas_aviso_vencida'),
            error: false,
            texto: TextosCuotas.vencio(primeraVencida),
            textoAccion: TextosCuotas.agendarCobranza,
            alAccion: () => unawaited(_agendarCobranza()),
          ),
          const SizedBox(height: 9),
        ],
        ResumenDeLaVenta(
          titulo: TextosCobro.ventaDel(
            venta.numeroTalonario,
            ReglasDeVenta.diaDeMontevideo(venta.fecha),
          ),
          totalCentavos: venta.montoTotalCentavos,
          cobradoCentavos: venta.cobradoCentavos,
          saldoCentavos: venta.saldoCentavos,
        ),
        const SizedBox(height: 12),
        if (plan.tienePlan) ...[
          RotuloDeCuotas(
            TextosCuotas.rotuloDelPlan(
              plan.cuotas.length,
              RepartoDeCuotas.deducirFrecuencia(plan.cuotas),
            ),
          ),
          for (final cuota in plan.cuotas) ...[
            TarjetaDeCuota(cuota: cuota, ahora: ahora),
            const SizedBox(height: 8),
          ],
          if (!plan.tieneCuotasAbiertas && venta.tieneSaldo)
            const Text(TextosCuotas.sinPlanTexto, style: TextStyle(fontSize: 13.5, height: 1.4)),
        ] else if (!venta.tieneSaldo)
          const MarcaDeSinSaldo()
        else ...[
          const Text(
            TextosCuotas.sinPlanTitulo,
            key: Key('cuotas_sin_plan'),
            style: TextStyle(fontFamily: 'SourceSerif4', fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(TextosCuotas.sinPlanTexto, style: TextStyle(fontSize: 14, height: 1.4)),
        ],
      ],
      cta: plan.tieneCuotasAbiertas
          ? BotonDeVenta(texto: TextosCuotas.modificar, alPresionar: () => unawaited(_modificar()))
          : plan.sePuedeArmar
          ? BotonDeVenta(
              texto: TextosCuotas.pagarEnCuotas,
              alPresionar: () => unawaited(_pagarEnCuotas()),
            )
          : null,
    );
  }
}
