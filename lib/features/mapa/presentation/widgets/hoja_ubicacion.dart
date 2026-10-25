import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/espacio.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/services/agrupador_espacios.dart';
import '../formato_espacios.dart';
import '../formato_ubicaciones.dart';
import '../pages/modificar_ubicacion_page.dart';
import '../providers/espacios_providers.dart';
import 'hoja_depto.dart';
import 'piezas_alta.dart';
import 'piezas_lista_ubicaciones.dart';

/// Las claves de la hoja de una ubicación (vista 11·01).
abstract final class ClavesHojaUbicacion {
  static const hoja = Key('ubicacion_hoja');
  static const cerrar = Key('ubicacion_hoja_cerrar');
  static const agregarDepto = Key('ubicacion_hoja_agregar_depto');
  static const editar = Key('ubicacion_hoja_editar');
  static const cargando = Key('ubicacion_hoja_cargando');
  static const vacio = Key('ubicacion_hoja_vacio');
  static const error = Key('ubicacion_hoja_error');
  static const reintentar = Key('ubicacion_hoja_reintentar');
  static const cantidad = Key('ubicacion_hoja_cantidad');

  /// La fila del espacio [id].
  static Key fila(String id) => Key('ubicacion_hoja_fila_$id');

  /// El rótulo del grupo de un piso (`null`: «Sin piso»).
  static Key grupo(String? piso) => Key('ubicacion_hoja_grupo_${piso ?? 'sin_piso'}');
}

/// Cómo se abre «Editar edificio» (la vista 07). Por defecto abre `ModificarUbicacionPage`; un test lo
/// reemplaza.
typedef AbridorEdicionUbicacion =
    Future<SalidaModificarUbicacion?> Function(
      BuildContext context, {
      required String colportorId,
      required String ubicacionId,
    });

final abridorEdicionUbicacionProvider = Provider<AbridorEdicionUbicacion>(
  (ref) => ModificarUbicacionPage.abrir,
);

/// Abre la hoja de la ubicación [ubicacionId] (vista 11·01): su dirección, sus deptos agrupados por
/// piso, «+ Departamento» y «Editar …». Se abre desde «Detalle» de la vista previa del mapa y desde
/// «›» de la lista. [distanciaMetros] es la distancia desde donde está el colportor, si se sabe (el
/// rótulo «EDIFICIO · A 25 M»).
///
/// Devuelve lo que pasó en la edición de la ubicación ([SalidaModificarUbicacion]) para que quien la
/// abrió lo aplique (seleccionarla en el mapa, dejar de mostrarla si se dio de baja…), o `null` si el
/// colportor solo la cerró.
Future<SalidaModificarUbicacion?> mostrarHojaUbicacion(
  BuildContext context, {
  required String colportorId,
  required String ubicacionId,
  double? distanciaMetros,
}) => showModalBottomSheet<SalidaModificarUbicacion>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black26,
  builder: (_) => HojaUbicacion(
    colportorId: colportorId,
    ubicacionId: ubicacionId,
    distanciaMetros: distanciaMetros,
  ),
);

/// La hoja de una ubicación con sus espacios (vista 11·01, HU-UBI-007). Arranca a la mitad de la
/// pantalla (a casi toda con el texto grande o el lector de pantalla) y se agranda arrastrándola.
///
/// - Sin clientes (decisión de Cristian del 06/10): ni «+ Agregar cliente», ni «Registrar visita», ni
///   el atajo de la casa al alta de una persona; vuelven con #140 (S7) y #151 (S8).
///
/// Para volver a implementar lo diferido (documentado a pedido de Cristian, 06/10):
/// - Ficha del depto (artboard «11 · 04 Departamento con clientes») y «+ Agregar cliente»: hoy tocar una
///   fila abre `HojaDepto` (edición, [_editarDepto]). Con #140 la fila abre la ficha (clientes del
///   espacio, `personasDelEspacioProvider`, y el alta de persona de `AltaPersonaPage`), y la edición y la
///   baja pasan a un botón de esa ficha. «Ver depto N ›» del repetido (11·03) también va a la ficha.
/// - Atajo de la casa al alta de una persona: en [_contenido], rama `esCasa`, hoy solo el encabezado y
///   «Editar casa».
/// - «Registrar visita» y «Agendar» (#151): botones de `VistaPreviaUbicacion` junto a «Detalle», en
///   `hoja_mapa_ubicaciones.dart`.
/// - Una casa no tiene deptos: solo el encabezado y «Editar casa».
/// - Tocar un depto abre su edición (11·02 con los datos cargados), donde también se da de baja.
class HojaUbicacion extends ConsumerStatefulWidget {
  const HojaUbicacion({
    super.key,
    required this.colportorId,
    required this.ubicacionId,
    this.distanciaMetros,
  });

