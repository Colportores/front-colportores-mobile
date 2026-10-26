import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../../tiles/domain/entities/paquete_tiles.dart' show AmbitoTrabajo;
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/entities/ubicacion.dart' show TipoUbicacion, Ubicacion;
import '../../domain/services/cuadrados_del_mapa.dart';
import '../../domain/services/proyeccion_mercator.dart';
import '../../domain/services/ubicaciones_en_el_punto.dart';
import '../../domain/value_objects/area_mapa.dart';
import '../../domain/value_objects/camara_mapa.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../formato_hoja_casa.dart' show TextosHojaCasa;
import '../formato_mapa_ubicaciones.dart';
import '../mapa_base/mapa_base.dart';
import '../mapa_base/marcador_estado.dart' show VarianteMarcador;
import '../mapa_base/modelo_mapa_base.dart';
import '../providers/alta_ubicacion_notifier.dart';
import '../providers/hoja_casa_providers.dart';
import '../providers/lista_ubicaciones_providers.dart';
import '../providers/mapa_base_providers.dart';
import '../providers/mapa_ubicaciones_notifier.dart';
import '../providers/mapa_ubicaciones_providers.dart';
import '../providers/personas_providers.dart' show espacioRepositoryProvider;
import '../providers/situacion_mapa_providers.dart';
import '../salida_alta_ubicacion.dart';
import '../textos_alta_por_pin.dart';
import '../widgets/aviso_mapa.dart';
import '../widgets/hoja_mapa_ubicaciones.dart';
import '../widgets/hoja_posicion_nueva.dart';
import '../widgets/hoja_que_hay_aca.dart';
import '../widgets/mapa_alta.dart';
import '../widgets/piezas_mapa_ubicaciones.dart';
import '../widgets/pin_nueva_casa.dart';
import 'alta_ubicacion_page.dart' show AltaUbicacionPage;

/// La pestaña «Mapa» (vista 06, HU-UBI-003): las ubicaciones del colportor sobre el mapa, su GPS y,
/// abajo, la hoja «Cercanía» con la lista de la más cercana a la más lejana o la vista previa de la
/// ubicación que se tocó.
///
/// Vive dentro de la pantalla principal (`IndexedStack`, que arma todas las pestañas al arrancar):
/// [activa] dice si la pestaña está a la vista. Hasta que se abre por primera vez no arma el mapa ni
/// lee la base: el mapa nativo cuesta memoria y datos. El GPS se pide esa primera vez, no al
/// arrancar la app, y se refresca cada vez que se vuelve a ella.
///
/// Cada casa se ve con el color y el símbolo de su estado (`house_status`, vista 39, HU-VIS-005):
/// de lejos es un punto de color (M·01) y, acercando, un cuadrado de 40 dp con su número (M·02). Los
/// cuadrados aparecen solo cuando **entran todos** los de lo que se ve sin taparse (decisión de
/// Cristian del 23/10, «Números casas»: [CuadradosDelMapa]); hasta entonces siguen los puntos y los
/// grupos de HU-UBI-003.
///
/// **Sumar una casa** (vista 39, N·01 a N·03, #451): el botón del pin de abajo a la derecha se arrastra
/// al mapa (o se toca y queda en el centro) y reemplaza al «Nueva» y al dedo mantenido en el mapa.
/// Soltado, el pin queda en el mapa con la dirección que el mapa conoce y «Confirmar posición» (N·01);
/// «¿Qué hay acá?» pide tipo y número y registra (N·02, con las reglas de las vistas 03 y 04); una casa
/// recién registrada sigue directo a «¿Qué pasó?» (N·03).
///
/// Qué queda para otras HU (decisión de Cristian en el #199): «Agendados» y la vista previa con
/// «Registrar visita» y «Agendar» (HU-VIS-001 y HU-VIS-002) y «Cobranza» (HU-COB-005).
class MapaUbicacionesPage extends ConsumerStatefulWidget {
  const MapaUbicacionesPage({
    super.key,
    required this.colportorId,
    this.activa = true,
    this.alConfirmarPosicion,
  });

