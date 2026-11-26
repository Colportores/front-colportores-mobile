import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../catalogo/domain/entities/item_de_precio.dart' show CategoriaDePrecios;
import '../../../mapa/presentation/widgets/dialogos_modificar.dart'
    show confirmarDescartarLoEscrito;
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../../ventas/presentation/widgets/piezas_venta.dart';
import '../../domain/entities/companiero_de_campania.dart';
import '../../domain/entities/material_de_transferencia.dart';
import '../../domain/usecases/pedir_transferencia_use_case.dart';
import '../providers/transferencias_providers.dart';
import '../textos_transferencias.dart';
import '../widgets/piezas_transferencias.dart';

/// «Pedir transferencia de materiales» (vista 40 A, HU-STK-005, #512): la colportora le pide a otro de su
/// campaña unos materiales (40A·01 a 40A·09), la coordinadora la autoriza y los dos ven la transferencia
/// con su estado.
///
/// - **Qué pedís** (40A·01): las categorías como chips (con cuántos hay elegidos en cada una) y, debajo, los
///   materiales con «Tenés N» y su cantidad; sin precios (la transferencia mueve materiales, no plata).
/// - **A quién** (40A·02): una hoja con los colportores de su campaña, que da el servidor. Sin esa lista
///   (sin conexión o sin fuente) la hoja dice que no pudo traerla y deja reintentar.
/// - **Lista para enviar** (40A·03): botón apagado hasta tener a quién y al menos un material, y dice por
///   qué (40A·01 y 40A·04).
/// - **Enviando** (40A·05): el botón no admite otro toque y la pantalla no se cierra.
/// - **Sin conexión** (40A·07): la transferencia se guarda en el teléfono y sube sola; el botón lo dice.
/// - **Error** (40A·08): no se guardó nada, lo elegido queda y el botón pasa a «Reintentar» con el mismo
///   id (un reintento no pide dos).
/// - **Enviada** (40A·06): «Transferencia pedida» con lo pedido y «Ver transferencias».
/// - **Sin compañeros** (40A·09): no hay otro colportor en la campaña; se ofrece el pedido a la casa editora.
///
/// Devuelve `true` si la colportora tocó «Ver transferencias» en 40A·06 (quien la abrió decide si muestra la
/// lista), o `null` si cerró sin más.
class PedirTransferenciaPage extends ConsumerStatefulWidget {
  const PedirTransferenciaPage({super.key, required this.colportorId});

  /// UUID del colportor con la sesión iniciada: el que recibe los materiales.
  final String colportorId;

  static Future<bool?> abrir(BuildContext context, {required String colportorId}) => Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(builder: (_) => PedirTransferenciaPage(colportorId: colportorId)));

  @override
  ConsumerState<PedirTransferenciaPage> createState() => _PedirTransferenciaPageState();
}

class _Enviada {
  const _Enviada({required this.nombre, required this.lineas});

  final String nombre;
  final List<(String, int)> lineas;
}

class _PedirTransferenciaPageState extends ConsumerState<PedirTransferenciaPage> {
  late final String _transferenciaId;
  final _idsDeLineas = <String, String>{};
  final _cantidades = <String, int>{};
  CategoriaDePrecios? _categoria;
  CompanieroDeCampania? _companiero;

  /// Hay un envío en curso: no admite otro toque, no deja salir.
  var _enviando = false;

  /// La última falla al enviar (40A·08); `null` si no hay.
  Failure? _falla;

  /// Lo que se pidió (40A·06); `null` mientras se está armando.
  _Enviada? _enviada;

  /// La hoja de colportores está abierta o por abrirse: no admite otra encima.
  var _eligiendo = false;

  var _cerrando = false;
  var _preguntando = false;

  @override
  void initState() {
    super.initState();
    _transferenciaId = ref.read(generadorIdTransferenciaProvider)();
  }

  int get _total => _cantidades.values.fold(0, (a, b) => a + b);

  bool get _sePuede => !_enviando && _companiero != null && _total > 0;

  bool get _hayAlgoElegido => _companiero != null || _total > 0;

  String? get _nota {
    if (_enviando) return null;
    if (_total == 0) return TextosTransferencias.sumaUnMaterial;
    if (_companiero == null) return TextosTransferencias.elegiAQuien;
    return null;
  }

