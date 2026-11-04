import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ChipAgenda, HeroAgenda;
import '../../../inicio/presentation/widgets/barra_pestanas_inicio.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../domain/entities/ciudad_consultable.dart';
import '../../domain/entities/item_de_precio.dart';
import '../../domain/services/antiguedad_de_precios.dart';
import '../../domain/services/resolvedor_de_precios.dart';
import '../formato_precios.dart';
import '../providers/precios_providers.dart';
import '../widgets/hoja_detalle_combo.dart';
import '../widgets/hoja_otra_ciudad.dart';
import '../widgets/piezas_precios.dart';

/// La consulta de precios (vista 26, HU-CAT-006): los precios vigentes de la ciudad donde está la
/// colportora —el de la excepción de la ciudad o, si no hay, el general—, las colecciones con lo que
/// llevan, y los de otra ciudad de sus campañas solo para consultar.
///
/// Todo sale del teléfono: funciona sin conexión y dice de cuándo son los precios (26·09). Elegir
/// otra ciudad **no cambia** con qué precios se vende (vista 27).
class PreciosPage extends ConsumerStatefulWidget {
  const PreciosPage({super.key, required this.colportorId});

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  /// La ruta de la pantalla, que se entra desde Ventas (`Ventas → Precios`). Si se sale por la barra
  /// de pestañas devuelve la pestaña elegida; con «volver», `null`.
  static Route<PestanaInicio> ruta({required String colportorId}) =>
      MaterialPageRoute<PestanaInicio>(builder: (_) => PreciosPage(colportorId: colportorId));

  @override
  ConsumerState<PreciosPage> createState() => _PreciosPageState();
}

class _PreciosPageState extends ConsumerState<PreciosPage> {
  final _busqueda = TextEditingController();

