import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../tiles/domain/entities/paquete_tiles.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/estado_casa.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/usecases/duplicados_ubicacion_use_cases.dart';
import '../formato_ubicaciones.dart';
import '../mapa_base/mapa_base.dart';
import '../mapa_base/modelo_mapa_base.dart';
import '../pages/modificar_ubicacion_page.dart';
import '../providers/duplicados_providers.dart';
import '../providers/mapa_base_providers.dart';
import '../providers/uniones_pendientes_notifier.dart';
import 'mapa_alta.dart';
import 'piezas_alta.dart';
import 'piezas_lista_ubicaciones.dart' show ColoresLista;
import 'piezas_posibles_duplicados.dart';
import 'textos_posibles_duplicados.dart';

/// Abre la hoja de la vista 10·02: compara el par y deja elegir cuál conservar. Cierra sola cuando el
/// par deja de existir (se unió, se decidió o se corrigió una de las dos).
///
/// «Conservar A y unir» **no une**: deja la unión pendiente 8 s en `UnionesPendientesNotifier` y
/// cierra la hoja; el aviso con «Deshacer» lo muestra la pantalla de atrás.
Future<void> mostrarHojaCompararDuplicado(
  BuildContext context, {
  required String colportorId,
  required ParaRevisar par,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Sin arrastrar para cerrar: mientras se guarda una decisión la hoja no se puede cerrar de costado
  // (el arrastre no pasa por el `PopScope`). Las salidas son los botones y atrás.
  enableDrag: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaCompararDuplicado(colportorId: colportorId, inicial: par),
);

class HojaCompararDuplicado extends ConsumerStatefulWidget {
  const HojaCompararDuplicado({super.key, required this.colportorId, required this.inicial});

  final String colportorId;

  /// El par con el que se abrió. La hoja lo busca después en la lista viva (por su clave) y se
  /// queda con el último que vio.
  final ParaRevisar inicial;

  @override
  ConsumerState<HojaCompararDuplicado> createState() => _HojaCompararDuplicadoState();
}

class _HojaCompararDuplicadoState extends ConsumerState<HojaCompararDuplicado> {
  late ParaRevisar _par = widget.inicial;

  /// Cuál se conserva: por defecto la primera («A», la más vieja); el colportor puede elegir la otra.
  var _conservaLaPrimera = true;

  /// Una decisión guardándose («Son distintos», «Ignorar»): los botones esperan.
  var _guardando = false;

  /// La hoja ya se está cerrando: un segundo toque no cierra dos veces.
  var _cerrando = false;
  var _eligiendoCual = false;

  /// El par dejó de existir con otra ruta arriba de la hoja (la edición de «Editar uno»): la hoja se
  /// cierra cuando esa ruta vuelve, sin tocarla.
  var _cerrarAlVolver = false;
  Failure? _falla;
  ModalRoute<void>? _ruta;

  Ubicacion get _conservada => _conservaLaPrimera ? _par.par.a : _par.par.b;
  Ubicacion get _duplicada => _conservaLaPrimera ? _par.par.b : _par.par.a;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ruta = ModalRoute.of<void>(context);
  }

  /// Cierra **la ruta de la hoja**. `Navigator.pop()` saca la de más arriba, y con «Editar uno» hay
  /// otras encima: el selector «¿Cuál querés editar?» y la edición. Si una de ellas se llevaba el
  /// cierre, la hoja quedaba abierta mostrando un par que ya no existe y sin respuesta.
  void _cerrar() {
    if (_cerrando || !mounted) return;
    final ruta = _ruta;
    if (_eligiendoCual) {
      // El selector es de este par: si el par ya no existe, no hay nada que elegir.
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (ruta != null && !ruta.isCurrent) {
      // La edición está arriba: no se la saca (se perdería lo que está escribiendo). La hoja se cierra
      // al volver (`_editarUno`).
      _cerrarAlVolver = true;
      return;
    }
    _cerrando = true;
    Navigator.of(context).pop();
  }

  void _elegir({required bool laPrimera}) {
    if (_guardando || _conservaLaPrimera == laPrimera) return;
    setState(() => _conservaLaPrimera = laPrimera);
  }

  void _conservarYUnir() {
    if (_guardando || _cerrando) return;
    ref
        .read(unionesPendientesProvider.notifier)
        .unir(
          UnionPendiente(
            clavePar: _par.par.clave,
            conservarId: _conservada.id,
            duplicadaId: _duplicada.id,
            direccion: FormatoUbicaciones.direccion(_conservada),
          ),
        );
    _cerrar();
  }

  Future<void> _decidir(DecisionParDuplicado decision) async {
    if (_guardando || _cerrando) return;
    final decidir = ref.read(decidirParDuplicadoUseCaseProvider);
    setState(() {
      _guardando = true;
      _falla = null;
    });
    Failure? falla;
    try {
      final resultado = await decidir(DecidirParDuplicadoParams(par: _par.par, decision: decision));
      falla = resultado.fold((f) => f, (_) => null);
    } on Object catch (e) {
      falla = FailureInesperado(causa: e);
    }
    if (!mounted) return;
    if (falla == null) {
      // El par sale de la lista solo; la hoja se cierra con él.
      _cerrar();
      return;
    }
    setState(() {
      _guardando = false;
      _falla = falla;
    });
  }

  Future<void> _editarUno() async {
    if (_guardando || _cerrando || _eligiendoCual) return;
    setState(() => _eligiendoCual = true);
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _ElegirCualEditar(par: _par),
    );
    if (!mounted) return;
    setState(() => _eligiendoCual = false);
    if (id == null) return;
    await ModificarUbicacionPage.abrir(context, colportorId: widget.colportorId, ubicacionId: id);
    // Si mientras se editaba el par dejó de existir (por ejemplo, se corrigió la dirección), la hoja
    // ya no tiene nada que mostrar.
    if (mounted && _cerrarAlVolver) _cerrar();
  }

  @override
  Widget build(BuildContext context) {
    // La hoja sigue al par: si cambia (una de las dos se editó) se ve lo nuevo, y si ya no es un par
    // (se corrigió la dirección, se unió) se cierra.
    ref.listen(paresParaRevisarProvider(widget.colportorId), (_, nuevo) {
      final pares = nuevo.value;
      if (pares == null) return;
      final actual = pares.where((p) => p.par.clave == widget.inicial.par.clave).firstOrNull;
      if (actual == null) {
        _cerrar();
      } else if (actual != _par && mounted) {
        setState(() => _par = actual);
      }
    });

    final par = _par.par;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: !_guardando,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Asa(),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: TextosPosiblesDuplicados.esElMismoLugar,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: ' ${TextosPosiblesDuplicados.detalle(par)}'),
                    ],
                  ),
                  style: const TextStyle(fontFamily: 'SourceSerif4', fontSize: 18, height: 1.3),
                ),
              ),
              const SizedBox(height: 12),
              _MiniMapa(
                conservada: _conservada,
                duplicada: _duplicada,
                distanciaMetros: par.distanciaMetros,
              ),
              const SizedBox(height: 14),
              const Text(
                TextosPosiblesDuplicados.cualConservar,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                  letterSpacing: 1.4,
                  color: ColoresAlta.gris,
                ),
              ),
              const SizedBox(height: 8),
              _OpcionConservar(
                key: const Key('comparar_opcion_primera'),
                letra: _conservaLaPrimera ? 'A' : 'B',
                ubicacion: par.a,
                espacios: _par.espaciosA,
                estado: _par.estadoA,
                conservada: _conservaLaPrimera,
                alElegir: () => _elegir(laPrimera: true),
              ),
              const SizedBox(height: 8),
              _OpcionConservar(
                key: const Key('comparar_opcion_segunda'),
                letra: _conservaLaPrimera ? 'B' : 'A',
                ubicacion: par.b,
                espacios: _par.espaciosB,
                estado: _par.estadoB,
                conservada: !_conservaLaPrimera,
                alElegir: () => _elegir(laPrimera: false),
              ),
              const SizedBox(height: 10),
              Text(
                TextosPosiblesDuplicados.avisoUnion,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ColoresAlta.tinta),
              ),
              if (!par.admiteConservarAmbos) ...[
                const SizedBox(height: 10),
                Text(
                  TextosPosiblesDuplicados.direccionUnica,
                  key: const Key('comparar_direccion_unica'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ColoresAlta.tinta),
                ),
              ],
              if (_falla != null) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    TextosPosiblesDuplicados.noSePudoGuardar,
                    key: const Key('comparar_falla'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: ColoresAlta.rojo),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('comparar_conservar_y_unir'),
                onPressed: _guardando ? null : _conservarYUnir,
                style: _estiloPrincipal,
                child: const Text(TextosPosiblesDuplicados.conservarYUnir),
              ),
              if (par.admiteConservarAmbos) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('comparar_son_distintos'),
                  onPressed: _guardando
                      ? null
                      : () => unawaited(_decidir(DecisionParDuplicado.conservarAmbos)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                    foregroundColor: ColoresAlta.azul,
                    textStyle: _estiloBoton,
                  ),
                  child: const Text(TextosPosiblesDuplicados.sonDistintos),
                ),
              ],
              const SizedBox(height: 4),
              TextButton(
                key: const Key('comparar_despues'),
                onPressed: _guardando ? null : _cerrar,
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: ColoresAlta.azul,
                  textStyle: _estiloBoton,
                ),
                child: const Text(TextosPosiblesDuplicados.despues),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  EnlaceAlta(
                    key: const Key('comparar_ignorar'),
                    texto: TextosPosiblesDuplicados.ignorar,
                    alPresionar: _guardando
                        ? null
                        : () => unawaited(_decidir(DecisionParDuplicado.ignorar)),
                  ),
                  EnlaceAlta(
                    key: const Key('comparar_editar_uno'),
                    texto: TextosPosiblesDuplicados.editarUno,
                    alPresionar: _guardando ? null : () => unawaited(_editarUno()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _estiloBoton = TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static final _estiloPrincipal = FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
    shape: const StadiumBorder(),
    backgroundColor: const Color(0xFF002856),
    foregroundColor: Colors.white,
    textStyle: _estiloBoton,
  );
}

