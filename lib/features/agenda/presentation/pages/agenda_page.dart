import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../mapa/presentation/providers/hoja_casa_providers.dart'
    show ContextoDeVisita, registrarVisitaDesdeLaCasaProvider;
import '../../domain/entities/filtros_agenda.dart';
import '../../domain/entities/item_agenda.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/entities/vista_agenda.dart';
import '../../domain/services/armador_agenda.dart';
import '../formato_agenda.dart';
import '../providers/consulta_agenda_providers.dart';
import '../widgets/hoja_estado_agenda.dart';
import '../widgets/piezas_agenda.dart';

/// La pestaña «Agenda» (vista 23B, HU-VIS-002): las visitas de hoy y de los próximos 7 días,
/// agrupadas por día, con filtros por tipo y por estado.
///
/// Vive dentro de la pantalla principal (`IndexedStack`): [activa] dice si la pestaña está a la
/// vista. La hora (qué cita «ya pasó») se renueva cada minuto solo mientras está a la vista, y al
/// volver a la app.
class AgendaPage extends ConsumerStatefulWidget {
  const AgendaPage({super.key, required this.colportorId, this.activa = true});

  /// UUID del colportor con la sesión iniciada: la agenda es «las que programé».
  final String colportorId;

  /// La pestaña está a la vista.
  final bool activa;

  @override
  ConsumerState<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends ConsumerState<AgendaPage> with WidgetsBindingObserver {
  late DateTime _ahora;
  Timer? _reloj;

  /// Un solo destino abierto a la vez: un segundo toque (o dos filas seguidas) no abre otro encima.
  var _abriendo = false;

  /// La visita que se está registrando: su «Registrar» queda deshabilitado hasta que vuelve.
  String? _registrandoId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ahora = ref.read(relojAgendaProvider)();
    if (widget.activa) _programarProximoMinuto();
  }

  @override
  void didUpdateWidget(AgendaPage anterior) {
    super.didUpdateWidget(anterior);
    if (widget.activa == anterior.activa) return;
    if (widget.activa) {
      _ahora = ref.read(relojAgendaProvider)();
      _programarProximoMinuto();
    } else {
      _reloj?.cancel();
      _reloj = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed && widget.activa) _renovarHora();
  }

  void _renovarHora() {
    if (!mounted) return;
    setState(() => _ahora = ref.read(relojAgendaProvider)());
    _programarProximoMinuto();
  }

  /// Un temporizador hasta el próximo cambio de minuto: la cita que acaba de pasar de hora se marca
  /// como vencida (23B·02) sin tocar nada.
  void _programarProximoMinuto() {
    _reloj?.cancel();
    final ahora = ref.read(relojAgendaProvider)();
    final faltan = Duration(seconds: 60 - ahora.second, milliseconds: -ahora.millisecond);
    _reloj = Timer(faltan < const Duration(seconds: 1) ? const Duration(seconds: 1) : faltan, () {
      if (mounted && widget.activa) _renovarHora();
    });
  }

  /// Corre [accion] si no hay otra en curso: un doble toque (o dos filas seguidas) no abre dos
  /// destinos. Pase lo que pase —incluso si el destino falla— la pantalla vuelve a quedar libre y
  /// lo dice, para que el botón no quede trabado sin explicación.
  Future<void> _sola(FutureOr<Object?> Function() accion, {String? registrandoId}) async {
    if (_abriendo) return;
    _abriendo = true;
    if (registrandoId != null) setState(() => _registrandoId = registrandoId);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    try {
      await accion();
    } on Object {
      mensajero?.showSnackBar(const SnackBar(content: Text(TextosAgenda.noPudimosAbrir)));
    } finally {
      _abriendo = false;
      if (mounted && registrandoId != null) setState(() => _registrandoId = null);
    }
  }

  Future<void> _registrar(FutureOr<Object?> Function(ContextoDeVisita) destino, ItemAgenda item) {
    final casa = item.casa;
    if (casa == null) return Future.value();
    return _sola(
      // Con el `id` de la fila tocada: sin él el flujo tomaría «la programada más antigua» de la casa,
      // que con dos agendas pendientes puede ser otra.
      () => destino((
        ubicacionId: casa.ubicacionId,
        espacioId: item.agenda.espacioId,
        agendaId: item.agenda.id,
      )),
      registrandoId: item.agenda.id,
    );
  }

