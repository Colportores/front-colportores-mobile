import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../domain/entities/cliente_de_la_venta.dart';
import '../formato_venta.dart';

// Las piezas de la vista 27 (Registrar venta). Todas crecen con el texto (`textScaler` 2.0): nada
// tiene alto fijo salvo el mínimo táctil de 48.

const _borde = Color(0xFFE3E7EE);
const _verdeFondo = Color(0xFFDDE8D3);
const _verdeTinta = Color(0xFF1F6E3A);

TextStyle _estiloRotulo() => const TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 10.5,
  letterSpacing: 1.6,
  color: ColoresAgenda.gris,
);

/// El encabezado: botón de volver (‹ o ✕), «NUEVA VENTA · …», el título y, si hay, la línea de abajo.
class CabeceraVenta extends StatelessWidget {
  const CabeceraVenta({
    super.key,
    required this.eyebrow,
    required this.titulo,
    this.subtitulo,
    this.alVolver,
    this.cerrar = false,
  });

  final String eyebrow;
  final String titulo;
  final String? subtitulo;
  final VoidCallback? alVolver;

  /// «✕» en vez de «‹»: la pantalla abre y cierra el flujo entero.
  final bool cerrar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (alVolver != null)
                IconButton(
                  key: const Key('venta_atras'),
                  tooltip: TextosVenta.volver,
                  onPressed: alVolver,
                  icon: Icon(cerrar ? Icons.close : Icons.arrow_back),
                )
              else
                const SizedBox(width: 48, height: 48),
              Expanded(
                child: ExcludeSemantics(child: Text(eyebrow, style: _estiloRotulo())),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontFamily: 'SourceSerif4',
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ),
                if (subtitulo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitulo!,
                      style: const TextStyle(fontSize: 13.5, color: ColoresAgenda.gris),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La tarjeta del cliente («María Fernández», «Mataojo 2044 · Depto 3B»).
class TarjetaDelCliente extends StatelessWidget {
  const TarjetaDelCliente({super.key, required this.cliente});

  final ClienteDeLaVenta cliente;

  @override
  Widget build(BuildContext context) {
    final iniciales = _iniciales(cliente.nombre);
    return Semantics(
      container: true,
      label: '${cliente.nombre}, ${cliente.direccion}',
      child: ExcludeSemantics(
        child: Container(
          key: const Key('venta_cliente'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borde),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: ColoresAgenda.navy, shape: BoxShape.circle),
                child: Text(
                  iniciales,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cliente.nombre,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      cliente.direccion,
                      style: const TextStyle(fontSize: 12.5, color: ColoresAgenda.gris),
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

  static String _iniciales(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '·';
    final a = partes.first.characters.first;
    final b = partes.length > 1 ? partes.last.characters.first : '';
    return '$a$b'.toUpperCase();
  }
}

/// Un rótulo de sección («EN LA VENTA») con una acción a la derecha («+ Agregar»).
class RotuloDeSeccion extends StatelessWidget {
  const RotuloDeSeccion(this.texto, {super.key, this.textoAccion, this.alAccion});

  final String texto;
  final String? textoAccion;
  final VoidCallback? alAccion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(header: true, child: Text(texto, style: _estiloRotulo())),
          ),
          if (textoAccion != null)
            TextButton(
              key: const Key('venta_agregar'),
              onPressed: alAccion,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                textoAccion!,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: ColoresAgenda.azul,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Un campo de texto con su rótulo, un texto de ayuda y, si hay, un error (talonario repetido,
/// monto inválido). Con error el borde y el texto van en rojo, y el lector lo anuncia.
class CampoDeVenta extends StatelessWidget {
  const CampoDeVenta({
    super.key,
    required this.rotulo,
    required this.controlador,
    required this.alCambiar,
    this.ayuda,
    this.error,
    this.teclado,
    this.maxLargo,
    this.lineas = 1,
    this.hint,
    this.icono,
    this.habilitado = true,
    this.autofocus = false,
  });

  final String? rotulo;
  final TextEditingController controlador;
  final ValueChanged<String> alCambiar;
  final String? ayuda;
  final String? error;
  final TextInputType? teclado;
  final int? maxLargo;
  final int lineas;
  final String? hint;
  final IconData? icono;
  final bool habilitado;

  /// Abre el teclado al mostrarse (el monto del cobro, vista 28).
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final conError = error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rotulo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ExcludeSemantics(child: Text(rotulo!, style: _estiloRotulo())),
          ),
        Semantics(
          label: hint != null ? rotulo : null,
          child: TextField(
            controller: controlador,
            onChanged: alCambiar,
            enabled: habilitado,
            autofocus: autofocus,
            keyboardType: teclado,
            minLines: lineas,
            maxLines: lineas,
            maxLength: maxLargo,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            decoration: InputDecoration(
              // Con texto de ejemplo (`hint`) el rótulo no va adentro: taparía el ejemplo. El rótulo de
              // arriba es solo visual, así que el lector lo recibe por el `Semantics` de afuera.
              labelText: hint == null ? rotulo : null,
              floatingLabelBehavior: FloatingLabelBehavior.never,
              hintText: hint,
              prefixIcon: icono == null ? null : Icon(icono),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: conError ? ColoresAgenda.rojo : _borde),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: conError ? ColoresAgenda.rojo : _borde, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: conError ? ColoresAgenda.rojo : ColoresAgenda.azul,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        if (conError)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: ColoresAgenda.rojo,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else if (ayuda != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(ayuda!, style: const TextStyle(fontSize: 12.5, color: ColoresAgenda.gris)),
          ),
      ],
    );
  }
}

/// Un aviso arriba de la pantalla: error (27A·13) o advertencia.
class AvisoDeVenta extends StatelessWidget {
  const AvisoDeVenta({
    super.key,
    required this.texto,
    this.error = true,
    this.textoAccion,
    this.alAccion,
  });

  final String texto;
  final bool error;
  final String? textoAccion;
  final VoidCallback? alAccion;

  @override
  Widget build(BuildContext context) {
    final color = error ? ColoresAgenda.rojo : ColoresAgenda.ambarTinta;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: error ? Colors.white : ColoresAgenda.ambarFondo,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              texto,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: error ? ColoresAgenda.tinta : color,
              ),
            ),
            if (textoAccion != null)
              TextButton(
                key: const Key('venta_aviso_accion'),
                onPressed: alAccion,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  textoAccion!,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Un chip de categoría («Colecciones», «Libros»…).
class ChipDeVenta extends StatelessWidget {
  const ChipDeVenta({
    super.key,
    required this.texto,
    required this.elegido,
    required this.alPresionar,
  });

  final String texto;
  final bool elegido;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: elegido,
      label: texto,
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: alPresionar,
          borderRadius: BorderRadius.circular(999),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              widthFactor: 1,
              child: Container(
                constraints: const BoxConstraints(minHeight: 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: elegido ? ColoresAgenda.navy : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: elegido ? ColoresAgenda.navy : ColoresAgenda.bordeChip,
                    width: 1.5,
                  ),
                ),
                child: Align(
                  widthFactor: 1,
                  child: Text(
                    texto,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: elegido ? Colors.white : ColoresAgenda.tinta,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Una fila que se elige (una colección, un libro de la hoja): título, detalle y, a la derecha, el
/// precio si hay.
class FilaElegible extends StatelessWidget {
  const FilaElegible({
    super.key,
    required this.titulo,
    required this.elegida,
    required this.alPresionar,
    this.detalle,
    this.precio,
  });

  final String titulo;
  final String? detalle;
  final String? precio;
  final bool elegida;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: elegida,
      inMutuallyExclusiveGroup: true,
      label: [titulo, ?detalle, ?precio].join('. '),
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: alPresionar,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: elegida ? ColoresAgenda.azulFondo : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: elegida ? ColoresAgenda.azul : _borde,
                width: elegida ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      if (detalle != null)
                        Text(
                          detalle!,
                          style: const TextStyle(fontSize: 12, color: ColoresAgenda.gris),
                        ),
                    ],
                  ),
                ),
                if (precio != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      precio!,
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (elegida)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle, color: ColoresAgenda.azul, size: 22),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un libro de la colección: lo que siempre va (con ⊙) o un lugar para elegir (27A·02 a 27A·06).
class TarjetaDeLibro extends StatelessWidget {
  const TarjetaDeLibro({
    super.key,
    required this.glifo,
    required this.titulo,
    this.rotulo,
    this.detalle,
    this.accion,
    this.alPresionar,
    this.vacia = false,
  });

  final String glifo;
  final String titulo;

  /// «LIBRO 1».
  final String? rotulo;
  final String? detalle;

  /// «Cambiar», «›» o «⊙».
  final String? accion;
  final VoidCallback? alPresionar;

  /// Un lugar sin libro: borde punteado y el título en azul.
  final bool vacia;

  @override
  Widget build(BuildContext context) {
    final fijo = alPresionar == null;
    final contenido = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: fijo ? ColoresAgenda.grisFondo : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vacia ? ColoresAgenda.bordeChip : _borde, width: vacia ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fijo || vacia ? ColoresAgenda.grisFondo : ColoresAgenda.navy,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              glifo,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fijo || vacia ? ColoresAgenda.gris : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rotulo != null) Text(rotulo!, style: _estiloRotulo()),
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: vacia ? ColoresAgenda.azul : null,
                  ),
                ),
                if (detalle != null)
                  Text(detalle!, style: const TextStyle(fontSize: 12, color: ColoresAgenda.gris)),
              ],
            ),
          ),
          if (accion != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                accion!,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: fijo ? ColoresAgenda.gris : ColoresAgenda.azul,
                ),
              ),
            ),
        ],
      ),
    );
    if (fijo) {
      return Semantics(
        container: true,
        label: '$titulo${detalle == null ? '' : ', $detalle'}. Siempre va en la colección.',
        child: ExcludeSemantics(child: contenido),
      );
    }
    return Semantics(
      button: true,
      label: [?rotulo, titulo, ?(accion == '›' ? null : accion)].join('. '),
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: alPresionar,
          borderRadius: BorderRadius.circular(14),
          child: contenido,
        ),
      ),
    );
  }
}

