import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/resultado_alta_ubicacion.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../../domain/value_objects/punto_capturado.dart';
import '../formato_ubicaciones.dart';
import '../pages/alta_ubicacion_page.dart'
    show SalidaAltaUbicacion, UbicacionCreada, UbicacionReutilizada;
import '../providers/alta_ubicacion_notifier.dart';
import '../providers/alta_ubicacion_providers.dart';
import '../providers/mapa_principal_provider.dart';
import '../providers/pantallas_sobre_el_mapa.dart' show RutasCapaDelMapa;
import 'campos_ubicacion.dart';
import 'hoja_alta.dart';
import 'hoja_duplicado_alta.dart';
import 'mapa_alta.dart' show MapaAlta;
import 'piezas_alta.dart';
import 'ruta_capa_del_mapa.dart';

/// Los textos del alta sobre el mapa principal (vista 41, grupos 41A y 41B), tal cual el canvas.
abstract final class TextosAltaMapa {
  static const confirmarPosicion = 'Confirmar posición';
  static const arrastraElPin = 'Arrastrá el pin o tocá el mapa para moverlo.';
  static const casaNueva = 'Casa nueva';
  static const queHayAca = '¿Qué hay acá?';
  static const volver = 'Volver';
  static const cancelar = 'Cancelar';
  static const ciudad = 'CIUDAD';
  static const elegiLaCiudad = 'Elegí la ciudad';
  static const buscarCiudad = 'Buscar ciudad';
  static const delMapa = 'Del mapa';
  static const deTuZona = 'De tu zona';
  static const deTuCampania = 'De tu campaña';
  static const editado = 'Editado';
  static const calleActualizada = 'Calle actualizada';
  static const sinGps = 'Sin GPS';
  static const laNueva = 'La nueva';
  static const crearIgual = 'Crear igual';

  /// HU-UBI-001: mientras se leen las ciudades de la campaña.
  static const buscandoCiudades = 'Buscando las ciudades de tu campaña…';

  /// Propuesta del implementador (el canvas no dibuja la búsqueda sin resultados).
  static const sinResultados =
      'Ninguna ciudad de tu campaña se llama así. Revisá cómo la escribiste.';

  static String gps(double metros) => 'GPS ±${metros.round()} m';
  static String usar(String ciudad) => 'Usar $ciudad';
  static String loEscribisteVos(String delMapa) =>
      'Lo escribiste vos: no lo cambiamos. El mapa dice $delMapa.';
  static String crearIgualTexto(String direccion, String distancia) =>
      'Ya existe $direccion a $distancia. Contá por qué este lugar es otro.';
  static String yaRegistraste(String direccion) => 'Ya registraste $direccion';
  static String unaSolaVez(String distancia) =>
      'Está a $distancia, en la misma ciudad. Una dirección se registra una sola vez.';
  static String yaRegistradaA(String distancia) => 'Ya registrada · a $distancia';
  static String candidataA(String letra, String distancia) => '$letra · a $distancia';
}

/// Las claves que buscan los tests del alta sobre el mapa.
abstract final class ClavesAltaMapa {
  static const hoja = Key('alta_mapa_hoja');
  static const chipGps = Key('alta_mapa_chip_gps');
  static const tocaElMapa = Key('alta_mapa_toca_el_mapa');
  static const velo = Key('alta_mapa_velo');
  static const principal = Key('alta_mapa_principal');
  static const secundario = Key('alta_mapa_secundario');
  static const cerrar = Key('alta_mapa_cerrar');
  static const ciudad = Key('alta_mapa_ciudad');
  static const calle = Key('alta_mapa_calle');
  static const numero = Key('alta_mapa_numero');
  static const buscarCiudad = Key('alta_mapa_buscar_ciudad');
  static const justificacion = Key('alta_mapa_justificacion');
  static const crearIgual = Key('alta_mapa_crear_igual');
  static Key opcionCiudad(String id) => Key('alta_mapa_ciudad_$id');
  static Key candidata(String id) => Key('alta_mapa_candidata_$id');
}

/// Abre el alta sobre el mapa principal: la capa sin velo ni barrera con su hoja (N·01, N·02, «Elegí
/// la ciudad» y el aviso de duplicado). Devuelve la ubicación creada o la que se reutilizó, o `null`
/// si se canceló (no se guardó nada).
Future<SalidaAltaUbicacion?> abrirAltaSobreElMapa(
  BuildContext context, {
  required ParametrosAlta parametros,
}) => Navigator.of(context).push(
  RutaCapaDelMapa<SalidaAltaUbicacion>(
    settings: const RouteSettings(name: RutasCapaDelMapa.alta),
    builder: (_) => AltaSobreElMapa(parametros: parametros),
  ),
);

