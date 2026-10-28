import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../agenda/domain/entities/franja_horaria.dart';
import '../../../agenda/presentation/widgets/piezas_agendar_visita.dart' show mostrarHojaDiaYHora;
import '../../domain/entities/componente_vendido.dart';
import '../../domain/entities/entrega_pendiente.dart';
import '../../domain/entities/nueva_venta.dart';
import '../../domain/usecases/diferir_entrega_use_case.dart';
import '../formato_entrega.dart';
import '../formato_entrega_diferida.dart';
import '../formato_venta.dart';
import '../providers/entrega_diferida_providers.dart';
import '../providers/ventas_providers.dart';
import '../widgets/piezas_entrega_diferida.dart';
import '../widgets/piezas_venta.dart';

/// «Entregar otro día» (vista 27, grupo C, HU-VEN-003): la colportora que vendió sin tener el material
/// elige para cuándo lo entrega (27C·01); la app agenda una visita de entrega para esa fecha, con
/// recordatorio a la hora que ella eligió («Hora entrega», decisión de Cristian del 28/10: «Que elija
/// la hora»; la hoja es la misma de «Agendar visita», 23A·02).
///
/// Se abre de dos maneras:
/// - [EntregarOtroDiaPage.ruta]: con la venta recién guardada (27A·14, «Entregar otro día»). Si la venta
///   ya tiene filas de entrega (volvió atrás y reentró, o dejó algo pendiente al entregar), se pone la
///   fecha a lo que quedó pendiente.
/// - [EntregarOtroDiaPage.rutaPonerFecha]: con lo pendiente de «Entregas pendientes» (27C·02, «Poner
///   fecha»).
///
/// Devuelve la [ResultadoDiferirEntrega] al cerrarse; `null` si se sale sin guardar. La confirmación
/// («Entrega guardada para …») queda a la vista al volver. El color de la casa (`house_status`) ya se
/// recalculó en la misma transacción.
class EntregarOtroDiaPage extends ConsumerStatefulWidget {
  const EntregarOtroDiaPage._({
    super.key,
    required this.colportorId,
    this.guardada,
    this.nombreDelCliente,
    this.pendiente,
  });

  /// Con la venta recién guardada (27A·14).
  const EntregarOtroDiaPage({
    Key? key,
    required VentaGuardada guardada,
    required String nombreDelCliente,
  }) : this._(key: key, colportorId: '', guardada: guardada, nombreDelCliente: nombreDelCliente);

  /// Con lo que falta entregar de una venta (27C·02, «Poner fecha»).
  const EntregarOtroDiaPage.ponerFecha({
    Key? key,
    required String colportorId,
    required EntregaPendiente pendiente,
  }) : this._(key: key, colportorId: colportorId, pendiente: pendiente);

  final String colportorId;
  final VentaGuardada? guardada;
  final String? nombreDelCliente;
  final EntregaPendiente? pendiente;

  static Route<ResultadoDiferirEntrega> ruta({
    required VentaGuardada guardada,
    required String nombreDelCliente,
  }) => MaterialPageRoute<ResultadoDiferirEntrega>(
    builder: (_) => EntregarOtroDiaPage(guardada: guardada, nombreDelCliente: nombreDelCliente),
  );

  static Route<ResultadoDiferirEntrega> rutaPonerFecha({
    required String colportorId,
    required EntregaPendiente pendiente,
  }) => MaterialPageRoute<ResultadoDiferirEntrega>(
    builder: (_) => EntregarOtroDiaPage.ponerFecha(colportorId: colportorId, pendiente: pendiente),
  );

  @override
  ConsumerState<EntregarOtroDiaPage> createState() => _EntregarOtroDiaPageState();
}

/// Lo que se muestra y se manda: las filas de «Qué entregás» y los productos que hay que guardar.
final class _Contenido {
  const _Contenido({required this.filas, required this.productos});

  final List<({String titulo, String? detalle})> filas;
  final List<ComponenteVendido> productos;
}

class _EntregarOtroDiaPageState extends ConsumerState<EntregarOtroDiaPage> {
  var _saliendo = false;

  String get _eyebrow {
    final talonario = widget.guardada?.venta.numeroTalonario ?? widget.pendiente?.numeroTalonario;
    return talonario == null
        ? TextosEntregaDiferida.eyebrowVentas
        : TextosVenta.eyebrowTalonario(talonario);
  }

  void _cerrar([ResultadoDiferirEntrega? guardada]) {
    if (_saliendo) return;
    _saliendo = true;
    Navigator.of(context).pop(guardada);
  }

