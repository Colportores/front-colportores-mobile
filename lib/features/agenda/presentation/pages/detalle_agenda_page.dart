import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../cobranzas/presentation/pages/cuotas_de_la_venta_page.dart';
import '../../../cobranzas/presentation/textos_cuotas.dart' show TextosCuotas;
import '../../../mapa/domain/entities/persona_del_espacio.dart';
import '../../../mapa/domain/repositories/espacio_repository.dart';
import '../../../mapa/presentation/providers/hoja_casa_providers.dart'
    show registrarVisitaDesdeLaCasaProvider;
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../../mapa/presentation/textos_personas.dart';
import '../../../mapa/presentation/widgets/piezas_alta.dart';
import '../../../ventas/domain/usecases/cumplir_entrega_use_case.dart';
import '../../../ventas/presentation/formato_entrega_diferida.dart' show TextosEntregaDiferida;
import '../../../ventas/presentation/providers/entrega_providers.dart'
    show cumplirEntregaUseCaseProvider;
import '../../domain/entities/detalle_de_agenda.dart';
import '../../domain/entities/estado_agenda.dart';
import '../../domain/entities/franja_horaria.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/usecases/cancelar_agenda_use_case.dart';
import '../formato_agenda.dart' show TextosAgenda;
import '../formato_detalle_agenda.dart';
import '../providers/agenda_providers.dart';
import '../providers/detalle_agenda_providers.dart';
import '../textos_agendar_visita.dart';
import '../textos_detalle_agenda.dart';
import '../widgets/enlace_cancelar_agenda.dart';
import 'modificar_agenda_page.dart';

/// El detalle de una agenda (vista 23, 23C·01, 23C·03 y 23C·06, HU-VIS-003): qué es, con quién, cuándo
/// y a qué hora suena el recordatorio, y las salidas.
///
/// - **Programada** (23C·01): «Registrar resultado» lleva a «¿Qué pasó?» de la vista 39 con la casa y
///   la agenda ya puestas; «Modificar» abre 23C·02; «Cancelar agenda» va como enlace al pie.
///   En una cita de **entrega** (HU-VEN-003) «Registrar resultado» no va: su lugar lo toma «Entregado
///   hoy», que marca como entregado lo pendiente de la venta (una sola llamada mientras guarda). Si no
///   se puede guardar, un aviso fijo arriba lo dice y «Entregado hoy» queda a mano para reintentar
///   (decisión del 28/10, P3 del QA de #435).
/// - **Modificada** (23C·03): al volver de «Modificar», el detalle ya muestra lo nuevo y el aviso de éxito
///   («Guardado. El recordatorio pasó a las 10:00.») queda en pantalla.
/// - **Cumplida o no cumplida** (23C·06): el aviso «Esta visita ya tiene resultado…» y ninguna salida.
/// - **Cancelada**: el mismo criterio con su propio aviso (el canvas no la dibuja).
/// - **Cobranza de una cuota** (HU-COB-004, #580): «Ver las cuotas» abre las cuotas de esa venta
///   (30A-06), en cualquier estado de la agenda.
/// - Cargando, error al leer («Reintentar») y agenda que ya no está en el teléfono.
///
/// Todo se lee del teléfono: sin conexión funciona igual.
class DetalleAgendaPage extends ConsumerStatefulWidget {
  const DetalleAgendaPage({super.key, required this.agendaId, required this.colportorId});

