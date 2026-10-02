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

/// Abre la lista de ciudades del catálogo (vista 03 «Cambiar», HU-UBI-001 «Seleccionar ciudad
/// manualmente»). Devuelve la ciudad elegida o `null` si se cerró.
///
/// Esta hoja **no tiene diseño** en el canvas (la vista 03 solo dibuja el campo «Montevideo
/// detectada · Cambiar»): es una lista simple con los textos de la HU, a confirmar con Cristian.
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

  @override
  void initState() {
    super.initState();
    _ciudades = ref.read(ciudadesParaAltaProvider).todas();
  }

  void _reintentar() {
    final nuevas = ref.read(ciudadesParaAltaProvider).todas();
    setState(() {
      _ciudades = nuevas;
    });
  }

  @override
  Widget build(BuildContext context) {
    final proveedor = altaUbicacionProvider(widget.parametros);
    final estado = ref.watch(proveedor);
    final theme = Theme.of(context);
    final solicitud = estado.solicitud;
    final String? resultadoSolicitud = switch (solicitud) {
      SolicitudCiudadEnviada() => TextosAlta.solicitudEnviada,
      SolicitudCiudadFallida(:final falla) => mensajePara(
        falla,
        accion: 'pedir el alta de la ciudad.',
      ),
      _ => null,
    };

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
                              'No hay ciudades en el catálogo de este teléfono.',
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
            const SizedBox(height: 8),
            if (resultadoSolicitud != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    resultadoSolicitud,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
              ),
            if (solicitud is! SolicitudCiudadEnviada)
              Align(
                alignment: Alignment.centerLeft,
                child: EnlaceAlta(
                  texto: TextosAlta.solicitarCiudad,
                  alPresionar: solicitud is SolicitudCiudadEnviando || estado.punto == null
                      ? null
                      : () => ref.read(proveedor.notifier).solicitarAltaCiudad(),
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
        EnlaceAlta(texto: 'Reintentar', alPresionar: alReintentar),
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
