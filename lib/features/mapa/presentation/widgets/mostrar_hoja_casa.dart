import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/lista_ubicaciones.dart';
import '../formato_mapa_ubicaciones.dart';
import '../providers/lista_ubicaciones_notifier.dart';
import '../providers/lista_ubicaciones_providers.dart';
import 'hoja_casa.dart';
import 'hoja_mapa_ubicaciones.dart' show AlturaHoja;
import 'piezas_hoja_casa.dart';
import 'piezas_lista_ubicaciones.dart' show ColoresLista;

/// Abre la hoja de la casa desde la Lista (vista 05): «la misma que en el mapa»
/// (`00 Navegacion.dc.html`). Es una hoja modal que abre en el resumen (C·01, un tercio de la
/// pantalla) y, con el mismo gesto que en el mapa (arrastrar el asa hacia arriba o tocarla), sube a la
/// hoja arriba (C·02, la mitad) con las pestañas. Bajarla desde la hoja arriba vuelve al resumen y
/// bajarla desde el resumen la cierra; la ✕, el atrás del teléfono y tocar afuera también la cierran
/// sin cambiar nada. No hay altura mínima: detrás no hay mapa.
///
/// La hoja sigue a la Lista: si la casa cambia mientras está abierta (se reactivó, cambió su color)
/// se ve el cambio; si la casa sale de la lista que se está viendo (otro filtro) queda la última
/// que se tuvo. [alReactivar] es el «Reactivar» de una casa dada de baja (E·04); sin él, el aviso va
/// sin acción.
Future<void> mostrarHojaCasa(
  BuildContext context, {
  required String colportorId,
  required ItemListaUbicacion item,
  FutureOr<void> Function(ItemListaUbicacion item)? alReactivar,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // El asa es propia (sube y baja entre las dos alturas): el arrastre del modal no compite con ella.
  enableDrag: false,
  showDragHandle: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) =>
      _HojaCasaDeLaLista(colportorId: colportorId, inicial: item, alReactivar: alReactivar),
);

class _HojaCasaDeLaLista extends ConsumerWidget {
  const _HojaCasaDeLaLista({
    required this.colportorId,
    required this.inicial,
    required this.alReactivar,
  });

  final String colportorId;
  final ItemListaUbicacion inicial;
  final FutureOr<void> Function(ItemListaUbicacion item)? alReactivar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = inicial.ubicacion.id;
    final vivo = ref.watch(
      listaUbicacionesProvider(colportorId).select((estado) {
        for (final fila in estado.lista?.items ?? const <ItemListaUbicacion>[]) {
          if (fila.ubicacion.id == id) return fila;
        }
        return null;
      }),
    );
    final item = vivo ?? inicial;
    final ahora = ref.watch(relojListaUbicacionesProvider)();
    return _AlturasDeLaLista(
      alBajarDelResumen: () => Navigator.of(context).maybePop(),
      hoja: (arriba) => HojaCasa(
        item: item,
        ahora: ahora,
        alCerrar: () => Navigator.of(context).maybePop(),
        alReactivar: alReactivar == null || !item.puedeReactivarse
            ? null
            : () => alReactivar!(item),
        arriba: arriba,
        colportorId: colportorId,
      ),
    );
  }
}

/// Las dos alturas de la hoja de la Lista (las del mapa que corresponden): el resumen
/// ([AlturaHoja.tercio]) y arriba ([AlturaHoja.mitad]). La hoja de la casa es la misma en las dos
/// (su estado, la pestaña y el aviso del alta, se conserva al cambiar de altura).
class _AlturasDeLaLista extends StatefulWidget {
  const _AlturasDeLaLista({required this.hoja, required this.alBajarDelResumen});

  final Widget Function(bool arriba) hoja;

  /// Bajar la hoja desde el resumen: se cierra.
  final VoidCallback alBajarDelResumen;

  @override
  State<_AlturasDeLaLista> createState() => _AlturasDeLaListaState();
}

