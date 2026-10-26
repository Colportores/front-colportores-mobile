import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/eleccion_de_cita.dart';
import '../../domain/entities/persona.dart';
import '../../domain/entities/persona_de_la_entrevista.dart';
import '../../domain/entities/persona_del_espacio.dart';
import '../../domain/services/validador_persona.dart';
import '../../domain/usecases/registrar_persona_use_case.dart';
import '../../domain/value_objects/paso_con_quien.dart';
import '../pages/alta_persona_page.dart';
import '../providers/personas_providers.dart';
import '../textos_con_quien.dart';
import '../textos_personas.dart';
import 'piezas_alta.dart';
import 'piezas_persona.dart';

/// Cuánto se espera la lectura previa de las personas antes de mostrar la hoja «cargando».
const _esperaPrevia = Duration(milliseconds: 250);

/// Abre el paso «¿Con quién?» de la vista 39 para el espacio [espacioId] (la casa o el depto que se
/// visita) y devuelve con quién es la entrevista, o `null` si la colportora tocó «Volver» o cerró sin
/// elegir (HU-VIS-005, HU-UBI-008; artboards R·04 y C·07). Es el paso que sigue a «Entrevista dada».
///
/// - Sin personas: pide el nombre (el apellido es opcional) y con eso alcanza; la persona se guarda
///   en el teléfono al tocar «Empezar entrevista».
/// - Con una sola: **no muestra nada** y devuelve a esa persona.
/// - Con varias: la lista, y «+ Alguien nuevo» abre el alta de persona (32A) y vuelve acá.
///
/// Todo es local: no hay estado «sin conexión» ni espera de red. [colportorId] es el usuario con la
/// sesión iniciada (`created_by` de la persona nueva).
Future<PersonaDeLaEntrevista?> mostrarHojaConQuien(
  BuildContext context, {
  required String espacioId,
  required String colportorId,
}) async {
  final r = await _abrir(
    context,
    espacioId: espacioId,
    colportorId: colportorId,
    paraProgramar: false,
  );
  return r is PersonaDeLaEntrevista ? r : null;
}

/// El mismo paso para **programar** una entrevista (vista 39, «Programar entrevista» → «¿Con quién es la
/// entrevista?»): devuelve con quién queda la cita, o `null` si la colportora tocó «Volver» o cerró sin
/// elegir. A diferencia de [mostrarHojaConQuien], la cita puede quedar sin persona:
///
/// - Sin personas: **no muestra nada** y devuelve [CitaSinPersona] (el nombre se pide al dar la
///   entrevista, no al agendarla).
/// - Con una sola: no muestra nada y devuelve [CitaConPersona] con ella.
/// - Con varias: la lista con «Seguir», «+ Alguien nuevo» y «Todavía no sé con quién».
Future<EleccionDeCita?> mostrarHojaConQuienParaProgramar(
  BuildContext context, {
  required String espacioId,
  required String colportorId,
}) async {
  final r = await _abrir(
    context,
    espacioId: espacioId,
    colportorId: colportorId,
    paraProgramar: true,
  );
  return r is EleccionDeCita ? r : null;
}

Future<Object?> _abrir(
  BuildContext context, {
  required String espacioId,
  required String colportorId,
  required bool paraProgramar,
}) async {
  // La lectura previa evita que, con una sola persona, la hoja se abra para cerrarse enseguida.
  try {
    final repo = ProviderScope.containerOf(context, listen: false).read(personaRepositoryProvider);
    final previas = await repo.observarDelEspacio(espacioId).first.timeout(_esperaPrevia);
    final paso = PasoConQuien.de(previas);
    if (paso is UnaPersona) {
      return paraProgramar ? CitaConPersona(paso.elegida) : paso.elegida;
    }
    if (paso is SinPersonas && paraProgramar) return const CitaSinPersona();
  } on Object {
    // Sin lectura a tiempo o con una falla: la hoja lo muestra («cargando» o el aviso con «Reintentar»).
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Sin arrastrar para cerrar: el arrastre no pasa por el `PopScope` y mientras se guarda a la
    // persona la hoja no se cierra. Las salidas son «Volver», el atrás y el toque afuera.
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        HojaConQuien(espacioId: espacioId, colportorId: colportorId, paraProgramar: paraProgramar),
  );
}

enum _Modo { formulario, lista }

