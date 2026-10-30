import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/contexto_edicion_persona.dart';
import '../../domain/entities/contexto_notas_persona.dart';
import '../../domain/entities/persona.dart';
import '../../domain/services/criterio_otra_persona.dart';
import '../../domain/services/validador_persona.dart';
import '../../domain/usecases/modificar_persona_use_case.dart';
import '../providers/personas_providers.dart';
import '../textos_notas.dart';
import '../textos_personas.dart';
import '../widgets/dialogos_modificar.dart';
import '../widgets/piezas_alta.dart';
import '../widgets/piezas_notas.dart';
import '../widgets/piezas_persona.dart';
import 'alta_persona_page.dart';

/// Lo que devuelve [ModificarPersonaPage]: la edición se guardó, o la colportora eligió dar de baja a
/// la persona y registrar a otra en su lugar.
sealed class ResultadoEdicionPersona {
  const ResultadoEdicionPersona();
}

/// Se guardaron los cambios; [persona] es la persona como quedó.
final class PersonaEditada extends ResultadoEdicionPersona {
  const PersonaEditada(this.persona);

  final Persona persona;
}

/// En «¿Es otra persona?» (canvas 32C·03) eligió «Dar de baja y crear nueva»: **no se escribió nada**.
/// Quien abrió la edición da de baja a [original] (HU-UBI-011) y abre el alta con lo que se escribió
/// ([nombre], [apellido] y [telefono], ya validados y tal cual los dejó).
final class DarDeBajaYCrearNuevaElegido extends ResultadoEdicionPersona {
  const DarDeBajaYCrearNuevaElegido({
    required this.original,
    required this.nombre,
    required this.apellido,
    required this.telefono,
  });

  final Persona original;
  final String nombre;
  final String apellido;
  final String? telefono;
}

/// «Editar persona» (HU-UBI-010, vista 32C, artboards C·01 a C·04): el formulario con el nombre, el
/// apellido y el teléfono de una persona. Todo se guarda en el teléfono —la persona no se sincroniza—,
/// así que no hay estado «sin conexión» ni espera de red.
///
/// - Comparte el candado, los campos y las validaciones con el alta. Vaciar el nombre muestra al
///   instante «El nombre no puede quedar vacío.» (C·02); «Guardar cambios» se ve apagado pero **se
///   puede tocar**: el toque muestra qué falta, lleva el foco al primer campo con problema y lo
///   anuncia al lector de pantalla.
/// - Un cambio que parece «otra persona» (C·03) muestra el aviso con «Dar de baja y crear nueva» y el
///   botón pasa a decir «Guardar igual», que guarda sin más. Es «demasiado grande» cuando cambian el
///   nombre y el apellido a la vez (`CriterioOtraPersonaPorNombreYApellido`, decisión del 27/10): una
///   tilde, un apellido o el teléfono solos no lo muestran.
/// - Si guardar falla, el formulario conserva lo escrito, el botón vuelve a habilitarse y pasa a decir
///   «Reintentar». Un doble toque no guarda dos veces; mientras se guarda no se puede salir.
/// - Sin cambios, «Guardar cambios» cierra sin escribir nada (no se toca `updated_at`). La ✕ y el
///   atrás del sistema, con cambios sin guardar, preguntan «¿Descartar lo que escribiste?».
/// - La persona se lee al abrir: cargando, error de lectura («Reintentar»), persona que ya no está y
///   persona en solo lectura (de baja, o sin un espacio activo: 32B·04 y 32B·08) tienen su aviso.
///
/// Devuelve un [ResultadoEdicionPersona] (o `null` si se cerró sin guardar). Al volver con una
/// [PersonaEditada], [abrir] muestra «Cambios guardados en tu teléfono.» (C·04) en la pantalla que la
/// abrió.
class ModificarPersonaPage extends ConsumerWidget {
  const ModificarPersonaPage({super.key, required this.personaId, required this.colportorId});

