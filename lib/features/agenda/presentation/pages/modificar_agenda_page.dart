import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/instante.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../mapa/domain/entities/persona_del_espacio.dart';
import '../../../mapa/domain/entities/ubicacion.dart';
import '../../../mapa/domain/repositories/espacio_repository.dart';
import '../../../mapa/presentation/formato_ubicaciones.dart';
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../../mapa/presentation/textos_personas.dart';
import '../../../mapa/presentation/widgets/piezas_alta.dart';
import '../../../mapa/presentation/widgets/piezas_persona.dart';
import '../../../notificaciones/domain/entities/preferencias_recordatorios.dart';
import '../../../notificaciones/presentation/providers/preferencias_recordatorios_providers.dart';
import '../../domain/entities/anticipacion_recordatorio.dart';
import '../../domain/entities/detalle_de_agenda.dart';
import '../../domain/entities/franja_horaria.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/services/recordatorios.dart';
import '../../domain/usecases/modificar_agenda_use_case.dart';
import '../formato_agendar_visita.dart';
import '../formato_detalle_agenda.dart';
import '../providers/agenda_providers.dart';
import '../providers/detalle_agenda_providers.dart';
import '../providers/recordatorios_providers.dart';
import '../textos_agendar_visita.dart';
import '../textos_detalle_agenda.dart';
import '../widgets/piezas_agendar_visita.dart';

/// Lo que devuelve [ModificarAgendaPage] al guardar: el aviso de éxito que corresponde mostrar
/// (23C·03: «Guardado. El recordatorio pasó a las 10:00.»).
typedef ModificacionGuardada = ({AgendaModificada resultado, String aviso});

/// Las claves de «Modificar agenda», para los tests.
abstract final class ClavesModificarAgenda {
  static const cerrar = Key('modificar_agenda_cerrar');
  static const titulo = Key('modificar_agenda_titulo');
  static const guardar = Key('modificar_agenda_guardar');
  static const avisoFalla = Key('modificar_agenda_aviso_falla');
  static const textoRecordatorio = Key('modificar_agenda_texto_recordatorio');
  static const avisoCasa = Key('modificar_agenda_aviso_casa');
}

/// «Modificar agenda» (vista 23, 23C·02, 23C·03 y 23C·07, HU-VIS-003): cambiar el tipo, el día y la
/// hora, la franja y la nota de una agenda **programada**. Se abre desde el detalle con la agenda y su
/// nota ya leídas; no las vuelve a pedir.
///
/// - **Reprogramamos** (23C·02): debajo del formulario dice a qué hora quedará el recordatorio.
/// - **Hora que ya pasó**: igual que al agendar, el campo se marca y, al guardar, una hoja pide
///   confirmar («Guardar igual»; no hay recordatorio). Una agenda que ya estaba vencida y no cambia de
///   hora no vuelve a preguntar.
/// - **Guardando**: el botón no admite otro toque y la pantalla no se cierra. El id de la nota se
///   genera una vez por formulario: un doble toque o un «Reintentar» no la duplican.
/// - **Error al guardar** (23C·07): el formulario conserva lo escrito y el botón pasa a «Reintentar».
///   Si la agenda ya no se puede modificar (se cumplió o se canceló mientras tanto), el aviso dice por
///   qué.
/// - **Sin conexión**: no hay estado propio. Todo es local.
///
/// Devuelve una [ModificacionGuardada], o `null` si se cerró sin guardar.
class ModificarAgendaPage extends ConsumerStatefulWidget {
  const ModificarAgendaPage({super.key, required this.detalle, required this.colportorId});

  /// La agenda que se modifica, con su nota.
  final DetalleDeAgenda detalle;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  /// Abre la pantalla encima de la actual.
  static Future<ModificacionGuardada?> abrir(
    BuildContext context, {
    required DetalleDeAgenda detalle,
    required String colportorId,
  }) => Navigator.of(context).push<ModificacionGuardada>(
    MaterialPageRoute(
      builder: (_) => ModificarAgendaPage(detalle: detalle, colportorId: colportorId),
    ),
  );

  @override
  ConsumerState<ModificarAgendaPage> createState() => _ModificarAgendaPageState();
}

class _ModificarAgendaPageState extends ConsumerState<ModificarAgendaPage> {
  late final TextEditingController _nota;
  final _focoNota = FocusNode();

  late TipoAgenda _tipo;
  late DateTime _cuando;
  FranjaHoraria? _franja;

  /// La persona eligió (o sacó) la franja a mano: de ahí en más la hora no la cambia sola.
  var _franjaAMano = false;

  /// Hay un guardado en curso: no admite otro toque, no deja salir y bloquea los campos.
  var _enviando = false;

