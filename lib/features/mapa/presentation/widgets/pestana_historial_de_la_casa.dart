import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../agenda/domain/entities/visita.dart' show TipoResultadoVisita;
import '../../domain/entities/evento_de_la_casa.dart';
import '../../domain/services/historial_de_la_casa.dart';
import '../providers/historial_de_la_casa_providers.dart';
import '../providers/personas_providers.dart';
import '../textos_historial_de_la_casa.dart';
import 'hoja_detalle_de_visita.dart';
import 'piezas_alta.dart';

/// Las claves con que los tests (y el QA) encuentran lo que dibuja la pestaña Historial.
abstract final class ClavesHistorialDeLaCasa {
  static const pestana = Key('historial_casa_pestana');
  static const filtros = Key('historial_casa_filtros');
  static const lista = Key('historial_casa_lista');
  static const vacio = Key('historial_casa_vacio');
  static const sinResultados = Key('historial_casa_sin_resultados');
  static const verTodo = Key('historial_casa_ver_todo');
  static const verMas = Key('historial_casa_ver_mas');
  static const cargando = Key('historial_casa_cargando');
  static const error = Key('historial_casa_error');
  static const reintentar = Key('historial_casa_reintentar');
  static const aviso = Key('historial_casa_aviso');
  static Key filtro(FiltroDeLaCasa f) => Key('historial_casa_filtro_${f.name}');
  static Key fila(String id) => Key('historial_casa_fila_$id');
}

/// La pestaña **Historial** de la hoja arriba de la casa (vista 39, C·03 y C·04): todo lo que pasó en
/// el lugar —visitas, ventas y cobros—, de lo más nuevo a lo más viejo, con el símbolo del resultado y
/// los filtros Todo / Entrevistas / Ventas / Cobros. ✎ marca las visitas con nota y las entrevistas
/// muestran su duración (cuando la visita la guarde, #466).
///
/// - Tocar una visita o una venta abre su detalle (C·04). Tocar un cobro abre el detalle del cobro de la
///   vista 30 B por [verCobroDesdeLaCasaProvider]; sin ese destino la fila no se toca y no lleva «›».
/// - Cargando, vacío, filtro sin resultados y error al leer son estados propios. Sin conexión funciona
///   igual: todo sale del teléfono. Una casa dada de baja se lee igual (el historial no se esconde).
/// - Una sola cosa se abre a la vez: un doble toque sobre una fila, o un segundo toque sobre otra
///   mientras la primera se abre, no abre dos veces. Si abrir el cobro o la venta falla, el aviso queda
///   en la pestaña (no en un `SnackBar`: la hoja puede ser una ruta modal que lo taparía).
/// - «Ver la venta» del detalle de una venta abre las cuotas de ESA venta (vista 30 A) por
///   [verVentaDesdeLaCasaProvider].
///
/// **local-only — PII**: los nombres y las notas viven solo en el teléfono y no van a ningún log.
class PestanaHistorialDeLaCasa extends ConsumerStatefulWidget {
  const PestanaHistorialDeLaCasa({super.key, required this.espacioId, required this.direccion});

  /// El espacio (casa, negocio o depto) del que habla la hoja.
  final String espacioId;

  /// «Grecia 3310»: va en la segunda línea del detalle.
  final String direccion;

  /// Cuántas filas se dibujan antes de «Ver más».
  static const pagina = 30;

  @override
  ConsumerState<PestanaHistorialDeLaCasa> createState() => _PestanaHistorialDeLaCasaState();
}

class _PestanaHistorialDeLaCasaState extends ConsumerState<PestanaHistorialDeLaCasa> {
  var _filtro = FiltroDeLaCasa.todo;
  var _mostrar = PestanaHistorialDeLaCasa.pagina;

  /// Ya se está abriendo algo (un detalle o el cobro): un segundo toque no abre otro encima. Es un
  /// campo: corta aunque el toque llegue antes de que se vuelva a dibujar.
  var _abriendo = false;

  /// El aviso de que no se pudo abrir el cobro o la venta; `null` sin aviso.
  String? _noPudimosAbrir;

