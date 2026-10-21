import 'package:flutter/material.dart';

import 'hoja_modificar.dart';
import 'piezas_alta.dart';

/// Hasta este factor del texto del sistema (el 200 % de AA) los avisos se ven como siempre —título y
/// cuerpo en la zona que se desplaza y las dos acciones fijas al pie— salvo que en el teléfono alguna
/// palabra no entre en el aviso de siempre (#379): entonces es el aviso grande. Con más, siempre el grande.
const _factorDelAvisoNormal = 2.0;

/// Margen del aviso de siempre a los costados: el `insetPadding` de un `Dialog` (40 dp).
const _margenDelAvisoNormal = 40.0;

/// Relleno lateral del título, del cuerpo y de las acciones de un `AlertDialog` de Material 3 antes de
/// escalarlo (24 dp).
const _rellenoLateralDelAvisoNormal = 24.0;

/// Margen del aviso a los costados cuando el texto pasa de [_factorDelAvisoNormal]: casi todo el ancho.
const _margenDelAvisoGrande = 16.0;

/// Relleno lateral del título y del cuerpo de un `AlertDialog`: 24 dp, que él mismo reduce a un tercio
/// con el texto al 200 % o más (`_scalePadding` de Flutter).
const _rellenoLateralDelAvisoGrande = 24.0 / 3;

/// Donde se parte una frase en palabras: los espacios corrientes. El que no se parte (U+00A0) une.
final _espacios = RegExp(r'[ \n\t]+');

/// Relleno horizontal de las etiquetas de los botones: el de `FilledButton` en el tema de la app
/// (`tema_colportaje.dart`), que es el más ancho de los dos botones.
const _rellenoDelBoton = 24.0;

/// El aviso de la vista 07·04: «¿Descartar los cambios?». Devuelve `true` si el colportor eligió
/// «Descartar»; `false` con «Seguir editando» o si cerró el aviso de otro modo.
Future<bool> confirmarDescartarCambios(BuildContext context, List<String> cambios) {
  return _preguntar(
    context,
    titulo: TextosModificar.descartarTitulo,
    cuerpo: TextosModificar.descartarCuerpo(cambios),
    paraNo: TextosModificar.seguirEditando,
    paraSi: TextosModificar.descartar,
    colorDelSi: ColoresAlta.rojo,
  );
}

/// Una pregunta del guardado que el colportor tiene que contestar con «Confirmar» o «Cancelar»:
/// reactivar la ubicación, cambiarle la ciudad o moverla más de 100 m. [texto] es el aviso de la HU
/// tal cual. Devuelve `true` si confirmó.
Future<bool> confirmarModificacion(BuildContext context, {required String texto}) {
  return _preguntar(
    context,
    cuerpo: texto,
    paraNo: TextosModificar.cancelar,
    paraSi: TextosModificar.confirmar,
  );
}

Future<bool> _preguntar(
  BuildContext context, {
  String? titulo,
  required String cuerpo,
  required String paraNo,
  required String paraSi,
  Color? colorDelSi,
}) async {
  final respuesta = await showDialog<bool>(
    context: context,
    builder: (_) => _Aviso(
      titulo: titulo,
      cuerpo: cuerpo,
      paraNo: paraNo,
      paraSi: paraSi,
      colorDelSi: colorDelSi,
    ),
  );
  return respuesta ?? false;
}

