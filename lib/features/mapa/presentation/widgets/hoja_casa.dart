import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/contexto_de_la_casa.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/services/cercania_de_la_casa.dart';
import '../formato_hoja_casa.dart';
import '../formato_mapa_ubicaciones.dart';
import '../formato_ubicaciones.dart';
import '../providers/hoja_casa_providers.dart';
import 'estados_hoja_casa.dart';
import 'piezas_alta.dart' show AvisoAlta, ColoresAlta;
import 'piezas_hoja_casa.dart';
import 'piezas_lista_ubicaciones.dart' show ColoresLista;
import 'piezas_mapa_ubicaciones.dart' show ClavesMapaUbicaciones;

/// La hoja de la casa (vista 39, C·01 «Tocar una casa: resumen»): la dirección, una línea con el tipo,
/// el estado y la distancia, la persona de la casa, la nota más reciente del lugar y un solo botón,
/// «Registrar visita». Es lo que se ve al tocar una ubicación en el mapa o en la Lista.
///
/// Compone los estados del grupo E (#448):
/// - **E·01** mientras lee la casa: tres esqueletos y el subtítulo vacío ([CargandoHojaCasa]).
/// - **E·02** si no la puede leer: «No pudimos leer esta casa en tu teléfono.» con «Reintentar».
///   El teléfono no necesita conexión para esta hoja (todo es local): **E·03** «sin conexión» se ve
///   igual que el resumen, sin aviso.
/// - **E·04** si la casa está dada de baja: el aviso con «Reactivar» (si [alReactivar] lo permite) y
///   lo que había, solo para ver; no se registra nada. Con la baja va **solo** ese aviso, no el de
///   lejos (decisión del 23/10).
/// - **E·05** si el colportor está a 100 m o más ([CercaniaDeLaCasa]): un aviso informativo; no frena
///   ni pide confirmar.
///
/// Los dos botones dependen de pantallas que se enganchan por [registrarVisitaDesdeLaCasaProvider] y
/// [cobrarDesdeLaCasaProvider]: sin destino no se dibujan (HU-UBI-003: «los botones no se muestran
/// mientras no tengan a dónde llevar»).
///
/// Una sola acción a la vez: «Registrar visita» y «$ Cobrar» comparten la guarda, así que un doble
/// toque, o dos botones seguidos, abren una sola vez; si la acción falla la hoja avisa y los botones
/// vuelven a poder tocarse.
class HojaCasa extends ConsumerStatefulWidget {
  const HojaCasa({
    super.key,
    required this.item,
    required this.ahora,
    required this.alCerrar,
    this.alReactivar,
  });

  final ItemListaUbicacion item;
  final DateTime ahora;

  /// La ✕ de la hoja.
  final VoidCallback alCerrar;

  /// «Reactivar» de E·04; `null` = el aviso va sin acción (la baja por unión de duplicados no se
  /// reactiva, HU-UBI-005).
  final FutureOr<void> Function()? alReactivar;

  @override
  ConsumerState<HojaCasa> createState() => _HojaCasaState();
}

class _HojaCasaState extends ConsumerState<HojaCasa> {
  /// Hay una acción abierta. Es un campo y no solo estado de la UI: la guarda tiene que cortar el
  /// segundo toque aunque llegue antes de que se vuelva a dibujar.
  bool _enCurso = false;

  /// Qué falló en la última acción, para decirlo en la hoja; `null` si nada falló.
  String? _falla;