  /// Dónde está el aviso, para desplazar la hoja hasta él.
  final _lugarDelAviso = GlobalKey();

  void _elegirFiltro(FiltroDeLaCasa filtro) {
    if (filtro == _filtro) return;
    setState(() {
      _filtro = filtro;
      _mostrar = PestanaHistorialDeLaCasa.pagina;
    });
  }

  Future<void> _abrir(EventoDeLaCasa evento) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      if (_noPudimosAbrir != null) setState(() => _noPudimosAbrir = null);
      switch (evento) {
        case CobroDeLaCasa():
          await _abrirElCobro(evento);
        case VisitaDeLaCasa() || VentaDeLaCasa():
          await _abrirElDetalle(evento);
      }
    } finally {
      _abriendo = false;
    }
  }

  Future<void> _abrirElCobro(CobroDeLaCasa cobro) async {
    final ver = ref.read(verCobroDesdeLaCasaProvider);
    if (ver == null) return;
    try {
      await Future<Object?>.sync(() => ver(cobro.id));
    } on Object {
      // Nada de la excepción al aviso: puede traer datos de la persona (convenciones §7.5).
      _avisar(TextosHistorialDeLaCasa.noPudimosAbrirElCobro);
    }
  }

  /// Muestra el aviso arriba de las filas y desplaza la hoja hasta él: la hoja quedó donde estaba la
  /// fila tocada y, con letra grande o una lista larga, el aviso quedaría fuera de la vista (QA #446).
  void _avisar(String texto) {
    if (!mounted) return;
    setState(() => _noPudimosAbrir = texto);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lugar = _lugarDelAviso.currentContext;
      if (!mounted || lugar == null) return;
      Scrollable.ensureVisible(lugar);
    });
  }

  Future<void> _abrirElDetalle(EventoDeLaCasa evento) async {
    final ahora = ref.read(relojPersonaProvider)();
    final verVenta = ref.read(verVentaDesdeLaCasaProvider);
    final accion = await mostrarHojaDetalleDeVisita(
      context,
      evento: evento,
      direccion: widget.direccion,
      ahora: ahora,
      conVerLaVenta: verVenta != null,
    );
    if (!mounted ||
        accion != AccionDelDetalle.verLaVenta ||
        verVenta == null ||
        evento is! VentaDeLaCasa) {
      return;
    }
    // La venta tocada, no otra de la casa: su `id`, el espacio de la hoja y su cliente.
    final venta = (
      ventaId: evento.id,
      espacioId: widget.espacioId,
      espacioPersonaId: evento.espacioPersonaId,
    );
    try {
      await Future<Object?>.sync(() => verVenta(venta));
    } on Object {
      _avisar(TextosHistorialDeLaCasa.noPudimosAbrirLaVenta);
    }
  }

  void _reintentarLectura() => ref.invalidate(historialDeLaCasaProvider(widget.espacioId));

  @override
  Widget build(BuildContext context) {
    final historial = ref.watch(historialDeLaCasaProvider(widget.espacioId));
    final ahora = ref.watch(relojPersonaProvider)();
    final verCobro = ref.watch(verCobroDesdeLaCasaProvider);

    final List<Widget> cuerpo;
    if (historial.hasError) {
      cuerpo = [
        AvisoAlta(
          key: ClavesHistorialDeLaCasa.error,
          color: ColoresAlta.rojo,
          glyph: '!',
          texto: TextosHistorialDeLaCasa.noPudimosLeer,
          acciones: Align(
            alignment: Alignment.centerLeft,
            child: EnlaceAlta(
              key: ClavesHistorialDeLaCasa.reintentar,
              texto: TextosHistorialDeLaCasa.reintentar,
              alPresionar: _reintentarLectura,
            ),
          ),
        ),
      ];
    } else if (!historial.hasValue) {
      cuerpo = const [_CargandoHistorial()];
    } else {
      final todos = historial.requireValue;
      if (todos.isEmpty) {
        cuerpo = const [_VacioHistorial()];
      } else {
        final filtrados = FiltroDelHistorialDeLaCasa.aplicar(todos, _filtro);
        final visibles = filtrados.length <= _mostrar ? filtrados : filtrados.sublist(0, _mostrar);
        final faltan = filtrados.length - visibles.length;
        cuerpo = [
          _FiltrosDelHistorial(elegido: _filtro, alElegir: _elegirFiltro),
          if (filtrados.isEmpty)
            _SinResultados(filtro: _filtro, alVerTodo: () => _elegirFiltro(FiltroDeLaCasa.todo)),
          Column(
            key: ClavesHistorialDeLaCasa.lista,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              for (final e in visibles)
                FilaDelHistorialDeLaCasa(
                  key: ClavesHistorialDeLaCasa.fila(e.id),
                  evento: e,
                  ahora: ahora,
                  alTocar: e is CobroDeLaCasa && verCobro == null ? null : () => _abrir(e),
                ),
            ],
          ),
          if (faltan > 0)
            Align(
              child: TextButton(
                key: ClavesHistorialDeLaCasa.verMas,
                onPressed: () => setState(() => _mostrar += PestanaHistorialDeLaCasa.pagina),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: ColoresAlta.azul,
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                child: Text(TextosHistorialDeLaCasa.verMas(faltan)),
              ),
            ),
        ];
      }
    }

    return Column(
      key: ClavesHistorialDeLaCasa.pestana,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        if (_noPudimosAbrir case final texto?)
          KeyedSubtree(
            key: _lugarDelAviso,
            child: AvisoAlta(
              key: ClavesHistorialDeLaCasa.aviso,
              color: ColoresAlta.rojo,
              glyph: '!',
              texto: texto,
            ),
          ),
        ...cuerpo,
      ],
    );
  }
}

