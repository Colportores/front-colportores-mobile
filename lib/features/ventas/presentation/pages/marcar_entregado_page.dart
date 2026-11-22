import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../agenda/domain/entities/franja_horaria.dart';
import '../../../agenda/presentation/formato_agendar_visita.dart';
import '../../../agenda/presentation/textos_agendar_visita.dart';
import '../../../agenda/presentation/textos_detalle_agenda.dart';
import '../../../agenda/presentation/widgets/piezas_agendar_visita.dart'
    show mostrarHojaDiaYHora, mostrarHojaHoraPasada;
import '../../domain/entities/entrega_pendiente.dart';
import '../../domain/usecases/cumplir_entrega_use_case.dart';
import '../formato_entrega.dart';
import '../formato_entrega_diferida.dart';
import '../formato_venta.dart';
import '../providers/entrega_diferida_providers.dart';
import '../providers/entrega_providers.dart';
import '../widgets/piezas_entrega.dart';
import '../widgets/piezas_entrega_diferida.dart';
import '../widgets/piezas_venta.dart';

/// «Marcar entregado» (vista 27, grupo C, HU-VEN-003): el día de la entrega la colportora tilda lo que
/// entregó (27C·03); si deja algo sin tildar (27C·04, entrega parcial) lo que falta sigue pendiente y
/// elige para cuándo («Nueva fecha», que puede quedar «Sin fecha»).
///
/// Funciona sin conexión (27C·08): todo se guarda en el teléfono y la entrega se envía cuando vuelve la
/// señal (vista 25). Lee lo pendiente en vivo: si ya se entregó todo (volvió atrás y reentró, o lo
/// marcó desde la Agenda) lo dice en vez de entregar de nuevo.
///
/// Devuelve el [ResultadoCumplirEntrega] al cerrarse; `null` si se sale sin marcar.
class MarcarEntregadoPage extends ConsumerStatefulWidget {
  const MarcarEntregadoPage({super.key, required this.ventaId, this.cual});

  /// La venta cuya entrega se marca.
  final String ventaId;

  /// Cuál de sus entregas: una venta puede tener una cita por cada grupo de libros diferido (decisión
  /// de Cristian del 11/11, «Entrega cita») y se marcan solo los de esa. `null`: la primera de la venta.
  final CualEntrega? cual;

  static Route<ResultadoCumplirEntrega> ruta({required String ventaId}) =>
      MaterialPageRoute<ResultadoCumplirEntrega>(
        builder: (_) => MarcarEntregadoPage(ventaId: ventaId),
      );

  /// La de [cual] (la tarjeta de «Entregas pendientes», o la de la ficha con su fecha).
  static Route<ResultadoCumplirEntrega> rutaDe(CualEntrega cual) =>
      MaterialPageRoute<ResultadoCumplirEntrega>(
        builder: (_) => MarcarEntregadoPage(ventaId: cual.ventaId, cual: cual),
      );

  @override
  ConsumerState<MarcarEntregadoPage> createState() => _MarcarEntregadoPageState();
}

class _MarcarEntregadoPageState extends ConsumerState<MarcarEntregadoPage> {
  final _scroll = ScrollController();
  var _saliendo = false;
  var _abriendoHoja = false;

  /// Lo último que se supo de lo pendiente: al marcar todo, la lista en vivo lo saca y la pantalla
  /// tiene que seguir mostrando lo que se acaba de entregar hasta cerrarse.
  EntregaPendiente? _ultima;

  /// Los nombres que se leyeron mientras había algo pendiente: cuando la lista en vivo ya no trae la
  /// venta, los nombres también se vacían y no tienen que verse «Producto sin nombre» al cerrarse.
  Map<String, String>? _nombresUltimos;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  DateTime get _ahora => ref.read(relojEntregaProvider)().toLocal();

  CualEntrega get _cual => widget.cual ?? CualEntrega(widget.ventaId);

  void _cerrar([ResultadoCumplirEntrega? resultado]) {
    if (_saliendo) return;
    _saliendo = true;
    Navigator.of(context).pop(resultado);
  }