  @override
  Widget build(BuildContext context) {
    final guardada = widget.guardada;
    final pendiente = widget.pendiente;
    if (guardada != null) {
      final datos = ref.watch(datosDeLaEntregaProvider(guardada));
      return _marco(
        datos.when(
          loading: () => _Cargando(cabecera: _cabecera(widget.nombreDelCliente, alVolver: _cerrar)),
          error: (error, _) => _ConError(
            cabecera: _cabecera(widget.nombreDelCliente, alVolver: _cerrar),
            texto: error is Failure ? error.mensaje : const FailureEntregaNoDisponible().mensaje,
            alReintentar: () => ref.invalidate(datosDeLaEntregaProvider(guardada)),
          ),
          data: (datos) {
            final previas = datos.previas;
            final _Contenido contenido;
            if (previas.isEmpty) {
              contenido = _Contenido(
                filas: [for (final l in datos.lineas) (titulo: l.titulo, detalle: l.detalle)],
                productos: [for (final l in datos.lineas) ...l.productos],
              );
            } else {
              // Ya tiene filas de entrega: solo se le pone fecha a lo que quedó pendiente.
              contenido = _Contenido(
                filas: [
                  for (final e in previas)
                    if (e.pendiente)
                      (
                        titulo:
                            '${datos.nombres[e.productoId] ?? TextosEntregaDiferida.productoSinNombre}'
                            ' × ${e.cantidad}',
                        detalle: null,
                      ),
                ],
                productos: const [],
              );
            }
            return _Formulario(
              args: ArgumentosOtroDia(
                ventaId: guardada.venta.id,
                colportorId: guardada.venta.colportorId,
                productos: contenido.productos,
              ),
              contenido: contenido,
              cabecera: ({alVolver}) => _cabecera(widget.nombreDelCliente, alVolver: alVolver),
              sinNada: previas.isEmpty
                  ? TextosEntregaDiferida.sinProductos
                  : TextosEntregaDiferida.nadaPendiente,
              alCerrar: _cerrar,
            );
          },
        ),
      );
    }

    final lista = pendiente!;
    final nombres = ref.watch(nombresDeLosPendientesProvider);
    final rotulo = ref.watch(
      rotuloDeEntregaProvider((
        espacioId: lista.espacioId,
        espacioPersonaId: lista.espacioPersonaId,
      )),
    );
    final persona = rotulo.value?.persona ?? '';
    return _marco(
      nombres.when(
        loading: () => _Cargando(cabecera: _cabecera(persona, alVolver: _cerrar)),
        error: (_, _) => _ConError(
          cabecera: _cabecera(persona, alVolver: _cerrar),
          texto: TextosEntregaDiferida.noPudimosLeerLoVendido,
          alReintentar: () => ref.invalidate(nombresDeLosPendientesProvider),
        ),
        data: (nombres) {
          if (nombres == null) {
            return _ConError(
              cabecera: _cabecera(persona, alVolver: _cerrar),
              texto: TextosEntregaDiferida.noPudimosLeerLoVendido,
              alReintentar: () => ref.invalidate(nombresDeLosPendientesProvider),
            );
          }
          return _Formulario(
            args: ArgumentosOtroDia(ventaId: lista.ventaId, colportorId: widget.colportorId),
            contenido: _Contenido(
              filas: [
                for (final l in lista.lineas)
                  (
                    titulo:
                        '${nombres[l.productoId] ?? TextosEntregaDiferida.productoSinNombre} × ${l.cantidad}',
                    detalle: null,
                  ),
              ],
              productos: const [],
            ),
            cabecera: ({alVolver}) => _cabecera(persona, alVolver: alVolver),
            sinNada: TextosEntregaDiferida.nadaPendiente,
            alCerrar: _cerrar,
          );
        },
      ),
    );
  }

  Widget _marco(Widget cuerpo) => Scaffold(
    key: const Key('otro_dia_pagina'),
    body: SafeArea(child: cuerpo),
  );

  Widget _cabecera(String? subtitulo, {VoidCallback? alVolver}) => CabeceraVenta(
    eyebrow: _eyebrow,
    titulo: TextosEntregaDiferida.tituloOtroDia,
    subtitulo: (subtitulo ?? '').isEmpty ? null : subtitulo,
    alVolver: alVolver,
  );
}

class _Cargando extends StatelessWidget {
  const _Cargando({required this.cabecera});

  final Widget cabecera;

