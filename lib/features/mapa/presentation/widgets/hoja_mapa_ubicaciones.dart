import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/services/armador_agendados.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../formato_agendados.dart';
import '../formato_mapa_ubicaciones.dart';
import '../mapa_base/modelo_mapa_base.dart' show ColoresMapa;
import '../providers/hoja_agendados_provider.dart';
import '../providers/mapa_ubicaciones_state.dart';
import 'estados_hoja_casa.dart' show ElegirUbicacionDelPunto;
import 'hoja_agendados.dart';
import 'hoja_casa.dart';
import 'piezas_alta.dart' show AvisoAlta, ColoresAlta, EnlaceAlta;
import 'piezas_lista_ubicaciones.dart';
import 'piezas_mapa_ubicaciones.dart';

/// Las tres alturas de la hoja del mapa (canvas, «Tres alturas de la hoja»): minimizada (solo la
/// pestaña), a un tercio de la pantalla (tres o cuatro filas, o la vista previa) y a la mitad.
enum AlturaHoja {
  minimizada,
  tercio,
  mitad;

  /// El alto de la asa: la franja que se toca o se arrastra para cambiar la altura (48 dp de
  /// objetivo táctil).
  static const altoAsa = 48.0;

  /// La altura que sigue al tocar el asa: de la más baja a la más alta y vuelta a empezar.
  AlturaHoja get siguiente => values[(index + 1) % values.length];

  /// Una altura más arriba (la misma si ya es la más alta).
  AlturaHoja get mas => index == values.length - 1 ? this : values[index + 1];

  /// Una altura más abajo (la misma si ya es la más baja).
  AlturaHoja get menos => index == 0 ? this : values[index - 1];

  /// Lo que dice el lector de pantalla de la altura actual.
  String get descripcion => switch (this) {
    AlturaHoja.minimizada => TextosMapaUbicaciones.alturaMinimizada,
    AlturaHoja.tercio => TextosMapaUbicaciones.alturaTercio,
    AlturaHoja.mitad => TextosMapaUbicaciones.alturaMitad,
  };

  /// El alto de la hoja minimizada: el asa y las pestañas (canvas: 104 dp; el asa mide 48 dp para ser
  /// un objetivo táctil, así que son 108). Con el texto muy grande las pestañas crecen y la hoja con
  /// ellas; en una hoja de [ancho] dp donde «Cercanía» y «Agendados» no entran lado a lado, van una
  /// debajo de la otra ([MedidaPestanas.enUnaFila]).
  static double altoMinimizada(TextScaler escala, {double? ancho}) {
    final filas = ancho == null || MedidaPestanas.enUnaFila(escala, ancho) ? 1 : 2;
    return altoAsa + 6 + filas * MedidaPestanas.alto(escala) + 6;
  }

  /// El alto de esta altura en una pantalla de [pantalla] dp de alto, con [disponible] dp para el
  /// mapa y la hoja (la hoja nunca tapa más del 70 % de eso: el mapa sigue a la vista).
  ///
  /// [reserva] son los dp que tienen que quedar libres sobre la hoja para lo que flota encima (los
  /// botones y «Referencias»): en un teléfono chico la hoja a 1/2 los pisaría, así que se achica
  /// hasta dejarlos a la vista. Sin [reserva] solo manda el 70 %.
  double alto({
    required double pantalla,
    required double disponible,
    required TextScaler escala,
    double reserva = 0,
    double? ancho,
  }) {
    final minimo = altoMinimizada(escala, ancho: ancho);
    final base = switch (this) {
      AlturaHoja.minimizada => minimo,
      AlturaHoja.tercio => pantalla / 3,
      AlturaHoja.mitad => pantalla / 2,
    };
    final tope = math.max(minimo, math.min(disponible * 0.7, disponible - reserva));
    return math.min(math.max(base, minimo), tope);
  }
}

/// La medida de las pestañas «Cercanía» y «Agendados» de la hoja.
abstract final class MedidaPestanas {
  /// El alto de una pestaña: 48 dp de objetivo táctil, o lo que pida el texto grande.
  static double alto(TextScaler escala) => math.max(48.0, escala.scale(14.5) * 1.4 + 12);

