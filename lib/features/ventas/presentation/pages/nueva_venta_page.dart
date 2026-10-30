import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../catalogo/domain/entities/catalogo_local.dart';
import '../../../catalogo/domain/entities/ciudad_consultable.dart' show CampaniaTerminada;
import '../../../catalogo/domain/entities/item_de_precio.dart';
import '../../../catalogo/domain/services/resolvedor_de_precios.dart';
import '../../../catalogo/presentation/providers/precios_providers.dart'
    show catalogoDePreciosProvider;
import '../../domain/entities/componente_vendido.dart';
import '../../domain/entities/linea_de_venta.dart';
import '../../domain/entities/nueva_venta.dart';
import '../../domain/entities/precios_de_la_venta.dart';
import '../../domain/repositories/venta_repository.dart';
import '../formato_venta.dart';
import '../providers/nueva_venta_notifier.dart';
import '../providers/ventas_providers.dart';
import '../widgets/piezas_venta.dart';
import '../widgets/selector_de_productos.dart';
import 'agregar_productos_page.dart';
import 'armar_coleccion_page.dart';

/// Registrar una venta (vista 27, HU-VEN-001): talonario, lo que se vende (colecciones armadas con
/// los libros que elige la colportora y productos sueltos), el monto —que se puede cambiar a mano— y
/// «Registrar venta».
///
/// Devuelve la [VentaGuardada] al cerrarse con la venta registrada; `null` si se sale sin registrar.
/// [antesDeGuardar] corre en la misma transacción que la venta (el cierre de la entrevista, #428).
class NuevaVentaPage extends ConsumerStatefulWidget {
  const NuevaVentaPage({super.key, required this.argumentos, this.antesDeGuardar});

  final ArgumentosDeVenta argumentos;
  final AntesDeGuardarLaVenta? antesDeGuardar;

  static Route<VentaGuardada> ruta({
    required ArgumentosDeVenta argumentos,
    AntesDeGuardarLaVenta? antesDeGuardar,
  }) => MaterialPageRoute<VentaGuardada>(
    builder: (_) => NuevaVentaPage(argumentos: argumentos, antesDeGuardar: antesDeGuardar),
  );

  @override
  ConsumerState<NuevaVentaPage> createState() => _NuevaVentaPageState();
}

class _NuevaVentaPageState extends ConsumerState<NuevaVentaPage> {
  final _talonario = TextEditingController();
  final _monto = TextEditingController();
  final _motivo = TextEditingController();
  var _navegando = false;

  /// El aviso «No pudimos guardar»: al fallar el guardado la lista se lleva hasta él (27A·13), porque
  /// con la lista abajo (donde está el total) y el texto grande quedaría fuera de la vista.
  final _avisoDeGuardado = GlobalKey();
  final _lista = ScrollController();

  ArgumentosDeVenta get _args => widget.argumentos;

  NuevaVentaNotifier get _notifier => ref.read(nuevaVentaProvider(_args).notifier);

  @override
  void dispose() {
    _talonario.dispose();
    _monto.dispose();
    _motivo.dispose();
    _lista.dispose();
    super.dispose();
  }

  Future<void> _soloUna(Future<void> Function() abrir) async {
    if (_navegando) return;
    _navegando = true;
    try {
      await abrir();
    } finally {
      _navegando = false;
    }
  }

  Future<void> _registrar() async {
    final guardada = await _notifier.registrar(antesDeGuardar: widget.antesDeGuardar);
    if (guardada != null && mounted) Navigator.of(context).pop(guardada);
  }

