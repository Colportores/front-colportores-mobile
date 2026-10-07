import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/consulta_lista_ubicaciones.dart';
import '../../domain/entities/estado_casa.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/entities/ubicacion.dart';
import '../formato_lista_ubicaciones.dart';
import '../formato_ubicaciones.dart';
import '../providers/lista_ubicaciones_notifier.dart';
import '../providers/lista_ubicaciones_providers.dart';
import '../widgets/hoja_filtros_lista.dart';
import '../widgets/piezas_alta.dart' show AvisoAlta, ColoresAlta, EnlaceAlta;
import '../widgets/piezas_lista_ubicaciones.dart';
import 'alta_ubicacion_page.dart';

/// Los textos de la pantalla que el canvas no dibuja (el vacío, el «sin resultados» y el error de
/// lectura). Los del canvas están en cada widget.
abstract final class TextosListaUbicaciones {
  static const titulo = 'Ubicaciones';
  static const buscar = 'Buscar por calle y número';
  static const registrarPrimera = 'Registrar tu primera ubicación';
  static const vacioTitulo = 'Todavía no registraste ubicaciones';
  static const vacioCuerpo =
      'Las casas, los negocios y los edificios que registres aparecen acá y también en el mapa.';
  static const sinResultadosTitulo = 'Sin resultados';
  static const sinResultadosCuerpo = 'Ninguna ubicación cumple los filtros o la búsqueda.';
  static const limpiarFiltros = 'Limpiar filtros';
  static const errorLectura = 'No pudimos leer tus ubicaciones.';
  static const reintentar = 'Reintentar';
  static const cargando = 'Cargando ubicaciones';
  static const cargandoMas = 'Cargando 50 más…';
  static const nueva = 'Nueva';
}

/// La pestaña «Lista» (vista 05, HU-UBI-002): las ubicaciones del colportor con filtros combinables,
/// contadores, orden por cercanía, «Mostrar bajas», buscador y carga de a 50.
///
/// Vive dentro de la pantalla principal (`IndexedStack`): [activa] dice si la pestaña está a la
/// vista. El GPS se pide la primera vez que se abre, no al arrancar la app.
class ListaUbicacionesPage extends ConsumerStatefulWidget {
  const ListaUbicacionesPage({
    super.key,
    required this.colportorId,
    this.activa = true,
    this.alAbrirUbicacion,
    this.alRegistrar,
  });

  /// UUID del colportor con la sesión iniciada: la lista es «las que registré».
  final String colportorId;

  /// La pestaña está a la vista.
  final bool activa;

  /// Qué pasa al tocar una fila. `null` mientras no haya una pantalla de destino (las ubicaciones
  /// del espacio, vista 11): las filas se ven igual pero no se tocan.
  final ValueChanged<String>? alAbrirUbicacion;

  /// Cómo se abre el alta («Nueva» y «Registrar tu primera ubicación»). Por defecto abre
  /// `AltaUbicacionPage`; un test lo reemplaza.
  final Future<void> Function()? alRegistrar;

  @override
  ConsumerState<ListaUbicacionesPage> createState() => _ListaUbicacionesPageState();
}