  @override
  Widget build(BuildContext context) {
    Widget bloque() => Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE4),
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      children: [
        cabecera,
        Semantics(
          liveRegion: true,
          label: TextosEntregaDiferida.cargandoLoVendido,
          child: ExcludeSemantics(
            child: Column(
              key: const Key('otro_dia_cargando'),
              children: [bloque(), const SizedBox(height: 10), bloque()],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConError extends StatelessWidget {
  const _ConError({required this.cabecera, required this.texto, required this.alReintentar});

  final Widget cabecera;
  final String texto;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      children: [
        cabecera,
        AvisoDeVenta(
          texto: texto,
          textoAccion: TextosEntregaDiferida.reintentar,
          alAccion: alReintentar,
        ),
      ],
    );
  }
}

/// 27C·01: qué se entrega, para cuándo y «Guardar entrega».
class _Formulario extends ConsumerStatefulWidget {
  const _Formulario({
    required this.args,
    required this.contenido,
    required this.cabecera,
    required this.sinNada,
    required this.alCerrar,
  });

  final ArgumentosOtroDia args;
  final _Contenido contenido;

  /// La cabecera con el botón de volver que se le da (apagado mientras se guarda).
  final Widget Function({VoidCallback? alVolver}) cabecera;

  /// Lo que se dice si no hay filas (una venta sin productos, o sin nada pendiente).
  final String sinNada;
  final void Function([ResultadoDiferirEntrega?]) alCerrar;

  @override
  ConsumerState<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends ConsumerState<_Formulario> {
  final _scroll = ScrollController();

  /// La hoja «Día y hora» está abierta: un segundo toque no abre otra encima.
  var _abriendoHoja = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  DateTime get _ahora => ref.read(relojVentaProvider)().toLocal();

  Future<void> _elegirFecha(DateTime? actual) async {
    if (_abriendoHoja) return;
    _abriendoHoja = true;
    try {
      final ahora = _ahora;
      final manana = DateTime(ahora.year, ahora.month, ahora.day + 1);
      final elegida = await mostrarHojaDiaYHora(
        context,
        // Donde arranca la hoja; no queda elegido hasta tocar «Listo».
        inicial:
            actual ??
            DateTime(manana.year, manana.month, manana.day, 0, FranjaHoraria.primeraManiana.desde),
        ahora: ahora,
      );
      if (elegida == null || !mounted) return;
      ref.read(otroDiaProvider(widget.args).notifier).elegirFecha(elegida);
    } finally {
      _abriendoHoja = false;
    }
  }

  Future<void> _guardar() async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final guardada = await ref.read(otroDiaProvider(widget.args).notifier).guardar();
    if (guardada == null || !mounted) return;
    final cuando = FormatoEntregaDiferida.cuando(guardada.entrega.cita.fechaProgramada, _ahora);
    mensajero
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(TextosEntregaDiferida.entregaGuardada(cuando, guardada.recordatorio)),
        ),
      );
    widget.alCerrar(guardada);
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    ref.listen(otroDiaProvider(args).select((s) => s.falla), (anterior, falla) {
      // El aviso de error está arriba: si la lista es larga y estaba más abajo, se lo lleva a la vista.
      if (falla != null && _scroll.hasClients) _scroll.jumpTo(0);
    });
    final estado = ref.watch(otroDiaProvider(args));
    final filas = widget.contenido.filas;
    final fecha = estado.fecha;
    final ocupado = estado.guardando;
    final sinFecha = fecha == null;

    if (filas.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        children: [
          widget.cabecera(alVolver: () => widget.alCerrar()),
          AvisoDeVenta(texto: widget.sinNada, error: false),
        ],
      );
    }

    return PopScope(
      // Mientras se guarda no se sale: la entrega se escribe igual y habría que volver a entrar.
      canPop: !ocupado,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                widget.cabecera(
                  // Mientras se guarda no se sale: la entrega se escribe igual y habría que volver a
                  // entrar para verla.
                  alVolver: ocupado ? null : () => widget.alCerrar(),
                ),
                if (estado.falla case final falla?) ...[
                  AvisoDeVenta(texto: falla.mensaje),
                  const SizedBox(height: 10),
                ],
                const RotuloDeSeccion(TextosEntregaDiferida.queEntregas),
                const SizedBox(height: 7),
                for (final fila in filas) ...[
                  FilaDeLoQueSeEntrega(titulo: fila.titulo, detalle: fila.detalle),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 6),
                CampoDeFechaDeEntrega(
                  rotulo: TextosEntregaDiferida.fechaPrevista,
                  valor: sinFecha
                      ? TextosEntregaDiferida.elegirCuando
                      : FormatoEntregaDiferida.cuando(fecha, _ahora),
                  conValor: !sinFecha,
                  alTocar: ocupado ? null : () => unawaited(_elegirFecha(fecha)),
                ),
                const SizedBox(height: 10),
                const Text(
                  TextosEntregaDiferida.agendamosLaVisita,
                  style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF5B6B82)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: BotonDeVenta(
              texto: estado.falla != null
                  ? TextosEntrega.reintentar
                  : TextosEntregaDiferida.guardarEntrega,
              nota: sinFecha ? TextosEntregaDiferida.elegiCuando : null,
              ocupado: ocupado,
              alPresionar: sinFecha ? null : () => unawaited(_guardar()),
            ),
          ),
        ],
      ),
    );
  }
}