/// La capa del alta sobre el mapa principal (vista 41, 41A y 41B). Dibuja el chip del GPS, el chip
/// «Tocá donde está el lugar», el velo de los pasos que lo llevan y la hoja de abajo. Lo demás (el
/// pin, las candidatas y sus etiquetas) lo dibuja la pestaña Mapa, que lee el mismo estado.
///
/// La cámara solo se mueve cuando la colportora lo pide: al confirmar la posición (el pin queda
/// arriba de N·02) y al tocar el pin con un GPS que no está a la vista. Elegir la ciudad, escribir,
/// abrir el teclado o ver las candidatas no la mueven.
class AltaSobreElMapa extends ConsumerStatefulWidget {
  const AltaSobreElMapa({super.key, required this.parametros});

  final ParametrosAlta parametros;

  @override
  ConsumerState<AltaSobreElMapa> createState() => _AltaSobreElMapaState();
}

class _AltaSobreElMapaState extends ConsumerState<AltaSobreElMapa> {
  final _claveHoja = GlobalKey();
  final _calle = TextEditingController();
  final _numero = TextEditingController();
  final _justificacion = TextEditingController();

  /// La capa ya se está cerrando: un segundo toque no la cierra dos veces.
  var _cerrando = false;

  /// Ya se acomodó la cámara al GPS de la primera lectura (una sola vez por alta).
  var _acomodadaAlGps = false;

  AltaUbicacionNotifier get _alta => ref.read(altaUbicacionProvider(widget.parametros).notifier);

  @override
  void initState() {
    super.initState();
    final inicial = ref.read(altaUbicacionProvider(widget.parametros));
    _sincronizarCampos(inicial);
    // El GPS ya tenía lectura al abrir: el pin cae ahí de entrada.
    _alLlegarElPuntoDelGps(null, inicial);
  }

  @override
  void dispose() {
    _calle.dispose();
    _numero.dispose();
    _justificacion.dispose();
    super.dispose();
  }

  /// El borde de arriba de la hoja, en coordenadas globales (`null` si todavía no se dibujó).
  double? _bordeDeLaHoja() {
    final caja = _claveHoja.currentContext?.findRenderObject();
    if (caja is! RenderBox || !caja.hasSize) return null;
    return caja.localToGlobal(Offset.zero).dy;
  }

  void _cerrar([SalidaAltaUbicacion? salida]) {
    if (_cerrando || !mounted) return;
    _cerrando = true;
    Navigator.of(context).pop(salida);
  }

