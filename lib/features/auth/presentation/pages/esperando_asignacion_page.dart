import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../configuracion/presentation/pages/configuracion_page.dart';
import '../../../inicio/presentation/widgets/barra_pestanas_inicio.dart';
import '../../domain/entities/estado_cuenta.dart';
import '../providers/asignacion_campania_providers.dart';
import '../providers/estado_cuenta_providers.dart';
import '../providers/sesion_notifier.dart';
import '../widgets/aviso_modulo_bloqueado.dart';

/// Textos de la pantalla de espera (HU-AUTH-008, vista 18). Los literales de la HU van tal cual;
/// el resto es propuesta del diseño.
abstract final class TextosEsperaAsignacion {
  static const marca = 'COLPORTAJE';
  static const eyebrowPendiente = 'CUENTA PENDIENTE';
  static const eyebrowSuspendida = 'CUENTA SUSPENDIDA';

  static const tituloPendiente = 'Esperando asignación';
  static const pendiente =
      'Tu cuenta fue creada. Estamos esperando que tu coordinador te asigne a una campaña.';
  static const comoRevisar =
      'Cuando te asigne vas a poder empezar a trabajar. Deslizá hacia abajo o tocá Actualizar '
      'para revisar.';

  static const pasoCuentaCreada = 'Cuenta creada';
  static const pasoEsperando = 'Esperando asignación · ahora';
  static const pasoEsperandoNota = 'Depende de tu coordinador.';
  static const pasoListo = 'Listo para trabajar';

  static const actualizar = 'Actualizar';
  static const reintentar = 'Reintentar';
  static const consultando = 'Consultando…';
  static const revisando = 'Revisando con el servidor…';
  static const aunNoAsignado = 'Aún no asignado';

  static const tituloSuspendida = 'Cuenta suspendida';
  static const suspendida = 'Tu cuenta está suspendida. Contactá al administrador.';
  static const irAConfiguracion = 'Ir a Configuración';

  static const tituloSinEstado = 'No pudimos revisar tu cuenta';

  /// Sin conexión y sin estado conocido (nunca se pudo consultar; decisión de Cristian, 02/10): lo
  /// dice tal cual, qué pasa y qué hacer, en vez del genérico «No pudimos revisar tu cuenta».
  static const tituloSinConexion = 'Sin conexión';
  static const sinConexionSinEstado =
      'No hay conexión para revisar tu cuenta. Conectate a internet y tocá Reintentar.';
  static const probarDeNuevo = 'Probá de nuevo en unos minutos.';
  static const sinEstadoSinConexion =
      'Necesitás conexión para saber si ya te asignaron a una campaña. Conectate y tocá '
      'Actualizar.';
  static const sinEstado =
      'No pudimos consultar el estado de tu cuenta. Tocá Reintentar para probar de nuevo; si '
      'sigue pasando, avisale a tu coordinador.';

  static String revisadoRecien(String hora) => 'Revisado recién, a las $hora.';

  /// «Última revisión: hoy a las 14:30» (o «ayer», o con la fecha).
  static String ultimaRevision(DateTime revision, DateTime ahora) {
    final hora = _hora(revision);
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(revision.year, revision.month, revision.day);
    final cuando = switch (hoy.difference(dia).inDays) {
      0 => 'hoy',
      1 => 'ayer',
      _ => 'el ${dia.day.toString().padLeft(2, '0')}/${dia.month.toString().padLeft(2, '0')}',
    };
    return 'Última revisión: $cuando a las $hora';
  }

