import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/consulta_lista_ubicaciones.dart';
import '../../domain/entities/estado_casa.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../formato_lista_ubicaciones.dart';
import '../formato_ubicaciones.dart';
import '../providers/lista_ubicaciones_providers.dart';
import '../providers/lista_ubicaciones_state.dart';
import 'hoja_alta.dart' show TextosAlta;
import 'piezas_alta.dart' show EnlaceAlta;
import 'piezas_lista_ubicaciones.dart';

const _scrim = Color(0x730E1A2B);
const _bordeHoja = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

/// Abre la hoja de filtros (vista 05, artboard «05B · 01 Hoja de filtros») y devuelve los filtros
/// armados si se tocó «Ver N ubicaciones», o `null` si se cerró sin aplicar.
Future<FiltrosLista?> mostrarHojaFiltrosLista(
  BuildContext context, {
  required String colportorId,
  required FiltrosLista actuales,
  required Coordenadas? posicion,
}) => showModalBottomSheet<FiltrosLista>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  barrierColor: _scrim,
  shape: _bordeHoja,
  builder: (_) =>
      HojaFiltrosLista(colportorId: colportorId, actuales: actuales, posicion: posicion),
);

/// Abre el menú del orden (vista 05: «Última actualización ▾» / «Por cercanía ▾»). «Por cercanía»
/// necesita GPS: sin él se ve deshabilitada con «Necesita GPS».
Future<OrdenListaUbicaciones?> mostrarHojaOrdenLista(
  BuildContext context, {
  required OrdenListaUbicaciones actual,
  required bool hayGps,
}) => showModalBottomSheet<OrdenListaUbicaciones>(
  context: context,
  useSafeArea: true,
  backgroundColor: Colors.white,
  barrierColor: _scrim,
  shape: _bordeHoja,
  builder: (_) => _MarcoHoja(
    titulo: 'Ordenar',
    hijo: _OpcionesHoja<OrdenListaUbicaciones>(
      elegida: actual,
      opciones: [
        const _Opcion(
          valor: OrdenListaUbicaciones.recientes,
          texto: TextosFiltrosLista.ordenRecientes,
        ),
        _Opcion(
          valor: OrdenListaUbicaciones.cercania,
          texto: TextosFiltrosLista.ordenCercania,
          detalle: hayGps ? null : TextosFiltrosLista.necesitaGps,
          habilitada: hayGps,
        ),
      ],
    ),
  ),
);

/// Los textos que comparten la hoja de filtros, el menú del orden y la pantalla.
abstract final class TextosFiltrosLista {
  static const ordenRecientes = 'Última actualización';
  static const ordenCercania = 'Por cercanía';
  static const necesitaGps = 'Necesita GPS';
  static const todasLasCiudades = 'Todas';
}

/// La hoja de filtros. Arma un borrador (nada se aplica hasta «Ver N ubicaciones») y, a medida que
/// cambia, muestra cuántas ubicaciones quedarían en cada tipo y estado: cada contador cuenta con
/// los demás filtros aplicados («Casa 8» = 8 casas con cobranza pendiente).
class HojaFiltrosLista extends ConsumerStatefulWidget {
  const HojaFiltrosLista({
    super.key,
    required this.colportorId,
    required this.actuales,
    required this.posicion,
  });

  final String colportorId;
  final FiltrosLista actuales;
  final Coordenadas? posicion;

  @override
  ConsumerState<HojaFiltrosLista> createState() => _HojaFiltrosListaState();
}

class _HojaFiltrosListaState extends ConsumerState<HojaFiltrosLista> {
  late Set<TipoUbicacion> _tipos = {...widget.actuales.tipos};
  late Set<EstadoCasa> _estados = {...widget.actuales.estados};
  late String? _ciudadId = widget.actuales.ciudadId;
  late ProximidadLista _proximidad = widget.actuales.proximidad;
  late bool _bajas = widget.actuales.incluirBajas;

