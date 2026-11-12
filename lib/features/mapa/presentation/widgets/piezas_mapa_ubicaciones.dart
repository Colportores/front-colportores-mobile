import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/entities/estado_casa.dart';
import '../../domain/value_objects/modo_seguimiento.dart';
import '../formato_lista_ubicaciones.dart';
import '../formato_mapa_ubicaciones.dart';
import '../mapa_base/marcador_estado.dart' show MarcadorEstado, VarianteMarcador;
import '../mapa_base/modelo_mapa_base.dart' show ColoresMapa;
import '../providers/lista_ubicaciones_state.dart' show EstadoGpsLista;
import 'piezas_alta.dart' show ColoresAlta, PinAlta;
import 'piezas_lista_ubicaciones.dart';

/// Las claves con que los tests (y el QA) encuentran lo que dibuja el mapa de ubicaciones.
abstract final class ClavesMapaUbicaciones {
  static const miUbicacion = Key('mapa_mi_ubicacion');
  static const nueva = Key('mapa_nueva');
  static const referencias = Key('mapa_referencias');
  static const hoja = Key('mapa_hoja');
  static const asa = Key('mapa_asa');
  static const pestanaCercania = Key('mapa_pestana_cercania');
  static const vistaPrevia = Key('mapa_vista_previa');
  static const cerrarVistaPrevia = Key('mapa_vista_previa_cerrar');
  static const cargando = Key('mapa_cargando');
  static const vacio = Key('mapa_vacio');
  static const error = Key('mapa_error');
  static const reintentar = Key('mapa_reintentar');
  static const activarGps = Key('mapa_activar_gps');
  static const registrarPrimera = Key('mapa_registrar_primera');
  static const hojaReferencias = Key('mapa_hoja_referencias');
  static const cerrarReferencias = Key('mapa_referencias_cerrar');
  static const muestraEdificio = Key('mapa_referencias_edificio');
  static const muestraCuadrado = Key('mapa_referencias_cuadrado');

  /// El nombre del modo que aparece 2 s junto al botón de ubicación (41E·03).
  static const rotuloModo = Key('mapa_rotulo_modo');

  /// La brújula de arriba con el mapa girado (41E·03C).
  static const brujula = Key('mapa_brujula');

  /// El cono que sale del punto del GPS en «Seguir y girar» (41E·03C).
  static const cono = Key('mapa_cono_orientacion');

  /// La fila de la ubicación [id] en la hoja.
  static Key fila(String id) => Key('mapa_fila_$id');
}

/// El símbolo, los colores y el texto de cada modo de seguimiento del botón de ubicación (#670; con
/// el canvas 41E·03, 03B y 03C, #692). Un solo lugar: el botón, su rótulo y el anuncio al cambiar de
/// modo dicen lo mismo.
extension PresentacionModoSeguimiento on ModoSeguimiento {
  /// El nombre del modo: el rótulo que aparece 2 s al cambiar y lo que se anuncia.
  String get texto => switch (this) {
    ModoSeguimiento.libre => TextosMapaUbicaciones.seguimientoLibre,
    ModoSeguimiento.seguir => TextosMapaUbicaciones.seguimientoSeguir,
    ModoSeguimiento.seguirYGirar => TextosMapaUbicaciones.seguimientoSeguirYGirar,
  };

  /// El nombre accesible del botón en este modo (canvas: «Ubicación: Mapa libre»).
  String get nombreDelBoton => '${TextosMapaUbicaciones.ubicacion}: $texto';

  /// El botón va lleno (fondo azul y símbolo blanco) mientras el mapa sigue a la colportora: el modo
  /// se distingue por el símbolo y no solo por el color (41E·03B).
  bool get botonLleno => sigue;

  /// El fondo del botón (canvas: blanco en «Mapa libre», el azul `#002856` siguiendo).
  Color get fondoDelBoton => botonLleno ? ColoresMapa.aroSeleccion : Colors.white;

  /// El color del símbolo (canvas: el azul sobre blanco y el blanco sobre azul, 14:1 los dos).
  Color get tintaDelBoton => botonLleno ? Colors.white : ColoresMapa.aroSeleccion;
}

/// Las medidas del botón de ubicación y de lo que lo acompaña (canvas 41E·03).
abstract final class MedidasBotonUbicacion {
  /// El lado del botón y de la brújula: 48 dp (el objetivo de toque de las reglas comunes de la 41).
  static const lado = 48.0;

