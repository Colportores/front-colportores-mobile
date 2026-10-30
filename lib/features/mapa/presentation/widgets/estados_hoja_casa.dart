import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../agenda/presentation/formato_agenda.dart' show TextosAgenda;
import '../../domain/entities/estado_casa.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/entities/ubicacion.dart';
import '../formato_lista_ubicaciones.dart';
import '../formato_ubicaciones.dart';
import 'piezas_alta.dart';
import 'piezas_lista_ubicaciones.dart';

/// Los textos de los estados de la hoja de la casa (vista 39, grupo E · «Estados y casos límite»,
/// HU-UBI-003 y HU-UBI-005). Los literales son los del canvas, letra por letra.
abstract final class TextosEstadosHojaCasa {
  // E·01 — cargando la casa. No tiene texto a la vista: es el rótulo que lee el lector de pantalla.
  static const cargando = 'Cargando la casa';

  // E·02 — error al leer la casa.
  static const errorAlLeer = 'No pudimos leer esta casa en tu teléfono.';
  static const reintentar = 'Reintentar';

  // E·04 — casa dada de baja.
  static const dadaDeBaja =
      'Esta casa está dada de baja: podés ver lo que pasó, pero no registrar nada.';
  static const reactivar = 'Reactivar';

  // E·06 — varias ubicaciones en el mismo punto.
  static const elegiCual = 'Elegí cuál';

  // La baja de una ubicación en la segunda línea de la fila de E·06.
  static const filaDadaDeBaja = 'dada de baja';

  /// E·05: «Estás a 650 m de esta casa.» La distancia sale de `FormatoUbicaciones.distancia` (el
  /// espacio entre el número y la unidad es duro). Vacío si [metros] no es una distancia (no hay
  /// posición, o un número que no existe): nunca «Estás a  de esta casa.»
  static String lejos(double metros) {
    final distancia = FormatoUbicaciones.distancia(metros);
    return distancia.isEmpty ? '' : 'Estás a $distancia de esta casa.';
  }

  /// E·06: el título de la hoja, «3 ubicaciones acá».
  static String variasEnElPunto(int cantidad) =>
      cantidad == 1 ? '1 ubicación acá' : '$cantidad ubicaciones acá';

  /// E·04: la segunda línea del título de la hoja de una casa dada de baja, «Casa · dada de baja el
  /// 18/10» (`dd/MM` en hora local).
  static String subtituloDeBaja(TipoUbicacion tipo, DateTime bajaEl) =>
      '${FormatoUbicaciones.tipo(tipo)} · $filaDadaDeBaja el ${FormatoListaUbicaciones.diaMes(bajaEl)}';
}

/// Las claves de los estados de la hoja de la casa, para los tests y para quien los monta.
abstract final class ClavesEstadosHojaCasa {
  static const cargando = Key('hoja_casa_cargando');
  static const avisoErrorAlLeer = Key('hoja_casa_aviso_error');
  static const avisoErrorAlLeerAgendas = Key('hoja_casa_aviso_error_agendas');
  static const avisoDadaDeBaja = Key('hoja_casa_aviso_baja');
  static const avisoLejos = Key('hoja_casa_aviso_lejos');
  static const accionDelAviso = Key('hoja_casa_aviso_accion');
  static const elegirUbicacion = Key('hoja_casa_elegir_ubicacion');
  static Key filaDelPunto(String ubicacionId) => Key('hoja_casa_punto_$ubicacionId');
}

const _fondoEsqueleto = Color(0xFFEDEBE4);
const _fondoAvisoAtencion = Color(0xFFFFFDF6);

/// E·01 · «Cargando la casa»: tres barras grises en el lugar del contenido de la hoja (la persona, la
/// nota y el botón). Es quieta a propósito (sin brillo que se mueve: no depende de «reducir
/// movimientos»); lo que la hace un estado y no un hueco es su rótulo, que el lector de pantalla dice
/// como región viva. Mientras se muestra no hay nada que tocar: la hoja no ofrece «Registrar visita»
/// hasta saber de qué casa se trata.
class CargandoHojaCasa extends StatelessWidget {
  const CargandoHojaCasa({super.key});

