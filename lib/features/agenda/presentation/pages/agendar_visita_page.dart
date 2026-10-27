import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../../notificaciones/domain/entities/estado_notificaciones.dart';
import '../../../notificaciones/domain/entities/preferencias_recordatorios.dart';
import '../../../notificaciones/presentation/providers/notificaciones_providers.dart';
import '../../../notificaciones/presentation/providers/preferencias_recordatorios_providers.dart';
import '../../domain/entities/anticipacion_recordatorio.dart';
import '../../domain/entities/franja_horaria.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/services/recordatorios.dart';
import '../../domain/usecases/agendar_visita_use_case.dart';
import '../formato_agendar_visita.dart';
import '../providers/agenda_providers.dart';
import '../providers/recordatorios_providers.dart';
import '../textos_agendar_visita.dart';
import '../widgets/piezas_agendar_visita.dart';

/// Lo que devuelve [AgendarVisitaPage] al guardar: la agenda y el aviso que corresponde mostrar
/// (23A·05: «Agendada. La casa queda como «Entrevista agendada».»).
typedef AgendaGuardada = ({VisitaAgendada visita, String aviso});

/// «Agendar visita» (vista 23, grupo A, HU-VIS-001, artboards 23A·01 a 23A·08): agendar una entrevista
/// o una cobranza en un día y una hora. Se abre ya con la casa y, si se sabe, la persona resueltas
/// (contrato de navegación de la vista 39); no los vuelve a pedir.
///
/// - **Día y hora** abre la hoja 23A·02. La franja se recomienda según la hora (§8.5.2) y se puede
///   cambiar o sacar.
/// - **Hora que ya pasó** (23A·03): el campo se marca y, al guardar, una hoja pide confirmar. «Agendar
///   igual» guarda sin recordatorio.
/// - **Agendando** (23A·04): el botón no admite otro toque y la pantalla no se cierra. Los ids se
///   generan una vez por formulario: un doble toque o un «Reintentar» no crean dos agendas.
/// - **Error al guardar** (23A·06): el formulario conserva lo escrito y el botón pasa a «Reintentar».
/// - **Sin permiso de notificaciones** (23A·07): la visita se agenda igual; el aviso lo dice y ofrece
///   activarlas.
/// - **Sin conexión** (23A·08): no hay estado propio. Todo es local.
///
/// Devuelve un [AgendaGuardada], o `null` si se cerró sin agendar.
class AgendarVisitaPage extends ConsumerStatefulWidget {
  const AgendarVisitaPage({
    super.key,
    required this.espacioId,
    this.espacioPersonaId,
    required this.colportorId,
    this.tipoInicial = TipoAgenda.entrevista,
  });

  /// La casa o el depto de la visita.
  final String espacioId;

  /// Con quién es, o `null` si queda sin persona (decisión «Sin persona», 23/10).
  final String? espacioPersonaId;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  final TipoAgenda tipoInicial;

  /// Cuántos caracteres admite la nota: un resguardo para que un pegado enorme no trabe el
  /// formulario (a confirmar; la HU no fija un tope).
  static const largoNota = 500;

  /// Abre la pantalla encima de la actual.
  static Future<AgendaGuardada?> abrir(
    BuildContext context, {
    required String espacioId,
    String? espacioPersonaId,
    required String colportorId,
    TipoAgenda tipo = TipoAgenda.entrevista,
  }) => Navigator.of(context).push<AgendaGuardada>(
    MaterialPageRoute(
      builder: (_) => AgendarVisitaPage(
        espacioId: espacioId,
        espacioPersonaId: espacioPersonaId,
        colportorId: colportorId,
        tipoInicial: tipo,
      ),
    ),
  );

  @override
  ConsumerState<AgendarVisitaPage> createState() => _AgendarVisitaPageState();
}

class _AgendarVisitaPageState extends ConsumerState<AgendarVisitaPage> with WidgetsBindingObserver {
  final _nota = TextEditingController();
  final _focoNota = FocusNode();

  late TipoAgenda _tipo = widget.tipoInicial;
  late DateTime _cuando;
  FranjaHoraria? _franja;

  /// La persona eligió (o sacó) la franja a mano: de ahí en más la hora no la cambia sola.
  var _franjaAMano = false;

  /// Hay un guardado en curso: no admite otro toque, no deja salir y bloquea los campos.
  var _enviando = false;

  /// La última falla al guardar (23A·06); `null` si no hay.
  Failure? _falla;

  /// La hora que la persona ya confirmó con «Agendar igual». Mientras no cambien el día ni la hora, un
  /// «Reintentar» tras una falla no vuelve a preguntar; si cambian, la hoja vuelve a aparecer.
  DateTime? _horaConfirmada;

  /// Los ids de la agenda, creados con el primer intento y repetidos en los siguientes.
  IdsAgendarVisita? _ids;

