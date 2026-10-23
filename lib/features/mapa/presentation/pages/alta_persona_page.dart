import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/persona.dart';
import '../../domain/services/validador_persona.dart';
import '../../domain/usecases/registrar_persona_use_case.dart';
import '../providers/personas_providers.dart';
import '../textos_personas.dart';
import '../widgets/campos_ubicacion.dart' show EtiquetaCampoUbicacion;
import '../widgets/piezas_alta.dart';

/// "Nueva persona" (HU-UBI-008, vista 32A, artboards A·01 a A·06): el formulario que da de alta a un
/// cliente en un espacio. Todo se guarda en el teléfono —la persona y su nota no se sincronizan—, así
/// que no hay estado «sin conexión» ni espera de red.
///
/// - El nombre es lo único obligatorio (al menos 2 letras); el apellido, el teléfono y la primera nota
///   son opcionales.
/// - «Guardar persona» se ve apagado mientras el formulario no sirve, pero **se puede tocar**: el toque
///   muestra qué falta, lleva el foco al primer campo con problema y lo anuncia al lector de pantalla.
/// - Los ids del alta se generan una vez por formulario ([IdsAltaPersona]): un doble toque o un
///   «Reintentar» tras una falla no crean dos personas.
/// - Si guardar falla, el formulario conserva lo escrito, el botón vuelve a habilitarse y pasa a decir
///   «Reintentar» (A·06).
///
/// Devuelve la [Persona] guardada (o `null` si se cerró sin guardar), para que quien la abrió avise
/// «Guardamos a Jorge en este teléfono.» (A·05).
class AltaPersonaPage extends ConsumerStatefulWidget {
  const AltaPersonaPage({super.key, required this.espacioId, required this.colportorId});

  /// El espacio al que se agrega la persona.
  final String espacioId;

  /// UUID del usuario con la sesión iniciada (`created_by`).
  final String colportorId;

  /// Abre el alta encima de la pantalla actual.
  static Future<Persona?> abrir(
    BuildContext context, {
    required String espacioId,
    required String colportorId,
  }) => Navigator.of(context).push<Persona>(
    MaterialPageRoute(
      builder: (_) => AltaPersonaPage(espacioId: espacioId, colportorId: colportorId),
    ),
  );

  /// Cuántos caracteres admite cada campo. Los topes del nombre y el apellido son los de la
  /// cuenta (HU-AUTH-001); los del teléfono y de la nota, sin tope de la HU, son un resguardo para
  /// que un pegado enorme no trabe el formulario (a confirmar).
  static const largoNombre = 60;
  static const largoTelefono = 20;

  @override
  ConsumerState<AltaPersonaPage> createState() => _AltaPersonaPageState();
}

class _AltaPersonaPageState extends ConsumerState<AltaPersonaPage> {
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _telefono = TextEditingController();
  final _nota = TextEditingController();

  final _focoNombre = FocusNode();
  final _focoApellido = FocusNode();
  final _focoTelefono = FocusNode();
  final _focoNota = FocusNode();

  /// Qué campos ya se tocaron: el error de un campo se muestra recién cuando se lo dejó o se intentó
  /// guardar, no mientras se escribe el primer carácter.
  var _nombreTocado = false;
  var _telefonoTocado = false;

  /// Hay un guardado en curso: no admite otro toque, no deja salir y bloquea los campos.
  var _enviando = false;

  /// La última falla al guardar (A·06); `null` si no hay.
  Failure? _falla;

  /// Los ids del alta, creados con el primer intento y repetidos en los siguientes.
  IdsAltaPersona? _ids;

  @override
  void initState() {
    super.initState();
    _focoNombre.addListener(() {
      if (!_focoNombre.hasFocus && !_nombreTocado) setState(() => _nombreTocado = true);
    });
    _focoTelefono.addListener(() {
      if (!_focoTelefono.hasFocus && !_telefonoTocado) setState(() => _telefonoTocado = true);
    });
  }

  @override
  void dispose() {
    for (final c in [_nombre, _apellido, _telefono, _nota]) {
      c.dispose();
    }
    for (final f in [_focoNombre, _focoApellido, _focoTelefono, _focoNota]) {
      f.dispose();
    }
    super.dispose();
  }

  ProblemaNombre? get _problemaNombre => ValidadorPersona.problemaNombre(_nombre.text);
  ProblemaTelefono? get _problemaTelefono => ValidadorPersona.problemaTelefono(_telefono.text);
  bool get _sirve => _problemaNombre == null && _problemaTelefono == null;