  /// La última falla al guardar (23C·07); `null` si no hay.
  Failure? _falla;

  /// La hora que la persona ya confirmó con «Guardar igual».
  DateTime? _horaConfirmada;

  /// El id de la nota, creado con el primer intento y repetido en los siguientes.
  String? _idNota;

  /// Las preferencias de los recordatorios; `null` hasta leerlas (se usan los valores de fábrica).
  PreferenciasRecordatorios? _preferencias;

  bool? _puedeAvisar;

  @override
  void initState() {
    super.initState();
    final agenda = widget.detalle.agenda;
    _tipo = agenda.tipo;
    _cuando = agenda.fechaProgramada.toLocal();
    _franja = FranjaHoraria.desdeCodigo(agenda.slotCodigo);
    _nota = TextEditingController(text: widget.detalle.nota ?? '');
    unawaited(_leerAvisos());
  }

  @override
  void dispose() {
    _nota.dispose();
    _focoNota.dispose();
    super.dispose();
  }

  Future<void> _leerAvisos() async {
    bool puede;
    try {
      puede = await ref.read(recordatoriosProvider).puedeAvisar();
    } on Object {
      puede = false;
    }
    PreferenciasRecordatorios? preferencias;
    try {
      preferencias = await ref.read(preferenciasRecordatoriosRepositoryProvider).leer();
    } on Object {
      preferencias = null;
    }
    if (!mounted) return;
    setState(() {
      _puedeAvisar = puede;
      _preferencias = preferencias ?? _preferencias;
    });
  }

  DateTime _ahora() => ref.read(relojVisitaProvider)();

  int get _minutosDeAnticipacion => AnticipacionRecordatorio.acotar(
    _preferencias?.anticipacionMinutos ?? AnticipacionRecordatorio.porDefecto,
  );

  bool get _recordatoriosPrendidos => _preferencias?.activados ?? true;

  /// La hora elegida ya pasó (se compara al minuto: elegir el minuto en curso no es «pasada»).
  bool get _horaPasada {
    final ahora = _ahora();
    final alMinuto = DateTime(ahora.year, ahora.month, ahora.day, ahora.hour, ahora.minute);
    return _cuando.isBefore(alMinuto);
  }

  /// La hora no cambió respecto de lo guardado: una agenda vencida que solo cambia de tipo o de nota
  /// no tiene por qué volver a preguntar por la hora.
  bool get _horaIgual => instanteMs(_cuando) == widget.detalle.agenda.fechaProgramada;

  Future<void> _elegirDiaYHora() async {
    if (_enviando) return;
    final elegido = await mostrarHojaDiaYHora(context, inicial: _cuando, ahora: _ahora());
    if (elegido == null || !mounted) return;
    setState(() {
      _cuando = elegido;
      if (!_franjaAMano) _franja = FranjaHoraria.sugeridaPara(elegido.hour * 60 + elegido.minute);
    });
  }

  void _elegirFranja(FranjaHoraria f) => setState(() {
    _franjaAMano = true;
    _franja = f == _franja ? null : f;
  });

  Future<void> _guardar({bool confirmoHoraPasada = false}) async {
    // El primer renglón de la defensa contra el doble toque: la bandera se levanta antes de cualquier
    // `await`, así que el segundo toque ya la ve.
    if (_enviando) return;
    if (confirmoHoraPasada) _horaConfirmada = _cuando;
    setState(() {
      _enviando = true;
      _falla = null;
    });
    Failure? falla;
    ResultadoModificar? resultado;
    try {
      final contexto = ref
          .read(contextoEspacioProvider(widget.detalle.agenda.espacioId))
          .asData
          ?.value;
      final respuesta = await ref.read(modificarAgendaUseCaseProvider)(
        ModificarAgendaParams(
          agendaId: widget.detalle.agenda.id,
          idNota: _idNota ??= ref.read(generadorIdVisitaProvider)(),
          tipo: _tipo,
          fechaProgramada: _cuando,
          franja: _franja,
          nota: _nota.text,
          direccion: contexto == null ? '' : _direccionDelAviso(contexto),
          confirmoHoraPasada: confirmoHoraPasada || _horaConfirmada == _cuando,
        ),
      );
      respuesta.fold((f) => falla = f, (r) => resultado = r);
    } on Object catch (e) {
      // Nada de `e` al mensaje: puede traer lo escrito (convenciones §7.5).
      falla = FailureInesperado(causa: e.runtimeType.toString());
    }
    if (!mounted) return;
    final r = resultado;
    switch (r) {
      case AgendaModificada():
        Navigator.of(context).pop<ModificacionGuardada>((resultado: r, aviso: _avisoDeExito(r)));
      case HoraPasadaSinConfirmarAlModificar(:final ahora):
        setState(() => _enviando = false);
        await _preguntarPorLaHoraPasada(ahora);
      case null:
        setState(() {
          _enviando = false;
          _falla = falla ?? const FailureInesperado();
        });
    }
  }