class _AlturasDeLaListaState extends State<_AlturasDeLaLista> {
  AlturaHoja _altura = AlturaHoja.tercio;

  /// Lo que se arrastró el asa desde que empezó el gesto (negativo = hacia arriba).
  double _arrastre = 0;

  bool get _arriba => _altura == AlturaHoja.mitad;

  void _subir() {
    if (!_arriba) setState(() => _altura = AlturaHoja.mitad);
  }

  void _bajar() {
    if (_arriba) {
      setState(() => _altura = AlturaHoja.tercio);
    } else {
      widget.alBajarDelResumen();
    }
  }

  void _alSoltar(DragEndDetails detalle) {
    final velocidad = detalle.primaryVelocity ?? 0;
    final desplazado = _arrastre;
    _arrastre = 0;
    if (desplazado < -24 || velocidad < -400) {
      _subir();
    } else if (desplazado > 24 || velocidad > 400) {
      _bajar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pantalla = MediaQuery.sizeOf(context).height;
    final alto = _altura.alto(
      pantalla: pantalla,
      disponible: pantalla,
      escala: MediaQuery.textScalerOf(context),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: alto,
      child: Column(
        children: [
          _AsaDeLaLista(
            altura: _altura,
            alTocar: () => _arriba ? _bajarAlResumen() : _subir(),
            alSubir: _arriba ? null : _subir,
            alBajarUnaAltura: _arriba ? _bajarAlResumen : null,
            alEmpezarArrastre: () => _arrastre = 0,
            alArrastrar: (delta) => _arrastre += delta,
            alSoltar: _alSoltar,
            alCancelar: () => _arrastre = 0,
          ),
          Expanded(child: widget.hoja(_arriba)),
        ],
      ),
    );
  }

  /// Tocar el asa con la hoja arriba la devuelve al resumen (no la cierra).
  void _bajarAlResumen() => setState(() => _altura = AlturaHoja.tercio);
}

/// El asa de la hoja de la Lista: la manija (44 × 5) y dos puntos que dicen en cuál de las dos alturas
/// está. Mide 48 dp de alto. Se arrastra o se toca; para el lector de pantalla, «subir» y «bajar».
class _AsaDeLaLista extends StatelessWidget {
  const _AsaDeLaLista({
    required this.altura,
    required this.alTocar,
    required this.alSubir,
    required this.alBajarUnaAltura,
    required this.alEmpezarArrastre,
    required this.alArrastrar,
    required this.alSoltar,
    required this.alCancelar,
  });

  final AlturaHoja altura;
  final VoidCallback alTocar;
  final VoidCallback? alSubir;
  final VoidCallback? alBajarUnaAltura;
  final VoidCallback alEmpezarArrastre;
  final ValueChanged<double> alArrastrar;
  final GestureDragEndCallback alSoltar;
  final VoidCallback alCancelar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: TextosMapaUbicaciones.cambiarAltura,
      value: altura.descripcion,
      increasedValue: AlturaHoja.mitad.descripcion,
      decreasedValue: AlturaHoja.tercio.descripcion,
      onTap: alTocar,
      onIncrease: alSubir,
      onDecrease: alBajarUnaAltura,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: ClavesHojaCasa.asaDeLaLista,
          behavior: HitTestBehavior.opaque,
          onTap: alTocar,
          onVerticalDragStart: (_) => alEmpezarArrastre(),
          onVerticalDragUpdate: (d) => alArrastrar(d.delta.dy),
          onVerticalDragEnd: alSoltar,
          onVerticalDragCancel: alCancelar,
          child: SizedBox(
            height: AlturaHoja.altoAsa,
            width: double.infinity,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: ColoresLista.chevron,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 18,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      for (final nivel in const [AlturaHoja.tercio, AlturaHoja.mitad])
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: nivel.index <= altura.index
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            border: nivel.index <= altura.index
                                ? null
                                : Border.all(color: ColoresLista.chevron, width: 1.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