  /// UUID del colportor con la sesión iniciada: el mapa es «las que registré».
  final String colportorId;

  /// La pestaña está a la vista.
  final bool activa;

  /// Cómo se abre N·02 «¿Qué hay acá?» con el pin puesto, y cómo terminó. Por defecto, la hoja de la
  /// vista 39 ([mostrarHojaQueHayAca]); un test la reemplaza.
  final Future<SalidaAltaUbicacion?> Function(ParametrosAlta alta)? alConfirmarPosicion;

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

  /// La cámara de la última vez que el mapa quedó quieto: con ella se decide si las casas se dibujan
  /// como cuadrados (nunca mientras el mapa se mueve: el cuadro cambiaría a cada paso del gesto).
  CamaraMapa? _camaraQuieta;

  /// Lo último que se le preguntó a [CuadradosDelMapa] y lo que contestó: la misma cámara, vista y
  /// lista no se vuelven a calcular. [_cuadradosPintados] es lo que se dibujó en el último cuadro.
  ({CamaraMapa camara, Size vista, double reserva, ListaUbicaciones lista})? _entradaCuadrados;
  var _cuadradosCalculados = false;
  var _cuadradosPintados = false;

  /// Una sola leyenda a la vez: un segundo toque no abre otra encima.
  var _abriendoReferencias = false;

  // ---- Sumar una casa con el pin (vista 39, N·01 a N·03).

  /// El alta en curso desde que se soltó el pin hasta que se registra o se cancela (N·01 y N·02); `null`
  /// si no hay ninguna. Su estado (punto, dirección, tipo, ciudad) es `altaUbicacionProvider(_alta)`.
  ParametrosAlta? _alta;

  /// Mientras se lleva el pin con el dedo desde el botón: dónde está el dedo, en coordenadas de la
  /// pantalla. `null` si no se lo está llevando.
  Offset? _dedo;

  /// Mientras se lleva el pin ya puesto a otro lado: dónde está su centro en la vista.
  Offset? _pinArrastrado;

  /// Un solo N·02 a la vez: un segundo toque en «Confirmar posición» no abre otra hoja encima.
  var _confirmando = false;

