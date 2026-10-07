import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../tiles/domain/entities/paquete_tiles.dart' show AmbitoTrabajo;
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/services/proyeccion_mercator.dart';
import '../../domain/value_objects/camara_mapa.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../formato_mapa_ubicaciones.dart';
import '../mapa_base/mapa_base.dart';
import '../mapa_base/modelo_mapa_base.dart';
import '../providers/lista_ubicaciones_providers.dart';
import '../providers/mapa_base_providers.dart';
import '../providers/mapa_ubicaciones_notifier.dart';
import '../providers/mapa_ubicaciones_providers.dart';
import '../providers/situacion_mapa_providers.dart';
import '../widgets/aviso_mapa.dart';
import '../widgets/hoja_mapa_ubicaciones.dart';
import '../widgets/mapa_alta.dart';
import '../widgets/piezas_mapa_ubicaciones.dart';
import 'alta_ubicacion_page.dart';

/// La pestaña «Mapa» (vista 06, HU-UBI-003): las ubicaciones del colportor sobre el mapa, su GPS y,
/// abajo, la hoja «Cercanía» con la lista de la más cercana a la más lejana o la vista previa de la
/// ubicación que se tocó.
///
/// Vive dentro de la pantalla principal (`IndexedStack`, que arma todas las pestañas al arrancar):
/// [activa] dice si la pestaña está a la vista. Hasta que se abre por primera vez no arma el mapa ni
/// lee la base: el mapa nativo cuesta memoria y datos. El GPS se pide esa primera vez, no al
/// arrancar la app, y se refresca cada vez que se vuelve a ella.
///
/// Qué queda para otras HU (decisión de Cristian en el #199): «Agendados» y la vista previa con
/// «Registrar visita» y «Agendar» (HU-VIS-001 y HU-VIS-002), los colores por estado (HU-VIS-005) y
/// «Cobranza» (HU-COB-005).
class MapaUbicacionesPage extends ConsumerStatefulWidget {
  const MapaUbicacionesPage({
    super.key,
    required this.colportorId,
    this.activa = true,
    this.alAbrirAlta,
  });

  /// UUID del colportor con la sesión iniciada: el mapa es «las que registré».
  final String colportorId;

  /// La pestaña está a la vista.
  final bool activa;

  /// Cómo se abre el alta («Nueva», mantener el dedo en el mapa y «Registrar tu primera
  /// ubicación»), con el punto donde se mantuvo el dedo si lo hay. Por defecto abre
  /// `AltaUbicacionPage`; un test lo reemplaza.
  final Future<SalidaAltaUbicacion?> Function(Coordenadas? puntoInicial)? alAbrirAlta;

  @override
  ConsumerState<MapaUbicacionesPage> createState() => _MapaUbicacionesPageState();
}

/// Hasta dónde se encuadró el mapa solo, sin que el colportor lo moviera.
enum _Encuadre { ninguno, todas, gps }