  /// «Av. Italia 1234», con el depto si es un edificio: lo que lleva el aviso de la visita. Nunca el
  /// nombre de la persona.
  static String _direccionDelAviso(EspacioConUbicacion lugar) {
    final propia = FormatoUbicaciones.direccionPropia(lugar.ubicacion);
    if (lugar.ubicacion.tipo != TipoUbicacion.edificio) return propia;
    final depto = lugar.espacio.numeroDepto?.trim() ?? '';
    if (depto.isEmpty) return propia;
    return propia.isEmpty ? 'Depto $depto' : '$propia · Depto $depto';
  }

  Future<void> _preguntarPorLaHoraPasada(DateTime ahora) async {
    final texto = TextosDetalleAgenda.horaPasadaTexto(
      FormatoAgendarVisita.cuandoEnFrase(_cuando, ahora),
      FormatoAgendarVisita.hora(ahora),
    );
    final decision = await mostrarHojaHoraPasada(
      context,
      texto: texto,
      confirmar: TextosDetalleAgenda.guardarIgual,
    );
    if (!mounted) return;
    if (decision == true) {
      await _guardar(confirmoHoraPasada: true);
    } else if (decision == false) {
      await _elegirDiaYHora();
    }
  }

  /// Lo que dice el aviso de éxito (23C·03), según qué pasó con el recordatorio.
  String _avisoDeExito(AgendaModificada r) => switch (r.recordatorio) {
    null => TextosDetalleAgenda.guardadoSinAvisoHoraPasada,
    ResultadoRecordatorio.programado => _guardadoConHora(r),
    ResultadoRecordatorio.sinPermiso => TextosDetalleAgenda.guardadoSinPermiso,
    ResultadoRecordatorio.yaPaso => TextosDetalleAgenda.guardadoSinTiempoDeAviso(
      _minutosDeAnticipacion,
    ),
    ResultadoRecordatorio.apagados => TextosDetalleAgenda.guardadoConRecordatoriosApagados,
    ResultadoRecordatorio.noSePudo => TextosDetalleAgenda.guardadoSinAviso,
  };

  /// «Guardado. El recordatorio pasó a las 10:00.»: la hora real del aviso, no la de la visita.
  String _guardadoConHora(AgendaModificada r) {
    final visita = r.agenda.fechaProgramada.toLocal();
    final aviso = FormatoDetalleAgenda.avisoEnFrase(
      FormatoDetalleAgenda.horaDelAviso(visita, _minutosDeAnticipacion),
      visita,
    );
    final dia = aviso.dia;
    return dia == null
        ? TextosDetalleAgenda.guardado(aviso.hora)
        : TextosDetalleAgenda.guardadoOtroDia(dia, aviso.hora);
  }

  String get _textoFalla {
    final f = _falla;
    if (f is FailureValidacion) {
      final texto = f.campos['agenda'];
      if (texto != null) return texto;
    }
    return TextosDetalleAgenda.noPudimosGuardar;
  }