  void _cambiar(String productoId, int cantidad) {
    if (_enviando) return;
    setState(() {
      if (cantidad <= 0) {
        _cantidades.remove(productoId);
      } else {
        _cantidades[productoId] = cantidad;
      }
      // Lo elegido cambió: la falla de antes ya no habla de esto.
      _falla = null;
    });
  }

  Future<CompanierosDeCampania?> _cargarColportores() async {
    // La hoja lee desde su `initState` (en pleno armado): invalidar el provider ahí es marcar a Riverpod
    // como sucio durante `build`. Un turno de microtareas lo saca del armado.
    await Future<void>.microtask(() {});
    if (!mounted) return null;
    ref.invalidate(companierosDeCampaniaProvider(widget.colportorId));
    final r = await ref.read(companierosDeCampaniaProvider(widget.colportorId).future);
    return r.fold((_) => null, (lista) => lista);
  }

  Future<void> _elegirColportor() async {
    if (_eligiendo || _enviando || _cerrando) return;
    _eligiendo = true;
    try {
      final elegido = await mostrarHojaDeColportores(
        context,
        cargar: _cargarColportores,
        elegido: _companiero,
      );
      if (elegido != null && mounted) {
        setState(() {
          _companiero = elegido;
          _falla = null;
        });
      }
    } finally {
      _eligiendo = false;
    }
  }

