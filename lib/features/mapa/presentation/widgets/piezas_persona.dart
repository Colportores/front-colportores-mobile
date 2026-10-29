import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../configuracion/presentation/providers/aviso_privacidad_providers.dart';
import '../textos_personas.dart';
import 'campos_ubicacion.dart' show EtiquetaCampoUbicacion;
import 'piezas_alta.dart';

// Las piezas de los formularios de personas, compartidas por el alta (32A) y el paso «¿Con quién?» de la
// vista 39 (R·04): el candado, el campo y el botón de acción.

/// Las claves de las piezas de los formularios de personas, para los tests y el QA.
abstract final class ClavesAvisoPrivacidad {
  static const aviso = Key('aviso_privacidad_persona');
  static const noVolverAMostrar = Key('aviso_privacidad_no_volver_a_mostrar');
  static const escondido = Key('aviso_privacidad_escondido');
  static const falla = Key('aviso_privacidad_falla');
}

/// El candado de privacidad (canvas 32A, `Bloques` · banner «lock»): lo primero que se lee, antes de
/// pedir datos de otra persona. Lleva «No volver a mostrar» (decisión de Cristian, 23/10, «Aviso
/// privado», #445): la preferencia es **por cuenta** ([colportorId]) y la misma que usan las notas
/// (#447); se vuelve a encender desde Configuración, «Mostrar el aviso de privacidad».
///
/// - Escondido, no ocupa lugar. Al esconderlo en este momento queda una línea que dice cómo volver a
///   verlo (todo aviso guía al usuario): se va con la pantalla.
/// - Si la preferencia no se pudo guardar, el aviso sigue a la vista y lo dice; se puede volver a
///   tocar. Un doble toque guarda una sola vez.
/// - Mientras se lee la preferencia, o si no se pudo leer, se ve: ante la duda, el aviso.
class AvisoPrivacidadPersona extends ConsumerStatefulWidget {
  const AvisoPrivacidadPersona({
    super.key,
    required this.colportorId,
    this.texto = TextosPersonas.privacidad,
  });

  /// UUID del usuario con la sesión iniciada: la preferencia es de su cuenta. Sin él (`null`) no hay
  /// de quién guardar la preferencia: el aviso se ve siempre y no ofrece esconderse.
  final String? colportorId;

  /// El aviso: el de los datos de una persona, o el de sus notas («Estas notas viven solo en tu
  /// celular.», vista 32E). La preferencia de esconderlo es la misma para todos.
  final String texto;

  @override
  ConsumerState<AvisoPrivacidadPersona> createState() => _AvisoPrivacidadPersonaState();
}

class _AvisoPrivacidadPersonaState extends ConsumerState<AvisoPrivacidadPersona> {
  /// Se está guardando la preferencia. Es un campo: la guarda corta el segundo toque aunque llegue
  /// antes de que se vuelva a dibujar.
  bool _guardando = false;

  /// Lo acabo de esconder yo en esta pantalla: queda la línea que dice cómo recuperarlo.
  bool _recienEscondido = false;

  /// La última vez no se pudo guardar.
  bool _fallo = false;

  /// Para llevar a la vista el aviso de la falla si la pantalla estaba desplazada: con el texto
  /// grande queda bajo el pliegue y la persona no vería nada pasar (QA #445).
  final _claveFalla = GlobalKey();

  Future<void> _noVolverAMostrar() async {
    final cuenta = widget.colportorId;
    if (_guardando || cuenta == null) return;
    _guardando = true;
    setState(() => _fallo = false);
    var guardado = false;
    try {
      guardado = await ref.read(avisoPrivacidadOcultoProvider(cuenta).notifier).ocultar();
    } finally {
      _guardando = false;
    }
    if (!mounted) return;
    setState(() {
      _recienEscondido = guardado;
      _fallo = !guardado;
    });
    if (!guardado) _mostrarLaFalla();
  }