  /// El lado del símbolo dentro del botón (canvas: el glifo a 20 px).
  static const simbolo = 20.0;

  /// Lo que separa el rótulo del modo del botón.
  static const separacionRotulo = 10.0;

  /// Cuánto se ve el nombre del modo al cambiar (canvas 41E·03: «aparece 2 s al cambiar»).
  static const duracionRotulo = Duration(seconds: 2);
}

/// El borde gris de los controles redondos del mapa (canvas: `0 0 0 1px #E3E7EE`).
const _bordeControl = Color(0xFFE3E7EE);

/// El símbolo del [modo], dibujado (no un glifo de fuente, que en algunos Android no está): ◎ para
/// «Mapa libre», ◉ para «Seguir mi ubicación» y ▲ para «Seguir y girar con el teléfono» (41E·03,
/// 03B y 03C).
class SimboloModoSeguimiento extends StatelessWidget {
  const SimboloModoSeguimiento({
    super.key,
    required this.modo,
    required this.color,
    this.lado = MedidasBotonUbicacion.simbolo,
  });

  final ModoSeguimiento modo;
  final Color color;
  final double lado;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(lado),
    painter: PintorSimboloModo(modo: modo, color: color),
  );
}

/// Pinta el símbolo de un modo de seguimiento en un cuadrado.
class PintorSimboloModo extends CustomPainter {
  const PintorSimboloModo({required this.modo, required this.color});

  final ModoSeguimiento modo;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final lado = size.shortestSide;
    final trazo = lado * .09;
    final aro = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = trazo;
    final relleno = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final radio = lado / 2 - trazo / 2;
    switch (modo) {
      case ModoSeguimiento.libre:
        // ◎: dos aros, el mapa no sigue a nadie.
        canvas
          ..drawCircle(centro, radio, aro)
          ..drawCircle(centro, radio * .45, aro);
      case ModoSeguimiento.seguir:
        // ◉: el aro con el centro lleno.
        canvas
          ..drawCircle(centro, radio, aro)
          ..drawCircle(centro, radio * .5, relleno);
      case ModoSeguimiento.seguirYGirar:
        // ▲: el triángulo que apunta hacia donde mira el mapa.
        final ancho = lado * .84;
        final alto = lado * .76;
        final arriba = centro.dy - alto / 2;
        canvas.drawPath(
          Path()
            ..moveTo(centro.dx, arriba)
            ..lineTo(centro.dx + ancho / 2, arriba + alto)
            ..lineTo(centro.dx - ancho / 2, arriba + alto)
            ..close(),
          relleno,
        );
    }
  }

  @override
  bool shouldRepaint(PintorSimboloModo oldDelegate) =>
      oldDelegate.modo != modo || oldDelegate.color != color;
}

/// El botón de ubicación (vista 41, 41E·03, 03B y 03C): el botón redondo de 48 dp que pasa por los
/// tres modos —libre, seguir y seguir y girar— (#670). En «Mapa libre» es blanco con ◎; siguiendo,
/// se llena de azul con ◉ o ▲. Su nombre accesible es «Ubicación: `<modo>`».
/// Sin [alPresionar] está deshabilitado (HU-UBI-003, «Edge: sin GPS») y el lector de pantalla dice por
/// qué según el [gps]: mientras busca la primera lectura todavía no se sabe si hay GPS, así que no se
/// afirma que no lo hay (#359).
class BotonMiUbicacion extends StatelessWidget {
  const BotonMiUbicacion({
    super.key,
    required this.alPresionar,
    required this.gps,
    this.modo = ModoSeguimiento.libre,
  });

  final VoidCallback? alPresionar;
  final EstadoGpsLista gps;

  /// Cómo sigue el mapa a la colportora.
  final ModoSeguimiento modo;

  /// El motivo por el que el botón está apagado.
  String get _motivo => switch (gps) {
    EstadoGpsLista.sinPedir ||
    EstadoGpsLista.buscando => TextosMapaUbicaciones.miUbicacionBuscandoGps,
    EstadoGpsLista.conLectura || EstadoGpsLista.sinGps => TextosMapaUbicaciones.miUbicacionSinGps,
  };