  Future<void> _pedir() async {
    final companiero = _companiero;
    if (!_sePuede || _cerrando || companiero == null) return;
    final materiales =
        ref.read(materialesDeTransferenciaProvider(widget.colportorId)).value ?? const [];
    final nombres = {for (final m in materiales) m.id: m.nombre};
    final elegidos = [
      for (final e in _cantidades.entries)
        if (e.value > 0) MaterialPedido(productoId: e.key, cantidad: e.value),
    ];
    final generar = ref.read(generadorIdTransferenciaProvider);
    final ids = [for (final m in elegidos) _idsDeLineas.putIfAbsent(m.productoId, generar)];
    setState(() {
      _enviando = true;
      _falla = null;
    });
    try {
      final resultado = await ref.read(pedirTransferenciaUseCaseProvider)(
        PedirTransferenciaParams(
          transferenciaId: _transferenciaId,
          colportorId: widget.colportorId,
          entregaId: companiero.id,
          materiales: elegidos,
          idsDeLineas: ids,
        ),
      );
      if (!mounted) return;
      resultado.fold(
        (falla) => setState(() => _falla = falla),
        (_) => setState(
          () => _enviada = _Enviada(
            nombre: companiero.nombre,
            lineas: [
              for (final m in elegidos)
                (nombres[m.productoId] ?? TextosTransferencias.materialSinNombre, m.cantidad),
            ],
          ),
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _falla = const FailureTransferenciaNoGuardada(causa: 'excepcion'));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _cerrar(bool? verLista) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(verLista);
  }

  Future<void> _atras() async {
    if (_enviando || _preguntando || _cerrando) return;
    if (_enviada == null && _hayAlgoElegido) {
      _preguntando = true;
      bool descartar;
      try {
        descartar = await confirmarDescartarLoEscrito(context);
      } finally {
        _preguntando = false;
      }
      if (!mounted || !descartar || _enviando) return;
    }
    _cerrar(null);
  }

  @override
  Widget build(BuildContext context) {
    final enviada = _enviada;
    final companieros = ref.watch(companierosDeCampaniaProvider(widget.colportorId));
    final sinCompanieros =
        companieros.value?.fold((_) => false, (lista) => lista.companieros.isEmpty) ?? false;
    final Widget cuerpo;
    if (enviada != null) {
      cuerpo = _VistaEnviada(enviada: enviada, alVer: () => _cerrar(true));
    } else if (sinCompanieros) {
      cuerpo = _VistaSinCompanieros(alCerrar: () => _cerrar(null));
    } else {
      cuerpo = _Formulario(
        colportorId: widget.colportorId,
        categoria: _categoria,
        cantidades: _cantidades,
        companiero: _companiero,
        enviando: _enviando,
        falla: _falla,
        nota: _nota,
        sePuede: _sePuede,
        alElegirCategoria: (c) => setState(() => _categoria = c),
        alCambiar: _cambiar,
        alElegirColportor: () => unawaited(_elegirColportor()),
        alPedir: () => unawaited(_pedir()),
        alVolver: () => unawaited(_atras()),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (salio) return;
        if (enviada != null || sinCompanieros) {
          _cerrar(null);
        } else {
          unawaited(_atras());
        }
      },
      child: Scaffold(
        key: const Key('pedir_transferencia_pagina'),
        body: SafeArea(child: cuerpo),
      ),
    );
  }
}

class _Formulario extends ConsumerWidget {
  const _Formulario({
    required this.colportorId,
    required this.categoria,
    required this.cantidades,
    required this.companiero,
    required this.enviando,
    required this.falla,
    required this.nota,
    required this.sePuede,
    required this.alElegirCategoria,
    required this.alCambiar,
    required this.alElegirColportor,
    required this.alPedir,
    required this.alVolver,
  });

  final String colportorId;
  final CategoriaDePrecios? categoria;
  final Map<String, int> cantidades;
  final CompanieroDeCampania? companiero;
  final bool enviando;
  final Failure? falla;
  final String? nota;
  final bool sePuede;
  final ValueChanged<CategoriaDePrecios> alElegirCategoria;
  final void Function(String productoId, int cantidad) alCambiar;
  final VoidCallback alElegirColportor;
  final VoidCallback alPedir;
  final VoidCallback alVolver;

  static const _categorias = [
    (CategoriaDePrecios.libros, TextosTransferencias.libros),
    (CategoriaDePrecios.misioneros, TextosTransferencias.misioneros),
    (CategoriaDePrecios.revistas, TextosTransferencias.revistas),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materiales = ref.watch(materialesDeTransferenciaProvider(colportorId));
    final sinConexion = ref.watch(conexionProvider).value == TipoConexion.sinConexion;
    final lista = materiales.value ?? const <MaterialDeTransferencia>[];
    final actual =
        categoria ??
        _categorias
            .map((c) => c.$1)
            .firstWhere(
              (c) => lista.any((m) => m.categoria == c),
              orElse: () => CategoriaDePrecios.libros,
            );
    int elegidosDe(CategoriaDePrecios c) => [
      for (final m in lista)
        if (m.categoria == c) cantidades[m.id] ?? 0,
    ].fold(0, (a, b) => a + b);
    final deLaCategoria = [
      for (final m in lista)
        if (m.categoria == actual) m,
    ];
    final textoDelBoton = falla != null
        ? TextosTransferencias.reintentar
        : sinConexion
        ? TextosTransferencias.pedirCuandoHayConexion
        : TextosTransferencias.pedirTransferencia;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              CabeceraVenta(
                eyebrow: TextosTransferencias.eyebrow,
                titulo: TextosTransferencias.titulo,
                cerrar: true,
                alVolver: enviando ? null : alVolver,
              ),
              if (sinConexion) ...[
                const BannerDeTransferencia(
                  key: Key('pedir_transferencia_sin_conexion'),
                  texto: TextosTransferencias.sinConexionQuedaEnCola,
                  tipo: TipoDeBanner.sinConexion,
                ),
                const SizedBox(height: 10),
              ],
              if (falla != null) ...[
                BannerDeTransferencia(
                  key: const Key('pedir_transferencia_error'),
                  texto: falla!.mensaje,
                  tipo: TipoDeBanner.error,
                ),
                const SizedBox(height: 10),
              ],
              const RotuloDeSeccion(TextosTransferencias.quePedis),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final (c, nombre) in _categorias)
                    ChipDeVenta(
                      key: Key('pedir_transferencia_chip_${c.name}'),
                      texto: TextosTransferencias.chipConCantidad(nombre, elegidosDe(c)),
                      elegido: c == actual,
                      alPresionar: () => alElegirCategoria(c),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (materiales.isLoading && !materiales.hasValue)
                const EsqueletoDeVenta()
              else if (materiales.hasError)
                const BannerDeTransferencia(
                  key: Key('pedir_transferencia_catalogo_error'),
                  texto: TextosTransferencias.sinCatalogo,
                  tipo: TipoDeBanner.error,
                )
              else if (lista.isEmpty)
                const Padding(
                  key: Key('pedir_transferencia_sin_catalogo'),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    TextosTransferencias.sinCatalogo,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: ColoresAgenda.gris),
                  ),
                )
              else if (deLaCategoria.isEmpty)
                const Padding(
                  key: Key('pedir_transferencia_categoria_vacia'),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    TextosTransferencias.sinMaterialesEnLaCategoria,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: ColoresAgenda.gris),
                  ),
                )
              else
                for (final m in deLaCategoria)
                  Padding(
                    key: Key('pedir_transferencia_material_${m.id}'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilaDeCantidad(
                      titulo: m.nombre,
                      precio: '${TextosTransferencias.tenes} ${m.tengo}',
                      cantidad: cantidades[m.id] ?? 0,
                      alCambiar: enviando ? (_) {} : (n) => alCambiar(m.id, n),
                      etiqueta: m.esBonificable ? TextosTransferencias.bonificable : null,
                    ),
                  ),
              const SizedBox(height: 8),
              const RotuloDeSeccion(TextosTransferencias.aQuien),
              const SizedBox(height: 6),
              TarjetaDeColportor(
                key: const Key('pedir_transferencia_colportor'),
                elegido: companiero,
                alPresionar: enviando ? null : alElegirColportor,
              ),
              if (companiero != null && sePuede) ...[
                const SizedBox(height: 10),
                Text(
                  TextosTransferencias.laTieneQueAutorizar(companiero!.nombre),
                  key: const Key('pedir_transferencia_info'),
                  style: const TextStyle(fontSize: 13, color: ColoresAgenda.gris),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: BotonDeVenta(
            texto: textoDelBoton,
            textoOcupado: TextosTransferencias.enviando,
            ocupado: enviando,
            nota: nota,
            alPresionar: sePuede ? alPedir : null,
          ),
        ),
      ],
    );
  }
}

