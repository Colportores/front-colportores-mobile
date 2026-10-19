import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/usecases/duplicados_ubicacion_use_cases.dart';
import '../providers/duplicados_providers.dart';
import '../providers/uniones_pendientes_notifier.dart';
import '../widgets/hoja_comparar_duplicado.dart';
import '../widgets/piezas_alta.dart' show AvisoAlta, ColoresAlta, EnlaceAlta, InsigniaCirculo;
import '../widgets/piezas_lista_ubicaciones.dart' show ColoresLista;
import '../widgets/piezas_posibles_duplicados.dart';
import '../widgets/textos_posibles_duplicados.dart';

/// «Posibles duplicados» (vista 10, HU-UBI-006): los pares de ubicaciones propias con la misma calle
/// y número, o a menos de 5 m, para revisar de a uno en la hoja de comparar (`HojaCompararDuplicado`).
///
/// Se entra desde el aviso «N posibles duplicados · Revisar» de la Lista. La lista de pares es la del
/// teléfono, en vivo: un par que se une, se decide o se corrige sale solo. «Conservar A y unir» deja
/// la unión esperando 8 s con «Deshacer» (`UnionesPendientesNotifier`); el par esperando no se ve
/// en la lista (ni los otros pares que contienen a la que quedaría de baja), y sale definitivo al
/// cumplirse el tiempo o al salir de la pantalla.
///
/// Si una unión no se puede hacer, el aviso rojo queda FIJO debajo de la barra (no dentro de la lista,
/// donde se iba de vista al bajar): con una falla dice por qué; con dos o más, cuántos pares son. Con
/// el texto agrandado no pasa del 200 % y, si no entra, se desplaza: la lista siempre tiene lugar. Mientras
/// el «quedaron unidas en una» está a la vista el aviso rojo se achica a una línea con la cuenta y
/// «Reintentar» (#362), y ese otro aviso tampoco pasa del 200 %.
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

  /// Lo más que ocupa el aviso rojo de la altura disponible: el resto es de la lista.
  static const _fraccionMaximaDelAviso = 0.5;

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
        // Con un lector de pantalla el aviso no se cierra solo (le da tiempo de leerlo y de llegar a
        // «Deshacer»): se va cuando la unión se hace o con «Deshacer» (`_ocultarAviso`). Eso NO cumple
        // WCAG 2.2.1 (límite de tiempo ajustable): la unión se hace igual a los 8 s, también con
        // lector. Cuánto espera con lector lo decide Cristian (mobile-208-impl-p6-deshacer-lector).
        persist: mediaQuery.accessibleNavigation,
        // Sin arrastrar para cerrarlo: «Deshacer» es lo único que sale de ahí antes de los 8 s.
        dismissDirection: DismissDirection.none,
        backgroundColor: ColoresLista.tinta,
        // El texto no pasa del 200 %, como el del aviso rojo (#362): a 300 % en un teléfono chico el
        // aviso ocupaba más de la mitad de la pantalla y, con el aviso rojo, no dejaba ver la lista.
        content: _EscalaAcotada(
          child: textoGrande
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    texto,
                    Align(alignment: AlignmentDirectional.centerEnd, child: deshacer),
                  ],
                )
              : texto,
        ),
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
    // Las claves de los pares que siguen para revisar: una falla cuyo par ya no está (se decidió,
    // se unió por otro lado, dejó de ser un par) no se avisa ni se reintenta.
    final clavesDePares = pares == null ? null : {for (final p in pares) p.par.clave};
    final fallas = uniones.fallasVigentes(clavesDePares);
    final visibles = pares == null
        ? const <ParaRevisar>[]
        : [
            for (final p in pares)
              if (!uniones.oculta(p.par)) p,
          ];

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF7),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, restricciones) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Barra(),
              if (fallas.isNotEmpty)
                _AvisoFalla(
                  fallas: fallas,
                  paresVigentes: clavesDePares,
                  alturaMaxima: restricciones.maxHeight * _fraccionMaximaDelAviso,
                  // Con el «quedaron unidas en una» a la vista el aviso rojo se achica (#362).
                  compacto: uniones.pendiente != null,
                ),
              Expanded(
                child: pares == null
                    ? _SinLista(
                        falla: lectura.hasError,
                        alReintentar: () =>
                            ref.invalidate(paresParaRevisarProvider(widget.colportorId)),
                      )
                    : visibles.isEmpty
                    ? const _Vacio()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: visibles.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) return _Encabezado(cantidad: visibles.length);
                          final item = visibles[i - 1];
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

/// El aviso rojo cuando una unión no se pudo hacer (HU-UBI-006, «Edge - la unión local falla»), fijo
/// debajo de la barra. Con una falla dice por qué; con dos o más, cuántos pares son. «Reintentar»
/// prueba todas las que se pueden reintentar y las que vuelven a fallar quedan con su cuenta.
///
/// El texto no pasa del 200 % ([escalaMaximaDelAviso]): este aviso comparte la pantalla con la lista y,
/// a 320×568, más grande no deja lugar. Si aun así no entra en [alturaMaxima], se desplaza solo el
/// texto: «Reintentar» y «Entendido» quedan siempre enteros a la vista.
///
/// Mientras el aviso «quedaron unidas en una» está a la vista ([compacto]) el aviso rojo se achica a
/// una línea con la cuenta y «Reintentar» (#362): los dos juntos taparían la lista en un teléfono chico.
/// Tocar la línea muestra el aviso entero, con el texto completo y «Entendido», hasta que el otro aviso
/// se va; entonces vuelve a su tamaño. Es el mismo nodo de región viva en las dos formas (la etiqueta es
/// el texto entero): pasar de una a otra no hace que el lector repita el aviso.
class _AvisoFalla extends ConsumerStatefulWidget {
  const _AvisoFalla({
    required this.fallas,
    required this.paresVigentes,
    required this.alturaMaxima,
    required this.compacto,
  });

