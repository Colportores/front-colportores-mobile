import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/domain/entities/sesion.dart';
import '../../domain/entities/jornada.dart';
import '../../domain/usecases/iniciar_jornada_use_case.dart';
import '../formato_jornada.dart';
import '../providers/jornada_actual_notifier.dart';
import '../providers/jornada_providers.dart';
import '../widgets/aviso_jornada.dart';
import '../widgets/con_espera.dart';
import '../widgets/fila_hora_jornada.dart';
import '../widgets/fin_de_jornada.dart';
import '../widgets/hoja_hora_inicio.dart';

/// Texto literal del criterio de aceptación "Bloqueo - jornada ya activa" (HU-JOR-001).
const textoBloqueoJornadaActiva = 'Tenés una jornada en curso. Cerrala antes de iniciar otra.';

/// "Hoy": la jornada de trabajo del colportor (HU-JOR-001 y HU-JOR-002), según la vista 20 del
/// diseño (#229). Es el contenido de la primera pestaña de `InicioPage`, que pone la barra
/// superior y la inferior.
///
/// Sin jornada muestra la hora de inicio como fila tocable (abre la hoja donde se ajusta de a 5
/// minutos, hasta 30 hacia atrás) e "Iniciar jornada" al pie; con una en curso, cuánto lleva,
/// "Abrir el mapa" y "Finalizar jornada" (con la hora de fin ajustable hasta 30 minutos hacia
/// atrás, sin pasar del inicio). Al finalizar muestra el resumen: por ahora solo las horas; casas
/// visitadas, ventas y cobros llegan con sus módulos (#74, #75).
///
/// Todo es local (offline-first): iniciar o finalizar la jornada no necesita conexión, así que no
/// hay aviso de "sin conexión".
class JornadaPage extends ConsumerStatefulWidget {
  const JornadaPage({super.key, required this.sesion, this.onAbrirMapa});

  final Sesion sesion;

  /// "Abrir el mapa" de la jornada activa: la estructura de la app (`InicioPage`) cambia de
  /// pestaña. Sin él (en un test aislado) el botón no hace nada.
  final VoidCallback? onAbrirMapa;

  @override
  ConsumerState<JornadaPage> createState() => _JornadaPageState();
}

class _JornadaPageState extends ConsumerState<JornadaPage> with FinDeJornada<JornadaPage> {
  /// Cuántos minutos hacia atrás eligió el colportor (0 = ahora).
  DateTime? _horaInicio;
  bool _iniciando = false;

  /// Se intentó iniciar y resultó que ya hay una jornada abierta (otro teléfono, otra sesión):
  /// se muestra el bloqueo de la HU (A07) hasta que el colportor vaya a la jornada en curso.
  bool _bloqueadaPorEnCurso = false;
  String? _error;

  @override
  Sesion get sesionDelFin => widget.sesion;

  /// Cerrar la jornada suelta los avisos de inicio y el bloqueo de «ya hay una en curso».
  @override
  void alCerrarLaJornada() {
    _error = null;
    _bloqueadaPorEnCurso = false;
  }

  @override
  void initState() {
    super.initState();
    iniciarTic();
  }

  @override
  void dispose() {
    detenerTic();
    super.dispose();
  }

  /// La hora elegida a mano (el instante que el colportor vio y confirmó en la hoja), o `null` si
  /// es "ahora". Es absoluta: no se corre si cambia el minuto; si con el tiempo quedó fuera de
  /// rango, el caso de uso la rechaza con el rango explícito (nunca se ajusta en silencio).
  DateTime? _horaElegida(DateTime ahora) => _horaInicio;

