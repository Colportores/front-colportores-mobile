import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../domain/entities/entrega.dart';
import '../../domain/entities/nueva_venta.dart';
import '../formato_entrega.dart';
import '../formato_venta.dart';
import '../providers/entregar_ahora_notifier.dart';
import '../providers/ventas_providers.dart';
import '../widgets/piezas_entrega.dart';
import '../widgets/piezas_venta.dart';

/// «Entregar ahora» (vista 27, grupo B, HU-VEN-002): con la venta recién registrada, la colportora que
/// tiene el material encima tilda lo que entrega y cierra la operación en un paso (27B·01); después ve
/// cómo quedó la venta (27B·03, venta completa, o 27B·04, entregada con saldo).
///
/// En V1 no hay stock (decisión del 23/10, el stock es V2, HU-STK-007): la app confía en la
/// colportora, así que no muestra «Tenés N en mano» ni «No tenés suficiente en mano» (27B·02). Lo que
/// destilda queda pendiente para otro día (27C).
///
/// Devuelve la [EntregaRegistrada] al cerrarse («Volver al mapa»); `null` si se sale sin entregar. El
/// color de la casa (`house_status`) ya se recalculó en la misma transacción.
///
/// [alCobrar] y [alAgendarCobranza] dibujan «Cobrar ahora» y «Agendar la cobranza» (27B·04) y los
/// engancha quien tenga esa pantalla (el cobro, la vista 28; la cobranza, la vista 22). Sin destino no
/// se dibujan: un botón que no lleva a ningún lado sería mentir (HU-UBI-003).
class EntregarAhoraPage extends ConsumerStatefulWidget {
  const EntregarAhoraPage({
    super.key,
    required this.guardada,
    required this.nombreDelCliente,
    this.alCobrar,
    this.alAgendarCobranza,
  });

  final VentaGuardada guardada;
  final String nombreDelCliente;
  final ValueChanged<EntregaRegistrada>? alCobrar;
  final ValueChanged<EntregaRegistrada>? alAgendarCobranza;

  static Route<EntregaRegistrada> ruta({
    required VentaGuardada guardada,
    required String nombreDelCliente,
    ValueChanged<EntregaRegistrada>? alCobrar,
    ValueChanged<EntregaRegistrada>? alAgendarCobranza,
  }) => MaterialPageRoute<EntregaRegistrada>(
    builder: (_) => EntregarAhoraPage(
      guardada: guardada,
      nombreDelCliente: nombreDelCliente,
      alCobrar: alCobrar,
      alAgendarCobranza: alAgendarCobranza,
    ),
  );

  @override
  ConsumerState<EntregarAhoraPage> createState() => _EntregarAhoraPageState();
}

class _EntregarAhoraPageState extends ConsumerState<EntregarAhoraPage> {
  var _saliendo = false;

  VentaGuardada get _guardada => widget.guardada;

  String get _eyebrow => TextosVenta.eyebrowTalonario(_guardada.venta.numeroTalonario);

  void _cerrar([EntregaRegistrada? registrada]) {
    if (_saliendo) return;
    _saliendo = true;
    Navigator.of(context).pop(registrada);
  }

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(datosDeLaEntregaProvider(_guardada));
    return Scaffold(
      key: const Key('entrega_pagina'),
      body: SafeArea(
        child: datos.when(
          loading: () => _Marco(
            cabecera: CabeceraVenta(
              eyebrow: _eyebrow,
              titulo: TextosEntrega.titulo,
              subtitulo: widget.nombreDelCliente,
              alVolver: _cerrar,
            ),
            hijos: const [_EsqueletoDeEntrega()],
          ),
          error: (error, _) => _Marco(
            cabecera: CabeceraVenta(
              eyebrow: _eyebrow,
              titulo: TextosEntrega.titulo,
              subtitulo: widget.nombreDelCliente,
              alVolver: _cerrar,
            ),
            hijos: [
              AvisoDeVenta(
                texto: error is Failure
                    ? error.mensaje
                    : const FailureEntregaNoDisponible().mensaje,
                textoAccion: TextosEntrega.reintentar,
                alAccion: () => ref.invalidate(datosDeLaEntregaProvider(_guardada)),
              ),
            ],
          ),
          data: (datos) {
            if (datos.previas.isNotEmpty) {
              // Ya se entregó (volvió atrás y reentró, o un reintento): se muestra cómo quedó, sin
              // entregar de nuevo.
              return _Resultado(
                guardada: _guardada,
                registrada: EntregaRegistrada(entregas: datos.previas, yaEstaba: true),
                nombres: datos.nombres,
                eyebrow: _eyebrow,
                alCobrar: widget.alCobrar,
                alAgendarCobranza: widget.alAgendarCobranza,
                alVolver: _cerrar,
              );
            }
            if (datos.lineas.isEmpty) {
              return _Marco(
                cabecera: CabeceraVenta(
                  eyebrow: _eyebrow,
                  titulo: TextosEntrega.titulo,
                  subtitulo: widget.nombreDelCliente,
                  alVolver: _cerrar,
                ),
                hijos: const [AvisoDeVenta(texto: TextosEntrega.sinProductos, error: false)],
              );
            }
            return _Formulario(
              args: ArgumentosDeEntrega(guardada: _guardada, lineas: datos.lineas),
              nombres: datos.nombres,
              nombreDelCliente: widget.nombreDelCliente,
              eyebrow: _eyebrow,
              alCobrar: widget.alCobrar,
              alAgendarCobranza: widget.alAgendarCobranza,
              alVolver: _cerrar,
            );
          },
        ),
      ),
    );
  }
}