  /// La persona que se edita.
  final String personaId;

  /// UUID del usuario con la sesión iniciada: la preferencia de «No volver a mostrar» del aviso de
  /// privacidad es de su cuenta (#445).
  final String colportorId;

  /// Abre la edición encima de la pantalla actual.
  static Future<ResultadoEdicionPersona?> abrir(
    BuildContext context, {
    required String personaId,
    required String colportorId,
  }) async {
    // Se leen antes de esperar: cuando la edición se cierre, `context` puede ya no ser el mismo.
    final mensajero = ScaffoldMessenger.of(context);
    final mediaQuery = MediaQuery.of(context);
    mensajero.hideCurrentSnackBar();
    final resultado = await Navigator.of(context).push<ResultadoEdicionPersona>(
      MaterialPageRoute(
        builder: (_) => ModificarPersonaPage(personaId: personaId, colportorId: colportorId),
      ),
    );
    if (resultado is PersonaEditada && mensajero.mounted) {
      mostrarAvisoDeNota(mensajero, mediaQuery: mediaQuery, texto: TextosPersonas.cambiosGuardados);
    }
    return resultado;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lectura = ref.watch(contextoEdicionPersonaProvider(personaId));
    return lectura.when(
      loading: () => const _Marco(cuerpo: _Cargando()),
      error: (_, _) => _Marco(
        cuerpo: _Aviso(
          color: ColoresAlta.rojo,
          texto: TextosPersonas.noPudimosLeerPersona,
          etiquetaAccion: TextosPersonas.reintentar,
          alAccion: () => ref.invalidate(contextoEdicionPersonaProvider(personaId)),
        ),
      ),
      data: (contexto) {
        if (contexto == null) {
          return _Marco(
            cuerpo: _Aviso(
              color: ColoresAlta.ambarBorde,
              colorInsignia: ColoresAlta.ambar,
              texto: TextosPersonas.personaNoEncontrada,
              etiquetaAccion: TextosPersonas.volver,
              alAccion: () => Navigator.of(context).maybePop(),
            ),
          );
        }
        if (contexto.soloLectura) {
          return _Marco(
            cuerpo: _Aviso(
              color: ColoresAlta.ambarBorde,
              colorInsignia: ColoresAlta.ambar,
              texto: _textoSoloLectura(contexto, ref),
              etiquetaAccion: TextosPersonas.volver,
              alAccion: () => Navigator.of(context).maybePop(),
            ),
          );
        }
        return _Formulario(contexto: contexto, colportorId: colportorId);
      },
    );
  }

  /// La causa como la ficha (32B·04 y 32B·08) y que sus datos no se pueden editar.
  static String _textoSoloLectura(ContextoEdicionPersona contexto, WidgetRef ref) {
    final causa = TextosNotas.causaSoloLectura(
      ContextoNotasPersona(
        nombre: contexto.persona.nombre,
        causa: contexto.causa,
        bajaDesde: contexto.bajaDesde,
        numeroDepto: contexto.numeroDepto,
        direccion: contexto.direccion,
      ),
      ref.read(relojPersonaProvider)(),
    );
    return '$causa ${TextosPersonas.soloLecturaEdicionAyuda}';
  }
}

/// La pantalla sin formulario: la ✕, el rótulo y el título, y [cuerpo] (cargando o un aviso).
class _Marco extends StatelessWidget {
  const _Marco({required this.cuerpo});