  Future<void> _elegirNuevaFecha(DateTime? actual) async {
    if (_abriendoHoja) return;
    _abriendoHoja = true;
    try {
      final ahora = _ahora;
      final manana = DateTime(ahora.year, ahora.month, ahora.day + 1);
      final elegida = await mostrarHojaDiaYHora(
        context,
        inicial:
            actual ??
            DateTime(manana.year, manana.month, manana.day, 0, FranjaHoraria.primeraManiana.desde),
        ahora: ahora,
      );
      if (elegida == null || !mounted) return;
      ref.read(marcarProvider(_cual).notifier).elegirNuevaFecha(elegida);
    } finally {
      _abriendoHoja = false;
    }
  }

  /// «Nueva fecha» ya pasó (al minuto, como 23A·03).
  bool _horaPasada(DateTime fecha) {
    final ahora = _ahora;
    return fecha.isBefore(DateTime(ahora.year, ahora.month, ahora.day, ahora.hour, ahora.minute));
  }

  /// Con algo destildado y su «Nueva fecha» ya pasada, antes de guardar se pregunta (decisión del
  /// 28/10, P2 del QA de #435, la misma regla que 27C·01).
  Future<void> _marcar(EntregaPendiente pendiente) async {
    final estado = ref.read(marcarProvider(_cual));
    final nueva = estado.nuevaFecha;
    final queda = pendiente.lineas.any((l) => estado.desmarcadas.contains(l.entregaId));
    final hayMarcadas = pendiente.lineas.any((l) => !estado.desmarcadas.contains(l.entregaId));
    if (queda && hayMarcadas && nueva != null && _horaPasada(nueva) && !estado.guardando) {
      final ahora = _ahora;
      final decision = await mostrarHojaHoraPasada(
        context,
        texto: TextosDetalleAgenda.horaPasadaTexto(
          FormatoAgendarVisita.cuandoEnFrase(nueva, ahora),
          FormatoAgendarVisita.hora(ahora),
        ),
        confirmar: TextosDetalleAgenda.guardarIgual,
      );
      if (!mounted) return;
      if (decision == false) return _elegirNuevaFecha(nueva);
      if (decision != true) return;
    }
    await _marcarYa(pendiente);
  }