  final String colportorId;
  final String ubicacionId;
  final double? distanciaMetros;

  @override
  ConsumerState<HojaUbicacion> createState() => _HojaUbicacionState();
}

class _HojaUbicacionState extends ConsumerState<HojaUbicacion> {
  /// Evita abrir dos veces la hoja de un depto o la edición con dos toques seguidos.
  var _abriendo = false;

  /// El depto que «Ver depto 102 ›» dejó señalado.
  String? _resaltado;

  final _claves = <String, GlobalKey>{};

  /// El controlador de la lista que da la hoja arrastrable (cambia en cada dibujo).
  ScrollController? _controlador;

  /// Lo que se dibujó en la lista la última vez (grupos y deptos, en orden): para estimar dónde cae una
  /// fila que todavía no se construyó.
  List<Object> _plana = const [];

  @override
  Widget build(BuildContext context) {
    final ubicacion = ref.watch(ubicacionDeLaHojaProvider(widget.ubicacionId));
    final grande =
        MediaQuery.textScalerOf(context).scale(14) > 18.2 ||
        MediaQuery.accessibleNavigationOf(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: grande ? 0.92 : 0.5,
      minChildSize: grande ? 0.6 : 0.3,
      maxChildSize: 0.95,
      snap: true,
      builder: (context, controlador) {
        _controlador = controlador;
        return Material(
          key: ClavesHojaUbicacion.hoja,
          color: Colors.white,
          elevation: 8,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ubicacion.when(
            loading: () => _Cuerpo(
              controlador: controlador,
              alCerrar: _cerrar,
              hijos: const [
                _Mensaje(clave: ClavesHojaUbicacion.cargando, texto: TextosEspacios.cargando),
              ],
            ),
            error: (_, _) => _Cuerpo(
              controlador: controlador,
              alCerrar: _cerrar,
              hijos: [
                _ErrorLectura(
                  texto: TextosEspacios.errorUbicacion,
                  alReintentar: () => ref.invalidate(ubicacionDeLaHojaProvider(widget.ubicacionId)),
                ),
              ],
            ),
            data: (u) => u == null
                ? _Cuerpo(
                    controlador: controlador,
                    alCerrar: _cerrar,
                    hijos: const [_Mensaje(texto: TextosEspacios.errorUbicacion)],
                  )
                : _contenido(context, u, controlador),
          ),
        );
      },
    );
  }

  void _cerrar() => Navigator.of(context).pop();