  /// ¿Entran las dos pestañas lado a lado en una hoja de [ancho] dp? Se estima con la más larga
  /// («▦ Agendados 99», letras de ~0,58 em de Inter semibold) contra la mitad del ancho; si no
  /// entran, van una debajo de la otra para no recortar el texto (AA, texto al 200 %).
  static bool enUnaFila(TextScaler escala, double ancho) {
    final necesita =
        escala.scale(15) + // el glifo
        8 +
        escala.scale(14.5) * 0.58 * TextosAgendados.agendados.length +
        8 +
        escala.scale(12) * 0.62 * 2 + // la cuenta
        12; // el relleno de la pestaña
    return necesita <= (ancho - 40 - 6) / 2;
  }
}

/// La hoja del mapa de ubicaciones (vista 06): las pestañas «Cercanía N» y «Agendados N» y, debajo,
/// la lista de las ubicaciones de la más cercana a la más lejana o las visitas agendadas (06C·03,
/// [ContenidoAgendados]), o la hoja de la casa que se tocó (vista 39, C·01).
/// Si el toque cayó sobre varias ubicaciones que ni el zoom máximo separa, primero se elige cuál
/// (vista 39, E·06). Se arrastra
/// entre las tres [AlturaHoja]; tocar el asa también la cambia (para quien no puede arrastrar).
class HojaMapaUbicaciones extends StatefulWidget {
  const HojaMapaUbicaciones({
    super.key,
    required this.estado,
    required this.altura,
    required this.alturaDisponible,
    this.reservaLibre = 0,
    required this.ahora,
    required this.alCambiarAltura,
    required this.alElegir,
    required this.alCerrarVistaPrevia,
    required this.alElegirDelPunto,
    required this.alReintentar,
    required this.alActivarGps,
    required this.alRegistrar,
    this.colportorId,
    this.hojaDelMapa = const HojaDelMapaState(),
    this.agendados = const AsyncLoading<VistaAgendados>(),
    this.alElegirPestana,
    this.alElegirTipoAgendados,
    this.alReintentarAgendados,
  });

  final MapaUbicacionesState estado;
  final AlturaHoja altura;

  /// Lo que mide la zona del mapa (la hoja ocupa hasta el 70 % de eso).
  final double alturaDisponible;

  /// Lo que tiene que quedar libre sobre la hoja ([AlturaHoja.alto]).
  final double reservaLibre;
  final DateTime ahora;
  final ValueChanged<AlturaHoja> alCambiarAltura;

  /// Una fila de la lista: se elige la ubicación (vista previa y mapa centrado en ella).
  final ValueChanged<String> alElegir;
  final VoidCallback alCerrarVistaPrevia;

  /// Una fila de «Elegí cuál» (E·06): se abre la hoja de esa ubicación.
  final ValueChanged<String> alElegirDelPunto;
  final VoidCallback alReintentar;
  final VoidCallback alActivarGps;
  final VoidCallback alRegistrar;

  /// El colportor con la sesión iniciada: sin él la hoja de la casa no ofrece «+ Agregar persona».
  final String? colportorId;

  /// La pestaña elegida y el chip de tipo de «Agendados».
  final HojaDelMapaState hojaDelMapa;

  /// Las visitas agendadas ya armadas (06C·03): cargando, el error de la lectura o la hoja.
  final AsyncValue<VistaAgendados> agendados;
  final ValueChanged<PestanaHojaMapa>? alElegirPestana;
  final ValueChanged<TipoAgenda?>? alElegirTipoAgendados;
  final VoidCallback? alReintentarAgendados;

  @override
  State<HojaMapaUbicaciones> createState() => _HojaMapaUbicacionesState();
}

class _HojaMapaUbicacionesState extends State<HojaMapaUbicaciones> {
  /// El alto mientras el dedo arrastra el asa; `null` si no se está arrastrando.
  double? _vivo;
  var _alturaAlEmpezar = AlturaHoja.minimizada;

  /// Una velocidad de arrastre desde la cual se pasa a la altura siguiente aunque el dedo no haya
  /// llegado a la mitad del camino.
  static const _velocidadDeLanzamiento = 700.0;

