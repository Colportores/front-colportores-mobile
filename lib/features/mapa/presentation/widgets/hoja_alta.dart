import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../domain/entities/resultado_alta_ubicacion.dart';
import '../../domain/entities/ubicacion.dart';
import '../formato_ubicaciones.dart';
import '../providers/alta_ubicacion_notifier.dart';
import 'piezas_alta.dart';

/// Textos de las vistas 03 y 04. Los literales de HU-UBI-001 van tal cual; el resto es propuesta
/// del diseño (en el canvas: «TEXTOS PROPUESTA») o provisorio, y está marcado.
abstract final class TextosAlta {
  static const titulo = 'Nueva ubicación';
  static const registrar = 'Registrar';
  static const registrando = 'Registrando…';
  static const cerrar = 'Cerrar';
  static const volverAMiUbicacion = 'Volver a mi ubicación';
  static const mover = 'Mové el mapa para ajustar el punto';
  static const tocar = 'Tocá donde está el lugar';
  static const calleActualizada = 'Calle actualizada';
  static const sinGpsAviso =
      'No tenemos tu ubicación. Tocá el mapa donde está el lugar o activá el GPS.';
  static const activarGps = 'Activar GPS';
  static const marcadoAMano = 'Marcado a mano';
  static const marcaElPunto = 'Marcá el punto en el mapa para registrar.';
  static const ajustarManualmente = 'Ajustar manualmente';
  static const continuar = 'Continuar';
  static const ciudadObligatoria = 'CIUDAD · OBLIGATORIA';
  static const calle = 'CALLE · OPCIONAL';
  static const numero = 'NÚMERO';
  static const delMapa = 'Del mapa';
  static const editado = 'Editado';
  static const cambiar = 'Cambiar';
  static const sinTiles = 'Sin tiles para esta zona. Descargá tu ciudad en Configuración.';

  // Provisorios: la HU y el canvas no los traen (se confirman con Cristian, ver el issue #193).
  static const elegiElTipo = 'Elegí el tipo de ubicación para registrar.';
  static const elegiLaCiudad = 'Elegí la ciudad para registrar.';
  static const elegiPrecision = 'Elegí «Ajustar manualmente» o «Continuar» para registrar.';
  static const buscandoGps = 'Buscando GPS…';
  static const buscandoCiudad = 'Buscando la ciudad…';
  static const reintentar = 'Reintentar';
  static const deTuCampania = 'de tu campaña';
  static const sinCiudades = 'Tu campaña todavía no tiene ciudades. Avisale a tu coordinador.';
  static const ciudadesNoLeidas = 'No pudimos leer las ciudades de tu campaña. Probá de nuevo.';

  /// Falla inesperada al guardar (decisión del 05/10, QA de #193): qué pasó y qué hacer. Las demás
  /// fallas siguen con su propio texto; la causa va solo al log, nunca a la pantalla.
  static const noPudimosGuardar =
      'No pudimos guardar la ubicación. Lo que cargaste sigue acá: probá de nuevo.';

  static String gps(double metros) => 'GPS ±${metros.round()} m';

  static String usar(String valor) => 'Usar $valor';
}

/// El texto del aviso rojo cuando no se pudo registrar, el mismo en la hoja del alta (vista 03) y en
/// la de duplicados (vista 04, «Crear igual»): la falla inesperada dice qué pasó y qué hacer
/// ([TextosAlta.noPudimosGuardar]); las demás pasan por [mensajePara] con la acción del alta.
String mensajeFallaAlta(Failure falla) => switch (falla) {
  FailureInesperado() => TextosAlta.noPudimosGuardar,
  _ => mensajePara(falla, accion: 'registrar la ubicación.'),
};

