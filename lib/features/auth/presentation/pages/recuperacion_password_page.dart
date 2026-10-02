import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/usecases/solicitar_recuperacion_password_use_case.dart';
import '../providers/auth_providers.dart';

/// Pantalla "Olvidé mi contraseña" (HU-AUTH-004), vista 14 del diseño (#223): el formulario con el
/// aviso informativo arriba y el botón al pie (A01 a A04 y A06) y, al enviar, una pantalla aparte
/// con el mensaje neutro, «Reenviar» con cuenta regresiva y «Volver al login» (A05).
///
/// Sin casilla «Entiendo el impacto» ni ⚠ (decisión de Cristian del 02/10, #272): como los datos
/// del teléfono se conservan, no hay impacto que aceptar, así que el botón está habilitado desde el
/// principio y un campo vacío se avisa al tocarlo. El canvas todavía dibuja la casilla en A01 y A02
/// y el ⚠; esta decisión manda sobre el canvas.
///
/// Llama directo a `solicitarRecuperacionPasswordUseCaseProvider`, no a través de
/// `SesionNotifier`: la solicitud no toca el estado de sesión (igual que
/// `SesionNotifier.reenviarVerificacion` en HU-AUTH-002), así que ni siquiera hace falta pasar por
/// el notifier.
///
/// El mensaje de éxito es **siempre el mismo** exista o no el email (anti-enumeración, OWASP): el
/// back (`AuthRepositoryImpl.solicitarRecuperacionPassword`) ya enmascara como éxito tanto "no
/// existe" como el rate limit de Supabase (429) — esta pantalla no puede ni debe intentar
/// distinguirlos. Los errores reales del servicio (sin conexión, falla del servidor) sí llegan
/// como [Failure] visible, con el mismo tratamiento que el resto del flujo de auth.
class RecuperacionPasswordPage extends ConsumerStatefulWidget {
  const RecuperacionPasswordPage({
    super.key,
    this.emailInicial,
    @visibleForTesting this.ahora = DateTime.now,
  });

  /// El email con el que arranca el campo, si ya se sabe: la preparación de la DB local la abre
  /// con el de la sesión (revisión del PR #130, N1). Se puede cambiar.
  final String? emailInicial;

  /// El reloj de la cuenta regresiva; los tests lo adelantan.
  final DateTime Function() ahora;

  @override
  ConsumerState<RecuperacionPasswordPage> createState() => _RecuperacionPasswordPageState();
}

