import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../domain/entities/catalogo_local.dart' show TipoDeProducto;
import '../../domain/entities/item_de_precio.dart';
import '../formato_precios.dart';

/// Los colores de la consulta de precios (vista 26) que el tema no cubre: los mismos de la agenda y
/// del resto de las vistas, más el verde de los misioneros.
abstract final class ColoresPrecios {
  static const navy = ColoresAgenda.navy;
  static const azul = ColoresAgenda.azul;
  static const azulFondo = ColoresAgenda.azulFondo;
  static const ambarFondo = ColoresAgenda.ambarFondo;
  static const ambarTinta = ColoresAgenda.ambarTinta;
  static const ambarBorde = Color(0xFFA98330);
  static const verdeFondo = Color(0xFFDDE8D3);
  static const verdeTinta = Color(0xFF1F6E3A);
  static const rojo = ColoresAgenda.rojo;
  static const tinta = ColoresAgenda.tinta;
  static const gris = ColoresAgenda.gris;
  static const esqueleto = ColoresAgenda.esqueleto;
  static const borde = Color(0xFFE3E7EE);
}

/// `true` desde el 130 % (el «Grande» de Android): el precio ya no cabe al lado del nombre y baja
/// debajo de él.
bool textoGrandePrecios(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) >= 13;

/// El encabezado: «VENTAS» y «Precios» (26·01 a 26·11).
class CabeceraPrecios extends StatelessWidget {
  const CabeceraPrecios({super.key, this.alVolver});

  /// Qué hace la flecha de atrás.
  final VoidCallback? alVolver;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('precios_atras'),
                tooltip: TextosPrecios.volver,
                onPressed: alVolver,
                icon: const Icon(Icons.arrow_back),
              ),
              const Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    TextosPrecios.eyebrow,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 2,
                      color: ColoresPrecios.navy,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 0, 10),
            child: Semantics(
              header: true,
              child: const Text(
                TextosPrecios.titulo,
                style: TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El cuadrito con el glifo de una fila o de la ciudad.
class _Glifo extends StatelessWidget {
  const _Glifo(this.texto, {this.fondo, this.tinta});

  final String texto;
  final Color? fondo;
  final Color? tinta;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fondo ?? ColoresPrecios.azulFondo,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          texto,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1,
            color: tinta ?? ColoresPrecios.navy,
          ),
        ),
      ),
    );
  }
}

/// La ciudad que se está viendo (26·01, 26·05, 26·06): el rótulo de dónde sale, su nombre y «Ver otra».
class TarjetaDeCiudad extends StatelessWidget {
  const TarjetaDeCiudad({
    super.key,
    required this.rotulo,
    required this.ciudad,
    required this.alVerOtra,
  });

  /// «SEGÚN DÓNDE ESTÁS», «ESTÁS VIENDO OTRA CIUDAD» o «CIUDAD DE TU ZONA · SIN GPS».
  final String rotulo;
  final String ciudad;

  /// `null`: no hay otra ciudad que ver y «Ver otra» no se muestra.
  final VoidCallback? alVerOtra;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ColoresPrecios.borde),
      ),
      child: Row(
        children: [
          const _Glifo('◉'),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              container: true,
              label: '$rotulo. $ciudad',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      rotulo,
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 11,
                        letterSpacing: .4,
                        color: ColoresPrecios.gris,
                      ),
                    ),
                    Text(
                      ciudad,
                      key: const Key('precios_ciudad'),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (alVerOtra != null)
            TextButton(
              key: const Key('precios_ver_otra'),
              onPressed: alVerOtra,
              style: TextButton.styleFrom(
                foregroundColor: ColoresPrecios.azul,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text(TextosPrecios.verOtra),
            ),
        ],
      ),
    );
  }
}

/// El tipo de aviso de una franja (los `banner` del canvas).
enum TipoDeAviso {
  /// 26·05: informa, no alarma.
  info,

  /// 26·06 y el aviso de precios viejos: algo a tener en cuenta.
  advertencia,

  /// 26·09: sin conexión (borde punteado).
  sinConexion,