  Widget _contenido(BuildContext context, Ubicacion u, ScrollController controlador) {
    final esCasa = u.tipo == TipoUbicacion.casa;
    final espacios = esCasa ? null : ref.watch(espaciosDeUbicacionProvider(u.id));
    final distancia = widget.distanciaMetros;
    final rotulo = [
      FormatoUbicaciones.tipo(u.tipo),
      if (distancia != null && distancia.isFinite && distancia >= 0)
        'a ${FormatoUbicaciones.distancia(distancia)}',
    ].join(' · ').toUpperCase();

    final total = espacios?.asData?.value.length;
    final hijos = <Widget>[
      _Encabezado(
        rotulo: rotulo,
        titulo: FormatoUbicaciones.direccion(u),
        cantidad: total == null ? null : TextosEspacios.cantidad(total),
        alCerrar: _cerrar,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (!esCasa)
              FilledButton(
                key: ClavesHojaUbicacion.agregarDepto,
                onPressed: _abriendo ? null : () => unawaited(_agregar(u)),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text(TextosEspacios.masDepartamento),
              ),
            OutlinedButton(
              key: ClavesHojaUbicacion.editar,
              onPressed: _abriendo ? null : () => unawaited(_editar(u)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: ColoresAlta.azul,
                side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
              ),
              child: Text(TextosEspacios.editarUbicacion(u.tipo)),
            ),
          ],
        ),
      ),
      const Divider(height: 1, color: ColoresLista.grisBorde),
    ];

    if (esCasa) {
      return _CuerpoSlivers(controlador: controlador, cabecera: hijos, lista: const []);
    }
    return espacios!.when(
      loading: () => _CuerpoSlivers(
        controlador: controlador,
        cabecera: [
          ...hijos,
          const _Mensaje(clave: ClavesHojaUbicacion.cargando, texto: TextosEspacios.cargando),
        ],
        lista: const [],
      ),
      error: (_, _) => _CuerpoSlivers(
        controlador: controlador,
        cabecera: [
          ...hijos,
          _ErrorLectura(
            texto: TextosEspacios.errorLectura,
            alReintentar: () => ref.invalidate(espaciosDeUbicacionProvider(u.id)),
          ),
        ],
        lista: const [],
      ),
      data: (lista) {
        if (lista.isEmpty) {
          return _CuerpoSlivers(
            controlador: controlador,
            cabecera: [...hijos, const _VacioEspacios()],
            lista: const [],
          );
        }
        final grupos = AgrupadorEspacios.porPiso(lista);
        final filas = <Object>[
          for (final g in grupos) ...[g, ...g.espacios],
        ];
        _plana = filas;
        return _CuerpoSlivers(
          controlador: controlador,
          cabecera: hijos,
          lista: filas,
          constructor: (contexto, fila) {
            if (fila is GrupoDePiso) return _CabeceraGrupo(grupo: fila);
            final e = fila as Espacio;
            return _FilaDepto(
              key: _claveFila(e.id),
              espacio: e,
              resaltado: e.id == _resaltado,
              alTocar: _abriendo ? null : () => unawaited(_editarDepto(u, e)),
            );
          },
        );
      },
    );
  }

  GlobalKey _claveFila(String id) => _claves.putIfAbsent(id, GlobalKey.new);

  // ---------------------------------------------------------------- acciones

  Future<void> _agregar(Ubicacion u) async {
    if (_abriendo) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    setState(() => _abriendo = true);
    try {
      final salida = await mostrarHojaDepto(context, ubicacion: u, colportorId: widget.colportorId);
      _aplicar(salida);
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  Future<void> _editarDepto(Ubicacion u, Espacio e) async {
    if (_abriendo) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    setState(() => _abriendo = true);
    try {
      final salida = await mostrarHojaDepto(
        context,
        ubicacion: u,
        colportorId: widget.colportorId,
        espacio: e,
      );
      _aplicar(salida);
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  void _aplicar(SalidaHojaDepto? salida) {
    if (!mounted) return;
    switch (salida) {
      case VerDeptoElegido(:final espacioId):
        setState(() => _resaltado = espacioId);
        _mostrarFila(espacioId);
      case DeptoDadoDeBaja(:final espacio):
        setState(() => _resaltado = null);
        unawaited(
          SemanticsService.sendAnnouncement(
            View.of(context),
            '${TextosEspacios.depto(espacio)} dado de baja.',
            Directionality.of(context),
          ),
        );
      case DeptoAgregado() || DeptoEditado() || null:
        if (_resaltado != null) setState(() => _resaltado = null);
    }
  }

  /// Deja a la vista la fila de [id]. Las filas son perezosas: si todavía no se dibujó, la lista se
  /// acerca por una estimación y se vuelve a intentar.
  void _mostrarFila(String id, {int intento = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final contexto = _claves[id]?.currentContext;
      if (contexto != null) {
        unawaited(Scrollable.ensureVisible(contexto, alignment: 0.3));
        return;
      }
      if (intento >= 6) return;
      final controlador = _controlador;
      if (controlador != null && controlador.hasClients) {
        final posicion = controlador.position;
        // Primero la estimación de dónde cae la fila; si todavía no se construyó, se sigue de a media
        // pantalla.
        final destino = intento == 0
            ? _alturaHasta(id)
            : posicion.pixels + posicion.viewportDimension / 2;
        posicion.jumpTo(destino.clamp(0, posicion.maxScrollExtent));
      }
      _mostrarFila(id, intento: intento + 1);
    });
  }

  /// Lo que miden las filas que van antes de la de [id] (un grupo ~34 dp y un depto ~56 dp con el texto
  /// normal).
  double _alturaHasta(String id) {
    var y = 0.0;
    for (final fila in _plana) {
      if (fila is Espacio && fila.id == id) return y;
      y += fila is GrupoDePiso ? 34 : 56;
    }
    return 0;
  }

  Future<void> _editar(Ubicacion u) async {
    if (_abriendo) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    setState(() => _abriendo = true);
    SalidaModificarUbicacion? salida;
    try {
      salida = await ref.read(abridorEdicionUbicacionProvider)(
        context,
        colportorId: widget.colportorId,
        ubicacionId: u.id,
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text(TextosEspacios.noPudimosAbrirEdicion)));
      }
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
    if (!mounted) return;
    if (salida != null) {
      // Lo que pasó con la ubicación (editada, baja, otra elegida) lo aplica el mapa: la hoja se cierra.
      Navigator.of(context).pop(salida);
      return;
    }
    // Se cerró sin guardar: la dirección pudo no cambiar, pero se vuelve a leer por si acaso.
    ref.invalidate(ubicacionDeLaHojaProvider(u.id));
  }
}

// -------------------------------------------------------------------- piezas

/// El armazón de la hoja cuando no hay nada que listar (cargando, error): el asa, el cierre y [hijos].
class _Cuerpo extends StatelessWidget {
  const _Cuerpo({required this.controlador, required this.alCerrar, required this.hijos});

  final ScrollController controlador;
  final VoidCallback alCerrar;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => _CuerpoSlivers(
    controlador: controlador,
    cabecera: [
      _Encabezado(rotulo: '', titulo: '', cantidad: null, alCerrar: alCerrar, vacio: true),
      ...hijos,
    ],
    lista: const [],
  );
}

/// El cuerpo desplazable: la cabecera (asa, título, botones), y la lista perezosa de filas.
class _CuerpoSlivers extends StatelessWidget {
  const _CuerpoSlivers({
    required this.controlador,
    required this.cabecera,
    required this.lista,
    this.constructor,
  });

  final ScrollController controlador;
  final List<Widget> cabecera;
  final List<Object> lista;
  final Widget Function(BuildContext, Object)? constructor;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controlador,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    decoration: BoxDecoration(
                      color: ColoresLista.chevron,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              ...cabecera,
            ],
          ),
        ),
        if (lista.isNotEmpty)
          SliverList.builder(
            itemCount: lista.length,
            itemBuilder: (contexto, i) => constructor!(contexto, lista[i]),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.rotulo,
    required this.titulo,
    required this.cantidad,
    required this.alCerrar,
    this.vacio = false,
  });

  final String rotulo;
  final String titulo;
  final String? cantidad;
  final VoidCallback alCerrar;
  final bool vacio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: vacio
                ? const SizedBox(height: 48)
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rotulo,
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 10,
                            letterSpacing: 1.4,
                            color: ColoresAlta.gris,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Semantics(
                          header: true,
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
                        if (cantidad != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              cantidad!,
                              key: ClavesHojaUbicacion.cantidad,
                              style: const TextStyle(fontSize: 13, color: ColoresLista.grisTexto),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          IconButton(
            key: ClavesHojaUbicacion.cerrar,
            tooltip: TextosEspacios.cerrar,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: alCerrar,
            icon: const ExcludeSemantics(child: Text('✕', style: TextStyle(fontSize: 18))),
          ),
        ],
      ),
    );
  }
}