class _ListaUbicacionesPageState extends ConsumerState<ListaUbicacionesPage>
    with WidgetsBindingObserver {
  final _busqueda = TextEditingController();
  Timer? _espera;

  /// Una sola hoja de filtros y una sola alta a la vez: un segundo toque no abre otra encima.
  var _abriendoHoja = false;
  var _abriendoAlta = false;

  ListaUbicacionesNotifier get _notificador =>
      ref.read(listaUbicacionesProvider(widget.colportorId).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.activa) WidgetsBinding.instance.addPostFrameCallback((_) => _alAbrirPestana());
  }

  @override
  void didUpdateWidget(ListaUbicacionesPage anterior) {
    super.didUpdateWidget(anterior);
    // Cambiar un provider durante la construcción no se permite: se pide el GPS al terminar el
    // cuadro.
    if (widget.activa && !anterior.activa) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _alAbrirPestana());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _espera?.cancel();
    _busqueda.dispose();
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

  void _alEscribir(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _notificador.buscar(texto);
    });
  }

  void _buscarYa(String texto) {
    _espera?.cancel();
    _notificador.buscar(texto);
  }

  Future<void> _abrirFiltros(ListaUbicacionesState estado) async {
    if (_abriendoHoja) return;
    _abriendoHoja = true;
    try {
      final elegidos = await mostrarHojaFiltrosLista(
        context,
        colportorId: widget.colportorId,
        actuales: estado.filtros,
        posicion: estado.posicion,
      );
      if (elegidos == null || !mounted) return;
      _notificador.aplicar(
        tipos: elegidos.tipos,
        estados: elegidos.estados,
        ciudadId: elegidos.ciudadId,
        proximidad: elegidos.proximidad,
        incluirBajas: elegidos.incluirBajas,
      );
    } finally {
      _abriendoHoja = false;
    }
  }

  Future<void> _abrirOrden(ListaUbicacionesState estado, OrdenListaUbicaciones actual) async {
    if (_abriendoHoja) return;
    _abriendoHoja = true;
    try {
      final elegido = await mostrarHojaOrdenLista(
        context,
        actual: actual,
        hayGps: estado.posicion != null,
      );
      if (elegido != null && mounted) _notificador.ordenar(elegido);
    } finally {
      _abriendoHoja = false;
    }
  }

  Future<void> _registrar() async {
    if (_abriendoAlta) return;
    _abriendoAlta = true;
    try {
      final personalizado = widget.alRegistrar;
      if (personalizado != null) {
        await personalizado();
      } else {
        await AltaUbicacionPage.abrir(context, colportorId: widget.colportorId);
      }
    } finally {
      _abriendoAlta = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final proveedor = listaUbicacionesProvider(widget.colportorId);
    final estado = ref.watch(proveedor);
    // «Limpiar filtros» también vacía la búsqueda: el campo tiene que seguirla.
    ref.listen(proveedor.select((s) => s.filtros.busqueda), (_, texto) {
      if (_busqueda.text != texto) _busqueda.text = texto;
    });
    final ahora = ref.watch(relojListaUbicacionesProvider)();
    final lista = estado.lista;
    final sinUbicaciones = lista?.sinUbicaciones ?? false;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cabecera(
              estado: estado,
              busqueda: _busqueda,
              alEscribir: _alEscribir,
              alEnviar: _buscarYa,
              alActivarGps: () => unawaited(_notificador.activarGps()),
            ),
            _FilaFiltros(
              estado: estado,
              colportorId: widget.colportorId,
              alAbrirFiltros: () => unawaited(_abrirFiltros(estado)),
              notificador: _notificador,
            ),
            if (lista != null && !sinUbicaciones)
              _FilaContador(
                lista: lista,
                alAbrirOrden: () => unawaited(_abrirOrden(estado, lista.ordenAplicado)),
              ),
            if (estado.fallaLectura && lista != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _AvisoLectura(alReintentar: _notificador.reintentar),
              ),
            Expanded(
              child: _Cuerpo(
                estado: estado,
                ahora: ahora,
                alAbrirUbicacion: widget.alAbrirUbicacion,
                alRegistrar: () => unawaited(_registrar()),
                notificador: _notificador,
              ),
            ),
          ],
        ),
        if (!sinUbicaciones)
          Positioned(
            right: 16,
            bottom: 16,
            child: _BotonNueva(alPresionar: () => unawaited(_registrar())),
          ),
      ],
    );
  }
}

/// El título con el GPS, y el buscador.
class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.estado,
    required this.busqueda,
    required this.alEscribir,
    required this.alEnviar,
    required this.alActivarGps,
  });

  final ListaUbicacionesState estado;
  final TextEditingController busqueda;
  final ValueChanged<String> alEscribir;
  final ValueChanged<String> alEnviar;
  final VoidCallback alActivarGps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  TextosListaUbicaciones.titulo,
                  style: TextStyle(
                    fontFamily: 'SourceSerif4',
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _ChipGps(estado: estado, alActivar: alActivarGps),
            ],
          ),
          const SizedBox(height: 8),
          _CampoBusqueda(controlador: busqueda, alEscribir: alEscribir, alEnviar: alEnviar),
        ],
      ),
    );
  }
}

/// «◎ GPS ±8 m», o el estado del GPS si no hay lectura.
class _ChipGps extends StatelessWidget {
  const _ChipGps({required this.estado, required this.alActivar});