/// 40A·06: «Transferencia pedida».
class _VistaEnviada extends StatelessWidget {
  const _VistaEnviada({required this.enviada, required this.alVer});

  final _Enviada enviada;
  final VoidCallback alVer;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('pedir_transferencia_enviada'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              const CabeceraVenta(
                eyebrow: TextosTransferencias.eyebrow,
                titulo: TextosTransferencias.tituloEnviada,
              ),
              const HeroDeTransferencias(
                glifo: '✓',
                verde: true,
                titulo: TextosTransferencias.enviadaTitulo,
                texto: TextosTransferencias.enviadaTexto,
              ),
              FilasDeLaTransferencia(
                datos: [
                  DatoDeTransferencia(
                    clave: 'transferencia_enviada_a',
                    rotulo: TextosTransferencias.lePediste,
                    valor: enviada.nombre,
                  ),
                  for (final (i, (nombre, cantidad)) in enviada.lineas.indexed)
                    DatoDeTransferencia(
                      clave: 'transferencia_enviada_linea_$i',
                      rotulo: nombre,
                      valor: '× $cantidad',
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: BotonDeVenta(texto: TextosTransferencias.verTransferencias, alPresionar: alVer),
        ),
      ],
    );
  }
}

/// 40A·09: no hay otro colportor en la campaña.
class _VistaSinCompanieros extends ConsumerWidget {
  const _VistaSinCompanieros({required this.alCerrar});

  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hacerUnPedido = ref.watch(hacerUnPedidoDesdeTransferenciaProvider);
    return Column(
      key: const Key('pedir_transferencia_sin_companieros'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              CabeceraVenta(
                eyebrow: TextosTransferencias.eyebrow,
                titulo: TextosTransferencias.titulo,
                cerrar: true,
                alVolver: alCerrar,
              ),
              const HeroDeTransferencias(
                glifo: '⇄',
                titulo: TextosTransferencias.sinCompanierosTitulo,
                texto: TextosTransferencias.sinCompanierosTexto,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: BotonDeVenta(
            texto: hacerUnPedido == null
                ? TextosTransferencias.volver
                : TextosTransferencias.hacerUnPedido,
            alPresionar: hacerUnPedido == null ? alCerrar : () => hacerUnPedido(context),
          ),
        ),
      ],
    );
  }
}
