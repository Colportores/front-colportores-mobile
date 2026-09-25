import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../providers/sesion_notifier.dart';

/// Estado visible de [VerificacionEmailPage] (HU-AUTH-002).
enum EstadoVerificacionEmail {
  /// Recién registrado, esperando que confirme el correo.
  pendiente,

  /// El enlace abierto confirmó el email.
  verificado,

  /// El enlace abierto está vencido o ya fue usado — Supabase no distingue los dos casos (mismo
  /// `error_code` `otp_expired`), así que la app tampoco.
  expirado,
}

/// Pantalla de espera/reenvío de verificación de email (HU-AUTH-002), diseño "Login Colportor"
/// (reusa los mismos componentes/tema que [LoginPage] y `RegistroPage`: no hay diseño propio para
/// esta pantalla — decisión de Cristian).
///
/// Reemplaza al banner que antes vivía dentro del login: ahora se llega acá (a) después de un
/// registro que queda pendiente de verificar ([email] y [password] conocidos, para poder ofrecer
/// "Ya verifiqué mi email" reintentando el login), o (b) desde la raíz de la app cuando el deep
/// link de verificación vuelve con un error y la app puede estar mostrando cualquier otra pantalla
/// en ese momento ([email] vacío: Supabase no lo manda en el error del deep link, así que el
/// campo queda editable para poder reenviar).
class VerificacionEmailPage extends ConsumerStatefulWidget {
  const VerificacionEmailPage({
    super.key,
    this.email = '',
    this.password,
    this.estadoInicial = EstadoVerificacionEmail.pendiente,
  });

  /// Email a verificar. Vacío cuando se llega por un deep link de error sin contexto — ahí el
  /// campo queda editable para que el usuario lo escriba.
  final String email;

  /// Contraseña recién tipeada en el registro, solo en memoria mientras esta pantalla está viva
  /// (no se persiste, igual que el checkbox "mantener sesión" del login). Habilita "Ya verifiqué
  /// mi email"; `null` cuando se llegó por el deep link de error, sin ese contexto.
  final String? password;

  final EstadoVerificacionEmail estadoInicial;

  @override
  ConsumerState<VerificacionEmailPage> createState() => _VerificacionEmailPageState();
}

class _VerificacionEmailPageState extends ConsumerState<VerificacionEmailPage> {
  /// Regla de negocio HU-AUTH-002: "máximo 1 reenvío cada 60 segundos". El tope de "máximo 5 por
  /// hora" no se replica acá — Supabase ya lo hace cumplir (~2 emails/hora en el plan free sin
  /// SMTP propio) y ese rechazo llega traducido como cualquier otro rate limit.
  static const Duration _cooldown = Duration(seconds: 60);

  late final TextEditingController _emailController;
  late EstadoVerificacionEmail _estado;
  Timer? _timer;
  int _segundosRestantes = 0;

  String? _errorEmail;
  String? _errorGeneral;
  String? _mensajeReenvio;
  bool _enviando = false;

  bool get _emailConocido => widget.email.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _estado = widget.estadoInicial;
    _emailController = TextEditingController(text: widget.email);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
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

  Future<void> _reenviar() async {
    final email = _emailConocido ? widget.email : _emailController.text.trim();
    setState(() {
      _enviando = true;
      _errorEmail = null;
      _errorGeneral = null;
      _mensajeReenvio = null;
    });

    final failure = await ref.read(sesionProvider.notifier).reenviarVerificacion(email);

    if (!mounted) return;
    setState(() {
      _enviando = false;
      switch (failure) {
        case null:
          _mensajeReenvio = 'Te reenviamos el correo a $email.';
          _iniciarCooldown();
        case FailureValidacion(:final campos):
          _errorEmail = campos['email'];
        case Failure(:final mensaje):
          _errorGeneral = mensaje;
      }
    });
  }