  final Widget cuerpo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _Cerrar(alTocar: null, habilitado: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [const _Titulo(), const SizedBox(height: 20), cuerpo],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La ✕ de arriba. Con [alTocar] `null` y [habilitado], cierra la pantalla sin preguntar.
class _Cerrar extends StatelessWidget {
  const _Cerrar({required this.alTocar, required this.habilitado});

  final VoidCallback? alTocar;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: IconButton(
          tooltip: TextosPersonas.cerrar,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: !habilitado ? null : (alTocar ?? () => Navigator.of(context).maybePop()),
          icon: const Icon(Icons.close),
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({this.donde});

  /// «Mataojo 2044 · Depto 3B», si se conoce.
  final String? donde;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          TextosPersonas.editarRotulo,
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
          child: Text(TextosPersonas.editarTitulo, style: theme.textTheme.headlineSmall),
        ),
        if (donde != null) ...[
          const SizedBox(height: 4),
          Text(
            donde!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.extension<ColoresColportaje>()?.gris,
            ),
          ),
        ],
      ],
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: TextosPersonas.cargandoPersona,
      child: const ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

/// Un aviso con una acción de texto («Reintentar», «Volver»).
class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.color,
    required this.texto,
    required this.etiquetaAccion,
    required this.alAccion,
    this.colorInsignia,
  });

  final Color color;
  final Color? colorInsignia;
  final String texto;
  final String etiquetaAccion;
  final VoidCallback alAccion;

  @override
  Widget build(BuildContext context) {
    return AvisoAlta(
      color: color,
      colorInsignia: colorInsignia,
      glyph: '!',
      texto: texto,
      acciones: Align(
        alignment: Alignment.centerLeft,
        child: EnlaceAlta(texto: etiquetaAccion, alPresionar: alAccion),
      ),
    );
  }
}

class _Formulario extends ConsumerStatefulWidget {
  const _Formulario({required this.contexto, required this.colportorId});

  final ContextoEdicionPersona contexto;
  final String colportorId;