/// Un aviso de dos respuestas: la que deja todo como está ([paraNo]) y la que sigue ([paraSi]).
///
/// Hasta el 200 % del texto del sistema es un `AlertDialog` común, con las acciones fijas al pie, si en
/// ese teléfono ninguna palabra se parte por dentro; en uno de 320–340 dp ya desde 1,8× «Descartar» o
/// «Confirmar» se partían (#379) y va el aviso de abajo. Con más del 200 % va siempre el de abajo: en un
/// teléfono chico ya no alcanza el alto (con el teclado todavía bajando, 300 dp, las acciones fijas
/// desbordaban) y con el título a 3× una palabra no entraba y se partía por dentro («Descart/ar», #358).
/// Entonces el aviso:
/// - ocupa casi todo el ancho de la pantalla;
/// - lleva las dos acciones DENTRO de la zona que se desplaza, así que no hay nada fijo que pueda
///   desbordar mientras sube o baja el teclado;
/// - limita el texto del aviso al mayor tamaño en el que ninguna palabra se parte, sin bajar nunca
///   de 2×.
class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.titulo,
    required this.cuerpo,
    required this.paraNo,
    required this.paraSi,
    required this.colorDelSi,
  });

  final String? titulo;
  final String cuerpo;
  final String paraNo;
  final String paraSi;
  final Color? colorDelSi;

  @override
  Widget build(BuildContext context) {
    final factor = _factorDe(MediaQuery.textScalerOf(context));
    return LayoutBuilder(
      builder: (context, caja) {
        if (factor <= _factorDelAvisoNormal && _entraEnElDeSiempre(context, caja.maxWidth)) {
          return _normal(context);
        }
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: _factorQueEntra(context, caja.maxWidth),
          child: _grande(context),
        );
      },
    );
  }

  Widget _botonNo(BuildContext context) => TextButton(
    onPressed: () => Navigator.of(context).pop(false),
    style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
    child: Text(paraNo),
  );

  Widget _botonSi(BuildContext context) => FilledButton(
    onPressed: () => Navigator.of(context).pop(true),
    style: FilledButton.styleFrom(backgroundColor: colorDelSi, minimumSize: const Size(64, 48)),
    child: Text(paraSi),
  );

  Widget _normal(BuildContext context) => AlertDialog(
    // Con el texto del sistema muy grande el aviso no entra en la pantalla: se desplaza y los dos
    // botones siguen a mano (#324).
    scrollable: true,
    title: titulo == null ? null : Text(titulo!),
    content: Text(cuerpo),
    actions: [_botonNo(context), _botonSi(context)],
  );

  Widget _grande(BuildContext context) => _AvisoGrande(
    titulo: titulo,
    cuerpo: cuerpo,
    // Como las acciones de un `AlertDialog` (a la derecha y una sobre otra si no entran), pero
    // adentro de lo que se desplaza.
    acciones: OverflowBar(
      alignment: MainAxisAlignment.end,
      spacing: 8,
      overflowAlignment: OverflowBarAlignment.end,
      overflowSpacing: 8,
      children: [_botonNo(context), _botonSi(context)],
    ),
  );

  /// Si en el aviso de siempre, en una pantalla de [anchoDeLaPantalla], ninguna palabra del título, del
  /// cuerpo ni de los botones es más ancha que su renglón con el texto al tamaño del sistema (si no,
  /// Flutter la parte por dentro: «Descart/ar», #379). Es la misma medida que usa [_factorQueEntra], con
  /// los anchos del `AlertDialog`: la pantalla menos 40 dp a cada lado, el relleno de 24 dp que el
  /// `AlertDialog` baja a un tercio entre 1× y 2×, y las acciones con 24 dp de margen más el relleno de
  /// cada botón.
  bool _entraEnElDeSiempre(BuildContext context, double anchoDeLaPantalla) {
    final escalador = MediaQuery.textScalerOf(context);
    final factor = _factorDe(escalador);
    final reduccion = 1 - (factor.clamp(1.0, 2.0) - 1) * 2 / 3;
    final ancho = anchoDeLaPantalla - 2 * _margenDelAvisoNormal;
    final anchoDelTexto = ancho - 2 * _rellenoLateralDelAvisoNormal * reduccion;
    final anchoDeLasAcciones = ancho - 2 * _rellenoLateralDelAvisoNormal;
    return _entran(
      context,
      escalador,
      anchoDelTexto: anchoDelTexto,
      anchoDelNo: anchoDeLasAcciones - 2 * _rellenoDelTextButton(factor),
      anchoDelSi: anchoDeLasAcciones - 2 * _rellenoDelBoton,
    );
  }

  /// Si con el texto a [escala] ninguna palabra del aviso queda más ancha que el renglón donde se
  /// escribe: el título y el cuerpo en [anchoDelTexto], cada botón en el ancho de su etiqueta.
  bool _entran(
    BuildContext context,
    TextScaler escala, {
    required double anchoDelTexto,
    required double anchoDelNo,
    required double anchoDelSi,
  }) {
    final tema = Theme.of(context);
    final dialogos = DialogTheme.of(context);
    final direccion = Directionality.of(context);
    final etiquetaDeSi =
        tema.filledButtonTheme.style?.textStyle?.resolve(const {}) ?? tema.textTheme.labelLarge;
    final piezas = <({String texto, TextStyle? estilo, double ancho})>[
      if (titulo != null)
        (
          texto: titulo!,
          estilo: dialogos.titleTextStyle ?? tema.textTheme.headlineSmall,
          ancho: anchoDelTexto,
        ),
      (
        texto: cuerpo,
        estilo: dialogos.contentTextStyle ?? tema.textTheme.bodyMedium,
        ancho: anchoDelTexto,
      ),
      (texto: paraNo, estilo: tema.textTheme.labelLarge, ancho: anchoDelNo),
      (texto: paraSi, estilo: etiquetaDeSi, ancho: anchoDelSi),
    ];
    for (final pieza in piezas) {
      for (final palabra in pieza.texto.split(_espacios)) {
        final pintor = TextPainter(
          text: TextSpan(text: palabra, style: pieza.estilo),
          textDirection: direccion,
          textScaler: escala,
        )..layout();
        final ancho = pintor.width;
        pintor.dispose();
        if (ancho + .01 > pieza.ancho) return false;
      }
    }
    return true;
  }

  /// El mayor factor de texto, de 2× hasta el del sistema, con el que ninguna palabra del aviso grande
  /// queda más ancha que el renglón donde se escribe (si no, Flutter la parte por dentro). Si ni a 2×
  /// entra, 2×: el aviso no baja de ahí. Con el texto del sistema por debajo de 2× (#379) no hay nada
  /// que limitar: el aviso grande lo muestra al tamaño del sistema.
  double _factorQueEntra(BuildContext context, double anchoDeLaPantalla) {
    final escalador = MediaQuery.textScalerOf(context);
    final anchoDelTexto =
        anchoDeLaPantalla - 2 * _margenDelAvisoGrande - 2 * _rellenoLateralDelAvisoGrande;
    final anchoDeLaEtiqueta = anchoDelTexto - 2 * _rellenoDelBoton;

    bool entra(double factor) => _entran(
      context,
      escalador.clamp(maxScaleFactor: factor),
      anchoDelTexto: anchoDelTexto,
      anchoDelNo: anchoDeLaEtiqueta,
      anchoDelSi: anchoDeLaEtiqueta,
    );

    final delSistema = _factorDe(escalador);
    if (delSistema <= _factorDelAvisoNormal || entra(delSistema)) return delSistema;
    var entraSeguro = _factorDelAvisoNormal;
    var noEntra = delSistema;
    for (var i = 0; i < 10; i++) {
      final medio = (entraSeguro + noEntra) / 2;
      if (entra(medio)) {
        entraSeguro = medio;
      } else {
        noEntra = medio;
      }
    }
    return entraSeguro;
  }
}