/// La hoja de «¿Con quién?» (vista 39, R·04 y C·07). Ver [mostrarHojaConQuien].
///
/// - **Cargando** y **no se pudo leer** (con «Reintentar»): los estados que el canvas no dibuja.
/// - **R·04**: el candado, `NOMBRE` y `APELLIDO (OPCIONAL)`. «Empezar entrevista» queda apagado a la
///   vista mientras falta el nombre, pero se puede tocar (dice qué falta). Los ids del alta se
///   generan una vez por hoja: un doble toque o un reintento tras una falla no crean dos personas.
/// - **C·07**: una persona por fila (viene elegida la primera), con su saldo si se lo conoce, y
///   «+ Alguien nuevo» al final. Al volver del alta, la persona nueva queda elegida.
/// - Mientras se guarda no se puede cerrar; si falla, el aviso rojo y la acción vuelve a quedar
///   habilitada con lo escrito.
class HojaConQuien extends ConsumerStatefulWidget {
  const HojaConQuien({
    super.key,
    required this.espacioId,
    required this.colportorId,
    this.paraProgramar = false,
  });

  /// El espacio visitado. En un edificio es siempre el depto, nunca el edificio entero.
  final String espacioId;

  /// UUID del usuario con la sesión iniciada (`created_by`).
  final String colportorId;

  /// El paso de **programar** una entrevista: la cita puede quedar sin persona (ver
  /// [mostrarHojaConQuienParaProgramar]). Sale con un [EleccionDeCita] en vez de una
  /// [PersonaDeLaEntrevista].
  final bool paraProgramar;

  @override
  ConsumerState<HojaConQuien> createState() => _HojaConQuienState();
}

class _HojaConQuienState extends ConsumerState<HojaConQuien> {
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _focoNombre = FocusNode();
  final _focoApellido = FocusNode();

  /// Cuál de los dos pasos es: se decide con la primera lectura y no cambia (un alta que llega por
  /// la lista no debe convertir el formulario en la lista a mitad de guardar).
  _Modo? _modo;

  var _nombreTocado = false;

  /// Hay un guardado en curso (R·04): no admite otro toque ni se puede cerrar.
  var _enviando = false;

  /// Ya se está cerrando con un resultado: ningún otro toque cierra otra vez.
  var _cerrando = false;

  /// El alta de «+ Alguien nuevo» está abierta: un segundo toque no abre otra.
  var _abriendoAlta = false;

  Failure? _falla;
  IdsAltaPersona? _ids;

  /// La persona elegida de la lista; `null` = la primera.
  String? _elegidaId;

  @override
  void initState() {
    super.initState();
    _focoNombre.addListener(() {
      if (!_focoNombre.hasFocus && !_nombreTocado) setState(() => _nombreTocado = true);
    });
  }

  @override
  void dispose() {
    _nombre.dispose();
    _apellido.dispose();
    _focoNombre.dispose();
    _focoApellido.dispose();
    super.dispose();
  }

  ProblemaNombre? get _problemaNombre => ValidadorPersona.problemaNombre(_nombre.text);

  String? get _errorNombre {
    final problema = _problemaNombre;
    return _nombreTocado && problema != null ? ValidadorPersona.mensajeNombre(problema) : null;
  }

  void _anunciar(String mensaje) {
    if (!mounted) return;
    unawaited(
      SemanticsService.sendAnnouncement(View.of(context), mensaje, Directionality.of(context)),
    );
  }

  /// Lo que entrega la hoja con [elegida]: la persona sola, o la cita con ella al programar.
  Object _resultadoDe(PersonaDeLaEntrevista elegida) =>
      widget.paraProgramar ? CitaConPersona(elegida) : elegida;