  /// «Confirmar posición» y «Continuar»: el pin queda arriba de N·02, en lo que la hoja deja libre.
  /// Se espera a que N·02 se dibuje para saber cuánto tapa.
  void _acomodarArribaDeLaHoja() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final punto = ref.read(altaUbicacionProvider(widget.parametros)).punto;
      final borde = _bordeDeLaHoja();
      if (punto == null || borde == null) return;
      unawaited(
        ref
            .read(mapaPrincipalProvider.notifier)
            .acomodarArribaDe(punto, bordeDeLaHoja: borde, por: IntencionCamara.confirmarPosicion),
      );
    });
  }

  /// Lo que la etiqueta de un marcador ocupa encima de su punto («La nueva» va sobre el pin).
  static const _reservaEtiquetas = 90.0;

  /// Llegó el aviso de duplicado (tocó «Registrar»): la casa nueva y las que ya estaban tienen que
  /// verse con sus etiquetas arriba de la hoja, para compararlas (41B, sin velo). Si ya se ven, el
  /// mapa no se mueve; si no, las encuadra (aleja solo si no entran).
  void _encuadrarElAviso() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final estado = ref.read(altaUbicacionProvider(widget.parametros));
      final punto = estado.punto;
      final borde = _bordeDeLaHoja();
      if (punto == null || borde == null || estado.paso != PasoAlta.duplicado) return;
      final puntos = [punto, for (final c in estado.candidatas) c.ubicacion.coordenadas];
      final mapa = ref.read(mapaPrincipalProvider.notifier);
      final seVen = puntos.every(
        (p) =>
            mapa.estaALaVista(p, bordeDeLaHoja: borde, margen: 24, margenArriba: _reservaEtiquetas),
      );
      if (seVen) return;
      unawaited(
        mapa.encuadrarArribaDe(
          puntos,
          bordeDeLaHoja: borde,
          por: IntencionCamara.compararDuplicado,
          reservaArriba: _reservaEtiquetas,
        ),
      );
    });
  }

  /// El pin cayó en el GPS al tocar el botón del pin: si esa posición no está a la vista, el mapa va
  /// a ella (la colportora pidió «mi ubicación»). Una sola vez.
  void _alLlegarElPuntoDelGps(AltaUbicacionState? anterior, AltaUbicacionState nuevo) {
    if (_acomodadaAlGps || widget.parametros.puntoInicial != null) return;
    final punto = nuevo.punto;
    if (anterior?.punto != null || punto == null || nuevo.origen != OrigenCoordenadas.gps) return;
    _acomodadaAlGps = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mapa = ref.read(mapaPrincipalProvider.notifier);
      final borde = _bordeDeLaHoja() ?? MediaQuery.sizeOf(context).height;
      if (mapa.estaALaVista(punto, bordeDeLaHoja: borde)) return;
      unawaited(
        mapa.acomodarArribaDe(
          punto,
          bordeDeLaHoja: borde,
          por: IntencionCamara.miUbicacion,
          zoomMinimo: MapaAlta.zoomCalle,
        ),
      );
    });
  }

  /// Lo que la colportora no escribió sigue al mapa: los controladores muestran el valor del estado.
  void _sincronizarCampos(AltaUbicacionState estado) {
    void poner(TextEditingController c, CampoDireccion campo) {
      if (campo.fuente == FuenteCampo.editado || c.text == campo.texto) return;
      c.value = TextEditingValue(
        text: campo.texto,
        selection: TextSelection.collapsed(offset: campo.texto.length),
      );
    }

    poner(_calle, estado.calle);
    poner(_numero, estado.numero);
  }

  Future<void> _registrar({String? justificacion}) async {
    final resultado = await _alta.registrar(justificacion: justificacion);
    if (!mounted) return;
    if (resultado case AltaCreada(:final ubicacion)) _cerrar(UbicacionCreada(ubicacion));
  }

  @override
  Widget build(BuildContext context) {
    final proveedor = altaUbicacionProvider(widget.parametros);
    final estado = ref.watch(proveedor);
    ref.listen(proveedor, (anterior, nuevo) {
      _alLlegarElPuntoDelGps(anterior, nuevo);
      _sincronizarCampos(nuevo);
      if (anterior?.paso != PasoAlta.duplicado && nuevo.paso == PasoAlta.duplicado) {
        _encuadrarElAviso();
      }
    });
    final conVelo = switch (estado.paso) {
      PasoAlta.queHayAca || PasoAlta.ciudad || PasoAlta.crearIgual => true,
      PasoAlta.posicion || PasoAlta.duplicado => false,
    };
    return PopScope(
      // El atrás anda de a un paso (N·02 → N·01, «Crear igual» → el aviso…) y recién en N·01 cierra
      // la capa. Mientras guarda no hace nada.
      canPop: estado.paso == PasoAlta.posicion && !estado.guardando,
      onPopInvokedWithResult: (seCerro, _) {
        if (seCerro) return;
        _alta.atras();
      },
      child: Stack(
        children: [
          if (conVelo)
            Positioned.fill(
              // El velo solo frena los toques al mapa (el pin ya está confirmado; N·02 tiene
              // «Volver»): no es un botón, así que el lector de pantalla no lo ve.
              child: ExcludeSemantics(
                child: GestureDetector(
                  key: ClavesAltaMapa.velo,
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const ColoredBox(color: Color(0x520E1A2B)),
                ),
              ),
            ),
          if (estado.paso == PasoAlta.posicion) ...[
            Positioned(
              top: MediaQuery.paddingOf(context).top + 14,
              left: 16,
              child: _ChipGps(estado: estado),
            ),
            if (estado.punto == null)
              Positioned(
                left: 16,
                right: 16,
                top: MediaQuery.sizeOf(context).height * 0.3,
                child: const Center(child: _ChipTocaElMapa()),
              ),
          ],
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Hoja(
              clave: _claveHoja,
              child: switch (estado.paso) {
                PasoAlta.posicion => _construirPosicion(estado),
                PasoAlta.queHayAca => _construirQueHayAca(estado),
                PasoAlta.ciudad => _HojaCiudades(
                  parametros: widget.parametros,
                  estado: estado,
                  alElegir: _alta.elegirCiudad,
                  alVolver: _alta.atras,
                ),
                PasoAlta.duplicado => _construirDuplicado(estado),
                PasoAlta.crearIgual => _construirCrearIgual(estado),
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- N·01 (41A·01 a 41A·03)

  Widget _construirPosicion(AltaUbicacionState estado) {
    final punto = estado.punto;
    if (punto == null) return _construirSinPunto(estado);
    final preguntaPrecision = estado.necesitaDecisionPrecision;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Encabezado(
          titulo: _direccion(estado) ?? FormatoUbicaciones.coordenadas(punto),
          subtitulo: _subtituloPosicion(estado),
          alCerrar: estado.guardando ? null : _cerrar,
        ),
        const SizedBox(height: 10),
        if (preguntaPrecision)
          const AvisoAlta(
            color: ColoresAlta.ambarBorde,
            colorInsignia: ColoresAlta.ambar,
            glyph: '!',
            texto: AltaConBajaPrecision.aviso,
          )
        else
          const Text(
            TextosAltaMapa.arrastraElPin,
            style: TextStyle(fontSize: 13, color: ColoresAlta.gris),
          ),
        const SizedBox(height: 16),
        if (preguntaPrecision) ...[
          FilledButton(
            key: ClavesAltaMapa.principal,
            // «Ajustar manualmente» deja el pin listo para arrastrar o tocar (41A·03).
            onPressed: _alta.decidirPrecision,
            style: _estiloPrincipal,
            child: const Text(TextosAlta.ajustarManualmente),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: ClavesAltaMapa.secundario,
            onPressed: () {
              if (_alta.continuarConBajaPrecision()) _acomodarArribaDeLaHoja();
            },
            style: _estiloSecundario,
            child: const Text(TextosAlta.continuar),
          ),
        ] else
          FilledButton(
            key: ClavesAltaMapa.principal,
            onPressed: () {
              if (_alta.confirmarPosicion()) _acomodarArribaDeLaHoja();
            },
            style: _estiloPrincipal,
            child: const Text(TextosAltaMapa.confirmarPosicion),
          ),
      ],
    );
  }

  /// 41A·02: sin GPS (o con el permiso denegado) y sin punto todavía. La hoja queda baja para dejar
  /// el mapa libre; al tocar el mapa cae el pin y sigue N·01.
  Widget _construirSinPunto(AltaUbicacionState estado) {
    final buscando = estado.gps == EstadoGps.buscando;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Encabezado(titulo: TextosAltaMapa.casaNueva, alCerrar: _cerrar),
        const SizedBox(height: 10),
        if (buscando)
          const Text(
            TextosAlta.buscandoGps,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: ColoresAlta.gris),
          )
        else ...[
          AvisoAlta(
            color: ColoresAlta.ambarBorde,
            colorInsignia: ColoresAlta.ambar,
            glyph: '!',
            texto: TextosAlta.sinGpsAviso,
            acciones: Align(
              alignment: Alignment.centerLeft,
              child: EnlaceAlta(
                texto: TextosAlta.activarGps,
                alPresionar: () => unawaited(_alta.activarGps()),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            TextosAlta.marcaElPunto,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: ColoresAlta.gris),
          ),
        ],
        const SizedBox(height: 16),
        const FilledButton(
          key: ClavesAltaMapa.principal,
          onPressed: null,
          style: _estiloPrincipal,
          child: Text(TextosAlta.registrar),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- N·02 (41A·04 a 41A·06)

  Widget _construirQueHayAca(AltaUbicacionState estado) {
    final ciudad = estado.ciudad;
    final propuesta = estado.propuesta;
    final numeroDelMapa = propuesta?.numero?.trim();
    final avisaNumero =
        estado.numero.fuente == FuenteCampo.editado &&
        numeroDelMapa != null &&
        numeroDelMapa.isNotEmpty &&
        numeroDelMapa != estado.numero.texto.trim();
    final avisoCiudad = switch (estado.origenCiudad) {
      OrigenCiudad.sinCiudades || OrigenCiudad.noSePudoLeer => AvisoAlta(
        color: ColoresAlta.ambarBorde,
        colorInsignia: ColoresAlta.ambar,
        glyph: '!',
        texto: estado.origenCiudad == OrigenCiudad.sinCiudades
            ? TextosAlta.sinCiudades
            : TextosAlta.ciudadesNoLeidas,
        acciones: Align(
          alignment: Alignment.centerLeft,
          child: EnlaceAlta(
            texto: TextosAlta.reintentar,
            alPresionar: estado.guardando ? null : () => unawaited(_alta.reintentarCiudad()),
          ),
        ),
      ),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Encabezado(
          titulo: TextosAltaMapa.queHayAca,
          subtitulo: [?_direccion(estado), ?ciudad?.nombre].join(' · '),
        ),
        const SizedBox(height: 14),
        SelectorTipoUbicacion(
          tipo: estado.tipo,
          conDescripcion: true,
          alElegir: estado.guardando ? (_) {} : _alta.elegirTipo,
        ),
        const SizedBox(height: 14),
        _CampoCiudad(estado: estado, alTocar: estado.guardando ? null : _alta.abrirCiudades),
        if (avisoCiudad != null) ...[const SizedBox(height: 8), avisoCiudad],
        const SizedBox(height: 14),
        CampoDireccionUbicacion(
          etiqueta: TextosAlta.calle,
          sugerencia: '',
          campo: estado.calle,
          controlador: _calle,
          alCambiar: _alta.editarCalle,
          limite: 120,
          accion: TextInputAction.next,
          bloqueado: estado.guardando,
          claveCampo: ClavesAltaMapa.calle,
        ),
        if (estado.calleActualizada && estado.calle.fuente == FuenteCampo.delMapa) ...[
          const SizedBox(height: 4),
          const InsigniaCampo(
            icono: Icons.check,
            texto: TextosAltaMapa.calleActualizada,
            fondo: ColoresAlta.verdeFondo,
            color: ColoresAlta.verde,
          ),
        ],
        const SizedBox(height: 14),
        CampoDireccionUbicacion(
          etiqueta: TextosAlta.numero,
          sugerencia: '',
          campo: estado.numero,
          controlador: _numero,
          alCambiar: _alta.editarNumero,
          limite: 20,
          accion: TextInputAction.done,
          bloqueado: estado.guardando,
          claveCampo: ClavesAltaMapa.numero,
        ),
        if (avisaNumero) ...[
          const SizedBox(height: 4),
          Text(
            TextosAltaMapa.loEscribisteVos(numeroDelMapa),
            style: const TextStyle(fontSize: 12, color: ColoresAlta.gris),
          ),
        ],
        if (estado.falla != null) ...[
          const SizedBox(height: 12),
          AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: mensajeFallaAlta(estado.falla!)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: ClavesAltaMapa.principal,
          onPressed: estado.puedeRegistrar ? () => unawaited(_registrar()) : null,
          style: _estiloPrincipal,
          child: Text(estado.guardando ? TextosAlta.registrando : TextosAlta.registrar),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: ClavesAltaMapa.secundario,
          onPressed: estado.guardando ? null : _alta.atras,
          style: _estiloTexto,
          child: const Text(TextosAltaMapa.volver),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 41B

  Widget _construirDuplicado(AltaUbicacionState estado) {
    final candidatas = estado.candidatas;
    if (candidatas.isEmpty) return const SizedBox.shrink();
    final ahora = ref.read(relojAltaUbicacionProvider)();
    String? ciudadDe(CandidataDuplicado c) =>
        c.ubicacion.ciudadId == estado.ciudad?.id ? estado.ciudad?.nombre : null;

    // 41B·04: la misma dirección a menos de 100 m (D1): solo «Abrir la existente».
    if (!estado.admiteCrearIgual) {
      final existente = candidatas.firstWhere(
        (c) => !c.admiteConservarAmbos,
        orElse: () => candidatas.first,
      );
      final direccion = FormatoUbicaciones.direccion(existente.ubicacion);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Encabezado(
            titulo: TextosAltaMapa.yaRegistraste(direccion),
            subtitulo: TextosAltaMapa.unaSolaVez(
              FormatoUbicaciones.distancia(existente.distanciaMetros),
            ),
            regionViva: true,
          ),
          const SizedBox(height: 12),
          TarjetaCandidataDuplicado(
            key: ClavesAltaMapa.candidata(existente.ubicacion.id),
            candidata: existente,
            letra: null,
            ciudad: ciudadDe(existente),
            ahora: ahora,
            etiquetaBoton: TextosDuplicado.abrirExistente,
            principal: true,
            alReutilizar: null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: ClavesAltaMapa.principal,
            onPressed: () => _cerrar(UbicacionReutilizada(existente.ubicacion.id)),
            style: _estiloPrincipal,
            child: const Text(TextosDuplicado.abrirExistente),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: ClavesAltaMapa.secundario,
            onPressed: _alta.atras,
            style: _estiloTexto,
            child: const Text(TextosAltaMapa.cancelar),
          ),
        ],
      );
    }

    final varias = candidatas.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Encabezado(
          titulo: TextosDuplicado.titulo(candidatas),
          subtitulo: TextosDuplicado.subtitulo(candidatas),
          regionViva: true,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < candidatas.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _FilaCandidata(
            resaltada: varias && estado.resaltada == candidatas[i].ubicacion.id,
            // Tocar una fila resalta su marcador en el mapa, sin moverlo (41B·02).
            alTocar: varias ? () => _alta.resaltar(candidatas[i].ubicacion.id) : null,
            child: TarjetaCandidataDuplicado(
              key: ClavesAltaMapa.candidata(candidatas[i].ubicacion.id),
              candidata: candidatas[i],
              letra: varias ? FormatoUbicaciones.rotuloCandidata(i) : null,
              ciudad: ciudadDe(candidatas[i]),
              ahora: ahora,
              etiquetaBoton: TextosDuplicado.reutilizar,
              principal: false,
              alReutilizar: varias
                  ? () => _cerrar(UbicacionReutilizada(candidatas[i].ubicacion.id))
                  : null,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (!varias) ...[
          FilledButton(
            key: ClavesAltaMapa.principal,
            onPressed: () => _cerrar(UbicacionReutilizada(candidatas.first.ubicacion.id)),
            style: _estiloPrincipal,
            child: const Text(TextosDuplicado.reutilizar),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton(
          key: ClavesAltaMapa.crearIgual,
          onPressed: _alta.irACrearIgual,
          style: _estiloSecundario,
          child: const Text(TextosAltaMapa.crearIgual),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: ClavesAltaMapa.secundario,
          onPressed: _alta.atras,
          style: _estiloTexto,
          child: const Text(TextosAltaMapa.cancelar),
        ),
      ],
    );
  }

  /// 41B·03: «Crear igual» con la justificación. Lo escrito se conserva al volver y reentrar.
  Widget _construirCrearIgual(AltaUbicacionState estado) {
    final candidatas = estado.candidatas;
    if (candidatas.isEmpty) return const SizedBox.shrink();
    final cercana = candidatas.first;
    final valida = _justificacion.text.trim().length >= TextosDuplicado.minimoJustificacion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Encabezado(
          titulo: TextosAltaMapa.crearIgual,
          subtitulo: TextosAltaMapa.crearIgualTexto(
            FormatoUbicaciones.direccion(cercana.ubicacion),
            FormatoUbicaciones.distancia(cercana.distanciaMetros),
          ),
        ),
        const SizedBox(height: 14),
        const EtiquetaCampoUbicacion(TextosDuplicado.justificacion),
        const SizedBox(height: 6),
        TextField(
          key: ClavesAltaMapa.justificacion,
          controller: _justificacion,
          readOnly: estado.guardando,
          onChanged: (_) => setState(() {}),
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(TextosDuplicado.maximoJustificacion)],
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          TextosDuplicado.quedaEnTuTelefono,
          style: TextStyle(fontSize: 12.5, color: ColoresAlta.gris),
        ),
        if (estado.falla != null) ...[
          const SizedBox(height: 12),
          AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: mensajeFallaAlta(estado.falla!)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: ClavesAltaMapa.principal,
          onPressed: valida && !estado.guardando
              ? () => unawaited(_registrar(justificacion: _justificacion.text.trim()))
              : null,
          style: _estiloPrincipal,
          child: Text(estado.guardando ? TextosAlta.registrando : TextosAltaMapa.crearIgual),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: ClavesAltaMapa.secundario,
          onPressed: estado.guardando ? null : _alta.atras,
          style: _estiloTexto,
          child: const Text(TextosAltaMapa.volver),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- textos

  /// «Grecia 3307»: la calle y el número del alta (del mapa o escritos), o `null` sin ninguno.
  static String? _direccion(AltaUbicacionState estado) {
    final texto = [
      estado.calle.texto.trim(),
      estado.numero.texto.trim(),
    ].where((t) => t.isNotEmpty).join(' ');
    return texto.isEmpty ? null : texto;
  }

  /// «◎ Del mapa · Montevideo»: de dónde salió la dirección y la ciudad.
  static String _subtituloPosicion(AltaUbicacionState estado) {
    final fuentes = {estado.calle.fuente, estado.numero.fuente};
    final origen = fuentes.contains(FuenteCampo.editado)
        ? '✎ ${TextosAltaMapa.editado}'
        : fuentes.contains(FuenteCampo.delMapa)
        ? '◎ ${TextosAltaMapa.delMapa}'
        : null;
    final ciudad = switch (estado.origenCiudad) {
      OrigenCiudad.buscando => TextosAlta.buscandoCiudad,
      _ => estado.ciudad?.nombre,
    };
    return [?origen, ?ciudad].join(' · ');
  }
}

const _estiloPrincipal = ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(52)));
const _estiloSecundario = ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)));
const _estiloTexto = ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)));

/// La hoja blanca de abajo. Sube con el teclado y se desplaza por dentro (41A·06): el mapa no se
/// recentra. Nunca pasa del 88 % de la pantalla.
class _Hoja extends StatelessWidget {
  const _Hoja({required this.clave, required this.child});

  final GlobalKey clave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final medidas = MediaQuery.of(context);
    final teclado = medidas.viewInsets.bottom;
    final alto = math.max(0.0, (medidas.size.height - teclado - medidas.padding.top) * 0.88);
    return Padding(
      padding: EdgeInsets.only(bottom: teclado),
      child: ConstrainedBox(
        key: clave,
        constraints: BoxConstraints(maxHeight: alto),
        child: Material(
          key: ClavesAltaMapa.hoja,
          color: Colors.white,
          elevation: 8,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: ColoresAlta.grisBorde,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El título de la hoja (encabezado para el lector), el subtítulo y, en N·01, la ✕ para salir.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.titulo, this.subtitulo, this.alCerrar, this.regionViva = false});

  final String titulo;
  final String? subtitulo;
  final VoidCallback? alCerrar;

  /// El título se anuncia al aparecer (el aviso de duplicado llega sin que la colportora lo pida).
  final bool regionViva;

  @override
  Widget build(BuildContext context) {
    final sub = subtitulo;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                liveRegion: regionViva,
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontFamily: 'SourceSerif4',
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              if (sub != null && sub.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(sub, style: const TextStyle(fontSize: 13.5, color: ColoresAlta.tinta)),
              ],
            ],
          ),
        ),
        if (alCerrar != null)
          IconButton(
            key: ClavesAltaMapa.cerrar,
            tooltip: TextosAlta.cerrar,
            onPressed: alCerrar,
            icon: const Icon(Icons.close),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
      ],
    );
  }
}