/// Por cuánto agranda el sistema el texto. Con un escalador no lineal (Android 14) depende del tamaño:
/// se mide con el de un texto de cuerpo (14).
double _factorDe(TextScaler escalador) => escalador.scale(14) / 14;

/// El relleno horizontal de un `TextButton` de Material 3 con el texto del sistema a [factor]: 12 dp,
/// que Flutter baja a 8 dp a 2× y a 4 dp a 3× (`ButtonStyleButton.scaledPadding`).
double _rellenoDelTextButton(double factor) => factor <= 1
    ? 12
    : factor < 2
    ? 12 + (8 - 12) * (factor - 1)
    : factor < 3
    ? 8 + (4 - 8) * (factor - 2)
    : 4;

/// El aviso grande: casi todo el ancho, con título, cuerpo y acciones en una misma zona que se
/// desplaza y una barra de desplazamiento siempre visible cuando no entran (#379): en un teléfono de
/// 320 dp con el texto al 200 % «Descartar» puede quedar debajo del borde y la barra avisa que hay más.
///
/// Arma por su cuenta lo que un `AlertDialog(scrollable: true)` haría con el título y el cuerpo (los
/// mismos estilos y rellenos que con el texto a 2× o más: un tercio de 24 dp) porque la barra tiene que
/// envolver la zona que se desplaza, no el aviso entero.
class _AvisoGrande extends StatefulWidget {
  const _AvisoGrande({required this.titulo, required this.cuerpo, required this.acciones});

  final String? titulo;
  final String cuerpo;
  final Widget acciones;

  @override
  State<_AvisoGrande> createState() => _AvisoGrandeState();
}

class _AvisoGrandeState extends State<_AvisoGrande> {
  final _controlador = ScrollController();

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final dialogos = DialogTheme.of(context);
    final titulo = widget.titulo;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: _margenDelAvisoGrande, vertical: 24),
      contentPadding: EdgeInsets.zero,
      content: ScrollbarTheme(
        data: const ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(ColoresAlta.gris),
          thickness: WidgetStatePropertyAll(4),
          radius: Radius.circular(2),
        ),
        child: Scrollbar(
          controller: _controlador,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _controlador,
            padding: EdgeInsets.fromLTRB(
              _rellenoLateralDelAvisoGrande,
              titulo == null ? 16 / 3 : _rellenoLateralDelAvisoGrande,
              _rellenoLateralDelAvisoGrande,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titulo != null) ...[
                  DefaultTextStyle(
                    style:
                        dialogos.titleTextStyle ??
                        tema.textTheme.headlineSmall!.copyWith(color: tema.colorScheme.onSurface),
                    child: Semantics(container: true, child: Text(titulo)),
                  ),
                  const SizedBox(height: 16),
                ],
                DefaultTextStyle(
                  style:
                      dialogos.contentTextStyle ??
                      tema.textTheme.bodyMedium!.copyWith(color: tema.colorScheme.onSurfaceVariant),
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: Text(widget.cuerpo),
                  ),
                ),
                const SizedBox(height: 24),
                widget.acciones,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
