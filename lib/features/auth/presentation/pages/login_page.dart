import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../providers/aviso_sesion_notifier.dart';
import '../providers/sesion_notifier.dart';
import 'recuperacion_password_page.dart';
import 'registro_page.dart';

/// Pantalla de inicio de sesión (HU-AUTH-003), diseño "Login Colportor".
///
/// Sin lógica de negocio: valida por [Failure] que devuelve el notifier y muestra los mensajes
/// por campo o un banner general. Todo lo visual sale de `Theme.of(context)` — el tema
/// (`temaClaro`, ver `core/theme/`) decide colores, tipografía y forma.
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

  // Solo estado local: ninguna HU dice qué hace este checkbox (la sesión deslizante de 30 días de
  // HU-AUTH-007 corre siempre). Queda sin efecto hasta que se decida.
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
        case Failure():
          _errorGeneral = mensajePara(failure, accion: _accionSinConexion);
      }
    });
  }

  /// HU-AUTH-003, "Error - primer login sin conectividad" (#94).
  static const _accionSinConexion = 'iniciar sesión por primera vez en este dispositivo.';

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
      _errorGeneral = failure == null ? null : mensajePara(failure, accion: _accionSinConexion);
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
    final mostrarApple = widget.mostrarApple ?? Platform.isIOS;
    const paddingHorizontal = 30.0;
    final aviso = ref.watch(avisoSesionProvider);

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
                      const _MarcaColportaje(),
                      const SizedBox(height: 58),
                      Text(
                        'COLPORTAJE · URUGUAY',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Iniciá tu jornada', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 34),
                      if (aviso != null) ...[
                        _AvisoSesion(texto: aviso.mensaje),
                        const SizedBox(height: 20),
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
                          // Sin achicar: el área de toque tiene que ser de 48x48 (accesibilidad).
                          Checkbox(
                            value: _mantenerSesion,
                            semanticLabel: 'Mantener sesión',
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            onChanged: (valor) => setState(() => _mantenerSesion = valor ?? true),
                          ),
                          Expanded(
                            // La etiqueta ya la lleva el checkbox para el lector de pantalla.
                            child: ExcludeSemantics(
                              child: Text(
                                'Mantener sesión',
                                style: theme.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: TextButton(
                              key: const Key('login_olvidaste_clave'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                minimumSize: const Size(48, 48),
                              ),
                              onPressed: () {
                                unawaited(
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const RecuperacionPasswordPage(),
                                    ),
                                  ),
                                );
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
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
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
                          onPressed: () {
                            unawaited(
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => RegistroPage(mostrarApple: widget.mostrarApple),
                                ),
                              ),
                            );
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

/// Por qué la app volvió al login sin que el usuario cerrara sesión (HU-AUTH-007). No es un error
/// del formulario: se anuncia al lector de pantalla al aparecer y dura hasta volver a entrar.
class _AvisoSesion extends StatelessWidget {
  const _AvisoSesion({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('login_aviso_sesion'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.primary),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(Icons.info_outline, color: theme.colorScheme.primary)),
            const SizedBox(width: 10),
            Expanded(child: Text(texto, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// Marca de Colportaje: cuadrado navy + wordmark.
class _MarcaColportaje extends StatelessWidget {
  const _MarcaColportaje();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
        Flexible(
          child: Text(
            'COLPORTAJE',
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 2.4,
              color: theme.colorScheme.primary,
            ),
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
            // Área de toque mínima de 48 (accesibilidad): en el tema claro el campo queda en 41.
            constraints: const BoxConstraints(minHeight: 48),
            suffixIcon: widget.esContrasena
                ? IconButton(
                    tooltip: _mostrarTexto ? 'Ocultar contraseña' : 'Mostrar contraseña',
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
        // Flexible: con el texto grande (200 %) no entra en una línea y tiene que poder partirse.
        Flexible(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              texto,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(letterSpacing: 1.1, color: colores.gris),
            ),
          ),
        ),
        Expanded(child: Divider(color: colores.borde)),
      ],
    );
  }
}

/// Botón "Continuar con" un proveedor (Google/Apple).
class _BotonProveedor extends StatelessWidget {
  const _BotonProveedor({
    required this.etiqueta,
    required this.glifo,
    required this.onPressed,
    this.colorGlifo,
  });

  final String etiqueta;
  final String glifo;
  final Color? colorGlifo;

  /// `null` deshabilita el botón (mientras hay un ingreso en curso).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            glifo,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: colorGlifo),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(etiqueta, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}