  /// La última cuenta que llegó: se sigue mostrando mientras llega la del borrador nuevo.
  ListaUbicaciones? _ultima;

  /// Un segundo toque mientras la hoja se cierra no cierra también la pantalla de atrás.
  var _cerrando = false;

  bool get _hayGps => widget.posicion != null;

  FiltrosLista get _borrador => widget.actuales.copyWith(
    tipos: _tipos,
    estados: _estados,
    ciudadId: _ciudadId,
    sinCiudad: _ciudadId == null,
    // Sin GPS la proximidad no se puede pedir: el borrador no la lleva.
    proximidad: _hayGps ? _proximidad : ProximidadLista.cualquiera,
    incluirBajas: _bajas,
  );

  void _alternarTipo(TipoUbicacion tipo) => setState(() {
    _tipos = _tipos.contains(tipo) ? ({..._tipos}..remove(tipo)) : {..._tipos, tipo};
  });

  void _alternarEstado(EstadoCasa estado) => setState(() {
    _estados = _estados.contains(estado) ? ({..._estados}..remove(estado)) : {..._estados, estado};
  });

  void _limpiar() => setState(() {
    _tipos = {};
    _estados = {};
    _ciudadId = null;
    _proximidad = ProximidadLista.cualquiera;
    _bajas = false;
  });

  void _ver() {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(_borrador);
  }