/// El chip de arriba a la izquierda: la precisión del GPS (41A·01 y 41A·03), «Sin GPS» (41A·02) o
/// «Buscando GPS…».
class _ChipGps extends StatelessWidget {
  const _ChipGps({required this.estado});

  final AltaUbicacionState estado;

  @override
  Widget build(BuildContext context) {
    final lectura = estado.lectura;
    final (texto, fondo, color, borde) = switch (estado.gps) {
      EstadoGps.conLectura when lectura != null =>
        PuntoCapturado.gps(lectura).esImpreciso
            ? (
                '! ${TextosAltaMapa.gps(lectura.precisionMetros)}',
                const Color(0xFFFBF1DA),
                const Color(0xFF6E5212),
                ColoresAlta.ambarBorde,
              )
            : (
                '◎ ${TextosAltaMapa.gps(lectura.precisionMetros)}',
                const Color(0xFFDDE8D3),
                ColoresAlta.verde,
                ColoresAlta.verde,
              ),
      EstadoGps.sinGps || EstadoGps.conLectura => (
        '✕ ${TextosAltaMapa.sinGps}',
        Colors.white,
        ColoresAlta.rojo,
        ColoresAlta.rojo,
      ),
      EstadoGps.buscando => (
        TextosAlta.buscandoGps,
        Colors.white,
        ColoresAlta.tinta,
        ColoresAlta.grisBorde,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        key: ClavesAltaMapa.chipGps,
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: borde, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0x290E1A2B), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Text(
          texto,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
        ),
      ),
    );
  }
}

