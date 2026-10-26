import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../textos_personas.dart';
import 'campos_ubicacion.dart' show EtiquetaCampoUbicacion;
import 'piezas_alta.dart';

// Las piezas de los formularios de personas, compartidas por el alta (32A) y el paso «¿Con quién?» de la
// vista 39 (R·04): el candado, el campo y el botón de acción.

/// El candado de privacidad (canvas 32A): lo primero que se lee, antes de pedir datos de otra persona.
class AvisoPrivacidadPersona extends StatelessWidget {
  const AvisoPrivacidadPersona({super.key, this.texto = TextosPersonas.privacidad});

  /// El aviso: el de los datos de una persona, o el de sus notas («Estas notas viven solo en tu
  /// celular.», vista 32E).
  final String texto;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    return Semantics(
      container: true,
      label: texto,
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
                  texto,
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
  });

  final String etiqueta;
  final bool aspectoApagado;
  final bool enviando;
  final VoidCallback alTocar;
  final String etiquetaEnviando;

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
                Flexible(child: Text(etiquetaEnviando)),
              ],
            )
          : Text(etiqueta, textAlign: TextAlign.center),
    );
  }
}