  Future<void> _elegirEstado(FiltrosAgenda filtros) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      final elegido = await mostrarHojaEstadoAgenda(context, actual: filtros.estado);
      if (elegido == null || !mounted) return;
      ref.read(filtrosAgendaProvider(widget.colportorId).notifier).elegirEstado(elegido);
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inicioDeHoy = VentanaAgenda.de(_ahora).inicioDeHoy;
    final clave = (colportorId: widget.colportorId, inicioDeHoy: inicioDeHoy);
    final leida = ref.watch(agendaLeidaProvider(clave));
    final filtros = ref.watch(filtrosAgendaProvider(widget.colportorId));
    final notificador = ref.read(filtrosAgendaProvider(widget.colportorId).notifier);
    final agendar = ref.watch(agendarDesdeLaAgendaProvider);
    final detalle = ref.watch(abrirDetalleDeAgendaProvider);
    final registrar = ref.watch(registrarVisitaDesdeLaCasaProvider);

    // Un error del lector también cuenta si llega después de los primeros datos: se dice (23B·09) en
    // vez de seguir mostrando una lista que ya no se sabe si está al día.
    final conError = leida.hasError;
    final items = conError ? null : leida.value;

    final List<Widget> cuerpo;
    if (conError) {
      cuerpo = [
        SliverToBoxAdapter(
          child: BannerErrorAgenda(alReintentar: () => ref.invalidate(agendaLeidaProvider(clave))),
        ),
      ];
    } else if (items == null) {
      cuerpo = const [SliverToBoxAdapter(child: EsqueletoAgenda())];
    } else {
      final vista = ArmadorAgenda.armar(items, filtros, _ahora);
      if (vista.estaVacia) {
        cuerpo = [
          SliverFillRemaining(
            hasScrollBody: false,
            child: filtros.esPorDefecto
                ? HeroAgenda(
                    glifo: '▦',
                    titulo: TextosAgenda.vaciaTitulo,
                    cuerpo: TextosAgenda.vaciaCuerpo,
                    textoAccion: TextosAgenda.agendar,
                    alAccion: agendar == null ? null : () => unawaited(_sola(agendar)),
                  )
                : HeroAgenda(
                    glifo: '⌕',
                    titulo: TextosAgenda.sinResultadosTitulo,
                    textoAccion: TextosAgenda.limpiarFiltros,
                    alAccion: notificador.limpiar,
                  ),
          ),
        ];
      } else {
        cuerpo = [
          _Dias(
            vista: vista,
            ahora: _ahora,
            alAgendar: agendar == null ? null : () => unawaited(_sola(agendar)),
            alAbrirDetalle: detalle == null
                ? null
                : (item) => unawaited(_sola(() => detalle(item.agenda.id))),
            alRegistrar: registrar == null
                ? null
                : (item) => unawaited(_registrar(registrar, item)),
            registrando: _registrandoId != null,
          ),
        ];
      }
    }

    // Todo se desplaza junto: con el texto al 200 % el encabezado y los filtros ocupan casi la
    // pantalla y las filas tienen que poder llegar a la vista.
    return CustomScrollView(
      key: const Key('agenda_filas'),
      slivers: [
        const SliverToBoxAdapter(child: CabeceraAgenda()),
        if (!conError)
          SliverToBoxAdapter(
            child: _FilaFiltros(
              filtros: filtros,
              alElegirTipo: notificador.elegirTipo,
              alAbrirEstado: () => unawaited(_elegirEstado(filtros)),
            ),
          ),
        ...cuerpo,
      ],
    );
  }
}

/// Los chips «Todas / Entrevistas / Cobranzas» y «Pendientes ▾» (que abre la hoja del estado).
class _FilaFiltros extends StatelessWidget {
  const _FilaFiltros({
    required this.filtros,
    required this.alElegirTipo,
    required this.alAbrirEstado,
  });