  void _cerrarCon(Object? resultado) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(resultado);
  }

  /// Con una sola persona el paso se salta: se cierra apenas termina el cuadro.
  void _saltar(Object resultado) {
    if (_cerrando) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cerrarCon(resultado);
    });
  }

  Future<void> _empezarConNombre() async {
    // El primer renglón de la defensa contra el doble toque: la bandera se levanta antes de cualquier
    // `await`, así que el segundo toque ya la ve.
    if (_enviando || _cerrando) return;
    final problema = _problemaNombre;
    if (problema != null) {
      setState(() => _nombreTocado = true);
      _focoNombre.requestFocus();
      _anunciar(ValidadorPersona.mensajeNombre(problema));
      return;
    }
    setState(() {
      _enviando = true;
      _falla = null;
    });
    Failure? falla;
    PersonaDeLaEntrevista? guardada;
    try {
      final casoDeUso = ref.read(registrarPersonaUseCaseProvider);
      final ids = _ids ??= casoDeUso.nuevosIds();
      final resultado = await casoDeUso(
        RegistrarPersonaParams(
          ids: ids,
          espacioId: widget.espacioId,
          colportorId: widget.colportorId,
          nombre: _nombre.text,
          apellido: _apellido.text,
        ),
      );
      resultado.fold(
        (f) => falla = f,
        (p) => guardada = PersonaDeLaEntrevista(personaId: p.id, espacioPersonaId: ids.vinculo),
      );
    } on Object catch (e) {
      // Nada de `e` al mensaje: puede traer lo escrito (convenciones §7.5).
      falla = FailureInesperado(causa: e.runtimeType.toString());
    }
    if (!mounted) return;
    final exito = guardada;
    if (exito != null) {
      _cerrarCon(exito);
      return;
    }
    setState(() {
      _enviando = false;
      _falla = falla;
    });
  }

  Future<void> _alguienNuevo() async {
    if (_abriendoAlta || _cerrando) return;
    setState(() => _abriendoAlta = true);
    Persona? nueva;
    try {
      nueva = await AltaPersonaPage.abrir(
        context,
        espacioId: widget.espacioId,
        colportorId: widget.colportorId,
      );
    } finally {
      if (mounted) setState(() => _abriendoAlta = false);
    }
    if (!mounted || nueva == null) return;
    setState(() => _elegidaId = nueva!.id);
    _anunciar(TextosPersonas.guardada(nueva.nombre));
  }

  String get _textoFalla {
    final f = _falla;
    if (f is FailureValidacion && f.campos.containsKey('espacio')) return f.campos['espacio']!;
    return TextosConQuien.noPudimosGuardar;
  }

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(personasDelEspacioProvider(widget.espacioId));
    final personas = datos.value;
    if (_modo == null && personas != null) {
      switch (PasoConQuien.de(personas)) {
        case SinPersonas() when widget.paraProgramar:
          _saltar(const CitaSinPersona());
        case SinPersonas():
          _modo = _Modo.formulario;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focoNombre.requestFocus();
          });
        case VariasPersonas():
          _modo = _Modo.lista;
        case UnaPersona(:final elegida):
          _saltar(_resultadoDe(elegida));
      }
    }

    final Widget cuerpo;
    if (_modo == _Modo.formulario) {
      cuerpo = _formulario(context);
    } else if (_modo == _Modo.lista) {
      cuerpo = _lista(context, personas ?? const []);
    } else if (datos.hasError && personas == null) {
      cuerpo = _ErrorDeLectura(
        alReintentar: () => ref.invalidate(personasDelEspacioProvider(widget.espacioId)),
        alVolver: () => _cerrarCon(null),
      );
    } else {
      cuerpo = _Cargando(alVolver: () => _cerrarCon(null));
    }

    return PopScope(
      // Mientras se guarda no se sale: el resultado se perdería.
      canPop: !_enviando,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 100),
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Asa(),
            Flexible(child: cuerpo),
          ],
        ),
      ),
    );
  }

  /// R·04: el nombre alcanza. Todo en el desplazable: con el teclado y el texto grande, la acción
  /// queda al final, alcanzable, en vez de quedar fija y tapar los campos.
  Widget _formulario(BuildContext context) {
    final contexto = ref.watch(contextoEspacioProvider(widget.espacioId)).asData?.value;
    final donde = contexto == null
        ? null
        : FormatoPersonas.dondeEstaElEspacio(contexto.espacio, contexto.ubicacion);
    final conFalla = _falla != null;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Encabezado(
            titulo: TextosConQuien.tituloSinPersonas,
            ayuda: TextosConQuien.ayudaSinPersonas(donde),
          ),
          const SizedBox(height: 16),
          const AvisoPrivacidadPersona(),
          const SizedBox(height: 16),
          CampoPersona(
            etiqueta: TextosPersonas.etiquetaNombre,
            sugerencia: TextosPersonas.sugerenciaNombre,
            controlador: _nombre,
            foco: _focoNombre,
            error: _errorNombre,
            obligatorio: true,
            bloqueado: _enviando,
            limite: AltaPersonaPage.largoNombre,
            capitalizacion: TextCapitalization.words,
            accion: TextInputAction.next,
            alCambiar: (_) => setState(() {}),
            alEnviar: _focoApellido.requestFocus,
          ),
          const SizedBox(height: 16),
          CampoPersona(
            etiqueta: TextosPersonas.etiquetaApellido,
            sugerencia: TextosPersonas.sugerenciaApellido,
            controlador: _apellido,
            foco: _focoApellido,
            bloqueado: _enviando,
            limite: AltaPersonaPage.largoNombre,
            capitalizacion: TextCapitalization.words,
            accion: TextInputAction.done,
            alEnviar: _empezarConNombre,
          ),
          const SizedBox(height: 20),
          if (conFalla) ...[
            AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: _textoFalla),
            const SizedBox(height: 12),
          ],
          BotonAccionPersona(
            etiqueta: TextosConQuien.empezar,
            etiquetaEnviando: TextosConQuien.empezando,
            aspectoApagado: _problemaNombre != null,
            enviando: _enviando,
            alTocar: _empezarConNombre,
          ),
          const SizedBox(height: 10),
          _BotonVolver(alTocar: _enviando ? null : () => _cerrarCon(null)),
        ],
      ),
    );
  }

  /// La persona elegida de [personas]: la que se tocó o, si no se tocó ninguna, la primera.
  PersonaDelEspacio? _elegidaDe(List<PersonaDelEspacio> personas) => personas.isEmpty
      ? null
      : personas.firstWhere((p) => p.persona.id == _elegidaId, orElse: () => personas.first);

  /// C·07: las personas del espacio, «+ Alguien nuevo» y la acción fija al pie.
  Widget _lista(BuildContext context, List<PersonaDelEspacio> personas) {
    final saldos = ref.watch(saldosDelEspacioProvider(widget.espacioId)).asData?.value ?? const {};
    final elegida = _elegidaDe(personas);
    final repetidos = TextosConQuien.conNombreRepetido(personas);
    final conHora = TextosConQuien.conSegundaLineaRepetida(personas);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            itemCount: personas.length + (widget.paraProgramar ? 3 : 2),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) {
                return _Encabezado(
                  titulo: widget.paraProgramar
                      ? TextosConQuien.tituloProgramar
                      : TextosConQuien.tituloConPersonas,
                );
              }
              if (widget.paraProgramar && i == personas.length + 2) {
                // Solo al programar: la cita puede quedar sin nombre.
                return _FilaOpcion(
                  key: ClavesConQuien.todaviaNoSe,
                  titulo: TextosConQuien.todaviaNoSe,
                  etiquetaLector: TextosConQuien.todaviaNoSe,
                  seleccionable: false,
                  alTocar: _abriendoAlta ? null : () => _cerrarCon(const CitaSinPersona()),
                );
              }
              if (i == personas.length + 1) {
                return _FilaOpcion(
                  titulo: TextosConQuien.alguienNuevo,
                  detalle: TextosConQuien.alguienNuevoAyuda,
                  etiquetaLector:
                      '${TextosConQuien.alguienNuevo}. ${TextosConQuien.alguienNuevoAyuda}',
                  seleccionable: false,
                  alTocar: _abriendoAlta ? null : _alguienNuevo,
                );
              }
              final p = personas[i - 1];
              final saldo = saldos[p.persona.id];
              final repetido = repetidos.contains(p.persona.id);
              final horaDeAlta = conHora.contains(p.persona.id);
              return _FilaOpcion(
                titulo: FormatoPersonas.nombreCompleto(p.persona),
                // Solo con el nombre repetido, la segunda línea de 11·04 que dice quién es quién; si
                // esa línea también se repite, suma la hora de alta.
                distintivo: repetido
                    ? TextosConQuien.paraDistinguir(p.persona, conHora: horaDeAlta)
                    : null,
                detalle: saldo == null ? null : TextosConQuien.saldo(saldo),
                etiquetaLector: TextosConQuien.filaParaLector(
                  p,
                  saldo,
                  nombreRepetido: repetido,
                  conHora: horaDeAlta,
                ),
                seleccionada: p.persona.id == elegida?.persona.id,
                alTocar: () => setState(() => _elegidaId = p.persona.id),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: elegida == null
                    ? null
                    : () => _cerrarCon(
                        // La elección de este instante, no la del último cuadro pintado: dos toques
                        // seguidos (elegir y empezar) no pueden devolver a la anterior.
                        _elegidaDe(
                          ref.read(personasDelEspacioProvider(widget.espacioId)).value ?? personas,
                        )?.aLaEntrevista.paraLaHoja(paraProgramar: widget.paraProgramar),
                      ),
                child: Text(
                  widget.paraProgramar ? TextosConQuien.seguir : TextosConQuien.empezar,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              _BotonVolver(alTocar: () => _cerrarCon(null)),
            ],
          ),
        ),
      ],
    );
  }
}