  String? get _errorNombre {
    final problema = _problemaNombre;
    return _nombreTocado && problema != null ? ValidadorPersona.mensajeNombre(problema) : null;
  }

  String? get _errorTelefono {
    final problema = _problemaTelefono;
    return _telefonoTocado && problema != null ? ValidadorPersona.mensajeTelefono(problema) : null;
  }

  void _anunciar(String mensaje) {
    if (!mounted) return;
    unawaited(
      SemanticsService.sendAnnouncement(View.of(context), mensaje, Directionality.of(context)),
    );
  }

  Future<void> _guardar() async {
    // El primer renglón de la defensa contra el doble toque: la bandera se levanta antes de cualquier
    // `await`, así que el segundo toque ya la ve.
    if (_enviando) return;
    if (!_sirve) {
      setState(() {
        _nombreTocado = true;
        _telefonoTocado = true;
      });
      final enNombre = _problemaNombre != null;
      (enNombre ? _focoNombre : _focoTelefono).requestFocus();
      final problema = _problemaNombre;
      _anunciar(
        problema != null
            ? ValidadorPersona.mensajeNombre(problema)
            : ValidadorPersona.mensajeTelefono(_problemaTelefono!),
      );
      return;
    }
    setState(() {
      _enviando = true;
      _falla = null;
    });
    Failure? falla;
    Persona? guardada;
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
          telefono: _telefono.text,
          nota: _nota.text,
        ),
      );
      resultado.fold((f) => falla = f, (p) => guardada = p);
    } on Object catch (e) {
      // Nada de `e` al mensaje: puede traer lo escrito (convenciones §7.5).
      falla = FailureInesperado(causa: e.runtimeType.toString());
    }
    if (!mounted) return;
    final exito = guardada;
    if (exito != null) {
      Navigator.of(context).pop(exito);
      return;
    }
    setState(() {
      _enviando = false;
      _falla = falla;
    });
  }

  String get _textoFalla {
    final f = _falla;
    if (f is FailureValidacion && f.campos.containsKey('espacio')) return f.campos['espacio']!;
    return TextosPersonas.noPudimosGuardar;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contexto = ref.watch(contextoEspacioProvider(widget.espacioId)).asData?.value;
    final donde = contexto == null
        ? null
        : FormatoPersonas.dondeEstaElEspacio(contexto.espacio, contexto.ubicacion);
    final conFalla = _falla != null;

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
                    tooltip: TextosPersonas.cerrar,
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
                        TextosPersonas.altaRotulo,
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
                          TextosPersonas.altaTitulo,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      if (donde != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          donde,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.extension<ColoresColportaje>()?.gris,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const _AvisoPrivacidad(),
                      const SizedBox(height: 20),
                      _CampoPersona(
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
                      _CampoPersona(
                        etiqueta: TextosPersonas.etiquetaApellido,
                        sugerencia: TextosPersonas.sugerenciaApellido,
                        controlador: _apellido,
                        foco: _focoApellido,
                        bloqueado: _enviando,
                        limite: AltaPersonaPage.largoNombre,
                        capitalizacion: TextCapitalization.words,
                        accion: TextInputAction.next,
                        alEnviar: _focoTelefono.requestFocus,
                      ),
                      const SizedBox(height: 16),
                      _CampoPersona(
                        etiqueta: TextosPersonas.etiquetaTelefono,
                        sugerencia: TextosPersonas.sugerenciaTelefono,
                        controlador: _telefono,
                        foco: _focoTelefono,
                        error: _errorTelefono,
                        bloqueado: _enviando,
                        limite: AltaPersonaPage.largoTelefono,
                        teclado: TextInputType.phone,
                        accion: TextInputAction.next,
                        alCambiar: (_) => setState(() {}),
                        alEnviar: _focoNota.requestFocus,
                      ),
                      const SizedBox(height: 16),
                      _CampoPersona(
                        etiqueta: TextosPersonas.etiquetaNota,
                        sugerencia: TextosPersonas.sugerenciaNota,
                        controlador: _nota,
                        foco: _focoNota,
                        bloqueado: _enviando,
                        capitalizacion: TextCapitalization.sentences,
                        teclado: TextInputType.multiline,
                        accion: TextInputAction.newline,
                        renglones: 3,
                      ),
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
                    _BotonGuardar(
                      etiqueta: conFalla ? TextosPersonas.reintentar : TextosPersonas.guardar,
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

/// El candado de privacidad (canvas 32A): lo primero que se lee, antes de pedir datos de otra persona.
class _AvisoPrivacidad extends StatelessWidget {
  const _AvisoPrivacidad();

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    return Semantics(
      container: true,
      label: TextosPersonas.privacidad,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F6FB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: navy.withValues(alpha: .25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 20, color: navy),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  TextosPersonas.privacidad,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: navy, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un campo del formulario: la etiqueta mono de arriba, el cuadro con borde de 1,5 y el error debajo.
class _CampoPersona extends StatelessWidget {
  const _CampoPersona({
    required this.etiqueta,
    required this.sugerencia,
    required this.controlador,
    required this.foco,
    required this.bloqueado,
    required this.accion,
    this.error,
    this.obligatorio = false,
    this.limite,
    this.capitalizacion = TextCapitalization.none,
    this.teclado,
    this.renglones = 1,
    this.alCambiar,
    this.alEnviar,
  });

  final String etiqueta;
  final String sugerencia;
  final TextEditingController controlador;
  final FocusNode foco;
  final bool bloqueado;
  final TextInputAction accion;
  final String? error;
  final bool obligatorio;
  final int? limite;
  final TextCapitalization capitalizacion;
  final TextInputType? teclado;
  final int renglones;
  final ValueChanged<String>? alCambiar;
  final VoidCallback? alEnviar;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    OutlineInputBorder borde(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: 1.5),
    );
    final multilinea = renglones > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(child: EtiquetaCampoUbicacion(etiqueta)),
        const SizedBox(height: 6),
        Semantics(
          label: obligatorio ? '$etiqueta, obligatorio' : etiqueta,
          child: TextField(
            controller: controlador,
            focusNode: foco,
            readOnly: bloqueado,
            keyboardType: teclado,
            textInputAction: accion,
            textCapitalization: capitalizacion,
            minLines: multilinea ? renglones : 1,
            maxLines: multilinea ? null : 1,
            onChanged: alCambiar,
            onSubmitted: alEnviar == null ? null : (_) => alEnviar!(),
            inputFormatters: [
              if (!multilinea) FilteringTextInputFormatter.deny(RegExp(r'[\r\n  ]+')),
              if (limite != null) LengthLimitingTextInputFormatter(limite),
            ],
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: sugerencia,
              errorText: error,
              errorMaxLines: 6,
              isDense: false,
              filled: true,
              fillColor: Colors.white,
              constraints: const BoxConstraints(minHeight: 50),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: borde(ColoresAlta.grisBorde),
              enabledBorder: borde(ColoresAlta.grisBorde),
              focusedBorder: borde(navy),
              errorBorder: borde(ColoresAlta.rojo),
              focusedErrorBorder: borde(ColoresAlta.rojo),
            ),
          ),
        ),
      ],
    );
  }
}

/// «Guardar persona» / «Reintentar». Apagado a la vista cuando el formulario no sirve, pero tocable
/// (el toque dice qué falta); trabajando, muestra «Guardando…» y no admite otro toque.
class _BotonGuardar extends StatelessWidget {
  const _BotonGuardar({
    required this.etiqueta,
    required this.aspectoApagado,
    required this.enviando,
    required this.alTocar,
  });

  final String etiqueta;
  final bool aspectoApagado;
  final bool enviando;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final gris = Theme.of(context).extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    // El «apagado» del canvas (#90A0B7) no llega al 4,5:1 con texto blanco: se usa el gris de texto
    // de la app, que sí, como en «Continuar» de la cuenta (#335).
    final estilo = enviando
        ? FilledButton.styleFrom(
            disabledBackgroundColor: esquema.primary.withValues(alpha: .85),
            disabledForegroundColor: esquema.onPrimary,
          )
        : aspectoApagado
        ? FilledButton.styleFrom(backgroundColor: gris, foregroundColor: Colors.white)
        : null;
    return FilledButton(
      onPressed: enviando ? null : alTocar,
      style:
          estilo?.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(56))) ??
          FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      child: enviando
          ? Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: esquema.onPrimary,
                    backgroundColor: esquema.onPrimary.withValues(alpha: .35),
                  ),
                ),
                const Flexible(child: Text(TextosPersonas.guardando)),
              ],
            )
          : Text(etiqueta, textAlign: TextAlign.center),
    );
  }
}