  /// El `agenda.id` que se muestra.
  final String agendaId;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  /// Abre el detalle encima de la pantalla actual. Si ya es la pantalla de arriba (tocar el aviso de
  /// la agenda que se está mirando), no apila otro igual: habría que volver dos veces.
  static Future<void> abrir(
    BuildContext context, {
    required String agendaId,
    required String colportorId,
  }) {
    final navegador = Navigator.of(context);
    final nombre = 'detalle_agenda/$agendaId';
    var yaEstaArriba = false;
    // El predicado devuelve `true` en la primera ruta: mira la de arriba y no saca ninguna.
    navegador.popUntil((ruta) {
      yaEstaArriba = ruta.settings.name == nombre;
      return true;
    });
    if (yaEstaArriba) return Future<void>.value();
    return navegador.push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: nombre),
        builder: (_) => DetalleAgendaPage(agendaId: agendaId, colportorId: colportorId),
      ),
    );
  }

  @override
  ConsumerState<DetalleAgendaPage> createState() => _DetalleAgendaPageState();
}

class _DetalleAgendaPageState extends ConsumerState<DetalleAgendaPage> {
  /// Hay una pantalla abierta desde el detalle («Modificar», «Registrar resultado»): un segundo toque
  /// no abre otra encima.
  var _abriendo = false;