/// El asa de la hoja.
class _Asa extends StatelessWidget {
  const _Asa();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: ColoresAlta.grisBorde,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

/// El título de la hoja y, si hay, la línea de ayuda de abajo.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.titulo, this.ayuda});

  final String titulo;
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ayuda = this.ayuda;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(titulo, style: theme.textTheme.headlineSmall)),
        if (ayuda != null) ...[
          const SizedBox(height: 4),
          Text(
            ayuda,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.extension<ColoresColportaje>()?.gris,
            ),
          ),
        ],
      ],
    );
  }
}

/// Una opción de C·07: un círculo de elección, el nombre y, abajo, su saldo (o «Con el nombre
/// alcanza»). Elegida: fondo azul claro y borde de 2. Una opción [seleccionable] es una de varias
/// excluyentes; «+ Alguien nuevo» no se elige, abre el alta.
class _FilaOpcion extends StatelessWidget {
  const _FilaOpcion({
    super.key,
    required this.titulo,
    required this.etiquetaLector,
    required this.alTocar,
    this.detalle,
    this.distintivo,
    this.seleccionada = false,
    this.seleccionable = true,
  });

  final String titulo;
  final String? detalle;

  /// El dato que distingue a dos personas con el mismo nombre (va entre el nombre y el detalle).
  final String? distintivo;
  final String etiquetaLector;
  final bool seleccionada;
  final bool seleccionable;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navy = theme.colorScheme.primary;
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: !seleccionable,
      inMutuallyExclusiveGroup: seleccionable,
      checked: seleccionable ? seleccionada : null,
      enabled: alTocar != null,
      label: etiquetaLector,
      onTap: alTocar,
      child: Material(
        color: seleccionada ? const Color(0xFFF2F6FB) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: seleccionada
              ? BorderSide(color: navy, width: 2)
              : const BorderSide(color: Color(0xFFE3E7EE)),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: alTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: seleccionada ? navy : Colors.white,
                      border: Border.all(color: seleccionada ? navy : ColoresAlta.gris, width: 1.5),
                    ),
                    child: seleccionada
                        ? const Icon(Icons.circle, size: 8, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (distintivo != null)
                          Text(
                            distintivo!,
                            style: theme.textTheme.bodyMedium?.copyWith(color: gris),
                          ),
                        if (detalle != null)
                          Text(detalle!, style: theme.textTheme.bodyMedium?.copyWith(color: gris)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Volver»: la salida sin elegir, de contorno (canvas: la acción secundaria de la hoja).
class _BotonVolver extends StatelessWidget {
  const _BotonVolver({required this.alTocar});

  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      foregroundColor: ColoresAlta.tinta,
      side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
    ),
    onPressed: alTocar,
    child: const Text(TextosConQuien.volver, textAlign: TextAlign.center),
  );
}

/// Mientras llegan las personas del espacio.
class _Cargando extends StatelessWidget {
  const _Cargando({required this.alVolver});