  /// Una sola hoja abierta a la vez: un segundo toque (o dos filas seguidas) no abre otra encima.
  var _abriendo = false;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  /// Abre una hoja si no hay otra abierta. Pase lo que pase —incluso si la hoja falla al abrir— la
  /// pantalla vuelve a quedar libre.
  Future<void> _soloUna(Future<void> Function() abrir) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await abrir();
    } finally {
      _abriendo = false;
    }
  }

  Future<void> _elegirCiudad(AperturaDePrecios apertura, CiudadConsultable? vista) =>
      _soloUna(() async {
        final inicial = apertura.inicial;
        final marcas = <String, String>{
          if (inicial.ciudad != null)
            inicial.ciudad!.campaniaCiudadId: inicial.origen == OrigenDeLaCiudad.gps
                ? TextosPrecios.dondeEstas
                : TextosPrecios.tuZona,
        };
        final elegida = await mostrarHojaOtraCiudad(
          context,
          ciudades: apertura.contexto.ciudades,
          actual: vista,
          marcas: marcas,
        );
        if (elegida == null || !mounted) return;
        // Elegir la ciudad de entrada es volver a ella: no queda «otra ciudad» elegida.
        ref
            .read(ciudadElegidaDePreciosProvider(widget.colportorId).notifier)
            .elegir(elegida.campaniaCiudadId == inicial.ciudad?.campaniaCiudadId ? null : elegida);
      });

  Future<void> _verCombo(PrecioDeCombo combo, String ciudad) =>
      _soloUna(() => mostrarHojaDetalleDelCombo(context, combo: combo, ciudad: ciudad));

  void _reintentar() {
    ref.invalidate(aperturaDePreciosProvider(widget.colportorId));
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.colportorId;
    final filtros = ref.watch(filtrosDePreciosProvider(id));
    // Al cambiar de pestaña el notificador limpia la búsqueda: la caja de texto la sigue.
    ref.listen(filtrosDePreciosProvider(id), (anterior, actual) {
      if (_busqueda.text != actual.busqueda) _busqueda.text = actual.busqueda;
    });

    return Scaffold(
      key: const Key('precios_pagina'),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const Key('precios_scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: CabeceraPrecios(alVolver: () => unawaited(Navigator.of(context).maybePop())),
            ),
            ..._cuerpo(context, filtros),
          ],
        ),
      ),
      bottomNavigationBar: BarraPestanasInicio(
        seleccionada: PestanaInicio.ventas,
        onSeleccionar: (pestana) => Navigator.of(context).pop(pestana),
      ),
    );
  }

  /// Los slivers de debajo del encabezado, según en qué estado está la consulta.
  List<Widget> _cuerpo(BuildContext context, FiltrosDePrecios filtros) {
    final id = widget.colportorId;
    final apertura = ref.watch(aperturaDePreciosProvider(id));

    if (apertura.hasError) {
      return [
        _fila(
          AvisoDePrecios(
            tipo: TipoDeAviso.error,
            texto: TextosPrecios.errorLectura,
            textoAccion: TextosPrecios.reintentar,
            alAccion: _reintentar,
          ),
        ),
      ];
    }
    final datos = apertura.value;
    if (datos == null) return [_fila(const EsqueletoDePrecios())];

    if (datos.contexto.ciudades.isEmpty) {
      final terminada = datos.contexto.campaniaTerminada;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: HeroAgenda(
            glifo: r'$',
            titulo: TextosPrecios.sinPreciosVigentes,
            cuerpo: terminada == null
                ? TextosPrecios.sinCampaniaSub
                : FormatoPrecios.campaniaTerminada(terminada),
          ),
        ),
      ];
    }

    final elegida = ref.watch(ciudadElegidaDePreciosProvider(id));
    final inicial = datos.inicial;
    final vista = elegida ?? inicial.ciudad;
    final hayOtras = datos.contexto.ciudades.length > 1;

    if (vista == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: HeroAgenda(
            glifo: '◉',
            titulo: TextosPrecios.elegiUnaCiudadTitulo,
            cuerpo: TextosPrecios.elegiUnaCiudadSub,
            textoAccion: TextosPrecios.elegiUnaCiudadAccion,
            alAccion: () => unawaited(_elegirCiudad(datos, null)),
          ),
        ),
      ];
    }

    final viendoOtra =
        elegida != null && elegida.campaniaCiudadId != inicial.ciudad?.campaniaCiudadId;
    final String rotulo;
    if (viendoOtra) {
      rotulo = inicial.ciudad == null ? TextosPrecios.ciudadElegida : TextosPrecios.ciudadOtra;
    } else if (inicial.origen == OrigenDeLaCiudad.gps) {
      rotulo = TextosPrecios.ciudadSegunDondeEstas;
    } else {
      rotulo = TextosPrecios.ciudadDeTuZonaSinGps;
    }

    final conexion = ref.watch(conexionProvider).value;
    final sinConexion = conexion == TipoConexion.sinConexion;
    final ultimaBajada = ref.watch(ultimaBajadaDePreciosProvider).value;
    final dias = ref.watch(diasDelAvisoFuerteProvider).value ?? AntiguedadDePrecios.diasPorDefecto;
    final ahora = ref.read(relojPreciosProvider)();

    final arriba = <Widget>[
      if (sinConexion) _avisoSinConexion(ultimaBajada, ahora, dias),
      TarjetaDeCiudad(
        rotulo: rotulo,
        ciudad: vista.nombre,
        alVerOtra: hayOtras ? () => unawaited(_elegirCiudad(datos, vista)) : null,
      ),
      if (viendoOtra && inicial.ciudad != null)
        AvisoDePrecios(
          tipo: TipoDeAviso.info,
          texto: FormatoPrecios.viendoOtraCiudad(
            viendo: vista.nombre,
            enQueVende: inicial.ciudad!.nombre,
          ),
          textoAccion: inicial.origen == OrigenDeLaCiudad.gps
              ? TextosPrecios.volverADondeEstoy
              : TextosPrecios.volverAMiZona,
          alAccion: () => ref.read(ciudadElegidaDePreciosProvider(id).notifier).elegir(null),
        )
      else if (!viendoOtra && inicial.origen == OrigenDeLaCiudad.zona)
        AvisoDePrecios(
          tipo: TipoDeAviso.advertencia,
          texto: FormatoPrecios.sinUbicacion(vista.nombre),
        ),
    ];

    final catalogo = ref.watch(catalogoDePreciosProvider(vista.campaniaCiudadId));
    if (catalogo.hasError) {
      return [
        _filas([
          ...arriba,
          AvisoDePrecios(
            tipo: TipoDeAviso.error,
            texto: TextosPrecios.errorLectura,
            textoAccion: TextosPrecios.reintentar,
            alAccion: () => ref.invalidate(catalogoDePreciosProvider(vista.campaniaCiudadId)),
          ),
        ]),
      ];
    }

    final chips = _Chips(
      categoria: filtros.categoria,
      alElegir: ref.read(filtrosDePreciosProvider(id).notifier).elegirCategoria,
    );
    final buscador = filtros.conBuscador
        ? CampoDeBusquedaPrecios(
            controlador: _busqueda,
            alCambiar: ref.read(filtrosDePreciosProvider(id).notifier).buscar,
            alBorrar: () {
              _busqueda.clear();
              ref.read(filtrosDePreciosProvider(id).notifier).buscar('');
            },
          )
        : null;

    final catalogoLeido = catalogo.value;
    if (catalogoLeido == null) {
      return [
        _filas([...arriba, chips, ?buscador, const EsqueletoDePrecios()]),
      ];
    }

    final dia = ResolvedorDePrecios.diaDeMontevideo(ahora);
    final todos = ResolvedorDePrecios.resolver(catalogoLeido, dia: dia);
    final deLaCategoria = ResolvedorDePrecios.deLaCategoria(todos, filtros.categoria);
    final visibles = filtros.estaBuscando
        ? ResolvedorDePrecios.buscar(deLaCategoria, filtros.busqueda)
        : deLaCategoria;

    return [
      _filas([...arriba, chips, ?buscador]),
      if (visibles.isEmpty)
        SliverToBoxAdapter(
          child: HeroAgenda(
            glifo: filtros.estaBuscando ? '⌕' : r'$',
            titulo: filtros.estaBuscando
                ? FormatoPrecios.sinResultados(filtros.categoria, vista.nombre)
                : FormatoPrecios.pestanaVacia(filtros.categoria, vista.nombre),
            cuerpo: filtros.estaBuscando
                ? TextosPrecios.sinResultadosSub
                : TextosPrecios.pestanaVaciaSub,
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverList.builder(
            itemCount: visibles.length,
            itemBuilder: (context, i) {
              final item = visibles[i];
              return switch (item) {
                final PrecioDeCombo combo => FilaDeCombo(
                  key: ValueKey(combo.id),
                  combo: combo,
                  alTocar: () => unawaited(_verCombo(combo, vista.nombre)),
                ),
                final PrecioDeProducto producto => FilaDeProducto(
                  key: ValueKey(producto.id),
                  producto: producto,
                ),
              };
            },
          ),
        ),
    ];
  }

  Widget _avisoSinConexion(DateTime? ultimaBajada, DateTime ahora, int dias) {
    final fuerte =
        ultimaBajada != null && AntiguedadDePrecios.esFuerte(ultimaBajada, ahora, umbral: dias);
    return AvisoDePrecios(
      tipo: fuerte ? TipoDeAviso.advertencia : TipoDeAviso.sinConexion,
      texto: fuerte
          ? FormatoPrecios.preciosViejos(
              ultimaBajada,
              AntiguedadDePrecios.dias(ultimaBajada, ahora),
            )
          : FormatoPrecios.sinConexion(ultimaBajada),
    );
  }

  /// Un solo hijo con el margen lateral de la pantalla.
  Widget _fila(Widget hijo) => _filas([hijo]);

  /// Los hijos uno debajo del otro, con el margen lateral y 8 de separación.
  Widget _filas(List<Widget> hijos) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
    sliver: SliverList.separated(
      itemCount: hijos.length,
      itemBuilder: (context, i) => hijos[i],
      separatorBuilder: (context, i) => const SizedBox(height: 8),
    ),
  );
}

/// Los chips de las categorías.
class _Chips extends StatelessWidget {
  const _Chips({required this.categoria, required this.alElegir});

  final CategoriaDePrecios categoria;
  final ValueChanged<CategoriaDePrecios> alElegir;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const Key('precios_chips'),
      spacing: 8,
      children: [
        for (final c in CategoriaDePrecios.values)
          ChipAgenda(
            key: Key('precios_chip_${c.name}'),
            texto: FormatoPrecios.categoria(c),
            elegido: c == categoria,
            alPresionar: () => alElegir(c),
          ),
      ],
    );
  }
}
