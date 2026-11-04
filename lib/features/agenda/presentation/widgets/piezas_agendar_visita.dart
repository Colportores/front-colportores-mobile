import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../mapa/presentation/widgets/campos_ubicacion.dart';
import '../../../mapa/presentation/widgets/piezas_alta.dart';
import '../../domain/entities/franja_horaria.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../formato_agendar_visita.dart';
import '../textos_agendar_visita.dart';

/// Claves de los controles de «Agendar una visita» (para los tests).
abstract final class ClavesAgendarVisita {
  static const campoDiaYHora = Key('agendar_campo_dia_y_hora');
  static const errorHora = Key('agendar_error_hora');
  static const avisoSinPermiso = Key('agendar_aviso_sin_permiso');
  static const accionNotificaciones = Key('agendar_activar_notificaciones');
  static const avisoFalla = Key('agendar_aviso_falla');
  static const textoRecordatorio = Key('agendar_texto_recordatorio');
  static const tarjetaPersona = Key('agendar_tarjeta_persona');
  static const botonAgendar = Key('agendar_boton');
  static const cerrar = Key('agendar_cerrar');
  static const horaPasadaAgendarIgual = Key('agendar_hora_pasada_igual');
  static const horaPasadaCambiar = Key('agendar_hora_pasada_cambiar');
  static const hojaListo = Key('agendar_hoja_listo');
  static const hojaMas = Key('agendar_hoja_mas');
  static const hojaMenos = Key('agendar_hoja_menos');
  static const hojaHora = Key('agendar_hoja_hora');
  static const hojaFranja = Key('agendar_hoja_franja');

  static Key franja(FranjaHoraria f) => Key('agendar_franja_${f.codigo}');
  static Key dia(int desdeHoy) => Key('agendar_dia_$desdeHoy');
  static const otroDia = Key('agendar_otro_dia');
  static const diaElegido = Key('agendar_dia_elegido');

  // Vista 39, R·02 y R·03.
  static const tarjetaFecha = Key('agendar_tarjeta_fecha');
  static const interruptorEstricta = Key('agendar_estricta');
  static const campoHoraAcordada = Key('agendar_campo_hora_acordada');
  static const errorHoraAcordada = Key('agendar_error_hora_acordada');
}

/// El renglón de con quién y dónde es la visita (23A·01): las iniciales, el nombre y la dirección.
/// Mientras se lee, [cargando] dibuja el esqueleto.
class TarjetaPersonaAgendar extends StatelessWidget {
  const TarjetaPersonaAgendar({
    super.key,
    required this.iniciales,
    required this.titulo,
    required this.subtitulo,
    this.cargando = false,
  });

  final String iniciales;
  final String titulo;
  final String subtitulo;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    final contenido = cargando
        ? const _EsqueletoPersona()
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    iniciales.isEmpty ? '⌂' : iniciales,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: theme.textTheme.bodySmall?.copyWith(color: gris)),
                  ],
                ),
              ),
            ],
          );
    return Semantics(
      container: true,
      label: cargando
          ? TextosAgendarVisita.cargando
          : TextosAgendarVisita.lectorPersona(titulo, subtitulo),
      excludeSemantics: true,
      child: Container(
        key: ClavesAgendarVisita.tarjetaPersona,
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ColoresAlta.grisBorde),
        ),
        child: contenido,
      ),
    );
  }
}

class _EsqueletoPersona extends StatelessWidget {
  const _EsqueletoPersona();

  @override
  Widget build(BuildContext context) {
    Widget barra(double ancho) => Container(
      width: ancho,
      height: 12,
      decoration: BoxDecoration(
        color: ColoresAlta.grisFondo,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: ColoresAlta.grisFondo, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [barra(140), barra(200)],
          ),
        ),
      ],
    );
  }
}