/// «Tocá donde está el lugar» (41A·02): sin punto todavía.
class _ChipTocaElMapa extends StatelessWidget {
  const _ChipTocaElMapa();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        key: ClavesAltaMapa.tocaElMapa,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1A2B),
          borderRadius: BorderRadius.circular(99),
        ),
        child: const Text(
          TextosAlta.tocar,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// El campo «Ciudad» de N·02: el nombre y de dónde salió («◎ Del mapa», «De tu zona», «De tu
/// campaña» o «✎ Editado»). Tocarlo abre «Elegí la ciudad» (41A·04B).
class _CampoCiudad extends StatelessWidget {
  const _CampoCiudad({required this.estado, required this.alTocar});

  final AltaUbicacionState estado;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final ciudad = estado.ciudad;
    final origen = switch (estado.origenCiudad) {
      OrigenCiudad.detectada => '◎ ${TextosAltaMapa.delMapa}',
      OrigenCiudad.deZona => TextosAltaMapa.deTuZona,
      OrigenCiudad.deCampania => TextosAltaMapa.deTuCampania,
      OrigenCiudad.elegida => '✎ ${TextosAltaMapa.editado}',
      _ => null,
    };
    final nombre =
        ciudad?.nombre ??
        (estado.origenCiudad == OrigenCiudad.buscando
            ? TextosAlta.buscandoCiudad
            : TextosAlta.elegiLaCiudad);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EtiquetaCampoUbicacion(TextosAltaMapa.ciudad),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: [TextosAltaMapa.ciudad, nombre, ?origen].join(', '),
          excludeSemantics: true,
          onTap: alTocar,
          child: Material(
            key: ClavesAltaMapa.ciudad,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: estado.origenCiudad == OrigenCiudad.elegida
                    ? ColoresAlta.azul
                    : ColoresAlta.grisBorde,
                width: 1.5,
              ),
            ),
            child: InkWell(
              onTap: alTocar,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                      if (origen != null)
                        Text(
                          '$origen  ›',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ColoresAlta.azul,
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

/// Una fila de candidata que se puede tocar para resaltar su marcador (41B·02).
class _FilaCandidata extends StatelessWidget {
  const _FilaCandidata({required this.resaltada, required this.alTocar, required this.child});

  final bool resaltada;
  final VoidCallback? alTocar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (alTocar == null) return child;
    return Semantics(
      selected: resaltada,
      child: Material(
        color: resaltada ? ColoresAlta.azulFondo : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(onTap: alTocar, borderRadius: BorderRadius.circular(14), child: child),
      ),
    );
  }
}

/// «Elegí la ciudad» (41A·04B): las ciudades de la campaña, con un buscador. La de la propuesta
/// dice «Del mapa», la de su zona «De tu zona» y las demás «De tu campaña». Elegir otra no mueve el
/// mapa ni el pin: vuelve a N·02 con la ciudad elegida.
class _HojaCiudades extends ConsumerStatefulWidget {
  const _HojaCiudades({
    required this.parametros,
    required this.estado,
    required this.alElegir,
    required this.alVolver,
  });

  final ParametrosAlta parametros;
  final AltaUbicacionState estado;
  final ValueChanged<CiudadCatalogo> alElegir;
  final VoidCallback alVolver;

  @override
  ConsumerState<_HojaCiudades> createState() => _HojaCiudadesState();
}

class _HojaCiudadesState extends ConsumerState<_HojaCiudades> {
  final _buscar = TextEditingController();
  late Future<_Ciudades> _ciudades = _leer();
  late CiudadCatalogo? _elegida = widget.estado.ciudad;

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<_Ciudades> _leer() async {
    final puerto = ref.read(ciudadesParaAltaProvider);
    final colportorId = widget.parametros.colportorId;
    try {
      final lista = await puerto.deMiCampania(colportorId);
      // La de su zona: la que se propone sin punto (si la propuesta la saca de la zona).
      String? deZona;
      try {
        final propuesta = await puerto.proponer(colportorId: colportorId);
        deZona = propuesta.fold(
          (_) => null,
          (p) => p is CiudadPropuesta && p.origen == OrigenPropuesta.deZona ? p.ciudad.id : null,
        );
      } on Object {
        deZona = null;
      }
      return lista.fold(
        (_) => const _Ciudades.noSePudieronLeer(),
        (ciudades) => _Ciudades(ciudades, deZona: deZona),
      );
    } on Object {
      return const _Ciudades.noSePudieronLeer();
    }
  }

  String _normalizar(String texto) {
    const con = 'áéíóúüñ';
    const sin = 'aeiouun';
    final minusculas = texto.toLowerCase().trim();
    final salida = StringBuffer();
    for (final letra in minusculas.split('')) {
      final i = con.indexOf(letra);
      salida.write(i < 0 ? letra : sin[i]);
    }
    return salida.toString();
  }

  String _origen(CiudadCatalogo ciudad, String? deZona) {
    final propuesta = widget.estado;
    if (propuesta.origenCiudad == OrigenCiudad.detectada && propuesta.ciudad?.id == ciudad.id) {
      return TextosAltaMapa.delMapa;
    }
    if (ciudad.id == deZona) return TextosAltaMapa.deTuZona;
    return TextosAltaMapa.deTuCampania;
  }

  void _usar() {
    final elegida = _elegida;
    if (elegida == null) return;
    // La misma que ya tenía: vuelve sin marcarla «Editado».
    if (elegida.id == widget.estado.ciudad?.id) {
      widget.alVolver();
      return;
    }
    widget.alElegir(elegida);
  }

  @override
  Widget build(BuildContext context) {
    final elegida = _elegida;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Encabezado(titulo: TextosAltaMapa.elegiLaCiudad),
        const SizedBox(height: 12),
        TextField(
          key: ClavesAltaMapa.buscarCiudad,
          controller: _buscar,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: TextosAltaMapa.buscarCiudad,
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            constraints: const BoxConstraints(minHeight: 48),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<_Ciudades>(
          future: _ciudades,
          builder: (context, foto) {
            final datos = foto.data;
            if (datos == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Semantics(
                  liveRegion: true,
                  child: const Column(
                    children: [
                      ExcludeSemantics(child: CircularProgressIndicator()),
                      SizedBox(height: 10),
                      Text(
                        TextosAltaMapa.buscandoCiudades,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.5, color: ColoresAlta.gris),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (datos.fallo) {
              return AvisoAlta(
                color: ColoresAlta.ambarBorde,
                colorInsignia: ColoresAlta.ambar,
                glyph: '!',
                texto: TextosAlta.ciudadesNoLeidas,
                acciones: Align(
                  alignment: Alignment.centerLeft,
                  child: EnlaceAlta(
                    texto: TextosAlta.reintentar,
                    alPresionar: () => setState(() => _ciudades = _leer()),
                  ),
                ),
              );
            }
            if (datos.ciudades.isEmpty) {
              return const AvisoAlta(
                color: ColoresAlta.ambarBorde,
                colorInsignia: ColoresAlta.ambar,
                glyph: '!',
                texto: TextosAlta.sinCiudades,
              );
            }
            final filtro = _normalizar(_buscar.text);
            final visibles = [
              for (final c in datos.ciudades)
                if (filtro.isEmpty || _normalizar(c.nombre).contains(filtro)) c,
            ];
            if (visibles.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  TextosAltaMapa.sinResultados,
                  style: TextStyle(fontSize: 13.5, color: ColoresAlta.gris),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in visibles)
                  _OpcionCiudad(
                    key: ClavesAltaMapa.opcionCiudad(c.id),
                    nombre: c.nombre,
                    origen: _origen(c, datos.deZona),
                    elegida: c.id == elegida?.id,
                    alTocar: () => setState(() => _elegida = c),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: ClavesAltaMapa.principal,
          onPressed: elegida == null ? null : _usar,
          style: _estiloPrincipal,
          child: Text(
            elegida == null ? TextosAltaMapa.elegiLaCiudad : TextosAltaMapa.usar(elegida.nombre),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: ClavesAltaMapa.secundario,
          onPressed: widget.alVolver,
          style: _estiloTexto,
          child: const Text(TextosAltaMapa.volver),
        ),
      ],
    );
  }
}

/// Las ciudades de la campaña y la de su zona.
final class _Ciudades {
  const _Ciudades(this.ciudades, {this.deZona}) : fallo = false;

  const _Ciudades.noSePudieronLeer() : ciudades = const [], deZona = null, fallo = true;

  final List<CiudadCatalogo> ciudades;
  final String? deZona;
  final bool fallo;
}

class _OpcionCiudad extends StatelessWidget {
  const _OpcionCiudad({
    super.key,
    required this.nombre,
    required this.origen,
    required this.elegida,
    required this.alTocar,
  });

  final String nombre;
  final String origen;
  final bool elegida;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: elegida,
      inMutuallyExclusiveGroup: true,
      button: true,
      label: '$nombre, $origen',
      excludeSemantics: true,
      onTap: alTocar,
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Icon(
                  elegida ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: elegida ? Theme.of(context).colorScheme.primary : ColoresAlta.gris,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      Text(origen, style: const TextStyle(fontSize: 12.5, color: ColoresAlta.gris)),
                    ],
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