  Future<void> _modificar(DetalleDeAgenda detalle) async {
    if (_abriendo) return;
    _abriendo = true;
    final mensajero = ScaffoldMessenger.maybeOf(context);
    try {
      mensajero?.clearSnackBars();
      final guardado = await ModificarAgendaPage.abrir(
        context,
        detalle: detalle,
        colportorId: widget.colportorId,
      );
      if (guardado == null) return;
      // Lo nuevo se lee de la base; el aviso (23C·03) se queda en el detalle.
      ref.invalidate(detalleDeAgendaProvider(widget.agendaId));
      mensajero
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(guardado.aviso)));
    } finally {
      _abriendo = false;
    }
  }

  Future<void> _verLasCuotas(DetalleDeAgenda detalle) async {
    final agenda = detalle.agenda;
    final ventaId = agenda.ventaId;
    if (ventaId == null || _abriendo) return;
    _abriendo = true;
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    try {
      await CuotasDeLaVentaPage.abrir(
        context,
        ventaId: ventaId,
        colportorId: widget.colportorId,
        espacioId: agenda.espacioId,
        espacioPersonaId: agenda.espacioPersonaId,
      );
    } finally {
      _abriendo = false;
    }
    // Armar o modificar el plan puede mover la cita (fecha, monto): se vuelve a leer de la base.
    if (mounted) ref.invalidate(detalleDeAgendaProvider(widget.agendaId));
  }

  /// Ya hay un «Entregado hoy» en curso: un segundo toque no llama de nuevo.
  var _entregando = false;

  /// El último «Entregado hoy» no se pudo guardar: el aviso queda fijo hasta que un reintento sale bien
  /// o se sale de la pantalla.
  var _fallaAlEntregar = false;

  /// «Entregado hoy» (HU-VEN-003, «Cumplir entrega pendiente»): lo pendiente de la venta pasa a
  /// entregado con la fecha de hoy y la cita se cumple.
  Future<void> _entregadoHoy(DetalleDeAgenda detalle) async {
    final ventaId = detalle.agenda.ventaId;
    if (_entregando || ventaId == null) return;
    setState(() => _entregando = true);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    String? aviso;
    try {
      final hecho = await ref
          .read(cumplirEntregaUseCaseProvider)
          .call(CumplirEntregaParams(ventaId: ventaId));
      aviso = hecho.fold(
        (_) => null,
        (r) => r.entrega.yaEstaba
            ? TextosEntregaDiferida.yaEstabaEntregada
            : TextosEntregaDiferida.entregaMarcada,
      );
    } on Object {
      // Sin base abierta o cualquier falla inesperada: no se marcó nada y se puede reintentar.
      aviso = null;
    }
    if (!mounted) return;
    setState(() {
      _entregando = false;
      _fallaAlEntregar = aviso == null;
    });
    if (aviso == null) return;
    ref.invalidate(detalleDeAgendaProvider(widget.agendaId));
    mensajero
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(aviso)));
  }

  Future<void> _registrar(DetalleDeAgenda detalle, String ubicacionId) async {
    final destino = ref.read(registrarVisitaDesdeLaCasaProvider);
    if (destino == null || _abriendo) return;
    _abriendo = true;
    final mensajero = ScaffoldMessenger.maybeOf(context);
    try {
      await destino((
        ubicacionId: ubicacionId,
        espacioId: detalle.agenda.espacioId,
        // El id de ESTA agenda: sin él el flujo tomaría «la programada más antigua» de la casa.
        agendaId: detalle.agenda.id,
      ));
    } on Object {
      mensajero?.showSnackBar(const SnackBar(content: Text(TextosAgenda.noPudimosAbrir)));
    } finally {
      _abriendo = false;
    }
    if (mounted) ref.invalidate(detalleDeAgendaProvider(widget.agendaId));
  }

  /// La agenda se canceló (23C·05): el detalle se cierra y la lista —que lee en vivo— ya no la
  /// muestra entre las pendientes; el aviso «Agenda cancelada.» lo pone el enlace. Si el detalle no
  /// se pudiera cerrar, queda con la agenda ya cancelada.
  void _alCancelar(ResultadoCancelarAgenda _) {
    ref.invalidate(detalleDeAgendaProvider(widget.agendaId));
    unawaited(Navigator.of(context).maybePop());
  }

  /// La hoja de cancelar se cerró sin cancelar: la agenda pudo cumplirse mientras estaba abierta
  /// (23C·06), así que se vuelve a leer.
  void _alVolverSinCancelar() => ref.invalidate(detalleDeAgendaProvider(widget.agendaId));

  @override
  Widget build(BuildContext context) {
    final detalle = ref.watch(detalleDeAgendaProvider(widget.agendaId));
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: IconButton(
                  key: ClavesDetalleAgenda.volver,
                  tooltip: TextosDetalleAgenda.volver,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
            ),
            Expanded(
              child: detalle.when(
                skipLoadingOnReload: true,
                loading: () => const _Cargando(),
                error: (_, _) => _ConAviso(
                  texto: TextosDetalleAgenda.noPudimosLeer,
                  alReintentar: () => ref.invalidate(detalleDeAgendaProvider(widget.agendaId)),
                ),
                data: (d) => d == null
                    ? const _ConAviso(texto: TextosDetalleAgenda.noEstaMas)
                    : _Cuerpo(
                        detalle: d,
                        alModificar: () => unawaited(_modificar(d)),
                        alVerLasCuotas: () => unawaited(_verLasCuotas(d)),
                        alRegistrar: (ubicacionId) => unawaited(_registrar(d, ubicacionId)),
                        alEntregadoHoy: () => unawaited(_entregadoHoy(d)),
                        entregando: _entregando,
                        fallaAlEntregar: _fallaAlEntregar,
                        alCancelar: _alCancelar,
                        alVolverSinCancelar: _alVolverSinCancelar,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Las claves del detalle, para los tests.
abstract final class ClavesDetalleAgenda {
  static const volver = Key('detalle_agenda_volver');
  static const titulo = Key('detalle_agenda_titulo');
  static const cargando = Key('detalle_agenda_cargando');
  static const aviso = Key('detalle_agenda_aviso');
  static const reintentar = Key('detalle_agenda_reintentar');
  static const registrar = Key('detalle_agenda_registrar');
  static const entregadoHoy = Key('detalle_agenda_entregado_hoy');
  static const avisoEntrega = Key('detalle_agenda_aviso_entrega');
  static const avisoCasa = Key('detalle_agenda_aviso_casa');
  static const modificar = Key('detalle_agenda_modificar');
  static const avisoCerrada = Key('detalle_agenda_aviso_cerrada');
  static const estado = Key('detalle_agenda_estado');
  static const cuando = Key('detalle_agenda_cuando');
  static const franja = Key('detalle_agenda_franja');
  static const recordatorio = Key('detalle_agenda_recordatorio');
  static const nota = Key('detalle_agenda_nota');
  static const verLasCuotas = Key('detalle_agenda_ver_cuotas');
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: TextosDetalleAgenda.cargando,
      child: const Padding(
        key: ClavesDetalleAgenda.cargando,
        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
        ),
      ),
    );
  }
}

/// Un aviso a pantalla (error al leer o agenda que ya no está), con «Reintentar» si hay a dónde.
class _ConAviso extends StatelessWidget {
  const _ConAviso({required this.texto, this.alReintentar});

  final String texto;
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: KeyedSubtree(
        key: ClavesDetalleAgenda.aviso,
        child: AvisoAlta(
          color: ColoresAlta.rojo,
          glyph: '!',
          texto: texto,
          acciones: alReintentar == null
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: EnlaceAlta(
                    key: ClavesDetalleAgenda.reintentar,
                    texto: TextosDetalleAgenda.reintentar,
                    alPresionar: alReintentar,
                  ),
                ),
        ),
      ),
    );
  }
}