  static String _hora(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String horaDe(DateTime t) => _hora(t);
}

/// Qué pasó en la última revisión pedida por el colportor (18-A03, 18-A04, 18-A05).
enum _Resultado { aunNoAsignado, sinConexion, error }

/// Pantalla de la cuenta que todavía no puede trabajar (HU-AUTH-008, vista 18): pendiente de
/// asignación a una campaña, suspendida, o sin estado conocido porque nunca se pudo consultar. Los
/// módulos de campo no están (la barra inferior los muestra bloqueados); Configuración sí (cerrar
/// sesión, borrar datos). Nada de lo que hay en el teléfono se toca desde acá.
///
/// Refrescar (deslizando o con «Actualizar») vuelve a consultar al backend: si la cuenta pasó a
/// activa, la raíz de la app muestra «Ya te asignaron» y lleva a la pantalla principal sola.
class EsperandoAsignacionPage extends ConsumerStatefulWidget {
  const EsperandoAsignacionPage({this.estado, this.falla, super.key})
    : assert(estado != null || falla != null, 'un estado o la falla de no tenerlo');

  /// [EstadoCuenta.pendienteAsignacion] o [EstadoCuenta.suspendida].
  final EstadoCuenta? estado;

  /// Por qué no se conoce el estado (cuando [estado] es `null`).
  final Failure? falla;

  @override
  ConsumerState<EsperandoAsignacionPage> createState() => _EsperandoAsignacionPageState();
}

class _EsperandoAsignacionPageState extends ConsumerState<EsperandoAsignacionPage> {
  bool _consultando = false;
  _Resultado? _resultado;

  /// El resultado a mostrar: el de la última revisión pedida o, si todavía no se pidió ninguna y
  /// no se conoce el estado, la razón por la que no se conoce.
  _Resultado? get _resultadoVisible {
    if (_resultado != null) return _resultado;
    if (widget.estado != null) return null;
    return widget.falla is FailureSinConexion ? _Resultado.sinConexion : _Resultado.error;
  }

  /// Cuándo se consultó el estado por última vez con éxito (lo recuerda el repositorio).
  DateTime? get _ultimaRevision {
    final usuarioId = ref.read(sesionProvider).value?.usuarioId;
    if (usuarioId == null) return null;
    return ref.read(cuentaRepositoryProvider).ultimaConsultaExitosa(usuarioId);
  }

  Future<void> _actualizar() async {
    if (_consultando) return; // Doble tap o deslizar con el botón ya apretado: una sola consulta.
    setState(() => _consultando = true);
    Failure? falla;
    try {
      falla = await ref.read(estadoCuentaProvider.notifier).refrescar();
    } on Object catch (e) {
      falla = FailureInesperado(causa: e);
    }
    if (!mounted) return; // Pasó a activa: la raíz ya cambió de pantalla.

    final estado = ref.read(estadoCuentaProvider).value;
    setState(() {
      _consultando = false;
      if (falla == null) {
        _resultado = estado == EstadoCuenta.pendienteAsignacion ? _Resultado.aunNoAsignado : null;
      } else {
        _resultado = falla is FailureSinConexion ? _Resultado.sinConexion : _Resultado.error;
      }
    });
    // La cuenta suspendida no tiene dónde mostrar el resultado en el diseño: un aviso breve.
    if (widget.estado == EstadoCuenta.suspendida && falla != null) _avisar(falla.mensaje);
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(key: const Key('espera_resultado'), content: Text(mensaje)));
  }

  void _abrirConfiguracion() => unawaited(Navigator.of(context).push(ConfiguracionPage.ruta()));