/// Una fila de «EN LA VENTA»: la colección o el producto, su precio y la acción de quitarla.
class TarjetaDeRenglon extends StatelessWidget {
  const TarjetaDeRenglon({
    super.key,
    required this.rotulo,
    required this.titulo,
    required this.precio,
    this.detalle,
    this.alPresionar,
    this.alQuitar,
    this.glifo = '▣',
  });

  final String? rotulo;
  final String titulo;
  final String? detalle;
  final String precio;
  final String glifo;
  final VoidCallback? alPresionar;
  final VoidCallback? alQuitar;

  @override
  Widget build(BuildContext context) {
    final fila = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borde),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ColoresAgenda.navy,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              glifo,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rotulo != null) Text(rotulo!, style: _estiloRotulo()),
                Text(titulo, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                if (detalle != null)
                  Text(detalle!, style: const TextStyle(fontSize: 12, color: ColoresAgenda.gris)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              precio,
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: TextosVenta.quitar,
            onPressed: alQuitar,
            icon: const Icon(Icons.close, size: 20, color: ColoresAgenda.gris),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: alPresionar != null,
      label: [?rotulo, titulo, ?detalle, precio].join('. '),
      onTap: alPresionar,
      excludeSemantics: false,
      child: alPresionar == null
          ? fila
          : InkWell(onTap: alPresionar, borderRadius: BorderRadius.circular(14), child: fila),
    );
  }
}