  Future<void> _elegirCiudad() async {
    final elegida = await showModalBottomSheet<_EleccionCiudad>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: _scrim,
      shape: _bordeHoja,
      builder: (_) => _HojaCiudades(colportorId: widget.colportorId, elegida: _ciudadId),
    );
    if (elegida != null && mounted) setState(() => _ciudadId = elegida.id);
  }

  Future<void> _elegirProximidad() async {
    final elegida = await showModalBottomSheet<ProximidadLista>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      barrierColor: _scrim,
      shape: _bordeHoja,
      builder: (_) => _MarcoHoja(
        titulo: 'Proximidad',
        hijo: _OpcionesHoja<ProximidadLista>(
          elegida: _proximidad,
          opciones: [
            for (final p in ProximidadLista.values)
              _Opcion(valor: p, texto: FormatoListaUbicaciones.proximidad(p)),
          ],
        ),
      ),
    );
    if (elegida != null && mounted) setState(() => _proximidad = elegida);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const colores = ColoresColportaje.unica;
    final previa = ref
        .watch(
          previsualizacionFiltrosProvider((
            colportorId: widget.colportorId,
            filtros: _borrador,
            posicion: widget.posicion,
          )),
        )
        .value;
    if (previa != null) _ultima = previa;
    final lista = _ultima;
    final grande = textoGrande(context);
    final nombreCiudad = _nombreCiudad();

    Widget rotulo(String texto) => Semantics(
      header: true,
      child: Text(
        texto,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 10,
          letterSpacing: 1.4,
          color: colores.gris,
        ),
      ),
    );

    final tipos = [
      for (final t in TipoUbicacion.values)
        _FichaTipo(
          texto: FormatoUbicaciones.tipo(t),
          cantidad: lista?.porTipo[t],
          elegida: _tipos.contains(t),
          alPresionar: () => _alternarTipo(t),
        ),
    ];

    final ciudad = _CampoSelector(
      rotulo: 'CIUDAD',
      valor: nombreCiudad,
      alPresionar: _elegirCiudad,
    );
    final proximidad = _CampoSelector(
      rotulo: 'PROXIMIDAD',
      valor: _hayGps
          ? FormatoListaUbicaciones.proximidad(_proximidad)
          : TextosFiltrosLista.necesitaGps,
      alPresionar: _hayGps ? _elegirProximidad : null,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Asa(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Semantics(
                        header: true,
                        child: const Text(
                          'Filtros',
                          style: TextStyle(
                            fontFamily: 'SourceSerif4',
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _limpiar,
                        style: TextButton.styleFrom(
                          foregroundColor: ColoresLista.azul,
                          minimumSize: const Size(48, 48),
                          textStyle: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Limpiar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  rotulo('TIPO'),
                  const SizedBox(height: 8),
                  if (grande)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final t in tipos) ...[t, const SizedBox(height: 8)],
                      ],
                    )
                  else
                    Row(
                      children: [
                        for (var i = 0; i < tipos.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(child: tipos[i]),
                        ],
                      ],
                    ),
                  // Sin `house_status` local todavía no se sabe el estado de ninguna casa: el filtro
                  // no se ofrece (si no, todo filtro por estado daría una lista vacía).
                  if (lista?.estadosConocidos ?? false) ...[
                    const SizedBox(height: 14),
                    rotulo('ESTADO DE LA CASA'),
                    const SizedBox(height: 8),
                    _GrillaEstados(
                      grande: grande,
                      elegidos: _estados,
                      cantidades: lista!.porEstado,
                      alAlternar: _alternarEstado,
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (grande) ...[
                    ciudad,
                    const SizedBox(height: 10),
                    proximidad,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: ciudad),
                        const SizedBox(width: 10),
                        Expanded(child: proximidad),
                      ],
                    ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    key: const Key('hoja_filtros_bajas'),
                    contentPadding: EdgeInsets.zero,
                    value: _bajas,
                    onChanged: (v) => setState(() => _bajas = v),
                    title: Text('Mostrar bajas', style: theme.textTheme.bodyLarge),
                    activeTrackColor: theme.colorScheme.primary,
                    inactiveTrackColor: ColoresLista.grisBorde,
                    inactiveThumbColor: Colors.white,
                    trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
            child: FilledButton(
              key: const Key('hoja_filtros_ver'),
              onPressed: _ver,
              child: Text(
                lista == null
                    ? 'Ver ubicaciones'
                    : FormatoListaUbicaciones.verUbicaciones(lista.total),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// El nombre de la ciudad elegida para el campo; «Todas» si no hay ninguna.
  String _nombreCiudad() {
    final id = _ciudadId;
    if (id == null) return TextosFiltrosLista.todasLasCiudades;
    return FormatoListaUbicaciones.ciudad(
      ref.watch(ciudadesListaProvider(widget.colportorId)).value,
      id,
    );
  }
}

/// La barrita para arrastrar de arriba de toda hoja.
class _Asa extends StatelessWidget {
  const _Asa();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 8),
    child: Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: ColoresLista.grisBorde,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

/// El marco de las hojas chicas (orden, proximidad, ciudad): asa, título y contenido.
class _MarcoHoja extends StatelessWidget {
  const _MarcoHoja({required this.titulo, required this.hijo});

  final String titulo;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Asa(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Semantics(
              header: true,
              child: Text(
                titulo,
                style: const TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Flexible(child: hijo),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _Opcion<T> {
  const _Opcion({required this.valor, required this.texto, this.detalle, this.habilitada = true});

  final T valor;
  final String texto;

  /// Una segunda línea (por ejemplo «Necesita GPS» en una opción deshabilitada).
  final String? detalle;
  final bool habilitada;
}

/// Una lista de opciones de una sola elección: la elegida lleva un «✓», la deshabilitada no se
/// puede tocar. Cierra la hoja devolviendo el valor.
class _OpcionesHoja<T> extends StatefulWidget {
  const _OpcionesHoja({required this.opciones, required this.elegida});

  final List<_Opcion<T>> opciones;
  final T elegida;

  @override
  State<_OpcionesHoja<T>> createState() => _OpcionesHojaState<T>();
}

class _OpcionesHojaState<T> extends State<_OpcionesHoja<T>> {
  var _cerrando = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        for (final o in widget.opciones)
          _FilaOpcion(
            texto: o.texto,
            detalle: o.detalle,
            elegida: o.valor == widget.elegida,
            alPresionar: o.habilitada
                ? () {
                    if (_cerrando) return;
                    _cerrando = true;
                    Navigator.of(context).pop(o.valor);
                  }
                : null,
          ),
      ],
    );
  }
}

class _FilaOpcion extends StatelessWidget {
  const _FilaOpcion({
    required this.texto,
    required this.elegida,
    required this.alPresionar,
    this.detalle,
  });

  final String texto;
  final String? detalle;
  final bool elegida;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const colores = ColoresColportaje.unica;
    final habilitada = alPresionar != null;
    return Semantics(
      button: true,
      enabled: habilitada,
      selected: elegida,
      label: detalle == null ? texto : '$texto. $detalle',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: alPresionar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      elegida ? '✓' : '',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          texto,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: elegida ? FontWeight.w600 : null,
                            color: habilitada ? null : colores.gris,
                          ),
                        ),
                        if (detalle != null)
                          Text(
                            detalle!,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12.5,
                              color: colores.gris,
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
      ),
    );
  }
}

/// Una ficha de tipo con su contador («✓ Casa 8»). La elegida va en navy.
class _FichaTipo extends StatelessWidget {
  const _FichaTipo({
    required this.texto,
    required this.cantidad,
    required this.elegida,
    required this.alPresionar,
  });

  final String texto;
  final int? cantidad;
  final bool elegida;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    const colores = ColoresColportaje.unica;
    return Semantics(
      checked: elegida,
      label: cantidad == null ? texto : '$texto, $cantidad',
      child: ExcludeSemantics(
        child: Material(
          color: elegida ? navy : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: elegida ? navy : ColoresLista.grisBorde, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: alPresionar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      elegida ? '✓ $texto' : texto,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: elegida ? FontWeight.w600 : FontWeight.w400,
                        color: elegida ? Colors.white : ColoresLista.grisTexto,
                      ),
                    ),
                    if (cantidad != null)
                      Text(
                        '$cantidad',
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 11.5,
                          color: elegida ? const Color(0xFFC9D6EA) : colores.gris,
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

/// Los ocho estados de la casa como casillas de a dos (de a uno con el texto muy grande), cada una
/// con su insignia y el contador.
class _GrillaEstados extends StatelessWidget {
  const _GrillaEstados({
    required this.grande,
    required this.elegidos,
    required this.cantidades,
    required this.alAlternar,
  });

  final bool grande;
  final Set<EstadoCasa> elegidos;
  final Map<EstadoCasa, int> cantidades;
  final ValueChanged<EstadoCasa> alAlternar;

  @override
  Widget build(BuildContext context) {
    final casillas = [
      for (final e in EstadoCasa.values)
        _CasillaEstado(
          estado: e,
          cantidad: cantidades[e] ?? 0,
          elegida: elegidos.contains(e),
          alPresionar: () => alAlternar(e),
        ),
    ];
    if (grande) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in casillas) ...[c, const SizedBox(height: 8)],
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < casillas.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          // Las dos casillas de la fila miden lo mismo, aunque una dé más renglones.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: casillas[i]),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < casillas.length ? casillas[i + 1] : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CasillaEstado extends StatelessWidget {
  const _CasillaEstado({
    required this.estado,
    required this.cantidad,
    required this.elegida,
    required this.alPresionar,
  });

  final EstadoCasa estado;
  final int cantidad;
  final bool elegida;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    const colores = ColoresColportaje.unica;
    final rotulo = FormatoListaUbicaciones.estado(estado);
    return Semantics(
      checked: elegida,
      label: '$rotulo, $cantidad',
      child: ExcludeSemantics(
        child: Material(
          color: elegida ? ColoresLista.azulFondo : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: elegida ? navy : colores.borde, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: alPresionar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: elegida ? navy : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: elegida ? null : Border.all(color: colores.gris, width: 1.5),
                      ),
                      child: elegida
                          ? const Text(
                              '✓',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 9),
                    InsigniaEstadoCasa(estado: estado, tamano: 20),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        rotulo,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12.5,
                          height: 1.2,
                          fontWeight: elegida ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      '$cantidad',
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 11.5,
                        color: colores.gris,
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

/// «CIUDAD» y «PROXIMIDAD»: un rótulo, y un campo con el valor y la flecha. Sin [alPresionar] se ve
/// deshabilitado.
class _CampoSelector extends StatelessWidget {
  const _CampoSelector({required this.rotulo, required this.valor, required this.alPresionar});

  final String rotulo;
  final String valor;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    const colores = ColoresColportaje.unica;
    final habilitado = alPresionar != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          rotulo,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 1.4,
            color: colores.gris,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          enabled: habilitado,
          label: '$rotulo: $valor',
          child: ExcludeSemantics(
            child: Material(
              color: habilitado ? Colors.transparent : ColoresLista.filaBaja,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: ColoresLista.grisBorde, width: 1.5),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: alPresionar,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            valor,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              color: habilitado ? null : colores.gris,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('▾', style: TextStyle(color: habilitado ? null : colores.gris)),
                      ],
                    ),
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

/// Lo que devuelve la hoja de ciudades: la ciudad elegida, o `null` en [id] si se eligió «Todas».
class _EleccionCiudad {
  const _EleccionCiudad(this.id);

  final String? id;
}

/// La lista de ciudades de la campaña con «Todas» arriba. Cargando, vacía y con error («Reintentar»,
/// como la hoja de ciudades del alta).
class _HojaCiudades extends ConsumerWidget {
  const _HojaCiudades({required this.colportorId, required this.elegida});

  final String colportorId;
  final String? elegida;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lectura = ref.watch(ciudadesListaProvider(colportorId));
    const colores = ColoresColportaje.unica;
    return _MarcoHoja(
      titulo: 'Ciudad',
      hijo: lectura.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        // `ciudadesListaProvider` no termina en error; por si un día lo hace, se ve igual que una falla.
        error: (_, _) => _ErrorCiudades(
          texto: const FailureInesperado().mensaje,
          alReintentar: () => ref.invalidate(ciudadesListaProvider(colportorId)),
        ),
        data: (resultado) => resultado.fold(
          (falla) => _ErrorCiudades(
            texto: mensajePara(falla, accion: 'ver las ciudades.'),
            alReintentar: () => ref.invalidate(ciudadesListaProvider(colportorId)),
          ),
          (ciudades) => ciudades.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(
                    TextosAlta.sinCiudades,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 13.5, color: colores.gris),
                  ),
                )
              : _OpcionesCiudad(elegida: elegida, ciudades: ciudades),
        ),
      ),
    );
  }
}

/// Las opciones de la hoja de ciudades: «Todas» y cada ciudad de la campaña.
class _OpcionesCiudad extends StatefulWidget {
  const _OpcionesCiudad({required this.elegida, required this.ciudades});

  final String? elegida;
  final List<CiudadCatalogo> ciudades;

  @override
  State<_OpcionesCiudad> createState() => _OpcionesCiudadState();
}

class _OpcionesCiudadState extends State<_OpcionesCiudad> {
  var _cerrando = false;

  void _elegir(String? id) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(_EleccionCiudad(id));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        _FilaOpcion(
          texto: TextosFiltrosLista.todasLasCiudades,
          elegida: widget.elegida == null,
          alPresionar: () => _elegir(null),
        ),
        for (final c in widget.ciudades)
          _FilaOpcion(
            texto: c.nombre,
            elegida: widget.elegida == c.id,
            alPresionar: () => _elegir(c.id),
          ),
      ],
    );
  }
}

class _ErrorCiudades extends StatelessWidget {
  const _ErrorCiudades({required this.texto, required this.alReintentar});

  final String texto;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4)),
          const SizedBox(height: 4),
          EnlaceAlta(texto: 'Reintentar', alPresionar: alReintentar),
        ],
      ),
    );
  }
}
