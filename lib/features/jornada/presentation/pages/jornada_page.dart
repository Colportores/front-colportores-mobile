import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/domain/entities/sesion.dart';
import '../../../configuracion/presentation/pages/configuracion_page.dart';
import '../../domain/entities/jornada.dart';
import '../../domain/usecases/iniciar_jornada_use_case.dart';
import '../formato_jornada.dart';
import '../providers/jornada_actual_notifier.dart';
import '../providers/jornada_providers.dart';

/// Texto literal del criterio de aceptación "Bloqueo - jornada ya activa" (HU-JOR-001).
const textoBloqueoJornadaActiva = 'Tenés una jornada en curso. Cerrala antes de iniciar otra.';

/// Pantalla principal: la jornada de trabajo del colportor (HU-JOR-001).
///
/// Sin jornada muestra "Iniciar jornada" (con la hora ajustable hasta 30 minutos hacia atrás);
/// con una en curso cambia a "Jornada activa" y bloquea iniciar otra. Va sin diseño de Claude
/// Design, con el tema y los componentes de login/registro (decisión del 22/09 para las vistas
/// del Sprint 4).
///
/// Todo es local (offline-first): iniciar la jornada no necesita conexión, así que no hay aviso
/// de "sin conexión".
class JornadaPage extends ConsumerStatefulWidget {
  const JornadaPage({super.key, required this.sesion});

  final Sesion sesion;

  @override
  ConsumerState<JornadaPage> createState() => _JornadaPageState();
}

class _JornadaPageState extends ConsumerState<JornadaPage> {
  /// Refresca "Ahora · 14:35" y "Llevás 1 h 20 min" mientras la pantalla está abierta.
  Timer? _tic;

