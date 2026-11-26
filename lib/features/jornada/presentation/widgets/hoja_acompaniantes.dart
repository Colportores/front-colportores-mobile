import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/presentation/hoja_inferior.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/acompaniante.dart';
import '../providers/acompaniamiento_providers.dart';
import '../textos_acompaniamiento.dart';

/// «¿Quién te acompaña?» (vista 20, 20J·02, 20J·04, 20J·05 y 20J·06): la lista de coordinadores de la campaña,
/// de los que se marca a todos los que acompañaron (decisión de Cristian, 05/11, «Dos acomp.»). Devuelve
/// los ids que quedaron marcados; `null` si se canceló. Se elige igual sin conexión: la lista ya bajó con la
/// sincronización.
Future<Set<String>?> mostrarHojaAcompaniantes(
  BuildContext context, {
  required ClaveDeLaLista clave,
  required List<Acompaniante> actuales,
}) => mostrarHojaInferior<Set<String>>(
  context: context,
  isScrollControlled: true,
  builder: (_) => HojaAcompaniantes(clave: clave, actuales: actuales),
);

class HojaAcompaniantes extends ConsumerStatefulWidget {
  const HojaAcompaniantes({super.key, required this.clave, required this.actuales});

  final ClaveDeLaLista clave;

  /// Quienes ya acompañan la jornada: arrancan marcados, estén o no en la lista de hoy.
  final List<Acompaniante> actuales;

  @override
  ConsumerState<HojaAcompaniantes> createState() => _HojaAcompaniantesState();
}

class _HojaAcompaniantesState extends ConsumerState<HojaAcompaniantes> {
  late final Set<String> _marcados = {for (final a in widget.actuales) a.usuarioId};

  /// Un doble toque en «Listo» no debe sacar también la pantalla de abajo.
  bool _cerrando = false;

  void _cerrar(Set<String>? resultado) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(resultado);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final lista = ref.watch(listaDeAcompanantesProvider(widget.clave));
    final conocida = ref.watch(campaniaDeLaJornadaConocidaProvider(widget.clave)).value ?? true;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        key: const Key('hoja_acompaniantes'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Semantics(
            header: true,
            child: Text(TextosAcompaniamiento.tituloDeLaHoja, style: theme.textTheme.headlineSmall),
          ),
          ...lista.when(
            loading: () => [
              Text(
                TextosAcompaniamiento.cargandoLaLista,
                key: const Key('hoja_acompaniantes_cargando'),
                style: theme.textTheme.bodyLarge,
              ),
            ],
            error: (_, _) => [
              Semantics(
                liveRegion: true,
                child: Text(
                  TextosAcompaniamiento.noPudimosLeerLaLista,
                  key: const Key('hoja_acompaniantes_error'),
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                ),
              ),
              _botonCerrar(),
            ],
            data: (coordinadores) {
              final filas = _filas(coordinadores);
              if (filas.isEmpty) {
                return [
                  Text(
                    TextosAcompaniamiento.listaVacia,
                    key: const Key('hoja_acompaniantes_vacia'),
                    style: theme.textTheme.bodyLarge?.copyWith(color: colores.gris),
                  ),
                  _botonCerrar(),
                ];
              }
              return [
                Text(
                  TextosAcompaniamiento.ayudaDeLaHoja,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
                ),
                for (final fila in filas)
                  CheckboxListTile(
                    key: Key('acompaniante_${fila.usuarioId}'),
                    value: _marcados.contains(fila.usuarioId),
                    onChanged: (marcado) => setState(() {
                      if (marcado ?? false) {
                        _marcados.add(fila.usuarioId);
                      } else {
                        _marcados.remove(fila.usuarioId);
                      }
                    }),
                    controlAffinity: ListTileControlAffinity.trailing,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(fila.nombre),
                    subtitle: Text(
                      TextosAcompaniamiento.rolDeLaLista(campaniaConocida: conocida),
                      style: TextStyle(color: colores.gris),
                    ),
                  ),
                const SizedBox(height: 4),
                FilledButton(
                  key: const Key('hoja_acompaniantes_listo'),
                  onPressed: () => _cerrar(Set.of(_marcados)),
                  child: const Text(TextosAcompaniamiento.listo),
                ),
                OutlinedButton(
                  key: const Key('hoja_acompaniantes_cancelar'),
                  onPressed: () => _cerrar(null),
                  child: const Text(TextosAcompaniamiento.cancelar),
                ),
                if (widget.actuales.isNotEmpty)
                  TextButton(
                    key: const Key('hoja_acompaniantes_nadie'),
                    onPressed: () => _cerrar(<String>{}),
                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    child: const Text(TextosAcompaniamiento.nadieMeAcompanio),
                  ),
              ];
            },
          ),
        ],
      ),
    );
  }

  Widget _botonCerrar() => OutlinedButton(
    key: const Key('hoja_acompaniantes_cerrar'),
    onPressed: () => _cerrar(null),
    child: const Text(TextosAcompaniamiento.cerrar),
  );

  /// Los de la lista de hoy y, al final, los que ya acompañaban y la lista ya no trae (dejaron de
  /// contar): se muestran para poder sacarlos; nada se borra por su cuenta.
  List<({String usuarioId, String nombre})> _filas(List<CoordinadorDeCampania> coordinadores) {
    final enLaLista = {for (final c in coordinadores) c.usuarioId};
    return [
      for (final c in coordinadores)
        (
          usuarioId: c.usuarioId,
          nombre: c.nombreCompleto ?? TextosAcompaniamiento.personaSinNombre,
        ),
      for (final a in widget.actuales)
        if (!enLaLista.contains(a.usuarioId))
          (
            usuarioId: a.usuarioId,
            nombre: a.nombreCompleto ?? TextosAcompaniamiento.personaSinNombre,
          ),
    ];
  }
}