  static const _alturas = [52.0, 52.0, 20.0];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ClavesEstadosHojaCasa.cargando,
      container: true,
      liveRegion: true,
      label: TextosEstadosHojaCasa.cargando,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _alturas.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Container(
                height: _alturas[i],
                decoration: BoxDecoration(
                  color: _fondoEsqueleto,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// El tono de un [AvisoHojaCasa]: el borde, la insignia y el fondo del cuadro del canvas (`Bloques`,
/// banner `err`, `warn` e `info`).
enum TonoAvisoHojaCasa {
  /// Rojo, «!»: algo falló y hay qué hacer.
  error(ColoresAlta.rojo, '!', Colors.white),

  /// Ámbar, «!»: se puede mirar, pero no hacer.
  atencion(ColoresAlta.ambarBorde, '!', _fondoAvisoAtencion),

  /// Gris oscuro, «i»: se informa y se sigue.
  informacion(ColoresAlta.tinta, 'i', Colors.white);

  const TonoAvisoHojaCasa(this.color, this.glifo, this.fondo);

  final Color color;
  final String glifo;
  final Color fondo;
}

/// El cuadro de aviso de la hoja de la casa (vista 39, E·02, E·04 y E·05): insignia, texto y, si hay
/// algo que hacer, una acción de texto abajo.
///
/// Se construye con uno de los tres avisos de la hoja ([AvisoHojaCasa.errorAlLeer],
/// [AvisoHojaCasa.dadaDeBaja] y [AvisoHojaCasa.lejos]). **Sin conexión (E·03) no tiene aviso**: todo
/// funciona igual y lo registrado se envía al volver (vista 25).
///
/// La acción se dispara **una sola vez por vez**: mientras la que se tocó no termina (su `Future`) el
/// botón queda apagado, así un doble toque no abre dos «Reactivar» ni lanza dos lecturas. Si termina
/// —bien o con una excepción— el botón vuelve a estar habilitado: nada queda «ocupado» para siempre.
/// La acción es quien avisa su propio error; una excepción que escapa de ella se descarta acá.
///
/// Se anuncia a los lectores de pantalla como región viva.
class AvisoHojaCasa extends StatefulWidget {
  const AvisoHojaCasa._({
    super.key,
    required this.tono,
    required this.texto,
    this.etiquetaDeLaAccion,
    this.alAccionar,
    this.accionAlLado = false,
  });

  /// E·02 · «No pudimos leer esta casa en tu teléfono.» con «Reintentar».
  factory AvisoHojaCasa.errorAlLeer({Key? key, required FutureOr<void> Function() alReintentar}) =>
      AvisoHojaCasa._(
        key: key ?? ClavesEstadosHojaCasa.avisoErrorAlLeer,
        tono: TonoAvisoHojaCasa.error,
        texto: TextosEstadosHojaCasa.errorAlLeer,
        etiquetaDeLaAccion: TextosEstadosHojaCasa.reintentar,
        alAccionar: alReintentar,
      );

  /// «No pudimos leer tu agenda.» con «Reintentar», cuando no se puede leer la lista de «Visitas
  /// agendadas» de la casa (23B·09, el mismo aviso de la pestaña Agenda).
  factory AvisoHojaCasa.errorAlLeerAgendas({
    Key? key,
    required FutureOr<void> Function() alReintentar,
  }) => AvisoHojaCasa._(
    key: key ?? ClavesEstadosHojaCasa.avisoErrorAlLeerAgendas,
    tono: TonoAvisoHojaCasa.error,
    texto: TextosAgenda.errorLectura,
    etiquetaDeLaAccion: TextosAgenda.reintentar,
    alAccionar: alReintentar,
    accionAlLado: true,
  );

  /// E·04 · «Esta casa está dada de baja: podés ver lo que pasó, pero no registrar nada.» con
  /// «Reactivar». Sin [alReactivar] (la baja por unión de duplicados no se reactiva, HU-UBI-005) el
  /// aviso va sin acción.
  factory AvisoHojaCasa.dadaDeBaja({Key? key, FutureOr<void> Function()? alReactivar}) =>
      AvisoHojaCasa._(
        key: key ?? ClavesEstadosHojaCasa.avisoDadaDeBaja,
        tono: TonoAvisoHojaCasa.atencion,
        texto: TextosEstadosHojaCasa.dadaDeBaja,
        etiquetaDeLaAccion: alReactivar == null ? null : TextosEstadosHojaCasa.reactivar,
        alAccionar: alReactivar,
      );

  /// E·05 · «Estás a 650 m de esta casa.» Solo informa: no bloquea ni pide confirmar (pregunta 6
  /// abierta). Con una distancia que no existe (NaN, infinita o negativa) no dibuja nada.
  factory AvisoHojaCasa.lejos({Key? key, required double metros}) => AvisoHojaCasa._(
    key: key ?? ClavesEstadosHojaCasa.avisoLejos,
    tono: TonoAvisoHojaCasa.informacion,
    texto: TextosEstadosHojaCasa.lejos(metros),
  );

  final TonoAvisoHojaCasa tono;
  final String texto;

  /// `null`: el aviso no tiene acción.
  final String? etiquetaDeLaAccion;
  final FutureOr<void> Function()? alAccionar;

  /// La acción va a la derecha del texto y no debajo: el aviso mide lo que el botón (48 dp) y entra
  /// bajo el título en la hoja a un tercio de la pantalla (360×640). Con el texto grande (desde 1,3×)
  /// no queda ancho para las dos cosas y va debajo, como los demás avisos.
  final bool accionAlLado;

  @override
  State<AvisoHojaCasa> createState() => _AvisoHojaCasaState();
}

class _AvisoHojaCasaState extends State<AvisoHojaCasa> {
  bool _enCurso = false;

  Future<void> _accionar() async {
    final accion = widget.alAccionar;
    // La guarda es una variable, no el `setState`: dos toques en el mismo cuadro llegan antes de que
    // el segundo se reconstruya.
    if (accion == null || _enCurso) return;
    _enCurso = true;
    setState(() {});
    try {
      await accion();
    } catch (_) {
      // Quien actúa avisa su propio error; el botón tiene que volver a estar habilitado.
    } finally {
      _enCurso = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.texto.isEmpty) return const SizedBox.shrink();
    final tono = widget.tono;
    final etiqueta = widget.etiquetaDeLaAccion;
    final texto = Text(
      widget.texto,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 13.5,
        height: 1.45,
        color: Color(0xFF0E1A2B),
      ),
    );
    final accion = etiqueta == null
        ? null
        : TextButton(
            key: ClavesEstadosHojaCasa.accionDelAviso,
            onPressed: _enCurso ? null : _accionar,
            style: TextButton.styleFrom(
              foregroundColor: ColoresAlta.azul,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              tapTargetSize: MaterialTapTargetSize.padded,
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(etiqueta),
          );
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: tono.fondo,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tono.color, width: 1.5),
        ),
        child: widget.accionAlLado && accion != null && !textoGrande(context)
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  InsigniaCirculo(color: tono.color, glyph: tono.glifo),
                  const SizedBox(width: 12),
                  Expanded(child: texto),
                  const SizedBox(width: 4),
                  accion,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InsigniaCirculo(color: tono.color, glyph: tono.glifo),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        texto,
                        if (accion != null)
                          Align(alignment: AlignmentDirectional.centerStart, child: accion),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// E·06 · «Varias ubicaciones en el mismo punto»: el título «3 ubicaciones acá», «Elegí cuál» y una
/// fila por ubicación (su insignia de estado, la dirección y «Casa · Cobranza pendiente»). Tocar una
/// fila llama a [alElegir] con esa ubicación y la hoja sigue con ella.
///
/// Quién decide que dos ubicaciones están «en el mismo punto» no es de este widget: recibe la lista
/// ya resuelta (ver el pendiente de la entrega). Con una lista vacía no dibuja nada.
///
/// [alElegir] se dispara **una sola vez por vez**: hasta que su `Future` termina las demás filas (y la
/// misma) no responden, así un doble toque —o dos filas seguidas— no abren dos hojas ni se pisan. Si
/// termina, con o sin excepción, las filas vuelven a poder tocarse.
///
/// Con un alto acotado (la hoja) el título y las filas se desplazan juntos; sin alto acotado el widget
/// mide lo que miden el título y sus filas.
class ElegirUbicacionDelPunto extends StatefulWidget {
  const ElegirUbicacionDelPunto({super.key, required this.ubicaciones, required this.alElegir});

  final List<ItemListaUbicacion> ubicaciones;
  final FutureOr<void> Function(ItemListaUbicacion elegida) alElegir;

  @override
  State<ElegirUbicacionDelPunto> createState() => _ElegirUbicacionDelPuntoState();
}

class _ElegirUbicacionDelPuntoState extends State<ElegirUbicacionDelPunto> {
  bool _enCurso = false;

  Future<void> _elegir(ItemListaUbicacion item) async {
    if (_enCurso) return;
    _enCurso = true;
    setState(() {});
    try {
      await widget.alElegir(item);
    } catch (_) {
      // Quien abre la hoja avisa su propio error; las filas tienen que volver a poder tocarse.
    } finally {
      _enCurso = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.ubicaciones;
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final encabezado = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            TextosEstadosHojaCasa.variasEnElPunto(items.length),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          TextosEstadosHojaCasa.elegiCual,
          style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF5B6B82)),
        ),
        const SizedBox(height: 12),
      ],
    );
    Widget fila(int i) => Padding(
      padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 8),
      child: _FilaDelPunto(item: items[i], enCurso: _enCurso, alTocar: () => _elegir(items[i])),
    );
    return LayoutBuilder(
      builder: (context, restricciones) => restricciones.hasBoundedHeight
          // El título se desplaza con las filas: a 300 % el título solo puede ocupar la hoja entera.
          ? ListView.builder(
              key: ClavesEstadosHojaCasa.elegirUbicacion,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: items.length + 1,
              itemBuilder: (_, i) => i == 0 ? encabezado : fila(i - 1),
            )
          : Column(
              key: ClavesEstadosHojaCasa.elegirUbicacion,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [encabezado, for (var i = 0; i < items.length; i++) fila(i)],
            ),
    );
  }
}

