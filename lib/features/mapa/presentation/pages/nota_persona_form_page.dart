import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/nota_persona.dart';
import '../../domain/services/validador_nota.dart';
import '../../domain/usecases/notas_persona_use_cases.dart';
import '../providers/notas_persona_providers.dart';
import '../providers/personas_providers.dart';
import '../textos_notas.dart';
import '../widgets/dialogos_modificar.dart';
import '../widgets/piezas_alta.dart';
import '../widgets/piezas_notas.dart';
import '../widgets/piezas_persona.dart';

/// Lo que devuelve el formulario de una nota: la nota guardada y si era nueva o una edición.
typedef NotaGuardada = ({NotaPersona nota, bool esNueva});

/// «Nueva nota» y «Editar nota» (HU-UBI-012, vista 32E, artboards E·02 y E·07): el formulario de una
/// nota de una persona. Todo se guarda en el teléfono —la nota no se sincroniza—, así que no hay estado
/// «sin conexión» ni espera de red.
///
/// - Una nota en blanco no se guarda: «Guardar nota» se ve apagado pero **se puede tocar**; el toque
///   lleva el foco al campo y lo anuncia al lector de pantalla.
/// - Pasar los 5000 caracteres **avisa pero deja guardar** (límite blando de la HU).
/// - El id de una nota nueva se genera una vez por formulario: un doble toque o un «Reintentar» tras una
///   falla no crean dos notas.
/// - Si guardar falla, el texto queda en el campo, el botón vuelve a habilitarse y pasa a decir
///   «Reintentar» (E·07).
/// - Al editar, si el texto no cambió se cierra sin escribir nada (no se toca `updated_at`).
/// - La ✕ y el atrás del sistema, con texto sin guardar, preguntan «¿Descartar lo que escribiste?»
///   (mapa §2, P5 de #144); sin cambios cierran directo.
///
/// Devuelve la [NotaGuardada] (o `null` si se cerró sin guardar).
class NotaPersonaFormPage extends ConsumerStatefulWidget {
  const NotaPersonaFormPage({
    super.key,
    required this.personaId,
    required this.colportorId,
    this.nota,
  });

  /// La persona dueña de la nota.
  final String personaId;

  /// UUID del usuario con la sesión iniciada (`created_by` de una nota nueva).
  final String colportorId;

  /// La nota que se edita, o `null` para una nueva.
  final NotaPersona? nota;

  /// Abre el formulario encima de la pantalla actual.
  static Future<NotaGuardada?> abrir(
    BuildContext context, {
    required String personaId,
    required String colportorId,
    NotaPersona? nota,
  }) => Navigator.of(context).push<NotaGuardada>(
    MaterialPageRoute(
      builder: (_) =>
          NotaPersonaFormPage(personaId: personaId, colportorId: colportorId, nota: nota),
    ),
  );

  @override
  ConsumerState<NotaPersonaFormPage> createState() => _NotaPersonaFormPageState();
}

class _NotaPersonaFormPageState extends ConsumerState<NotaPersonaFormPage> {
  late final TextEditingController _texto;
  final _foco = FocusNode();

  /// Hay un guardado en curso: no admite otro toque, no deja salir y bloquea el campo.
  var _enviando = false;

  /// Se tocó «Guardar» con la nota en blanco: desde ahí el campo muestra el error.
  var _intentado = false;

  /// La última falla al guardar (E·07); `null` si no hay.
  Failure? _falla;

  /// El id de la nota nueva, creado con el primer intento y repetido en los siguientes.
  String? _id;

  bool get _esEdicion => widget.nota != null;

  @override
  void initState() {
    super.initState();
    _texto = TextEditingController(text: widget.nota?.texto ?? '');
  }

  @override
  void dispose() {
    _texto.dispose();
    _foco.dispose();
    super.dispose();
  }

  bool get _sirve => ValidadorNota.problema(_texto.text) == null;

  /// Hay algo escrito que se perdería al salir: una nota nueva con texto, o una edición distinta de la
  /// nota original.
  bool get _hayCambios {
    final original = widget.nota;
    final escrito = _texto.text;
    if (original == null) return ValidadorNota.limpiar(escrito).isNotEmpty;
    return ValidadorNota.limpiar(escrito) != original.texto;
  }

  /// Se está preguntando si se descarta (un segundo toque en la ✕ no abre otro aviso).
  var _preguntando = false;

