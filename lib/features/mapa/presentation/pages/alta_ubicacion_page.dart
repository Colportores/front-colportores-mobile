import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../providers/alta_ubicacion_notifier.dart';
import '../providers/alta_ubicacion_providers.dart';
import '../widgets/aviso_mapa.dart';
import '../widgets/hoja_alta.dart';
import '../widgets/hoja_ciudad.dart';
import '../widgets/hoja_duplicado_alta.dart';
import '../widgets/mapa_alta.dart';
import '../widgets/medida_hoja.dart';
import '../widgets/piezas_alta.dart';

/// Cómo se cerró el alta de ubicación.
sealed class SalidaAltaUbicacion {
  const SalidaAltaUbicacion();
}

/// La ubicación quedó registrada: el mapa vuelve con ella seleccionada.
final class UbicacionCreada extends SalidaAltaUbicacion {
  const UbicacionCreada(this.ubicacion);

  final Ubicacion ubicacion;
}

/// El colportor eligió «Reutilizar esta» (o «Abrir la existente») en el aviso de duplicado: el mapa
/// abre esa ubicación con la vista previa, sin modificar sus datos.
final class UbicacionReutilizada extends SalidaAltaUbicacion {
  const UbicacionReutilizada(this.ubicacionId);

  final String ubicacionId;
}

/// Vista 03 (HU-UBI-001, #193): alta de ubicación sobre el mapa, con captura GPS.
///
/// Pantalla completa, sin barra inferior: el mapa con el pin fijo en el centro arriba y, abajo, la
/// hoja con tipo, ciudad y dirección. Al tocar «Registrar» se valida contra las ubicaciones
/// cercanas antes de crear (vista 04). Sale con un [SalidaAltaUbicacion], o con `null` si el
/// colportor cierra sin registrar.
class AltaUbicacionPage extends ConsumerStatefulWidget {
  const AltaUbicacionPage({super.key, required this.parametros});

  final ParametrosAlta parametros;

  static var _aperturas = 0;

  /// Abre el alta encima de la pantalla actual. [puntoInicial] es el tap largo del mapa.
  static Future<SalidaAltaUbicacion?> abrir(
    BuildContext context, {
    required String colportorId,
    Coordenadas? puntoInicial,
  }) => Navigator.of(context).push<SalidaAltaUbicacion>(
    MaterialPageRoute(
      builder: (_) => AltaUbicacionPage(
        parametros: ParametrosAlta(
          colportorId: colportorId,
          puntoInicial: puntoInicial,
          apertura: ++_aperturas,
        ),
      ),
    ),
  );

  @override
  ConsumerState<AltaUbicacionPage> createState() => _AltaUbicacionPageState();
}

class _AltaUbicacionPageState extends ConsumerState<AltaUbicacionPage> with WidgetsBindingObserver {
  /// Un solo aviso de duplicado a la vez (un segundo toque no abre otra hoja encima).
  var _mostrandoDuplicados = false;
  var _eligiendoCiudad = false;

  AltaUbicacionNotifier get _notificador =>
      ref.read(altaUbicacionProvider(widget.parametros).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Volvió de los ajustes del sistema: si estaba sin GPS, se vuelve a intentar.
    if (estado == AppLifecycleState.resumed) unawaited(_notificador.reintentarGpsSiHaceFalta());
  }

  Future<void> _registrar() async {
    final resultado = await _notificador.registrar();
    if (!mounted) return;
    switch (resultado) {
      case AltaCreada(:final ubicacion):
        Navigator.of(context).pop(UbicacionCreada(ubicacion));
      case AltaConCandidatas(:final candidatas):
        await _mostrarDuplicados(candidatas);
      case AltaFallida() || AltaIgnorada():
        break;
    }
  }

  Future<Map<String, String>> _nombresCiudad() async {
    try {
      final r = await ref
          .read(ciudadesParaAltaProvider)
          .deMiCampania(widget.parametros.colportorId);
      return r.fold<Map<String, String>>(
        (_) => const {},
        (ciudades) => {for (final c in ciudades) c.id: c.nombre},
      );
    } on Object {
      return const {};
    }
  }