  /// 26·10: no se pudo leer.
  error,
}

/// Una franja de aviso con su ícono y, si corresponde, una acción (los `banner` del canvas).
class AvisoDePrecios extends StatelessWidget {
  const AvisoDePrecios({
    super.key,
    required this.tipo,
    required this.texto,
    this.textoAccion,
    this.alAccion,
  });

  final TipoDeAviso tipo;
  final String texto;
  final String? textoAccion;
  final VoidCallback? alAccion;

  @override
  Widget build(BuildContext context) {
    final (Color color, Color fondo, String icono) = switch (tipo) {
      TipoDeAviso.info => (ColoresPrecios.tinta, Colors.white, 'i'),
      TipoDeAviso.advertencia => (ColoresPrecios.ambarBorde, const Color(0xFFFFFDF6), '!'),
      TipoDeAviso.sinConexion => (ColoresPrecios.gris, Colors.white, '✕'),
      TipoDeAviso.error => (ColoresPrecios.rojo, Colors.white, '!'),
    };
    final contenido = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text(
                icono,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  texto,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, height: 1.45),
                ),
                if (alAccion != null)
                  TextButton(
                    onPressed: alAccion,
                    style: TextButton.styleFrom(
                      foregroundColor: ColoresPrecios.azul,
                      minimumSize: const Size(48, 48),
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      tapTargetSize: MaterialTapTargetSize.padded,
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(textoAccion ?? ''),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    // Se anuncia al aparecer: es un estado que cambia lo que se está viendo.
    return Semantics(liveRegion: true, container: true, child: contenido);
  }
}

/// La caja de búsqueda «Buscar por nombre o código» (26·02 y 26·07).
class CampoDeBusquedaPrecios extends StatelessWidget {
  const CampoDeBusquedaPrecios({
    super.key,
    required this.controlador,
    required this.alCambiar,
    required this.alBorrar,
  });

  final TextEditingController controlador;
  final ValueChanged<String> alCambiar;
  final VoidCallback alBorrar;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCFD6E1), width: 1.5),
      ),
      child: Row(
        children: [
          const ExcludeSemantics(
            child: Text('⌕', style: TextStyle(fontSize: 15, color: ColoresPrecios.gris)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('precios_busqueda'),
              controller: controlador,
              onChanged: alCambiar,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
              decoration: const InputDecoration(
                hintText: TextosPrecios.buscar,
                hintStyle: TextStyle(fontFamily: 'Inter', fontSize: 15, color: Color(0xFF6B7688)),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controlador,
            builder: (context, valor, _) => valor.text.isEmpty
                ? const SizedBox(width: 14)
                : IconButton(
                    key: const Key('precios_borrar_busqueda'),
                    tooltip: TextosPrecios.borrarBusqueda,
                    onPressed: alBorrar,
                    icon: const Text(
                      '✕',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    color: ColoresPrecios.gris,
                  ),
          ),
        ],
      ),
    );
  }
}

/// La caja de una fila de precios: tarjeta blanca de borde fino.
class _TarjetaDeFila extends StatelessWidget {
  const _TarjetaDeFila({required this.alTocar, required this.etiqueta, required this.hijo});

  final VoidCallback? alTocar;
  final String etiqueta;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        container: true,
        button: alTocar != null,
        label: etiqueta,
        onTap: alTocar,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ColoresPrecios.borde),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Material(
                color: Colors.transparent,
                child: alTocar == null ? hijo : InkWell(onTap: alTocar, child: hijo),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El precio, en mono. A texto grande baja debajo del nombre en vez de apretarlo.
class _Precio extends StatelessWidget {
  const _Precio(this.centavos);

  final int centavos;

  @override
  Widget build(BuildContext context) => Text(
    FormatoPrecios.monto(centavos),
    key: const Key('precio_monto'),
    style: const TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Color(0xFF0E1A2B),
    ),
  );
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, this.fondo, this.tinta);

  final String texto;
  final Color fondo;
  final Color tinta;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 3),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(99)),
    child: Text(
      texto,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: tinta,
      ),
    ),
  );
}