/// Cabecera y contenido que se desplaza, sin botón de abajo.
class _Marco extends StatelessWidget {
  const _Marco({required this.cabecera, required this.hijos});

  final Widget cabecera;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      children: [cabecera, ...hijos],
    );
  }
}

class _EsqueletoDeEntrega extends StatelessWidget {
  const _EsqueletoDeEntrega();

  @override
  Widget build(BuildContext context) {
    Widget bloque() => Container(
      height: 56,
      decoration: BoxDecoration(
        color: ColoresAgenda.esqueleto,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: TextosEntrega.cargando,
      child: ExcludeSemantics(
        child: Column(
          key: const Key('entrega_cargando'),
          children: [
            bloque(),
            const SizedBox(height: 10),
            bloque(),
            const SizedBox(height: 10),
            bloque(),
          ],
        ),
      ),
    );
  }
}

/// 27B·01: qué se entrega.
class _Formulario extends ConsumerStatefulWidget {
  const _Formulario({
    required this.args,
    required this.nombres,
    required this.nombreDelCliente,
    required this.eyebrow,
    required this.alVolver,
    this.alCobrar,
    this.alAgendarCobranza,
  });

  final ArgumentosDeEntrega args;
  final Map<String, String> nombres;
  final String nombreDelCliente;
  final String eyebrow;
  final void Function([EntregaRegistrada?]) alVolver;
  final ValueChanged<EntregaRegistrada>? alCobrar;
  final ValueChanged<EntregaRegistrada>? alAgendarCobranza;

  @override
  ConsumerState<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends ConsumerState<_Formulario> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    ref.listen(entregarAhoraProvider(args).select((s) => s.falla), (anterior, falla) {
      // El aviso de error está arriba: si la lista es larga y estaba más abajo, se lo lleva a la vista.
      if (falla != null && _scroll.hasClients) _scroll.jumpTo(0);
    });
    final estado = ref.watch(entregarAhoraProvider(args));
    final notifier = ref.read(entregarAhoraProvider(args).notifier);

    final registrada = estado.registrada;
    if (registrada != null) {
      return _Resultado(
        guardada: args.guardada,
        registrada: registrada,
        nombres: widget.nombres,
        eyebrow: widget.eyebrow,
        alCobrar: widget.alCobrar,
        alAgendarCobranza: widget.alAgendarCobranza,
        alVolver: widget.alVolver,
      );
    }

    final lineas = args.lineas;
    final sinMarcar = [
      for (final l in lineas)
        if (!estado.marcadas.contains(l.clave)) l,
    ];
    final ocupado = estado.entregando;
    final sinNada = estado.marcadas.isEmpty;
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              CabeceraVenta(
                eyebrow: widget.eyebrow,
                titulo: TextosEntrega.titulo,
                subtitulo: widget.nombreDelCliente,
                // Mientras se guarda no se sale: la entrega se escribe igual y habría que volver a
                // entrar para verla.
                alVolver: ocupado ? null : () => widget.alVolver(),
              ),
              if (estado.falla case final falla?) ...[
                AvisoDeVenta(texto: falla.mensaje),
                const SizedBox(height: 10),
              ],
              const RotuloDeSeccion(TextosEntrega.queEntregas),
              const SizedBox(height: 7),
              for (final linea in lineas) ...[
                FilaDeEntrega(
                  titulo: linea.titulo,
                  detalle: linea.detalle,
                  marcada: estado.marcadas.contains(linea.clave),
                  alCambiar: ocupado ? null : () => notifier.alternar(linea.clave),
                ),
                const SizedBox(height: 8),
              ],
              if (sinMarcar.isNotEmpty && !sinNada)
                AvisoDeVenta(
                  texto: TextosEntrega.quedaParaOtroDia([for (final l in sinMarcar) l.nombre]),
                  error: false,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: BotonDeVenta(
            texto: estado.falla != null
                ? TextosEntrega.reintentar
                : TextosEntrega.entregarN(estado.marcadas.length, todo: sinMarcar.isEmpty),
            nota: sinNada ? TextosEntrega.elegiUnProducto : null,
            ocupado: ocupado,
            alPresionar: sinNada ? null : notifier.entregar,
          ),
        ),
      ],
    );
  }
}

