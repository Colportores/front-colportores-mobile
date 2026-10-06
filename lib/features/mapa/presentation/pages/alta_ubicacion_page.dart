import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/services/resolutores_mapa.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../providers/alta_ubicacion_notifier.dart';
import '../providers/alta_ubicacion_providers.dart';
import '../widgets/hoja_alta.dart';
import '../widgets/hoja_ciudad.dart';
import '../widgets/hoja_duplicado_alta.dart';
import '../widgets/mapa_alta.dart';
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
      await mostrarHojaCiudad(context, parametros: widget.parametros);
    } finally {
      _eligiendoCiudad = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final proveedor = altaUbicacionProvider(widget.parametros);
    final estado = ref.watch(proveedor);
    final sinTiles = ref.watch(fuenteTilesAltaProvider) == FuenteTiles.sinTiles;
    final sinGps = estado.gps == EstadoGps.sinGps;
    final cierre = Navigator.of(context);

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
                    alCerrar: cierre.maybePop,
                    alMover: _notificador.moverPunto,
                    alTocar: _notificador.marcarPunto,
                    alVolverAMiUbicacion: _notificador.volverAMiUbicacion,
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: caja.maxHeight * .62),
                  child: Material(
                    color: Colors.white,
                    elevation: 8,
                    shadowColor: const Color(0x1F0E1A2B),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: ColoresAlta.grisBorde,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            if (sinGps) _AvisoSinGps(alActivarGps: _notificador.activarGps),
                            if (sinTiles) const _AvisoSinTiles(),
                            HojaAlta(
                              parametros: widget.parametros,
                              alRegistrar: _registrar,
                              alElegirCiudad: _elegirCiudad,
                            ),
                          ],
                        ),
                      ),
                    ),
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
/// ([_AvisoSinGps], [_AvisoSinTiles]), que se desplaza y no pisa el pin.
class _ZonaMapa extends StatefulWidget {
  const _ZonaMapa({
    required this.parametros,
    required this.estado,
    required this.alCerrar,
    required this.alMover,
    required this.alTocar,
    required this.alVolverAMiUbicacion,
  });

  final ParametrosAlta parametros;
  final AltaUbicacionState estado;
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
        // Mientras se guarda el punto no se toca (el notifier ya ignora el movimiento): sin esto el
        // mapa se podría arrastrar y, si el alta falla o devuelve candidatas, el pin quedaría lejos del
        // punto que se registra.
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
        Positioned(
          left: 14,
          top: arriba + 8,
          child: _BotonRedondo(
            tamano: 48,
            icono: Icons.close,
            etiqueta: TextosAlta.cerrar,
            alPresionar: estado.guardando ? null : widget.alCerrar,
          ),
        ),
        Positioned(
          left: 72,
          right: 14,
          top: arriba + 14,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _ChipGps(estado: estado),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: const Alignment(0, .3),
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xD10E1A2B),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(pista, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                ),
              ),
            ),
          ),
        ),
        if (estado.lectura != null)
          Positioned(
            right: 14,
            bottom: 36,
            child: _BotonRedondo(
              tamano: 52,
              icono: Icons.my_location,
              etiqueta: TextosAlta.volverAMiUbicacion,
              alPresionar: widget.alVolverAMiUbicacion,
            ),
          ),
      ],
    );
  }
}

/// «No tenemos tu ubicación. Tocá el mapa donde está el lugar o activá el GPS.» con «Activar GPS»
/// (artboard 03A · 02). El canvas lo dibuja flotando sobre el mapa, pero el mapa de un teléfono es
/// más chico que el del canvas (la hoja ocupa hasta el 62 % del alto): ahí el recuadro tapaba el pin
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

/// «Sin tiles para esta zona. Descargá tu ciudad en Configuración.» (HU-UBI-003). Va en la hoja de
/// abajo y no flotando sobre el mapa: en el mapa chico (360×640, o con el texto al 200 %) el recuadro
/// tapaba «Activar GPS», la pista del pin, el pin y «Volver a mi ubicación».
class _AvisoSinTiles extends StatelessWidget {
  const _AvisoSinTiles();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ColoresAlta.grisBorde),
      ),
      child: const Text(
        TextosAlta.sinTiles,
        style: TextStyle(fontSize: 12, color: ColoresAlta.tinta),
      ),
    );
  }
}

class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({
    required this.tamano,
    required this.icono,
    required this.etiqueta,
    required this.alPresionar,
  });

  final double tamano;
  final IconData icono;
  final String etiqueta;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: etiqueta,
        onPressed: alPresionar,
        icon: Icon(icono, color: Theme.of(context).colorScheme.primary),
        constraints: BoxConstraints.tightFor(width: tamano, height: tamano),
        padding: EdgeInsets.zero,
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