  void _tocoModulo(PestanaInicio pestana) {
    if (pestana == PestanaInicio.hoy) return; // «Hoy» es esta pantalla.
    // Sin estado conocido, el aviso es el de esta pantalla para la misma causa y trae «Reintentar»
    // (#278): consulta igual que el botón de la pantalla.
    avisarModuloBloqueado(
      context,
      widget.estado,
      sinConexion: _resultadoVisible == _Resultado.sinConexion,
      alReintentar: () => unawaited(_actualizar()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suspendida = widget.estado == EstadoCuenta.suspendida;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 26,
        title: ExcludeSemantics(
          child: Text(
            TextosEsperaAsignacion.marca,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 2.4,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        actions: [
          IconButton(
            key: const Key('espera_configuracion'),
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _abrirConfiguracion,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _actualizar,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              // Deslizar tiene que andar aunque el contenido no llene la pantalla.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 18),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - 40)),
                child: suspendida
                    ? _Suspendida(alto: constraints.maxHeight, onConfiguracion: _abrirConfiguracion)
                    : _Pendiente(
                        estado: widget.estado,
                        consultando: _consultando,
                        resultado: _consultando ? null : _resultadoVisible,
                        revisadoA: _ultimaRevision,
                        ahora: ref.read(ahoraEsperaProvider),
                        detalleError: widget.estado == null,
                        onActualizar: _actualizar,
                      ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: BarraPestanasInicio(
        seleccionada: PestanaInicio.hoy,
        bloqueadas: modulosDeCampo,
        onSeleccionar: _tocoModulo,
      ),
    );
  }
}

/// 18-A01 a 18-A05: la cuenta pendiente (o sin estado conocido) con su revisión.
class _Pendiente extends StatelessWidget {
  const _Pendiente({
    required this.estado,
    required this.consultando,
    required this.resultado,
    required this.revisadoA,
    required this.ahora,
    required this.detalleError,
    required this.onActualizar,
  });

  /// `null`: no se conoce el estado (nunca se pudo consultar).
  final EstadoCuenta? estado;
  final bool consultando;
  final _Resultado? resultado;
  final DateTime? revisadoA;
  final DateTime Function() ahora;

  /// Sin estado conocido: el aviso de error lleva el texto largo y no repite el título.
  final bool detalleError;
  final VoidCallback onActualizar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final conocido = estado != null;
    // 18-A01: el cuerpo completo con la línea de tiempo. Mientras consulta o con un resultado a la
    // vista (18-A02 a 18-A05) queda lo esencial.
    final completo = conocido && !consultando && resultado == null;
    // Sin estado conocido y sin red: un aviso de sin conexión explícito, no el error genérico.
    final sinConexionSinEstado = !conocido && !consultando && resultado == _Resultado.sinConexion;

    final cuerpo = <Widget>[
      if (conocido)
        Text(
          TextosEsperaAsignacion.eyebrowPendiente,
          key: const Key('espera_eyebrow'),
          style: theme.textTheme.labelSmall?.copyWith(color: colores.gris, letterSpacing: 1.4),
        ),
      Semantics(
        header: true,
        child: Text(
          conocido
              ? TextosEsperaAsignacion.tituloPendiente
              : sinConexionSinEstado
              ? TextosEsperaAsignacion.tituloSinConexion
              : TextosEsperaAsignacion.tituloSinEstado,
          key: const Key('espera_titulo'),
          style: theme.textTheme.headlineMedium,
        ),
      ),
      if (conocido && (resultado == null || resultado == _Resultado.aunNoAsignado || consultando))
        Text(
          TextosEsperaAsignacion.pendiente,
          key: const Key('espera_mensaje'),
          style: theme.textTheme.bodyLarge,
        ),
      if (completo)
        Text(
          TextosEsperaAsignacion.comoRevisar,
          key: const Key('espera_ayuda'),
          style: theme.textTheme.bodyLarge,
        ),
    ];

    final aviso = switch (resultado) {
      _Resultado.aunNoAsignado => _Aviso(
        key: const Key('espera_aun_no_asignado'),
        tipo: _TipoAviso.info,
        titulo: TextosEsperaAsignacion.aunNoAsignado,
        texto: revisadoA == null
            ? null
            : TextosEsperaAsignacion.revisadoRecien(TextosEsperaAsignacion.horaDe(revisadoA!)),
      ),
      _Resultado.sinConexion => _Aviso(
        key: const Key('espera_sin_conexion'),
        tipo: _TipoAviso.sinConexion,
        texto: conocido
            ? TextosEsperaAsignacion.sinEstadoSinConexion
            : TextosEsperaAsignacion.sinConexionSinEstado,
      ),
      _Resultado.error => _Aviso(
        key: const Key('espera_error'),
        tipo: _TipoAviso.error,
        titulo: detalleError ? null : TextosEsperaAsignacion.tituloSinEstado,
        texto: detalleError
            ? TextosEsperaAsignacion.sinEstado
            : TextosEsperaAsignacion.probarDeNuevo,
      ),
      null => null,
    };

    final pie = <Widget>[
      if (consultando)
        Text(
          TextosEsperaAsignacion.revisando,
          key: const Key('espera_revisando'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
        )
      else if (aviso != null)
        aviso
      else if (revisadoA != null)
        Text(
          TextosEsperaAsignacion.ultimaRevision(revisadoA!, ahora()),
          key: const Key('espera_ultima_revision'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
        ),
      _BotonActualizar(
        consultando: consultando,
        // Sin estado conocido, siempre «Reintentar» (el texto del aviso lo nombra así).
        texto: resultado == _Resultado.error || !conocido
            ? TextosEsperaAsignacion.reintentar
            : TextosEsperaAsignacion.actualizar,
        onPressed: onActualizar,
      ),
    ];

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            ...cuerpo,
            if (completo) const Padding(padding: EdgeInsets.only(top: 10), child: _LineaDeTiempo()),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: pie),
        ),
      ],
    );
  }
}

/// 18-A06: la cuenta suspendida. Solo Configuración, sin «Actualizar».
class _Suspendida extends StatelessWidget {
  const _Suspendida({required this.alto, required this.onConfiguracion});

  final double alto;
  final VoidCallback onConfiguracion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rojo = theme.colorScheme.error;
    final escala = MediaQuery.textScalerOf(context).scale(15);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: math.max(0, alto - 40 - 90)),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                      border: Border.all(color: rojo, width: 1.5),
                    ),
                    child: Icon(Icons.block, color: rojo),
                  ),
                ),
                Text(
                  TextosEsperaAsignacion.eyebrowSuspendida,
                  style: theme.textTheme.labelSmall?.copyWith(color: rojo, letterSpacing: 1.4),
                ),
                Semantics(
                  header: true,
                  child: Text(
                    TextosEsperaAsignacion.tituloSuspendida,
                    key: const Key('espera_titulo'),
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                Text(
                  TextosEsperaAsignacion.suspendida,
                  key: const Key('espera_mensaje'),
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          key: const Key('espera_ir_a_configuracion'),
          onPressed: onConfiguracion,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: escala > 20
                ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                : const StadiumBorder(),
          ),
          child: const Text(TextosEsperaAsignacion.irAConfiguracion, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

/// «Actualizar» / «Reintentar»; mientras consulta se deshabilita y dice «Consultando…».
class _BotonActualizar extends StatelessWidget {
  const _BotonActualizar({required this.consultando, required this.texto, required this.onPressed});

  final bool consultando;
  final String texto;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final escala = MediaQuery.textScalerOf(context).scale(15);
    return FilledButton(
      key: const Key('espera_actualizar'),
      onPressed: consultando ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: escala > 20
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
            : const StadiumBorder(),
        disabledBackgroundColor: theme.colorScheme.secondary.withValues(alpha: .85),
        disabledForegroundColor: Colors.white,
      ),
      child: consultando
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 10,
              children: [
                SizedBox.square(
                  key: Key('espera_consultando'),
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                Flexible(
                  child: Text(TextosEsperaAsignacion.consultando, textAlign: TextAlign.center),
                ),
              ],
            )
          : Text(texto, textAlign: TextAlign.center),
    );
  }
}

enum _TipoAviso { info, sinConexion, error }

/// El resultado de una revisión (18-A03 a 18-A05): marca, color y borde propios de cada tipo, para
/// que no dependa solo del color.
class _Aviso extends StatelessWidget {
  const _Aviso({super.key, required this.tipo, this.titulo, this.texto});

  final _TipoAviso tipo;
  final String? titulo;
  final String? texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final (color, marca, estiloBorde) = switch (tipo) {
      _TipoAviso.info => (colores.gris, 'i', false),
      _TipoAviso.sinConexion => (theme.colorScheme.onSurfaceVariant, '✕', true),
      _TipoAviso.error => (theme.colorScheme.error, '!', false),
    };
    final borde = tipo == _TipoAviso.error ? theme.colorScheme.error : colores.bordeInput;
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        if (titulo != null)
          Text(titulo!, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        if (texto != null)
          Text(
            texto!,
            style: titulo == null
                ? theme.textTheme.bodyMedium?.copyWith(height: 1.45)
                : theme.textTheme.bodySmall?.copyWith(color: colores.gris, height: 1.45),
          ),
      ],
    );
    return Semantics(
      liveRegion: true,
      container: true,
      child: CustomPaint(
        painter: estiloBorde ? _BordeDiscontinuo(colores.gris) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: estiloBorde ? null : Border.all(color: borde, width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: tipo == _TipoAviso.info
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 1.5),
                        )
                      : BoxDecoration(shape: BoxShape.circle, color: color),
                  child: Text(
                    marca,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tipo == _TipoAviso.info
                          ? theme.colorScheme.onSurfaceVariant
                          : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(child: contenido),
            ],
          ),
        ),
      ),
    );
  }
}

