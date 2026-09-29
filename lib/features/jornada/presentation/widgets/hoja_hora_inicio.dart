import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../formato_jornada.dart';

/// Abre la hoja "¿A qué hora empezaste?" (vista 20, estados A02 y A03) y devuelve cuántos minutos
/// hacia atrás eligió el colportor (0 = ahora), o `null` si canceló.
///
/// [ahora] es el instante con el que se armó la pantalla que se está viendo y [margenMinutos] lo
/// que se puede retroceder (30, el mismo rango que valida `IniciarJornadaUseCase`).
Future<int?> mostrarHojaHoraInicio(
  BuildContext context, {
  required DateTime ahora,
  required int margenMinutos,
  required int minutosAtras,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) =>
      HojaHoraInicio(ahora: ahora, margenMinutos: margenMinutos, minutosAtras: minutosAtras),
);

/// La hora de inicio se ajusta de a [pasoMinutos] con −5 / +5; tocando la hora se escribe otra en
/// formato 24 h ("Otra hora"). Fuera de rango se rechaza con el rango explícito, nunca se ajusta
/// en silencio (HU-JOR-001).
class HojaHoraInicio extends StatefulWidget {
  const HojaHoraInicio({
    super.key,
    required this.ahora,
    required this.margenMinutos,
    required this.minutosAtras,
  });

  static const pasoMinutos = 5;

  final DateTime ahora;
  final int margenMinutos;
  final int minutosAtras;

  @override
  State<HojaHoraInicio> createState() => _HojaHoraInicioState();
}

class _HojaHoraInicioState extends State<HojaHoraInicio> {
  late int _minutos = widget.minutosAtras;
  bool _escribiendo = false;
  late final TextEditingController _texto;

  /// Al minuto: el selector ofrece minutos enteros (igual que el caso de uso).
  late final DateTime _base = DateTime(
    widget.ahora.year,
    widget.ahora.month,
    widget.ahora.day,
    widget.ahora.hour,
    widget.ahora.minute,
  );

  DateTime _hora(int minutosAtras) => _base.subtract(Duration(minutes: minutosAtras));

  /// "14:05 y las 14:35": el rango que se ofrece y el que se rechaza dicen lo mismo.
  String get _desdeHasta => '${horaCorta(_hora(widget.margenMinutos))} y las ${horaCorta(_base)}';