/// La hoja inferior de la vista 03: tipo, ciudad, calle, número y «Registrar».
///
/// - El tipo no viene preseleccionado: es obligatorio y elegirlo es un toque.
/// - Calle y número muestran «Del mapa» o «Editado»; si el colportor escribió un campo y el mapa
///   dice otra cosa, se ofrece «Usar …» sin pisarlo.
/// - Con el GPS impreciso (más de 50 m), «Registrar» espera a «Ajustar manualmente» o «Continuar».
/// - Mientras guarda, «Registrando…» y el botón deshabilitado.
class HojaAlta extends ConsumerStatefulWidget {
  const HojaAlta({
    super.key,
    required this.parametros,
    required this.alRegistrar,
    required this.alElegirCiudad,
  });

  final ParametrosAlta parametros;
  final VoidCallback alRegistrar;

  /// Abre la lista de ciudades de la campaña («Cambiar»).
  final VoidCallback alElegirCiudad;

  @override
  ConsumerState<HojaAlta> createState() => _HojaAltaState();
}

class _HojaAltaState extends ConsumerState<HojaAlta> {
  final _calle = TextEditingController();
  final _numero = TextEditingController();

  AltaUbicacionNotifier get _notificador =>
      ref.read(altaUbicacionProvider(widget.parametros).notifier);

  @override
  void dispose() {
    _calle.dispose();
    _numero.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proveedor = altaUbicacionProvider(widget.parametros);
    final estado = ref.watch(proveedor);
    ref.listen(proveedor.select((s) => s.calle), (_, c) {
      if (c.texto != _calle.text) _calle.text = c.texto;
    });
    ref.listen(proveedor.select((s) => s.numero), (_, n) {
      if (n.texto != _numero.text) _numero.text = n.texto;
    });
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Encabezado(estado: estado),
        if (estado.necesitaDecisionPrecision) ...[
          const SizedBox(height: 14),
          AvisoAlta(
            color: ColoresAlta.ambarBorde,
            colorInsignia: ColoresAlta.ambar,
            glyph: '!',
            texto: AltaConBajaPrecision.aviso,
            acciones: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _notificador.decidirPrecision,
                    style: _estiloAviso,
                    child: const Text(TextosAlta.ajustarManualmente, textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _notificador.decidirPrecision,
                    style: _estiloAviso,
                    child: const Text(TextosAlta.continuar, textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _SelectorTipo(tipo: estado.tipo, alElegir: _notificador.elegirTipo),
        const SizedBox(height: 14),
        _CampoCiudad(estado: estado, alTocar: widget.alElegirCiudad),
        if (estado.ciudad == null &&
            (estado.origenCiudad == OrigenCiudad.sinCiudades ||
                estado.origenCiudad == OrigenCiudad.noSePudoLeer)) ...[
          const SizedBox(height: 10),
          _AvisoCiudad(
            sinCiudades: estado.origenCiudad == OrigenCiudad.sinCiudades,
            alReintentar: _notificador.reintentarCiudad,
          ),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _CampoDireccion(
                etiqueta: TextosAlta.calle,
                sugerencia: 'Calle',
                campo: estado.calle,
                controlador: _calle,
                alCambiar: _notificador.editarCalle,
                limite: 120,
                accion: TextInputAction.next,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CampoDireccion(
                etiqueta: TextosAlta.numero,
                sugerencia: 'Nº',
                campo: estado.numero,
                controlador: _numero,
                alCambiar: _notificador.editarNumero,
                limite: 20,
                accion: TextInputAction.done,
              ),
            ),
          ],
        ),
        if (_diferencias(estado).isNotEmpty) ...[
          const SizedBox(height: 10),
          _PuntoEstaEn(
            estado: estado,
            alUsarCalle: _notificador.usarCalleDelMapa,
            alUsarNumero: _notificador.usarNumeroDelMapa,
          ),
        ],
        if (estado.falla != null) ...[
          const SizedBox(height: 14),
          AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: mensajeFallaAlta(estado.falla!)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: estado.puedeRegistrar ? widget.alRegistrar : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            disabledBackgroundColor: ColoresAlta.grisFondo,
            disabledForegroundColor: ColoresAlta.gris,
            minimumSize: const Size.fromHeight(52),
          ),
          child: Text(estado.guardando ? TextosAlta.registrando : TextosAlta.registrar),
        ),
        if (_porQueNo(estado) case final motivo?) ...[
          const SizedBox(height: 8),
          Text(
            motivo,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: ColoresAlta.gris, fontSize: 12.5),
          ),
        ],
      ],
    );
  }

  static const _estiloAviso = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 48)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
    textStyle: WidgetStatePropertyAll(
      TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  /// Por qué «Registrar» está deshabilitado, para que el colportor sepa qué falta.
  String? _porQueNo(AltaUbicacionState e) {
    if (e.guardando) return null;
    if (e.punto == null) return TextosAlta.marcaElPunto;
    if (e.necesitaDecisionPrecision) return TextosAlta.elegiPrecision;
    if (e.tipo == null) return TextosAlta.elegiElTipo;
    // Sin ciudad: buscándola, el campo lo dice; sin ciudades o sin poder leerlas, el aviso de arriba
    // dice qué hacer. Solo «por elegir» (varias ciudades y todavía sin punto) pide elegir.
    if (e.ciudad == null && e.origenCiudad == OrigenCiudad.porElegir) {
      return TextosAlta.elegiLaCiudad;
    }
    return null;
  }
}

