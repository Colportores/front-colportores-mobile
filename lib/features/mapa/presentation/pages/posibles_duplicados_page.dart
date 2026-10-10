import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/usecases/duplicados_ubicacion_use_cases.dart';
import '../providers/duplicados_providers.dart';
import '../providers/uniones_pendientes_notifier.dart';
import '../widgets/hoja_comparar_duplicado.dart';
import '../widgets/piezas_alta.dart' show AvisoAlta, ColoresAlta, EnlaceAlta;
import '../widgets/piezas_lista_ubicaciones.dart' show ColoresLista;
import '../widgets/piezas_posibles_duplicados.dart';
import '../widgets/textos_posibles_duplicados.dart';

/// «Posibles duplicados» (vista 10, HU-UBI-006): los pares de ubicaciones propias con la misma calle
/// y número, o a menos de 5 m, para revisar de a uno en la hoja de comparar (`HojaCompararDuplicado`).
///
/// Se entra desde el aviso «N posibles duplicados · Revisar» de la Lista. La lista de pares es la del
/// teléfono, en vivo: un par que se une, se decide o se corrige sale solo. «Conservar A y unir» deja
/// la unión esperando 8 s con «Deshacer» (`UnionesPendientesNotifier`); el par esperando no se ve
/// en la lista, y sale definitivo al cumplirse el tiempo o al salir de la pantalla.
class PosiblesDuplicadosPage extends ConsumerStatefulWidget {
  const PosiblesDuplicadosPage({super.key, required this.colportorId});

  /// UUID del colportor con la sesión iniciada: se revisan las ubicaciones que registró.
  final String colportorId;

  /// Abre «Posibles duplicados» encima de la pantalla actual.
  static Future<void> abrir(BuildContext context, {required String colportorId}) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => PosiblesDuplicadosPage(colportorId: colportorId)));

  @override
  ConsumerState<PosiblesDuplicadosPage> createState() => _PosiblesDuplicadosPageState();
}

class _PosiblesDuplicadosPageState extends ConsumerState<PosiblesDuplicadosPage> {
  /// El aviso «quedaron unidas en una» que esta pantalla tiene abierto, si lo tiene, y el mensajero
  /// donde lo abrió. Al salir se cierra solo si es nuestro: el mensajero es el de toda la app.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _aviso;
  ScaffoldMessengerState? _mensajero;

  /// Una sola hoja a la vez: un segundo toque en «Revisar» no abre otra encima.
  var _abriendoHoja = false;

  @override
  void dispose() {
    _ocultarAviso();
    super.dispose();
  }

  Future<void> _abrirHoja(ParaRevisar par) async {
    if (_abriendoHoja) return;
    _abriendoHoja = true;
    try {
      await mostrarHojaCompararDuplicado(context, colportorId: widget.colportorId, par: par);
    } finally {
      _abriendoHoja = false;
    }
  }