  /// El texto de debajo del formulario: qué pasa con el recordatorio.
  String get _textoRecordatorio {
    if (_horaPasada) return TextosDetalleAgenda.horaPasadaSinRecordatorio;
    if (_puedeAvisar == false) return '';
    if (!_recordatoriosPrendidos) return TextosDetalleAgenda.recordatoriosApagados;
    final aviso = FormatoDetalleAgenda.horaDelAviso(_cuando, _minutosDeAnticipacion);
    if (!aviso.isAfter(_ahora())) {
      return TextosDetalleAgenda.sinTiempoDeAviso(_minutosDeAnticipacion);
    }
    final frase = FormatoDetalleAgenda.avisoEnFrase(aviso, _cuando);
    final dia = frase.dia;
    return dia == null
        ? TextosDetalleAgenda.reprogramamos(frase.hora)
        : TextosDetalleAgenda.reprogramamosOtroDia(dia, frase.hora);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    final agenda = widget.detalle.agenda;
    final contexto = ref.watch(contextoEspacioProvider(agenda.espacioId));
    final personas = agenda.espacioPersonaId == null
        ? null
        : ref.watch(personasDelEspacioProvider(agenda.espacioId));
    final conFalla = _falla != null;
    // El aviso lleva la dirección: mientras la casa se lee (o si no se pudo leer) no se guarda, para no
    // dejar un recordatorio sin ella. Una casa que ya no está sí deja guardar: la agenda sigue ahí.
    final esperaLaCasa = contexto.isLoading || contexto.hasError;
    final textoRecordatorio = _textoRecordatorio;

    return PopScope(
      // Mientras se guarda no se sale: el resultado se perdería.
      canPop: !_enviando,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: IconButton(
                    key: ClavesModificarAgenda.cerrar,
                    tooltip: TextosAgendarVisita.cerrar,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: _enviando ? null : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        TextosDetalleAgenda.modificarRotulo,
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
                          TextosDetalleAgenda.modificarTitulo,
                          key: ClavesModificarAgenda.titulo,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _tarjeta(contexto, personas),
                      if (contexto.hasError) ...[
                        const SizedBox(height: 12),
                        KeyedSubtree(
                          key: ClavesModificarAgenda.avisoCasa,
                          child: AvisoAlta(
                            color: ColoresAlta.rojo,
                            glyph: '!',
                            texto: TextosDetalleAgenda.noPudimosLeerLaCasa,
                            acciones: EnlaceAlta(
                              texto: TextosAgendarVisita.reintentar,
                              alPresionar: () =>
                                  ref.invalidate(contextoEspacioProvider(agenda.espacioId)),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SelectorTipoAgenda(
                        tipo: _tipo,
                        bloqueado: _enviando,
                        alCambiar: (t) => setState(() => _tipo = t),
                      ),
                      if (conFalla) ...[
                        const SizedBox(height: 16),
                        KeyedSubtree(
                          key: ClavesModificarAgenda.avisoFalla,
                          child: AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: _textoFalla),
                        ),
                      ],
                      const SizedBox(height: 16),
                      CampoDiaYHora(
                        valor: FormatoAgendarVisita.cuando(_cuando, _ahora()),
                        alTocar: _enviando ? null : () => unawaited(_elegirDiaYHora()),
                        // Una agenda vencida que no cambia de hora no se marca: no hay nada que corregir.
                        error: _horaPasada && !_horaIgual
                            ? TextosAgendarVisita.horaPasadaCorta
                            : null,
                      ),
                      const SizedBox(height: 16),
                      ChipsFranja(elegida: _franja, bloqueado: _enviando, alElegir: _elegirFranja),
                      const SizedBox(height: 16),
                      CampoPersona(
                        etiqueta: TextosAgendarVisita.etiquetaNota,
                        sugerencia: TextosAgendarVisita.sugerenciaNota,
                        controlador: _nota,
                        foco: _focoNota,
                        bloqueado: _enviando,
                        limite: 500,
                        capitalizacion: TextCapitalization.sentences,
                        teclado: TextInputType.multiline,
                        accion: TextInputAction.newline,
                        renglones: 3,
                      ),
                      if (textoRecordatorio.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          textoRecordatorio,
                          key: ClavesModificarAgenda.textoRecordatorio,
                          style: theme.textTheme.bodySmall?.copyWith(color: gris, fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Semantics(
                  hint: esperaLaCasa ? TextosDetalleAgenda.guardarEsperaLaCasa : null,
                  child: BotonAccionPersona(
                    key: ClavesModificarAgenda.guardar,
                    etiqueta: conFalla
                        ? TextosAgendarVisita.reintentar
                        : TextosDetalleAgenda.guardarCambios,
                    etiquetaEnviando: TextosDetalleAgenda.guardando,
                    aspectoApagado: false,
                    habilitado: !esperaLaCasa,
                    enviando: _enviando,
                    alTocar: () => unawaited(_guardar()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjeta(
    AsyncValue<EspacioConUbicacion?> contexto,
    AsyncValue<List<PersonaDelEspacio>>? personas,
  ) {
    final lugar = contexto.asData?.value;
    if (lugar == null) {
      return TarjetaPersonaAgendar(
        iniciales: '',
        titulo: '',
        subtitulo: '',
        cargando: contexto.isLoading,
      );
    }
    final donde = FormatoPersonas.dondeEstaElEspacio(lugar.espacio, lugar.ubicacion);
    var titulo = TextosAgendarVisita.sinPersona;
    var iniciales = '';
    final lista = personas?.asData?.value;
    final vinculoId = widget.detalle.agenda.espacioPersonaId;
    if (vinculoId != null && lista != null) {
      for (final p in lista) {
        if (p.vinculo.id == vinculoId) {
          titulo = '${p.persona.nombre} ${p.persona.apellido}'.trim();
          iniciales = FormatoAgendarVisita.iniciales(p.persona.nombre, p.persona.apellido);
          break;
        }
      }
    }
    return TarjetaPersonaAgendar(
      iniciales: iniciales,
      titulo: titulo,
      subtitulo: donde,
      cargando: vinculoId != null && personas != null && personas.isLoading,
    );
  }
}
