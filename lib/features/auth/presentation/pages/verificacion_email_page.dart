import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/usecases/bloqueo_reenvio_verificacion_use_cases.dart';
import '../providers/auth_providers.dart';
import '../providers/enlace_verificacion_usado_providers.dart';
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

  /// El enlace abierto ya se había usado: la cuenta ya está verificada (HU-AUTH-002, «Error -
  /// token ya usado»). Sin salida automática (decisión de Cristian, 02/10; WCAG 2.2.1): la
  /// pantalla se queda hasta que la colportora toca «Ir a mi inicio» (con sesión) o «Ir al login».
  yaVerificado,

  /// El enlace ya no sirve y no hay forma de saber si se usó o venció (HU-AUTH-002, «"Vencido" vs
  /// "ya usado"», caso 3): ofrece **Ir al login** y **Reenviar**.
  enlaceInutil,
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
  /// (no se persiste). Habilita "Ya verifiqué mi email"; `null` cuando se llegó por el deep link
  /// de error, sin ese contexto.
  final String? password;

  final EstadoVerificacionEmail estadoInicial;

  /// Reloj de la cuenta regresiva del reenvío; se inyecta solo en tests.
  final DateTime Function() ahora;

  @override
  ConsumerState<VerificacionEmailPage> createState() => _VerificacionEmailPageState();
}