  Future<void> _iniciar() async {
    if (_iniciando) return;
    final ahora = ahoraMostrado ?? ref.read(relojJornadaProvider)();
    setState(() {
      _iniciando = true;
      _error = null;
    });

    final failure = await ref
        .read(jornadaActualProvider(widget.sesion.usuarioId).notifier)
        .iniciar(hora: _horaElegida(ahora));

    if (!mounted) return;
    setState(() {
      _iniciando = false;
      switch (failure) {
        case null:
          _horaInicio = null;
        case FailureJornadaActiva():
          // La pantalla se relee con la jornada que ya estaba abierta y muestra el bloqueo literal.
          _bloqueadaPorEnCurso = true;
        case FailureHoraFueraDeRango(:final mensaje):
          _error = '$mensaje Elegí otra hora y volvé a intentar.';
        case Failure():
          _error =
              'No pudimos guardar el inicio de tu jornada. Probá de nuevo; si sigue pasando, '
              'avisale a tu coordinador.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ahora = ref.watch(relojJornadaProvider)();
    ahoraMostrado = ahora;
    final estado = ref.watch(jornadaActualProvider(widget.sesion.usuarioId));

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: estado.when(
            loading: () => const _Cargando(),
            error: (_, _) => _ErrorAlLeer(
              onReintentar: () => ref.invalidate(jornadaActualProvider(widget.sesion.usuarioId)),
            ),
            data: (jornada) => _Cuerpo(
              // La cabecera va arriba y las acciones al pie; en el medio queda el aire.
              cabecera: jornada == null
                  ? _cabeceraSinJornada(ahora)
                  : _bloqueadaPorEnCurso
                  ? _Cabecera(ahora: ahora)
                  : _cabeceraActiva(jornada, ahora),
              acciones: jornada == null
                  ? _accionesSinJornada(context, ahora)
                  : _bloqueadaPorEnCurso
                  ? _accionesBloqueada(jornada)
                  : _accionesFin(jornada, ahora),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabeceraSinJornada(DateTime ahora) => _Cabecera(
    ahora: ahora,
    estado: 'Sin jornada',
    titulo: 'Sin jornada en curso',
    detalle: 'Marcá el inicio cuando salgas a trabajar.',
  );

  /// "Jornada activa": desde qué hora y cuánto lleva.
  Widget _cabeceraActiva(Jornada jornada, DateTime ahora) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esquema = theme.colorScheme;
    // Mientras finaliza, cuánto llevaba hasta la hora de fin elegida (A04).
    final fin = finalizando ? (horaElegidaFin(jornada, ahora) ?? ahora) : ahora;
    final transcurrido = fin.difference(jornada.inicio);
    final conError = errorFin != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Cabecera(
          ahora: ahora,
          estado: conError ? 'Sigue en curso' : 'En curso',
          estadoActivo: true,
          titulo: 'Jornada activa',
          detalle: 'Desde las ${horaCorta(jornada.inicio)}',
        ),
        if (!conError) ...[
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: esquema.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colores.borde),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LLEVÁS', style: theme.textTheme.labelSmall?.copyWith(color: colores.gris)),
                const SizedBox(height: 4),
                Text(
                  transcurrido.isNegative ? 'menos de 1 min' : duracionCorta(transcurrido),
                  key: const Key('jornada_transcurrido'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 44,
                    color: esquema.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _accionesSinJornada(BuildContext context, DateTime ahora) {
    final elegida = _horaElegida(ahora);
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        if (_error case final error?)
          AvisoJornada(key: const Key('jornada_error'), texto: error, esError: true),
        FilaHoraJornada(
          hora: elegida == null ? 'Ahora' : horaCorta(elegida),
          detalle: elegida == null
              ? horaCorta(ahora)
              : 'hace ${minutosAtrasDe(ahora, elegida)} min',
          onTap: _iniciando ? null : () => _elegirHora(ahora),
        ),
        if (_error == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Podés marcar el inicio hasta ${IniciarJornadaUseCase.margenHaciaAtras.inMinutes} '
              'minutos hacia atrás.',
              style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris, fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 4),
        FilledButton(
          key: const Key('jornada_iniciar'),
          onPressed: _iniciando ? null : _iniciar,
          style: _iniciando ? ConEspera.estiloDelBoton(context) : null,
          child: _iniciando ? const ConEspera('Iniciando…') : const Text('Iniciar jornada'),
        ),
      ],
    );
  }

  /// Otra jornada quedó abierta (por ejemplo, sincronizada desde otro teléfono) y el colportor
  /// intentó iniciar: se bloquea con el texto literal de la HU y se ofrece ir a la que está en curso.
  Widget _accionesBloqueada(Jornada jornada) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 10,
    children: [
      const AvisoJornada(key: Key('jornada_bloqueo'), texto: textoBloqueoJornadaActiva),
      OutlinedButton(
        key: const Key('jornada_ver_en_curso'),
        onPressed: () => setState(() => _bloqueadaPorEnCurso = false),
        child: Text('Ver jornada en curso · desde ${horaCorta(jornada.inicio)}'),
      ),
      const SizedBox(height: 4),
      FilledButton.icon(
        key: const Key('jornada_iniciar'),
        onPressed: null,
        icon: const Icon(Icons.lock_outline, size: 16),
        label: const Text('Iniciar jornada'),
      ),
    ],
  );

  Future<void> _elegirHora(DateTime ahora) async {
    final margen = IniciarJornadaUseCase.margenHaciaAtras.inMinutes;
    final actual = _horaInicio;
    final elegida = await mostrarHojaHoraInicio(
      context,
      ahora: ahora,
      margenMinutos: margen,
      minutosAtras: actual == null ? 0 : minutosAtrasDe(ahora, actual).clamp(0, margen),
    );
    if (!mounted || elegida == null) return;
    setState(() {
      _horaInicio = elegida.esAhora ? null : elegida.hora;
      _error = null;
    });
  }

  /// Al pie de "Jornada activa" (vista 21): la hora de fin como fila tocable (abre la hoja de ±5
  /// minutos), "Abrir el mapa" y "Finalizar jornada".
  Widget _accionesFin(Jornada jornada, DateTime ahora) {
    final maximo = maximoAtrasFinDeJornada(jornada, ahora);
    final elegida = horaElegidaFin(jornada, ahora);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        if (errorFin case final error?)
          AvisoJornada(key: const Key('jornada_error_fin'), texto: error, esError: true),
        FilaHoraJornada(
          sufijoKey: '_fin',
          etiqueta: 'HORA DE FIN',
          hora: elegida == null ? 'Ahora' : horaCorta(elegida),
          detalle: elegida == null
              ? horaCorta(ahora)
              : 'hace ${minutosAtrasDe(ahora, elegida)} min',
          onTap: finalizando || maximo == 0 ? null : () => elegirHoraFin(ahora, maximo),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          key: const Key('jornada_abrir_mapa'),
          onPressed: widget.onAbrirMapa,
          icon: const Icon(Icons.map_outlined),
          label: const Text('Abrir el mapa'),
        ),
        FilledButton(
          key: const Key('jornada_finalizar'),
          onPressed: finalizando ? null : () => finalizarJornada(jornada),
          style: finalizando ? ConEspera.estiloDelBoton(context) : null,
          child: finalizando ? const ConEspera('Finalizando…') : const Text('Finalizar jornada'),
        ),
        // Vista 20 A08: con una jornada en curso no se puede iniciar otra.
        const AvisoJornada(key: Key('jornada_bloqueo'), texto: textoBloqueoJornadaActiva),
        FilledButton.icon(
          key: const Key('jornada_iniciar'),
          onPressed: null,
          icon: const Icon(Icons.lock_outline, size: 16),
          label: const Text('Iniciar jornada'),
        ),
      ],
    );
  }
}

/// Estructura común de "Hoy": la [cabecera] arriba, las [acciones] al pie (al alcance del pulgar) y
/// el aire en el medio. Con letra grande o pantalla baja, todo scrollea junto.
class _Cuerpo extends StatelessWidget {
  const _Cuerpo({required this.cabecera, required this.acciones});

  final Widget cabecera;
  final Widget acciones;

  @override
  Widget build(BuildContext context) => _PieFijoScrolleable(
    padding: const EdgeInsets.fromLTRB(20, 26, 20, 18),
    hijos: [
      Padding(padding: const EdgeInsets.fromLTRB(6, 0, 6, 24), child: cabecera),
      acciones,
    ],
  );
}

/// Columna que ocupa toda la altura disponible (con [hijos] separados: el primero arriba, el
/// último al pie) y scrollea entera si no entra. Sin `IntrinsicHeight`: mide el alto con el que
/// la pantalla la arma.
class _PieFijoScrolleable extends StatelessWidget {
  const _PieFijoScrolleable({required this.padding, required this.hijos});

  final EdgeInsets padding;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, restricciones) => SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (restricciones.maxHeight - padding.vertical).clamp(0, double.infinity),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: hijos,
        ),
      ),
    ),
  );
}