/// Los filtros del historial (canvas, `Bloques` · chips): «Todo / Entrevistas / Ventas / Cobros», uno
/// solo elegido, con un objetivo táctil de 48 dp.
class _FiltrosDelHistorial extends StatelessWidget {
  const _FiltrosDelHistorial({required this.elegido, required this.alElegir});

  final FiltroDeLaCasa elegido;
  final ValueChanged<FiltroDeLaCasa> alElegir;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: TextosHistorialDeLaCasa.filtroDelHistorial,
      child: Wrap(
        key: ClavesHistorialDeLaCasa.filtros,
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final f in FiltroDeLaCasa.values)
            _OpcionDelFiltro(filtro: f, elegida: f == elegido, alTocar: () => alElegir(f)),
        ],
      ),
    );
  }
}

class _OpcionDelFiltro extends StatelessWidget {
  const _OpcionDelFiltro({required this.filtro, required this.elegida, required this.alTocar});

  final FiltroDeLaCasa filtro;
  final bool elegida;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: elegida,
      inMutuallyExclusiveGroup: true,
      label: TextosHistorialDeLaCasa.lectorDelFiltro(filtro, elegido: elegida),
      onTap: alTocar,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Center(
          widthFactor: 1,
          child: Material(
            color: elegida ? const Color(0xFF002856) : Colors.white,
            shape: StadiumBorder(
              side: BorderSide(color: elegida ? const Color(0xFF002856) : ColoresAlta.grisBorde),
            ),
            child: InkWell(
              key: ClavesHistorialDeLaCasa.filtro(filtro),
              customBorder: const StadiumBorder(),
              onTap: alTocar,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  TextosHistorialDeLaCasa.etiquetaDelFiltro(filtro),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: elegida ? FontWeight.w600 : FontWeight.w500,
                    color: elegida ? Colors.white : ColoresAlta.tinta,
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

/// Una fila del historial (canvas, `Bloques` · card): el símbolo del resultado, la línea chica de
/// arriba, el título y, si hay, la de abajo; con «›» si se puede tocar.
class FilaDelHistorialDeLaCasa extends StatelessWidget {
  const FilaDelHistorialDeLaCasa({
    super.key,
    required this.evento,
    required this.ahora,
    this.alTocar,
  });

  final EventoDeLaCasa evento;
  final DateTime ahora;

  /// Lo que pasa al tocar la fila; `null`: no se toca y no lleva «›».
  final VoidCallback? alTocar;

  /// El símbolo, el color y la forma de cada tipo, los del mapa: círculo para lo que pasó en la
  /// visita y cuadrado redondeado para lo que se vendió o se cobró.
  static ({String glyph, Color fondo, bool circulo}) _simbolo(EventoDeLaCasa e) => switch (e) {
    VisitaDeLaCasa(:final resultado) => switch (resultado) {
      TipoResultadoVisita.entrevista => (glyph: '✓', fondo: ColoresAlta.verde, circulo: true),
      TipoResultadoVisita.noContesto => (glyph: '–', fondo: const Color(0xFF6B7688), circulo: true),
      TipoResultadoVisita.rechazo => (glyph: '✕', fondo: ColoresAlta.rojo, circulo: true),
      TipoResultadoVisita.cobranza => (glyph: r'$', fondo: ColoresAlta.azul, circulo: false),
      TipoResultadoVisita.venta => (glyph: '★', fondo: ColoresAlta.verde, circulo: false),
    },
    VentaDeLaCasa() => (glyph: '★', fondo: ColoresAlta.verde, circulo: false),
    CobroDeLaCasa() => (glyph: r'$', fondo: ColoresAlta.azul, circulo: false),
  };

  @override
  Widget build(BuildContext context) {
    final simbolo = _simbolo(evento);
    final sub = FormatoHistorialDeLaCasa.subtitulo(evento);
    final cuadro = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E7EE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: simbolo.fondo,
                shape: simbolo.circulo ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: simbolo.circulo ? null : BorderRadius.circular(6),
              ),
              child: Text(
                simbolo.glyph,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  FormatoHistorialDeLaCasa.antetitulo(evento, ahora),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: ColoresAlta.gris,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  FormatoHistorialDeLaCasa.titulo(evento),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: ColoresAlta.gris, height: 1.3),
                  ),
              ],
            ),
          ),
          if (alTocar != null)
            const Padding(
              padding: EdgeInsets.only(left: 8, top: 4),
              child: ExcludeSemantics(
                child: Icon(Icons.chevron_right, color: ColoresAlta.gris, size: 22),
              ),
            ),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: alTocar != null,
      onTap: alTocar,
      label: FormatoHistorialDeLaCasa.paraLector(evento, ahora),
      excludeSemantics: true,
      child: alTocar == null
          ? cuadro
          : InkWell(onTap: alTocar, borderRadius: BorderRadius.circular(14), child: cuadro),
    );
  }
}