/// Un producto suelto con su cantidad (27A·07 y 27A·08): nombre, etiqueta, precio y − n +.
class FilaDeCantidad extends StatelessWidget {
  const FilaDeCantidad({
    super.key,
    required this.titulo,
    required this.precio,
    required this.cantidad,
    required this.alCambiar,
    this.etiqueta,
    this.tintaEtiqueta = ColoresAgenda.ambarTinta,
    this.fondoEtiqueta = ColoresAgenda.ambarFondo,
    this.maximo = 999,
  });

  final String titulo;
  final String precio;
  final int cantidad;
  final ValueChanged<int> alCambiar;
  final String? etiqueta;
  final Color tintaEtiqueta;
  final Color fondoEtiqueta;
  final int maximo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$titulo. $precio. ${cantidad == 0 ? 'Ninguno' : '$cantidad'}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cantidad > 0 ? ColoresAgenda.azul : _borde,
            width: cantidad > 0 ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        precio,
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 12.5,
                          color: ColoresAgenda.gris,
                        ),
                      ),
                      if (etiqueta != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: fondoEtiqueta,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            etiqueta!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: tintaEtiqueta,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Uno menos de $titulo',
              onPressed: cantidad > 0 ? () => alCambiar(cantidad - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 24),
              child: Text(
                '$cantidad',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Uno más de $titulo',
              onPressed: cantidad < maximo ? () => alCambiar(cantidad + 1) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// El botón principal de abajo, con una nota debajo cuando está apagado («Elegí el libro 2 para
/// seguir.»). Apagado no es invisible: el lector dice por qué.
class BotonDeVenta extends StatelessWidget {
  const BotonDeVenta({
    super.key,
    required this.texto,
    required this.alPresionar,
    this.nota,
    this.ocupado = false,
    this.textoOcupado,
  });

  final String texto;
  final VoidCallback? alPresionar;
  final String? nota;

  /// Guardando: el botón no responde (un doble toque no hace nada) y lo dice con una ruedita.
  final bool ocupado;

  /// Lo que dice el botón mientras está [ocupado] («Registrando…»), al lado de la ruedita; sin él,
  /// solo la ruedita.
  final String? textoOcupado;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (nota != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              nota!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: ColoresAgenda.gris),
            ),
          ),
        FilledButton(
          key: const Key('venta_cta'),
          onPressed: ocupado ? null : alPresionar,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: ColoresAgenda.navy,
            // Un botón apagado de Material pinta el rótulo con `onSurface` al 38 %: ilegible sobre
            // azul. Ocupado («Registrando…») se ve lleno, como en el canvas; apagado por falta de
            // datos queda más claro, pero con el rótulo blanco.
            disabledBackgroundColor: ocupado
                ? ColoresAgenda.navy
                : ColoresAgenda.navy.withValues(alpha: .6),
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: ocupado
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    ),
                    if (textoOcupado != null) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          textoOcupado!,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                )
              : Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// El interruptor «Entregarlos sin cobrar» (27A·08).
