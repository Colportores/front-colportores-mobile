import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/ubicacion.dart';
import '../formato_ubicaciones.dart';
import '../providers/alta_ubicacion_notifier.dart' show CampoDireccion, FuenteCampo;
import 'piezas_alta.dart';

/// Los campos de la ficha de una ubicación que comparten el alta (vista 03) y la edición (vista 07):
/// el tipo, la ciudad y la calle y el número. Los dos arman la misma hoja con los mismos campos; lo
/// que cambia es de dónde sale cada valor.
abstract final class TextosCampos {
  static const ciudadObligatoria = 'CIUDAD · OBLIGATORIA';
  static const calle = 'CALLE · OPCIONAL';
  static const numero = 'NÚMERO';
  static const delMapa = 'Del mapa';
  static const editado = 'Editado';
  static const cambiar = 'Cambiar';
  static const elegir = 'Elegir';
}

class SelectorTipoUbicacion extends StatelessWidget {
  const SelectorTipoUbicacion({super.key, required this.tipo, required this.alElegir});

  final TipoUbicacion? tipo;
  final ValueChanged<TipoUbicacion> alElegir;

  static const _iconos = {
    TipoUbicacion.casa: Icons.home_outlined,
    TipoUbicacion.negocio: Icons.storefront_outlined,
    TipoUbicacion.edificio: Icons.apartment_outlined,
  };

  static const _separacion = 8.0;

  /// Si la etiqueta más larga entra entera en un botón de la fila de tres: sin eso («Negoc/io»,
  /// «Edifici/o» con el texto al 200 %) los botones pasan a una columna, uno por renglón, con el
  /// ícono y la etiqueta lado a lado. Se mide con la escala de texto real del teléfono.
  static bool _entranEnFila(BuildContext context, double anchoDisponible) {
    final cantidad = TipoUbicacion.values.length;
    final anchoBoton = (anchoDisponible - _separacion * (cantidad - 1)) / cantidad;
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final escala = MediaQuery.textScalerOf(context);
    var masAncha = 0.0;
    for (final t in TipoUbicacion.values) {
      final medida = TextPainter(
        text: TextSpan(
          text: FormatoUbicaciones.tipo(t),
          style: base.merge(_BotonTipo.estiloEtiqueta(elegido: true)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: escala,
      )..layout();
      masAncha = math.max(masAncha, medida.width);
      medida.dispose();
    }
    // Relleno horizontal del botón (4 + 4) y el lugar del tilde del botón elegido (14 + 2).
    return masAncha + _BotonTipo.relleno + _BotonTipo.reservaTilde <= anchoBoton;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, caja) {
        final enFila = _entranEnFila(context, caja.maxWidth);
        final botones = [
          for (final t in TipoUbicacion.values)
            _BotonTipo(
              etiqueta: FormatoUbicaciones.tipo(t),
              icono: _iconos[t]!,
              elegido: tipo == t,
              enFila: enFila,
              alTocar: () => alElegir(t),
            ),
        ];
        if (!enFila) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final b in botones) ...[
                if (b != botones.first) const SizedBox(height: _separacion),
                b,
              ],
            ],
          );
        }
        return Row(
          children: [
            for (final b in botones) ...[
              if (b != botones.first) const SizedBox(width: _separacion),
              Expanded(child: b),
            ],
          ],
        );
      },
    );
  }
}

class _BotonTipo extends StatelessWidget {
  const _BotonTipo({
    required this.etiqueta,
    required this.icono,
    required this.elegido,
    required this.enFila,
    required this.alTocar,
  });

  final String etiqueta;
  final IconData icono;
  final bool elegido;

  /// `true`: ícono arriba y etiqueta abajo, en una fila de tres. `false`: un botón por renglón con
  /// el ícono a la izquierda de la etiqueta (texto grande o pantalla angosta).
  final bool enFila;
  final VoidCallback alTocar;

  static const relleno = 8.0;
  static const reservaTilde = 16.0;

  static TextStyle estiloEtiqueta({required bool elegido}) =>
      TextStyle(fontSize: 14, fontWeight: elegido ? FontWeight.w600 : FontWeight.w400);

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    final color = elegido ? Colors.white : ColoresAlta.tinta;
    final textoEtiqueta = Flexible(
      child: Text(
        etiqueta,
        textAlign: TextAlign.center,
        style: estiloEtiqueta(elegido: elegido).copyWith(color: color),
      ),
    );
    return Semantics(
      button: true,
      selected: elegido,
      inMutuallyExclusiveGroup: true,
      label: etiqueta,
      excludeSemantics: true,
      onTap: alTocar,
      child: Material(
        color: elegido ? navy : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: elegido ? navy : ColoresAlta.grisBorde, width: 1.5),
        ),
        child: InkWell(
          onTap: alTocar,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: enFila ? 60 : 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: relleno / 2, vertical: 6),
              child: enFila
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icono, size: 20, color: color),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (elegido) Icon(Icons.check, size: 14, color: color),
                            if (elegido) const SizedBox(width: 2),
                            textoEtiqueta,
                          ],
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icono, size: 20, color: color),
                        const SizedBox(width: 8),
                        if (elegido) Icon(Icons.check, size: 14, color: color),
                        if (elegido) const SizedBox(width: 2),
                        textoEtiqueta,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class EtiquetaCampoUbicacion extends StatelessWidget {
  const EtiquetaCampoUbicacion(this.texto, {super.key, this.insignia});

  final String texto;
  final Widget? insignia;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 2,
        children: [
          Text(
            texto,
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 10,
              letterSpacing: 1.4,
              color: ColoresAlta.gris,
            ),
          ),
          ?insignia,
        ],
      ),
    );
  }
}

