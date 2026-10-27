import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../mapa/domain/entities/persona_del_espacio.dart';
import '../../../mapa/domain/repositories/espacio_repository.dart';
import '../../../mapa/presentation/providers/hoja_casa_providers.dart'
    show registrarVisitaDesdeLaCasaProvider;
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../../mapa/presentation/textos_personas.dart';
import '../../../mapa/presentation/widgets/piezas_alta.dart';
import '../../domain/entities/detalle_de_agenda.dart';
import '../../domain/entities/estado_agenda.dart';
import '../../domain/entities/franja_horaria.dart';
import '../formato_agenda.dart' show TextosAgenda;
import '../formato_detalle_agenda.dart';
import '../providers/agenda_providers.dart';
import '../providers/detalle_agenda_providers.dart';
import '../textos_detalle_agenda.dart';
import '../widgets/enlace_cancelar_agenda.dart';
import 'modificar_agenda_page.dart';

/// El detalle de una agenda (vista 23, 23C·01, 23C·03 y 23C·06, HU-VIS-003): qué es, con quién, cuándo
/// y a qué hora suena el recordatorio, y las salidas.
///
/// - **Programada** (23C·01): «Registrar resultado» lleva a «¿Qué pasó?» de la vista 39 con la casa y
///   la agenda ya puestas; «Modificar» abre 23C·02; «Cancelar agenda» va como enlace al pie.
/// - **Modificada** (23C·03): al volver de «Modificar», el detalle ya muestra lo nuevo y el aviso de éxito
///   («Guardado. El recordatorio pasó a las 10:00.») queda en pantalla.
/// - **Cumplida o no cumplida** (23C·06): el aviso «Esta visita ya tiene resultado…» y ninguna salida.
/// - **Cancelada**: el mismo criterio con su propio aviso (el canvas no la dibuja).
/// - Cargando, error al leer («Reintentar») y agenda que ya no está en el teléfono.
///
/// Todo se lee del teléfono: sin conexión funciona igual.
class DetalleAgendaPage extends ConsumerStatefulWidget {
  const DetalleAgendaPage({super.key, required this.agendaId, required this.colportorId});

  /// El `agenda.id` que se muestra.
  final String agendaId;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  /// Abre el detalle encima de la pantalla actual.
  static Future<void> abrir(
    BuildContext context, {
    required String agendaId,
    required String colportorId,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => DetalleAgendaPage(agendaId: agendaId, colportorId: colportorId),
    ),
  );

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
                        alRegistrar: (ubicacionId) => unawaited(_registrar(d, ubicacionId)),
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
  static const modificar = Key('detalle_agenda_modificar');
  static const avisoCerrada = Key('detalle_agenda_aviso_cerrada');
  static const estado = Key('detalle_agenda_estado');
  static const cuando = Key('detalle_agenda_cuando');
  static const franja = Key('detalle_agenda_franja');
  static const recordatorio = Key('detalle_agenda_recordatorio');
  static const nota = Key('detalle_agenda_nota');
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
  const _Cuerpo({required this.detalle, required this.alModificar, required this.alRegistrar});

  final DetalleDeAgenda detalle;
  final VoidCallback alModificar;
  final ValueChanged<String> alRegistrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final agenda = detalle.agenda;
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    final contexto = ref.watch(contextoEspacioProvider(agenda.espacioId)).asData?.value;
    final personas = agenda.espacioPersonaId == null
        ? null
        : ref.watch(personasDelEspacioProvider(agenda.espacioId)).asData?.value;
    final preferencias = ref.watch(preferenciasDelAvisoProvider).asData?.value;
    final reloj = ref.watch(relojVisitaProvider);
    final programada = agenda.estado == EstadoAgenda.programada;
    final registrar = ref.watch(registrarVisitaDesdeLaCasaProvider);
    final ubicacionId = contexto?.ubicacion.id;

    final subtitulo = _subtitulo(contexto, _persona(personas, agenda.espacioPersonaId));
    final estado = _estado(detalle);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          if (programada) ...[
            const SizedBox(height: 24),
            if (registrar != null)
              FilledButton(
                key: ClavesDetalleAgenda.registrar,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: ubicacionId == null ? null : () => alRegistrar(ubicacionId),
                child: const Text(TextosDetalleAgenda.registrarResultado),
              ),
            if (registrar != null) const SizedBox(height: 10),
            OutlinedButton(
              key: ClavesDetalleAgenda.modificar,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: alModificar,
              child: const Text(TextosDetalleAgenda.modificar),
            ),
            const SizedBox(height: 16),
            EnlaceCancelarAgenda(agendaId: agenda.id, tipo: agenda.tipo, estado: agenda.estado),
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