  final List<FallaUnion> fallas;

  /// Las claves de los pares que siguen para revisar (`null` mientras no se leyeron).
  final Set<String>? paresVigentes;
  final double alturaMaxima;

  /// Hay un «quedaron unidas en una» a la vista: el aviso se achica.
  final bool compacto;

  /// El tamaño más grande del texto del aviso: el 200 % de WCAG 1.4.4, que a 320×568 deja la lista a la
  /// vista (revisión de #357).
  static const escalaMaximaDelAviso = 2.0;

  @override
  ConsumerState<_AvisoFalla> createState() => _AvisoFallaState();
}

class _AvisoFallaState extends ConsumerState<_AvisoFalla> {
  /// La persona tocó la línea y pidió ver el aviso entero mientras dura el «quedaron unidas».
  var _completo = false;

  @override
  void didUpdateWidget(_AvisoFalla anterior) {
    super.didUpdateWidget(anterior);
    // Al irse el otro aviso se olvida lo pedido: el próximo «quedaron unidas» vuelve a empezar compacto.
    if (!widget.compacto) _completo = false;
  }

  @override
  Widget build(BuildContext context) {
    final notificador = ref.read(unionesPendientesProvider.notifier);
    final fallas = widget.fallas;
    final texto = TextosPosiblesDuplicados.falloUniones([for (final f in fallas) f.falla]);
    final sePuedeReintentar = fallas.any((f) => f.sePuedeReintentar);
    void reintentar() => notificador.reintentar(paresVigentes: widget.paresVigentes);
    final compacto = widget.compacto && !_completo;
    return _EscalaAcotada(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Semantics(
          liveRegion: true,
          container: true,
          label: texto,
          child: compacto
              ? _FallaCompacta(
                  key: const Key('duplicados_falla_union'),
                  texto: texto,
                  cuenta: TextosPosiblesDuplicados.cuentaDeFallas(fallas.length),
                  alVerCompleta: () => setState(() => _completo = true),
                  alReintentar: sePuedeReintentar ? reintentar : null,
                )
              : AvisoAlta(
                  key: const Key('duplicados_falla_union'),
                  color: ColoresAlta.rojo,
                  glyph: '!',
                  texto: texto,
                  conRegionViva: false,
                  alturaMaxima: widget.alturaMaxima - 12,
                  acciones: Wrap(
                    children: [
                      if (sePuedeReintentar)
                        EnlaceAlta(
                          key: const Key('duplicados_reintentar_union'),
                          texto: TextosPosiblesDuplicados.reintentar,
                          alPresionar: reintentar,
                        ),
                      EnlaceAlta(
                        key: const Key('duplicados_descartar_falla'),
                        texto: TextosPosiblesDuplicados.entendido,
                        alPresionar: notificador.descartarFalla,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// El texto de [child] no pasa del 200 % ([_AvisoFalla.escalaMaximaDelAviso]): el aviso rojo y el
/// «quedaron unidas en una» comparten la pantalla con la lista.
class _EscalaAcotada extends StatelessWidget {
  const _EscalaAcotada({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: mediaQuery.textScaler.clamp(maxScaleFactor: _AvisoFalla.escalaMaximaDelAviso),
      ),
      child: child,
    );
  }
}

/// El aviso rojo en su forma de una línea: «! 2 no se pudieron unir ⌄  Reintentar». La línea entera es un
/// botón que muestra el aviso completo; «Reintentar» (si hay algo para reintentar) va aparte, a un toque.
/// Con el texto grande la cuenta y «Reintentar» pasan a renglones distintos (`Wrap`), cada uno de 48 dp
/// como mínimo.
class _FallaCompacta extends StatelessWidget {
  const _FallaCompacta({
    super.key,
    required this.texto,
    required this.cuenta,
    required this.alVerCompleta,
    required this.alReintentar,
  });

  /// El texto entero del aviso: lo dice el nodo de región viva de afuera y va en el nombre del botón.
  final String texto;

  /// «2 no se pudieron unir».
  final String cuenta;
  final VoidCallback alVerCompleta;

  /// `null`: ninguna de las fallas se puede reintentar.
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    final reintentar = alReintentar;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ColoresAlta.rojo, width: 1.5),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            button: true,
            container: true,
            excludeSemantics: true,
            label: '$cuenta. ${TextosPosiblesDuplicados.verAvisoCompleto}',
            onTap: alVerCompleta,
            child: InkWell(
              key: const Key('duplicados_falla_ver_completa'),
              borderRadius: BorderRadius.circular(10),
              onTap: alVerCompleta,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const InsigniaCirculo(color: ColoresAlta.rojo, glyph: '!'),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          cuenta,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.expand_more, size: 20, color: ColoresAlta.tinta),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (reintentar != null)
            EnlaceAlta(
              key: const Key('duplicados_reintentar_union'),
              texto: TextosPosiblesDuplicados.reintentar,
              alPresionar: reintentar,
            ),
        ],
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
