import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../formato_mapa_ubicaciones.dart';
import '../formato_ubicaciones.dart';
import '../mapa_base/modelo_mapa_base.dart' show ColoresMapa;
import '../providers/mapa_ubicaciones_state.dart';
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

  /// El alto de la hoja minimizada: el asa y la pestaña (canvas: 104 dp; el asa mide 48 dp para ser
  /// un objetivo táctil, así que son 108). Con el texto muy grande la pestaña crece y la hoja con ella.
  static double altoMinimizada(TextScaler escala) =>
      altoAsa + 6 + math.max(48.0, escala.scale(14.5) * 1.4 + 12) + 6;

  /// El alto de esta altura en una pantalla de [pantalla] dp de alto, con [disponible] dp para el
  /// mapa y la hoja (la hoja nunca tapa más del 70 % de eso: el mapa sigue a la vista).
  double alto({required double pantalla, required double disponible, required TextScaler escala}) {
    final minimo = altoMinimizada(escala);
    final base = switch (this) {
      AlturaHoja.minimizada => minimo,
      AlturaHoja.tercio => pantalla / 3,
      AlturaHoja.mitad => pantalla / 2,
    };
    return math.min(math.max(base, minimo), math.max(minimo, disponible * 0.7));
  }
}

/// La hoja del mapa de ubicaciones (vista 06): la pestaña «Cercanía N» y, debajo, la lista de las
/// ubicaciones de la más cercana a la más lejana, o la vista previa de la que se tocó. Se arrastra
/// entre las tres [AlturaHoja]; tocar el asa también la cambia (para quien no puede arrastrar).
class HojaMapaUbicaciones extends StatefulWidget {
  const HojaMapaUbicaciones({
    super.key,
    required this.estado,
    required this.altura,
    required this.alturaDisponible,
    required this.ahora,
    required this.alCambiarAltura,
    required this.alElegir,
    required this.alCerrarVistaPrevia,
    required this.alReintentar,
    required this.alActivarGps,
    required this.alRegistrar,
  });

  final MapaUbicacionesState estado;
  final AlturaHoja altura;

  /// Lo que mide la zona del mapa (la hoja ocupa hasta el 70 % de eso).
  final double alturaDisponible;
  final DateTime ahora;
  final ValueChanged<AlturaHoja> alCambiarAltura;

  /// Una fila de la lista: se elige la ubicación (vista previa y mapa centrado en ella).
  final ValueChanged<String> alElegir;
  final VoidCallback alCerrarVistaPrevia;
  final VoidCallback alReintentar;
  final VoidCallback alActivarGps;
  final VoidCallback alRegistrar;

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
    final conVistaPrevia = seleccionada != null && altura != AlturaHoja.minimizada;
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
          if (!conVistaPrevia) _PestanaCercania(estado: estado),
          if (altura != AlturaHoja.minimizada)
            Expanded(
              child: conVistaPrevia
                  ? VistaPreviaUbicacion(
                      item: seleccionada,
                      ahora: widget.ahora,
                      alCerrar: widget.alCerrarVistaPrevia,
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

/// La pestaña «Cercanía N» (canvas): la única de esta semana. «Agendados» llega con las visitas
/// (HU-VIS-001 y HU-VIS-002), así que por ahora no se ofrece.
class _PestanaCercania extends StatelessWidget {
  const _PestanaCercania({required this.estado});

  final MapaUbicacionesState estado;

  @override
  Widget build(BuildContext context) {
    final lista = estado.lista;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: ColoresLista.filaBaja,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Semantics(
          header: true,
          container: true,
          label: estado.cargando
              ? '${TextosMapaUbicaciones.cercania}. ${TextosMapaUbicaciones.cargando}'
              : FormatoMapaUbicaciones.cuentaCercania(lista?.total),
          excludeSemantics: true,
          child: Container(
            key: ClavesMapaUbicaciones.pestanaCercania,
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              boxShadow: const [
                BoxShadow(color: Color(0x2E0E1A2B), blurRadius: 3, offset: Offset(0, 1)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('◎', style: TextStyle(fontSize: 15, color: ColoresMapa.aroSeleccion)),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    TextosMapaUbicaciones.cercania,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: ColoresMapa.aroSeleccion,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (lista != null)
                  Text(
                    '${lista.total}',
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 12,
                      color: ColoresMapa.aroSeleccion,
                    ),
                  )
                else if (estado.cargando)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
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

/// La vista previa de la ubicación que se tocó (canvas, 06C·04): el rótulo («CASA · 2 ESPACIOS · A
/// 40 M»), la dirección y, si se conoce, el estado de la casa. Los botones («Registrar visita»,
/// «Agendar», «Detalle») llegan con sus pantallas: las visitas (HU-VIS-001 y HU-VIS-002) y el
/// detalle de la ubicación (#211).
class VistaPreviaUbicacion extends StatelessWidget {
  const VistaPreviaUbicacion({
    super.key,
    required this.item,
    required this.ahora,
    required this.alCerrar,
  });

  final ItemListaUbicacion item;
  final DateTime ahora;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    final estado = item.estado;
    return SingleChildScrollView(
      child: Semantics(
        container: true,
        liveRegion: true,
        label: TextosMapaUbicaciones.vistaPrevia,
        child: Padding(
          key: ClavesMapaUbicaciones.vistaPrevia,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      FormatoMapaUbicaciones.rotuloVistaPrevia(item),
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 10,
                        letterSpacing: 1.4,
                        color: Color(0xFF5B6B82),
                      ),
                    ),
                  ),
                  Semantics(
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
                ],
              ),
              Text(
                FormatoUbicaciones.direccion(item.ubicacion),
                style: const TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              if (estado != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: ColoresLista.azulFondo,
                    border: Border.all(color: ColoresLista.azul, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    spacing: 10,
                    children: [
                      InsigniaEstadoCasa(estado: estado, tamano: 26),
                      Expanded(
                        child: Text(
                          FormatoMapaUbicaciones.estadoVistaPrevia(
                            estado,
                            item.proximaEntrevista,
                            ahora,
                          ),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: ColoresMapa.aroSeleccion,
                          ),
                        ),
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
}