/// «TIPO»: Entrevista o Cobranza.
class SelectorTipoAgenda extends StatelessWidget {
  const SelectorTipoAgenda({
    super.key,
    required this.tipo,
    required this.alCambiar,
    this.bloqueado = false,
  });

  final TipoAgenda tipo;
  final ValueChanged<TipoAgenda>? alCambiar;
  final bool bloqueado;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExcludeSemantics(child: EtiquetaCampoUbicacion(TextosAgendarVisita.etiquetaTipo)),
        const SizedBox(height: 6),
        SegmentedButton<TipoAgenda>(
          showSelectedIcon: false,
          // El elegido se ve igual con el selector bloqueado (23A·04): pinta navy con texto blanco
          // (el apagado por defecto lo dejaba blanco sobre claro, a 1,05:1) y así se ve qué tipo se
          // está guardando.
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
            backgroundColor: WidgetStateProperty.resolveWith(
              (estados) => estados.contains(WidgetState.selected)
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (estados) => estados.contains(WidgetState.selected)
                  ? Theme.of(context).colorScheme.onPrimary
                  : ColoresAlta.tinta,
            ),
          ),
          segments: const [
            ButtonSegment(
              value: TipoAgenda.entrevista,
              label: Text(TextosAgendarVisita.entrevista),
            ),
            ButtonSegment(value: TipoAgenda.cobranza, label: Text(TextosAgendarVisita.cobranza)),
          ],
          selected: {tipo},
          onSelectionChanged: bloqueado || alCambiar == null ? null : (s) => alCambiar!(s.first),
        ),
      ],
    );
  }
}

/// «DÍA Y HORA»: el valor elegido; al tocarlo se abre la hoja «Día y hora» (23A·02). Con [error] (23A·03)
/// el borde y el texto se ponen rojos y el aviso va debajo.
class CampoDiaYHora extends StatelessWidget {
  const CampoDiaYHora({
    super.key,
    required this.valor,
    required this.alTocar,
    this.error,
    this.etiqueta = TextosAgendarVisita.etiquetaDiaYHora,
    this.lector = TextosAgendarVisita.lectorDiaYHora,
    this.claveCampo = ClavesAgendarVisita.campoDiaYHora,
    this.claveError = ClavesAgendarVisita.errorHora,
  });

  final String valor;
  final VoidCallback? alTocar;
  final String? error;

  /// El rótulo del campo: «DÍA Y HORA», o «HORA ACORDADA» con la entrevista estricta (R·03).
  final String etiqueta;

  /// Cómo lo lee el lector de pantalla, dado [valor].
  final String Function(String valor) lector;
  final Key claveCampo;
  final Key claveError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conError = error != null;
    final color = conError ? ColoresAlta.rojo : ColoresAlta.grisBorde;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(child: EtiquetaCampoUbicacion(etiqueta)),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: lector(valor),
          excludeSemantics: true,
          onTap: alTocar,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: color, width: 1.5),
            ),
            child: InkWell(
              key: claveCampo,
              onTap: alTocar,
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          valor,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: conError ? ColoresAlta.rojo : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('›', style: TextStyle(fontSize: 22, color: ColoresAlta.gris)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (conError) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              key: claveError,
              style: theme.textTheme.bodySmall?.copyWith(color: ColoresAlta.rojo),
            ),
          ),
        ],
      ],
    );
  }
}

/// La tarjeta de la fecha de la vista 39: «SUGERIDA» (R·02) con las entrevistas cercanas que la
/// explican, o «FECHA» (R·03) con la entrevista estricta, donde la hora va aparte. Al tocarla se abre la
/// hoja «Día y hora»; «Cambiar» es parte de la tarjeta, no un segundo destino.
class TarjetaFechaAgendar extends StatelessWidget {
  const TarjetaFechaAgendar({
    super.key,
    required this.etiqueta,
    required this.titulo,
    this.detalle,
    required this.alTocar,
  });

  /// «SUGERIDA» o «FECHA».
  final String etiqueta;