  @override
  Widget build(BuildContext context) {
    final habilitado = alPresionar != null;
    // Apagado no sigue a nadie: blanco con el símbolo gris, como cualquier control apagado.
    final lleno = habilitado && modo.botonLleno;
    return Semantics(
      button: true,
      enabled: habilitado,
      // Apagado, el motivo va en la etiqueta, detrás del nombre, y no en la pista: con «Hablar pistas»
      // apagado en VoiceOver una pista no se leería (#359; igual que «Registrar» apagado, #345).
      label: habilitado ? modo.nombreDelBoton : '${TextosMapaUbicaciones.miUbicacion}. $_motivo',
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: Material(
          color: lleno ? modo.fondoDelBoton : Colors.white,
          elevation: 3,
          shape: CircleBorder(side: BorderSide(color: lleno ? modo.fondoDelBoton : _bordeControl)),
          child: InkResponse(
            customBorder: const CircleBorder(),
            onTap: alPresionar,
            child: SizedBox.square(
              dimension: MedidasBotonUbicacion.lado,
              child: Center(
                child: SimboloModoSeguimiento(
                  modo: modo,
                  color: habilitado ? modo.tintaDelBoton : ColoresLista.chevron,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El nombre del modo junto al botón de ubicación (41E·03, 03B y 03C): la píldora oscura que aparece
/// 2 s al cambiar de modo. Es solo para la vista: el lector de pantalla ya oye el anuncio y el nombre
/// del botón. No toma toques (el mapa de abajo sigue respondiendo). Con el texto grande se parte en
/// renglones en vez de salirse de la pantalla.
class RotuloModoSeguimiento extends StatelessWidget {
  const RotuloModoSeguimiento({super.key, required this.modo});

  final ModoSeguimiento modo;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ColoresMapa.tintaOscura,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(color: Color(0x400E1A2B), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  modo.texto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La brújula del mapa (41E·03C): el botón redondo blanco de 48 dp con la «N», arriba a la derecha,
/// que aparece con el mapa girado y lo vuelve al norte al tocarla.
class BrujulaMapa extends StatelessWidget {
  const BrujulaMapa({super.key, required this.alPresionar});

  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: TextosMapaUbicaciones.brujula,
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          elevation: 3,
          shape: const CircleBorder(side: BorderSide(color: _bordeControl)),
          child: InkResponse(
            customBorder: const CircleBorder(),
            onTap: alPresionar,
            child: const SizedBox.square(
              dimension: MedidasBotonUbicacion.lado,
              child: Center(
                // La «N» no crece con el texto: es un símbolo dentro de un botón de tamaño fijo, y
                // su nombre lo lee el lector de pantalla.
                child: Text(
                  TextosMapaUbicaciones.brujulaNorte,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: ColoresMapa.aroSeleccion,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El cono de orientación (41E·03C): el abanico azul que sale del punto del GPS hacia donde apunta el
/// teléfono. En «Seguir y girar» el mapa gira con el rumbo, así que el cono queda siempre hacia
/// arriba. Va centrado en [centro] (el punto del GPS en la vista del mapa) y no toma toques. Se pone
/// en un `Stack` que cubra el mapa.
class ConoOrientacion extends StatelessWidget {
  const ConoOrientacion({super.key, required this.centro});

  /// El punto del GPS en la vista del mapa.
  final Offset centro;

  /// El diámetro del cono (canvas: 150 px).
  static const diametro = 150.0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: centro.dx - diametro / 2,
      top: centro.dy - diametro / 2,
      width: diametro,
      height: diametro,
      child: IgnorePointer(
        child: Semantics(
          image: true,
          label: TextosMapaUbicaciones.conoOrientacion,
          child: const CustomPaint(painter: PintorConoOrientacion()),
        ),
      ),
    );
  }
}

/// Pinta el cono: un sector de 64° hacia arriba, del azul `#13407A` al 62 %, que se desvanece hacia
/// afuera (canvas: `conic-gradient` con una máscara radial). Deja libre el punto del GPS (6 dp más
/// su borde blanco de 3), que se sigue viendo entero.
class PintorConoOrientacion extends CustomPainter {
  const PintorConoOrientacion();

  /// La apertura del cono, en grados.
  static const apertura = 64.0;

  /// El radio del punto del GPS con su borde (el estilo del mapa: 6 + 3).
  static const radioPuntoGps = 9.0;

  static const _azul = Color(0x9E13407A);

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final radio = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: centro, radius: radio);
    // Hacia arriba es -90°: el sector va de -90 - 32 a -90 + 32.
    const inicio = (-90 - apertura / 2) * math.pi / 180;
    const barrido = apertura * math.pi / 180;
    final sector = Path()
      ..moveTo(centro.dx, centro.dy)
      ..arcTo(rect, inicio, barrido, false)
      ..close();
    final hueco = Path()..addOval(Rect.fromCircle(center: centro, radius: radioPuntoGps));
    canvas.drawPath(
      Path.combine(PathOperation.difference, sector, hueco),
      Paint()
        ..shader = const RadialGradient(
          colors: [_azul, _azul, Color(0x0013407A)],
          stops: [0, .14, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(PintorConoOrientacion oldDelegate) => false;
}

/// «+ Nueva» (canvas): la píldora navy de 52 dp de alto que abre el alta.
class BotonNuevaUbicacion extends StatelessWidget {
  const BotonNuevaUbicacion({super.key, required this.alPresionar});

  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: TextosMapaUbicaciones.nuevaUbicacion,
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: Material(
          color: Theme.of(context).colorScheme.primary,
          elevation: 4,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: alPresionar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52, minWidth: 52),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 20, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('+', style: TextStyle(color: Colors.white, fontSize: 22, height: 1)),
                    SizedBox(width: 8),
                    Text(
                      TextosMapaUbicaciones.nueva,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El pin para sumar una casa, abajo a la derecha (vista 39, M·01; vista 41, 41A): un botón redondo
/// blanco con la gota del pin. Se arrastra al lugar del mapa ([alSoltar] recibe dónde quedó la punta,
/// en coordenadas globales) o se toca para dejarlo en la ubicación de la colportora ([alTocar]).
class BotonPinCasaNueva extends StatelessWidget {
  const BotonPinCasaNueva({super.key, required this.alTocar, required this.alSoltar});

  final VoidCallback alTocar;
  final ValueChanged<Offset> alSoltar;

  /// El lado del botón (canvas: 60 dp).
  static const lado = 60.0;

  /// Mientras se arrastra, la punta del pin va esta distancia por encima del dedo: el dedo no la tapa.
  static const sobreElDedo = 24.0;

  @override
  Widget build(BuildContext context) {
    final boton = Material(
      color: Colors.white,
      elevation: 6,
      shape: const CircleBorder(side: BorderSide(color: ColoresAlta.grisBorde)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: alTocar,
        child: const SizedBox(
          width: lado,
          height: lado,
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(top: 6),
              child: ExcludeSemantics(child: SizedBox(width: 26, height: 32, child: _PinChico())),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: TextosMapaUbicaciones.pinCasaNueva,
      hint: TextosMapaUbicaciones.pinCasaNuevaPista,
      onTap: alTocar,
      excludeSemantics: true,
      child: Tooltip(
        message: TextosMapaUbicaciones.pinCasaNueva,
        excludeFromSemantics: true,
        child: Draggable<Object>(
          data: const Object(),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Transform.translate(
            // La punta de la gota (abajo al medio) queda [sobreElDedo] por encima del dedo.
            offset: const Offset(-18, -44 - sobreElDedo),
            child: const PinAlta(),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: boton),
          onDragEnd: (detalles) => alSoltar(detalles.offset - const Offset(0, sobreElDedo)),
          child: boton,
        ),
      ),
    );
  }
}

/// La gota del pin, chica, para el botón.
class _PinChico extends StatelessWidget {
  const _PinChico();

  @override
  Widget build(BuildContext context) {
    return const FittedBox(child: PinAlta(etiqueta: TextosMapaUbicaciones.pinCasaNueva));
  }
}

/// El chip «Referencias» de arriba a la derecha (canvas): abre la leyenda de los marcadores.
class ChipReferencias extends StatelessWidget {
  const ChipReferencias({super.key, required this.alPresionar});

  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: TextosMapaUbicaciones.referencias,
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: alPresionar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.layers_outlined, size: 18, color: ColoresAlta.azul),
                    SizedBox(width: 7),
                    Text(
                      TextosMapaUbicaciones.referencias,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13.5,
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
    );
  }
}

/// Abre la leyenda «Referencias». Devuelve cuando se cierra.
Future<void> mostrarReferenciasMapa(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => const HojaReferenciasMapa(),
);

/// La leyenda de los marcadores de la vista 06. El canvas la dibuja entera y la marca «PROPUESTA»
/// (con los ocho estados de la visita y la venta). Desde la vista 39 (HU-VIS-005) el mapa dibuja los
/// ocho —el color y el símbolo de cada estado—, y acá van todos, con los rótulos de la lista.
class HojaReferenciasMapa extends StatelessWidget {
  const HojaReferenciasMapa({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: ClavesMapaUbicaciones.hojaReferencias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text(
                TextosMapaUbicaciones.referencias,
                style: TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _FilaReferencia(
              muestra: InsigniaEstadoCasa(estado: EstadoCasa.sinVisita, tamano: 24),
              texto: TextosMapaUbicaciones.leyendaSinVisita,
            ),
            for (final estado in EstadoCasa.values)
              if (estado != EstadoCasa.sinVisita)
                _FilaReferencia(
                  muestra: InsigniaEstadoCasa(estado: estado, tamano: 24),
                  texto: FormatoListaUbicaciones.estado(estado),
                ),
            const _FilaReferencia(
              muestra: _MuestraEdificio(),
              texto: TextosMapaUbicaciones.leyendaEdificio,
            ),
            const _FilaReferencia(
              muestra: _MuestraGrupo(),
              texto: TextosMapaUbicaciones.leyendaAgrupadas,
            ),
            const _FilaReferencia(
              muestra: _MuestraCerca(),
              texto: TextosMapaUbicaciones.leyendaCerca,
            ),
            const _FilaReferencia(
              muestra: _MuestraCuadrado(),
              etiquetaMuestra: TextosMapaUbicaciones.muestraCuadrado,
              texto: TextosMapaUbicaciones.leyendaAcercar,
            ),
            const _FilaReferencia(
              muestra: _MuestraTuUbicacion(),
              texto: TextosMapaUbicaciones.leyendaTuUbicacion,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: ClavesMapaUbicaciones.cerrarReferencias,
                onPressed: () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(
                  foregroundColor: ColoresAlta.azul,
                  minimumSize: const Size(48, 48),
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text(TextosMapaUbicaciones.cerrar),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaReferencia extends StatelessWidget {
  const _FilaReferencia({required this.muestra, required this.texto, this.etiquetaMuestra});

  final Widget muestra;
  final String texto;

  /// Lo que dice el lector de la muestra cuando no se explica sola (el cuadrado con su número).
  final String? etiquetaMuestra;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: etiquetaMuestra == null ? texto : '$etiquetaMuestra. $texto',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            SizedBox(width: 44, child: Center(child: muestra)),
            const SizedBox(width: 12),
            Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      ),
    );
  }
}

/// El símbolo del edificio (▦), tal como lo dibuja el mapa de lejos: la misma insignia de 24 dp.
class _MuestraEdificio extends StatelessWidget {
  const _MuestraEdificio();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      key: ClavesMapaUbicaciones.muestraEdificio,
      size: Size.square(24),
      painter: _PintorEdificio(),
    );
  }
}

class _PintorEdificio extends CustomPainter {
  const _PintorEdificio();

  @override
  void paint(Canvas canvas, Size size) => MarcadorEstado.pintarInsignia(
    canvas,
    size.center(Offset.zero),
    size.width,
    VarianteMarcador.edificio,
  );

  @override
  bool shouldRepaint(_PintorEdificio old) => false;
}

/// El cuadrado de la casa acercada (canvas 39, M·02): el número en dos renglones («20 / 44»). Va
/// con el aspecto de «Sin visita»; el color y el símbolo del estado son los de las filas de arriba.
class _MuestraCuadrado extends StatelessWidget {
  const _MuestraCuadrado();

  @override
  Widget build(BuildContext context) {
    const variante = VarianteMarcador.sinVisita;
    return Container(
      key: ClavesMapaUbicaciones.muestraCuadrado,
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: variante.fondo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: variante.borde, width: variante.grosorBorde),
      ),
      child: Text(
        MarcadorEstado.numeroEnDosRenglones('2044'),
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: variante.tintaNumero,
          height: 1.05,
        ),
      ),
    );
  }
}

/// El círculo de un grupo (canvas: «9»).
class _MuestraGrupo extends StatelessWidget {
  const _MuestraGrupo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ColoresMapa.tintaOscura,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Text(
        '9',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

/// La etiqueta de «cerca tuyo» (canvas: «1234»).
class _MuestraCerca extends StatelessWidget {
  const _MuestraCerca();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ColoresMapa.bordeContexto, width: 2),
      ),
      child: const Text(
        '1234',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: ColoresMapa.tinta,
          height: 1,
        ),
      ),
    );
  }
}

/// El punto azul del GPS.
class _MuestraTuUbicacion extends StatelessWidget {
  const _MuestraTuUbicacion();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: ColoresMapa.puntoGps,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x292F6FD1), spreadRadius: 6)],
      ),
    );
  }
}