class _VerificacionEmailPageState extends ConsumerState<VerificacionEmailPage>
    with WidgetsBindingObserver {
  /// Regla de negocio HU-AUTH-002: "máximo 1 reenvío cada 60 segundos". El tope por hora lo hace
  /// cumplir Supabase; cuando rechaza por límite, el botón de **esa dirección** queda bloqueado una
  /// hora fija ([bloqueoReenvioVerificacion], decisión de Cristian 29/09) y el candado se guarda en
  /// el teléfono: sobrevive a salir de la pantalla y a reiniciar la app (decisión de Cristian,
  /// 30/09, #249).
  static const Duration _cooldown = Duration(seconds: 60);

  static const String _textoLimite = 'Demasiados intentos. Probá nuevamente en una hora.';

  late final TextEditingController _emailController;
  late EstadoVerificacionEmail _estado;
  Timer? _timer;
  Timer? _timerBloqueo;
  bool _saliendo = false;
  late final VerificacionEnEsperaNotifier _enEspera;
  DatosDeEsperaVerificacion? _datosEnEspera;
  int _segundosRestantes = 0;

  /// Los candados por límite de reenvíos que siguen vigentes: correo normalizado
  /// ([correoParaBloqueo]) → instante en que vencen. Salen del teléfono al abrir la pantalla.
  Map<String, DateTime> _bloqueos = const {};

  /// `true` mientras se leen del teléfono los candados guardados: un reenvío pedido en ese instante
  /// espera a [_lecturaBloqueos] para no saltearse un candado vigente.
  bool _leyendoBloqueos = true;
  late final Future<void> _lecturaBloqueos;

  /// La dirección que ve la persona: la conocida o, si hay que escribirla, la que va en el campo.
  String get _correoVisible => _emailConocido ? widget.email : _emailController.text;

  bool _estaBloqueado(String correo) {
    final hasta = _bloqueos[correoParaBloqueo(correo)];
    return hasta != null && widget.ahora().isBefore(hasta);
  }

  /// El reenvío a la dirección que se ve está bloqueado. Otra dirección no lo está.
  bool get _bloqueado => _estaBloqueado(_correoVisible);

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
    _lecturaBloqueos = _leerBloqueosGuardados();
    _enEspera = ref.read(verificacionEnEsperaProvider.notifier);
    final password = widget.password;
    if (_estado == EstadoVerificacionEmail.pendiente && _emailConocido && password != null) {
      // Se avisa después del primer frame: modificar un provider mientras el árbol se construye
      // no está permitido. Solo en memoria, mientras esta pantalla vive.
      final datos = DatosDeEsperaVerificacion(email: widget.email, password: password);
      _datosEnEspera = datos;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enEspera.abrir(datos);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final datos = _datosEnEspera;
    if (datos != null) scheduleMicrotask(() => _enEspera.cerrar(datos));
    _timer?.cancel();
    _timerBloqueo?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  /// Lee del teléfono los candados vigentes (los de cualquier dirección) y los retoma.
  Future<void> _leerBloqueosGuardados() async {
    final consultar = ref.read(consultarBloqueosReenvioVerificacionUseCaseProvider);
    var vigentes = const <String, DateTime>{};
    try {
      vigentes = (await consultar(
        ConsultarBloqueosReenvioVerificacionParams(ahora: widget.ahora()),
      )).fold((_) => const <String, DateTime>{}, (vigentes) => vigentes);
    } on Object {
      // El candado es una comodidad de la pantalla: sin poder leerlo, sigue sin candados (el
      // servidor tiene la última palabra).
    } finally {
      _leyendoBloqueos = false;
    }
    if (!mounted || vigentes.isEmpty) return;
    setState(() {
      _bloqueos = {...vigentes, ..._bloqueos};
      _programarDesbloqueo();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _bloqueos.isNotEmpty) {
      setState(_programarDesbloqueo);
    }
    final vence = _venceCooldown;
    if (state != AppLifecycleState.resumed || vence == null || _segundosRestantes <= 0) return;
    final restanteMs = vence.difference(widget.ahora()).inMilliseconds;
    setState(() {
      _segundosRestantes = (restanteMs / 1000).ceil().clamp(0, _cooldown.inSeconds);
      if (_segundosRestantes <= 0) _terminarCooldown();
    });
  }

  /// Descarta los candados que ya vencieron y agenda el repintado para cuando venza el próximo
  /// (de cualquier dirección: la persona puede cambiar la que escribió).
  void _programarDesbloqueo() {
    _timerBloqueo?.cancel();
    final ahora = widget.ahora();
    _bloqueos = {
      for (final MapEntry(key: correo, value: vence) in _bloqueos.entries)
        if (vence.isAfter(ahora)) correo: vence,
    };
    if (_bloqueos.isEmpty) return;
    final proximo = _bloqueos.values.reduce((a, b) => a.isBefore(b) ? a : b);
    _timerBloqueo = Timer(proximo.difference(ahora), () {
      if (!mounted) return;
      setState(_programarDesbloqueo);
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
    if (_reenviando || _verificando || _segundosRestantes > 0 || _bloqueado) return;
    final email = _emailConocido ? widget.email : _emailController.text.trim();
    final sesion = ref.read(sesionProvider.notifier);
    final registrarBloqueo = ref.read(registrarBloqueoReenvioVerificacionUseCaseProvider);
    setState(() {
      _reenviando = true;
      _errorEmail = null;
      _errorGeneral = null;
      _mensajeReenvio = null;
    });

    // Un reenvío pedido mientras se leen los candados guardados espera a saber si esta dirección
    // está bloqueada.
    if (_leyendoBloqueos) {
      await _lecturaBloqueos;
      if (!mounted) return;
      if (_estaBloqueado(email)) {
        setState(() => _reenviando = false);
        return;
      }
    }

    final failure = await sesion.reenviarVerificacion(email);

    // El candado se guarda aunque la pantalla ya no esté (el servidor ya rechazó a esta dirección)
    // y antes de soltar el «ocupado»: al volver a entrar, ya está guardado.
    DateTime? venceBloqueo;
    if (failure case FailureServidor(status: 429)) {
      final cuando = widget.ahora();
      venceBloqueo = (await registrarBloqueo(
        RegistrarBloqueoReenvioVerificacionParams(correo: email, ahora: cuando),
      )).fold((_) => cuando.add(bloqueoReenvioVerificacion), (vence) => vence);
    }

    if (!mounted) return;
    setState(() {
      _reenviando = false;
      switch (failure) {
        case null:
          _mensajeReenvio = 'Te reenviamos el correo. Puede tardar unos minutos.';
          _iniciarCooldown();
        case FailureValidacion(:final campos):
          _errorEmail = campos['email'];
        case FailureServidor(status: 429):
          // Bloquea la dirección a la que se pidió el reenvío, no la que se vea cuando conteste.
          _bloqueos = {..._bloqueos, correoParaBloqueo(email): venceBloqueo!};
          _programarDesbloqueo();
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

  /// Sale de esta pantalla hacia la raíz: el login, o la app si hay sesión. Idempotente: dos
  /// toques seguidos en el botón salen una sola vez.
  void _irAlLogin() {
    if (_saliendo || !mounted) return;
    _saliendo = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

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
    final yaVerificado = _estado == EstadoVerificacionEmail.yaVerificado;
    final expirado = _estado == EstadoVerificacionEmail.expirado;
    final inutil = _estado == EstadoVerificacionEmail.enlaceInutil;
    // «Verificado» y «ya verificado» son pantallas de cierre: sin correo, sin avisos ni reenvío.
    final cierre = verificado || yaVerificado;
    final conAvisoDeReenvio = _mensajeReenvio != null;
    // Con sesión, al salir la app entra a Inicio (casos 1 y 2 de HU-AUTH-002): el botón lo dice así.
    final haySesion = ref.watch(sesionProvider).value != null;

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
                        if (cierre || expirado || inutil)
                          ExcludeSemantics(
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: esquema.primary, width: 1.5),
                              ),
                              child: Icon(
                                cierre
                                    ? Icons.check
                                    : (inutil ? Icons.link_off : Icons.hourglass_bottom),
                                color: esquema.primary,
                              ),
                            ),
                          ),
                        if (!cierre)
                          Text(
                            'VERIFICACIÓN DE EMAIL',
                            style: theme.textTheme.labelSmall?.copyWith(color: esquema.primary),
                          ),
                        if (_titulo() case final titulo?)
                          Semantics(
                            header: true,
                            child: Text(
                              titulo,
                              key: const Key('verificacion_email_titulo'),
                              style: theme.textTheme.headlineMedium,
                            ),
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
                        if (!cierre && _emailConocido)
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
                        if (!cierre && !_emailConocido)
                          _CampoEmail(
                            controller: _emailController,
                            errorText: _errorEmail,
                            // Repinta siempre: el candado depende de la dirección que se escribe.
                            onChanged: (_) => setState(() => _errorEmail = null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        if (!cierre)
                          ..._acciones(context)
                        else if (yaVerificado)
                          _irAlLoginBoton(haySesion: haySesion)
                        else
                          _continuarBoton(),
                      ],
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

  Widget _irAlLoginBoton({required bool haySesion}) => FilledButton(
    key: const Key('verificacion_email_ir_login'),
    onPressed: _irAlLogin,
    child: Text(haySesion ? 'Ir a mi inicio' : 'Ir al login'),
  );

  /// Los avisos (arriba de las acciones) y las acciones de la espera, según el diseño.
  List<Widget> _acciones(BuildContext context) {
    final theme = Theme.of(context);
    final inutil = _estado == EstadoVerificacionEmail.enlaceInutil;
    // El botón dice «de verificación» cuando el enlace no sirvió (vencido o inútil).
    final expirado = _estado == EstadoVerificacionEmail.expirado || inutil;
    final conCuentaRegresiva = _segundosRestantes > 0;
    final etiquetaReenviar = conCuentaRegresiva
        ? 'Reenviar en ${_segundosRestantes}s'
        : (expirado ? 'Reenviar email de verificación' : 'Reenviar email');
    final ocupado = _reenviando || _verificando;
    final bloqueado = _bloqueado;
    final reenviar = ocupado || conCuentaRegresiva || bloqueado ? null : _reenviar;

    return [
      if (_mensajeReenvio case final mensaje?)
        _AvisoVerificacion(
          key: const Key('verificacion_email_mensaje_reenvio'),
          texto: mensaje,
          icono: Icons.check_circle_outline,
        ),
      if (bloqueado)
        const _AvisoVerificacion(
          key: Key('verificacion_email_limite'),
          texto: _textoLimite,
          icono: Icons.lock_outline,
          esError: true,
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
      if (bloqueado)
        OutlinedButton.icon(
          key: const Key('verificacion_email_reenviar'),
          onPressed: null,
          icon: const Icon(Icons.lock_outline),
          label: Text(etiquetaReenviar),
        )
      else if (expirado && widget.password == null)
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
        onPressed: inutil ? _irAlLogin : _volverAlLogin,
        child: Text(
          inutil ? 'Ir al login' : 'Volver al login',
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

  /// `null` cuando el texto de la HU ya es todo el mensaje y no hay un título aparte.
  String? _titulo() => switch (_estado) {
    EstadoVerificacionEmail.pendiente => 'Verificá tu cuenta',
    EstadoVerificacionEmail.verificado => 'Email verificado',
    EstadoVerificacionEmail.expirado => 'El enlace expiró',
    EstadoVerificacionEmail.yaVerificado => 'Tu email ya está verificado',
    EstadoVerificacionEmail.enlaceInutil => null,
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
    // 12-A05 (decisión de Cristian, 02/10): sin salida automática, el mismo texto con o sin sesión.
    EstadoVerificacionEmail.yaVerificado => 'Ya podés entrar a tu inicio.',
    EstadoVerificacionEmail.enlaceInutil =>
      'Este enlace ya no sirve: puede que ya lo hayas usado o que haya vencido. Si ya '
          'verificaste tu email, entrá con tu contraseña. Si no, pedí un enlace nuevo.',
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
