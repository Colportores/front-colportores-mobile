import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../agenda/presentation/widgets/flujo_entrevista.dart';
import '../../../agenda/presentation/widgets/hoja_termino_entrevista.dart'
    show VentaGuardadaEnLaEntrevista;
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show HeroAgenda;
import '../../../inicio/presentation/widgets/barra_pestanas_inicio.dart' show PestanaInicio;
import '../../../mapa/presentation/widgets/piezas_hoja_casa.dart' show FilaPersonaDeLaCasa;
import '../../domain/entities/persona_para_vender.dart';
import '../listado_de_personas_para_vender.dart';
import '../providers/ventas_providers.dart';
import '../textos_elegir_persona.dart';
import '../widgets/piezas_elegir_persona.dart';
import '../widgets/piezas_venta.dart' show AvisoDeVenta, CabeceraVenta, RotuloDeSeccion;

/// «¿A quién le vendés?»: el paso previo de «+ Registrar venta» de la pestaña Ventas (HU-VEN-001, #546).
///
/// Lista a las personas activas de espacios activos —nombre y, debajo, «dirección · depto», como las
/// filas de la vista 32 (32A·05)— con búsqueda por nombre o dirección. Tocar a alguien abre la venta
/// (vista 27) con esa persona puesta y, al registrarla, sigue como cuando se vende desde la casa:
/// «Venta registrada: ¿y ahora?», el cobro y «¿Cuándo volvés a cobrar?». Al terminar vuelve a la
/// pestaña Ventas.
///
/// Sin personas cargadas dice qué pasa y lleva al mapa, donde se las suma; nunca una lista vacía muda.
/// Devuelve la pestaña a la que se quiere ir («Ir al mapa»), o `null` con «volver» o al terminar.
class ElegirPersonaParaVenderPage extends ConsumerStatefulWidget {
  const ElegirPersonaParaVenderPage({super.key, required this.colportorId});

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  static Route<PestanaInicio> ruta({required String colportorId}) =>
      MaterialPageRoute<PestanaInicio>(
        builder: (_) => ElegirPersonaParaVenderPage(colportorId: colportorId),
      );

  @override
  ConsumerState<ElegirPersonaParaVenderPage> createState() => _ElegirPersonaParaVenderPageState();
}

class _ElegirPersonaParaVenderPageState extends ConsumerState<ElegirPersonaParaVenderPage> {
  final _busqueda = TextEditingController();
  var _texto = '';

  /// Ya hay una venta en curso desde esta lista: un segundo toque (a otra persona, o a la misma) no
  /// abre otra encima. Pase lo que pase vuelve a quedar libre.
  var _vendiendo = false;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  void _escribir(String texto) => setState(() => _texto = texto);

  void _borrarBusqueda() {
    _busqueda.clear();
    setState(() => _texto = '');
  }

  Future<void> _vender(FilaDePersonaParaVender fila) async {
    if (_vendiendo) return;
    _vendiendo = true;
    final navegador = Navigator.of(context);
    try {
      final nombre = fila.nombre.trim();
      final salida = await FlujoEntrevista.venderDesdeVentas(
        context,
        ProviderScope.containerOf(context),
        colportorId: widget.colportorId,
        espacioId: fila.origen.espacioId,
        espacioPersonaId: fila.espacioPersonaId,
        persona: nombre.isEmpty ? TextosElegirPersona.sinNombre : nombre,
        direccion: fila.direccion,
      );
      // Salió sin registrar: la lista sigue donde estaba. Registrada, vuelve a la pestaña Ventas con el
      // aviso de lo que quedó (42B·01H).
      if (salida is VentaGuardadaEnLaEntrevista && mounted) navegador.pop();
    } finally {
      _vendiendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final personas = ref.watch(personasParaVenderProvider(widget.colportorId));
    return Scaffold(
      key: const Key('elegir_persona_pagina'),
      body: SafeArea(
        child: CustomScrollView(
          key: const Key('elegir_persona_scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: CabeceraVenta(
                eyebrow: TextosElegirPersona.eyebrow,
                titulo: TextosElegirPersona.titulo,
                alVolver: () => unawaited(Navigator.of(context).maybePop()),
              ),
            ),
            ..._cuerpo(personas),
          ],
        ),
      ),
    );
  }

  /// Los slivers de debajo del encabezado, según en qué estado está la lectura.
  List<Widget> _cuerpo(AsyncValue<List<PersonaParaVender>> personas) {
    final datos = personas.value;
    if (datos == null) {
      if (personas.hasError) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: AvisoDeVenta(
                texto: TextosElegirPersona.errorLectura,
                textoAccion: TextosElegirPersona.reintentar,
                alAccion: () => ref.invalidate(personasParaVenderProvider(widget.colportorId)),
              ),
            ),
          ),
        ];
      }
      return const [SliverToBoxAdapter(child: EsqueletoDePersonas())];
    }

    if (datos.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: HeroAgenda(
            glifo: '☰',
            titulo: TextosElegirPersona.sinPersonas,
            cuerpo: TextosElegirPersona.sinPersonasAyuda,
            textoAccion: TextosElegirPersona.irAlMapa,
            alAccion: () => Navigator.of(context).pop(PestanaInicio.mapa),
          ),
        ),
      ];
    }

    final filas = ListadoDePersonasParaVender.armar(datos, busqueda: _texto);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: CampoDeBusquedaDePersonas(
            controlador: _busqueda,
            alCambiar: _escribir,
            alBorrar: _borrarBusqueda,
          ),
        ),
      ),
      if (filas.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: HeroAgenda(
            glifo: '⌕',
            titulo: TextosElegirPersona.sinResultados,
            cuerpo: TextosElegirPersona.sinResultadosAyuda,
            textoAccion: TextosElegirPersona.borrarBusqueda,
            alAccion: _borrarBusqueda,
          ),
        )
      else ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: RotuloDeSeccion(TextosElegirPersona.personas(filas.length)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          sliver: SliverList.separated(
            itemCount: filas.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final fila = filas[i];
              return FilaPersonaDeLaCasa(
                key: Key('persona_para_vender_${fila.espacioPersonaId}'),
                persona: fila.origen.persona,
                detalle: fila.direccion,
                alAbrir: () => unawaited(_vender(fila)),
              );
            },
          ),
        ),
      ],
    ];
  }
}
