import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/entities/motivo_baja.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/usecases/baja_ubicacion_use_cases.dart';
import '../formato_baja.dart';
import '../formato_lista_ubicaciones.dart';
import '../formato_ubicaciones.dart';
import '../providers/baja_ubicacion_providers.dart';
import '../providers/lista_ubicaciones_providers.dart';
import 'piezas_alta.dart';
import 'piezas_lista_ubicaciones.dart';

/// Textos de la vista 09·03 («Reactivar desde la lista») y 09·04 («Reactivada»). Los rótulos son los
/// de «TEXTOS PROPUESTA» del canvas; los avisos de error son provisorios (ni la HU ni el canvas los
/// traen).
abstract final class TextosReactivar {
  static const reactivar = 'Reactivar';
  static const cancelar = 'Cancelar';
  static const dadaDeBaja = 'Dada de baja';
  static const motivo = 'Motivo';
  static const ultimaVisita = 'Última visita';
  static const reactivando = 'Reactivando…';
  static const deshacer = 'Deshacer';

  /// «Av. Italia 1240 reactivada. Vuelve a aparecer en el mapa.»
  static String reactivada(String direccion) =>
      '$direccion reactivada. Vuelve a aparecer en el mapa.';

  // Provisorios.
  static const noPudimosReactivar = 'No pudimos reactivar la ubicación. Probá de nuevo.';
  static const noPudimosDeshacer =
      'No pudimos deshacer. Podés darla de baja de nuevo desde Editar.';
  static const deshecha = 'Volvió a quedar de baja.';

  /// Cuánto dura el aviso con «Deshacer» (canvas 09, «Deshacer dura 8 s»).
  static const duracionDeshacer = Duration(seconds: 8);
}

/// El texto del aviso rojo cuando no se pudo reactivar.
String mensajeFallaReactivar(Failure falla) => switch (falla) {
  FailureInesperado() => TextosReactivar.noPudimosReactivar,
  _ => mensajePara(falla, accion: 'reactivar la ubicación.'),
};

/// Abre la hoja de «Reactivar» de la baja [item] (vista 09·03). Devuelve la ubicación ya reactivada,
/// o `null` si el colportor cerró sin hacer nada.
///
/// [ultimaVisita] es el renglón «Última visita» («No contestó · 02/09»); `null` no lo muestra (hasta que
/// las visitas se guarden en el teléfono no hay de dónde sacarlo).
Future<Ubicacion?> mostrarHojaReactivar(
  BuildContext context, {
  required String colportorId,
  required ItemListaUbicacion item,
  String? ultimaVisita,
}) => showModalBottomSheet<Ubicacion>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Sin arrastrar para cerrar: mientras reactiva, la hoja no se puede cerrar de costado.
  enableDrag: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) =>
      HojaReactivarUbicacion(colportorId: colportorId, item: item, ultimaVisita: ultimaVisita),
);

/// La hoja de «Reactivar» (vista 09·03): el círculo punteado, la dirección, qué es, y los renglones
/// «Dada de baja», «Motivo» y «Última visita». La única acción es «Reactivar» (y «Cancelar»).
///
/// Mientras reactiva, el botón dice «Reactivando…» y no hay nada que tocar ni forma de cerrar; si
/// falla, el aviso rojo y el botón vuelve a quedar habilitado.
class HojaReactivarUbicacion extends ConsumerStatefulWidget {
  const HojaReactivarUbicacion({
    super.key,
    required this.colportorId,
    required this.item,
    this.ultimaVisita,
  });

  final String colportorId;
  final ItemListaUbicacion item;

  /// «No contestó · 02/09»; `null` oculta el renglón.
  final String? ultimaVisita;

  @override
  ConsumerState<HojaReactivarUbicacion> createState() => _HojaReactivarUbicacionState();
}

class _HojaReactivarUbicacionState extends ConsumerState<HojaReactivarUbicacion> {
  var _enviando = false;
  Failure? _falla;

  Future<void> _reactivar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _falla = null;
    });
    final u = widget.item.ubicacion;
    Failure? falla;
    Ubicacion? reactivada;
    try {
      final r = await ref.read(reactivarUbicacionUseCaseProvider)(
        ReactivarUbicacionParams(id: u.id, baseUpdatedAt: u.auditoria.updatedAt),
      );
      falla = r.fold<Failure?>((f) => f, (_) => null);
      reactivada = r.fold<Ubicacion?>((_) => null, (x) => x);
    } on Object catch (e) {
      falla = FailureInesperado(causa: e);
    }
    if (!mounted) return;
    if (reactivada != null) {
      Navigator.of(context).pop(reactivada);
      return;
    }
    setState(() {
      _enviando = false;
      _falla = falla ?? const FailureInesperado();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = widget.item.ubicacion;
    final ciudades = ref.watch(ciudadesListaProvider(widget.colportorId));
    final ciudad = ciudades.hasValue
        ? FormatoListaUbicaciones.ciudad(ciudades.value, u.ciudadId)
        : null;
    final subtitulo = [
      FormatoUbicaciones.tipo(u.tipo),
      FormatoListaUbicaciones.espacios(widget.item.cantidadEspacios),
      ?ciudad,
    ].join(' · ');
    final borrada = u.auditoria.deletedAt;
    final motivo = MotivosBaja.paraMostrar(widget.item.motivoBaja);

    return PopScope(
      canPop: !_enviando,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF90A0B7),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(padding: EdgeInsets.only(top: 4), child: InsigniaBaja()),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(
                                  header: true,
                                  liveRegion: true,
                                  child: Text(
                                    FormatoUbicaciones.direccion(u),
                                    style: const TextStyle(
                                      fontFamily: 'SourceSerif4',
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitulo,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 13.5,
                                    color: ColoresAlta.gris,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (borrada != null)
                        _Renglon(
                          etiqueta: TextosReactivar.dadaDeBaja,
                          valor: FormatoBaja.fecha(borrada),
                        ),
                      if (motivo != null) ...[
                        const SizedBox(height: 8),
                        _Renglon(etiqueta: TextosReactivar.motivo, valor: motivo),
                      ],
                      if (widget.ultimaVisita != null) ...[
                        const SizedBox(height: 8),
                        _Renglon(
                          etiqueta: TextosReactivar.ultimaVisita,
                          valor: widget.ultimaVisita!,
                        ),
                      ],
                      if (_falla != null) ...[
                        const SizedBox(height: 12),
                        AvisoAlta(
                          color: ColoresAlta.rojo,
                          glyph: '!',
                          texto: mensajeFallaReactivar(_falla!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _enviando ? null : () => unawaited(_reactivar()),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(
                  _enviando ? TextosReactivar.reactivando : TextosReactivar.reactivar,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _enviando ? null : () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: ColoresAlta.azul,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text(TextosReactivar.cancelar, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un renglón con borde de la hoja: la etiqueta a la izquierda y el dato a la derecha. Con texto
/// agrandado se apilan, para que ninguno de los dos se corte.
class _Renglon extends StatelessWidget {
  const _Renglon({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final apilado = textoGrande(context);
    const estiloEtiqueta = TextStyle(fontSize: 13.5, color: ColoresAlta.gris);
    const estiloValor = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);
    return Semantics(
      container: true,
      label: '$etiqueta: $valor',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ColoresAlta.grisFondo),
        ),
        child: apilado
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiqueta, style: estiloEtiqueta),
                  const SizedBox(height: 2),
                  Text(valor, style: estiloValor),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiqueta, style: estiloEtiqueta),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(valor, textAlign: TextAlign.end, style: estiloValor),
                  ),
                ],
              ),
      ),
    );
  }
}