class _CabeceraGrupo extends StatelessWidget {
  const _CabeceraGrupo({required this.grupo});

  final GrupoDePiso grupo;

  @override
  Widget build(BuildContext context) {
    final nombre = grupo.piso == null
        ? TextosEspacios.grupoSinPiso
        : TextosEspacios.piso(grupo.piso!);
    return Semantics(
      header: true,
      child: Container(
        key: ClavesHojaUbicacion.grupo(grupo.piso),
        width: double.infinity,
        color: ColoresLista.filaBaja,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                nombre,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: ColoresAlta.gris,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${grupo.espacios.length}',
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 1.4,
                color: ColoresAlta.gris,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaDepto extends StatelessWidget {
  const _FilaDepto({
    super.key,
    required this.espacio,
    required this.resaltado,
    required this.alTocar,
  });

  final Espacio espacio;
  final bool resaltado;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final sinNumero = espacio.sinNumero;
    return Semantics(
      button: true,
      label: TextosEspacios.filaSemantica(espacio),
      excludeSemantics: true,
      onTap: alTocar,
      child: Material(
        color: resaltado ? ColoresLista.azulFondo : Colors.white,
        child: InkWell(
          key: ClavesHojaUbicacion.fila(espacio.id),
          onTap: alTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: ColoresLista.grisBorde)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      TextosEspacios.depto(espacio),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: sinNumero ? ColoresLista.grisTexto : ColoresLista.tinta,
                        fontStyle: sinNumero ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('›', style: TextStyle(fontSize: 22, color: ColoresLista.chevron)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto, this.clave});

  final String texto;
  final Key? clave;

  @override
  Widget build(BuildContext context) => Padding(
    key: clave,
    padding: const EdgeInsets.all(24),
    child: Semantics(
      liveRegion: true,
      child: Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
    ),
  );
}

class _VacioEspacios extends StatelessWidget {
  const _VacioEspacios();

  @override
  Widget build(BuildContext context) => Padding(
    key: ClavesHojaUbicacion.vacio,
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
    child: Column(
      children: [
        Semantics(
          header: true,
          child: const Text(
            TextosEspacios.vacioTitulo,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          TextosEspacios.vacioCuerpo,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: ColoresLista.grisTexto),
        ),
      ],
    ),
  );
}

class _ErrorLectura extends StatelessWidget {
  const _ErrorLectura({required this.texto, required this.alReintentar});

  final String texto;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) => Padding(
    key: ClavesHojaUbicacion.error,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: texto),
        const SizedBox(height: 8),
        OutlinedButton(
          key: ClavesHojaUbicacion.reintentar,
          onPressed: alReintentar,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text(TextosEspacios.reintentar),
        ),
      ],
    ),
  );
}
