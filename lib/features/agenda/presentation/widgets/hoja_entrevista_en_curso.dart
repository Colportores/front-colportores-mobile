import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../jornada/presentation/formato_jornada.dart';
import 'textos_entrevista.dart';

/// Abre la hoja R·05 «Entrevista en curso» sobre el mapa (sin velo, como el canvas) y devuelve
/// `true` si la colportora tocó «Finalizar entrevista», o `null` si la cerró.
Future<bool?> mostrarHojaEntrevistaEnCurso(
  BuildContext context, {
  required String direccion,
  required String persona,
  required DateTime inicio,
  required String notaInicial,
  required ValueChanged<String> alEscribirNota,
  DateTime Function()? reloj,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  barrierColor: Colors.transparent,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaEntrevistaEnCurso(
    direccion: direccion,
    persona: persona,
    inicio: inicio,
    notaInicial: notaInicial,
    alEscribirNota: alEscribirNota,
    alFinalizar: () => Navigator.of(context).pop(true),
    reloj: reloj,
  ),
);

/// R·05 · «Entrevista en curso» (vista 39): el lugar y la persona, cuánto va y desde cuándo,
/// «✎ Nota de la visita» y «Finalizar entrevista».
///
/// El inicio es el toque de «Empezar»; la detección por GPS (quieta más de 2 min) es V2/V3 (§8.5.3).
/// El tiempo se actualiza solo cada medio minuto. La nota se escribe acá mismo y queda guardada en
/// la entrevista mientras dure; el contenido entero se desplaza, así que a 200 % de letra nada
/// queda fuera de alcance.
class HojaEntrevistaEnCurso extends StatefulWidget {
  const HojaEntrevistaEnCurso({
    super.key,
    required this.direccion,
    required this.persona,
    required this.inicio,
    required this.notaInicial,
    required this.alEscribirNota,
    required this.alFinalizar,
    this.reloj,
  });

  final String direccion;
  final String persona;
  final DateTime inicio;
  final String notaInicial;
  final ValueChanged<String> alEscribirNota;
  final VoidCallback alFinalizar;

  /// El reloj de la pantalla; un test lo reemplaza.
  final DateTime Function()? reloj;

  @override
  State<HojaEntrevistaEnCurso> createState() => _HojaEntrevistaEnCursoState();
}

class _HojaEntrevistaEnCursoState extends State<HojaEntrevistaEnCurso> {
  Timer? _timer;
  late DateTime _ahora = _reloj();
  late final TextEditingController _nota = TextEditingController(text: widget.notaInicial);
  late bool _escribiendoNota = widget.notaInicial.trim().isNotEmpty;

  /// Un solo toque en «Finalizar entrevista»: el segundo, antes de que cierre la hoja, no hace nada.
  bool _finalizando = false;

  DateTime _reloj() => (widget.reloj ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _ahora = _reloj());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nota.dispose();
    super.dispose();
  }

  void _finalizar() {
    if (_finalizando) return;
    _finalizando = true;
    widget.alFinalizar();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final transcurrido = _ahora.difference(widget.inicio);
    final lugar = TextosEntrevista.lugarYPersona(widget.direccion, widget.persona);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: ClavesEntrevista.hojaEnCurso,
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Asa(),
            const SizedBox(height: 14),
            Semantics(
              header: true,
              child: Text(TextosEntrevista.enCursoTitulo, style: theme.textTheme.headlineMedium),
            ),
            if (lugar.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(lugar, style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris)),
            ],
            const SizedBox(height: 18),
            // El tiempo se anuncia como una sola frase: «En curso, 12 min, desde las 14:23».
            Semantics(
              container: true,
              label:
                  '${TextosEntrevista.enCurso.toLowerCase()}, ${duracionCorta(transcurrido)}, '
                  '${TextosEntrevista.desdeLas(horaCorta(widget.inicio)).toLowerCase()}',
              excludeSemantics: true,
              child: Padding(
                key: ClavesEntrevista.tiempo,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TextosEntrevista.enCurso,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colores.gris,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      duracionCorta(transcurrido),
                      style: theme.textTheme.headlineMedium?.copyWith(fontSize: 36),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      TextosEntrevista.desdeLas(horaCorta(widget.inicio)),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              key: ClavesEntrevista.botonNota,
              onPressed: () => setState(() => _escribiendoNota = !_escribiendoNota),
              child: const Text(TextosEntrevista.notaDeLaVisita),
            ),
            if (_escribiendoNota) ...[
              const SizedBox(height: 12),
              TextField(
                key: ClavesEntrevista.campoNota,
                controller: _nota,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: TextosEntrevista.campoNota),
                onChanged: widget.alEscribirNota,
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              key: ClavesEntrevista.finalizar,
              onPressed: _finalizar,
              child: const Text(TextosEntrevista.finalizar),
            ),
          ],
        ),
      ),
    );
  }
}

class _Asa extends StatelessWidget {
  const _Asa();

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).extension<ColoresColportaje>()!;
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colores.bordeInput,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