  @override
  ConsumerState<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends ConsumerState<_Formulario> {
  late final TextEditingController _nombre;
  late final TextEditingController _apellido;
  late final TextEditingController _telefono;

  final _focoNombre = FocusNode();
  final _focoApellido = FocusNode();
  final _focoTelefono = FocusNode();

  /// Qué campos ya se dejaron o se intentó guardar: el error del teléfono y el de un nombre corto
  /// se muestran recién entonces, no mientras se escribe el primer carácter. Vaciar el nombre se
  /// avisa al instante.
  var _nombreTocado = false;
  var _telefonoTocado = false;

  /// Hay un guardado en curso: no admite otro toque, no deja salir y bloquea los campos.
  var _enviando = false;

  /// Se está preguntando si se descarta (un segundo toque en la ✕ no abre otro aviso).
  var _preguntando = false;

  /// Ya se pidió cerrar la pantalla: un segundo toque en el mismo fotograma no cierra también la
  /// pantalla de abajo.
  var _cerrando = false;

  /// La última falla al guardar; `null` si no hay.
  Failure? _falla;

  Persona get _persona => widget.contexto.persona;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: _persona.nombre);
    _apellido = TextEditingController(text: _persona.apellido);
    _telefono = TextEditingController(text: _persona.telefono ?? '');
    _focoNombre.addListener(() {
      if (!_focoNombre.hasFocus && !_nombreTocado) setState(() => _nombreTocado = true);
    });
    _focoTelefono.addListener(() {
      if (!_focoTelefono.hasFocus && !_telefonoTocado) setState(() => _telefonoTocado = true);
    });
  }

  @override
  void dispose() {
    for (final c in [_nombre, _apellido, _telefono]) {
      c.dispose();
    }
    for (final f in [_focoNombre, _focoApellido, _focoTelefono]) {
      f.dispose();
    }
    super.dispose();
  }

  ProblemaNombre? get _problemaNombre => ValidadorPersona.problemaNombre(_nombre.text);
  ProblemaTelefono? get _problemaTelefono => ValidadorPersona.problemaTelefono(_telefono.text);
  bool get _sirve => _problemaNombre == null && _problemaTelefono == null;

  bool get _cambioNombre => ValidadorPersona.limpiar(_nombre.text) != _persona.nombre;
  bool get _cambioApellido => ValidadorPersona.limpiar(_apellido.text) != _persona.apellido;
  bool get _cambioTelefono => ValidadorPersona.telefonoLimpio(_telefono.text) != _persona.telefono;

  /// Hay algo escrito que se perdería al salir.
  bool get _hayCambios => _cambioNombre || _cambioApellido || _cambioTelefono;

  String? get _errorNombre {
    final problema = _problemaNombre;
    if (problema == null) return null;
    final vaciado = problema == ProblemaNombre.vacio && _cambioNombre;
    return _nombreTocado || vaciado ? ValidadorPersona.mensajeNombreEdicion(problema) : null;
  }

  String? get _errorTelefono {
    final problema = _problemaTelefono;
    return _telefonoTocado && problema != null ? ValidadorPersona.mensajeTelefono(problema) : null;
  }

  DatosDePersona get _datos => (
    nombre: ValidadorPersona.limpiar(_nombre.text),
    apellido: ValidadorPersona.limpiar(_apellido.text),
    telefono: ValidadorPersona.limpiar(_telefono.text),
  );

  /// Los campos que cambió, en el orden del formulario («nombre», «apellido», «teléfono»).
  List<String> get _camposCambiados => [
    if (_cambioNombre) 'nombre',
    if (_cambioApellido) 'apellido',
    if (_cambioTelefono) 'teléfono',
  ];

  void _anunciar(String mensaje) {
    if (!mounted) return;
    unawaited(
      SemanticsService.sendAnnouncement(View.of(context), mensaje, Directionality.of(context)),
    );
  }

  /// Cierra la pantalla, una sola vez, devolviendo [resultado].
  void _cerrar([ResultadoEdicionPersona? resultado]) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(resultado);
  }

  /// La ✕ y el atrás del sistema: sin cambios cierran directo; con cambios sin guardar preguntan antes.
  Future<void> _salir() async {
    if (_enviando || _preguntando || _cerrando) return;
    if (!_hayCambios) {
      _cerrar();
      return;
    }
    _preguntando = true;
    bool descartar;
    try {
      descartar = await confirmarDescartarLoEscrito(context);
    } finally {
      _preguntando = false;
    }
    if (!mounted || !descartar) return;
    _cerrar();
  }

  /// Si el formulario no sirve: marca los campos, lleva el foco al primero con problema y lo anuncia.
  /// Devuelve `true` si había un problema (y no hay que seguir).
  bool _mostrarLoQueFalta() {
    if (_sirve) return false;
    setState(() {
      _nombreTocado = true;
      _telefonoTocado = true;
    });
    final problema = _problemaNombre;
    (problema != null ? _focoNombre : _focoTelefono).requestFocus();
    _anunciar(
      problema != null
          ? ValidadorPersona.mensajeNombreEdicion(problema)
          : ValidadorPersona.mensajeTelefono(_problemaTelefono!),
    );
    return true;
  }

  Future<void> _guardar() async {
    // El primer renglón de la defensa contra el doble toque: la bandera se levanta antes de cualquier
    // `await`, así que el segundo toque ya la ve.
    if (_enviando || _cerrando) return;
    if (_mostrarLoQueFalta()) return;
    if (!_hayCambios) {
      // Nada cambió: no hay nada que escribir.
      _cerrar();
      return;
    }
    setState(() {
      _enviando = true;
      _falla = null;
    });
    Failure? falla;
    ResultadoEdicionPersona? resultado;
    try {
      final respuesta = await ref.read(modificarPersonaUseCaseProvider)(
        ModificarPersonaParams(
          personaId: _persona.id,
          nombre: _nombre.text,
          apellido: _apellido.text,
          telefono: _telefono.text,
        ),
      );
      respuesta.fold(
        (f) => falla = f,
        (r) => resultado = r.huboCambios ? PersonaEditada(r.persona) : null,
      );
    } on Object catch (e) {
      // Nada de `e` al mensaje: puede traer lo escrito (convenciones §7.5).
      falla = FailureInesperado(causa: e.runtimeType.toString());
    }
    if (!mounted) return;
    if (falla == null) {
      _cerrar(resultado);
      return;
    }
    setState(() {
      _enviando = false;
      _falla = falla;
    });
  }

  /// «Dar de baja y crear nueva» (C·03): no escribe nada; le devuelve a quien abrió la edición lo que
  /// se escribió, para que dé de baja a la persona y abra el alta con eso.
  void _darDeBajaYCrearNueva() {
    if (_enviando || _cerrando || _mostrarLoQueFalta()) return;
    final datos = _datos;
    _cerrar(
      DarDeBajaYCrearNuevaElegido(
        original: _persona,
        nombre: datos.nombre,
        apellido: datos.apellido,
        telefono: ValidadorPersona.telefonoLimpio(datos.telefono),
      ),
    );
  }

  String get _textoFalla {
    final f = _falla;
    if (f is FailureValidacion && f.campos.containsKey('persona')) return f.campos['persona']!;
    return TextosPersonas.noPudimosGuardar;
  }

  @override
  Widget build(BuildContext context) {
    final espacioId = widget.contexto.espacioId;
    final espacio = espacioId == null
        ? null
        : ref.watch(contextoEspacioProvider(espacioId)).asData?.value;
    final donde = espacio == null
        ? null
        : FormatoPersonas.dondeEstaElEspacio(espacio.espacio, espacio.ubicacion);
    final conFalla = _falla != null;
    final otraPersona =
        _sirve &&
        _hayCambios &&
        ref.watch(criterioOtraPersonaProvider).pareceOtraPersona(_persona, _datos);
    final etiqueta = conFalla
        ? TextosPersonas.reintentar
        : otraPersona
        ? TextosPersonas.guardarIgual
        : TextosPersonas.guardarCambios;

    return PopScope(
      // Mientras se guarda no se sale (el resultado se perdería) y con cambios sin guardar se pregunta.
      canPop: !_enviando && !_hayCambios,
      onPopInvokedWithResult: (salio, _) {
        if (!salio && !_enviando) unawaited(_salir());
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _Cerrar(alTocar: _salir, habilitado: !_enviando),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Titulo(donde: donde),
                      const SizedBox(height: 16),
                      AvisoPrivacidadPersona(colportorId: widget.colportorId),
                      const SizedBox(height: 20),
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
                        accion: TextInputAction.next,
                        alCambiar: (_) => setState(() {}),
                        alEnviar: _focoTelefono.requestFocus,
                      ),
                      const SizedBox(height: 16),
                      CampoPersona(
                        etiqueta: TextosPersonas.etiquetaTelefono,
                        sugerencia: TextosPersonas.sugerenciaTelefono,
                        controlador: _telefono,
                        foco: _focoTelefono,
                        error: _errorTelefono,
                        bloqueado: _enviando,
                        limite: AltaPersonaPage.largoTelefono,
                        teclado: TextInputType.phone,
                        accion: TextInputAction.done,
                        alCambiar: (_) => setState(() {}),
                      ),
                      if (otraPersona) ...[
                        const SizedBox(height: 20),
                        AvisoAlta(
                          color: ColoresAlta.ambarBorde,
                          colorInsignia: ColoresAlta.ambar,
                          glyph: '!',
                          texto: TextosPersonas.otraPersona(
                            campos: _camposCambiados,
                            antes: _persona.nombre,
                            despues: _datos.nombre,
                          ),
                          acciones: Align(
                            alignment: Alignment.centerLeft,
                            child: EnlaceAlta(
                              texto: TextosPersonas.darDeBajaYCrearNueva,
                              alPresionar: _enviando ? null : _darDeBajaYCrearNueva,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (conFalla) ...[
                      AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: _textoFalla),
                      const SizedBox(height: 12),
                    ],
                    BotonAccionPersona(
                      etiqueta: etiqueta,
                      aspectoApagado: !_sirve,
                      enviando: _enviando,
                      alTocar: _guardar,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