  /// La ✕ y el atrás del sistema: sin cambios cierran directo; con texto sin guardar preguntan antes.
  Future<void> _salir() async {
    if (_enviando || _preguntando) return;
    if (!_hayCambios) {
      Navigator.of(context).pop();
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
    Navigator.of(context).pop();
  }

  String? get _error {
    final problema = ValidadorNota.problema(_texto.text);
    return _intentado && problema != null ? ValidadorNota.mensaje(problema) : null;
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
      setState(() => _intentado = true);
      _foco.requestFocus();
      _anunciar(ValidadorNota.mensaje(ProblemaNota.vacia));
      return;
    }
    final original = widget.nota;
    if (original != null && ValidadorNota.limpiar(_texto.text) == original.texto) {
      // Nada cambió: no hay nada que escribir.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _enviando = true;
      _falla = null;
    });
    Failure? falla;
    NotaPersona? guardada;
    try {
      if (original != null) {
        final resultado = await ref.read(editarNotaPersonaUseCaseProvider)(
          EditarNotaPersonaParams(notaId: original.id, texto: _texto.text),
        );
        resultado.fold((f) => falla = f, (n) => guardada = n);
      } else {
        final id = _id ??= ref.read(generadorIdPersonaProvider)();
        final resultado = await ref.read(agregarNotaPersonaUseCaseProvider)(
          AgregarNotaPersonaParams(
            id: id,
            personaId: widget.personaId,
            colportorId: widget.colportorId,
            texto: _texto.text,
          ),
        );
        resultado.fold((f) => falla = f, (n) => guardada = n);
      }
    } on Object catch (e) {
      // Nada de `e` al mensaje: puede traer lo escrito (convenciones §7.5).
      falla = FailureInesperado(causa: e.runtimeType.toString());
    }
    if (!mounted) return;
    final exito = guardada;
    if (exito != null) {
      Navigator.of(context).pop<NotaGuardada>((nota: exito, esNueva: !_esEdicion));
      return;
    }
    setState(() {
      _enviando = false;
      _falla = falla;
    });
  }

  /// Si la persistencia dijo por qué (la persona en solo lectura, la nota que ya no está), esa
  /// frase guía; si no, la de la vista.
  String get _textoFalla {
    final f = _falla;
    if (f is FailureValidacion) {
      final motivo = f.campos['persona'] ?? f.campos['nota'];
      if (motivo != null) return motivo;
    }
    return TextosNotas.noPudimosGuardar;
  }

  @override
  Widget build(BuildContext context) {
    final conFalla = _falla != null;
    final largo = ValidadorNota.largo(_texto.text);
    final muyLarga = ValidadorNota.superaElLimite(_texto.text);

    return PopScope(
      // Mientras se guarda no se sale (el resultado se perdería) y con texto sin guardar se pregunta.
      canPop: !_enviando && !_hayCambios,
      onPopInvokedWithResult: (salio, _) {
        if (!salio && !_enviando) unawaited(_salir());
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: CabeceraNotas(
                  icono: Icons.close,
                  tooltip: TextosNotas.cerrar,
                  alTocar: _enviando ? null : _salir,
                ),
              ),
              TituloNotas(titulo: _esEdicion ? TextosNotas.tituloEditar : TextosNotas.tituloNueva),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AvisoPrivacidadPersona(texto: TextosNotas.privacidad),
                      const SizedBox(height: 16),
                      if (conFalla) ...[
                        AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: _textoFalla),
                        const SizedBox(height: 12),
                      ],
                      _CampoNota(
                        controlador: _texto,
                        foco: _foco,
                        bloqueado: _enviando,
                        error: _error,
                        alCambiar: (_) => setState(() {}),
                      ),
                      if (muyLarga) ...[
                        const SizedBox(height: 12),
                        AvisoAlta(
                          color: ColoresAlta.ambarBorde,
                          colorInsignia: ColoresAlta.ambar,
                          glyph: '!',
                          texto: TextosNotas.notaLarga(largo),
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
                    BotonAccionPersona(
                      etiqueta: conFalla ? TextosNotas.reintentar : TextosNotas.guardarNota,
                      etiquetaEnviando: TextosNotas.guardando,
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

/// El campo de la nota: texto libre de varios renglones, con el foco puesto al abrir (E·02).
class _CampoNota extends StatelessWidget {
  const _CampoNota({
    required this.controlador,
    required this.foco,
    required this.bloqueado,
    required this.error,
    required this.alCambiar,
  });

  final TextEditingController controlador;
  final FocusNode foco;
  final bool bloqueado;
  final String? error;
  final ValueChanged<String> alCambiar;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    OutlineInputBorder borde(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: 1.5),
    );
    return Semantics(
      label: TextosNotas.etiquetaCampo,
      child: TextField(
        key: ClavesNotas.campo,
        controller: controlador,
        focusNode: foco,
        autofocus: true,
        readOnly: bloqueado,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        minLines: 6,
        maxLines: null,
        onChanged: alCambiar,
        style: const TextStyle(fontSize: 15, height: 1.4),
        decoration: InputDecoration(
          hintText: TextosNotas.sugerenciaNota,
          errorText: error,
          errorMaxLines: 6,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: borde(ColoresAlta.grisBorde),
          enabledBorder: borde(ColoresAlta.grisBorde),
          focusedBorder: borde(navy),
          errorBorder: borde(ColoresAlta.rojo),
          focusedErrorBorder: borde(ColoresAlta.rojo),
        ),
      ),
    );
  }
}