class _FilaDelPunto extends StatelessWidget {
  const _FilaDelPunto({required this.item, required this.enCurso, required this.alTocar});

  final ItemListaUbicacion item;
  final bool enCurso;
  final VoidCallback alTocar;

  String get _direccion => FormatoUbicaciones.direccion(item.ubicacion);

  /// «Casa · Cobranza pendiente»; sin estado conocido, solo «Casa»; una baja, «Casa · dada de baja».
  String get _meta {
    final partes = [
      FormatoUbicaciones.tipo(item.ubicacion.tipo),
      if (item.esBaja)
        TextosEstadosHojaCasa.filaDadaDeBaja
      else if (item.estado != null)
        FormatoListaUbicaciones.estado(item.estado!),
    ];
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estado = item.estado;
    final Widget insignia = item.esBaja
        ? const InsigniaBaja()
        : (estado == null || estado == EstadoCasa.sinVisita)
        ? InsigniaTipoUbicacion(tipo: item.ubicacion.tipo)
        : InsigniaEstadoCasa(estado: estado);
    return Semantics(
      key: ClavesEstadosHojaCasa.filaDelPunto(item.ubicacion.id),
      container: true,
      button: true,
      enabled: !enCurso,
      label: '$_direccion. $_meta',
      onTap: enCurso ? null : alTocar,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: ColoresColportaje.unica.borde),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enCurso ? null : alTocar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    insignia,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _direccion,
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _meta,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12.5,
                              color: Color(0xFF5B6B82),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('›', style: TextStyle(color: ColoresLista.chevron, fontSize: 18)),
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