class InterruptorDeVenta extends StatelessWidget {
  const InterruptorDeVenta({
    super.key,
    required this.titulo,
    required this.detalle,
    required this.valor,
    required this.alCambiar,
  });

  final String titulo;
  final String detalle;
  final bool valor;
  final ValueChanged<bool> alCambiar;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: valor ? _verdeFondo : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: valor ? _verdeTinta : _borde, width: valor ? 1.5 : 1),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          key: const Key('venta_sin_cobrar'),
          contentPadding: EdgeInsets.zero,
          title: Text(titulo, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          subtitle: Text(
            detalle,
            style: const TextStyle(fontSize: 12.5, color: ColoresAgenda.gris),
          ),
          value: valor,
          onChanged: alCambiar,
        ),
      ),
    );
  }
}

/// La pantalla mientras se leen los precios.
class EsqueletoDeVenta extends StatelessWidget {
  const EsqueletoDeVenta({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bloque(double alto) => Container(
      height: alto,
      decoration: BoxDecoration(
        color: ColoresAgenda.esqueleto,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: TextosVenta.cargandoPrecios,
      child: ExcludeSemantics(
        child: Column(
          key: const Key('venta_cargando'),
          children: [
            bloque(56),
            const SizedBox(height: 10),
            bloque(56),
            const SizedBox(height: 10),
            bloque(56),
          ],
        ),
      ),
    );
  }
}