  void _mostrarLaFalla() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _claveFalla.currentContext;
      if (!mounted || contexto == null) return;
      // Al medio de la vista: arriba quedaría pegado al borde y cortaría el «No volver a mostrar» de
      // arriba; abajo, bajo la barra de acciones.
      unawaited(
        Scrollable.ensureVisible(
          contexto,
          alignment: .5,
          duration: const Duration(milliseconds: 150),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cuenta = widget.colportorId;
    final oculto = cuenta == null
        ? false
        : ref.watch(avisoPrivacidadOcultoProvider(cuenta)).value ?? false;
    if (oculto) {
      return _recienEscondido ? const _AvisoEscondido() : const SizedBox.shrink();
    }
    final navy = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Container(
          key: ClavesAvisoPrivacidad.aviso,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F6FB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: navy.withValues(alpha: .25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(Icons.lock_outline, size: 20, color: navy)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      container: true,
                      label: widget.texto,
                      child: ExcludeSemantics(
                        child: Text(
                          widget.texto,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: navy, height: 1.4),
                        ),
                      ),
                    ),
                    if (cuenta != null)
                      _NoVolverAMostrar(alTocar: _noVolverAMostrar, guardando: _guardando)
                    else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_fallo)
          Semantics(
            key: _claveFalla,
            liveRegion: true,
            child: const Text(
              TextosPersonas.noPudimosGuardarElAviso,
              key: ClavesAvisoPrivacidad.falla,
              style: TextStyle(fontSize: 13, height: 1.4, color: ColoresAlta.rojo),
            ),
          ),
      ],
    );
  }
}

/// «☐ No volver a mostrar» (canvas: casilla de 18 con borde de 2 y texto de 13), con un objetivo
/// táctil de 48 dp. Es una acción de un toque, no un interruptor: al tocarla el aviso se esconde.
class _NoVolverAMostrar extends StatelessWidget {
  const _NoVolverAMostrar({required this.alTocar, required this.guardando});

  final VoidCallback alTocar;
  final bool guardando;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: !guardando,
      label: TextosPersonas.noVolverAMostrar,
      onTap: guardando ? null : alTocar,
      excludeSemantics: true,
      child: InkWell(
        key: ClavesAvisoPrivacidad.noVolverAMostrar,
        borderRadius: BorderRadius.circular(8),
        onTap: guardando ? null : alTocar,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            spacing: 8,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFF5B6B82), width: 2),
                ),
              ),
              const Flexible(
                child: Text(
                  TextosPersonas.noVolverAMostrar,
                  style: TextStyle(fontSize: 13, height: 1.3, color: ColoresAlta.tinta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo que queda donde estaba el aviso justo después de esconderlo: cómo volver a verlo.
class _AvisoEscondido extends StatelessWidget {
  const _AvisoEscondido();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: const Text(
        TextosPersonas.avisoEscondido,
        key: ClavesAvisoPrivacidad.escondido,
        style: TextStyle(fontSize: 13, height: 1.4, color: ColoresAlta.gris),
      ),
    );
  }
}

/// Un campo del formulario: la etiqueta mono de arriba, el cuadro con borde de 1,5 y el error debajo.
class CampoPersona extends StatelessWidget {
  const CampoPersona({
    super.key,
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

/// La acción de un formulario de personas («Guardar persona», «Reintentar», «Empezar entrevista»).
/// Apagada a la vista cuando el formulario no sirve, pero tocable (el toque dice qué falta); trabajando,
/// muestra [etiquetaEnviando] y no admite otro toque.
class BotonAccionPersona extends StatelessWidget {
  const BotonAccionPersona({
    super.key,
    required this.etiqueta,
    required this.aspectoApagado,
    required this.enviando,
    required this.alTocar,
    this.etiquetaEnviando = TextosPersonas.guardando,
    this.habilitado = true,
  });

  final String etiqueta;
  final bool aspectoApagado;
  final bool enviando;
  final VoidCallback alTocar;
  final String etiquetaEnviando;

  /// `false`: el botón no admite toques (no es el «apagado» de [aspectoApagado], que sí los admite).
  final bool habilitado;

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
      onPressed: enviando || !habilitado ? null : alTocar,
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
                Flexible(child: Text(etiquetaEnviando)),
              ],
            )
          : Text(etiqueta, textAlign: TextAlign.center),
    );
  }
}