  Future<void> _marcarYa(EntregaPendiente pendiente) async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final resultado = await ref.read(marcarProvider(_cual).notifier).marcar([
      for (final l in pendiente.lineas) l.entregaId,
    ]);
    if (resultado == null || !mounted) return;
    mensajero
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            resultado.entrega.todoDevuelto
                ? TextosEntregaDiferida.nadaQueEntregarDevuelto
                : resultado.entrega.yaEstaba
                ? TextosEntregaDiferida.yaEstabaEntregada
                : resultado.entrega.quedaPendiente
                ? TextosEntregaDiferida.entregaMarcadaQuedaAlgo
                : TextosEntregaDiferida.entregaMarcada,
          ),
        ),
      );
    _cerrar(resultado);
  }

  @override
  Widget build(BuildContext context) {
    final vivo = ref.watch(entregaPendienteDeVentaProvider(_cual));
    // Guardando o ya guardado, la lista en vivo puede haber sacado la venta: se sigue mostrando lo que
    // se estaba marcando hasta cerrarse.
    final enCurso = ref.watch(
      marcarProvider(_cual).select((s) => s.guardando || s.guardada != null),
    );
    final pendiente = vivo.value ?? (enCurso ? _ultima : null);
    if (vivo.value != null) _ultima = vivo.value;
    final leidos = ref.watch(nombresDeLosPendientesProvider);
    final nombresVivos = leidos.value;
    if (!enCurso && nombresVivos != null && nombresVivos.isNotEmpty) _nombresUltimos = nombresVivos;
    final nombres = enCurso && _nombresUltimos != null ? AsyncData(_nombresUltimos) : leidos;

    Widget cabecera({VoidCallback? alVolver, String? subtitulo, String? talonario}) =>
        CabeceraVenta(
          eyebrow: talonario == null
              ? TextosEntregaDiferida.eyebrowVentas
              : TextosVenta.eyebrowTalonario(talonario),
          titulo: TextosEntregaDiferida.tituloMarcar,
          subtitulo: (subtitulo ?? '').isEmpty ? null : subtitulo,
          alVolver: alVolver,
        );

    final Widget cuerpo;
    if (vivo.isLoading && pendiente == null) {
      cuerpo = _Marco(
        cabecera: cabecera(alVolver: _cerrar),
        hijos: const [_EsqueletoDeMarcar()],
      );
    } else if (vivo.hasError && pendiente == null) {
      cuerpo = _Marco(
        cabecera: cabecera(alVolver: _cerrar),
        hijos: [
          AvisoDeVenta(
            texto: TextosEntregaDiferida.noPudimosLeer,
            textoAccion: TextosEntregaDiferida.reintentar,
            alAccion: () => ref.invalidate(entregasPendientesProvider),
          ),
        ],
      );
    } else if (pendiente == null) {
      // Ya se entregó todo (reentró, o se marcó desde la Agenda): se dice, sin entregar de nuevo.
      cuerpo = _Marco(
        cabecera: cabecera(alVolver: _cerrar),
        hijos: const [AvisoDeVenta(texto: TextosEntregaDiferida.nadaPendiente, error: false)],
      );
    } else {
      cuerpo = _Formulario(
        cual: _cual,
        pendiente: pendiente,
        nombresLeidos: nombres,
        scroll: _scroll,
        alElegirFecha: (actual) => unawaited(_elegirNuevaFecha(actual)),
        alMarcar: () => unawaited(_marcar(pendiente)),
        cabecera: ({alVolver, subtitulo}) => cabecera(
          alVolver: alVolver,
          subtitulo: subtitulo,
          talonario: pendiente.numeroTalonario,
        ),
        alCerrar: _cerrar,
      );
    }
    return PopScope(
      // Mientras se guarda no se sale: la entrega se escribe igual y habría que volver a entrar.
      canPop: !enCurso,
      child: Scaffold(
        key: const Key('marcar_pagina'),
        body: SafeArea(child: cuerpo),
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

class _EsqueletoDeMarcar extends StatelessWidget {
  const _EsqueletoDeMarcar();

  @override
  Widget build(BuildContext context) {
    Widget bloque() => Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE4),
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: TextosEntregaDiferida.cargandoPendientes,
      child: ExcludeSemantics(
        child: Column(
          key: const Key('marcar_cargando'),
          children: [bloque(), const SizedBox(height: 10), bloque()],
        ),
      ),
    );
  }
}

/// 27C·03 y 27C·04: qué se entregó y, si falta algo, para cuándo.
class _Formulario extends ConsumerWidget {
  const _Formulario({
    required this.cual,
    required this.pendiente,
    required this.nombresLeidos,
    required this.scroll,
    required this.alElegirFecha,
    required this.alMarcar,
    required this.cabecera,
    required this.alCerrar,
  });

  /// Con qué se abrió la pantalla: la clave del estado de «Marcar» (no cambia aunque la fecha sí).
  final CualEntrega cual;
  final EntregaPendiente pendiente;
  final AsyncValue<Map<String, String>?> nombresLeidos;
  final ScrollController scroll;
  final ValueChanged<DateTime?> alElegirFecha;
  final VoidCallback alMarcar;
  final Widget Function({VoidCallback? alVolver, String? subtitulo}) cabecera;
  final VoidCallback alCerrar;

  /// [fecha] ya pasó (al minuto).
  static bool _yaPaso(DateTime fecha, WidgetRef ref) {
    final ahora = ref.read(relojEntregaProvider)().toLocal();
    return fecha.isBefore(DateTime(ahora.year, ahora.month, ahora.day, ahora.hour, ahora.minute));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(marcarProvider(cual).select((s) => s.falla), (anterior, falla) {
      // El aviso de error está arriba: si la lista es larga y estaba más abajo, se lo lleva a la vista.
      if (falla != null && scroll.hasClients) scroll.jumpTo(0);
    });
    final estado = ref.watch(marcarProvider(cual));
    final notifier = ref.read(marcarProvider(cual).notifier);
    final rotulo = ref.watch(
      rotuloDeEntregaProvider((
        espacioId: pendiente.espacioId,
        espacioPersonaId: pendiente.espacioPersonaId,
      )),
    );
    final subtitulo = rotulo.value?.persona;
    final ocupado = estado.guardando;

    final nombres = nombresLeidos.value;
    if (nombres == null) {
      // Sin nombres no se puede decir qué se entrega: «Reintentar», nunca un nombre inventado.
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        children: [
          cabecera(alVolver: alCerrar, subtitulo: subtitulo),
          if (nombresLeidos.isLoading)
            const _EsqueletoDeMarcar()
          else
            AvisoDeVenta(
              texto: TextosEntregaDiferida.noPudimosLeerLoVendido,
              textoAccion: TextosEntregaDiferida.reintentar,
              alAccion: () => ref.invalidate(nombresDeLosPendientesProvider),
            ),
        ],
      );
    }

    String titulo(LineaPendiente l) =>
        '${nombres[l.productoId] ?? TextosEntregaDiferida.productoSinNombre} × ${l.cantidad}';
    final lineas = pendiente.lineas;
    final sinMarcar = [
      for (final l in lineas)
        if (estado.desmarcadas.contains(l.entregaId)) l,
    ];
    final marcadas = lineas.length - sinMarcar.length;
    final sinNada = marcadas == 0;
    final nombresSinMarcar = [
      for (final l in sinMarcar) nombres[l.productoId] ?? TextosEntregaDiferida.productoSinNombre,
    ];

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              cabecera(
                // Mientras se guarda no se sale: la entrega se escribe igual y habría que volver a
                // entrar para verla.
                alVolver: ocupado ? null : alCerrar,
                subtitulo: subtitulo,
              ),
              if (estado.falla case final falla?) ...[
                AvisoDeVenta(texto: falla.mensaje),
                const SizedBox(height: 10),
              ],
              const RotuloDeSeccion(TextosEntregaDiferida.queEntregas),
              const SizedBox(height: 7),
              for (final linea in lineas) ...[
                FilaDeEntrega(
                  titulo: titulo(linea),
                  marcada: !estado.desmarcadas.contains(linea.entregaId),
                  alCambiar: ocupado ? null : () => notifier.alternar(linea.entregaId),
                ),
                const SizedBox(height: 8),
              ],
              if (sinMarcar.isNotEmpty && !sinNada) ...[
                const SizedBox(height: 4),
                Text(
                  TextosEntregaDiferida.sigueFaltando(nombresSinMarcar),
                  key: const Key('marcar_sigue_pendiente'),
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 10),
                CampoDeFechaDeEntrega(
                  rotulo: TextosEntregaDiferida.nuevaFecha,
                  valor: estado.nuevaFecha == null
                      ? TextosEntregaDiferida.placeholderNuevaFecha
                      : FormatoEntregaDiferida.cuando(
                          estado.nuevaFecha!,
                          ref.read(relojEntregaProvider)(),
                        ),
                  conValor: estado.nuevaFecha != null,
                  error: estado.nuevaFecha != null && _yaPaso(estado.nuevaFecha!, ref)
                      ? TextosAgendarVisita.horaPasadaCorta
                      : null,
                  alTocar: ocupado ? null : () => alElegirFecha(estado.nuevaFecha),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: BotonDeVenta(
            texto: estado.falla != null
                ? TextosEntrega.reintentar
                : TextosEntregaDiferida.marcarN(marcadas, todo: sinMarcar.isEmpty),
            nota: sinNada ? TextosEntregaDiferida.elegiUnProducto : null,
            ocupado: ocupado,
            alPresionar: sinNada ? null : alMarcar,
          ),
        ),
      ],
    );
  }
}