  final ListaUbicacionesState estado;
  final VoidCallback alActivar;

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: ColoresLista.grisTexto);
    final lectura = estado.lectura;
    switch (estado.gps) {
      case EstadoGpsLista.sinPedir:
        return const SizedBox.shrink();
      case EstadoGpsLista.buscando when lectura == null:
        return const Text('◎ Buscando GPS…', style: estilo);
      case EstadoGpsLista.sinGps:
        return Semantics(
          button: true,
          label: 'Sin GPS. Activar GPS',
          child: ExcludeSemantics(
            child: TextButton(
              onPressed: alActivar,
              style: TextButton.styleFrom(
                foregroundColor: ColoresLista.azul,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: estilo.copyWith(fontWeight: FontWeight.w600),
              ),
              child: const Text('◎ Sin GPS'),
            ),
          ),
        );
      default:
        return Text(
          lectura == null ? '◎ GPS' : FormatoListaUbicaciones.gps(lectura.precisionMetros),
          style: estilo,
        );
    }
  }
}

class _CampoBusqueda extends StatelessWidget {
  const _CampoBusqueda({
    required this.controlador,
    required this.alEscribir,
    required this.alEnviar,
  });

  final TextEditingController controlador;
  final ValueChanged<String> alEscribir;
  final ValueChanged<String> alEnviar;