class _RecuperacionPasswordPageState extends ConsumerState<RecuperacionPasswordPage>
    with WidgetsBindingObserver {
  /// HU-AUTH-004: "máximo 1 solicitud por email cada 60 segundos" — mismo patrón que el reenvío
  /// de verificación de email (HU-AUTH-002, `VerificacionEmailPage._cooldown`). El tope de
  /// "5 por hora" no se replica acá: ver dartdoc de [SolicitarRecuperacionPasswordUseCase] y el
  /// comentario en el issue #46 — no hay infraestructura que lo aplique tal cual lo pide la HU
  /// todavía, y dónde resolverlo es una decisión pendiente de Cristian.
  static const Duration _cooldown = Duration(seconds: 60);

  /// Texto fijo por la HU (líneas 809/816): igual exista o no el email. El diseño lo abrevia
  /// («Te enviamos un enlace de recuperación»), pero eso afirma que el email existe: manda la HU.
  static const String _mensajeExito =
      'Si el email está registrado, te enviamos un enlace de recuperación';

  /// Apoyo de la pantalla de éxito (A05).
  static const String _textoSpam = 'Si no lo encontrás, revisá la carpeta de spam.';

  /// Aviso informativo (decisión de Cristian 01/10): el mismo texto de la vista 15 (15-A02). La
  /// clave de los datos del teléfono queda protegida (ADR-006, HU-AUTH-004): nada se pierde. Se
  /// muestra siempre, antes de enviar, sin casilla que aceptar (#272).
  static const String _textoAviso = 'Tus datos guardados en este teléfono se conservan.';

  late final _email = TextEditingController(text: widget.emailInicial);
  Timer? _timer;
  int _segundosRestantes = 0;

  /// Cuándo termina la cuenta regresiva. El timer solo repinta: al volver de segundo plano los
  /// segundos se recalculan desde acá, porque el timer se atrasa con la app pausada.
  DateTime? _venceCooldown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final vence = _venceCooldown;
    if (state != AppLifecycleState.resumed || vence == null || _segundosRestantes <= 0) return;
    final restanteMs = vence.difference(widget.ahora()).inMilliseconds;
    setState(() {
      _segundosRestantes = (restanteMs / 1000).ceil().clamp(0, _cooldown.inSeconds);
      if (_segundosRestantes <= 0) _timer?.cancel();
    });
  }

  Map<String, String> _erroresCampo = const {};
  String? _errorGeneral;
  bool _enviado = false;
  bool _enviando = false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  void _iniciarCooldown() {
    _timer?.cancel();
    _venceCooldown = widget.ahora().add(_cooldown);
    setState(() => _segundosRestantes = _cooldown.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _segundosRestantes--;
        if (_segundosRestantes <= 0) timer.cancel();
      });
    });
  }

  /// Gatea tanto el `onPressed` del botón como el envío por teclado (`onSubmitted`) y la reentrada
  /// de [_enviar]: sin esto, un doble tap o un "Listo" del teclado justo antes del próximo rebuild
  /// podría disparar dos solicitudes (el botón recién se deshabilita cuando `setState` repinta).
  bool get _puedeEnviar => !_enviando && _segundosRestantes == 0;

  Future<void> _enviar() async {
    if (!_puedeEnviar) return;

    setState(() {
      _enviando = true;
      _erroresCampo = const {};
      _errorGeneral = null;
    });

    final resultado = await ref.read(solicitarRecuperacionPasswordUseCaseProvider)(
      SolicitarRecuperacionPasswordParams(email: _email.text),
    );

    if (!mounted) return;

    resultado.fold(
      (failure) {
        setState(() {
          _enviando = false;
          switch (failure) {
            case FailureValidacion(:final campos):
              _erroresCampo = campos;
            case Failure():
              // HU-AUTH-004, "Error - sin conectividad" (#94).
              _errorGeneral = mensajePara(failure, accion: 'solicitar la recuperación');
          }
        });
      },
      (_) {
        setState(() {
          _enviando = false;
          _enviado = true;
        });
        _iniciarCooldown();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Mientras envía no se sale: ni la flecha ni el atrás del sistema (la solicitud sigue en vuelo).
    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 26),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 26).clamp(0, double.infinity),
                ),
                child: _enviado ? _exito(context) : _formulario(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A01 a A04 y A06: el formulario. Enviando (A04) el campo y el botón quedan deshabilitados y el
  /// botón dice «Enviando…».
  Widget _formulario(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerLeft, child: _botonAtras()),
            const SizedBox(height: 10),
            Text(
              'RECUPERAR CONTRASEÑA',
              style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
            ),
            const SizedBox(height: 10),
            Semantics(
              header: true,
              child: Text('¿Olvidaste tu contraseña?', style: _estiloTitulo(context, theme, 30)),
            ),
            const SizedBox(height: 12),
            Text(
              'Ingresá tu email y te enviamos un enlace para restablecerla.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            const _AvisoDatos(texto: _textoAviso),
            const SizedBox(height: 22),
            _CampoRecuperacion(
              controller: _email,
              errorText: _erroresCampo['email'],
              enabled: !_enviando,
              onSubmitted: (_) => _enviar(),
            ),
            if (_errorGeneral != null) ...[
              const SizedBox(height: 12),
              _ErrorGeneral(texto: _errorGeneral!),
            ],
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('recuperacion_password_enviar'),
              onPressed: _puedeEnviar ? _enviar : null,
              child: _enviando ? const _Enviando() : const Text('Enviar enlace de recuperación'),
            ),
          ],
        ),
      ],
    );
  }

  /// A05: el mensaje neutro, «Reenviar» con la cuenta regresiva y «Volver al login». El título es
  /// el texto de la HU (nunca dice si el email existe). Los límites de intentos muestran esta misma
  /// pantalla.
  Widget _exito(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 56),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.alternate_email, color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
            Text(
              'RECUPERAR CONTRASEÑA',
              style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
            ),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                _mensajeExito,
                key: const Key('recuperacion_password_exito'),
                style: _estiloTitulo(context, theme, 26),
              ),
            ),
            Text(_textoSpam, style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            if (_errorGeneral != null) _ErrorGeneral(texto: _errorGeneral!),
            OutlinedButton(
              key: const Key('recuperacion_password_reenviar'),
              onPressed: _puedeEnviar ? _enviar : null,
              child: _enviando
                  ? const _Enviando()
                  : Text(
                      _segundosRestantes > 0
                          ? 'Reenviar en ${_segundosRestantes}s'
                          : 'Reenviar enlace',
                    ),
            ),
            TextButton(
              key: const Key('recuperacion_password_volver_login'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Volver al login'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _botonAtras() => IconButton(
    key: const Key('recuperacion_password_atras'),
    tooltip: 'Volver',
    onPressed: _enviando ? null : () => Navigator.of(context).pop(),
    icon: const Icon(Icons.chevron_left, size: 32),
  );
}

/// El título, más chico con el texto muy grande (más de 1,5) para que una palabra larga no se
/// parta a mitad de palabra.
TextStyle? _estiloTitulo(BuildContext context, ThemeData theme, double tamano) {
  final grande = MediaQuery.textScalerOf(context).scale(1) > 1.5;
  return theme.textTheme.headlineMedium?.copyWith(fontSize: grande ? tamano * 0.72 : tamano);
}

/// El indicador y el texto «Enviando…» del botón (A04).
class _Enviando extends StatelessWidget {
  const _Enviando();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 10,
    children: [
      SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      Flexible(child: Text('Enviando…')),
    ],
  );
}