  final VoidCallback alVolver;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            label: TextosConQuien.cargando,
            child: ExcludeSemantics(
              child: Row(
                spacing: 12,
                children: [
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  Expanded(
                    child: Text(
                      TextosConQuien.cargando,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _BotonVolver(alTocar: alVolver),
        ],
      ),
    );
  }
}

/// No se pudieron leer las personas: qué pasó y qué hacer (principio 4).
class _ErrorDeLectura extends StatelessWidget {
  const _ErrorDeLectura({required this.alReintentar, required this.alVolver});

  final VoidCallback alReintentar;
  final VoidCallback alVolver;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: TextosConQuien.noPudimosLeer),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: alReintentar,
            child: const Text(TextosConQuien.reintentar, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 10),
          _BotonVolver(alTocar: alVolver),
        ],
      ),
    );
  }
}

extension on PersonaDeLaEntrevista {
  /// Lo que entrega la hoja al elegir a esta persona: ella sola, o la cita con ella al programar.
  Object paraLaHoja({required bool paraProgramar}) => paraProgramar ? CitaConPersona(this) : this;
}

/// Las claves de la hoja «¿Con quién?» (para los tests y la QA).
abstract final class ClavesConQuien {
  static const todaviaNoSe = Key('con_quien_todavia_no_se');
}
