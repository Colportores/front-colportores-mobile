import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../providers/alta_ubicacion_notifier.dart';
import '../providers/alta_ubicacion_providers.dart';
import 'hoja_alta.dart';
import 'piezas_alta.dart';

/// Abre la lista de las ciudades de la campaña del colportor (vista 03 «Cambiar»). Devuelve la
/// ciudad elegida o `null` si se cerró.
///
/// Esta hoja **no tiene diseño** en el canvas (la vista 03 solo dibuja el campo «Montevideo
/// detectada · Cambiar»): es una lista simple (cargando, vacía, error con «Reintentar»), con la misma
/// forma que las pantallas vecinas.
Future<CiudadCatalogo?> mostrarHojaCiudad(
  BuildContext context, {
  required ParametrosAlta parametros,
}) => showModalBottomSheet<CiudadCatalogo>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaCiudad(parametros: parametros),
);

class HojaCiudad extends ConsumerStatefulWidget {
  const HojaCiudad({super.key, required this.parametros});

  final ParametrosAlta parametros;

  @override
  ConsumerState<HojaCiudad> createState() => _HojaCiudadState();
}

class _HojaCiudadState extends ConsumerState<HojaCiudad> {
  late Future<Either<Failure, List<CiudadCatalogo>>> _ciudades;

  /// Un segundo toque mientras la hoja se cierra no tiene que cerrar también la pantalla de atrás.
  var _cerrando = false;

  @override
  void initState() {
    super.initState();
    _ciudades = _leer();
  }

  /// Las ciudades de la campaña. Si el puerto lanza en vez de devolver una falla, el `FutureBuilder`
  /// lo muestra como error con «Reintentar».
  Future<Either<Failure, List<CiudadCatalogo>>> _leer() async =>
      ref.read(ciudadesParaAltaProvider).deMiCampania(widget.parametros.colportorId);

  void _reintentar() {
    final nuevas = _leer();
    setState(() {
      _ciudades = nuevas;
    });
  }

  @override
  Widget build(BuildContext context) {
    final proveedor = altaUbicacionProvider(widget.parametros);
    final estado = ref.watch(proveedor);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text(
                'Elegí la ciudad',
                style: TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<Either<Failure, List<CiudadCatalogo>>>(
                future: _ciudades,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _Cargando();
                  }
                  final resultado = snapshot.data;
                  if (snapshot.hasError || resultado == null) {
                    return _Error(
                      texto: const FailureInesperado().mensaje,
                      alReintentar: _reintentar,
                    );
                  }
                  return resultado.fold(
                    (falla) => _Error(
                      texto: mensajePara(falla, accion: 'ver las ciudades.'),
                      alReintentar: _reintentar,
                    ),
                    (ciudades) => ciudades.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              TextosAlta.sinCiudades,
                              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final c in ciudades)
                                _OpcionCiudad(
                                  ciudad: c,
                                  elegida: estado.ciudad?.id == c.id,
                                  alElegir: () {
                                    if (_cerrando) return;
                                    _cerrando = true;
                                    ref.read(proveedor.notifier).elegirCiudad(c);
                                    Navigator.of(context).pop(c);
                                  },
                                ),
                            ],
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

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Buscando ciudades…', style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.texto, required this.alReintentar});

  final String texto;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: texto),
        EnlaceAlta(texto: TextosAlta.reintentar, alPresionar: alReintentar),
      ],
    );
  }
}

class _OpcionCiudad extends StatelessWidget {
  const _OpcionCiudad({required this.ciudad, required this.elegida, required this.alElegir});

  final CiudadCatalogo ciudad;
  final bool elegida;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: elegida,
      child: InkWell(
        onTap: alElegir,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(child: Text(ciudad.nombre, style: const TextStyle(fontSize: 15))),
              if (elegida) const Icon(Icons.check, color: ColoresAlta.verde),
            ],
          ),
        ),
      ),
    );
  }
}
