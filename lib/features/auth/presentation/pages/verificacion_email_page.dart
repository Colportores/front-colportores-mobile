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

/// Pantalla de espera/reenvío de verificación de email (HU-AUTH-002), vista 12 del diseño (#221):
/// el correo destacado en una tarjeta, las acciones al pie y los avisos encima de ellas.
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
    @visibleForTesting this.ahora = DateTime.now,
  });

  /// Email a verificar. Vacío cuando se llega por un deep link de error sin contexto — ahí el
  /// campo queda editable para que el usuario lo escriba.
  final String email;

  /// Contraseña recién tipeada en el registro, solo en memoria mientras esta pantalla está viva
  /// (no se persiste, igual que el checkbox "mantener sesión" del login). Habilita "Ya verifiqué
  /// mi email"; `null` cuando se llegó por el deep link de error, sin ese contexto.
  final String? password;

  final EstadoVerificacionEmail estadoInicial;

  /// Reloj de la cuenta regresiva del reenvío; se inyecta solo en tests.
  final DateTime Function() ahora;

  @override
  ConsumerState<VerificacionEmailPage> createState() => _VerificacionEmailPageState();
}

class _VerificacionEmailPageState extends ConsumerState<VerificacionEmailPage>
    with WidgetsBindingObserver {
  /// Regla de negocio HU-AUTH-002: "máximo 1 reenvío cada 60 segundos". El tope de "máximo 5 por
  /// hora" no se replica acá — Supabase ya lo hace cumplir (~2 emails/hora en el plan free sin
  /// SMTP propio) y ese rechazo llega traducido como cualquier otro rate limit.
  static const Duration _cooldown = Duration(seconds: 60);

  late final TextEditingController _emailController;
  late EstadoVerificacionEmail _estado;
  Timer? _timer;
  int _segundosRestantes = 0;

  /// Instante en que vence la espera del reenvío: con la app en segundo plano el `Timer` se
  /// pausa, así que al volver se recalcula desde la hora real.
  DateTime? _venceCooldown;

  String? _errorEmail;
  String? _errorGeneral;
  String? _mensajeReenvio;
  bool _reenviando = false;
  bool _verificando = false;

  bool get _emailConocido => widget.email.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _estado = widget.estadoInicial;
    _emailController = TextEditingController(text: widget.email);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final vence = _venceCooldown;
    if (state != AppLifecycleState.resumed || vence == null || _segundosRestantes <= 0) return;
    final restanteMs = vence.difference(widget.ahora()).inMilliseconds;
    setState(() {
      _segundosRestantes = (restanteMs / 1000).ceil().clamp(0, _cooldown.inSeconds);
      if (_segundosRestantes <= 0) _terminarCooldown();
    });
  }

  void _terminarCooldown() {
    _timer?.cancel();
    _mensajeReenvio = null;
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
        if (_segundosRestantes <= 0) _terminarCooldown();
      });
    });
  }

  Future<void> _reenviar() async {
    if (_reenviando || _verificando || _segundosRestantes > 0) return;
    final email = _emailConocido ? widget.email : _emailController.text.trim();
    setState(() {
      _reenviando = true;
      _errorEmail = null;
      _errorGeneral = null;
      _mensajeReenvio = null;
    });

    final failure = await ref.read(sesionProvider.notifier).reenviarVerificacion(email);

    if (!mounted) return;
    setState(() {
      _reenviando = false;
      switch (failure) {
        case null:
          _mensajeReenvio = 'Te reenviamos el correo. Puede tardar unos minutos.';
          _iniciarCooldown();
        case FailureValidacion(:final campos):
          _errorEmail = campos['email'];
        case final Failure f:
          _errorGeneral = _textoDeError(f, 'reenviar el email', 'No pudimos reenviar el email.');
      }
    });
  }

  Future<void> _yaVerifique() async {
    final password = widget.password;
    if (password == null || _verificando || _reenviando) return;

    setState(() {
      _verificando = true;
      _errorGeneral = null;
      _mensajeReenvio = null;
    });

    final failure = await ref
        .read(sesionProvider.notifier)
        .iniciarSesion(email: widget.email, password: password);

    if (!mounted) return;
    setState(() {
      _verificando = false;
      if (failure == null) {
        _estado = EstadoVerificacionEmail.verificado;
      } else {
        _errorGeneral = _textoDeError(
          failure,
          'verificar tu cuenta',
          'No pudimos verificar tu cuenta.',
        );
      }
    });
  }

  void _continuar() => Navigator.of(context).popUntil((route) => route.isFirst);

  void _volverAlLogin() => Navigator.of(context).pop();

  /// Todo aviso dice qué pasa y qué hacer (criterio de Cristian): sin conexión, un error del
  /// servidor sin mensaje propio o uno inesperado llevan texto de la pantalla; el resto (rate
  /// limit, credenciales, validación) ya trae el suyo.
  static String _textoDeError(Failure failure, String accion, String noPudimos) {
    return switch (failure) {
      FailureSinConexion() => 'Necesitás conexión para $accion. Conectate y probá de nuevo.',
      FailureInesperado() => '$noPudimos Probá de nuevo en unos minutos.',
      FailureServidor(:final mensaje) when mensaje == const FailureServidor().mensaje =>
        '$noPudimos Probá de nuevo en unos minutos.',
      _ => failure.mensaje,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    final colores = theme.extension<ColoresColportaje>()!;
    final verificado = _estado == EstadoVerificacionEmail.verificado;
    final expirado = _estado == EstadoVerificacionEmail.expirado;
    final conAvisoDeReenvio = _mensajeReenvio != null;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 44).clamp(0, double.infinity),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 12,
                      children: [
                        const SizedBox(height: 28),
                        if (verificado || expirado)
                          ExcludeSemantics(
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: esquema.primary, width: 1.5),
                              ),
                              child: Icon(
                                verificado ? Icons.check : Icons.hourglass_bottom,
                                color: esquema.primary,
                              ),
                            ),
                          ),
                        if (!verificado)
                          Text(
                            'VERIFICACIÓN DE EMAIL',
                            style: theme.textTheme.labelSmall?.copyWith(color: esquema.primary),
                          ),
                        Text(
                          _titulo(),
                          key: const Key('verificacion_email_titulo'),
                          style: theme.textTheme.headlineMedium,
                        ),
                        if (!(conAvisoDeReenvio && _emailConocido))
                          Text(
                            _mensaje(),
                            key: const Key('verificacion_email_mensaje'),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: esquema.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        if (!verificado && _emailConocido)
                          Container(
                            key: const Key('verificacion_email_tarjeta'),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: esquema.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colores.borde),
                            ),
                            child: Row(
                              spacing: 12,
                              children: [
                                ExcludeSemantics(
                                  child: Icon(Icons.alternate_email, color: esquema.primary),
                                ),
                                Expanded(
                                  child: Text(
                                    widget.email,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_estado == EstadoVerificacionEmail.pendiente &&
                            _emailConocido &&
                            !conAvisoDeReenvio) ...[
                          Text(
                            'Abrí el enlace para verificar tu cuenta.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: esquema.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            'Si no lo encontrás, revisá la carpeta de spam.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
                          ),
                        ],
                        if (!verificado && !_emailConocido)
                          _CampoEmail(
                            controller: _emailController,
                            errorText: _errorEmail,
                            onChanged: (_) {
                              if (_errorEmail != null) setState(() => _errorEmail = null);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [if (!verificado) ..._acciones(context) else _continuarBoton()],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _continuarBoton() => FilledButton(
    key: const Key('verificacion_email_continuar'),
    onPressed: _continuar,
    child: const Text('Continuar'),
  );

  /// Los avisos (arriba de las acciones) y las acciones de la espera, según el diseño.
  List<Widget> _acciones(BuildContext context) {
    final theme = Theme.of(context);
    final expirado = _estado == EstadoVerificacionEmail.expirado;
    final conCuentaRegresiva = _segundosRestantes > 0;
    final etiquetaReenviar = conCuentaRegresiva
        ? 'Reenviar en ${_segundosRestantes}s'
        : (expirado ? 'Reenviar email de verificación' : 'Reenviar email');
    final ocupado = _reenviando || _verificando;
    final reenviar = ocupado || conCuentaRegresiva ? null : _reenviar;

    return [
      if (_mensajeReenvio case final mensaje?)
        _AvisoVerificacion(
          key: const Key('verificacion_email_mensaje_reenvio'),
          texto: mensaje,
          icono: Icons.check_circle_outline,
        ),
      if (_errorGeneral case final error?)
        _AvisoVerificacion(
          key: const Key('verificacion_email_error_general'),
          texto: error,
          icono: Icons.error_outline,
          esError: true,
        ),
      if (_estado == EstadoVerificacionEmail.pendiente && widget.password != null)
        FilledButton(
          key: const Key('verificacion_email_ya_verifique'),
          onPressed: ocupado ? null : _yaVerifique,
          style: _estiloYaVerifique(context),
          child: _verificando
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : const Text('Ya verifiqué mi email'),
        ),
      if (expirado && widget.password == null)
        FilledButton(
          key: const Key('verificacion_email_reenviar'),
          onPressed: reenviar,
          child: Text(etiquetaReenviar),
        )
      else
        OutlinedButton(
          key: const Key('verificacion_email_reenviar'),
          onPressed: reenviar,
          child: Text(etiquetaReenviar),
        ),
      if (conCuentaRegresiva)
        ExcludeSemantics(
          child: LinearProgressIndicator(
            key: const Key('verificacion_email_progreso'),
            value: _segundosRestantes / _cooldown.inSeconds,
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      TextButton(
        key: const Key('verificacion_email_volver_login'),
        onPressed: _volverAlLogin,
        child: Text(
          'Volver al login',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary),
        ),
      ),
    ];
  }

  /// Con texto grande la etiqueta pasa a dos líneas y los extremos de píldora la recortan: ahí el
  /// radio baja y el relleno lateral sube.
  ButtonStyle? _estiloYaVerifique(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(14) <= 20) return null;
    return FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  String _titulo() => switch (_estado) {
    EstadoVerificacionEmail.pendiente => 'Verificá tu cuenta',
    EstadoVerificacionEmail.verificado => 'Email verificado',
    EstadoVerificacionEmail.expirado => 'El enlace expiró',
  };

  String _mensaje() => switch (_estado) {
    EstadoVerificacionEmail.pendiente =>
      _emailConocido
          ? 'Te enviamos un correo a'
          : 'Todavía no verificaste tu cuenta. Revisá tu correo (y la carpeta de spam) o pedí uno '
                'nuevo.',
    EstadoVerificacionEmail.verificado =>
      'Email verificado. Esperá la asignación de tu coordinador.',
    EstadoVerificacionEmail.expirado =>
      _emailConocido
          ? 'Pedí uno nuevo y abrilo desde este teléfono. Lo mandamos a ${widget.email}.'
          : 'Pedí uno nuevo y abrilo desde este teléfono.',
  };
}

/// Aviso encima de las acciones: qué pasó (y qué hacer) sin cambiar de pantalla.
class _AvisoVerificacion extends StatelessWidget {
  const _AvisoVerificacion({
    super.key,
    required this.texto,
    required this.icono,
    this.esError = false,
  });

  final String texto;
  final IconData icono;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    final color = esError ? esquema.error : esquema.primary;

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: esquema.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            ExcludeSemantics(child: Icon(icono, color: color)),
            Expanded(child: Text(texto, style: theme.textTheme.bodyLarge)),
          ],
        ),
      ),
    );
  }
}

/// Campo de email editable — mismo criterio visual que `_CampoLogin`/`_CampoRegistro`, pero sin
/// duplicar esas clases privadas de las otras páginas (conservan su propio archivo).
class _CampoEmail extends StatelessWidget {
  const _CampoEmail({required this.controller, this.errorText, this.onChanged});

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onChanged;

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
          onChanged: onChanged,
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
