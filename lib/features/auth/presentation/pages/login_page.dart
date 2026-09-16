import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../providers/sesion_notifier.dart';
import 'registro_page.dart';

/// Pantalla de inicio de sesión (HU-AUTH-003), diseño "Login Colportor".
///
/// Sin lógica de negocio: valida por [Failure] que devuelve el notifier y muestra los mensajes
/// por campo o un banner general. Todo lo visual sale de `Theme.of(context)` — el tema
/// (`temaClaro`/`temaOscuro`, ver `core/theme/`) decide colores, tipografía y forma.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.mostrarApple});

  /// Fuerza mostrar/ocultar "Continuar con Apple". `null` (el default en producción) lo infiere
  /// de la plataforma (`Platform.isIOS`, Apple solo lo exige ahí); en tests se fuerza por acá en
  /// vez de depender de `Platform`.
  final bool? mostrarApple;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  Map<String, String> _erroresCampo = const {};
  String? _errorGeneral;
  bool _enviando = false;

  /// Email con el que se acaba de registrar y todavía tiene que verificar (viene de
  /// [RegistroPendiente]). Muestra el banner informativo hasta que el usuario lo cierra.
  String? _emailPendienteVerificacion;

  // Solo estado local: la sesión deslizante ("mantenerme conectado" de verdad) es HU-AUTH-006,
  // Sprint 4. Por ahora este checkbox no persiste nada.
  bool _mantenerSesion = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _erroresCampo = const {};
      _errorGeneral = null;
    });

    final failure = await ref
        .read(sesionProvider.notifier)
        .iniciarSesion(email: _email.text, password: _password.text);

    if (!mounted) return;
    setState(() {
      _enviando = false;
      switch (failure) {
        case null:
          break;
        case FailureValidacion(:final campos):
          _erroresCampo = campos;
        case Failure(:final mensaje):
          _errorGeneral = mensaje;
      }
    });
  }

  Future<void> _entrarConGoogle() async {
    setState(() {
      _enviando = true;
      _erroresCampo = const {};
      _errorGeneral = null;
    });

    final failure = await ref.read(sesionProvider.notifier).iniciarSesionConGoogle();

    if (!mounted) return;
    setState(() {
      _enviando = false;
      _errorGeneral = failure?.mensaje;
    });
  }

  void _proximamente() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Disponible próximamente')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esOscuro = theme.brightness == Brightness.dark;
    final mostrarApple = widget.mostrarApple ?? Platform.isIOS;
    final paddingHorizontal = esOscuro ? 26.0 : 30.0;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MarcaColportaje(esOscuro: esOscuro),
                      const SizedBox(height: 58),
                      Text(
                        'COLPORTAJE · URUGUAY',
                        style: theme.textTheme.labelSmall?.copyWith(color: colores.oro),
                      ),
                      const SizedBox(height: 8),
                      Text('Iniciá tu jornada', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 34),
                      if (_emailPendienteVerificacion != null) ...[
                        _BannerInformativo(
                          mensaje:
                              'Te enviamos un correo a $_emailPendienteVerificacion. '
                              'Verificá tu cuenta y después tocá Entrar.',
                          onCerrar: () => setState(() => _emailPendienteVerificacion = null),
                        ),
                        const SizedBox(height: 18),
                      ],
                      _CampoLogin(
                        fieldKey: const Key('login_email'),
                        etiqueta: 'CORREO O CÉDULA',
                        textoAyuda: 'lucia.silva@correo.com',
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        errorText: _erroresCampo['email'],
                      ),
                      const SizedBox(height: 12),
                      _CampoLogin(
                        fieldKey: const Key('login_password'),
                        etiqueta: 'CONTRASEÑA',
                        textoAyuda: '••••••••',
                        controller: _password,
                        esContrasena: true,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _enviando ? null : _enviar(),
                        errorText: _erroresCampo['password'],
                      ),
                      if (_errorGeneral != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorGeneral!,
                          key: const Key('login_error_general'),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _mantenerSesion,
                              onChanged: (valor) => setState(() => _mantenerSesion = valor ?? true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mantener sesión',
                              style: theme.textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                // TODO(HU-AUTH-004): recuperación de contraseña.
                                _proximamente();
                              },
                              child: Text(
                                '¿Olvidaste tu clave?',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const Key('login_enviar'),
                        onPressed: _enviando ? null : _enviar,
                        child: _enviando
                            ? SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              )
                            : const Text('Entrar'),
                      ),
                      const SizedBox(height: 28),
                      const _DivisorTexto(texto: 'O CONTINUAR CON'),
                      const SizedBox(height: 18),
                      _BotonProveedor(
                        etiqueta: 'Continuar con Google',
                        glifo: 'G',
                        colorGlifo: colores.googleAzul,
                        onPressed: _enviando ? null : _entrarConGoogle,
                      ),
                      if (mostrarApple) ...[
                        const SizedBox(height: 12),
                        _BotonProveedor(
                          etiqueta: 'Continuar con Apple',
                          glifo: 'A',
                          fondoNegro: esOscuro,
                          onPressed: () {
                            // TODO: alta de OAuth con Apple — todavía sin HU asignada.
                            _proximamente();
                          },
                        ),
                      ],
                      const Spacer(),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: colores.oro, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Podés trabajar sin conexión después de entrar',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: .6),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          key: const Key('login_ir_a_registro'),
                          onPressed: () async {
                            final pendiente = await Navigator.of(context).push<RegistroPendiente>(
                              MaterialPageRoute<RegistroPendiente>(
                                builder: (_) => RegistroPage(mostrarApple: widget.mostrarApple),
                              ),
                            );
                            if (!mounted || pendiente == null) return;
                            setState(() {
                              _email.text = pendiente.email;
                              _password.text = pendiente.password;
                              _emailPendienteVerificacion = pendiente.email;
                            });
                          },
                          child: Text(
                            '¿No tenés cuenta? Registrate',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                      ),
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