/// El asa de la hoja: solo adorno (la hoja no se arrastra).
class _Asa extends StatelessWidget {
  const _Asa();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: ColoresAlta.grisBorde,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// La opción «cuál conservar»: una ubicación del par, elegible. La elegida lleva la «A».
class _OpcionConservar extends StatelessWidget {
  const _OpcionConservar({
    super.key,
    required this.letra,
    required this.ubicacion,
    required this.espacios,
    required this.estado,
    required this.conservada,
    required this.alElegir,
  });

  final String letra;
  final Ubicacion ubicacion;
  final int espacios;
  final EstadoCasa? estado;
  final bool conservada;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    // El nombre y el toque van en UN nodo: el del lector de pantalla es esta opción entera («Ubicación
    // A, la que se conserva: …», botón, marcada o no) y no la dirección suelta de adentro, que sin
    // esto quedaba como un nodo aparte y la opción como un «botón» sin nombre.
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: conservada,
      label: FilaUbicacionPar.descripcion(
        letra: letra,
        ubicacion: ubicacion,
        espacios: espacios,
        estado: estado,
        etiqueta: conservada
            ? TextosPosiblesDuplicados.conservada(letra)
            : TextosPosiblesDuplicados.duplicada(letra),
      ),
      onTap: alElegir,
      child: Material(
        color: conservada ? ColoresAlta.azulFondo : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: conservada ? ColoresAlta.azul : ColoresAlta.grisBorde,
            width: conservada ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: alElegir,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilaUbicacionPar(
                      letra: letra,
                      ubicacion: ubicacion,
                      espacios: espacios,
                      estado: estado,
                      etiqueta: conservada
                          ? TextosPosiblesDuplicados.conservada(letra)
                          : TextosPosiblesDuplicados.duplicada(letra),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ExcludeSemantics(
                    child: Icon(
                      conservada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: conservada ? ColoresAlta.azul : ColoresLista.chevron,
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

/// La vista previa del par: A y B en el mapa, con la distancia entre las dos.
class _MiniMapa extends ConsumerWidget {
  const _MiniMapa({
    required this.conservada,
    required this.duplicada,
    required this.distanciaMetros,
  });

  final Ubicacion conservada;
  final Ubicacion duplicada;
  final double distanciaMetros;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ambito = AmbitoTrabajo(zonaId: conservada.zonaId, ciudadId: conservada.ciudadId);
    return Semantics(
      container: true,
      label:
          'Mapa con las dos ubicaciones, A y B, a ${FormatoUbicaciones.distancia(distanciaMetros)} '
          'una de la otra',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 150,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Una imagen del mapa, sin gestos: los toques siguen de largo hacia el scroll de la hoja.
              MapaBase(
                fuente: ref.watch(fuenteMapaProvider(ambito)),
                ajuste: AjusteMapa(
                  puntos: [conservada.coordenadas, duplicada.coordenadas],
                  margen: 40,
                  zoomMaximo: MapaAlta.zoomMaximoVistaPrevia,
                ),
                interaccion: InteraccionMapa.ninguna,
                fondo: ColoresAlta.fondoMapa,
                puntos: [
                  PuntoMapa(
                    id: conservada.id,
                    coordenadas: conservada.coordenadas,
                    estilo: EstiloPunto.candidata,
                    letra: 'A',
                  ),
                  PuntoMapa(
                    id: duplicada.id,
                    coordenadas: duplicada.coordenadas,
                    estilo: EstiloPunto.candidata,
                    letra: 'B',
                  ),
                ],
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: ColoresAlta.grisBorde),
                    ),
                    child: Text(
                      FormatoUbicaciones.distancia(distanciaMetros),
                      key: const Key('comparar_distancia'),
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «¿Cuál querés editar?»: elige cuál de las dos abrir en la edición (HU-UBI-004).
class _ElegirCualEditar extends StatelessWidget {
  const _ElegirCualEditar({required this.par});

  final ParaRevisar par;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text(TextosPosiblesDuplicados.editarCual),
      children: [
        _OpcionEditar(
          letra: 'A',
          ubicacion: par.par.a,
          resumen: TextosPosiblesDuplicados.resumen(par.par.a, par.espaciosA),
        ),
        _OpcionEditar(
          letra: 'B',
          ubicacion: par.par.b,
          resumen: TextosPosiblesDuplicados.resumen(par.par.b, par.espaciosB),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(TextosPosiblesDuplicados.cancelar),
        ),
      ],
    );
  }
}

class _OpcionEditar extends StatelessWidget {
  const _OpcionEditar({required this.letra, required this.ubicacion, required this.resumen});

  final String letra;
  final Ubicacion ubicacion;
  final String resumen;

  @override
  Widget build(BuildContext context) {
    void elegir() => Navigator.of(context).pop(ubicacion.id);
    // El nombre va en el nodo que se toca (el del `SimpleDialogOption`), no en uno de adentro.
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: '$letra: ${FormatoUbicaciones.direccion(ubicacion)}, $resumen',
      onTap: elegir,
      child: SimpleDialogOption(
        key: Key('editar_opcion_${ubicacion.id}'),
        onPressed: elegir,
        child: Row(
          children: [
            LetraPar(letra),
            const SizedBox(width: 10),
            Expanded(child: Text('${FormatoUbicaciones.direccion(ubicacion)} · $resumen')),
          ],
        ),
      ),
    );
  }
}