  Future<void> _correr(FutureOr<void> Function() accion, String textoSiFalla) async {
    if (_enCurso) return;
    _enCurso = true;
    setState(() => _falla = null);
    try {
      await accion();
    } on Object {
      // El detalle del error puede llevar datos de la casa: se avisa en la hoja y no se loguea.
      if (mounted) _falla = textoSiFalla;
    } finally {
      _enCurso = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ubicacion = item.ubicacion;
    final clave = (ubicacionId: ubicacion.id, tipo: ubicacion.tipo);
    final contexto = ref.watch(contextoDeLaCasaProvider(clave));
    final cuerpo = contexto.when(
      skipLoadingOnReload: true,
      skipError: true,
      data: (datos) => _Resumen(
        item: item,
        contexto: datos,
        ocupado: _enCurso,
        falla: _falla,
        alReactivar: widget.alReactivar,
        alRegistrarVisita: _registrarVisita(datos),
        alCobrar: _cobrar(datos),
      ),
      error: (_, _) => AvisoHojaCasa.errorAlLeer(
        alReintentar: () => ref.invalidate(contextoDeLaCasaProvider(clave)),
      ),
      loading: () => const CargandoHojaCasa(),
    );
    // Con el contexto sin llegar (cargando o error) el subtítulo va vacío (canvas, E·01 y E·02); una
    // casa de baja ya sabe qué decir.
    final subtitulo = contexto.hasValue ? FormatoHojaCasa.subtitulo(item, widget.ahora) : '';
    return SingleChildScrollView(
      child: Semantics(
        container: true,
        // Cada pieza (el título, la ✕, la persona, la nota, los botones) es su propio nodo: sin esto
        // el lector de pantalla las leería como una sola cosa y «Registrar visita» no sería un botón.
        explicitChildNodes: true,
        liveRegion: true,
        label: TextosMapaUbicaciones.vistaPrevia,
        child: Padding(
          key: ClavesMapaUbicaciones.vistaPrevia,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Cabecera(
                direccion: FormatoUbicaciones.direccion(ubicacion),
                subtitulo: subtitulo,
                alCerrar: widget.alCerrar,
              ),
              const SizedBox(height: 10),
              cuerpo,
            ],
          ),
        ),
      ),
    );
  }

  /// Lo que hace «Registrar visita», o `null` si no se ofrece: sin destino enganchado, o con la casa
  /// de baja (no se registra nada en una casa dada de baja).
  VoidCallback? _registrarVisita(ContextoDeLaCasa contexto) {
    final destino = ref.watch(registrarVisitaDesdeLaCasaProvider);
    if (destino == null || widget.item.esBaja) return null;
    return () => _correr(() async {
      final resuelta = await destino((
        ubicacionId: widget.item.ubicacion.id,
        espacioId: contexto.espacioId,
      ));
      // Se guardó o siguió a otro flujo: la hoja de la casa se va y el mapa muestra el color nuevo.
      if (resuelta == true && mounted) widget.alCerrar();
    }, TextosHojaCasa.noPudimosAbrirVisita);
  }

  /// Lo que hace «$ Cobrar» de la persona [personaId], o `null` si no se ofrece.
  VoidCallback? Function(String personaId) _cobrar(ContextoDeLaCasa contexto) {
    final destino = ref.watch(cobrarDesdeLaCasaProvider);
    return (personaId) {
      if (destino == null || widget.item.esBaja) return null;
      return () => _correr(
        () => destino((
          ubicacionId: widget.item.ubicacion.id,
          espacioId: contexto.espacioId,
          personaId: personaId,
        )),
        TextosHojaCasa.noPudimosAbrirCobro,
      );
    };
  }
}

/// El título (la dirección), la ✕ y la línea de abajo.
class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.direccion, required this.subtitulo, required this.alCerrar});

  final String direccion;
  final String subtitulo;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  header: true,
                  child: Text(
                    direccion,
                    key: ClavesHojaCasa.titulo,
                    style: const TextStyle(
                      fontFamily: 'SourceSerif4',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: ColoresLista.tinta,
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: TextosMapaUbicaciones.cerrarVistaPrevia,
              onTap: alCerrar,
              child: ExcludeSemantics(
                child: InkResponse(
                  key: ClavesMapaUbicaciones.cerrarVistaPrevia,
                  onTap: alCerrar,
                  radius: 24,
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.close, size: 20, color: ColoresLista.grisTexto),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (subtitulo.isNotEmpty)
          Text(
            subtitulo,
            key: ClavesHojaCasa.subtitulo,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              height: 1.4,
              color: ColoresLista.grisTexto,
            ),
          ),
      ],
    );
  }
}

/// El resumen: los avisos que correspondan, la persona, la nota y «Registrar visita».
class _Resumen extends StatelessWidget {
  const _Resumen({
    required this.item,
    required this.contexto,
    required this.ocupado,
    required this.falla,
    required this.alReactivar,
    required this.alRegistrarVisita,
    required this.alCobrar,
  });

  final ItemListaUbicacion item;
  final ContextoDeLaCasa contexto;
  final bool ocupado;
  final String? falla;
  final FutureOr<void> Function()? alReactivar;
  final VoidCallback? alRegistrarVisita;
  final VoidCallback? Function(String personaId) alCobrar;

  @override
  Widget build(BuildContext context) {
    final persona = contexto.personaDestacada;
    final nota = contexto.nota;
    final distancia = item.distanciaMetros;
    final lejos = !item.esBaja && CercaniaDeLaCasa.estaLejos(distancia);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        if (item.esBaja) AvisoHojaCasa.dadaDeBaja(alReactivar: alReactivar),
        if (lejos && distancia != null) AvisoHojaCasa.lejos(metros: distancia),
        if (persona != null)
          FilaPersonaDeLaCasa(
            persona: persona.persona,
            saldoCentavos: contexto.saldoDe(persona.persona.id),
            alCobrar: alCobrar(persona.persona.id),
            ocupada: ocupado,
          ),
        if (nota != null) FilaNotaDelLugar(nota: nota),
        if (falla != null) AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: falla!),
        if (alRegistrarVisita != null)
          BotonRegistrarVisita(alPresionar: alRegistrarVisita!, ocupado: ocupado),
      ],
    );
  }
}