  /// «Jueves 24/10 · 10:00 a 11:30» o «Jueves 24/10».
  final String titulo;

  /// «2 entrevistas a menos de 300 m ese día»; `null` en R·03.
  final String? detalle;

  /// `null`: bloqueada (se está guardando).
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    return Semantics(
      button: true,
      label: TextosAgendarVisita.lectorTarjetaFecha(etiqueta, titulo, detalle),
      excludeSemantics: true,
      onTap: alTocar,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ColoresAlta.grisBorde),
        ),
        child: InkWell(
          key: ClavesAgendarVisita.tarjetaFecha,
          onTap: alTocar,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0B43C),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '◷',
                      style: TextStyle(color: Color(0xFF0E1A2B), fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          etiqueta,
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 10,
                            letterSpacing: 1.6,
                            color: ColoresAlta.gris,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(titulo, style: theme.textTheme.titleMedium),
                        if (detalle != null) ...[
                          const SizedBox(height: 2),
                          Text(detalle!, style: theme.textTheme.bodySmall?.copyWith(color: gris)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    TextosAgendarVisita.cambiar,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: alTocar == null ? gris : ColoresAlta.azul,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El interruptor «Entrevista estricta» (R·02 y R·03): hora fija acordada con la persona. Prendido, la
/// hora exacta reemplaza a la franja.
class InterruptorEstricta extends StatelessWidget {
  const InterruptorEstricta({super.key, required this.valor, required this.alCambiar});

  final bool valor;

  /// `null`: bloqueado (se está guardando).
  final ValueChanged<bool>? alCambiar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: ColoresAlta.grisBorde),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        key: ClavesAgendarVisita.interruptorEstricta,
        value: valor,
        onChanged: alCambiar,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: const Text(TextosAgendarVisita.estricta),
        subtitle: const Text(TextosAgendarVisita.estrictaAyuda),
      ),
    );
  }
}

/// «FRANJA SUGERIDA»: las seis franjas de §8.5.2. La recomendada viene elegida; tocar otra la cambia y
/// tocar la elegida la saca (sin franja).
class ChipsFranja extends StatelessWidget {
  const ChipsFranja({
    super.key,
    required this.elegida,
    required this.alElegir,
    this.bloqueado = false,
  });