  double _altoDe(AlturaHoja altura) => altura.alto(
    pantalla: MediaQuery.sizeOf(context).height,
    disponible: widget.alturaDisponible,
    escala: MediaQuery.textScalerOf(context),
    reserva: widget.reservaLibre,
    ancho: MediaQuery.sizeOf(context).width,
  );

  void _alEmpezarArrastre(DragStartDetails detalle) {
    _alturaAlEmpezar = widget.altura;
    setState(() => _vivo = _altoDe(widget.altura));
  }

  void _alArrastrar(DragUpdateDetails detalle) {
    final actual = _vivo;
    if (actual == null) return;
    final minimo = _altoDe(AlturaHoja.minimizada);
    final maximo = _altoDe(AlturaHoja.mitad);
    setState(() => _vivo = (actual - detalle.delta.dy).clamp(minimo, maximo));
  }

  void _alSoltar(DragEndDetails detalle) {
    final vivo = _vivo;
    if (vivo == null) return;
    final velocidad = detalle.velocity.pixelsPerSecond.dy;
    final AlturaHoja destino;
    if (velocidad.abs() > _velocidadDeLanzamiento) {
      destino = velocidad < 0 ? _alturaAlEmpezar.mas : _alturaAlEmpezar.menos;
    } else {
      // La altura más cercana a donde quedó la hoja.
      destino = AlturaHoja.values.reduce(
        (a, b) => (_altoDe(a) - vivo).abs() <= (_altoDe(b) - vivo).abs() ? a : b,
      );
    }
    setState(() => _vivo = null);
    if (destino != widget.altura) widget.alCambiarAltura(destino);
  }

  void _alCancelarArrastre() {
    if (_vivo != null) setState(() => _vivo = null);
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    final altura = widget.altura;
    final seleccionada = estado.seleccionada;
    final candidatas = estado.candidatas;
    final conVistaPrevia =
        (seleccionada != null || candidatas.isNotEmpty) && altura != AlturaHoja.minimizada;
    final arrastrando = _vivo != null;

    return AnimatedContainer(
      key: ClavesMapaUbicaciones.hoja,
      duration: arrastrando ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: _vivo ?? _altoDe(altura),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x290E1A2B), blurRadius: 24, offset: Offset(0, -8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Asa(
            altura: altura,
            alCambiar: widget.alCambiarAltura,
            alEmpezar: _alEmpezarArrastre,
            alArrastrar: _alArrastrar,
            alSoltar: _alSoltar,
            alCancelar: _alCancelarArrastre,
          ),
          if (!conVistaPrevia)
            _Pestanas(
              estado: estado,
              elegida: widget.hojaDelMapa.pestana,
              agendados: widget.agendados,
              alElegir: widget.alElegirPestana,
            ),
          if (altura != AlturaHoja.minimizada)
            Expanded(
              child: conVistaPrevia
                  ? (seleccionada != null
                        ? HojaCasa(
                            // Otra casa es otra hoja: no hereda el botón ocupado ni el aviso de la anterior.
                            key: ValueKey('hoja_casa_${seleccionada.ubicacion.id}'),
                            item: seleccionada,
                            ahora: widget.ahora,
                            alCerrar: widget.alCerrarVistaPrevia,
                            // C·02: con la hoja a la mitad se ven las pestañas; más abajo, el resumen.
                            arriba: altura == AlturaHoja.mitad,
                            colportorId: widget.colportorId,
                            alAbrirOtra: widget.alElegir,
                          )
                        : _ElegirDelPunto(
                            candidatas: candidatas,
                            alElegir: widget.alElegirDelPunto,
                            alCerrar: widget.alCerrarVistaPrevia,
                          ))
                  : widget.hojaDelMapa.enAgendados
                  ? ContenidoAgendados(
                      agendados: widget.agendados,
                      tipo: widget.hojaDelMapa.tipo,
                      ahora: widget.ahora,
                      alElegirTipo: (tipo) => widget.alElegirTipoAgendados?.call(tipo),
                      alReintentar: () => widget.alReintentarAgendados?.call(),
                    )
                  : _Contenido(
                      estado: estado,
                      ahora: widget.ahora,
                      alElegir: widget.alElegir,
                      alReintentar: widget.alReintentar,
                      alActivarGps: widget.alActivarGps,
                      alRegistrar: widget.alRegistrar,
                    ),
            ),
        ],
      ),
    );
  }
}