  @override
  void initState() {
    super.initState();
    _texto = TextEditingController(text: horaCorta(_hora(_minutos)));
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  void _mover(int delta) =>
      setState(() => _minutos = (_minutos + delta).clamp(0, widget.margenMinutos));

  void _abrirOtraHora() => setState(() {
    _texto.text = horaCorta(_hora(_minutos));
    _texto.selection = TextSelection(baseOffset: 0, extentOffset: _texto.text.length);
    _escribiendo = true;
  });

  /// Los minutos hacia atrás de lo escrito (`null` si no es una hora 24 h). Si la hora escrita es
  /// posterior a la actual se toma la de ayer: cruzando la medianoche (00:10 → 23:50) sigue en
  /// rango; en cualquier otro caso queda lejos y se rechaza.
  int? _minutosEscritos() {
    final coincidencia = RegExp(r'^(\d{1,2}):?(\d{2})$').firstMatch(_texto.text.trim());
    if (coincidencia == null) return null;
    final hora = int.parse(coincidencia.group(1)!);
    final minuto = int.parse(coincidencia.group(2)!);
    if (hora > 23 || minuto > 59) return null;
    var escrita = DateTime(_base.year, _base.month, _base.day, hora, minuto);
    if (escrita.isAfter(_base)) {
      escrita = DateTime(_base.year, _base.month, _base.day - 1, hora, minuto);
    }
    return _base.difference(escrita).inMinutes;
  }

  /// Qué decirle al colportor de lo escrito, o `null` si está bien (o todavía se está escribiendo).
  String? _errorEscrito() {
    final texto = _texto.text.trim();
    if (texto.isEmpty) return null;
    final minutos = _minutosEscritos();
    if (minutos == null) {
      // Mientras tipea ("1", "14") todavía no es un error.
      if (texto.length < 4) return null;
      return 'No entendimos esa hora. Escribila en formato 24 h, por ejemplo '
          '${horaCorta(_hora(widget.margenMinutos ~/ 2))}.';
    }
    if (minutos > widget.margenMinutos) {
      return 'La hora tiene que estar entre las $_desdeHasta.';
    }
    return null;
  }

  bool get _escritoValido {
    final minutos = _minutosEscritos();
    return minutos != null && minutos <= widget.margenMinutos;
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: teclado),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Asa(),
            const SizedBox(height: 16),
            if (_escribiendo) _otraHora(context) else _ajuste(context),
          ],
        ),
      ),
    );
  }

  Widget _ajuste(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final horaElegida = horaCorta(_hora(_minutos));

    return Column(
      key: const Key('hoja_hora_ajuste'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('¿A qué hora empezaste?', style: theme.textTheme.headlineMedium),
        ),
        const SizedBox(height: 4),
        Text(
          'Entre las $_desdeHasta.',
          style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _BotonPaso(
              key: const Key('hoja_hora_menos'),
              texto: '−${HojaHoraInicio.pasoMinutos}',
              etiqueta: '${HojaHoraInicio.pasoMinutos} minutos antes',
              onPressed: _minutos >= widget.margenMinutos
                  ? null
                  : () => _mover(HojaHoraInicio.pasoMinutos),
            ),
            Expanded(
              child: Semantics(
                button: true,
                onTapHint: 'Otra hora',
                child: InkWell(
                  key: const Key('hoja_hora_valor'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: _abrirOtraHora,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'HORA DE INICIO',
                          style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            horaElegida,
                            style: theme.textTheme.headlineMedium?.copyWith(fontSize: 40),
                          ),
                        ),
                        Text(
                          _minutos == 0 ? 'Ahora' : 'Hace $_minutos min',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _BotonPaso(
              key: const Key('hoja_hora_mas'),
              texto: '+${HojaHoraInicio.pasoMinutos}',
              etiqueta: '${HojaHoraInicio.pasoMinutos} minutos después',
              onPressed: _minutos <= 0 ? null : () => _mover(-HojaHoraInicio.pasoMinutos),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('hoja_hora_usar'),
          onPressed: () => Navigator.of(context).pop(_minutos),
          child: Text('Usar $horaElegida'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const Key('hoja_hora_cancelar'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _otraHora(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final error = _errorEscrito();

    return Column(
      key: const Key('hoja_hora_otra'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Otra hora', style: theme.textTheme.headlineMedium)),
        const SizedBox(height: 4),
        Text(
          'Escribila en formato 24 h.',
          style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('hoja_hora_campo'),
          controller: _texto,
          autofocus: true,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9:]')),
            LengthLimitingTextInputFormatter(5),
          ],
          style: theme.textTheme.headlineMedium,
          decoration: InputDecoration(
            labelText: 'HORA DE INICIO',
            errorText: error,
            errorMaxLines: 3,
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_escritoValido) Navigator.of(context).pop(_minutosEscritos());
          },
        ),
        const SizedBox(height: 18),
        FilledButton(
          key: const Key('hoja_hora_usar_escrita'),
          onPressed: _escritoValido ? () => Navigator.of(context).pop(_minutosEscritos()) : null,
          child: const Text('Usar esta hora'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const Key('hoja_hora_volver'),
          onPressed: () => setState(() => _escribiendo = false),
          child: const Text('Volver'),
        ),
      ],
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

/// El botón redondo −5 / +5 (56 dp, más que el mínimo de toque).
class _BotonPaso extends StatelessWidget {
  const _BotonPaso({super.key, required this.texto, required this.etiqueta, this.onPressed});

  final String texto;
  final String etiqueta;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: etiqueta,
    button: true,
    excludeSemantics: true,
    enabled: onPressed != null,
    onTap: onPressed,
    child: SizedBox.square(
      dimension: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(56),
        ),
        child: Text(texto),
      ),
    ),
  );
}