/// El historial que todavía no llegó: tres tarjetas grises. Lo dice el lector de pantalla.
class _CargandoHistorial extends StatelessWidget {
  const _CargandoHistorial();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ClavesHistorialDeLaCasa.cargando,
      liveRegion: true,
      label: TextosHistorialDeLaCasa.cargando,
      child: ExcludeSemantics(
        child: Column(
          spacing: 8,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                height: 64,
                decoration: BoxDecoration(
                  color: ColoresAlta.grisFondo,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// La casa sin nada que mostrar: un ícono, qué pasa y qué hacer.
class _VacioHistorial extends StatelessWidget {
  const _VacioHistorial();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: ClavesHistorialDeLaCasa.vacio,
      padding: const EdgeInsets.fromLTRB(0, 28, 0, 12),
      child: Column(
        children: [
          Icon(Icons.history, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            TextosHistorialDeLaCasa.vacioTitulo,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            TextosHistorialDeLaCasa.vacioAyuda,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Hay historial, pero el filtro elegido no deja ninguna fila: lo dice y ofrece volver a «Todo».
class _SinResultados extends StatelessWidget {
  const _SinResultados({required this.filtro, required this.alVerTodo});

  final FiltroDeLaCasa filtro;
  final VoidCallback alVerTodo;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ClavesHistorialDeLaCasa.sinResultados,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            TextosHistorialDeLaCasa.sinResultados(filtro),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        EnlaceAlta(
          key: ClavesHistorialDeLaCasa.verTodo,
          texto: TextosHistorialDeLaCasa.verTodo,
          alPresionar: alVerTodo,
        ),
      ],
    );
  }
}
