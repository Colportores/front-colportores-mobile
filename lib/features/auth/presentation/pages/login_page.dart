import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../domain/entities/motivo_expiracion.dart';
import '../providers/auth_providers.dart';
import '../providers/aviso_sesion_notifier.dart';
import '../providers/reingreso_sesion_notifier.dart';
import '../providers/sesion_notifier.dart';
import '../widgets/banner_error_con_accion.dart';
import '../widgets/borde_discontinuo.dart';
import '../widgets/texto_error_anunciado.dart';
import 'recuperacion_password_page.dart';
import 'registro_page.dart';

/// Pantalla de inicio de sesión (HU-AUTH-003), diseño "Login Colportor".
///
/// Sin lógica de negocio: valida por [Failure] que devuelve el notifier y muestra los mensajes
/// por campo o un banner general. Todo lo visual sale de `Theme.of(context)` — el tema
/// (`temaClaro`, ver `core/theme/`) decide colores, tipografía y forma.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

/// Tope del correo (RFC 5321). Sin contador a la vista. La contraseña del login no lleva tope: la
/// cuenta ya existe y el servidor la compara tal cual.
const _largoMaximoCorreo = 254;

/// El teléfono dice que no hay señal. Mientras la plataforma no contesta (o si falla) no se sabe:
/// no se afirma nada.
bool _sinSenal(AsyncValue<TipoConexion> conexion) => switch (conexion) {
  AsyncData(:final value) => value == TipoConexion.sinConexion,
  _ => false,
};

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  Map<String, String> _erroresCampo = const {};
  String? _errorGeneral;
  bool _enviando = false;

  /// `true` cuando el error general es el fallo intermitente del backend (5xx): el banner lleva
  /// «Reintentar», como el del registro (HU-AUTH-001, «Edge - fallo intermitente del backend»).
  bool _errorEsReintentable = false;

  /// Marca el aviso general para llevarlo a la vista cuando aparece.
  final _claveErrorGeneral = GlobalKey();

  /// Marca el aviso de sesión de arriba, para volver a mostrarlo cuando el intento de entrar lo
  /// cambia (17-A02) y la pantalla estaba bajada.
  final _claveAvisoSesion = GlobalKey();

  /// `true` si el último intento de entrar no llegó al servidor por falta de conexión. Con la
  /// sesión vencida eso es 17-A02, aunque el teléfono diga que hay señal (un Wi-Fi sin salida): lo
  /// que decide es la respuesta real. Lo baja cualquier otra respuesta del servidor y un cambio de
  /// conexión; la validación de los campos no lo toca porque no sale a la red.
  bool _ultimoIntentoSinConexion = false;

  /// `true` si en este teléfono ya hubo una cuenta (había un correo guardado): entonces no es el
  /// «primer login en este dispositivo» y el aviso sin conexión de «Entrar» no debe decirlo.
  bool _habiaCorreoGuardado = false;

  @override
  void initState() {
    super.initState();
    // Sesión vencida (vista 17): el correo de la cuenta que estaba adentro ya viene puesto.
    final correo = ref.read(reingresoSesionProvider)?.email;
    if (correo != null) {
      _email.text = correo;
    } else {
      unawaited(_precargarUltimoCorreo());
    }
  }

  /// Sin «Sesión vencida» de por medio, el correo de la última cuenta puede seguir guardado: la app
  /// cerró la sesión por su cuenta (el cambio de contraseña con el enlace de recuperación) y no se
  /// borra a propósito. Si la colportora ya empezó a escribir otro, no se lo pisa (pero se recuerda
  /// que había uno, para el texto sin conexión de «Entrar»).
  Future<void> _precargarUltimoCorreo() async {
    final guardado = await ref.read(ultimoCorreoRepositoryProvider).leer();
    if (!mounted || guardado == null) return;
    _habiaCorreoGuardado = true;
    if (_email.text.isEmpty) _email.text = guardado;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// La sesión terminó por 30 días sin uso (no porque el servidor la revocó): es el caso en que
  /// «Necesitás conexión para renovarla» dice la verdad (HU-AUTH-003, «JWT expirado y sin conexión»).
  bool get _vencidaPorInactividad =>
      ref.read(reingresoSesionProvider)?.motivo == MotivoExpiracion.inactividad;

  Future<void> _enviar() async {
    if (_enviando) return; // Doble toque: «Entrar» y «Reintentar» comparten este guardián.
    setState(() {
      _enviando = true;
      _erroresCampo = const {};
      _errorGeneral = null;
      _errorEsReintentable = false;
    });

    final failure = await ref
        .read(sesionProvider.notifier)
        .iniciarSesion(email: _email.text, password: _password.text);

    if (!mounted) return;
    final vencida = _vencidaPorInactividad;
    // El aviso de 17-A02 ya estaba a la vista antes de este intento: el `liveRegion` no lo vuelve a
    // anunciar si no cambia, así que se anuncia a mano (un anuncio por intento, WCAG 4.1.3).
    final avisoYaVisible =
        vencida && (_sinSenal(ref.read(conexionProvider)) || _ultimoIntentoSinConexion);
    setState(() {
      _enviando = false;
      if (failure is! FailureValidacion) {
        _ultimoIntentoSinConexion = failure is FailureSinConexion && vencida;
      }
      switch (failure) {
        case null:
          break;
        case FailureValidacion(:final campos):
          _erroresCampo = campos;
        case FailureSinConexion() when vencida:
          // 17-A02: lo dice el aviso de arriba («Tu sesión expiró. Necesitás conexión para
          // renovarla.»); repetirlo debajo del formulario sería decir lo mismo dos veces.
          break;
        case FailureServidor(:final status) when status != null && status >= 500:
          _errorGeneral = BannerErrorConAccion.servicioNoDisponible;
          _errorEsReintentable = true;
        case Failure():
          _errorGeneral = mensajePara(failure, accion: _accionSinConexion);
      }
    });
    // Con el texto grande y «Entrar» al borde de la pantalla el aviso (y «Reintentar») nacía
    // debajo del borde: como en el registro, baja hasta él una vez dibujado.
    if (_errorGeneral != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _llevarAVista(_claveErrorGeneral);
      });
    } else if (failure is FailureSinConexion && vencida) {
      // El aviso de 17-A02 está arriba de todo: con el botón al borde de la pantalla (texto
      // grande) o el teclado abierto quedaba fuera de la vista y el toque parecía no hacer nada.
      // El campo con foco le gana al desplazamiento con su cursor: se suelta antes.
      FocusScope.of(context).unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _llevarAVista(_claveAvisoSesion, alineacion: 0);
      });
      if (avisoYaVisible) {
        unawaited(
          SemanticsService.sendAnnouncement(
            View.of(context),
            const FailureSesionVencidaSinConexion().mensaje,
            Directionality.of(context),
          ),
        );
      }
    }
  }

  void _llevarAVista(GlobalKey clave, {double alineacion = 0.2}) {
    final contexto = clave.currentContext;
    if (contexto == null || !contexto.mounted) return;
    unawaited(
      Scrollable.ensureVisible(
        contexto,
        alignment: alineacion,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }

  /// HU-AUTH-003, "Error - primer login sin conectividad" (#94). Solo dice «primera vez» si de verdad
  /// lo es: con una cuenta ya conocida en el teléfono (sesión cerrada, vencida o revocada, o un
  /// correo guardado) un texto que miente se ajusta solo en ese caso.
  String get _accionSinConexion => ref.read(reingresoSesionProvider) != null || _habiaCorreoGuardado
      ? 'iniciar sesión.'
      : 'iniciar sesión por primera vez en este dispositivo.';

  /// «¿Olvidaste tu clave?» / «Recuperar acceso»: con el correo ya escrito en el formulario, la
  /// pantalla de recuperación lo trae cargado.
  void _abrirRecuperacion() {
    final email = _email.text.trim();
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RecuperacionPasswordPage(emailInicial: email.isEmpty ? null : email),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    const paddingHorizontal = 30.0;
    final reingreso = ref.watch(reingresoSesionProvider);
    // 17-A02: la sesión venció por inactividad y no hay con qué renovarla. Es un estado, no un
    // aviso que se pueda cerrar: dura mientras no haya señal.
    final sinSenal = ref.watch(conexionProvider.select(_sinSenal));
    final vencidaSinConexion =
        reingreso?.motivo == MotivoExpiracion.inactividad &&
        (sinSenal || _ultimoIntentoSinConexion);
    final Failure? aviso = vencidaSinConexion
        ? const FailureSesionVencidaSinConexion()
        : ref.watch(avisoSesionProvider);
    // Volvió la señal: lo que dijo un intento anterior ya no vale.
    ref.listen(conexionProvider, (anterior, actual) {
      if (!_ultimoIntentoSinConexion) return;
      if (actual case AsyncData(:final value) when value != TipoConexion.sinConexion) {
        setState(() => _ultimoIntentoSinConexion = false);
      }
    });

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
                      // 17-A01/A03: el aviso va arriba de todo y se puede cerrar (17-A04). El de
                      // 17-A02 no: dura mientras no haya señal.
                      if (aviso != null) ...[
                        _AvisoSesion(
                          key: _claveAvisoSesion,
                          aviso: aviso,
                          alCerrar: vencidaSinConexion
                              ? null
                              : ref.read(avisoSesionProvider.notifier).descartar,
                        ),
                        const SizedBox(height: 20),
                      ],
                      const _MarcaColportaje(),
                      SizedBox(height: reingreso == null ? 58 : 20),
                      if (reingreso == null) ...[
                        Text(
                          'COLPORTAJE · URUGUAY',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Iniciá tu jornada', style: theme.textTheme.headlineMedium),
                      ] else ...[
                        Text(
                          reingreso.nombre == null
                              ? 'Hola de nuevo'
                              : 'Hola de nuevo, ${reingreso.nombre}',
                          key: const Key('login_saludo'),
                          style: theme.textTheme.headlineMedium,
                        ),
                        // Solo cuando se cerró por inactividad: lo que dice es cierto porque la
                        // sesión vencida nunca toca la base local (HU-AUTH-007). 17-A02 no lo
                        // dibuja: el aviso de arriba ya ocupa ese lugar con lo que hay que hacer.
                        if (reingreso.motivo == MotivoExpiracion.inactividad &&
                            !vencidaSinConexion) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Tus visitas y cobranzas siguen guardadas en el teléfono.',
                            key: const Key('login_datos_guardados'),
                            style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
                          ),
                        ],
                      ],
                      const SizedBox(height: 34),
                      // Con `key`: el aviso, «guardadas» y la ayuda de 17-A02 entran y salen de esta
                      // `Column`; sin ella los campos se recrean y se pierde foco y «Mostrar».
                      _CampoLogin(
                        key: const ValueKey('login_campo_email'),
                        fieldKey: const Key('login_email'),
                        etiqueta: 'CORREO',
                        textoAyuda: 'lucia.silva@correo.com',
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        maxLength: _largoMaximoCorreo,
                        errorText: _erroresCampo['email'],
                      ),
                      const SizedBox(height: 12),
                      _CampoLogin(
                        key: const ValueKey('login_campo_password'),
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
                        SizedBox(key: _claveErrorGeneral, height: 12),
                        if (_errorEsReintentable)
                          BannerErrorConAccion(
                            mensaje: _errorGeneral!,
                            mensajeKey: const Key('login_error_general'),
                            textoAccion: 'Reintentar',
                            onAccion: _enviando ? null : _enviar,
                          )
                        else
                          TextoErrorAnunciado(
                            _errorGeneral!,
                            textoKey: const Key('login_error_general'),
                          ),
                      ],
                      const SizedBox(height: 16),
                      // 17-A02 no dibuja el enlace: recuperar la contraseña también pide red.
                      if (!vencidaSinConexion) ...[
                        _EnlaceRecuperacion(
                          texto: reingreso == null ? '¿Olvidaste tu clave?' : 'Recuperar acceso',
                          alRecuperar: _abrirRecuperacion,
                        ),
                        const SizedBox(height: 16),
                      ],
                      FilledButton(
                        key: const Key('login_enviar'),
                        onPressed: _enviando ? null : _enviar,
                        child: _enviando
                            // El spinner reemplaza al texto: sin esto el botón queda sin nombre.
                            ? Semantics(
                                label: 'Entrando…',
                                child: SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              )
                            : const Text('Entrar'),
                      ),
                      if (vencidaSinConexion) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Vas a poder entrar cuando vuelva la señal.',
                          key: const Key('login_vencida_sin_conexion_ayuda'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
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
                                MaterialPageRoute<void>(builder: (_) => const RegistroPage()),
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

/// Por qué la app volvió al login sin que el usuario cerrara sesión (HU-AUTH-007, 17-A01 y A03). No
/// es un error del formulario: se anuncia al lector de pantalla al aparecer, se puede cerrar con la
/// ✕ y, de todos modos, el login sigue mostrando el saludo.
///
/// 17-A02 (vencida y sin conexión, #248) es otro caso de [aviso] ([FailureSesionVencidaSinConexion]):
/// sin ✕ ([alCerrar] `null`, porque dura mientras no haya señal), con borde de trazos y el círculo
/// lleno con una ✕.
class _AvisoSesion extends StatelessWidget {
  const _AvisoSesion({super.key, required this.aviso, required this.alCerrar});

  final Failure aviso;
  final VoidCallback? alCerrar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final sinConexion = aviso is FailureSesionVencidaSinConexion;
    // El canvas pinta el aviso de 17-A02 en el gris de texto (#2A3A52), no en el azul de enlaces.
    final tinta = sinConexion ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.secondary;
    final icono = switch (aviso) {
      FailureSesionRevocada() => Icons.priority_high,
      FailureSesionVencidaSinConexion() => Icons.close,
      _ => Icons.timer_outlined,
    };
    final caja = Container(
      key: const Key('login_aviso_sesion'),
      padding: sinConexion
          ? const EdgeInsets.all(14)
          : const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: sinConexion ? null : Border.all(color: colores.bordeInput, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sinConexion ? tinta : null,
                border: sinConexion ? null : Border.all(color: tinta, width: 1.5),
              ),
              child: Icon(
                icono,
                size: 13,
                color: sinConexion ? theme.colorScheme.onPrimary : tinta,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(aviso.mensaje, style: theme.textTheme.bodyMedium)),
          if (alCerrar != null)
            IconButton(
              key: const Key('login_aviso_sesion_cerrar'),
              tooltip: 'Cerrar aviso',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: alCerrar,
              icon: Icon(Icons.close, size: 18, color: tinta),
            ),
        ],
      ),
    );
    return Semantics(
      liveRegion: true,
      container: true,
      child: sinConexion
          ? BordeDiscontinuo(
              key: const Key('login_aviso_sesion_borde_discontinuo'),
              color: colores.gris,
              radio: 14,
              child: caja,
            )
          : caja,
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
    super.key,
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
    this.maxLength,
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

  /// Tope de caracteres visibles, sin contador a la vista; `null` es sin tope.
  final int? maxLength;

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
          maxLength: widget.maxLength,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: widget.textoAyuda,
            errorText: widget.errorText,
            counterText: '',
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

/// El enlace de recuperación, a la derecha, debajo de la contraseña (HU-AUTH-004). El login no
/// ofrece «Mantener sesión»: la sesión es siempre la de HU-AUTH-007, 30 días desde el último uso, y
/// se cierra con «Cerrar sesión» (decisión de Cristian, 07/10, #303).
class _EnlaceRecuperacion extends StatelessWidget {
  const _EnlaceRecuperacion({required this.texto, required this.alRecuperar});

  final String texto;
  final VoidCallback alRecuperar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: TextButton(
        key: const Key('login_olvidaste_clave'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(48, 48),
        ),
        onPressed: alRecuperar,
        child: Text(
          texto,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