/// El aviso sobre los datos locales, arriba del campo (A01): solo informa, sin ⚠ ni casilla (#272).
class _AvisoDatos extends StatelessWidget {
  const _AvisoDatos({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: esquema.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: esquema.primary, width: 1.5),
        ),
        child: Text(
          texto,
          key: const Key('recuperacion_password_aviso'),
          style: theme.textTheme.bodySmall?.copyWith(color: esquema.onSurface, height: 1.45),
        ),
      ),
    );
  }
}

/// El error del servicio (sin conexión, falla del servidor), con la ✕ del diseño (A06).
class _ErrorGeneral extends StatelessWidget {
  const _ErrorGeneral({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          ExcludeSemantics(child: Icon(Icons.close, size: 18, color: theme.colorScheme.error)),
          Expanded(
            child: Text(
              texto,
              key: const Key('recuperacion_password_error_general'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo de email — mismo criterio visual que `_CampoLogin`/`_CampoRegistro`/`_CampoEmail` de las
/// otras páginas de auth, sin duplicar esas clases privadas.
class _CampoRecuperacion extends StatelessWidget {
  const _CampoRecuperacion({
    required this.controller,
    this.errorText,
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CORREO', style: theme.textTheme.labelMedium?.copyWith(color: colores.gris)),
        const SizedBox(height: 6),
        TextField(
          key: const Key('recuperacion_password_email'),
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: onSubmitted,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: 'lucia.silva@correo.com',
            errorText: errorText,
            constraints: const BoxConstraints(minHeight: 48),
          ),
        ),
      ],
    );
  }
}