  /// Cuántos minutos hacia atrás eligió el colportor (0 = ahora).
  int _minutosAtras = 0;
  bool _ajustandoHora = false;
  bool _iniciando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tic = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tic?.cancel();
    super.dispose();
  }

  /// La hora elegida a mano, al principio de su minuto (el selector ofrece minutos enteros), o
  /// `null` si es "ahora".
  DateTime? _horaElegida(DateTime ahora) =>
      _minutosAtras == 0 ? null : _menosMinutos(ahora, _minutosAtras);

  Future<void> _iniciar() async {
    if (_iniciando) return;
    final ahora = ref.read(relojJornadaProvider)();
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
          _minutosAtras = 0;
          _ajustandoHora = false;
        case FailureJornadaActiva():
          // La pantalla se relee y pasa a "Jornada activa", que ya muestra el bloqueo literal.
          break;
        case FailureHoraFueraDeRango(:final mensaje):
          _error = '$mensaje Elegí otra hora y volvé a intentar.';
        case Failure():
          _error =
              'No pudimos guardar el inicio de tu jornada. Probá de nuevo; si sigue pasando, '
              'cerrá y volvé a abrir la app.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esOscuro = theme.brightness == Brightness.dark;
    final ahora = ref.watch(relojJornadaProvider)();
    final estado = ref.watch(jornadaActualProvider(widget.sesion.usuarioId));
    final paddingHorizontal = esOscuro ? 26.0 : 30.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        // Sin esto los íconos de la barra salen con `onSurfaceVariant`, que en el tema oscuro es
        // casi negro sobre el navy.
        foregroundColor: theme.colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: paddingHorizontal,
        title: const _Marca(),
        actions: [
          // Cerrar sesión (con confirmación) y borrar datos viven en Configuración (HU-AUTH-006/010).
          IconButton(
            key: const Key('inicio_configuracion'),
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(ConfiguracionPage.ruta()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(paddingHorizontal, 12, paddingHorizontal, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    fechaLarga(ahora).toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: esOscuro ? colores.oro : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Tu jornada', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    widget.sesion.email,
                    key: const Key('inicio_email'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
                  ),
                  const SizedBox(height: 28),
                  estado.when(
                    loading: () => const _Cargando(),
                    error: (_, _) => _ErrorAlLeer(
                      onReintentar: () =>
                          ref.invalidate(jornadaActualProvider(widget.sesion.usuarioId)),
                    ),
                    data: (jornada) => jornada == null
                        ? _sinJornada(context, ahora)
                        : _JornadaActiva(jornada: jornada, ahora: ahora),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sinJornada(BuildContext context, DateTime ahora) {
    final elegida = _horaElegida(ahora);
    final textoHora = elegida == null
        ? 'Ahora · ${horaCorta(ahora)}'
        : '${horaCorta(elegida)} · hace $_minutosAtras min';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _TarjetaEstado(
          icono: Icons.wb_sunny_outlined,
          titulo: 'Sin jornada en curso',
          detalle: 'Marcá el inicio cuando salgas a trabajar.',
        ),
        const SizedBox(height: 14),
        _SelectorHora(
          textoHora: textoHora,
          ajustando: _ajustandoHora,
          minutosAtras: _minutosAtras,
          horaPara: (minutos) =>
              minutos == 0 ? horaCorta(ahora) : horaCorta(_menosMinutos(ahora, minutos)),
          onAlternar: _iniciando ? null : () => setState(() => _ajustandoHora = !_ajustandoHora),
          onCambiar: (minutos) => setState(() {
            _minutosAtras = minutos;
            _error = null;
          }),
        ),
        const SizedBox(height: 22),
        if (_error case final error?) ...[
          _Aviso(key: const Key('jornada_error'), texto: error, esError: true),
          const SizedBox(height: 14),
        ],
        FilledButton.icon(
          key: const Key('jornada_iniciar'),
          onPressed: _iniciando ? null : _iniciar,
          icon: _iniciando
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: Text(_iniciando ? 'Iniciando…' : 'Iniciar jornada'),
        ),
      ],
    );
  }

  static DateTime _menosMinutos(DateTime ahora, int minutos) => DateTime(
    ahora.year,
    ahora.month,
    ahora.day,
    ahora.hour,
    ahora.minute,
  ).subtract(Duration(minutes: minutos));
}

/// Marca de la app en la barra: el mismo cuadrado + "COLPORTAJE" del login claro (1b).
class _Marca extends StatelessWidget {
  const _Marca();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'COLPORTAJE',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 2.4,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta del estado de la jornada. [activa] la pinta con el color primario del tema.
class _TarjetaEstado extends StatelessWidget {
  const _TarjetaEstado({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.activa = false,
    this.extra = const [],
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final bool activa;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esOscuro = theme.brightness == Brightness.dark;
    final esquema = theme.colorScheme;

    final fondo = activa
        ? esquema.primary
        : (esOscuro ? colores.inputRelleno : esquema.surfaceContainerHighest);
    final texto = activa ? esquema.onPrimary : esquema.onSurface;
    final textoSecundario = activa ? esquema.onPrimary : colores.gris;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(20),
        border: activa ? null : Border.all(color: colores.borde, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: activa
                  ? esquema.onPrimary.withValues(alpha: .14)
                  : esquema.primary.withValues(alpha: .1),
            ),
            child: Icon(icono, color: activa ? esquema.onPrimary : esquema.primary),
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              titulo,
              key: const Key('jornada_estado'),
              style: theme.textTheme.headlineMedium?.copyWith(fontSize: 24, color: texto),
            ),
          ),
          const SizedBox(height: 6),
          Text(detalle, style: theme.textTheme.bodyLarge?.copyWith(color: textoSecundario)),
          ...extra,
        ],
      ),
    );
  }
}

/// "Jornada activa": desde qué hora y cuánto lleva, y el bloqueo de iniciar otra.
class _JornadaActiva extends StatelessWidget {
  const _JornadaActiva({required this.jornada, required this.ahora});