  /// El aviso de la vista 10·03: «Las dos Av. Italia 1234 quedaron unidas en una.» con «Deshacer».
  /// Dura lo que la espera (8 s); si se hace otra unión, el aviso nuevo reemplaza al anterior.
  void _mostrarAviso(UnionPendiente union) {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    if (mensajero == null) return;
    final notificador = ref.read(unionesPendientesProvider.notifier);
    final plazo = ref.read(plazoDeshacerUnionProvider);
    final mediaQuery = MediaQuery.of(context);
    // Con el texto grande «Deshacer» va debajo del aviso, no al lado (mismo motivo que en la Lista:
    // Flutter mide la acción sin la escala del texto y la deja en una columna angosta).
    final textoGrande = mediaQuery.textScaler.scale(14) / 14 > 1.3;
    final texto = Text(
      TextosPosiblesDuplicados.unidas(union.direccion),
      style: const TextStyle(fontSize: 13.5, color: Colors.white),
    );
    final deshacer = SnackBarAction(
      label: TextosPosiblesDuplicados.deshacer,
      textColor: const Color(0xFFC9D6EA),
      onPressed: () {
        if (mounted) notificador.deshacer();
      },
    );
    _ocultarAviso();
    final aviso = mensajero.showSnackBar(
      SnackBar(
        duration: plazo,
        // Con un lector de pantalla el aviso no se cierra solo (WCAG 2.2.1): se cierra cuando la
        // unión se hace, a los 8 s (`_ocultarAviso`).
        persist: mediaQuery.accessibleNavigation,
        // Sin arrastrar para cerrarlo: «Deshacer» es lo único que sale de ahí antes de los 8 s.
        dismissDirection: DismissDirection.none,
        backgroundColor: ColoresLista.tinta,
        content: textoGrande
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  texto,
                  Align(alignment: AlignmentDirectional.centerEnd, child: deshacer),
                ],
              )
            : texto,
        action: textoGrande ? null : deshacer,
      ),
    );
    _aviso = aviso;
    _mensajero = mensajero;
    unawaited(
      aviso.closed.then((_) {
        if (identical(_aviso, aviso)) _aviso = null;
      }),
    );
  }

  /// Cierra el aviso si es el nuestro. Se limpia la cola entera (no `close()` del aviso): con uno que
  /// todavía se está yendo, el nuestro puede no ser el primero de la cola.
  void _ocultarAviso() {
    if (_aviso == null) return;
    _aviso = null;
    _mensajero?.clearSnackBars();
  }

  @override
  Widget build(BuildContext context) {
    // El aviso sigue a la unión que espera: aparece con «Conservar A y unir» y se va con «Deshacer»
    // o cuando la unión se hace.
    ref.listen(unionesPendientesProvider.select((s) => s.pendiente), (_, pendiente) {
      if (pendiente == null) {
        _ocultarAviso();
      } else {
        _mostrarAviso(pendiente);
      }
    });

    final lectura = ref.watch(paresParaRevisarProvider(widget.colportorId));
    final uniones = ref.watch(unionesPendientesProvider);
    final pares = lectura.value;
    final visibles = pares == null
        ? const <ParaRevisar>[]
        : [
            for (final p in pares)
              if (!uniones.ocultas.contains(p.par.clave)) p,
          ];

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF7),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Barra(),
            Expanded(
              child: pares == null
                  ? _SinLista(
                      falla: lectura.hasError,
                      alReintentar: () =>
                          ref.invalidate(paresParaRevisarProvider(widget.colportorId)),
                    )
                  : visibles.isEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (uniones.falla != null) _AvisoFalla(falla: uniones.falla!),
                        const Expanded(child: _Vacio()),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: visibles.length + 1 + (uniones.falla == null ? 0 : 1),
                      itemBuilder: (context, i) {
                        if (i == 0) return _Encabezado(cantidad: visibles.length);
                        final falla = uniones.falla;
                        if (falla != null && i == 1) return _AvisoFalla(falla: falla);
                        final item = visibles[i - 1 - (falla == null ? 0 : 1)];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _TarjetaPar(
                            item: item,
                            alRevisar: () => unawaited(_abrirHoja(item)),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La barra de arriba: «‹ POSIBLES DUPLICADOS».
class _Barra extends StatelessWidget {
  const _Barra();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 14, 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('duplicados_volver'),
            tooltip: TextosPosiblesDuplicados.volver,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.chevron_left, size: 28, color: ColoresAlta.tinta),
            onPressed: () => unawaited(Navigator.of(context).maybePop()),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              header: true,
              label: TextosPosiblesDuplicados.titulo,
              excludeSemantics: true,
              child: const Text(
                TextosPosiblesDuplicados.etiquetaBarra,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF002856),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «3 para revisar» y la explicación.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.cantidad});

  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              TextosPosiblesDuplicados.paraRevisar(cantidad),
              key: const Key('duplicados_titulo'),
              style: const TextStyle(
                fontFamily: 'SourceSerif4',
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            TextosPosiblesDuplicados.subtitulo,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: ColoresAlta.tinta, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// Un par: el motivo y la distancia, las dos ubicaciones y «Revisar».
class _TarjetaPar extends StatelessWidget {
  const _TarjetaPar({required this.item, required this.alRevisar});

  final ParaRevisar item;
  final VoidCallback alRevisar;

  @override
  Widget build(BuildContext context) {
    final par = item.par;
    return Container(
      key: Key('par_${par.clave}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE3E7EE)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EncabezadoMotivoPar(
            motivo: TextosPosiblesDuplicados.motivo(par.motivo),
            distancia: TextosPosiblesDuplicados.aDistancia(par.distanciaMetros),
          ),
          const SizedBox(height: 10),
          FilaUbicacionPar(
            letra: 'A',
            ubicacion: par.a,
            espacios: item.espaciosA,
            estado: item.estadoA,
          ),
          const SizedBox(height: 10),
          FilaUbicacionPar(
            letra: 'B',
            ubicacion: par.b,
            espacios: item.espaciosB,
            estado: item.estadoB,
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: Key('revisar_${par.clave}'),
            onPressed: alRevisar,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
              backgroundColor: const Color(0xFF002856),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text(TextosPosiblesDuplicados.revisar),
          ),
        ],
      ),
    );
  }
}