  Future<void> _mostrarDuplicados(List<CandidataDuplicado> candidatas) async {
    if (_mostrandoDuplicados) return;
    final punto = ref.read(altaUbicacionProvider(widget.parametros)).punto;
    if (punto == null) return;
    _mostrandoDuplicados = true;
    try {
      final nombres = await _nombresCiudad();
      if (!mounted) return;
      final decision = await mostrarHojaDuplicado(
        context,
        candidatas: candidatas,
        puntoNuevo: punto,
        nombresCiudad: nombres,
        ambito: ref.read(altaUbicacionProvider(widget.parametros)).ambitoMapa,
        crearIgual: (justificacion) => _notificador.registrar(justificacion: justificacion),
        ahora: ref.read(relojAltaUbicacionProvider),
      );
      if (!mounted) return;
      switch (decision) {
        case DecisionReutilizar(:final ubicacionId):
          Navigator.of(context).pop(UbicacionReutilizada(ubicacionId));
        case DecisionCreada(:final ubicacion):
          Navigator.of(context).pop(UbicacionCreada(ubicacion));
        case null:
          break;
      }
    } finally {
      _mostrandoDuplicados = false;
    }
  }

  Future<void> _elegirCiudad() async {
    if (_eligiendoCiudad) return;
    _eligiendoCiudad = true;
    try {
      await mostrarHojaCiudad(
        context,
        colportorId: widget.parametros.colportorId,
        elegidaId: ref.read(altaUbicacionProvider(widget.parametros)).ciudad?.id,
        alElegir: _notificador.elegirCiudad,
      );
    } finally {
      _eligiendoCiudad = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final proveedor = altaUbicacionProvider(widget.parametros);
    final estado = ref.watch(proveedor);
    final sinGps = estado.gps == EstadoGps.sinGps;
    final cierre = Navigator.of(context);
    // Se lee acá y no dentro del `Scaffold`: este le quita el inset del teclado al `MediaQuery` de su
    // cuerpo (se achica él), y ahí `viewInsets.bottom` siempre da 0.
    final tecladoAbierto = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      // Mientras se guarda no se puede salir: el resultado se perdería.
      canPop: !estado.guardando,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, caja) {
            return Column(
              children: [
                Expanded(
                  child: _ZonaMapa(
                    parametros: widget.parametros,
                    estado: estado,
                    tecladoAbierto: tecladoAbierto,
                    alCerrar: cierre.maybePop,
                    alMover: _notificador.moverPunto,
                    alTocar: _notificador.marcarPunto,
                    alVolverAMiUbicacion: _notificador.volverAMiUbicacion,
                  ),
                ),
                // Los avisos y los campos se desplazan; «Registrar» queda fijo al pie (#305). La hoja ocupa
                // el 62 % del cuerpo y, con el teclado abierto, crece hasta lo que pida el campo (#324).
                HojaInferior(
                  cuerpo: caja.maxHeight,
                  tecladoAbierto: tecladoAbierto,
                  hijo: HojaAlta(
                    parametros: widget.parametros,
                    alRegistrar: _registrar,
                    alElegirCiudad: _elegirCiudad,
                    avisos: [
                      if (sinGps) _AvisoSinGps(alActivarGps: _notificador.activarGps),
                      AvisoMapaConectado(ambito: estado.ambitoMapa),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// La parte de arriba: el mapa con el pin fijo y todo lo que flota encima (cerrar, chip del GPS,
/// pista, «Volver a mi ubicación»). Los avisos largos no flotan acá: van arriba de la hoja de abajo
/// ([_AvisoSinGps], `AvisoMapaConectado`), que se desplaza y no pisa el pin.
class _ZonaMapa extends StatefulWidget {
  const _ZonaMapa({
    required this.parametros,
    required this.estado,
    required this.tecladoAbierto,
    required this.alCerrar,
    required this.alMover,
    required this.alTocar,
    required this.alVolverAMiUbicacion,
  });

  final ParametrosAlta parametros;
  final AltaUbicacionState estado;

  /// Con el teclado abierto el mapa queda de ~129 dp a 360×640 y la pista (dos renglones con la letra
  /// grande) taparía la atribución o se cortaría; el chip del GPS, con la barra de estado, caería sobre
  /// la punta del pin: el colportor está escribiendo, no moviendo el mapa. Los dos se ocultan mientras
  /// dura y vuelven al cerrarlo; el pin, «Cerrar», «Volver a mi ubicación» y el resto siguen.
  final bool tecladoAbierto;
  final VoidCallback alCerrar;
  final ValueChanged<Coordenadas> alMover;
  final ValueChanged<Coordenadas> alTocar;
  final VoidCallback alVolverAMiUbicacion;

  @override
  State<_ZonaMapa> createState() => _ZonaMapaState();
}

class _ZonaMapaState extends State<_ZonaMapa> {
  /// «Calle actualizada» se muestra un rato cada vez que la calle se actualiza sola.
  var _mostrandoAvisoCalle = false;
  var _avisosVistos = 0;
  static const _duracionAviso = Duration(seconds: 2);

  @override
  void didUpdateWidget(_ZonaMapa anterior) {
    super.didUpdateWidget(anterior);
    if (widget.estado.avisosCalle != _avisosVistos) {
      _avisosVistos = widget.estado.avisosCalle;
      final actual = _avisosVistos;
      _mostrandoAvisoCalle = true;
      Future<void>.delayed(_duracionAviso, () {
        if (mounted && _avisosVistos == actual) setState(() => _mostrandoAvisoCalle = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    final arriba = MediaQuery.paddingOf(context).top;
    final String pista = _mostrandoAvisoCalle
        ? TextosAlta.calleActualizada
        : (estado.punto == null ? TextosAlta.tocar : TextosAlta.mover);

    return Stack(
      fit: StackFit.expand,
      children: [
        // El fondo del mapa: si el mapa baja para no quedar bajo el chip, arriba queda esto.
        const ColoredBox(color: ColoresAlta.fondoMapa),
        CustomMultiChildLayout(
          delegate: _DisposicionZona(),
          children: [
            // El mapa y lo que va anclado a él (pin, pista, «Volver a mi ubicación») bajan juntos: el
            // pin sigue en el centro del mapa, que es el punto que se registra.
            LayoutId(
              id: _Parte.mapa,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Mientras se guarda el punto no se toca (el notifier ya ignora el movimiento): sin
                  // esto el mapa se podría arrastrar y, si el alta falla o devuelve candidatas, el pin
                  // quedaría lejos del punto que se registra.
                  IgnorePointer(
                    ignoring: estado.guardando,
                    child: MapaAlta(
                      parametros: widget.parametros,
                      estado: estado,
                      alMoverCentro: widget.alMover,
                      alTocar: widget.alTocar,
                    ),
                  ),
                  // El pin fijo en el centro: la punta queda justo en el centro del mapa.
                  IgnorePointer(
                    child: Center(
                      child: Transform.translate(
                        offset: const Offset(0, -22),
                        child: PinAlta(colocado: estado.punto != null),
                      ),
                    ),
                  ),
                  if (!widget.tecladoAbierto)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomSingleChildLayout(
                          delegate: _PosicionPista(conBotonVolver: estado.lectura != null),
                          child: Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xD10E1A2B),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                pista,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (estado.lectura != null)
                    Positioned(
                      right: _derechaBotonVolver,
                      bottom: 36,
                      child: BotonRedondoMapa(
                        tamano: _ladoBotonVolver,
                        icono: Icons.my_location,
                        etiqueta: TextosAlta.volverAMiUbicacion,
                        alPresionar: widget.alVolverAMiUbicacion,
                      ),
                    ),
                ],
              ),
            ),
            LayoutId(
              id: _Parte.rotulos,
              child: widget.tecladoAbierto
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: EdgeInsets.fromLTRB(72, arriba + 14, 14, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        heightFactor: 1,
                        child: _ChipGps(estado: estado),
                      ),
                    ),
            ),
          ],
        ),
        Positioned(
          left: 14,
          top: arriba + 8,
          child: BotonRedondoMapa(
            tamano: 48,
            icono: Icons.close,
            etiqueta: TextosAlta.cerrar,
            alPresionar: estado.guardando ? null : widget.alCerrar,
          ),
        ),
      ],
    );
  }
}

enum _Parte { mapa, rotulos }

/// La disposición de la zona del mapa (la misma regla que en la vista 07): el chip del GPS arriba y el
/// mapa debajo, que llega hasta arriba salvo que el chip llegue al pin.
///
/// El pin está fijo en el centro del mapa (su punta marca el punto) y mide 44 dp de alto. Si con el
/// texto grande, o con una barra de estado alta, el chip baja hasta el pin, el mapa entero baja lo
/// justo para que el pin quede debajo del chip: el punto que se registra sigue siendo el centro del
/// mapa, el que el pin marca.
class _DisposicionZona extends MultiChildLayoutDelegate {
  _DisposicionZona();

  static const _altoPin = 44.0;
  static const _holgura = 8.0;

  /// Lo mínimo que queda de mapa, por grande que sea el chip.
  static const _mapaMinimo = 96.0;

  @override
  void performLayout(Size size) {
    final rotulos = layoutChild(_Parte.rotulos, BoxConstraints.loose(size));
    positionChild(_Parte.rotulos, Offset.zero);
    // Sin chip (teclado abierto) no hay nada que esquivar.
    final hacerBajar = rotulos.height == 0
        ? 0.0
        : 2 * (rotulos.height + _holgura + _altoPin) - size.height;
    final baja = hacerBajar.clamp(0.0, math.max(0.0, size.height - _mapaMinimo)).toDouble();
    layoutChild(_Parte.mapa, BoxConstraints.tight(Size(size.width, size.height - baja)));
    positionChild(_Parte.mapa, Offset(0, baja));
  }

  @override
  bool shouldRelayout(_DisposicionZona anterior) => false;
}

/// «Volver a mi ubicación» flota abajo a la derecha del mapa: a [_derechaBotonVolver] del borde y de
/// [_ladoBotonVolver] de lado. La pista del pin le deja ese lugar.
const _derechaBotonVolver = 14.0;
const _ladoBotonVolver = 52.0;

/// Dónde va la pista «Mové el mapa para ajustar el punto»: centrada debajo de la punta del pin (que
/// está en el centro del mapa), con [margen] a los bordes y sin pasar por «Volver a mi ubicación».
/// Con el texto grande la pista baja a dos renglones o más; no ocupa todo el ancho ni sube a taparle
/// la punta al pin.
class _PosicionPista extends SingleChildLayoutDelegate {
  const _PosicionPista({required this.conBotonVolver});

  final bool conBotonVolver;

  static const margen = 16.0;

  /// Lo que la pista deja libre al lado del botón y, más chico, debajo de la punta del pin: en el
  /// mapa chico con el texto grande abajo todavía entra la atribución de OpenStreetMap.
  static const separacion = 8.0;
  static const separacionDelPin = 4.0;

  /// El borde derecho de donde cabe la pista.
  double _limiteDerecho(double ancho) => conBotonVolver
      ? ancho - (_derechaBotonVolver + _ladoBotonVolver + separacion)
      : ancho - margen;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    maxWidth: math.max(0, _limiteDerecho(constraints.maxWidth) - margen),
    maxHeight: constraints.maxHeight,
  );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Centrada bajo el pin y, si así tocaría el botón, corrida a la izquierda.
    final centrada = (size.width - childSize.width) / 2;
    final x = math.max(margen, math.min(centrada, _limiteDerecho(size.width) - childSize.width));
    // Donde estaba (alineada en (0, .3)), pero nunca más arriba que la punta del pin.
    final habitual = (size.height - childSize.height) * 0.65;
    final y = math.max(habitual, size.height / 2 + separacionDelPin);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PosicionPista anterior) => anterior.conBotonVolver != conBotonVolver;
}

/// «No tenemos tu ubicación. Tocá el mapa donde está el lugar o activá el GPS.» con «Activar GPS»
/// (artboard 03A · 02). El canvas lo dibuja flotando sobre el mapa, pero el mapa de un teléfono es
/// más chico que el del canvas (la hoja ocupa hasta el 62 % del alto, 80 % con el teclado): ahí el recuadro tapaba el pin
/// y la pista, y a 360×640 con el texto al 200 % (más alto que el mapa entero) la hoja dejaba
/// «Activar GPS» inalcanzable. Arriba de la hoja, que se desplaza, el recuadro conserva su forma y su
/// texto, el botón queda siempre a la vista y el pin y la pista quedan libres.
class _AvisoSinGps extends StatelessWidget {
  const _AvisoSinGps({required this.alActivarGps});

  final VoidCallback alActivarGps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AvisoAlta(
        color: ColoresAlta.gris,
        glyph: '!',
        texto: TextosAlta.sinGpsAviso,
        acciones: Align(
          alignment: Alignment.centerRight,
          child: EnlaceAlta(texto: TextosAlta.activarGps, alPresionar: alActivarGps),
        ),
      ),
    );
  }
}

/// El chip de arriba: «GPS ±6 m», «GPS ±85 m», «Sin GPS» o «Buscando GPS…».
class _ChipGps extends StatelessWidget {
  const _ChipGps({required this.estado});

  final AltaUbicacionState estado;

  @override
  Widget build(BuildContext context) {
    final Widget insignia;
    final String texto;
    switch (estado.gps) {
      case EstadoGps.buscando:
        insignia = const SizedBox(
          width: 20,
          height: 20,
          child: Padding(
            padding: EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
        texto = TextosAlta.buscandoGps;
      case EstadoGps.sinGps:
        insignia = const InsigniaCirculo(color: ColoresAlta.gris, glyph: '✕', tamano: 20);
        texto = 'Sin GPS';
      case EstadoGps.conLectura:
        final precision = estado.lectura!.precisionMetros;
        final impreciso = !(precision >= 0 && precision <= 50);
        insignia = InsigniaCirculo(
          color: impreciso ? ColoresAlta.ambar : ColoresAlta.verde,
          glyph: impreciso ? '!' : '✓',
          tamano: 20,
        );
        texto = precision.isFinite ? TextosAlta.gps(precision) : 'GPS';
    }
    return Semantics(
      liveRegion: true,
      container: true,
      label: texto,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        elevation: 2,
        shape: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 14, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                insignia,
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    texto,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