  /// Si el teléfono deja mostrar los avisos (23A·07). `null` hasta saberlo.
  bool? _puedeAvisar;

  /// Las preferencias de los recordatorios; `null` hasta leerlas (se usan los valores de fábrica).
  PreferenciasRecordatorios? _preferencias;

  /// «Activar notificaciones» en curso, y si no se pudo.
  var _activando = false;
  var _falloAlActivar = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final ahora = ref.read(relojVisitaProvider)();
    // Mañana a las 10:00 (media mañana): siempre en el futuro, así que se puede agendar sin tocar nada.
    _cuando = DateTime(ahora.year, ahora.month, ahora.day + 1, 10);
    _franja = FranjaHoraria.sugeridaPara(_cuando.hour * 60 + _cuando.minute);
    unawaited(_leerAvisos());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nota.dispose();
    _focoNota.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Volver de los ajustes del teléfono: las notificaciones pudieron prenderse.
    if (estado == AppLifecycleState.resumed) unawaited(_leerAvisos());
  }

  Future<void> _leerAvisos() async {
    bool puede;
    try {
      puede = await ref.read(recordatoriosProvider).puedeAvisar();
    } on Object {
      // Si no se puede saber, es mejor avisar de más que dejar a alguien sin recordatorio.
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

  Future<void> _activarNotificaciones() async {
    if (_activando) return;
    setState(() {
      _activando = true;
      _falloAlActivar = false;
    });
    var fallo = false;
    try {
      final notificaciones = ref.read(notificacionesProvider.notifier);
      final permiso = ref.read(notificacionesProvider).value?.permiso;
      if (permiso == EstadoPermisoNotificaciones.bloqueadas) {
        fallo = !await notificaciones.abrirAjustes();
      } else {
        fallo = await notificaciones.activar() == ResultadoActivacion.fallo;
      }
    } on Object {
      fallo = true;
    }
    await _leerAvisos();
    if (!mounted) return;
    setState(() {
      _activando = false;
      _falloAlActivar = fallo;
    });
  }

  Future<void> _agendar({bool confirmoHoraPasada = false}) async {
    // El primer renglón de la defensa contra el doble toque: la bandera se levanta antes de cualquier
    // `await`, así que el segundo toque ya la ve.
    if (_enviando) return;
    if (confirmoHoraPasada) _horaConfirmada = _cuando;
    setState(() {
      _enviando = true;
      _falla = null;
    });
    Failure? falla;
    ResultadoAgendar? resultado;
    try {
      final casoDeUso = ref.read(agendarVisitaUseCaseProvider);
      final ids = _ids ??= casoDeUso.nuevosIds();
      final contexto = ref.read(contextoEspacioProvider(widget.espacioId)).asData?.value;
      final respuesta = await casoDeUso(
        AgendarVisitaParams(
          ids: ids,
          espacioId: widget.espacioId,
          espacioPersonaId: widget.espacioPersonaId,
          colportorId: widget.colportorId,
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
      case VisitaAgendada():
        Navigator.of(context).pop<AgendaGuardada>((visita: r, aviso: _avisoDeExito(r)));
      case HoraPasadaSinConfirmar(:final ahora):
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
    final texto = TextosAgendarVisita.horaPasadaTexto(
      FormatoAgendarVisita.cuandoEnFrase(_cuando, ahora),
      FormatoAgendarVisita.hora(ahora),
    );
    final decision = await mostrarHojaHoraPasada(context, texto: texto);
    if (!mounted) return;
    if (decision == true) {
      await _agendar(confirmoHoraPasada: true);
    } else if (decision == false) {
      await _elegirDiaYHora();
    }
  }

  /// Lo que dice el aviso de éxito (23A·05), según qué pasó con el recordatorio.
  String _avisoDeExito(VisitaAgendada r) => switch (r.recordatorio) {
    null => TextosAgendarVisita.agendadaSinAvisoHoraPasada,
    ResultadoRecordatorio.programado => TextosAgendarVisita.agendada(_tipo),
    ResultadoRecordatorio.sinPermiso => TextosAgendarVisita.agendadaSinPermiso,
    ResultadoRecordatorio.yaPaso => TextosAgendarVisita.agendadaSinTiempoDeAviso(
      _minutosDeAnticipacion,
    ),
    ResultadoRecordatorio.apagados => TextosAgendarVisita.agendadaConRecordatoriosApagados,
    ResultadoRecordatorio.noSePudo => TextosAgendarVisita.agendadaSinAviso,
  };

  String get _textoFalla {
    final f = _falla;
    if (f is FailureValidacion) {
      final texto = f.campos['espacio'] ?? f.campos['persona'];
      if (texto != null) return texto;
    }
    return TextosAgendarVisita.noPudimosGuardar;
  }

  /// El texto de debajo del formulario: qué pasa con el recordatorio.
  String get _textoRecordatorio {
    if (_horaPasada) return TextosAgendarVisita.horaPasadaSinRecordatorio;
    if (_puedeAvisar == false) return '';
    if (!_recordatoriosPrendidos) return TextosAgendarVisita.recordatoriosApagados;
    final aviso = _cuando.subtract(Duration(minutes: _minutosDeAnticipacion));
    if (!aviso.isAfter(_ahora())) {
      return TextosAgendarVisita.sinTiempoDeAviso(_minutosDeAnticipacion);
    }
    return TextosAgendarVisita.recordatorio(_minutosDeAnticipacion);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    final contexto = ref.watch(contextoEspacioProvider(widget.espacioId));
    final personas = widget.espacioPersonaId == null
        ? null
        : ref.watch(personasDelEspacioProvider(widget.espacioId));
    final conFalla = _falla != null;
    final casaAusente = contexto.hasValue && contexto.value == null;
    final sinPermiso = _puedeAvisar == false && _recordatoriosPrendidos;
    final bloqueadas =
        ref.watch(notificacionesProvider).value?.permiso == EstadoPermisoNotificaciones.bloqueadas;
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
                    key: ClavesAgendarVisita.cerrar,
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
                        TextosAgendarVisita.rotulo,
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
                          TextosAgendarVisita.titulo,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _tarjeta(contexto, personas),
                      if (contexto.hasError || casaAusente) ...[
                        const SizedBox(height: 12),
                        AvisoAlta(
                          color: ColoresAlta.rojo,
                          glyph: '!',
                          texto: contexto.hasError
                              ? TextosAgendarVisita.noPudimosLeer
                              : TextosAgendarVisita.casaNoEstaMas,
                          acciones: contexto.hasError
                              ? EnlaceAlta(
                                  texto: TextosAgendarVisita.reintentar,
                                  alPresionar: () =>
                                      ref.invalidate(contextoEspacioProvider(widget.espacioId)),
                                )
                              : null,
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
                          key: ClavesAgendarVisita.avisoFalla,
                          child: AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: _textoFalla),
                        ),
                      ],
                      if (sinPermiso) ...[
                        const SizedBox(height: 16),
                        KeyedSubtree(
                          key: ClavesAgendarVisita.avisoSinPermiso,
                          child: AvisoAlta(
                            color: ColoresAlta.ambarBorde,
                            colorInsignia: ColoresAlta.ambar,
                            glyph: '!',
                            texto: _falloAlActivar
                                ? TextosAgendarVisita.noPudimosActivar
                                : TextosAgendarVisita.sinPermiso,
                            acciones: Align(
                              alignment: Alignment.centerLeft,
                              child: EnlaceAlta(
                                key: ClavesAgendarVisita.accionNotificaciones,
                                texto: bloqueadas
                                    ? TextosAgendarVisita.abrirAjustes
                                    : TextosAgendarVisita.activarNotificaciones,
                                alPresionar: _activando
                                    ? null
                                    : () => unawaited(_activarNotificaciones()),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      CampoDiaYHora(
                        valor: FormatoAgendarVisita.cuando(_cuando, _ahora()),
                        alTocar: _enviando ? null : () => unawaited(_elegirDiaYHora()),
                        error: _horaPasada ? TextosAgendarVisita.horaPasadaCorta : null,
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
                        limite: AgendarVisitaPage.largoNota,
                        capitalizacion: TextCapitalization.sentences,
                        teclado: TextInputType.multiline,
                        accion: TextInputAction.newline,
                        renglones: 3,
                      ),
                      if (textoRecordatorio.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          textoRecordatorio,
                          key: ClavesAgendarVisita.textoRecordatorio,
                          style: theme.textTheme.bodySmall?.copyWith(color: gris, fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                // Con la casa ausente no hay nada que agendar: el botón se apaga y el lector de
                // pantalla dice por qué.
                child: Semantics(
                  hint: casaAusente ? TextosAgendarVisita.casaNoEstaMas : null,
                  child: BotonAccionPersona(
                    key: ClavesAgendarVisita.botonAgendar,
                    etiqueta: conFalla
                        ? TextosAgendarVisita.reintentar
                        : TextosAgendarVisita.agendar,
                    etiquetaEnviando: TextosAgendarVisita.agendando,
                    aspectoApagado: false,
                    habilitado: !casaAusente,
                    enviando: _enviando,
                    alTocar: () => unawaited(_agendar()),
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
    String titulo = TextosAgendarVisita.sinPersona;
    var iniciales = '';
    final lista = personas?.asData?.value;
    if (widget.espacioPersonaId != null && lista != null) {
      for (final p in lista) {
        if (p.vinculo.id == widget.espacioPersonaId) {
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
      cargando: widget.espacioPersonaId != null && personas != null && personas.isLoading,
    );
  }
}