  /// Lleva la lista hasta el aviso de la falla, sin animación (respeta quitar movimiento).
  void _mostrarElAviso() {
    // Con la lista abajo el aviso ni está construido: se vuelve arriba y recién ahí se lo acomoda.
    if (_lista.hasClients) _lista.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _avisoDeGuardado.currentContext;
      if (!mounted || contexto == null) return;
      unawaited(Scrollable.ensureVisible(contexto));
    });
  }

  /// Una validación rechazada por el caso de uso se dice tal cual (reintentar igual no la arregla);
  /// cualquier otra falla es «No pudimos guardar… probá de nuevo».
  static String _textoDeLaFalla(Failure? falla) => switch (falla) {
    // La persona ausente no se arregla editando lo cargado: se vuelve atrás y se la elige de nuevo.
    FailureValidacion(:final campos) when campos.containsKey('persona') =>
      TextosVenta.personaYaNoEsta,
    FailureValidacion(:final campos) when campos.isNotEmpty => TextosVenta.revisaLoCargado(
      campos.values.first,
    ),
    _ => TextosVenta.errorAlGuardar,
  };

  Future<void> _confirmarSalida() async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Con texto grande el cuerpo y los botones tienen que poder desplazarse.
        scrollable: true,
        title: const Text(TextosVenta.salirTitulo),
        content: const Text(TextosVenta.salirCuerpo),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(TextosVenta.salirSeguir),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(TextosVenta.salirSalir),
          ),
        ],
      ),
    );
    if (salir == true && mounted) Navigator.of(context).pop();
  }

  // --- Armar y agregar ---------------------------------------------------------------------

  Future<void> _armarColeccion(
    PrecioDeCombo combo,
    CatalogoLocal catalogo,
    List<ItemDePrecio> items,
    String ciudad, {
    RenglonDeVenta? editar,
  }) => _soloUna(() async {
    final productos = {for (final p in catalogo.productos) p.id: p};
    final delCatalogo = catalogo.combos.where((c) => c.id == combo.id).firstOrNull;
    final base = [
      for (final c in delCatalogo?.componentes ?? const <ComponenteDelCombo>[])
        BaseDeColeccion(
          componente: ComponenteVendido(productoId: c.productoId, cantidad: c.cantidad),
          nombre: productos[c.productoId]?.nombre ?? 'Producto sin nombre',
          glifo: switch (productos[c.productoId]?.tipo) {
            TipoDeProducto.misionero => '✦',
            TipoDeProducto.revista => '▤',
            _ => '✝',
          },
        ),
    ];
    final libros = ResolvedorDePrecios.deLaCategoria(
      items,
      CategoriaDePrecios.libros,
    ).whereType<PrecioDeProducto>().toList();
    final porId = {for (final l in libros) l.id: l};
    final armada = await Navigator.of(context).push<ColeccionArmada>(
      MaterialPageRoute(
        builder: (ctx) => ArmarColeccionPage(
          combo: combo,
          ciudad: ciudad,
          base: base,
          libros: libros,
          elegidosAlAbrir: [for (final id in editar?.idsElegidos ?? const <String>[]) ?porId[id]],
          alQuitar: editar == null
              ? null
              : () {
                  _notifier.quitar(editar.clave);
                  Navigator.of(ctx).pop();
                },
        ),
      ),
    );
    if (armada == null || !mounted) return;
    _notifier.ponerColeccion(
      combo: combo,
      base: [for (final b in base) b.componente],
      nombresBase: [for (final b in base) b.nombre],
      elegidos: armada.elegidos,
      reemplazaClave: editar?.clave,
    );
  });

  Future<void> _agregar(List<ItemDePrecio> items, CatalogoLocal catalogo, String ciudad) =>
      _soloUna(() async {
        final agregado = await Navigator.of(context).push<LoAgregado>(
          MaterialPageRoute(
            builder: (_) =>
                AgregarProductosPage(items: items, actual: ref.read(nuevaVentaProvider(_args))),
          ),
        );
        if (!mounted) return;
        switch (agregado) {
          case AgregoProductos(:final productos):
            _notifier.fijarProductos(productos);
          case AgregoColeccion(:final combo):
            _navegando = false;
            await _armarColeccion(combo, catalogo, items, ciudad);
          case null:
            break;
        }
      });

  // --- Pantalla ----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final venta = ref.watch(nuevaVentaProvider(_args));
    ref.listen(nuevaVentaProvider(_args), (anterior, actual) {
      if (_monto.text != actual.montoTexto) _monto.text = actual.montoTexto;
      // La venta quedó vacía: el motivo del monto a mano se borra con el resto.
      if (actual.motivo.isEmpty && _motivo.text.isNotEmpty) _motivo.clear();
      if (anterior?.falla == null && actual.falla != null) _mostrarElAviso();
    });
    final id = _args.cliente.espacioPersonaId;
    final precios = ref.watch(preciosDeLaVentaProvider(id));

    final Widget cuerpo;
    if (precios.hasError) {
      cuerpo = _Marco(
        cabecera: _cabecera(),
        hijos: [
          TarjetaDelCliente(cliente: _args.cliente),
          const SizedBox(height: 12),
          AvisoDeVenta(
            texto: TextosVenta.errorPrecios,
            textoAccion: TextosVenta.reintentar,
            alAccion: () => ref.invalidate(preciosDeLaVentaProvider(id)),
          ),
        ],
      );
    } else if (precios.value == null) {
      cuerpo = _Marco(
        cabecera: _cabecera(),
        hijos: [
          TarjetaDelCliente(cliente: _args.cliente),
          const SizedBox(height: 12),
          const EsqueletoDeVenta(),
        ],
      );
    } else {
      cuerpo = switch (precios.value!) {
        SinCampaniaVigente(:final terminada) => _sinCampania(terminada),
        PreciosVigentes(:final ciudad) => _conPrecios(
          venta,
          ciudad.campaniaCiudadId,
          ciudad.nombre,
        ),
      };
    }

    final hayAlgo = venta.renglones.isNotEmpty || !venta.talonarioVacio;
    return PopScope(
      // Con el guardado en curso no se sale: la venta ya se está yendo a la base y «se pierde lo que
      // cargaste» sería falso. Termina y la pantalla se cierra sola (o muestra la falla).
      canPop: !venta.guardando && (!hayAlgo || venta.guardada != null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !venta.guardando) unawaited(_confirmarSalida());
      },
      child: cuerpo,
    );
  }

  Widget _cabecera({String? subtitulo}) => CabeceraVenta(
    eyebrow: TextosVenta.eyebrow,
    titulo: TextosVenta.titulo,
    subtitulo: subtitulo,
    cerrar: true,
    alVolver: () => unawaited(Navigator.of(context).maybePop()),
  );

  /// 27A·10: la campaña de la ciudad terminó. No se vende.
  Widget _sinCampania(CampaniaTerminada? terminada) {
    return _Marco(
      cabecera: _cabecera(),
      hijos: [
        TarjetaDelCliente(cliente: _args.cliente),
        Padding(
          key: const Key('venta_campania_terminada'),
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              const Text(r'$', style: TextStyle(fontSize: 40, color: ColoresAgenda.gris)),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  terminada == null
                      ? TextosVenta.sinPreciosVigentes
                      : TextosVenta.terminoEl(terminada.nombre, terminada.terminoEl),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                // Sin ninguna campaña vigente ni terminada, la salida es pedir que carguen los precios.
                terminada == null ? TextosVenta.salidaSinPrecio : TextosVenta.terminadaSub,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: ColoresAgenda.gris, height: 1.4),
              ),
            ],
          ),
        ),
      ],
      cta: BotonDeVenta(
        texto: TextosVenta.volver,
        alPresionar: () => unawaited(Navigator.of(context).maybePop()),
      ),
    );
  }

  Widget _conPrecios(NuevaVentaState venta, String campaniaCiudadId, String ciudad) {
    final catalogo = ref.watch(catalogoDePreciosProvider(campaniaCiudadId));
    if (catalogo.hasError) {
      return _Marco(
        cabecera: _cabecera(),
        hijos: [
          TarjetaDelCliente(cliente: _args.cliente),
          const SizedBox(height: 12),
          AvisoDeVenta(
            texto: TextosVenta.errorPrecios,
            textoAccion: TextosVenta.reintentar,
            alAccion: () => ref.invalidate(catalogoDePreciosProvider(campaniaCiudadId)),
          ),
        ],
      );
    }
    final leido = catalogo.value;
    if (leido == null) {
      return _Marco(
        cabecera: _cabecera(),
        hijos: [
          TarjetaDelCliente(cliente: _args.cliente),
          const SizedBox(height: 12),
          const EsqueletoDeVenta(),
        ],
      );
    }
    final dia = ResolvedorDePrecios.diaDeMontevideo(ref.read(relojVentaProvider)());
    final items = ResolvedorDePrecios.resolver(leido, dia: dia);
    if (items.isEmpty && venta.renglones.isEmpty) {
      return _Marco(
        cabecera: _cabecera(),
        hijos: [
          TarjetaDelCliente(cliente: _args.cliente),
          const Padding(
            key: Key('venta_sin_precios'),
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Text(
                  TextosVenta.sinPreciosVigentes,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  TextosVenta.salidaSinPrecio,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: ColoresAgenda.gris, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final vacia = venta.renglones.isEmpty;
    final repetido = venta.talonarioRepetido;
    return _Marco(
      controlador: _lista,
      cabecera: _cabecera(),
      hijos: [
        TarjetaDelCliente(cliente: _args.cliente),
        if (venta.falla != null) ...[
          const SizedBox(height: 9),
          KeyedSubtree(
            key: _avisoDeGuardado,
            child: AvisoDeVenta(key: const Key('venta_error'), texto: _textoDeLaFalla(venta.falla)),
          ),
        ],
        const SizedBox(height: 9),
        CampoDeVenta(
          key: const Key('venta_talonario'),
          rotulo: TextosVenta.talonario,
          controlador: _talonario,
          alCambiar: (t) => unawaited(_notifier.escribirTalonario(t)),
          error: repetido?.mensaje,
          teclado: TextInputType.text,
          maxLargo: 30,
          habilitado: !venta.guardando,
        ),
        const SizedBox(height: 9),
        Text(
          TextosVenta.ubicacion(ciudad),
          key: const Key('venta_ubicacion'),
          style: const TextStyle(fontSize: 12.5, color: ColoresAgenda.gris),
        ),
        const SizedBox(height: 9),
        if (vacia)
          SelectorDeProductos(
            items: items,
            actual: venta,
            alArmarLaColeccion: (c) => unawaited(_armarColeccion(c, leido, items, ciudad)),
            alAgregarProductos: _notifier.fijarProductos,
          )
        else ...[
          RotuloDeSeccion(
            TextosVenta.enLaVenta,
            textoAccion: TextosVenta.agregar,
            // Mientras se guarda no se agrega nada: la venta ya está yéndose a la base.
            alAccion: venta.guardando ? null : () => unawaited(_agregar(items, leido, ciudad)),
          ),
          for (final r in venta.renglones)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: _renglon(r, leido, items, ciudad, guardando: venta.guardando),
            ),
          const SizedBox(height: 12),
          ..._bloqueDeMonto(venta),
        ],
      ],
      cta: vacia
          ? null
          : BotonDeVenta(
              texto: venta.falla != null ? TextosVenta.reintentar : TextosVenta.registrarVenta,
              ocupado: venta.guardando,
              nota: venta.talonarioVacio
                  ? TextosVenta.talonarioVacio
                  : repetido != null
                  ? TextosVenta.talonarioRepetidoNota
                  : venta.motivoFalta
                  ? TextosVenta.motivoFalta
                  : null,
              alPresionar: venta.puedeRegistrar ? () => unawaited(_registrar()) : null,
            ),
    );
  }

  Widget _renglon(
    RenglonDeVenta r,
    CatalogoLocal catalogo,
    List<ItemDePrecio> items,
    String ciudad, {
    required bool guardando,
  }) {
    final linea = r.linea;
    final alQuitar = guardando ? null : () => _notifier.quitar(r.clave);
    switch (linea) {
      case LineaDeCombo(:final comboId, :final cantidad):
        final combo = items.whereType<PrecioDeCombo>().where((c) => c.id == comboId).firstOrNull;
        final unidades = cantidad > 1 ? ' · ×$cantidad' : '';
        return TarjetaDeRenglon(
          key: Key('venta_renglon_${r.clave}'),
          rotulo: r.titulo.toUpperCase(),
          titulo: r.nombresElegidos.isEmpty ? r.titulo : r.nombresElegidos.join(' · '),
          detalle: r.nombresBase.isEmpty
              ? null
              : '${TextosVenta.mas(r.nombresBase.join(', '))}$unidades',
          precio: FormatoVenta.monto(r.subtotalCentavos),
          alPresionar: combo == null || guardando
              ? null
              : () => unawaited(_armarColeccion(combo, catalogo, items, ciudad, editar: r)),
          alQuitar: alQuitar,
        );
      case LineaDeProducto(:final cantidad, :final precioCentavos, :final sinCobrar):
        return TarjetaDeRenglon(
          key: Key('venta_renglon_${r.clave}'),
          rotulo: null,
          titulo: r.titulo,
          detalle: sinCobrar
              ? '$cantidad · sin cobrar'
              : '$cantidad × ${FormatoVenta.monto(precioCentavos)}',
          precio: FormatoVenta.monto(r.subtotalCentavos),
          alQuitar: alQuitar,
          glifo: sinCobrar ? '✦' : '▤',
        );
    }
  }

  List<Widget> _bloqueDeMonto(NuevaVentaState venta) {
    if (!venta.cambiandoElMonto) {
      return [
        _FilaDeTotal(
          rotulo: TextosVenta.total,
          valor: FormatoVenta.monto(venta.totalCalculado),
          grande: true,
        ),
        // Con solo misioneros no hay monto que cambiar: no cuenta como venta y vale $ 0.
        if (venta.cobraAlgo)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('venta_cambiar_monto'),
              onPressed: venta.guardando ? null : _notifier.cambiarElMonto,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
              ),
              child: const Text(
                TextosVenta.cambiarElMonto,
                style: TextStyle(
                  fontSize: 13.5,
                  color: ColoresAgenda.azul,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ];
    }
    return [
      _FilaDeTotal(
        rotulo: TextosVenta.calculado,
        valor: FormatoVenta.monto(venta.totalCalculado),
        grande: false,
      ),
      const SizedBox(height: 8),
      CampoDeVenta(
        key: const Key('venta_monto'),
        rotulo: TextosVenta.montoDeLaVenta,
        controlador: _monto,
        alCambiar: _notifier.escribirMonto,
        ayuda: TextosVenta.avisoMonto,
        error: venta.montoValido ? null : TextosVenta.montoInvalido,
        teclado: const TextInputType.numberWithOptions(decimal: true),
        habilitado: !venta.guardando,
      ),
      const SizedBox(height: 12),
      CampoDeVenta(
        key: const Key('venta_motivo'),
        rotulo: TextosVenta.motivo,
        controlador: _motivo,
        alCambiar: _notifier.escribirMotivo,
        ayuda: TextosVenta.avisoMotivo,
        error: venta.motivoFalta ? TextosVenta.motivoFalta : null,
        teclado: TextInputType.multiline,
        maxLargo: 500,
        lineas: 3,
        habilitado: !venta.guardando,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const Key('venta_usar_calculado'),
          onPressed: venta.guardando
              ? null
              : () {
                  _motivo.clear();
                  _notifier.usarElMontoCalculado();
                },
          style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: EdgeInsets.zero),
          child: const Text(
            'Volver al monto calculado',
            style: TextStyle(
              fontSize: 13.5,
              color: ColoresAgenda.azul,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ];
  }
}

class _FilaDeTotal extends StatelessWidget {
  const _FilaDeTotal({required this.rotulo, required this.valor, required this.grande});

  final String rotulo;
  final String valor;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$rotulo: $valor',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                rotulo,
                style: TextStyle(fontSize: grande ? 15 : 13.5, color: ColoresAgenda.gris),
              ),
            ),
            Text(
              valor,
              key: const Key('venta_total'),
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: grande ? 20 : 14,
                fontWeight: grande ? FontWeight.w600 : FontWeight.w400,
                color: grande ? null : ColoresAgenda.gris,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El marco de toda pantalla de la venta: cabecera, cuerpo que se desplaza y, abajo fijo, el botón.
class _Marco extends StatelessWidget {
  const _Marco({required this.cabecera, required this.hijos, this.cta, this.controlador});

  final ScrollController? controlador;
  final Widget cabecera;
  final List<Widget> hijos;
  final Widget? cta;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('nueva_venta_pagina'),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: controlador,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [cabecera, ...hijos],
              ),
            ),
            if (cta != null) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: cta),
          ],
        ),
      ),
    );
  }
}