/// Fecha, estado (chip), título y detalle de "Hoy". Sin [estado] ni [titulo] es solo la fecha.
class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.ahora,
    this.estado,
    this.estadoActivo = false,
    this.titulo = 'Sin jornada en curso',
    this.detalle = 'Marcá el inicio cuando salgas a trabajar.',
  });

  final DateTime ahora;
  final String? estado;
  final bool estadoActivo;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esquema = theme.colorScheme;
    final colorEstado = estadoActivo ? esquema.primary : colores.gris;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Text(
          fechaLarga(ahora).toUpperCase(),
          key: const Key('jornada_fecha'),
          style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
        ),
        if (estado case final estado?)
          Container(
            key: const Key('jornada_chip'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: estadoActivo ? esquema.primary.withValues(alpha: .08) : null,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: estadoActivo ? esquema.primary : colores.bordeInput,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 7,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: estadoActivo ? colorEstado : null,
                      border: estadoActivo ? null : Border.all(color: colorEstado, width: 1.5),
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    estado,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: estadoActivo ? FontWeight.w600 : FontWeight.w500,
                      color: estadoActivo ? esquema.primary : esquema.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Semantics(
          liveRegion: true,
          child: Text(
            titulo,
            key: const Key('jornada_estado'),
            style: theme.textTheme.headlineMedium,
          ),
        ),
        Text(
          detalle,
          key: const Key('jornada_detalle'),
          style: theme.textTheme.bodyLarge?.copyWith(color: esquema.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('jornada_cargando'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Cargando tu jornada…', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// No se pudo leer la jornada guardada (A06): qué pasó y qué hacer, con "Reintentar".
class _ErrorAlLeer extends StatelessWidget {
  const _ErrorAlLeer({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;

    return _PieFijoScrolleable(
      padding: const EdgeInsets.fromLTRB(30, 0, 30, 18),
      hijos: [
        const SizedBox.shrink(),
        Semantics(
          liveRegion: true,
          container: true,
          key: const Key('jornada_error_lectura'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: esquema.error, width: 1.5),
                  ),
                  child: Text(
                    '!',
                    style: theme.textTheme.headlineMedium?.copyWith(color: esquema.error),
                  ),
                ),
              ),
              Text(textoNoPudimosLeerJornada, style: theme.textTheme.headlineMedium),
              Text(
                textoReintentarLeerJornada,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: esquema.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        FilledButton(
          key: const Key('jornada_reintentar'),
          onPressed: onReintentar,
          child: const Text('Reintentar'),
        ),
      ],
    );
  }
}
