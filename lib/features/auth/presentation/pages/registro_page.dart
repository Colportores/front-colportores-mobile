import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../providers/sesion_notifier.dart';
import 'recuperacion_password_page.dart';
import 'verificacion_email_page.dart';

/// Pantalla de registro de cuenta (HU-AUTH-001), diseño "Login Colportor" (registro 1a/1b).
///
/// Un solo paso: sin barra de progreso ni código de equipo (unirse a una campaña es otra HU).
/// Sin lógica de negocio propia: valida por [Failure] que devuelve [SesionNotifier.registrar] y
/// muestra los mensajes por campo o un banner general, igual que [LoginPage]. Todo lo visual sale
/// de `Theme.of(context)`.
///
/// Si el registro queda pendiente de verificar el email (HU-AUTH-002), reemplaza esta pantalla por
/// [VerificacionEmailPage] (con el email y la contraseña recién tipeados) en vez de volver al
/// login — esa pantalla es la que ahora ofrece esperar, reenviar o revisar el enlace.
class RegistroPage extends ConsumerStatefulWidget {
  const RegistroPage({super.key, this.mostrarApple});

  /// Fuerza mostrar/ocultar "Apple" — mismo mecanismo que [LoginPage.mostrarApple].
  final bool? mostrarApple;

  @override
  ConsumerState<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends ConsumerState<RegistroPage> {
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _cedula = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  late final TapGestureRecognizer _terminosRecognizer;

  Map<String, String> _erroresCampo = const {};
  String? _errorGeneral;
  bool _enviando = false;
  bool _aceptaTerminos = false;
  bool _aceptaTradeOffE2E = false;

  /// `true` cuando el error general es "email ya registrado" (HU-AUTH-001): habilita los accesos
  /// directos a login y a recuperar contraseña que exige el criterio de aceptación.
  bool _emailYaRegistrado = false;

  @override
  void initState() {
    super.initState();
    _terminosRecognizer = TapGestureRecognizer()..onTap = _proximamente;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _apellido.dispose();
    _cedula.dispose();
    _email.dispose();
    _password.dispose();
    _terminosRecognizer.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _erroresCampo = const {};
      _errorGeneral = null;
      _emailYaRegistrado = false;
    });

    final email = _email.text;
    final password = _password.text;

    final resultado = await ref
        .read(sesionProvider.notifier)
        .registrar(
          nombre: _nombre.text,
          apellido: _apellido.text,
          cedula: _cedula.text,
          email: email,
          password: password,
          aceptaTerminos: _aceptaTerminos,
          aceptaTradeOffE2E: _aceptaTradeOffE2E,
        );

    if (!mounted) return;