/// Aviso no destructivo (verificación de email pendiente, no un error): colores de
/// superficie/primario del tema, nunca `colorScheme.error`.
class _BannerInformativo extends StatelessWidget {
  const _BannerInformativo({required this.mensaje, required this.onCerrar});

  final String mensaje;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;

    return Container(
      key: const Key('login_banner_verificacion'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colores.borde, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              mensaje,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          IconButton(
            onPressed: onCerrar,
            icon: Icon(Icons.close, size: 18, color: theme.colorScheme.primary),
            tooltip: 'Cerrar',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// Marca de Colportaje: logo grande dorado con "C" en oscuro, fila navy+wordmark en claro.
class _MarcaColportaje extends StatelessWidget {
  const _MarcaColportaje({required this.esOscuro});

  final bool esOscuro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (esOscuro) {
      return Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          'C',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimary,
            height: 1,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'COLPORTAJE',
          style: theme.textTheme.labelMedium?.copyWith(
            letterSpacing: 2.4,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

/// Campo de formulario: label fijo arriba (no el label flotante de Material) + input del tema.
class _CampoLogin extends StatefulWidget {
  const _CampoLogin({
    required this.etiqueta,
    required this.textoAyuda,
    required this.controller,
    this.fieldKey,
    this.esContrasena = false,
    this.errorText,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
  });

  final String etiqueta;
  final String textoAyuda;
  final TextEditingController controller;
  final Key? fieldKey;
  final bool esContrasena;
  final String? errorText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_CampoLogin> createState() => _CampoLoginState();
}

class _CampoLoginState extends State<_CampoLogin> {
  bool _mostrarTexto = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.etiqueta, style: theme.textTheme.labelMedium?.copyWith(color: colores.gris)),
        const SizedBox(height: 6),
        TextField(
          key: widget.fieldKey,
          controller: widget.controller,
          obscureText: widget.esContrasena && !_mostrarTexto,
          keyboardType: widget.keyboardType,
          autofillHints: widget.autofillHints,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: widget.textoAyuda,
            errorText: widget.errorText,
            suffixIcon: widget.esContrasena
                ? IconButton(
                    icon: Icon(
                      _mostrarTexto ? Icons.visibility_off : Icons.visibility,
                      color: colores.placeholder,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _mostrarTexto = !_mostrarTexto),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// Línea divisoria con texto centrado, p.ej. "O CONTINUAR CON".
class _DivisorTexto extends StatelessWidget {
  const _DivisorTexto({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;

    return Row(
      children: [
        Expanded(child: Divider(color: colores.borde)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            texto,
            style: theme.textTheme.bodySmall?.copyWith(
              letterSpacing: 1.1,
              color: colores.placeholder,
            ),
          ),
        ),
        Expanded(child: Divider(color: colores.borde)),
      ],
    );
  }
}

/// Botón "Continuar con" un proveedor (Google/Apple). El fondo negro (solo Apple, solo tema
/// oscuro) es la única
/// variante que no sale del `outlinedButtonTheme` general.
class _BotonProveedor extends StatelessWidget {
  const _BotonProveedor({
    required this.etiqueta,
    required this.glifo,
    required this.onPressed,
    this.colorGlifo,
    this.fondoNegro = false,
  });

  final String etiqueta;
  final String glifo;
  final Color? colorGlifo;

  /// `null` deshabilita el botón (mientras hay un ingreso en curso).
  final VoidCallback? onPressed;
  final bool fondoNegro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final estiloBase = theme.outlinedButtonTheme.style ?? const ButtonStyle();

    return OutlinedButton(
      onPressed: onPressed,
      style: fondoNegro
          ? estiloBase.copyWith(
              backgroundColor: WidgetStatePropertyAll(colores.negro),
              foregroundColor: WidgetStatePropertyAll(theme.colorScheme.onSurface),
              side: const WidgetStatePropertyAll(BorderSide.none),
            )
          : estiloBase,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            glifo,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: colorGlifo),
          ),
          const SizedBox(width: 10),
          Text(etiqueta),
        ],
      ),
    );
  }
}