  /// Cuánto sobre el dedo se dibuja el pin que se lleva (para verlo) y cuánto sobre él queda su punto
  /// al soltarlo: la diferencia es lo que el pin cae al soltarlo.
  static const _pinSobreElDedo = 72.0;
  static const _pinAlSoltar = _pinSobreElDedo - PinSobreElMapa.alturaDeLaCaida;

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
    // Un pin puesto no sobrevive a un cambio de pestaña: al volver, el mapa está como se lo dejó.
    if (!widget.activa && anterior.activa) {
      _alta = null;
      _dedo = null;
      _pinArrastrado = null;
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

  /// Lo que ocupan los botones flotantes («Mi ubicación» y el pin de la casa nueva) sobre la hoja.
  double _altoBotones() {
    // «Mi ubicación» (52), el pin de la casa nueva (su leyenda, con el texto grande, puede ser más alta
    // que el círculo), 10 entre ellos y 14 de margen abajo.
    return 52 + 10 + BotonPinNuevaCasa.alto(context) + 14;
  }

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

  // ---------------------------------------------------------------- cuadrados (M·02)

  /// ¿Entran todos los cuadrados de las casas que se ven, sin taparse? Se mira con la cámara de la
  /// última vez que el mapa quedó quieto y con la parte del mapa que la hoja no tapa.
  bool _entranLosCuadrados(MapaUbicacionesState estado) {
    final camara = _camaraQuieta;
    final lista = estado.lista;
    if (camara == null || lista == null || _tamano.isEmpty) return false;
    final reserva = _altoHoja(_altura);
    final previa = _entradaCuadrados;
    if (previa != null &&
        previa.camara == camara &&
        previa.vista == _tamano &&
        previa.reserva == reserva &&
        identical(previa.lista, lista)) {
      return _cuadradosCalculados;
    }
    _entradaCuadrados = (camara: camara, vista: _tamano, reserva: reserva, lista: lista);
    return _cuadradosCalculados = CuadradosDelMapa.entranTodos(
      casas: [for (final item in lista.items) item.ubicacion.coordenadas],
      camara: camara,
      ancho: _tamano.width,
      alto: _tamano.height,
      reservaInferior: reserva,
    );
  }

  /// El mapa quedó quieto: si con esta cámara cambia entre puntos y cuadrados, se vuelve a dibujar.
  void _alQuedarQuieto(CamaraMapa camara, AreaMapa area) {
    _camaraQuieta = camara;
    if (!mounted) return;
    // El pin de la casa nueva es un widget: se vuelve a ubicar con la cámara nueva.
    if (_alta != null || _entranLosCuadrados(ref.read(_proveedor)) != _cuadradosPintados) {
      setState(() {});
    }
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
    final candidatas = _candidatasEnElPunto(id);
    if (candidatas.length >= 2) {
      _elegirEntre(candidatas);
      return;
    }
    _elegir(id);
  }

  /// Las ubicaciones entre las que hay que elegir al tocar [id] (vista 39, E·06): las que el mapa
  /// pinta a 44 dp o menos del toque, **solo** con el mapa en su zoom máximo —antes de eso se abre la
  /// más cercana y con los dedos se acerca—. Vacía si no hay nada que elegir.
  List<String> _candidatasEnElPunto(String id) {
    final lista = ref.read(_proveedor).lista;
    final camara = _mapa?.camara ?? _camaraQuieta;
    if (lista == null || camara == null) return const [];
    return UbicacionesEnElPunto.elegibles(
      tocada: id,
      todas: [
        for (final item in lista.items)
          (id: item.ubicacion.id, coordenadas: item.ubicacion.coordenadas),
      ],
      zoom: camara.zoom,
      zoomMaximo: MapaAlta.zoomMaximo,
    );
  }

  /// «3 ubicaciones acá»: la hoja pide elegir cuál, de la más cercana al toque a la más lejana. El
  /// mapa se centra en la tocada, que va primera.
  void _elegirEntre(List<String> ids) {
    final lista = ref.read(_proveedor).lista;
    ItemListaUbicacion? tocada;
    for (final candidato in lista?.items ?? const <ItemListaUbicacion>[]) {
      if (candidato.ubicacion.id == ids.first) tocada = candidato;
    }
    _notificador.elegirEntre(ids);
    // Elegir es mirar varias filas: a un tercio se verían una y media. Sube a la mitad (el colportor
    // la baja si quiere el mapa).
    const nueva = AlturaHoja.mitad;
    if (nueva != _altura) setState(() => _altura = nueva);
    if (tocada != null) _centrarEn(tocada.ubicacion.coordenadas, nueva);
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

  // ---------------------------------------------------------------- sumar una casa (vista 39)

  /// La cámara con que se ubica el pin de la casa nueva: la última que el mapa conoce.
  CamaraMapa? get _camaraVista => _mapa?.camara ?? _camaraQuieta;

  /// El dedo empezó a llevar el pin desde el botón.
  void _alEmpezarPin(Offset global) {
    // Con la cuenta restringida mientras esta pantalla estaba abierta no se empieza un alta nueva.
    if (_alta != null || frenaPorCuentaRestringida(context, ref)) return;
    setState(() => _dedo = global);
  }

  void _alMoverPin(Offset global) {
    if (_dedo != null) setState(() => _dedo = global);
  }

  void _alCancelarPin() {
    if (_dedo != null) setState(() => _dedo = null);
  }

  /// Se soltó el pin: si cae sobre el mapa se pone ahí; si cae sobre la lista o afuera, no se suma nada
  /// y se dice cómo hacerlo.
  void _alSoltarPin() {
    final dedo = _dedo;
    final caja = context.findRenderObject();
    setState(() => _dedo = null);
    if (dedo == null || caja is! RenderBox || _alta != null) return;
    final local = caja.globalToLocal(dedo);
    _ponerPin(Offset(local.dx, local.dy - _pinAlSoltar), avisarSiNoCae: true);
  }

  /// Tocar el botón (sin arrastrar): el pin va al GPS, si hay, y si no al centro de lo que se ve del
  /// mapa. Es la alternativa al arrastre (WCAG 2.5.7) y lo que hace «Registrar tu primera ubicación».
  void _alTocarPin() {
    if (_alta != null || frenaPorCuentaRestringida(context, ref)) return;
    final lectura = ref.read(_proveedor).lectura;
    if (lectura != null) {
      _empezarAlta(lectura.coordenadas);
      // El punto del GPS puede estar fuera de lo que se ve: el mapa va a él, con el pin a la vista.
      _centrarEn(lectura.coordenadas, AlturaHoja.tercio, zoomMinimo: MapaAlta.zoomCalle);
      return;
    }
    _ponerPin(Offset(_tamano.width / 2, (_tamano.height - _altoHoja(_altura)) / 2));
  }

  /// Pone el pin en [centro] (coordenadas de la vista). Sin cámara o fuera del mapa que se ve no hace
  /// nada; con [avisarSiNoCae] además dice que hay que soltarlo sobre el mapa.
  void _ponerPin(Offset centro, {bool avisarSiNoCae = false}) {
    final camara = _camaraVista;
    final libre = _tamano.height - _altoHoja(_altura);
    final cae =
        camara != null &&
        !_tamano.isEmpty &&
        centro.dx >= 0 &&
        centro.dx <= _tamano.width &&
        centro.dy >= 0 &&
        centro.dy <= libre;
    if (!cae) {
      if (avisarSiNoCae) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text(TextosAltaPorPin.soltalo)));
      }
      return;
    }
    _empezarAlta(
      ProyeccionMercator.dePantalla(
        centro.dx,
        centro.dy,
        camara,
        ancho: _tamano.width,
        alto: _tamano.height,
      ),
    );
  }

  /// N·01: el pin queda puesto en [punto]. La vista previa que hubiera abierta se cierra.
  void _empezarAlta(Coordenadas punto) {
    _notificador.cerrarSeleccion();
    // El aviso de antes (por ejemplo, «Esa ubicación ya la registró otro colportor») no tapa
    // «Confirmar posición», que queda en el mismo borde de abajo.
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    setState(() {
      _pinArrastrado = null;
      _alta = ParametrosAlta(
        colportorId: widget.colportorId,
        puntoInicial: punto,
        apertura: AltaUbicacionPage.siguienteApertura(),
      );
    });
  }

  /// Un toque en el mapa con el pin puesto: el pin se reubica ahí.
  void _alTocarElMapa(Coordenadas punto) {
    final alta = _alta;
    if (alta == null) return;
    ref.read(altaUbicacionProvider(alta).notifier).moverPunto(punto);
  }

  /// El dedo lleva el pin puesto a otro lado.
  void _alLlevarElPin(Offset delta) {
    final alta = _alta;
    final camara = _camaraVista;
    if (alta == null || camara == null) return;
    final punto = ref.read(altaUbicacionProvider(alta)).punto;
    final actual = _pinArrastrado ?? _centroDelPin(camara, punto);
    if (actual == null) return;
    setState(() => _pinArrastrado = actual + delta);
  }

  void _alSoltarElPin() {
    final centro = _pinArrastrado;
    final alta = _alta;
    final camara = _camaraVista;
    setState(() => _pinArrastrado = null);
    if (centro == null || alta == null || camara == null) return;
    ref
        .read(altaUbicacionProvider(alta).notifier)
        .moverPunto(
          ProyeccionMercator.dePantalla(
            centro.dx.clamp(0.0, _tamano.width),
            centro.dy.clamp(0.0, _tamano.height),
            camara,
            ancho: _tamano.width,
            alto: _tamano.height,
          ),
        );
  }

  Offset? _centroDelPin(CamaraMapa camara, Coordenadas? punto) {
    if (punto == null || _tamano.isEmpty) return null;
    final p = ProyeccionMercator.aPantalla(
      punto,
      camara,
      ancho: _tamano.width,
      alto: _tamano.height,
    );
    return Offset(p.x, p.y);
  }

  /// La ✕ de N·01 y el atrás del sistema: el pin se va y no se registra nada.
  void _cancelarAlta() {
    if (_alta == null) return;
    setState(() {
      _alta = null;
      _pinArrastrado = null;
    });
  }

  /// «Confirmar posición» (N·01): abre «¿Qué hay acá?» (N·02) y, al volver, sigue según cómo terminó.
  Future<void> _confirmarPosicion() async {
    final alta = _alta;
    if (alta == null || _confirmando) return;
    _confirmando = true;
    try {
      final personalizado = widget.alConfirmarPosicion;
      final salida = personalizado != null
          ? await personalizado(alta)
          : await mostrarHojaQueHayAca(context, parametros: alta);
      if (!mounted) return;
      await _alTerminarElAlta(salida);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text(TextosMapaUbicaciones.noPudimosAbrirAlta)));
    } finally {
      _confirmando = false;
    }
  }

  /// N·02 terminó: `null` es «Volver» (el pin sigue puesto); una ubicación registrada queda
  /// seleccionada y, si es una casa, sigue a «¿Qué pasó?» (N·03); una que ya existía se abre como en el
  /// aviso de duplicado.
  Future<void> _alTerminarElAlta(SalidaAltaUbicacion? salida) async {
    switch (salida) {
      case null:
        return;
      case UbicacionReutilizada(:final ubicacionId):
        setState(() => _alta = null);
        _alReutilizar(ubicacionId);
      case UbicacionCreada(:final ubicacion):
        setState(() => _alta = null);
        _notificador.seleccionar(ubicacion.id);
        final nueva = _altura == AlturaHoja.minimizada ? AlturaHoja.tercio : _altura;
        if (nueva != _altura) setState(() => _altura = nueva);
        _centrarEn(ubicacion.coordenadas, nueva, zoomMinimo: MapaAlta.zoomCalle);
        await _preguntarQuePaso(ubicacion);
    }
  }

  /// N·03: una casa recién registrada sigue directo a «¿Qué pasó?». Un edificio sigue a sus deptos
  /// (#452) y un negocio todavía no tiene espacio (S13): esos quedan registrados y con su hoja.
  Future<void> _preguntarQuePaso(Ubicacion ubicacion) async {
    final destino = ref.read(registrarVisitaDeLaCasaNuevaProvider);
    if (destino == null || ubicacion.tipo != TipoUbicacion.casa) return;
    String? espacioId;
    try {
      final r = await ref.read(espacioRepositoryProvider).listar(ubicacion.id);
      espacioId = r.fold((_) => null, (espacios) => espacios.firstOrNull?.id);
    } on Object {
      espacioId = null;
    }
    if (!mounted || espacioId == null) return;
    final Object? resuelta;
    try {
      resuelta = await destino((ubicacionId: ubicacion.id, espacioId: espacioId));
    } on Object {
      if (!mounted) return;
      // La casa ya está registrada: su hoja sigue a la vista y desde ahí se registra la visita.
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(TextosHojaCasa.noPudimosAbrirVisita)));
      return;
    }
    // Se guardó una visita (o siguió a otro flujo): la hoja de la casa se va y el mapa muestra el color
    // nuevo. Con «Volver» la casa queda registrada, sin visita, con su hoja.
    if (resuelta == true && mounted) _notificador.cerrarSeleccion();
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

  List<PuntoMapa> _puntos(MapaUbicacionesState estado, {required bool cuadrados}) {
    final seleccionada = estado.seleccionada?.ubicacion.id;
    return [
      for (final item in estado.lista?.items ?? const <ItemListaUbicacion>[])
        _punto(item, seleccionada: item.ubicacion.id == seleccionada, cuadrados: cuadrados),
      if (estado.lectura != null)
        PuntoMapa(id: 'gps', coordenadas: estado.lectura!.coordenadas, estilo: EstiloPunto.gps),
    ];
  }

  /// El marcador de una casa: con [cuadrados] el cuadrado de M·02 (con el aro si es la elegida); si
  /// no, el que se toca, el de «cerca tuyo», la insignia de su estado (M·01) o, sin estado, el punto
  /// de «Sin visita». El estado sale de `house_status` (`ItemListaUbicacion.estado`).
  PuntoMapa _punto(ItemListaUbicacion item, {required bool seleccionada, required bool cuadrados}) {
    final ubicacion = item.ubicacion;
    final variante = VarianteMarcador.de(
      item.estado,
      edificio: ubicacion.tipo == TipoUbicacion.edificio,
    );
    final distancia = item.distanciaMetros;
    final cerca = distancia != null && distancia <= MapaUbicacionesState.radioCercaMetros;
    final estilo = cuadrados
        ? (seleccionada ? EstiloPunto.cuadradoSeleccionado : EstiloPunto.cuadrado)
        : seleccionada
        ? EstiloPunto.seleccionado
        : cerca
        ? EstiloPunto.cercano
        : (variante == VarianteMarcador.sinVisita ? EstiloPunto.contexto : EstiloPunto.conEstado);
    return PuntoMapa(
      id: ubicacion.id,
      coordenadas: ubicacion.coordenadas,
      estilo: estilo,
      variante: variante,
      etiqueta: estilo == EstiloPunto.contexto || estilo == EstiloPunto.conEstado
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
    final conVistaPrevia = widget.activa && estado.hayVistaPrevia;
    // Con el pin puesto (N·01) el atrás del teléfono lo saca, como la ✕. Se mira el estado del alta acá,
    // en `build`, para que el pin siga vivo mientras se lo muestra.
    final alta = _alta;
    final estadoAlta = alta == null ? null : ref.watch(altaUbicacionProvider(alta));
    return PopScope(
      canPop: !conVistaPrevia && alta == null,
      onPopInvokedWithResult: (salio, _) {
        if (salio || !widget.activa) return;
        if (_alta != null) {
          _cancelarAlta();
        } else {
          _notificador.cerrarSeleccion();
        }
      },
      child: _contenido(context, estado, ambito, ahora, avisoVisible, estadoAlta),
    );
  }

  /// El título de N·01: la dirección del punto, o por qué todavía no hay.
  String _tituloDelPin(AltaUbicacionState alta) {
    if (alta.buscandoDireccion) return TextosAltaPorPin.buscandoDireccion;
    final direccion = TextosAltaPorPin.direccion(alta);
    return direccion.isEmpty ? TextosAltaPorPin.sinDireccion : direccion;
  }

  /// El pin de la casa nueva ya soltado (N·01): un widget encima del mapa, ubicado con la cámara.
  List<Widget> _pinPuesto(AltaUbicacionState? alta) {
    final camara = _camaraVista;
    final punto = alta?.punto;
    if (alta == null || camara == null || punto == null || _tamano.isEmpty) return const [];
    final centro = _pinArrastrado ?? _centroDelPin(camara, punto);
    if (centro == null) return const [];
    const mitad = ladoToquePinCasaNueva / 2;
    return [
      Positioned(
        left: centro.dx - mitad,
        top: centro.dy - mitad,
        width: ladoToquePinCasaNueva,
        height: ladoToquePinCasaNueva,
        child: PinSobreElMapa(
          key: ValueKey(_alta),
          alMover: _alLlevarElPin,
          alSoltar: _alSoltarElPin,
          deshabilitado: alta.guardando,
        ),
      ),
    ];
  }

  /// El pin que se lleva desde el botón: sobre el dedo, para que el dedo no lo tape.
  List<Widget> _pinEnArrastre() {
    final dedo = _dedo;
    final caja = context.findRenderObject();
    if (dedo == null || caja is! RenderBox || !caja.hasSize) return const [];
    final local = caja.globalToLocal(dedo);
    const mitad = ladoToquePinCasaNueva / 2;
    return [
      Positioned(
        left: local.dx - mitad,
        top: local.dy - _pinSobreElDedo - mitad,
        width: ladoToquePinCasaNueva,
        height: ladoToquePinCasaNueva,
        child: const IgnorePointer(
          child: Center(child: PinEnArrastre(key: ClavesPinNuevaCasa.enArrastre)),
        ),
      ),
    ];
  }

  Widget _contenido(
    BuildContext context,
    MapaUbicacionesState estado,
    AmbitoTrabajo ambito,
    DateTime ahora,
    bool avisoVisible,
    AltaUbicacionState? alta,
  ) {
    final lectura = estado.lectura;
    return LayoutBuilder(
      builder: (context, restricciones) {
        _tamano = restricciones.biggest;
        final hoja = _altoHoja(_altura);
        final cuadrados = _cuadradosPintados = _entranLosCuadrados(estado);
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
                  puntos: _puntos(estado, cuadrados: cuadrados),
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
                  alMoverCamara: (_) {
                    _gestos++;
                    // El pin de la casa nueva sigue al mapa mientras se lo mueve.
                    if (_alta != null) setState(() {});
                  },
                  alQuedarQuieto: _alQuedarQuieto,
                  alTocar: _alTocarElMapa,
                  // Con el pin puesto el mapa solo sirve para ubicarlo: tocar una casa no abre su hoja.
                  alTocarPunto: _alta == null ? _alTocarPunto : null,
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
                    child: AvisoMapaConectado(
                      ambito: ambito,
                      modo: AvisoMapaModo.flotante,
                      altoLibre: libre,
                    ),
                  ),
                ],
              ),
            ),
            // El pin de la casa nueva, ya soltado (N·01): sigue al mapa y se puede llevar a otro lado.
            ..._pinPuesto(alta),
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
                            gps: estado.gps,
                            // Sin una lectura no hay a dónde ir: no está disponible (HU-UBI-003,
                            // «Edge: sin GPS»).
                            alPresionar: lectura == null
                                ? null
                                : () => unawaited(_irAMiUbicacion()),
                          ),
                          // Con un pin puesto no se suma otro: el botón vuelve al cancelarlo.
                          if (alta == null)
                            BotonPinNuevaCasa(
                              key: ClavesMapaUbicaciones.nueva,
                              alEmpezar: _alEmpezarPin,
                              alMover: _alMoverPin,
                              alSoltar: _alSoltarPin,
                              alCancelar: _alCancelarPin,
                              alTocar: _alTocarPin,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (alta != null)
                    HojaPosicionNueva(
                      titulo: _tituloDelPin(alta),
                      alConfirmar: () => unawaited(_confirmarPosicion()),
                      alCancelar: _cancelarAlta,
                    )
                  else
                    HojaMapaUbicaciones(
                      estado: estado,
                      altura: _altura,
                      alturaDisponible: _tamano.height,
                      reservaLibre: _reservaSobreLaHoja(),
                      ahora: ahora,
                      alCambiarAltura: _cambiarAltura,
                      alElegir: (id) => _elegir(id, zoomMinimo: MapaAlta.zoomCalle),
                      alCerrarVistaPrevia: _notificador.cerrarSeleccion,
                      alElegirDelPunto: (id) => _elegir(id),
                      alReintentar: _notificador.reintentar,
                      alActivarGps: () => unawaited(_notificador.activarGps()),
                      alRegistrar: _alTocarPin,
                    ),
                ],
              ),
            ),
            // El pin que se lleva con el dedo desde el botón, por encima de todo.
            ..._pinEnArrastre(),
          ],
        );
      },
    );
  }
}