class _Cuerpo extends ConsumerWidget {
  const _Cuerpo({
    required this.detalle,
    required this.alModificar,
    required this.alVerLasCuotas,
    required this.alRegistrar,
    required this.alEntregadoHoy,
    required this.entregando,
    required this.fallaAlEntregar,
    required this.alCancelar,
    required this.alVolverSinCancelar,
  });

  final DetalleDeAgenda detalle;
  final VoidCallback alModificar;
  final VoidCallback alVerLasCuotas;
  final ValueChanged<String> alRegistrar;
  final VoidCallback alEntregadoHoy;

  /// Hay un «Entregado hoy» en curso: el botón no responde y lo dice con una ruedita.
  final bool entregando;

  /// El último «Entregado hoy» no se pudo guardar (aviso fijo arriba).
  final bool fallaAlEntregar;
  final ValueChanged<ResultadoCancelarAgenda> alCancelar;
  final VoidCallback alVolverSinCancelar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final agenda = detalle.agenda;
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    final casa = ref.watch(contextoEspacioProvider(agenda.espacioId));
    final contexto = casa.asData?.value;
    final personas = agenda.espacioPersonaId == null
        ? null
        : ref.watch(personasDelEspacioProvider(agenda.espacioId)).asData?.value;
    final preferencias = ref.watch(preferenciasDelAvisoProvider).asData?.value;
    final reloj = ref.watch(relojVisitaProvider);
    final programada = agenda.estado == EstadoAgenda.programada;
    final registrarEnganche = ref.watch(registrarVisitaDesdeLaCasaProvider);
    // Una cita de ENTREGA no se cierra con «Registrar resultado» (abriría «¿Qué pasó?» de una visita y
    // dejaría la entrega pendiente sin cita): su lugar lo toma «Entregado hoy».
    final esEntrega = agenda.tipo == TipoAgenda.entrega;
    final registrar = esEntrega ? null : registrarEnganche;
    final ubicacionId = contexto?.ubicacion.id;

