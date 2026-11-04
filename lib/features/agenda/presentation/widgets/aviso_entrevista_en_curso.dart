import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../jornada/presentation/formato_jornada.dart';
import '../../../mapa/presentation/widgets/piezas_alta.dart';
import '../providers/entrevista_providers.dart';
import '../providers/rotulo_entrevista_providers.dart';
import 'flujo_entrevista.dart';
import 'textos_entrevista.dart';

/// El aviso fijo arriba del mapa mientras hay una entrevista en curso (decisión de Cristian, 23/10,
/// #450, «Entrevista fuera»): «Entrevista en curso · Grecia 3307 · 12 min». Un toque lleva de
/// vuelta a la hoja R·05. Sin entrevista en curso no dibuja nada.
///
/// El canvas no dibuja este aviso: usa el cuadro de aviso de las vistas 03 y 04 (borde de color e
/// insignia) en verde, el color de «Entrevista dada». Texto y forma son propuesta (pendiente de #450,
/// «mapa §2: texto/aviso»).
class AvisoEntrevistaEnCurso extends ConsumerStatefulWidget {
  const AvisoEntrevistaEnCurso({super.key, required this.colportorId, this.alAbrir});

  final String colportorId;

  /// Cómo se vuelve a la entrevista. Por defecto abre [FlujoEntrevista.abrir]; un test lo
  /// reemplaza.
  final Future<void> Function()? alAbrir;

  @override
  ConsumerState<AvisoEntrevistaEnCurso> createState() => _AvisoEntrevistaEnCursoState();
}

class _AvisoEntrevistaEnCursoState extends ConsumerState<AvisoEntrevistaEnCurso> {
  Timer? _timer;

  /// Un solo toque a la vez: mientras la hoja está abierta, otro toque no abre otra encima.
  bool _abriendo = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _abrir() async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      final alAbrir = widget.alAbrir;
      if (alAbrir != null) {
        await alAbrir();
      } else {
        await FlujoEntrevista.abrir(context, ref, colportorId: widget.colportorId);
      }
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entrevista = ref.watch(entrevistaEnCursoProvider(widget.colportorId)).entrevista;
    if (entrevista == null) return const SizedBox.shrink();
    final direccion =
        ref.watch(rotuloDeEntrevistaProvider(entrevista)).asData?.value.direccion ?? '';
    final transcurrido = ref.read(relojEntrevistaProvider)().difference(entrevista.inicio);
    final texto = TextosEntrevista.avisoEnCurso(direccion, duracionCorta(transcurrido));
    final theme = Theme.of(context);
    return Semantics(
      key: ClavesEntrevista.avisoFijo,
      container: true,
      button: true,
      excludeSemantics: true,
      label: '$texto. ${TextosEntrevista.volverALaEntrevista}',
      onTap: _abrir,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ColoresAlta.verde, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _abrir,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  const InsigniaCirculo(color: ColoresAlta.verde, glyph: '◷'),
                  const SizedBox(width: 10),
                  Expanded(child: Text(texto, style: theme.textTheme.bodyMedium)),
                  const SizedBox(width: 8),
                  Text('›', style: theme.textTheme.titleLarge?.copyWith(color: ColoresAlta.gris)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