/// Una fila de producto (26·02): glifo, nombre, código, etiqueta (◆ Bonificable, ✦ Misionero,
/// Revista) y precio.
class FilaDeProducto extends StatelessWidget {
  const FilaDeProducto({super.key, required this.producto});

  final PrecioDeProducto producto;

  @override
  Widget build(BuildContext context) {
    final grande = textoGrandePrecios(context);
    final glifo = producto.esMisionero || producto.tipo == TipoDeProducto.misionero
        ? '✦'
        : producto.tipo == TipoDeProducto.revista
        ? '▤'
        : '▥';
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          producto.nombre,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
        ),
        if (producto.codigoEditor != null)
          Text(
            producto.codigoEditor!,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: ColoresPrecios.tinta),
          ),
        Wrap(
          spacing: 6,
          children: [
            if (producto.esBonificable)
              const _Etiqueta(
                TextosPrecios.bonificable,
                ColoresPrecios.azulFondo,
                ColoresPrecios.azul,
              ),
            if (producto.esMisionero || producto.tipo == TipoDeProducto.misionero)
              const _Etiqueta(
                TextosPrecios.misionero,
                ColoresPrecios.verdeFondo,
                ColoresPrecios.verdeTinta,
              ),
            if (producto.tipo == TipoDeProducto.revista)
              const _Etiqueta(
                TextosPrecios.revista,
                ColoresPrecios.ambarFondo,
                ColoresPrecios.ambarTinta,
              ),
          ],
        ),
        if (grande)
          Padding(padding: const EdgeInsets.only(top: 4), child: _Precio(producto.centavos)),
      ],
    );
    return _TarjetaDeFila(
      alTocar: null,
      etiqueta: FormatoPrecios.etiquetaDeFila(producto),
      hijo: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Glifo(glifo),
            const SizedBox(width: 12),
            Expanded(child: contenido),
            if (!grande) ...[const SizedBox(width: 8), _Precio(producto.centavos)],
          ],
        ),
      ),
    );
  }
}

/// Una fila de combo (26·01): la cantidad de libros a elegir, el nombre, lo que lleva, el precio por
/// libro y el precio del combo. Se toca para ver de qué se compone (26·03).
class FilaDeCombo extends StatelessWidget {
  const FilaDeCombo({super.key, required this.combo, required this.alTocar});

  final PrecioDeCombo combo;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final grande = textoGrandePrecios(context);
    final lleva = FormatoPrecios.componentes(combo);
    final porLibro = FormatoPrecios.porLibro(combo);
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          combo.nombre,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
        ),
        if (lleva.isNotEmpty)
          Text(
            lleva,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              height: 1.4,
              color: ColoresPrecios.tinta,
            ),
          ),
        if (porLibro != null)
          Text(
            porLibro,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: ColoresPrecios.gris),
          ),
        if (grande) Padding(padding: const EdgeInsets.only(top: 4), child: _Precio(combo.centavos)),
      ],
    );
    return _TarjetaDeFila(
      alTocar: alTocar,
      etiqueta: FormatoPrecios.etiquetaDeFila(combo),
      hijo: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Glifo(
              combo.librosAElegir > 0 ? '${combo.librosAElegir}' : '▣',
              fondo: ColoresPrecios.navy,
              tinta: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: contenido),
            if (!grande) ...[const SizedBox(width: 8), _Precio(combo.centavos)],
          ],
        ),
      ),
    );
  }
}

/// La carga (26·08): tres bloques grises donde irán las filas.
class EsqueletoDePrecios extends StatelessWidget {
  const EsqueletoDePrecios({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bloque() => Container(
      height: 66,
      decoration: BoxDecoration(
        color: ColoresPrecios.esqueleto,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: TextosPrecios.cargando,
      child: ExcludeSemantics(
        child: Column(
          key: const Key('precios_esqueleto'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            bloque(),
            const SizedBox(height: 8),
            bloque(),
            const SizedBox(height: 8),
            bloque(),
          ],
        ),
      ),
    );
  }
}
