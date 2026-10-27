import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/nota_persona.dart';
import '../providers/notas_persona_providers.dart';
import '../providers/personas_providers.dart';
import '../textos_notas.dart';
import '../widgets/piezas_alta.dart';
import '../widgets/piezas_notas.dart';

/// Las notas borradas de una persona (HU-UBI-012, vista 32E, artboard E·05): se ven atenuadas y cada
/// una tiene «Restaurar». Se llega desde «Ver borradas (n)» de las notas.
///
/// - Restaurar devuelve la nota a la lista con su fecha y su texto; el aviso «Nota restaurada.» lo
///   confirma. Si falla, el aviso dice qué pasó y ofrece «Reintentar».
/// - Cada nota tiene su propia guarda: un doble toque sobre «Restaurar» no lo repite.
/// - Las notas borradas **se guardan** (no hay limpieza con el tiempo): la PREGUNTA del canvas —si se
///   limpian después de un tiempo— espera la decisión de Cristian.
/// - En solo lectura (la persona o su espacio dados de baja) se ven, pero no hay «Restaurar».
class NotasBorradasPage extends ConsumerStatefulWidget {
  const NotasBorradasPage({super.key, required this.personaId, required this.colportorId});

  final String personaId;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  static Future<void> abrir(
    BuildContext context, {
    required String personaId,
    required String colportorId,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => NotasBorradasPage(personaId: personaId, colportorId: colportorId),
    ),
  );

  @override
  ConsumerState<NotasBorradasPage> createState() => _NotasBorradasPageState();
}

class _NotasBorradasPageState extends ConsumerState<NotasBorradasPage> {
  /// Las notas con una restauración en vuelo.
  final _restaurando = <String>{};

  Future<void> _restaurar(NotaPersona nota) async {
    if (frenaPorCuentaRestringida(context, ref)) return;
    await _correr(
      nota.id,
      restaurar: ref.read(restaurarNotaPersonaUseCaseProvider).call,
      mensajero: ScaffoldMessenger.of(context),
      mediaQuery: MediaQuery.of(context),
    );
  }

  Future<void> _correr(
    String id, {
    required Future<Either<Failure, NotaPersona>> Function(String) restaurar,
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

  void _reintentar() {
    ref
      ..invalidate(contextoNotasPersonaProvider(widget.personaId))
      ..invalidate(notasDePersonaProvider(widget.personaId));
  }

  @override
  Widget build(BuildContext context) {
    final contexto = ref.watch(contextoNotasPersonaProvider(widget.personaId));
    final notas = ref.watch(notasDePersonaProvider(widget.personaId));
    final datos = contexto.asData?.value;
    final soloLectura = datos?.soloLectura ?? false;
    final ahora = ref.watch(relojPersonaProvider)();

    final encabezado = EncabezadoNotas(
      titulo: datos == null ? TextosNotas.tituloGenerico : TextosNotas.titulo(datos.nombre),
      colportorId: widget.colportorId,
    );
    final Widget cuerpo;
    if (contexto.hasError || notas.hasError) {
      cuerpo = ListView(
        children: [
          encabezado,
          Padding(
            padding: const EdgeInsets.all(20),
            child: AvisoAlta(
              color: ColoresAlta.rojo,
              glyph: '!',
              texto: TextosNotas.noPudimosLeer(datos?.nombre),
              acciones: Align(
                alignment: Alignment.centerLeft,
                child: EnlaceAlta(texto: TextosNotas.reintentar, alPresionar: _reintentar),
              ),
            ),
          ),
        ],
      );
    } else if (!contexto.hasValue || !notas.hasValue) {
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
                alRestaurar: soloLectura ? null : () => _restaurar(nota),
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
