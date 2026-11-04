import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../agenda/presentation/formato_agenda.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/entities/ubicacion.dart';
import '../providers/lista_ubicaciones_notifier.dart';
import '../providers/personas_providers.dart';
import '../textos_registrar_visita.dart';
import 'lista_ubicaciones_page.dart';

/// La casa que se eligió para agendar: la ubicación y su espacio (donde cuelga la cita).
typedef CasaParaAgendar = ({String ubicacionId, String espacioId});

/// Los textos del paso de elegir la casa (pestaña Agenda → «+ Agendar»).
abstract final class TextosElegirCasaParaAgendar {
  static const titulo = 'Elegí la casa de la visita';
  static const cerrar = 'Volver a la agenda';
  static const sinLugar = 'Esa casa no tiene dónde agendar. Elegí otra.';
}

/// Las claves del paso de elegir la casa.
abstract final class ClavesElegirCasaParaAgendar {
  static const pantalla = Key('elegir_casa_agendar_pantalla');
}

/// La lista de ubicaciones (vista 05) en **modo selección**, para «+ Agendar» de la pestaña Agenda:
/// no viene de ninguna casa, así que se elige acá (decisión de Cristian, 04/11, #568). Tocar una fila
/// cierra la pantalla con la casa y su espacio; «Agendar visita» (23A·01) se abre ya con ella.
///
/// - Una casa dada de baja no se elige (no admite visitas): la lista ya no deja tocarla como casa, su
///   fila lleva a «Reactivar» (vista 09·03).
/// - Un edificio no se elige todavía (el depto se elige antes, #452): avisa lo mismo que «+ Agendar» de
///   la hoja de la casa.
/// - Un segundo toque mientras se resuelve el primero no hace nada.
class ElegirCasaParaAgendarPage extends StatelessWidget {
  const ElegirCasaParaAgendarPage({super.key, required this.colportorId});

  final String colportorId;

  /// Abre el paso encima de la pantalla actual. Devuelve la casa elegida, o `null` si se volvió atrás.
  static Future<CasaParaAgendar?> abrir(BuildContext context, {required String colportorId}) =>
      Navigator.of(context).push<CasaParaAgendar>(
        MaterialPageRoute(builder: (_) => ElegirCasaParaAgendarPage(colportorId: colportorId)),
      );

  @override
  Widget build(BuildContext context) => _SelectorDeCasa(colportorId: colportorId);
}

class _SelectorDeCasa extends ConsumerStatefulWidget {
  const _SelectorDeCasa({required this.colportorId});

  final String colportorId;

  @override
  ConsumerState<_SelectorDeCasa> createState() => _SelectorDeCasaState();
}

class _SelectorDeCasaState extends ConsumerState<_SelectorDeCasa> {
  var _resolviendo = false;

  ItemListaUbicacion? _itemDe(String ubicacionId) {
    final items =
        ref
            .read(
              listaUbicacionesProvider(
                ListaUbicacionesNotifier.claveDeSeleccion(widget.colportorId),
              ),
            )
            .lista
            ?.items ??
        const <ItemListaUbicacion>[];
    for (final item in items) {
      if (item.ubicacion.id == ubicacionId) return item;
    }
    return null;
  }

  void _avisar(String texto) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _elegir(String ubicacionId, double? _) async {
    if (_resolviendo) return;
    _resolviendo = true;
    var seVa = false;
    try {
      final item = _itemDe(ubicacionId);
      if (item == null) {
        _avisar(TextosAgenda.noPudimosAbrir);
        return;
      }
      if (item.ubicacion.tipo == TipoUbicacion.edificio) {
        _avisar(TextosRegistrarVisita.edificioSinDeptoParaAgendar);
        return;
      }
      final lectura = await ref.read(espacioRepositoryProvider).listar(ubicacionId);
      if (!mounted) return;
      final espacios = lectura.fold((_) => null, (todos) => todos);
      if (espacios == null) {
        _avisar(TextosAgenda.noPudimosAbrir);
        return;
      }
      if (espacios.isEmpty) {
        _avisar(TextosElegirCasaParaAgendar.sinLugar);
        return;
      }
      seVa = true;
      Navigator.of(
        context,
      ).pop<CasaParaAgendar>((ubicacionId: ubicacionId, espacioId: espacios.first.id));
    } on Object {
      if (mounted) _avisar(TextosAgenda.noPudimosAbrir);
    } finally {
      // Si la pantalla se va, el guardia queda puesto: ningún toque más la cierra dos veces.
      if (!seVa) _resolviendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: ClavesElegirCasaParaAgendar.pantalla,
      appBar: AppBar(
        title: const Text(TextosElegirCasaParaAgendar.titulo),
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: ListaUbicacionesPage(
          colportorId: widget.colportorId,
          paraElegir: true,
          alAbrirUbicacion: _elegir,
        ),
      ),
    );
  }
}