/// 27B·03 (venta completa) o 27B·04 (entregada con saldo).
class _Resultado extends StatelessWidget {
  const _Resultado({
    required this.guardada,
    required this.registrada,
    required this.nombres,
    required this.eyebrow,
    required this.alVolver,
    this.alCobrar,
    this.alAgendarCobranza,
  });

  final VentaGuardada guardada;
  final EntregaRegistrada registrada;
  final Map<String, String> nombres;
  final String eyebrow;
  final void Function([EntregaRegistrada?]) alVolver;
  final ValueChanged<EntregaRegistrada>? alCobrar;
  final ValueChanged<EntregaRegistrada>? alAgendarCobranza;

  @override
  Widget build(BuildContext context) {
    // Hasta que existan los cobros (HU-COB-001, #436) el saldo es el monto entero de la venta.
    final saldo = guardada.venta.montoTotalCentavos;
    final quedaPendiente = registrada.quedaPendiente;
    final completa = !quedaPendiente && saldo == 0;
    final pendientes = [
      for (final e in registrada.entregas)
        if (e.pendiente) e,
    ];
    final cobrar = completa ? null : alCobrar;
    final agendar = completa ? null : alAgendarCobranza;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (volvio, _) {
        if (!volvio) alVolver(registrada);
      },
      child: Column(
        children: [
          Expanded(
            child: ListView(
              key: const Key('entrega_resultado'),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                CabeceraVenta(
                  eyebrow: eyebrow,
                  titulo: completa
                      ? TextosEntrega.tituloListo
                      : TextosEntrega.tituloEntregaRegistrada,
                ),
                if (completa)
                  CartelDeVentaCompleta(
                    titulo: TextosEntrega.ventaCompleta,
                    detalle: TextosEntrega.entregasteTodoYPagada(
                      habiaQueCobrar: guardada.venta.montoTotalCentavos > 0,
                    ),
                  )
                else ...[
                  RenglonDeResumen(
                    rotulo: TextosEntrega.entregado,
                    valor: quedaPendiente
                        ? TextosEntrega.entregadoDe(
                            registrada.entregas.length - pendientes.length,
                            registrada.entregas.length,
                          )
                        : TextosEntrega.todo,
                  ),
                  if (quedaPendiente)
                    RenglonDeResumen(
                      rotulo: TextosEntrega.pendiente,
                      valor: [for (final e in pendientes) _conCantidad(e, nombres)].join(', '),
                    ),
                  RenglonDeResumen(
                    rotulo: TextosEntrega.saldo,
                    valor: FormatoVenta.monto(saldo),
                    cifra: true,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    quedaPendiente
                        ? (saldo > 0
                              ? TextosEntrega.casaEntregaYCobranzaPendientes
                              : TextosEntrega.casaEntregaPendiente)
                        : TextosEntrega.casaCobranzaPendiente,
                    key: const Key('entrega_casa'),
                    style: const TextStyle(fontSize: 14, height: 1.4, color: ColoresAgenda.tinta),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (cobrar != null)
                  FilledButton(
                    key: const Key('entrega_cobrar'),
                    onPressed: () => cobrar(registrada),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: ColoresAgenda.navy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text(
                      TextosEntrega.cobrarAhora,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (agendar != null)
                  TextButton(
                    key: const Key('entrega_agendar_cobranza'),
                    onPressed: () => agendar(registrada),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: const Text(
                      TextosEntrega.agendarLaCobranza,
                      style: TextStyle(fontWeight: FontWeight.w600, color: ColoresAgenda.azul),
                    ),
                  ),
                if (cobrar == null && agendar == null)
                  BotonDeVenta(
                    texto: TextosEntrega.volverAlMapa,
                    alPresionar: () => alVolver(registrada),
                  )
                else
                  TextButton(
                    key: const Key('entrega_volver'),
                    onPressed: () => alVolver(registrada),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: const Text(
                      TextosEntrega.volverAlMapa,
                      style: TextStyle(fontWeight: FontWeight.w600, color: ColoresAgenda.azul),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String _conCantidad(Entrega e, Map<String, String> nombres) =>
      '${nombres[e.productoId] ?? 'Producto sin nombre'} × ${e.cantidad}';
}