  @override
  Widget build(BuildContext context) {
    const colores = ColoresColportaje.unica;
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: ColoresLista.grisBorde, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(Icons.search, size: 20, color: colores.gris)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('lista_busqueda'),
              controller: controlador,
              onChanged: alEscribir,
              onSubmitted: alEnviar,
              textInputAction: TextInputAction.search,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: TextosListaUbicaciones.buscar,
                hintStyle: theme.textTheme.bodyLarge?.copyWith(color: colores.gris),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                // El campo en sí llega a 48 de alto (el borde del contenedor va aparte).
                constraints: const BoxConstraints(minHeight: 48),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controlador,
            builder: (context, _) => controlador.text.isEmpty
                ? const SizedBox(width: 14)
                : IconButton(
                    key: const Key('lista_busqueda_borrar'),
                    tooltip: 'Borrar búsqueda',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      controlador.clear();
                      alEnviar('');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// «☷ Filtros» y los filtros activos como chips (cada uno se quita con un toque).
class _FilaFiltros extends StatelessWidget {
  const _FilaFiltros({
    required this.estado,
    required this.colportorId,
    required this.alAbrirFiltros,
    required this.notificador,
  });

  final ListaUbicacionesState estado;
  final String colportorId;
  final VoidCallback alAbrirFiltros;
  final ListaUbicacionesNotifier notificador;

  @override
  Widget build(BuildContext context) {
    final f = estado.filtros;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          BotonFiltrosLista(cantidad: f.cantidadActivos, alPresionar: alAbrirFiltros),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Consumer(
                builder: (context, ref, _) {
                  final ciudades = f.ciudadId == null
                      ? null
                      : ref.watch(ciudadesListaProvider(colportorId)).value;
                  return Row(
                    children: [
                      for (final t in TipoUbicacion.values)
                        if (f.tipos.contains(t))
                          _Chip(
                            texto: FormatoUbicaciones.tipo(t),
                            alQuitar: () => notificador.quitarTipo(t),
                          ),
                      for (final e in EstadoCasa.values)
                        if (f.estados.contains(e))
                          _Chip(
                            texto: FormatoListaUbicaciones.estado(e),
                            alQuitar: () => notificador.quitarEstado(e),
                          ),
                      if (f.ciudadId != null)
                        _Chip(
                          texto: FormatoListaUbicaciones.ciudad(ciudades, f.ciudadId!),
                          alQuitar: notificador.quitarCiudad,
                        ),
                      if (f.proximidad != ProximidadLista.cualquiera)
                        _Chip(
                          texto: FormatoListaUbicaciones.chipProximidad(f.proximidad),
                          alQuitar: notificador.quitarProximidad,
                        ),
                      if (f.incluirBajas)
                        _Chip(texto: 'Con bajas', alQuitar: notificador.quitarBajas),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto, required this.alQuitar});

  final String texto;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: ChipFiltroLista(texto: texto, alQuitar: alQuitar),
  );
}

/// «8 de 30 · 3 bajas» y el orden.
class _FilaContador extends StatelessWidget {
  const _FilaContador({required this.lista, required this.alAbrirOrden});

  final ListaUbicaciones lista;
  final VoidCallback alAbrirOrden;

  @override
  Widget build(BuildContext context) {
    const colores = ColoresColportaje.unica;
    final orden = lista.ordenAplicado == OrdenListaUbicaciones.cercania
        ? TextosFiltrosLista.ordenCercania
        : TextosFiltrosLista.ordenRecientes;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colores.borde)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              FormatoListaUbicaciones.contador(lista),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Ordenar: $orden',
            child: ExcludeSemantics(
              child: InkWell(
                key: const Key('lista_orden'),
                onTap: alAbrirOrden,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      '$orden ▾',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ColoresLista.azul,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que ocupa el resto de la pantalla: cargando, error, vacío, sin resultados o las filas.
class _Cuerpo extends StatelessWidget {
  const _Cuerpo({
    required this.estado,
    required this.ahora,
    required this.alAbrirUbicacion,
    required this.alRegistrar,
    required this.notificador,
  });

  final ListaUbicacionesState estado;
  final DateTime ahora;
  final ValueChanged<String>? alAbrirUbicacion;
  final VoidCallback alRegistrar;
  final ListaUbicacionesNotifier notificador;

  @override
  Widget build(BuildContext context) {
    final lista = estado.lista;
    if (lista == null) {
      if (estado.fallaLectura) {
        return _Centrado(
          children: [
            const Text(TextosListaUbicaciones.errorLectura, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            EnlaceAlta(
              texto: TextosListaUbicaciones.reintentar,
              alPresionar: notificador.reintentar,
            ),
          ],
        );
      }
      return Semantics(
        label: TextosListaUbicaciones.cargando,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (lista.sinUbicaciones) {
      return _Centrado(
        children: [
          Semantics(
            header: true,
            child: const Text(
              TextosListaUbicaciones.vacioTitulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SourceSerif4',
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(TextosListaUbicaciones.vacioCuerpo, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('lista_registrar_primera'),
            onPressed: alRegistrar,
            child: const Text(TextosListaUbicaciones.registrarPrimera, textAlign: TextAlign.center),
          ),
        ],
      );
    }
    if (lista.sinResultados) {
      return _Centrado(
        children: [
          Semantics(
            header: true,
            child: const Text(
              TextosListaUbicaciones.sinResultadosTitulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SourceSerif4',
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(TextosListaUbicaciones.sinResultadosCuerpo, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('lista_limpiar_filtros'),
            onPressed: notificador.limpiarTodo,
            child: const Text(TextosListaUbicaciones.limpiarFiltros),
          ),
        ],
      );
    }
    final items = lista.items;
    return ListView.builder(
      key: const Key('lista_filas'),
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length + (lista.hayMas ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == items.length) {
          return _PieCargandoMas(key: const ValueKey('pie'), alLlegar: notificador.cargarMas);
        }
        final item = items[i];
        final id = item.ubicacion.id;
        return FilaUbicacionLista(
          key: ValueKey(id),
          item: item,
          lista: lista,
          ahora: ahora,
          alTocar: alAbrirUbicacion == null ? null : () => alAbrirUbicacion!(id),
        );
      },
    );
  }
}

/// El texto centrado de los estados sin filas (cargando aparte).
class _Centrado extends StatelessWidget {
  const _Centrado({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

/// El pie «Cargando 50 más…»: cuando entra en pantalla pide la página siguiente.
class _PieCargandoMas extends StatefulWidget {
  const _PieCargandoMas({super.key, required this.alLlegar});

  final VoidCallback alLlegar;

  @override
  State<_PieCargandoMas> createState() => _PieCargandoMasState();
}

class _PieCargandoMasState extends State<_PieCargandoMas> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.alLlegar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const ExcludeSemantics(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                TextosListaUbicaciones.cargandoMas,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: ColoresColportaje.unica.gris,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El error de lectura con la lista ya a la vista: la última lista se conserva y se ofrece reintentar.
class _AvisoLectura extends StatelessWidget {
  const _AvisoLectura({required this.alReintentar});

  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return AvisoAlta(
      color: ColoresAlta.rojo,
      glyph: '!',
      texto: TextosListaUbicaciones.errorLectura,
      acciones: Align(
        alignment: Alignment.centerLeft,
        child: EnlaceAlta(texto: TextosListaUbicaciones.reintentar, alPresionar: alReintentar),
      ),
    );
  }
}

/// El botón flotante «+ Nueva».
class _BotonNueva extends StatelessWidget {
  const _BotonNueva({required this.alPresionar});

  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: 'Nueva ubicación',
      child: ExcludeSemantics(
        child: Material(
          key: const Key('lista_nueva'),
          color: navy,
          elevation: 4,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: alPresionar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 20, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('+', style: TextStyle(color: Colors.white, fontSize: 22, height: 1)),
                    SizedBox(width: 8),
                    Text(
                      TextosListaUbicaciones.nueva,
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
