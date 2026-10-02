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
  static const seleccionarCiudad = 'Seleccionar ciudad manualmente';
  static const solicitarCiudad = 'Solicitar alta de ciudad al administrador';
  static const sinTiles = 'Sin tiles para esta zona. Descargá tu ciudad en Configuración.';

  // Provisorios: la HU y el canvas no los traen (se confirman con Cristian, ver el issue #193).
  static const elegiElTipo = 'Elegí el tipo de ubicación para registrar.';
  static const elegiLaCiudad = 'Elegí la ciudad para registrar.';
  static const elegiPrecision = 'Elegí «Ajustar manualmente» o «Continuar» para registrar.';
  static const buscandoGps = 'Buscando GPS…';
  static const buscandoCiudad = 'Buscando la ciudad…';
  static const ciudadAmbigua =
      'El punto está cerca del límite entre dos ciudades. Elegí cuál es la tuya.';
  static const solicitudEnviada =
      'Listo, le avisamos al administrador. Cuando dé de alta la ciudad vas a poder registrar '
      'esta ubicación.';

  static String gps(double metros) => 'GPS ±${metros.round()} m';

  static String usar(String valor) => 'Usar $valor';
}

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

  /// Abre la lista de ciudades («Cambiar», «Seleccionar ciudad manualmente»).
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
            (estado.origenCiudad == OrigenCiudad.noEncontrada ||
                estado.origenCiudad == OrigenCiudad.ambigua)) ...[
          const SizedBox(height: 10),
          _AvisoCiudad(
            estado: estado,
            alElegir: widget.alElegirCiudad,
            alSolicitar: _notificador.solicitarAltaCiudad,
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
          AvisoAlta(
            color: ColoresAlta.rojo,
            glyph: '!',
            texto: mensajePara(estado.falla!, accion: 'registrar la ubicación.'),
          ),
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
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
  );

  /// Por qué «Registrar» está deshabilitado, para que el colportor sepa qué falta.
  String? _porQueNo(AltaUbicacionState e) {
    if (e.guardando) return null;
    if (e.punto == null) return TextosAlta.marcaElPunto;
    if (e.necesitaDecisionPrecision) return TextosAlta.elegiPrecision;
    if (e.tipo == null) return TextosAlta.elegiElTipo;
    if (e.ciudad == null) return TextosAlta.elegiLaCiudad;
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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final t in TipoUbicacion.values) ...[
          if (t != TipoUbicacion.values.first) const SizedBox(width: 8),
          Expanded(
            child: _BotonTipo(
              etiqueta: FormatoUbicaciones.tipo(t),
              icono: _iconos[t]!,
              elegido: tipo == t,
              alTocar: () => alElegir(t),
            ),
          ),
        ],
      ],
    );
  }
}

class _BotonTipo extends StatelessWidget {
  const _BotonTipo({
    required this.etiqueta,
    required this.icono,
    required this.elegido,
    required this.alTocar,
  });

  final String etiqueta;
  final IconData icono;
  final bool elegido;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    final color = elegido ? Colors.white : ColoresAlta.tinta;
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
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
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
                      Flexible(
                        child: Text(
                          etiqueta,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: color,
                            fontWeight: elegido ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
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
        _ => null,
      };
    } else {
      nombre = estado.origenCiudad == OrigenCiudad.buscando
          ? TextosAlta.buscandoCiudad
          : 'Sin ciudad';
      origen = null;
    }
    final enlace = ciudad == null && estado.origenCiudad != OrigenCiudad.buscando
        ? 'Elegir'
        : TextosAlta.cambiar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EtiquetaCampo(TextosAlta.ciudadObligatoria),
        const SizedBox(height: 6),
        Semantics(
          button: true,
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
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          nombre,
                          style: TextStyle(
                            fontSize: 15,
                            color: ciudad == null ? ColoresAlta.gris : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (origen != null) TextSpan(text: '$origen · '),
                              TextSpan(
                                text: enlace,
                                style: const TextStyle(
                                  color: ColoresAlta.azul,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 12, color: ColoresAlta.tinta),
                        ),
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

/// «Ciudad no encontrada» (HU-UBI-001): «Seleccionar ciudad manualmente» o «Solicitar alta de
/// ciudad al administrador». Con el punto en el límite de dos ciudades, solo se pregunta.
class _AvisoCiudad extends StatelessWidget {
  const _AvisoCiudad({required this.estado, required this.alElegir, required this.alSolicitar});

  final AltaUbicacionState estado;
  final VoidCallback alElegir;
  final VoidCallback alSolicitar;

  @override
  Widget build(BuildContext context) {
    final ambigua = estado.origenCiudad == OrigenCiudad.ambigua;
    final solicitud = estado.solicitud;
    final texto = ambigua ? TextosAlta.ciudadAmbigua : const FailureCiudadRequerida().mensaje;
    final enviando = solicitud is SolicitudCiudadEnviando;
    final String? resultado = switch (solicitud) {
      SolicitudCiudadEnviada() => TextosAlta.solicitudEnviada,
      SolicitudCiudadFallida(:final falla) => mensajePara(
        falla,
        accion: 'pedir el alta de la ciudad.',
      ),
      _ => null,
    };
    return AvisoAlta(
      color: ColoresAlta.ambarBorde,
      colorInsignia: ColoresAlta.ambar,
      glyph: '!',
      texto: texto,
      acciones: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (resultado != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                resultado,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: EnlaceAlta(texto: TextosAlta.seleccionarCiudad, alPresionar: alElegir),
          ),
          if (!ambigua && solicitud is! SolicitudCiudadEnviada)
            Align(
              alignment: Alignment.centerLeft,
              child: EnlaceAlta(
                texto: TextosAlta.solicitarCiudad,
                alPresionar: enviando ? null : alSolicitar,
              ),
            ),
        ],
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
          inputFormatters: [LengthLimitingTextInputFormatter(limite)],
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