    resultado.fold(
      (failure) {
        setState(() {
          _enviando = false;
          switch (failure) {
            case FailureValidacion(:final campos):
              _erroresCampo = campos;
            case FailureSinConexion():
              // Mensaje propio del registro (HU-AUTH-001, "Error - sin conectividad"): no el
              // genérico de FailureSinConexion, que también usa el login. Se descarta la
              // contraseña tipeada "por seguridad" (el criterio de aceptación lo pide
              // explícitamente); el resto del formulario se conserva.
              _errorGeneral = 'Necesitás conexión para registrarte por primera vez';
              _password.clear();
            case FailureEmailYaRegistrado(:final mensaje):
              _errorGeneral = mensaje;
              _emailYaRegistrado = true;
            case Failure(:final mensaje):
              _errorGeneral = mensaje;
          }
        });
      },
      (r) {
        if (r.requiereVerificacion) {
          // r.email es el normalizado por el use case (trim + minúsculas), no lo que haya
          // tecleado el usuario.
          unawaited(
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => VerificacionEmailPage(email: r.email, password: password),
              ),
            ),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cuenta creada')));
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }

  /// Con Supabase, OAuth registra e inicia sesión en un solo paso: mismo flujo que en login.
  Future<void> _registrarConGoogle() async {
    setState(() {
      _enviando = true;
      _erroresCampo = const {};
      _errorGeneral = null;
    });

    final failure = await ref.read(sesionProvider.notifier).iniciarSesionConGoogle();

    if (!mounted) return;

    if (failure == null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    setState(() {
      _enviando = false;
      _errorGeneral = failure.mensaje;
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
    final errorTerminos = _erroresCampo['aceptaTerminos'];
    final errorTradeOffE2E = _erroresCampo['aceptaTradeOffE2E'];

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
                      Row(
                        children: [
                          IconButton(
                            key: const Key('registro_atras'),
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
                        'DATOS PERSONALES',
                        style: theme.textTheme.labelSmall?.copyWith(color: colores.oro),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Creá tu cuenta',
                        style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _CampoRegistro(
                              fieldKey: const Key('registro_nombre'),
                              etiqueta: 'NOMBRE',
                              textoAyuda: 'Lucía',
                              controller: _nombre,
                              autofillHints: const [AutofillHints.givenName],
                              textInputAction: TextInputAction.next,
                              errorText: _erroresCampo['nombre'],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _CampoRegistro(
                              fieldKey: const Key('registro_apellido'),
                              etiqueta: 'APELLIDO',
                              textoAyuda: 'Silva',
                              controller: _apellido,
                              autofillHints: const [AutofillHints.familyName],
                              textInputAction: TextInputAction.next,
                              errorText: _erroresCampo['apellido'],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _CampoRegistro(
                        fieldKey: const Key('registro_cedula'),
                        etiqueta: 'CÉDULA',
                        textoAyuda: '4.812.309-2',
                        controller: _cedula,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        errorText: _erroresCampo['cedula'],
                      ),
                      const SizedBox(height: 14),
                      _CampoRegistro(
                        fieldKey: const Key('registro_email'),
                        etiqueta: 'CORREO',
                        textoAyuda: 'lucia.silva@correo.com',
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        errorText: _erroresCampo['email'],
                      ),
                      const SizedBox(height: 14),
                      _CampoRegistro(
                        fieldKey: const Key('registro_password'),
                        etiqueta: 'CONTRASEÑA',
                        textoAyuda: 'Mínimo 8 caracteres',
                        controller: _password,
                        esContrasena: true,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _enviando ? null : _enviar(),
                        errorText: _erroresCampo['password'],
                        textoAyudaInferior: 'Usá al menos una mayúscula y un número.',
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              key: const Key('registro_terminos'),
                              value: _aceptaTerminos,
                              onChanged: (valor) =>
                                  setState(() => _aceptaTerminos = valor ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: theme.colorScheme.onSurface,
                                ),
                                children: [
                                  const TextSpan(text: 'Acepto los '),
                                  TextSpan(
                                    text: 'términos de uso',
                                    recognizer: _terminosRecognizer,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                      color: theme.colorScheme.secondary,
                                    ),
                                  ),
                                  const TextSpan(
                                    text:
                                        ' y el tratamiento de los datos de clientes según la '
                                        'política de la asociación.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (errorTerminos != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 32),
                          child: Text(
                            errorTerminos,
                            key: const Key('registro_terminos_error'),
                            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 12),
                      // Trade-off E2E (R-AU05, HU-AUTH-001, issue #85): mismos componentes que la
                      // casilla de términos de arriba, sin diseño nuevo (decisión de Cristian,
                      // 23/09). Sin link tappeable: es una única oración, no hay documento aparte.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              key: const Key('registro_trade_off'),
                              value: _aceptaTradeOffE2E,
                              onChanged: (valor) =>
                                  setState(() => _aceptaTradeOffE2E = valor ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Entiendo que mi contraseña protege la copia de seguridad de mis '
                              'datos: si la olvido y pierdo el teléfono, los datos de mis '
                              'clientes no se pueden recuperar.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12.5,
                                height: 1.45,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (errorTradeOffE2E != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 32),
                          child: Text(
                            errorTradeOffE2E,
                            key: const Key('registro_trade_off_error'),
                            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                          ),
                        ),
                      if (_errorGeneral != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorGeneral!,
                          key: const Key('registro_error_general'),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        if (_emailYaRegistrado)
                          Wrap(
                            spacing: 4,
                            children: [
                              TextButton(
                                key: const Key('registro_email_duplicado_ir_a_login'),
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Iniciar sesión'),
                              ),
                              TextButton(
                                key: const Key('registro_email_duplicado_ir_a_recuperar'),
                                onPressed: () => Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const RecuperacionPasswordPage(),
                                  ),
                                ),
                                child: const Text('Recuperar contraseña'),
                              ),
                            ],
                          ),
                      ],
                      const SizedBox(height: 4),
                      FilledButton(
                        key: const Key('registro_continuar'),
                        onPressed: _enviando ? null : _enviar,
                        child: _enviando
                            ? SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              )
                            : const Text('Continuar'),
                      ),
                      const SizedBox(height: 28),
                      const _DivisorTexto(texto: 'O REGISTRATE CON'),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _BotonProveedor(
                              etiqueta: 'Google',
                              glifo: 'G',
                              colorGlifo: colores.googleAzul,
                              onPressed: _enviando ? null : _registrarConGoogle,
                            ),
                          ),
                          if (mostrarApple) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: _BotonProveedor(
                                etiqueta: 'Apple',
                                glifo: 'A',
                                fondoNegro: esOscuro,
                                onPressed: () {
                                  // TODO: alta de OAuth con Apple — todavía sin HU asignada.
                                  _proximamente();
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                      const Spacer(),
                      const SizedBox(height: 24),
                      Center(
                        child: TextButton(
                          key: const Key('registro_ir_a_login'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            '¿Ya tenés cuenta? Entrar',
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

/// Campo de formulario: label fijo arriba + input del tema. Igual estructura que `_CampoLogin`
/// en `login_page.dart`, más un texto de ayuda opcional debajo (usado por CONTRASEÑA).
class _CampoRegistro extends StatefulWidget {
  const _CampoRegistro({
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
    this.textoAyudaInferior,
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

  /// Hint debajo del input (p.ej. la regla de contraseña). Se oculta si hay [errorText]: el
  /// propio `InputDecoration` prioriza el error sobre el helper.
  final String? textoAyudaInferior;

  @override
  State<_CampoRegistro> createState() => _CampoRegistroState();
}

class _CampoRegistroState extends State<_CampoRegistro> {
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
            helperText: widget.textoAyudaInferior,
            helperStyle: TextStyle(color: colores.gris, fontSize: 11),
            helperMaxLines: 2,
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

/// Línea divisoria con texto centrado, p.ej. "O REGISTRATE CON". Igual que en `login_page.dart`.
class _DivisorTexto extends StatelessWidget {
  const _DivisorTexto({required this.texto});

  final String texto;

  /// Padding horizontal del texto (12 a cada lado) — también entra en la cuenta de ancho.
  static const _paddingHorizontal = 24.0;

  /// Línea visible mínima de cada `Divider`, aun con el texto más largo posible.
  static const _anchoMinimoDivisor = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final estilo = theme.textTheme.bodySmall?.copyWith(
      letterSpacing: 1.1,
      color: colores.placeholder,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Mide el ancho real que pide el texto (con el tema y el `textScaler` actuales) en vez
        // de adivinar una proporción de `flex` fija: un `flex` chico lo truncaba a escala normal
        // (revisión de #116) y sin ningún límite desbordaba con `textScaler` alto (issue #108).
        // Midiendo, el texto ocupa exactamente lo que necesita —y los `Divider` el resto— hasta
        // el mínimo de `_anchoMinimoDivisor`; `TextOverflow.ellipsis` es el resguardo final si ni
        // así entra.
        final medidor = TextPainter(
          text: TextSpan(text: texto, style: estilo),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();

        final espacioParaTexto =
            constraints.maxWidth - _paddingHorizontal - _anchoMinimoDivisor * 2;
        final anchoMaximoTexto = espacioParaTexto > 0 ? espacioParaTexto : 0.0;
        final anchoTexto = medidor.width > anchoMaximoTexto ? anchoMaximoTexto : medidor.width;

        return Row(
          children: [
            Expanded(child: Divider(color: colores.borde)),
            SizedBox(
              width: anchoTexto + _paddingHorizontal,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo),
              ),
            ),
            Expanded(child: Divider(color: colores.borde)),
          ],
        );
      },
    );
  }
}

/// Botón "con" un proveedor (Google/Apple). Igual que en `login_page.dart`.
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
