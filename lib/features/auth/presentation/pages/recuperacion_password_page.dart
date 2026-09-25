import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/usecases/solicitar_recuperacion_password_use_case.dart';
import '../providers/auth_providers.dart';

/// Pantalla "Olvidé mi contraseña" (HU-AUTH-004), diseño "Login Colportor" — sin diseño propio
/// para esta pantalla (decisión de Cristian): reusa tema y componentes de [LoginPage]/`RegistroPage`.
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
  const RecuperacionPasswordPage({super.key, this.emailInicial});

  /// El email con el que arranca el campo, si ya se sabe: la preparación de la DB local la abre
  /// con el de la sesión (revisión del PR #130, N1). Se puede cambiar.
  final String? emailInicial;

  @override
  ConsumerState<RecuperacionPasswordPage> createState() => _RecuperacionPasswordPageState();
}

class _RecuperacionPasswordPageState extends ConsumerState<RecuperacionPasswordPage> {
  /// HU-AUTH-004: "máximo 1 solicitud por email cada 60 segundos" — mismo patrón que el reenvío
  /// de verificación de email (HU-AUTH-002, `VerificacionEmailPage._cooldown`). El tope de
  /// "5 por hora" no se replica acá: ver dartdoc de [SolicitarRecuperacionPasswordUseCase] y el
  /// comentario en el issue #46 — no hay infraestructura que lo aplique tal cual lo pide la HU
  /// todavía, y dónde resolverlo es una decisión pendiente de Cristian.
  static const Duration _cooldown = Duration(seconds: 60);

  /// Texto fijo por la HU (líneas 809/816): igual exista o no el email.
  static const String _mensajeExito =
      'Si el email está registrado, te enviamos un enlace de recuperación';

  /// Advertencia literal de la HU (línea 798) — se muestra siempre, antes de enviar.
  static const String _textoAviso =
      'Si restablecés tu contraseña y tenés datos locales en otro dispositivo, no podrás '
      'abrirlos ahí. Tendrás que restaurar desde tu backup.';

  late final _email = TextEditingController(text: widget.emailInicial);
  Timer? _timer;
  int _segundosRestantes = 0;

  Map<String, String> _erroresCampo = const {};
  String? _errorGeneral;
  String? _mensajeExitoActual;
  bool _entiendeImpacto = false;
  bool _enviando = false;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  void _iniciarCooldown() {
    _timer?.cancel();
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
  bool get _puedeEnviar => _entiendeImpacto && !_enviando && _segundosRestantes == 0;

  Future<void> _enviar() async {
    if (!_puedeEnviar) return;

    setState(() {
      _enviando = true;
      _erroresCampo = const {};
      _errorGeneral = null;
      _mensajeExitoActual = null;
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
          _mensajeExitoActual = _mensajeExito;
        });
        _iniciarCooldown();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    const paddingHorizontal = 30.0;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            key: const Key('recuperacion_password_atras'),
                            onPressed: () => Navigator.of(context).pop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            alignment: Alignment.centerLeft,
                            icon: Text(
                              '‹',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontSize: 26,
                                height: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'RECUPERAR CONTRASEÑA',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '¿Olvidaste tu contraseña?',
                        style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Ingresá tu email y te enviamos un enlace para restablecerla.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 22),
                      _CampoRecuperacion(
                        controller: _email,
                        errorText: _erroresCampo['email'],
                        onSubmitted: (_) => _enviar(),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _textoAviso,
                        key: const Key('recuperacion_password_aviso'),
                        style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              key: const Key('recuperacion_password_checkbox'),
                              value: _entiendeImpacto,
                              onChanged: (valor) =>
                                  setState(() => _entiendeImpacto = valor ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Entiendo el impacto sobre mis datos locales',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12.5,
                                height: 1.45,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_mensajeExitoActual != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _mensajeExitoActual!,
                          key: const Key('recuperacion_password_exito'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                      if (_errorGeneral != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorGeneral!,
                          key: const Key('recuperacion_password_error_general'),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const Key('recuperacion_password_enviar'),
                        onPressed: _puedeEnviar ? _enviar : null,
                        child: _enviando
                            ? SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              )
                            : Text(
                                _segundosRestantes > 0
                                    ? 'Reenviar en ${_segundosRestantes}s'
                                    : 'Enviar enlace de recuperación',
                              ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Campo de email — mismo criterio visual que `_CampoLogin`/`_CampoRegistro`/`_CampoEmail` de las
/// otras páginas de auth, sin duplicar esas clases privadas.
class _CampoRecuperacion extends StatelessWidget {
  const _CampoRecuperacion({required this.controller, this.errorText, this.onSubmitted});

  final TextEditingController controller;
  final String? errorText;
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
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: onSubmitted,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(hintText: 'lucia.silva@correo.com', errorText: errorText),
        ),
      ],
    );
  }
}