/// El aviso rojo cuando la unión no se pudo hacer (HU-UBI-006, «Edge - la unión local falla»).
class _AvisoFalla extends ConsumerWidget {
  const _AvisoFalla({required this.falla});

  final FallaUnion falla;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificador = ref.read(unionesPendientesProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: AvisoAlta(
        key: const Key('duplicados_falla_union'),
        color: ColoresAlta.rojo,
        glyph: '!',
        texto: TextosPosiblesDuplicados.falloUnion(falla.falla),
        acciones: Wrap(
          children: [
            if (falla.sePuedeReintentar)
              EnlaceAlta(
                key: const Key('duplicados_reintentar_union'),
                texto: TextosPosiblesDuplicados.reintentar,
                alPresionar: notificador.reintentar,
              ),
            EnlaceAlta(
              key: const Key('duplicados_descartar_falla'),
              texto: TextosPosiblesDuplicados.entendido,
              alPresionar: notificador.descartarFalla,
            ),
          ],
        ),
      ),
    );
  }
}

/// No hay pares (todavía, o ya no): la pantalla vacía.
class _Vacio extends StatelessWidget {
  const _Vacio();

  @override
  Widget build(BuildContext context) {
    return _Centrado(
      children: [
        Semantics(
          header: true,
          liveRegion: true,
          child: const Text(
            TextosPosiblesDuplicados.vacioTitulo,
            key: Key('duplicados_vacio'),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'SourceSerif4', fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        const Text(TextosPosiblesDuplicados.vacioCuerpo, textAlign: TextAlign.center),
      ],
    );
  }
}

/// Todavía no hay lista: leyendo, o no se pudo leer.
class _SinLista extends StatelessWidget {
  const _SinLista({required this.falla, required this.alReintentar});

  final bool falla;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    if (falla) {
      return _Centrado(
        children: [
          // Se anuncia al aparecer: un lector de pantalla no tiene otra forma de enterarse.
          Semantics(
            liveRegion: true,
            child: const Text(
              TextosPosiblesDuplicados.errorLectura,
              key: Key('duplicados_error_lectura'),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          EnlaceAlta(
            key: const Key('duplicados_reintentar_lectura'),
            texto: TextosPosiblesDuplicados.reintentar,
            alPresionar: alReintentar,
          ),
        ],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ExcludeSemantics(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              TextosPosiblesDuplicados.cargando,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: ColoresColportaje.unica.gris,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Contenido centrado que se desplaza si con el texto grande no entra.
class _Centrado extends StatelessWidget {
  const _Centrado({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
