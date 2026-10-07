import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../domain/entities/resultado_alta_ubicacion.dart';
import '../formato_ubicaciones.dart';
import '../providers/alta_ubicacion_notifier.dart';
import 'campos_ubicacion.dart';
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
  static const ciudadObligatoria = TextosCampos.ciudadObligatoria;
  static const calle = TextosCampos.calle;
  static const numero = TextosCampos.numero;
  static const delMapa = TextosCampos.delMapa;
  static const editado = TextosCampos.editado;
  static const cambiar = TextosCampos.cambiar;

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
/// - «Registrar» queda fijo al pie de la hoja y se desplaza todo lo de arriba (#305, como la 07): con
///   un teléfono chico, el texto grande o el teclado abierto la acción principal se ve siempre. El
///   aviso de falla queda en la parte que se desplaza, justo arriba del botón, y cuando aparece se
///   lleva a la vista. Con el teclado abierto no se dibuja el motivo de abajo (se está escribiendo):
///   a 200 % no entraría junto al botón; vuelve al cerrarlo.
class HojaAlta extends ConsumerStatefulWidget {
  const HojaAlta({
    super.key,
    required this.parametros,
    required this.alRegistrar,
    required this.alElegirCiudad,
    this.avisos = const [],
    this.tecladoAbierto = false,
  });

  final ParametrosAlta parametros;
  final VoidCallback alRegistrar;

  /// Abre la lista de ciudades de la campaña («Cambiar»).
  final VoidCallback alElegirCiudad;

  /// Los avisos de arriba de la hoja (sin GPS, mapa sin conexión): se desplazan con el resto.
  final List<Widget> avisos;

  /// Si el teclado está abierto. Lo informa quien está arriba del `Scaffold`: dentro del cuerpo el
  /// `Scaffold` ya descontó el teclado y `viewInsets.bottom` siempre da 0.
  final bool tecladoAbierto;

  @override
  ConsumerState<HojaAlta> createState() => _HojaAltaState();
}

class _HojaAltaState extends ConsumerState<HojaAlta> {
  final _calle = TextEditingController();
  final _numero = TextEditingController();

  /// El aviso de falla: cuando aparece se lleva a la vista, arriba del botón fijo.
  final _claveFalla = GlobalKey();

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
    ref.listen(proveedor.select((s) => s.falla), (anterior, nueva) {
      if (nueva == null || nueva == anterior) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final contexto = _claveFalla.currentContext;
        if (mounted && contexto != null) {
          unawaited(Scrollable.ensureVisible(contexto, duration: Duration.zero));
        }
      });
    });
    final theme = Theme.of(context);
    final motivo = widget.tecladoAbierto ? null : _porQueNo(estado);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...widget.avisos,
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
                            child: const Text(
                              TextosAlta.ajustarManualmente,
                              textAlign: TextAlign.center,
                            ),
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
                SelectorTipoUbicacion(tipo: estado.tipo, alElegir: _notificador.elegirTipo),
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
                      child: CampoDireccionUbicacion(
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
                      child: CampoDireccionUbicacion(
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
                    key: _claveFalla,
                    color: ColoresAlta.rojo,
                    glyph: '!',
                    texto: mensajeFallaAlta(estado.falla!),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: estado.puedeRegistrar ? widget.alRegistrar : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            disabledBackgroundColor: ColoresAlta.grisFondo,
            disabledForegroundColor: ColoresAlta.gris,
            minimumSize: const Size.fromHeight(52),
          ),
          child: Text(
            estado.guardando ? TextosAlta.registrando : TextosAlta.registrar,
            textAlign: TextAlign.center,
          ),
        ),
        if (motivo != null) ...[
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
              ? TextosCampos.elegir
              : TextosCampos.cambiar);
    return CampoCiudadUbicacion(
      nombre: nombre,
      sinValor: ciudad == null,
      origen: origen,
      enlace: enlace,
      alTocar: sinNadaQueElegir ? null : alTocar,
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