  final FiltrosAgenda filtros;
  final ValueChanged<TipoAgenda?> alElegirTipo;
  final VoidCallback alAbrirEstado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Wrap(
        spacing: 8,
        children: [
          ChipAgenda(
            texto: TextosAgenda.chipTodas,
            elegido: filtros.tipo == null,
            alPresionar: () => alElegirTipo(null),
          ),
          ChipAgenda(
            texto: TextosAgenda.chipEntrevistas,
            elegido: filtros.tipo == TipoAgenda.entrevista,
            alPresionar: () => alElegirTipo(TipoAgenda.entrevista),
          ),
          ChipAgenda(
            texto: TextosAgenda.chipCobranzas,
            elegido: filtros.tipo == TipoAgenda.cobranza,
            alPresionar: () => alElegirTipo(TipoAgenda.cobranza),
          ),
          ChipAgenda(
            texto: '${FormatoAgenda.estado(filtros.estado)} ▾',
            etiqueta: 'Estado: ${FormatoAgenda.estado(filtros.estado)}',
            elegido: filtros.estado != EstadoFiltroAgenda.pendientes,
            alPresionar: alAbrirEstado,
          ),
        ],
      ),
    );
  }
}

/// Lo que se desplaza: el rótulo de cada día y sus filas.
class _Dias extends StatelessWidget {
  const _Dias({
    required this.vista,
    required this.ahora,
    required this.alAgendar,
    required this.alAbrirDetalle,
    required this.alRegistrar,
    required this.registrando,
  });

  final VistaAgenda vista;
  final DateTime ahora;
  final VoidCallback? alAgendar;
  final ValueChanged<ItemAgenda>? alAbrirDetalle;
  final ValueChanged<ItemAgenda>? alRegistrar;

  /// Hay un registro abierto: todos los «Registrar» quedan apagados hasta que vuelva.
  final bool registrando;

  @override
  Widget build(BuildContext context) {
    final entradas = <Object>[
      if (vista.atrasadas.isNotEmpty) ...[
        const _RotuloAtrasadas(),
        for (final item in vista.atrasadas) _FilaAtrasada(item),
      ],
      for (final dia in vista.dias) ...[dia, ...dia.items],
    ];
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      sliver: SliverList.builder(
        itemCount: entradas.length,
        itemBuilder: (context, i) {
          final entrada = entradas[i];
          if (entrada is _RotuloAtrasadas) {
            return RotuloDeDia(
              key: const Key('agenda_atrasadas'),
              texto: FormatoAgenda.rotuloAtrasadas(vista.atrasadas.length),
              // Sin días debajo, «+ Agendar» queda en este primer rótulo.
              alAgendar: vista.dias.isEmpty ? alAgendar : null,
            );
          }
          if (entrada is DiaDeAgenda) {
            return RotuloDeDia(
              key: ValueKey('dia_${entrada.dia.millisecondsSinceEpoch}'),
              texto: FormatoAgenda.rotuloConConteo(entrada),
              // «+ Agendar» queda en el primer día de la lista (hoy, o el que siga), no en las atrasadas.
              alAgendar: identical(entrada, vista.dias.first) ? alAgendar : null,
            );
          }
          final item = switch (entrada) {
            _FilaAtrasada(:final item) => item,
            _ => entrada as ItemAgenda,
          };
          final atrasada = entrada is _FilaAtrasada;
          return FilaAgenda(
            key: ValueKey(item.agenda.id),
            item: item,
            ahora: ahora,
            conFecha: atrasada,
            alTocar: alAbrirDetalle == null ? null : () => alAbrirDetalle!(item),
            // Solo una entrevista vencida se registra desde acá: el cobro tiene su propio flujo.
            alRegistrar:
                alRegistrar != null &&
                    item.agenda.tipo == TipoAgenda.entrevista &&
                    item.casa != null
                ? () => alRegistrar!(item)
                : null,
            registrarHabilitado: !registrando,
          );
        },
      ),
    );
  }
}

/// El rótulo «ATRASADAS (N)» del grupo de arriba.
class _RotuloAtrasadas {
  const _RotuloAtrasadas();
}

/// Una fila del grupo «ATRASADAS»: lleva el día además de la hora.
class _FilaAtrasada {
  const _FilaAtrasada(this.item);

  final ItemAgenda item;
}