/// La insignia de un campo («Editado», «Del mapa»). Entera: va en su propio renglón (pasa de línea
/// como un todo, ver [EtiquetaCampoUbicacion]) y, si ni así entra en el ancho del campo (texto
/// grande en una columna angosta), se achica en lugar de partir una palabra a mitad.
class InsigniaCampo extends StatelessWidget {
  const InsigniaCampo({
    super.key,
    required this.icono,
    required this.texto,
    required this.fondo,
    required this.color,
  });

  final IconData icono;
  final String texto;
  final Color fondo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(99)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              texto,
              softWrap: false,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class CampoDireccionUbicacion extends StatelessWidget {
  const CampoDireccionUbicacion({
    super.key,
    required this.etiqueta,
    required this.sugerencia,
    required this.campo,
    required this.controlador,
    required this.alCambiar,
    required this.limite,
    required this.accion,
    this.bloqueado = false,
  });

  final String etiqueta;
  final String sugerencia;
  final CampoDireccion campo;
  final TextEditingController controlador;
  final ValueChanged<String> alCambiar;
  final int limite;
  final TextInputAction accion;

  /// El campo no recibe teclas (por ejemplo, mientras se guarda): lo que se ve es lo que se guarda.
  final bool bloqueado;

  @override
  Widget build(BuildContext context) {
    final editado = campo.fuente == FuenteCampo.editado;
    final Widget? insignia = switch (campo.fuente) {
      FuenteCampo.delMapa => const InsigniaCampo(
        icono: Icons.my_location,
        texto: TextosCampos.delMapa,
        fondo: ColoresAlta.verdeFondo,
        color: ColoresAlta.verde,
      ),
      FuenteCampo.editado => const InsigniaCampo(
        icono: Icons.edit_outlined,
        texto: TextosCampos.editado,
        fondo: ColoresAlta.azulFondo,
        color: ColoresAlta.azul,
      ),
      FuenteCampo.vacio => null,
    };
    OutlineInputBorder borde(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: 1.5),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EtiquetaCampoUbicacion(etiqueta, insignia: insignia),
        const SizedBox(height: 6),
        TextField(
          controller: controlador,
          readOnly: bloqueado,
          onChanged: alCambiar,
          textInputAction: accion,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [
            // Una dirección pegada en varias líneas queda en una: el `\r` suelto (el que deja un
            // pegado con `\r\n`) y los separadores de línea de Unicode pasan a un espacio. El `\n`
            // lo descarta antes el formateador propio de Flutter para los campos de una línea
            // (`maxLines: 1`), que corre primero: un `\n` solo deja las palabras pegadas.
            FilteringTextInputFormatter.deny(RegExp(r'[\r\n  ]+'), replacementString: ' '),
            LengthLimitingTextInputFormatter(limite),
          ],
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: sugerencia,
            isDense: false,
            filled: true,
            fillColor: Colors.white,
            constraints: const BoxConstraints(minHeight: 48),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: borde(ColoresAlta.grisBorde),
            enabledBorder: borde(editado ? ColoresAlta.azul : ColoresAlta.grisBorde),
            focusedBorder: borde(Theme.of(context).colorScheme.primary),
          ),
        ),
      ],
    );
  }
}

/// El campo «Ciudad» de la ficha: el nombre, de dónde salió ([origen]: «detectada», «de tu zona»…) y
/// el enlace para cambiarla ([enlace]). Con [alTocar] en `null` no abre nada (no hay otra ciudad que
/// elegir).
class CampoCiudadUbicacion extends StatelessWidget {
  const CampoCiudadUbicacion({
    super.key,
    required this.nombre,
    required this.sinValor,
    required this.alTocar,
    this.origen,
    this.enlace,
    this.editada = false,
  });

  final String nombre;

  /// La ciudad es otra que la que estaba guardada: el rótulo lleva la insignia «Editado» (vista 07).
  final bool editada;

  /// El nombre es un texto de relleno («Sin ciudad», «Buscando la ciudad…»), no la ciudad: va en gris.
  final bool sinValor;
  final String? origen;
  final String? enlace;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EtiquetaCampoUbicacion(
          TextosCampos.ciudadObligatoria,
          insignia: editada
              ? const InsigniaCampo(
                  icono: Icons.edit_outlined,
                  texto: TextosCampos.editado,
                  fondo: ColoresAlta.azulFondo,
                  color: ColoresAlta.azul,
                )
              : null,
        ),
        const SizedBox(height: 6),
        Semantics(
          button: alTocar != null,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
            ),
            child: InkWell(
              onTap: alTocar,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  // `Wrap` en vez de `Row`: con el texto grande el origen y «Cambiar» pasan al
                  // renglón de abajo y el nombre de la ciudad usa todo el ancho, sin partirse a
                  // mitad de palabra («Montevide/o»).
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        nombre,
                        style: TextStyle(fontSize: 15, color: sinValor ? ColoresAlta.gris : null),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (origen != null) TextSpan(text: '$origen · '),
                            if (enlace != null)
                              TextSpan(
                                text: enlace,
                                style: const TextStyle(
                                  color: ColoresAlta.azul,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 12, color: ColoresAlta.tinta),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