  Future<void> _yaVerifique() async {
    final password = widget.password;
    if (password == null) return;

    setState(() {
      _enviando = true;
      _errorGeneral = null;
    });

    final failure = await ref
        .read(sesionProvider.notifier)
        .iniciarSesion(email: widget.email, password: password);

    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (failure == null) {
        _estado = EstadoVerificacionEmail.verificado;
      } else {
        _errorGeneral = failure.mensaje;
      }
    });
  }

  void _continuar() => Navigator.of(context).popUntil((route) => route.isFirst);

  void _volverAlLogin() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                      const SizedBox(height: 40),
                      Text(
                        'VERIFICACIÓN DE EMAIL',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _titulo(),
                        key: const Key('verificacion_email_titulo'),
                        style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _mensaje(),
                        key: const Key('verificacion_email_mensaje'),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      if (_estado != EstadoVerificacionEmail.verificado) ...[
                        if (!_emailConocido) ...[
                          _CampoEmail(controller: _emailController, errorText: _errorEmail),
                          const SizedBox(height: 16),
                        ],
                        if (_mensajeReenvio != null) ...[
                          Text(
                            _mensajeReenvio!,
                            key: const Key('verificacion_email_mensaje_reenvio'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_errorGeneral != null) ...[
                          Text(
                            _errorGeneral!,
                            key: const Key('verificacion_email_error_general'),
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          const SizedBox(height: 12),
                        ],
                        OutlinedButton(
                          key: const Key('verificacion_email_reenviar'),
                          onPressed: (_enviando || _segundosRestantes > 0) ? null : _reenviar,
                          child: Text(
                            _segundosRestantes > 0
                                ? 'Reenviar en ${_segundosRestantes}s'
                                : 'Reenviar email de verificación',
                          ),
                        ),
                        if (_estado == EstadoVerificacionEmail.pendiente &&
                            widget.password != null) ...[
                          const SizedBox(height: 12),
                          FilledButton(
                            key: const Key('verificacion_email_ya_verifique'),
                            onPressed: _enviando ? null : _yaVerifique,
                            child: _enviando
                                ? SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  )
                                : const Text('Ya verifiqué mi email'),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            key: const Key('verificacion_email_volver_login'),
                            onPressed: _volverAlLogin,
                            child: Text(
                              'Volver al login',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        FilledButton(
                          key: const Key('verificacion_email_continuar'),
                          onPressed: _continuar,
                          child: const Text('Continuar'),
                        ),
                      ],
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

  String _titulo() => switch (_estado) {
    EstadoVerificacionEmail.pendiente => 'Verificá tu cuenta',
    EstadoVerificacionEmail.verificado => 'Email verificado',
    EstadoVerificacionEmail.expirado => 'El enlace no es válido',
  };

  String _mensaje() => switch (_estado) {
    EstadoVerificacionEmail.pendiente =>
      _emailConocido
          ? 'Te enviamos un correo a ${widget.email}. Abrí el enlace para verificar tu cuenta. '
                'Si no lo encontrás, revisá la carpeta de spam.'
          : 'Todavía no verificaste tu cuenta. Revisá tu correo (y la carpeta de spam) o pedí uno '
                'nuevo.',
    EstadoVerificacionEmail.verificado =>
      'Email verificado. Esperá la asignación de tu coordinador.',
    EstadoVerificacionEmail.expirado =>
      'El enlace de verificación venció o ya se usó. Pedí uno nuevo para volver a intentarlo.',
  };
}

/// Campo de email editable — mismo criterio visual que `_CampoLogin`/`_CampoRegistro`, pero sin
/// duplicar esas clases privadas de las otras páginas (conservan su propio archivo).
class _CampoEmail extends StatelessWidget {
  const _CampoEmail({required this.controller, this.errorText});

  final TextEditingController controller;
  final String? errorText;

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
          key: const Key('verificacion_email_campo'),
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: 'lucia.silva@correo.com',
            errorText: errorText,
            // Área de toque mínima de 48 (accesibilidad, #115): en el tema claro el campo queda
            // en 41.
            constraints: const BoxConstraints(minHeight: 48),
          ),
        ),
      ],
    );
  }
}