  final Jornada jornada;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    final transcurrido = ahora.difference(jornada.inicio);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TarjetaEstado(
          activa: true,
          icono: Icons.directions_walk_rounded,
          titulo: 'Jornada activa',
          detalle: 'Desde las ${horaCorta(jornada.inicio)}',
          extra: [
            const SizedBox(height: 18),
            Divider(color: esquema.onPrimary.withValues(alpha: .25)),
            const SizedBox(height: 14),
            Text('LLEVÁS', style: theme.textTheme.labelMedium?.copyWith(color: esquema.onPrimary)),
            const SizedBox(height: 4),
            Text(
              transcurrido.isNegative ? 'menos de 1 min' : duracionCorta(transcurrido),
              key: const Key('jornada_transcurrido'),
              style: theme.textTheme.headlineMedium?.copyWith(color: esquema.onPrimary),
            ),
          ],
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          key: const Key('jornada_iniciar'),
          onPressed: null,
          // El tema oscuro le da sombra dorada al botón; deshabilitado queda sucia.
          style: FilledButton.styleFrom(elevation: 0, shadowColor: Colors.transparent),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Iniciar jornada'),
        ),
        const SizedBox(height: 14),
        const _Aviso(key: Key('jornada_bloqueo'), texto: textoBloqueoJornadaActiva),
      ],
    );
  }
}

/// La hora de inicio: "ahora" por defecto, o hasta 30 minutos hacia atrás con el deslizador.
class _SelectorHora extends StatelessWidget {
  const _SelectorHora({
    required this.textoHora,
    required this.ajustando,
    required this.minutosAtras,
    required this.horaPara,
    required this.onAlternar,
    required this.onCambiar,
  });

  final String textoHora;
  final bool ajustando;
  final int minutosAtras;
  final String Function(int minutosAtras) horaPara;
  final VoidCallback? onAlternar;
  final ValueChanged<int> onCambiar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esOscuro = theme.brightness == Brightness.dark;
    final esquema = theme.colorScheme;
    final maximo = IniciarJornadaUseCase.margenHaciaAtras.inMinutes;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: esOscuro ? colores.inputRelleno : esquema.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.borde, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: esquema.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HORA DE INICIO',
                      style: theme.textTheme.labelMedium?.copyWith(color: colores.gris),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      textoHora,
                      key: const Key('jornada_hora'),
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('jornada_ajustar_hora'),
                onPressed: onAlternar,
                child: Text(ajustando ? 'Listo' : 'Cambiar'),
              ),
            ],
          ),
          if (ajustando) ...[
            const SizedBox(height: 8),
            Slider(
              key: const Key('jornada_selector_hora'),
              min: -maximo.toDouble(),
              max: 0,
              divisions: maximo,
              value: -minutosAtras.toDouble(),
              label: horaPara(minutosAtras),
              semanticFormatterCallback: (valor) => 'Inicio a las ${horaPara(-valor.round())}',
              onChanged: (valor) => onCambiar(-valor.round()),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Podés marcar el inicio hasta $maximo minutos hacia atrás.',
                style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Aviso en línea: error (qué pasó y qué hacer) o información (el bloqueo de jornada activa).
class _Aviso extends StatelessWidget {
  const _Aviso({super.key, required this.texto, this.esError = false});

  final String texto;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esOscuro = theme.brightness == Brightness.dark;
    final esquema = theme.colorScheme;

    final fondo = esError
        ? esquema.errorContainer
        : (esOscuro ? colores.inputRelleno : esquema.surfaceContainerHighest);
    final color = esError ? esquema.onErrorContainer : esquema.onSurface;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(14),
          border: esError ? null : Border.all(color: colores.borde, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              esError ? Icons.error_outline : Icons.info_outline,
              color: esError ? color : esquema.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(texto, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
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
    final theme = Theme.of(context);
    return Padding(
      key: const Key('jornada_cargando'),
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Cargando tu jornada…', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// No se pudo leer la jornada guardada: qué pasó y qué hacer, con "Reintentar".
class _ErrorAlLeer extends StatelessWidget {
  const _ErrorAlLeer({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Aviso(
          key: Key('jornada_error_lectura'),
          esError: true,
          texto:
              'No pudimos leer tu jornada. Tocá "Reintentar"; si sigue pasando, cerrá y volvé a '
              'abrir la app.',
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const Key('jornada_reintentar'),
          onPressed: onReintentar,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }
}