/// Borde discontinuo redondeado del aviso de «sin conexión» (18-A04).
class _BordeDiscontinuo extends CustomPainter {
  const _BordeDiscontinuo(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final trazo = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final camino = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(.75, .75, size.width - 1.5, size.height - 1.5),
          const Radius.circular(14),
        ),
      );
    for (final tramo in camino.computeMetrics()) {
      for (var d = 0.0; d < tramo.length; d += 10) {
        canvas.drawPath(tramo.extractPath(d, math.min(d + 6, tramo.length)), trazo);
      }
    }
  }

  @override
  bool shouldRepaint(_BordeDiscontinuo vieja) => vieja.color != color;
}

/// Los tres pasos del alta (18-A01): cuenta creada, esperando asignación, listo para trabajar.
class _LineaDeTiempo extends StatelessWidget {
  const _LineaDeTiempo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    const verde = Color(0xFF1F6E3A);
    final primario = theme.colorScheme.primary;

    Widget paso({
      required Widget marca,
      required String texto,
      String? nota,
      required String estado,
      Color? colorTexto,
      FontWeight peso = FontWeight.w600,
      bool conLinea = true,
      double largoLinea = 26,
    }) => Semantics(
      container: true,
      excludeSemantics: true,
      label: '$texto, $estado${nota == null ? '' : '. $nota'}',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Column(
              children: [
                marca,
                if (conLinea)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      constraints: BoxConstraints(minHeight: largoLinea),
                      color: colores.bordeInput,
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 2, bottom: conLinea ? 8 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      texto,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: peso,
                        color: colorTexto,
                      ),
                    ),
                    if (nota != null)
                      Text(nota, style: theme.textTheme.bodySmall?.copyWith(color: colores.gris)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      key: const Key('espera_linea_de_tiempo'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        paso(
          marca: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: verde),
            child: const Icon(Icons.check, size: 14, color: Colors.white),
          ),
          texto: TextosEsperaAsignacion.pasoCuentaCreada,
          estado: 'hecho',
        ),
        paso(
          marca: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: primario, width: 2),
            ),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: primario),
            ),
          ),
          texto: TextosEsperaAsignacion.pasoEsperando,
          nota: TextosEsperaAsignacion.pasoEsperandoNota,
          estado: 'en curso',
          colorTexto: primario,
          largoLinea: 40,
        ),
        paso(
          marca: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colores.placeholder, width: 1.5),
            ),
          ),
          texto: TextosEsperaAsignacion.pasoListo,
          estado: 'pendiente',
          colorTexto: colores.gris,
          peso: FontWeight.w400,
          conLinea: false,
        ),
      ],
    );
  }
}