  final FranjaHoraria? elegida;
  final ValueChanged<FranjaHoraria>? alElegir;
  final bool bloqueado;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExcludeSemantics(child: EtiquetaCampoUbicacion(TextosAgendarVisita.etiquetaFranja)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in FranjaHoraria.values)
              Semantics(
                selected: f == elegida,
                button: true,
                label: TextosAgendarVisita.lectorFranja(f.etiqueta, f.rango, elegida: f == elegida),
                excludeSemantics: true,
                // Con `excludeSemantics` se descarta la acción del chip: se declara acá.
                onTap: bloqueado || alElegir == null ? null : () => alElegir!(f),
                child: ChoiceChip(
                  key: ClavesAgendarVisita.franja(f),
                  label: Text(f.etiqueta),
                  selected: f == elegida,
                  showCheckmark: false,
                  selectedColor: esquema.primary,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: f == elegida ? esquema.primary : ColoresAlta.grisBorde),
                  labelStyle: TextStyle(
                    color: f == elegida ? esquema.onPrimary : ColoresAlta.tinta,
                    fontWeight: FontWeight.w500,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: bloqueado || alElegir == null ? null : (_) => alElegir!(f),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

const _formaHoja = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

/// La hoja «Día y hora» (23A·02): los próximos días, «Otro día…» y la hora de a 5 minutos. Devuelve el
/// instante elegido al tocar «Listo», o `null` si se la cerró sin confirmar (no cambia nada). Con
/// [conHora] en `false` (entrevista estricta, R·03) solo se elige el día y la hora de [inicial] queda
/// como está: la hora se escribe en «Hora acordada».
Future<DateTime?> mostrarHojaDiaYHora(
  BuildContext context, {
  required DateTime inicial,
  required DateTime ahora,
  bool conHora = true,
}) => showModalBottomSheet<DateTime>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: _formaHoja,
  builder: (_) => HojaDiaYHora(inicial: inicial, ahora: ahora, conHora: conHora),
);

/// Cuántos minutos suben o bajan los botones − y + de la hora.
const pasoDeLaHora = 5;

/// Cuántos días se ofrecen como atajo (hoy, mañana y los que siguen).
const diasDeAtajo = 5;

class HojaDiaYHora extends StatefulWidget {
  const HojaDiaYHora({super.key, required this.inicial, required this.ahora, this.conHora = true});

  final DateTime inicial;
  final DateTime ahora;

  /// Si la hoja pide también la hora; `false`: solo el día.
  final bool conHora;

  @override
  State<HojaDiaYHora> createState() => _HojaDiaYHoraState();
}

class _HojaDiaYHoraState extends State<HojaDiaYHora> {
  late DateTime _dia = FormatoAgendarVisita.soloDia(widget.inicial);
  late int _minutos = widget.inicial.hour * 60 + widget.inicial.minute;

  DateTime get _hoy => FormatoAgendarVisita.soloDia(widget.ahora);

  DateTime _masDias(int n) => DateTime(_hoy.year, _hoy.month, _hoy.day + n);

  /// Sube o baja la hora y, al pasar la medianoche, el día con ella: de 23:55 a 00:00 es el día que
  /// sigue, no el mismo (la cita quedaría 24 h antes de lo que pidió). Hacia atrás vale lo mismo,
  /// salvo antes de las 00:00 de hoy, donde la hora se queda: no se agenda en el pasado.
  void _moverHora(int delta) {
    const dia = 24 * 60;
    final total = _minutos + delta;
    final saltoDeDia = total >= dia ? 1 : (total < 0 ? -1 : 0);
    final nuevoDia = DateTime(_dia.year, _dia.month, _dia.day + saltoDeDia);
    if (nuevoDia.isBefore(_hoy)) return;
    setState(() {
      _dia = nuevoDia;
      _minutos = ((total % dia) + dia) % dia;
    });
  }

  Future<void> _elegirOtroDia() async {
    final elegido = await showDatePicker(
      context: context,
      initialDate: _dia.isBefore(_hoy) ? _hoy : _dia,
      firstDate: _hoy,
      lastDate: _masDias(366),
    );
    if (elegido != null && mounted) setState(() => _dia = FormatoAgendarVisita.soloDia(elegido));
  }

  Future<void> _escribirLaHora() async {
    final elegida = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _minutos ~/ 60, minute: _minutos % 60),
    );
    if (elegida != null && mounted) setState(() => _minutos = elegida.hour * 60 + elegida.minute);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gris = theme.extension<ColoresColportaje>()?.gris ?? ColoresAlta.gris;
    final esquema = theme.colorScheme;
    final atajos = [for (var i = 0; i < diasDeAtajo; i++) _masDias(i)];
    final fueraDeAtajo = !atajos.any((d) => FormatoAgendarVisita.mismoDia(d, _dia));
    final franja = FranjaHoraria.sugeridaPara(_minutos);

    Widget chipDia(String texto, DateTime dia, Key clave) {
      final elegido = FormatoAgendarVisita.mismoDia(dia, _dia);
      return Semantics(
        selected: elegido,
        button: true,
        excludeSemantics: true,
        label: texto,
        // Con `excludeSemantics` se descarta la acción del chip: se declara acá.
        onTap: () => setState(() => _dia = dia),
        child: ChoiceChip(
          key: clave,
          label: Text(texto),
          selected: elegido,
          showCheckmark: false,
          selectedColor: esquema.primary,
          backgroundColor: Colors.white,
          side: BorderSide(color: elegido ? esquema.primary : ColoresAlta.grisBorde),
          labelStyle: TextStyle(color: elegido ? esquema.onPrimary : ColoresAlta.tinta),
          materialTapTargetSize: MaterialTapTargetSize.padded,
          onSelected: (_) => setState(() => _dia = dia),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                widget.conHora ? TextosAgendarVisita.hojaTitulo : TextosAgendarVisita.hojaTituloDia,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 16),
            const ExcludeSemantics(child: EtiquetaCampoUbicacion(TextosAgendarVisita.etiquetaDia)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < atajos.length; i++)
                  chipDia(
                    switch (i) {
                      0 => TextosAgendarVisita.hoy,
                      1 => TextosAgendarVisita.manana,
                      _ => FormatoAgendarVisita.diaCorto(atajos[i]),
                    },
                    atajos[i],
                    ClavesAgendarVisita.dia(i),
                  ),
                if (fueraDeAtajo)
                  chipDia(
                    '${FormatoAgendarVisita.diaCorto(_dia)}/${_dia.month}',
                    _dia,
                    ClavesAgendarVisita.diaElegido,
                  ),
                ActionChip(
                  key: ClavesAgendarVisita.otroDia,
                  label: const Text(TextosAgendarVisita.otroDia),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: ColoresAlta.grisBorde),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onPressed: _elegirOtroDia,
                ),
              ],
            ),
            if (widget.conHora) ...[
              const SizedBox(height: 20),
              const ExcludeSemantics(
                child: EtiquetaCampoUbicacion(TextosAgendarVisita.etiquetaHora),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.outlined(
                    key: ClavesAgendarVisita.hojaMenos,
                    tooltip: TextosAgendarVisita.menosHora,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => _moverHora(-pasoDeLaHora),
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: InkWell(
                      key: ClavesAgendarVisita.hojaHora,
                      onTap: _escribirLaHora,
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 96, minHeight: 48),
                        child: Center(
                          child: Text(
                            FormatoAgendarVisita.minutosComoHora(_minutos),
                            semanticsLabel:
                                'Hora ${FormatoAgendarVisita.minutosComoHora(_minutos)}. Tocá para escribirla',
                            style: const TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    key: ClavesAgendarVisita.hojaMas,
                    tooltip: TextosAgendarVisita.masHora,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => _moverHora(pasoDeLaHora),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (franja != null) ...[
                const SizedBox(height: 12),
                Text(
                  TextosAgendarVisita.franjaSugerida(franja.etiqueta),
                  key: ClavesAgendarVisita.hojaFranja,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: gris),
                ),
              ],
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: ClavesAgendarVisita.hojaListo,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: () => Navigator.of(
                context,
              ).pop(DateTime(_dia.year, _dia.month, _dia.day, _minutos ~/ 60, _minutos % 60)),
              child: const Text(TextosAgendarVisita.listo),
            ),
          ],
        ),
      ),
    );
  }
}

/// La hoja «Esa hora ya pasó» (23A·03). Devuelve `true` con «Agendar igual» (o [confirmar]), `false`
/// con «Cambiar la hora» y `null` si se la cerró sin elegir (no se guarda nada).
Future<bool?> mostrarHojaHoraPasada(
  BuildContext context, {
  required String texto,
  String confirmar = TextosAgendarVisita.agendarIgual,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: _formaHoja,
  builder: (contexto) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              TextosAgendarVisita.horaPasadaCorta,
              style: Theme.of(contexto).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 10),
          Text(texto, style: Theme.of(contexto).textTheme.bodyLarge),
          const SizedBox(height: 20),
          FilledButton(
            key: ClavesAgendarVisita.horaPasadaAgendarIgual,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: Text(confirmar),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            key: ClavesAgendarVisita.horaPasadaCambiar,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text(TextosAgendarVisita.cambiarLaHora),
          ),
        ],
      ),
    ),
  ),
);