class _MapaUbicacionesPageState extends ConsumerState<MapaUbicacionesPage>
    with WidgetsBindingObserver {
  ControladorMapaBase? _mapa;
  Size _tamano = Size.zero;
  var _altura = AlturaHoja.minimizada;
  var _encuadre = _Encuadre.ninguno;

  /// Cuántos gestos del colportor movieron el mapa: sirve para no tirarle la cámara de las manos.
  var _gestos = 0;

  /// Un solo alta y una sola leyenda a la vez: un segundo toque no abre otra encima.
  var _abriendoAlta = false;
  var _abriendoReferencias = false;

  /// La pestaña se abrió alguna vez: desde ahí el mapa queda armado aunque se cambie de pestaña (la
  /// cámara y lo que se eligió no se pierden).
  late var _abierta = widget.activa;

  NotifierProvider<MapaUbicacionesNotifier, MapaUbicacionesState> get _proveedor =>
      mapaUbicacionesProvider(widget.colportorId);

  MapaUbicacionesNotifier get _notificador => ref.read(_proveedor.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.activa) WidgetsBinding.instance.addPostFrameCallback((_) => _alAbrirPestana());
  }

  @override
  void didUpdateWidget(MapaUbicacionesPage anterior) {
    super.didUpdateWidget(anterior);
    // Cambiar un provider durante la construcción no se permite: se pide el GPS al terminar el
    // cuadro.
    if (widget.activa && !anterior.activa) {
      _abierta = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _alAbrirPestana());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _alAbrirPestana() {
    if (!mounted) return;
    unawaited(_notificador.alAbrirPestana());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Volvió de los ajustes del sistema: si estaba sin GPS, se vuelve a intentar.
    if (estado == AppLifecycleState.resumed && widget.activa) {
      unawaited(_notificador.reintentarGpsSiHaceFalta());
    }
  }

  // ---------------------------------------------------------------- cámara

  void _alCrearseElMapa(ControladorMapaBase mapa) {
    _mapa = mapa;
    _encuadrarSiHaceFalta(ref.read(_proveedor));
  }

  /// Al abrir el mapa, una sola vez y mientras el colportor no lo haya movido: sobre su GPS, y si
  /// no hay, con todas sus ubicaciones a la vista. (La ciudad del colportor, que la HU pone primero,
  /// todavía no se conoce: #274.)
  void _encuadrarSiHaceFalta(MapaUbicacionesState estado) {
    final mapa = _mapa;
    if (mapa == null || _gestos > 0 || _tamano.isEmpty) return;
    final lectura = estado.lectura;
    if (lectura != null) {
      if (_encuadre == _Encuadre.gps) return;
      _encuadre = _Encuadre.gps;
      // El punto azul queda en la parte que la hoja deja libre, no detrás de ella.
      _centrarEn(lectura.coordenadas, _altura, zoomMinimo: MapaAlta.zoomCalle);
      return;
    }
    final lista = estado.lista;
    // Mientras el GPS busca, se espera: encuadrar todo y después saltar al GPS son dos movimientos.
    if (_encuadre != _Encuadre.ninguno ||
        lista == null ||
        lista.sinUbicaciones ||
        estado.gps == EstadoGpsLista.buscando) {
      return;
    }
    _encuadre = _Encuadre.todas;
    final camara = ProyeccionMercator.camaraQueAjusta(
      [for (final item in lista.items) item.ubicacion.coordenadas],
      ancho: _tamano.width,
      alto: _tamano.height,
      margen: 56,
      zoomMaximo: MapaAlta.zoomCalle,
    );
    unawaited(mapa.moverCamara(camara));
  }

  /// Lo que ocupan los botones flotantes («Mi ubicación» y «Nueva», con 10 entre ellos y 14 de
  /// margen abajo) sobre la hoja.
  double _altoBotones() =>
      52 + 10 + math.max(52.0, MediaQuery.textScalerOf(context).scale(22)) + 14;

  /// Lo que tiene que quedar libre sobre la hoja: los botones, y arriba el chip «Referencias» (48 dp
  /// de alto con 8 de margen arriba y 8 de aire hasta los botones). En un teléfono chico la hoja a 1/2
  /// se achica antes de pisarlos.
  double _reservaSobreLaHoja() => _altoBotones() + 8 + 48 + 8;

  double _altoHoja(AlturaHoja altura) => altura.alto(
    pantalla: MediaQuery.sizeOf(context).height,
    disponible: _tamano.height,
    escala: MediaQuery.textScalerOf(context),
    reserva: _reservaSobreLaHoja(),
  );

  /// Centra el mapa en [punto] de modo que quede en la parte que la hoja de [altura] deja libre.
  void _centrarEn(Coordenadas punto, AlturaHoja altura, {double zoomMinimo = 0}) {
    final mapa = _mapa;
    if (mapa == null || _tamano.isEmpty) return;
    final zoom = math.max(mapa.camara.zoom, zoomMinimo);
    final pixeles = ProyeccionMercator.aPixeles(punto, zoom);
    // El centro de la vista queda medio alto de hoja más abajo que el punto.
    final centro = ProyeccionMercator.aCoordenadas(
      pixeles.x,
      pixeles.y + _altoHoja(altura) / 2,
      zoom,
    );
    unawaited(mapa.moverCamara(CamaraMapa(centro: centro, zoom: zoom)));
  }

  // ---------------------------------------------------------------- acciones

  /// Un marcador o una fila de la lista: se abre su vista previa y el mapa se centra en ella.
  void _elegir(String ubicacionId, {double zoomMinimo = 0}) {
    final lista = ref.read(_proveedor).lista;
    ItemListaUbicacion? item;
    for (final candidato in lista?.items ?? const <ItemListaUbicacion>[]) {
      if (candidato.ubicacion.id == ubicacionId) item = candidato;
    }
    _notificador.seleccionar(ubicacionId);
    final nueva = _altura == AlturaHoja.minimizada ? AlturaHoja.tercio : _altura;
    if (nueva != _altura) setState(() => _altura = nueva);
    if (item != null) _centrarEn(item.ubicacion.coordenadas, nueva, zoomMinimo: zoomMinimo);
  }

  void _alTocarPunto(String id) {
    // El punto azul es «Tu ubicación»: no tiene vista previa.
    if (id == 'gps') return;
    _elegir(id);
  }

  /// «Mi ubicación»: el mapa vuelve al GPS; se pide una lectura nueva y, si el colportor no tocó el
  /// mapa mientras tanto y la posición cambió, se vuelve a centrar.
  Future<void> _irAMiUbicacion() async {
    final mapa = _mapa;
    final lectura = ref.read(_proveedor).lectura;
    if (mapa == null || lectura == null) return;
    final gestos = _gestos;
    // Con el punto en la parte que la hoja deja libre.
    void centrar(Coordenadas punto) => _centrarEn(punto, _altura, zoomMinimo: MapaAlta.zoomCalle);
    centrar(lectura.coordenadas);
    await _notificador.refrescarGps();
    if (!mounted || gestos != _gestos) return;
    final nueva = ref.read(_proveedor).lectura;
    if (nueva != null && nueva.coordenadas != lectura.coordenadas) centrar(nueva.coordenadas);
  }

  /// «Nueva» o el dedo mantenido en un lugar vacío del mapa: el alta, y al volver la ubicación
  /// registrada (o la que se reutilizó) queda seleccionada.
  Future<void> _abrirAlta([Coordenadas? punto]) async {
    if (_abriendoAlta) return;
    _abriendoAlta = true;
    try {
      final personalizado = widget.alAbrirAlta;
      final salida = personalizado != null
          ? await personalizado(punto)
          : await AltaUbicacionPage.abrir(
              context,
              colportorId: widget.colportorId,
              puntoInicial: punto,
            );
      if (!mounted) return;
      switch (salida) {
        case UbicacionCreada(:final ubicacion):
          _notificador.seleccionar(ubicacion.id);
          final nueva = _altura == AlturaHoja.minimizada ? AlturaHoja.tercio : _altura;
          if (nueva != _altura) setState(() => _altura = nueva);
          _centrarEn(ubicacion.coordenadas, nueva, zoomMinimo: MapaAlta.zoomCalle);
        case UbicacionReutilizada(:final ubicacionId):
          _alReutilizar(ubicacionId);
        case null:
          return;
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text(TextosMapaUbicaciones.noPudimosAbrirAlta)));
    } finally {
      _abriendoAlta = false;
    }
  }

  /// El alta devolvió una ubicación que ya existía. Si es una de las del colportor se elige, como al
  /// crearla. Si no está en su lista es de otro colportor (el duplicado se mira contra toda la base):
  /// el mapa no la dibuja ni la centra, se lo dice y no deja ninguna selección colgada (decisión del
  /// 07/10 en el #294).
  void _alReutilizar(String ubicacionId) {
    final lista = ref.read(_proveedor).lista;
    final esDelColportor =
        lista == null || lista.items.any((item) => item.ubicacion.id == ubicacionId);
    if (esDelColportor) {
      _elegir(ubicacionId, zoomMinimo: MapaAlta.zoomCalle);
      return;
    }
    _notificador.cerrarSeleccion();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(TextosMapaUbicaciones.ubicacionDeOtroColportor)));
  }

  Future<void> _abrirReferencias() async {
    if (_abriendoReferencias) return;
    _abriendoReferencias = true;
    try {
      await mostrarReferenciasMapa(context);
    } finally {
      _abriendoReferencias = false;
    }
  }

  void _cambiarAltura(AlturaHoja nueva) {
    if (nueva == _altura) return;
    setState(() => _altura = nueva);
  }

  // ---------------------------------------------------------------- dibujo

  List<PuntoMapa> _puntos(MapaUbicacionesState estado) {
    final seleccionada = estado.seleccionada?.ubicacion.id;
    return [
      for (final item in estado.lista?.items ?? const <ItemListaUbicacion>[])
        _punto(item, seleccionada: item.ubicacion.id == seleccionada),
      if (estado.lectura != null)
        PuntoMapa(id: 'gps', coordenadas: estado.lectura!.coordenadas, estilo: EstiloPunto.gps),
    ];
  }

  PuntoMapa _punto(ItemListaUbicacion item, {required bool seleccionada}) {
    final ubicacion = item.ubicacion;
    final distancia = item.distanciaMetros;
    final cerca = distancia != null && distancia <= MapaUbicacionesState.radioCercaMetros;
    final estilo = seleccionada
        ? EstiloPunto.seleccionado
        : (cerca ? EstiloPunto.cercano : EstiloPunto.contexto);
    return PuntoMapa(
      id: ubicacion.id,
      coordenadas: ubicacion.coordenadas,
      estilo: estilo,
      etiqueta: estilo == EstiloPunto.contexto
          ? null
          : FormatoMapaUbicaciones.etiquetaPuerta(ubicacion),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_abierta) return const SizedBox.expand();
    final estado = ref.watch(_proveedor);
    final ambito = ref.watch(ambitoMapaUbicacionesProvider(widget.colportorId));
    final ahora = ref.watch(relojListaUbicacionesProvider)();
    final avisoVisible = ref.watch(avisoMapaVisibleProvider(ambito));
    ref.listen(_proveedor, (anterior, nuevo) {
      // Sin ubicaciones o sin poder leerlas, la hoja sube sola para decir qué hacer: minimizada solo
      // se ve la pestaña, y a un tercio, en un teléfono chico, el botón quedaría debajo del borde.
      final sinUbicaciones =
          (nuevo.lista?.sinUbicaciones ?? false) && !(anterior?.lista?.sinUbicaciones ?? false);
      final fallo = nuevo.fallaLectura && !(anterior?.fallaLectura ?? false);
      final sube = (sinUbicaciones || fallo) && _altura == AlturaHoja.minimizada;
      if (sube) setState(() => _altura = AlturaHoja.mitad);
      final encuadradoAntes = _encuadre == _Encuadre.gps;
      _encuadrarSiHaceFalta(nuevo);
      // La hoja más alta tapa más del mapa: si el mapa ya estaba sobre el GPS y el colportor no lo
      // movió, el punto azul se vuelve a poner en la parte libre.
      final lectura = nuevo.lectura;
      if (sube && encuadradoAntes && _gestos == 0 && lectura != null) {
        _centrarEn(lectura.coordenadas, _altura, zoomMinimo: MapaAlta.zoomCalle);
      }
    });

    // Con la vista previa abierta, el atrás del teléfono hace lo que la ✕: cierra la vista previa y
    // deja la hoja a la altura que tenía. Solo con la pestaña a la vista: en otra, el atrás es de
    // la pantalla principal (y esta le avisa que ya es de ella: `InicioPage`).
    final conVistaPrevia = widget.activa && estado.seleccionada != null;
    return PopScope(
      canPop: !conVistaPrevia,
      onPopInvokedWithResult: (salio, _) {
        if (!salio && widget.activa) _notificador.cerrarSeleccion();
      },
      child: _contenido(context, estado, ambito, ahora, avisoVisible),
    );
  }

  Widget _contenido(
    BuildContext context,
    MapaUbicacionesState estado,
    AmbitoTrabajo ambito,
    DateTime ahora,
    bool avisoVisible,
  ) {
    final lectura = estado.lectura;
    return LayoutBuilder(
      builder: (context, restricciones) {
        _tamano = restricciones.biggest;
        final hoja = _altoHoja(_altura);
        // Lo que queda libre arriba, sobre los botones y la hoja: ahí caben el aviso de conexión y
        // «Referencias». La tarjeta del aviso no puede pasar de ahí (con el texto grande se
        // desliza): más abajo quedaría detrás de los botones y de la hoja, con sus acciones a las
        // que no se llega (QA del #294).
        final libre = math.max(0.0, _tamano.height - hoja - _altoBotones());
        return Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: TextosMapaUbicaciones.mapa,
                container: true,
                child: MapaBase(
                  fuente: ref.watch(fuenteMapaProvider(ambito)),
                  camaraInicial: CamaraMapa(
                    centro: MapaAlta.centroPorDefecto,
                    zoom: MapaAlta.zoomPais,
                  ),
                  zoomMinimo: MapaAlta.zoomMinimo,
                  zoomMaximo: MapaAlta.zoomMaximo,
                  agruparPuntos: true,
                  puntos: _puntos(estado),
                  precision: lectura != null
                      ? CirculoPrecision(
                          centro: lectura.coordenadas,
                          radioMetros: lectura.precisionMetros.isFinite
                              ? lectura.precisionMetros
                              : 0,
                        )
                      : null,
                  cercania: lectura != null
                      ? CirculoCercania(
                          centro: lectura.coordenadas,
                          radioMetros: MapaUbicacionesState.radioCercaMetros,
                        )
                      : null,
                  reservaInferior: hoja,
                  alCrearse: _alCrearseElMapa,
                  alMoverCamara: (_) => _gestos++,
                  alTocarLargo: (punto) => unawaited(_abrirAlta(punto)),
                  alTocarPunto: _alTocarPunto,
                ),
              ),
            ),
            // Todo hijo del `Stack` va posicionado: uno sin posición (el aviso, que sin aviso es un
            // `SizedBox.shrink`) le da su tamaño al `Stack`, y un `Stack` de 0 x 0 no recibe toques.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: libre,
              child: Stack(
                children: [
                  // «Referencias» y el aviso comparten el borde de arriba: con el aviso a la vista
                  // (la tarjeta o la píldora) el chip se corre, el canvas no los dibuja juntos.
                  if (!avisoVisible)
                    Positioned(
                      top: 8,
                      right: 14,
                      child: ChipReferencias(
                        key: ClavesMapaUbicaciones.referencias,
                        alPresionar: () => unawaited(_abrirReferencias()),
                      ),
                    ),
                  Positioned.fill(
                    child: AvisoMapaConectado(ambito: ambito, modo: AvisoMapaModo.flotante),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 14, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        spacing: 10,
                        children: [
                          BotonMiUbicacion(
                            key: ClavesMapaUbicaciones.miUbicacion,
                            // Sin una lectura no hay a dónde ir: no está disponible (HU-UBI-003,
                            // «Edge: sin GPS»).
                            alPresionar: lectura == null
                                ? null
                                : () => unawaited(_irAMiUbicacion()),
                          ),
                          BotonNuevaUbicacion(
                            key: ClavesMapaUbicaciones.nueva,
                            alPresionar: () => unawaited(_abrirAlta()),
                          ),
                        ],
                      ),
                    ),
                  ),
                  HojaMapaUbicaciones(
                    estado: estado,
                    altura: _altura,
                    alturaDisponible: _tamano.height,
                    reservaLibre: _reservaSobreLaHoja(),
                    ahora: ahora,
                    alCambiarAltura: _cambiarAltura,
                    alElegir: (id) => _elegir(id, zoomMinimo: MapaAlta.zoomCalle),
                    alCerrarVistaPrevia: _notificador.cerrarSeleccion,
                    alReintentar: _notificador.reintentar,
                    alActivarGps: () => unawaited(_notificador.activarGps()),
                    alRegistrar: () => unawaited(_abrirAlta()),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
