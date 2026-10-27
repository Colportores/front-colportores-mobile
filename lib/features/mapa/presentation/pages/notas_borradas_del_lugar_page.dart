import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/nota_ubicacion.dart';
import '../providers/notas_ubicacion_providers.dart';
import '../providers/personas_providers.dart';
import '../textos_notas.dart';
import '../widgets/piezas_alta.dart';
import '../widgets/piezas_notas.dart';

/// Las notas borradas de un lugar (vista 39, C·05; la pantalla es la E·05 de la vista 32E): se ven
/// atenuadas y cada una tiene «Restaurar». Se llega desde «Ver borradas (n)» de la pestaña Notas.
///
/// - Restaurar devuelve la nota a la lista con su fecha y su texto; el aviso «Nota restaurada.» lo
///   confirma. Si falla, el aviso dice qué pasó y ofrece «Reintentar».
/// - Cada nota tiene su propia guarda: un doble toque sobre «Restaurar» no lo repite.
/// - Las notas borradas **se guardan** (no hay limpieza con el tiempo).
/// - Con el lugar dado de baja (o sin sesión) se ven, pero no hay «Restaurar».
class NotasBorradasDelLugarPage extends ConsumerStatefulWidget {
  const NotasBorradasDelLugarPage({
    super.key,
    required this.ubicacionId,
    required this.colportorId,
    required this.puedeRestaurar,
  });

  final String ubicacionId;

  /// UUID del usuario con la sesión iniciada (para la preferencia del aviso de privacidad).
  final String? colportorId;

  /// `false`: el lugar está dado de baja (o no hay sesión): se ven, no se restauran.
  final bool puedeRestaurar;

  static Future<void> abrir(
    BuildContext context, {
    required String ubicacionId,
    required String? colportorId,
    required bool puedeRestaurar,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => NotasBorradasDelLugarPage(
        ubicacionId: ubicacionId,
        colportorId: colportorId,
        puedeRestaurar: puedeRestaurar,
      ),
    ),
  );

  @override
  ConsumerState<NotasBorradasDelLugarPage> createState() => _NotasBorradasDelLugarPageState();
}

class _NotasBorradasDelLugarPageState extends ConsumerState<NotasBorradasDelLugarPage> {
  /// Las notas con una restauración en vuelo.
  final _restaurando = <String>{};

  Future<void> _restaurar(NotaUbicacion nota) async {
    if (frenaPorCuentaRestringida(context, ref)) return;
    await _correr(
      nota.id,
      restaurar: ref.read(restaurarNotaUbicacionUseCaseProvider).call,
      mensajero: ScaffoldMessenger.of(context),
      mediaQuery: MediaQuery.of(context),
    );
  }

  Future<void> _correr(
    String id, {
    required Future<Either<Failure, NotaUbicacion>> Function(String) restaurar,
    required ScaffoldMessengerState mensajero,
    required MediaQueryData mediaQuery,
  }) async {
    if (!_restaurando.add(id)) return;
    var salioBien = false;
    try {
      salioBien = (await restaurar(id)).isRight();
    } on Object {
      // Nada de la excepción al aviso: puede traer lo escrito (convenciones §7.5).
      salioBien = false;
    } finally {
      _restaurando.remove(id);
    }
    mostrarAvisoDeNota(
      mensajero,
      mediaQuery: mediaQuery,
      texto: salioBien ? TextosNotas.restaurada : TextosNotas.noPudimosRestaurar,
      etiquetaAccion: salioBien ? null : TextosNotas.reintentar,
      alAccion: salioBien
          ? null
          : () => _correr(id, restaurar: restaurar, mensajero: mensajero, mediaQuery: mediaQuery),
    );
  }

  void _reintentar() => ref.invalidate(notasDeUbicacionProvider(widget.ubicacionId));

  @override
  Widget build(BuildContext context) {
    final notas = ref.watch(notasDeUbicacionProvider(widget.ubicacionId));
    final ahora = ref.watch(relojPersonaProvider)();

    final encabezado = EncabezadoNotas(
      titulo: TextosNotas.tituloDelLugar,
      colportorId: widget.colportorId,
    );
    final Widget cuerpo;
    if (notas.hasError) {
      cuerpo = ListView(
        children: [
          encabezado,
          Padding(
            padding: const EdgeInsets.all(20),
            child: AvisoAlta(
              color: ColoresAlta.rojo,
              glyph: '!',
              texto: TextosNotas.noPudimosLeerDelLugar,
              acciones: Align(
                alignment: Alignment.centerLeft,
                child: EnlaceAlta(texto: TextosNotas.reintentar, alPresionar: _reintentar),
              ),
            ),
          ),
        ],
      );
    } else if (!notas.hasValue) {
      cuerpo = ListView(children: [encabezado, const CargandoNotas()]);
    } else {
      final borradas = [
        for (final n in notas.requireValue)
          if (n.estaBorrada) n,
      ];
      cuerpo = ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          encabezado,
          if (borradas.isEmpty)
            const VacioNotas(titulo: TextosNotas.sinBorradas, ayuda: TextosNotas.sinBorradasAyuda)
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Semantics(
                header: true,
                child: const Text(
                  TextosNotas.borradasRotulo,
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: ColoresAlta.gris,
                  ),
                ),
              ),
            ),
            for (final nota in borradas)
              TarjetaNota.borrada(
                key: ValueKey('borrada_${nota.id}'),
                nota: nota,
                ahora: ahora,
                conLapiz: true,
                alRestaurar: widget.puedeRestaurar ? () => _restaurar(nota) : null,
              ),
          ],
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: CabeceraNotas(
                icono: Icons.chevron_left,
                tooltip: TextosNotas.volver,
                alTocar: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(child: cuerpo),
          ],
        ),
      ),
    );
  }
}