/// Los campos que el colportor escribió y que el mapa ve distinto.
List<({bool esCalle, String valor})> _diferencias(AltaUbicacionState e) {
  String norm(String s) => s.trim().toLowerCase();
  final p = e.propuesta;
  if (p == null) return const [];
  final r = <({bool esCalle, String valor})>[];
  final calle = p.calle?.trim() ?? '';
  final numero = p.numero?.trim() ?? '';
  if (e.calle.fuente == FuenteCampo.editado &&
      calle.isNotEmpty &&
      norm(calle) != norm(e.calle.texto)) {
    r.add((esCalle: true, valor: calle));
  }
  if (e.numero.fuente == FuenteCampo.editado &&
      numero.isNotEmpty &&
      norm(numero) != norm(e.numero.texto)) {
    r.add((esCalle: false, valor: numero));
  }
  return r;
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.estado});

  final AltaUbicacionState estado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final punto = estado.punto;
    final precision = estado.precisionMetros;
    final Color colorPrecision;
    final String? textoPrecision;
    if (punto == null) {
      colorPrecision = ColoresAlta.gris;
      textoPrecision = null;
    } else if (precision == null) {
      colorPrecision = ColoresAlta.tinta;
      textoPrecision = TextosAlta.marcadoAMano;
    } else {
      colorPrecision = estado.esImpreciso ? ColoresAlta.ambar : ColoresAlta.verde;
      textoPrecision = '±${precision.round()} m';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text(
            TextosAlta.titulo,
            style: TextStyle(fontFamily: 'SourceSerif4', fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        if (punto != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  FormatoUbicaciones.coordenadas(punto),
                  style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
                ),
                const Text('·'),
                Text(
                  textoPrecision!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorPrecision,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SelectorTipo extends StatelessWidget {
  const _SelectorTipo({required this.tipo, required this.alElegir});

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

class _EtiquetaCampo extends StatelessWidget {
  const _EtiquetaCampo(this.texto, {this.insignia});

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

class _Insignia extends StatelessWidget {
  const _Insignia({
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              texto,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampoCiudad extends StatelessWidget {
  const _CampoCiudad({required this.estado, required this.alTocar});

  final AltaUbicacionState estado;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final ciudad = estado.ciudad;
    final String nombre;
    final String? origen;
    if (ciudad != null) {
      nombre = ciudad.nombre;
      origen = switch (estado.origenCiudad) {
        OrigenCiudad.detectada => 'detectada',
        OrigenCiudad.deZona => 'de tu zona',
        OrigenCiudad.deCampania => TextosAlta.deTuCampania,
        _ => null,
      };
    } else {
      nombre = estado.origenCiudad == OrigenCiudad.buscando
          ? TextosAlta.buscandoCiudad
          : 'Sin ciudad';
      origen = null;
    }
    // Sin ciudades en la campaña no hay nada que elegir: el campo no abre una lista vacía.
    final sinNadaQueElegir = ciudad == null && estado.origenCiudad == OrigenCiudad.sinCiudades;
    final enlace = sinNadaQueElegir
        ? null
        : (ciudad == null && estado.origenCiudad != OrigenCiudad.buscando
              ? 'Elegir'
              : TextosAlta.cambiar);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EtiquetaCampo(TextosAlta.ciudadObligatoria),
        const SizedBox(height: 6),
        Semantics(
          button: !sinNadaQueElegir,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
            ),
            child: InkWell(
              onTap: sinNadaQueElegir ? null : alTocar,
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
                        style: TextStyle(
                          fontSize: 15,
                          color: ciudad == null ? ColoresAlta.gris : null,
                        ),
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

/// El único aviso de ciudad que queda: la campaña no tiene ciudades cargadas, o no se pudieron leer.
/// Dice qué pasa y qué hacer, con «Reintentar» a mano.
class _AvisoCiudad extends StatelessWidget {
  const _AvisoCiudad({required this.sinCiudades, required this.alReintentar});

  final bool sinCiudades;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return AvisoAlta(
      color: ColoresAlta.ambarBorde,
      colorInsignia: ColoresAlta.ambar,
      glyph: '!',
      texto: sinCiudades ? TextosAlta.sinCiudades : TextosAlta.ciudadesNoLeidas,
      acciones: Align(
        alignment: Alignment.centerLeft,
        child: EnlaceAlta(texto: TextosAlta.reintentar, alPresionar: alReintentar),
      ),
    );
  }
}

class _CampoDireccion extends StatelessWidget {
  const _CampoDireccion({
    required this.etiqueta,
    required this.sugerencia,
    required this.campo,
    required this.controlador,
    required this.alCambiar,
    required this.limite,
    required this.accion,
  });

  final String etiqueta;
  final String sugerencia;
  final CampoDireccion campo;
  final TextEditingController controlador;
  final ValueChanged<String> alCambiar;
  final int limite;
  final TextInputAction accion;

  @override
  Widget build(BuildContext context) {
    final editado = campo.fuente == FuenteCampo.editado;
    final Widget? insignia = switch (campo.fuente) {
      FuenteCampo.delMapa => const _Insignia(
        icono: Icons.my_location,
        texto: TextosAlta.delMapa,
        fondo: ColoresAlta.verdeFondo,
        color: ColoresAlta.verde,
      ),
      FuenteCampo.editado => const _Insignia(
        icono: Icons.edit_outlined,
        texto: TextosAlta.editado,
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
        _EtiquetaCampo(etiqueta, insignia: insignia),
        const SizedBox(height: 6),
        TextField(
          controller: controlador,
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

/// «El punto está en Av. Italia 1250. Usar 1250»: lo que el mapa dice del punto cuando el colportor
/// escribió otra cosa, con el atajo para tomar el valor del mapa.
class _PuntoEstaEn extends StatelessWidget {
  const _PuntoEstaEn({required this.estado, required this.alUsarCalle, required this.alUsarNumero});

  final AltaUbicacionState estado;
  final VoidCallback alUsarCalle;
  final VoidCallback alUsarNumero;

  @override
  Widget build(BuildContext context) {
    final p = estado.propuesta!;
    final direccion = [
      for (final t in [p.calle, p.numero])
        if (t != null && t.trim().isNotEmpty) t.trim(),
    ].join(' ');
    return Semantics(
      liveRegion: true,
      container: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(
            'El punto está en $direccion.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
          ),
          for (final d in _diferencias(estado))
            EnlaceAlta(
              texto: TextosAlta.usar(d.valor),
              alPresionar: d.esCalle ? alUsarCalle : alUsarNumero,
            ),
        ],
      ),
    );
  }
}