    final subtitulo = _subtitulo(contexto, _persona(personas, agenda.espacioPersonaId));
    final estado = _estado(detalle);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fallaAlEntregar && esEntrega && programada) ...[
            Semantics(
              liveRegion: true,
              child: const KeyedSubtree(
                key: ClavesDetalleAgenda.avisoEntrega,
                child: AvisoAlta(
                  color: ColoresAlta.rojo,
                  glyph: '!',
                  texto: TextosEntregaDiferida.noPudimosMarcar,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            TextosDetalleAgenda.rotulo,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 10,
              letterSpacing: 1.6,
              color: ColoresAlta.gris,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            header: true,
            child: Text(
              TextosDetalleAgenda.tipo(agenda.tipo),
              key: ClavesDetalleAgenda.titulo,
              style: theme.textTheme.headlineSmall,
            ),
          ),
          if (subtitulo.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subtitulo, style: theme.textTheme.bodyMedium?.copyWith(color: gris)),
          ],
          const SizedBox(height: 16),
          if (!programada) ...[
            KeyedSubtree(
              key: ClavesDetalleAgenda.avisoCerrada,
              child: AvisoAlta(
                color: ColoresAlta.azul,
                glyph: 'i',
                texto: agenda.estado == EstadoAgenda.cancelada
                    ? TextosDetalleAgenda.estaCancelada
                    : TextosDetalleAgenda.yaTieneResultado,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _FilaDato(
            clave: ClavesDetalleAgenda.estado,
            etiqueta: TextosDetalleAgenda.etiquetaEstado,
            valor: estado.texto,
            color: estado.color,
            negrita: true,
          ),
          _FilaDato(
            clave: ClavesDetalleAgenda.cuando,
            etiqueta: TextosDetalleAgenda.etiquetaCuando,
            valor: FormatoDetalleAgenda.cuando(agenda.fechaProgramada.toLocal()),
          ),
          _FilaDato(
            clave: ClavesDetalleAgenda.franja,
            etiqueta: TextosDetalleAgenda.etiquetaFranja,
            valor: _franja(agenda.slotCodigo),
          ),
          _FilaDato(
            clave: ClavesDetalleAgenda.recordatorio,
            etiqueta: TextosDetalleAgenda.etiquetaRecordatorio,
            valor: programada
                ? FormatoDetalleAgenda.recordatorio(
                    visita: agenda.fechaProgramada.toLocal(),
                    ahora: reloj(),
                    preferencias: preferencias,
                  )
                : TextosDetalleAgenda.sinValor,
          ),
          _FilaDato(
            clave: ClavesDetalleAgenda.nota,
            etiqueta: TextosDetalleAgenda.etiquetaNota,
            valor: _nota(detalle.nota),
            ultima: true,
          ),
          if (agenda.esCuota)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: ClavesDetalleAgenda.verLasCuotas,
                onPressed: alVerLasCuotas,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text(
                  TextosCuotas.verLasCuotas,
                  style: TextStyle(fontWeight: FontWeight.w600, color: ColoresAlta.azul),
                ),
              ),
            ),
          if (programada) ...[
            const SizedBox(height: 24),
            // Sin la casa «Registrar resultado» queda apagado: se dice por qué y, si se puede, se
            // ofrece volver a leerla (QA #409).
            if (registrar != null && (casa.hasError || (casa.hasValue && contexto == null))) ...[
              KeyedSubtree(
                key: ClavesDetalleAgenda.avisoCasa,
                child: AvisoAlta(
                  color: ColoresAlta.rojo,
                  glyph: '!',
                  texto: casa.hasError
                      ? TextosDetalleAgenda.noPudimosLeerLaCasa
                      : TextosAgendarVisita.casaNoEstaMas,
                  acciones: casa.hasError
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: EnlaceAlta(
                            key: ClavesDetalleAgenda.reintentar,
                            texto: TextosDetalleAgenda.reintentar,
                            alPresionar: () =>
                                ref.invalidate(contextoEspacioProvider(agenda.espacioId)),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (registrar != null)
              FilledButton(
                key: ClavesDetalleAgenda.registrar,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: ubicacionId == null ? null : () => alRegistrar(ubicacionId),
                child: const Text(TextosDetalleAgenda.registrarResultado),
              ),
            if (registrar != null) const SizedBox(height: 10),
            if (esEntrega && agenda.ventaId != null) ...[
              FilledButton(
                key: ClavesDetalleAgenda.entregadoHoy,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: entregando ? null : alEntregadoHoy,
                child: entregando
                    ? Semantics(
                        label: TextosEntregaDiferida.marcando,
                        child: const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : const Text(TextosEntregaDiferida.entregadoHoy),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton(
              key: ClavesDetalleAgenda.modificar,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: alModificar,
              child: const Text(TextosDetalleAgenda.modificar),
            ),
            const SizedBox(height: 16),
            EnlaceCancelarAgenda(
              agendaId: agenda.id,
              tipo: agenda.tipo,
              estado: agenda.estado,
              alCancelar: alCancelar,
              alVolverSinCancelar: alVolverSinCancelar,
            ),
          ],
        ],
      ),
    );
  }

  static PersonaDelEspacio? _persona(List<PersonaDelEspacio>? lista, String? vinculoId) {
    if (lista == null || vinculoId == null) return null;
    for (final p in lista) {
      if (p.vinculo.id == vinculoId) return p;
    }
    return null;
  }

  /// «María Fernández · Mataojo 2044 · Depto 3B»: sin persona, solo el lugar; sin lugar, solo la
  /// persona.
  static String _subtitulo(EspacioConUbicacion? lugar, PersonaDelEspacio? persona) {
    final nombre = persona == null
        ? ''
        : '${persona.persona.nombre} ${persona.persona.apellido}'.trim();
    final donde = lugar == null
        ? ''
        : FormatoPersonas.dondeEstaElEspacio(lugar.espacio, lugar.ubicacion);
    return [nombre, donde].where((t) => t.isNotEmpty).join(' · ');
  }

  static ({String texto, Color? color}) _estado(DetalleDeAgenda d) {
    final resultado = d.visita == null
        ? null
        : TextosDetalleAgenda.resultado(d.visita!.tipoResultado);
    return switch (d.agenda.estado) {
      EstadoAgenda.programada => (texto: TextosDetalleAgenda.programada, color: null),
      EstadoAgenda.cumplida => (
        texto: resultado == null
            ? TextosDetalleAgenda.cumplida
            : '${TextosDetalleAgenda.cumplida} · $resultado',
        color: ColoresAlta.verde,
      ),
      EstadoAgenda.noCumplida => (
        texto: resultado == null
            ? TextosDetalleAgenda.noCumplida
            : '${TextosDetalleAgenda.noCumplida} · $resultado',
        color: null,
      ),
      EstadoAgenda.cancelada => (texto: TextosDetalleAgenda.cancelada, color: null),
    };
  }

  static String _franja(String? codigo) {
    final franja = FranjaHoraria.desdeCodigo(codigo);
    return franja == null ? TextosDetalleAgenda.sinFranja : TextosDetalleAgenda.franja(franja);
  }

  static String _nota(String? nota) {
    final texto = nota?.trim() ?? '';
    return texto.isEmpty ? TextosDetalleAgenda.sinNota : texto;
  }
}

/// Un renglón «etiqueta / valor» del detalle. Con el texto grande (más de 1,4×) la etiqueta pasa
/// arriba del valor, para que ninguno de los dos se parta renglón por renglón.
class _FilaDato extends StatelessWidget {
  const _FilaDato({
    required this.clave,
    required this.etiqueta,
    required this.valor,
    this.color,
    this.negrita = false,
    this.ultima = false,
  });

  final Key clave;
  final String etiqueta;
  final String valor;
  final Color? color;
  final bool negrita;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    final apilado = MediaQuery.textScalerOf(context).scale(14) > 20;
    final estiloEtiqueta = theme.textTheme.bodyMedium?.copyWith(color: gris);
    final estiloValor = theme.textTheme.bodyMedium?.copyWith(
      color: color ?? ColoresAlta.tinta,
      fontWeight: negrita ? FontWeight.w600 : FontWeight.w400,
    );
    return MergeSemantics(
      child: Container(
        key: clave,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: ultima ? null : const Border(bottom: BorderSide(color: ColoresAlta.grisBorde)),
        ),
        child: apilado
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiqueta, style: estiloEtiqueta),
                  const SizedBox(height: 2),
                  Text(valor, style: estiloValor),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: Text(etiqueta, style: estiloEtiqueta)),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Text(valor, textAlign: TextAlign.end, style: estiloValor),
                  ),
                ],
              ),
      ),
    );
  }
}