/// El asa de arriba: la manija (canvas: 44 × 5), los tres puntos que dicen en qué altura está la
/// hoja y toda la franja como objetivo táctil de 48 dp.
class _Asa extends StatelessWidget {
  const _Asa({
    required this.altura,
    required this.alCambiar,
    required this.alEmpezar,
    required this.alArrastrar,
    required this.alSoltar,
    required this.alCancelar,
  });

  final AlturaHoja altura;
  final ValueChanged<AlturaHoja> alCambiar;
  final GestureDragStartCallback alEmpezar;
  final GestureDragUpdateCallback alArrastrar;
  final GestureDragEndCallback alSoltar;
  final VoidCallback alCancelar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: TextosMapaUbicaciones.cambiarAltura,
      value: altura.descripcion,
      // Flutter pide `increasedValue` y `decreasedValue` junto con `value` y las acciones de ajuste:
      // lo que el lector va a decir después de subir o bajar la hoja.
      increasedValue: altura.mas.descripcion,
      decreasedValue: altura.menos.descripcion,
      onTap: () => alCambiar(altura.siguiente),
      onIncrease: altura == AlturaHoja.mitad ? null : () => alCambiar(altura.mas),
      onDecrease: altura == AlturaHoja.minimizada ? null : () => alCambiar(altura.menos),
      child: ExcludeSemantics(
        child: GestureDetector(
          key: ClavesMapaUbicaciones.asa,
          behavior: HitTestBehavior.opaque,
          onTap: () => alCambiar(altura.siguiente),
          onVerticalDragStart: alEmpezar,
          onVerticalDragUpdate: alArrastrar,
          onVerticalDragEnd: alSoltar,
          onVerticalDragCancel: alCancelar,
          child: SizedBox(
            height: AlturaHoja.altoAsa,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: ColoresLista.chevron,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 18,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      for (final nivel in AlturaHoja.values)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: nivel.index <= altura.index ? ColoresMapa.aroSeleccion : null,
                            border: nivel.index <= altura.index
                                ? null
                                : Border.all(color: ColoresLista.chevron, width: 1.5),
                          ),
                        ),
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

/// Las pestañas «◎ Cercanía N» y «▦ Agendados N» (canvas 06C·01 y 06C·03): la elegida, en blanco
/// sobre el gris. Cada una es un botón de 48 dp que el lector de pantalla lee con su cuenta y si está
/// elegida.
class _Pestanas extends StatelessWidget {
  const _Pestanas({
    required this.estado,
    required this.elegida,
    required this.agendados,
    required this.alElegir,
  });

  final MapaUbicacionesState estado;
  final PestanaHojaMapa elegida;
  final AsyncValue<VistaAgendados> agendados;
  final ValueChanged<PestanaHojaMapa>? alElegir;

  @override
  Widget build(BuildContext context) {
    final lista = estado.lista;
    final alElegir = this.alElegir;
    // Con un error no se muestra una cuenta vieja: no se sabe si está al día.
    final cuentaAgendados = agendados.hasError ? null : agendados.value?.cuentas.todas;
    final escala = MediaQuery.textScalerOf(context);
    final alto = MedidaPestanas.alto(escala);
    final cercania = _Pestana(
      key: ClavesMapaUbicaciones.pestanaCercania,
      glifo: '◎',
      texto: TextosMapaUbicaciones.cercania,
      cuenta: lista?.total,
      cargando: estado.cargando,
      etiqueta: estado.cargando
          ? '${TextosMapaUbicaciones.cercania}. ${TextosMapaUbicaciones.cargando}'
          : FormatoMapaUbicaciones.cuentaCercania(lista?.total),
      alto: alto,
      elegida: elegida == PestanaHojaMapa.cercania,
      alPresionar: alElegir == null ? null : () => alElegir(PestanaHojaMapa.cercania),
    );
    final deAgendados = _Pestana(
      key: ClavesAgendados.pestana,
      glifo: '▦',
      texto: TextosAgendados.agendados,
      cuenta: cuentaAgendados,
      cargando: !agendados.hasError && !agendados.hasValue,
      etiqueta: FormatoAgendados.cuentaAgendados(cuentaAgendados),
      alto: alto,
      elegida: elegida == PestanaHojaMapa.agendados,
      alPresionar: alElegir == null ? null : () => alElegir(PestanaHojaMapa.agendados),
    );
    // Lado a lado como en el canvas; si no entran (texto grande, teléfono angosto), una debajo de la
    // otra: el alto de la hoja minimizada ya lo cuenta (`AlturaHoja.altoMinimizada`).
    final enUnaFila = MedidaPestanas.enUnaFila(escala, MediaQuery.sizeOf(context).width);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: ColoresLista.filaBaja,
          borderRadius: BorderRadius.circular(14),
        ),
        child: enUnaFila
            ? Row(
                children: [
                  Expanded(child: cercania),
                  Expanded(child: deAgendados),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [cercania, deAgendados],
              ),
      ),
    );
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({
    super.key,
    required this.glifo,
    required this.texto,
    required this.cuenta,
    required this.cargando,
    required this.etiqueta,
    required this.alto,
    required this.elegida,
    required this.alPresionar,
  });

  final String glifo;
  final String texto;
  final int? cuenta;
  final bool cargando;
  final String etiqueta;

  /// [MedidaPestanas.alto]: el mismo que cuenta la hoja minimizada.
  final double alto;
  final bool elegida;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    // La elegida en el azul de la selección; la otra en el gris de la lista (AA sobre el gris claro).
    final color = elegida ? ColoresMapa.aroSeleccion : ColoresLista.grisTexto;
    return Semantics(
      header: elegida,
      button: alPresionar != null,
      selected: elegida,
      container: true,
      label: etiqueta,
      onTap: alPresionar,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: alPresionar,
        child: Container(
          height: alto,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: elegida
              ? BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: const [
                    BoxShadow(color: Color(0x2E0E1A2B), blurRadius: 3, offset: Offset(0, 1)),
                  ],
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(glifo, style: TextStyle(fontSize: 15, color: color)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  texto,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (cuenta != null)
                Text(
                  '$cuenta',
                  style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, color: color),
                )
              else if (cargando)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo que va debajo de la pestaña cuando la hoja está a un tercio o a la mitad: cargando, el error,
/// el vacío o la lista de ubicaciones.
class _Contenido extends StatelessWidget {
  const _Contenido({
    required this.estado,
    required this.ahora,
    required this.alElegir,
    required this.alReintentar,
    required this.alActivarGps,
    required this.alRegistrar,
  });

  final MapaUbicacionesState estado;
  final DateTime ahora;
  final ValueChanged<String> alElegir;
  final VoidCallback alReintentar;
  final VoidCallback alActivarGps;
  final VoidCallback alRegistrar;

  @override
  Widget build(BuildContext context) {
    final lista = estado.lista;
    if (lista == null) {
      return estado.fallaLectura ? _VistaError(alReintentar: alReintentar) : const _VistaCargando();
    }
    if (lista.sinUbicaciones) {
      return _VistaVacia(soloBajas: lista.soloBajas, alRegistrar: alRegistrar);
    }
    final cabeceras = <Widget>[
      if (estado.fallaLectura) _BannerError(alReintentar: alReintentar),
      if (estado.gps == EstadoGpsLista.sinGps) _AvisoGps(alActivar: alActivarGps),
      if (estado.gps == EstadoGpsLista.buscando && estado.lectura == null) const _BuscandoGps(),
    ];
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: cabeceras.length + lista.items.length,
      itemBuilder: (context, indice) {
        if (indice < cabeceras.length) return cabeceras[indice];
        final item = lista.items[indice - cabeceras.length];
        final id = item.ubicacion.id;
        return FilaUbicacionLista(
          key: ClavesMapaUbicaciones.fila(id),
          item: item,
          lista: lista,
          ahora: ahora,
          alTocar: () => alElegir(id),
          conFlecha: false,
        );
      },
    );
  }
}

class _VistaCargando extends StatelessWidget {
  const _VistaCargando();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Column(
            key: ClavesMapaUbicaciones.cargando,
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              const ExcludeSemantics(child: CircularProgressIndicator(strokeWidth: 3)),
              Text(
                TextosMapaUbicaciones.cargando,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VistaError extends StatelessWidget {
  const _VistaError({required this.alReintentar});

  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Column(
            key: ClavesMapaUbicaciones.error,
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Text(
                TextosMapaUbicaciones.errorLectura,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              EnlaceAlta(
                key: ClavesMapaUbicaciones.reintentar,
                texto: TextosMapaUbicaciones.reintentar,
                alPresionar: alReintentar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El error de lectura cuando ya había una lista: se sigue viendo y arriba queda el aviso.
class _BannerError extends StatelessWidget {
  const _BannerError({required this.alReintentar});

  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ClavesMapaUbicaciones.error,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: AvisoAlta(
        color: ColoresAlta.rojo,
        glyph: '!',
        texto: TextosMapaUbicaciones.errorLectura,
        acciones: Align(
          alignment: Alignment.centerRight,
          child: EnlaceAlta(
            key: ClavesMapaUbicaciones.reintentar,
            texto: TextosMapaUbicaciones.reintentar,
            alPresionar: alReintentar,
          ),
        ),
      ),
    );
  }
}

class _VistaVacia extends StatelessWidget {
  const _VistaVacia({required this.soloBajas, required this.alRegistrar});

  final bool soloBajas;
  final VoidCallback alRegistrar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          key: ClavesMapaUbicaciones.vacio,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Semantics(
              header: true,
              child: Text(
                soloBajas
                    ? TextosMapaUbicaciones.soloBajasTitulo
                    : TextosMapaUbicaciones.vacioTitulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              soloBajas ? TextosMapaUbicaciones.soloBajasCuerpo : TextosMapaUbicaciones.vacioCuerpo,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ColoresColportaje.unica.gris,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            FilledButton(
              key: ClavesMapaUbicaciones.registrarPrimera,
              onPressed: alRegistrar,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                soloBajas
                    ? TextosMapaUbicaciones.registrarUna
                    : TextosMapaUbicaciones.registrarPrimera,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Sin GPS no podemos ordenarlas por cercanía.» con «Activar GPS».
class _AvisoGps extends StatelessWidget {
  const _AvisoGps({required this.alActivar});

  final VoidCallback alActivar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              TextosMapaUbicaciones.sinGps,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                color: ColoresColportaje.unica.gris,
              ),
            ),
          ),
          EnlaceAlta(
            key: ClavesMapaUbicaciones.activarGps,
            texto: TextosMapaUbicaciones.activarGps,
            alPresionar: alActivar,
          ),
        ],
      ),
    );
  }
}

class _BuscandoGps extends StatelessWidget {
  const _BuscandoGps();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Semantics(
        liveRegion: true,
        child: Text(
          TextosMapaUbicaciones.buscandoGps,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12.5,
            color: ColoresColportaje.unica.gris,
          ),
        ),
      ),
    );
  }
}

/// «3 ubicaciones acá» y «Elegí cuál» (vista 39, E·06) con la ✕ de la vista previa: cerrarla vuelve
/// a la lista. Las filas son de [ElegirUbicacionDelPunto]; tocar una abre su hoja.
class _ElegirDelPunto extends StatelessWidget {
  const _ElegirDelPunto({required this.candidatas, required this.alElegir, required this.alCerrar});

  final List<ItemListaUbicacion> candidatas;
  final ValueChanged<String> alElegir;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ClavesMapaUbicaciones.vistaPrevia,
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
              button: true,
              label: TextosMapaUbicaciones.cerrarVistaPrevia,
              onTap: alCerrar,
              child: ExcludeSemantics(
                child: InkResponse(
                  key: ClavesMapaUbicaciones.cerrarVistaPrevia,
                  onTap: alCerrar,
                  radius: 24,
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.close, size: 20, color: ColoresLista.grisTexto),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElegirUbicacionDelPunto(
                ubicaciones: candidatas,
                alElegir: (elegida) => alElegir(elegida.ubicacion.id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
