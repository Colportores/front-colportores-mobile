import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/reenvios_guardados.dart';
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
    this.envioDelAlta,
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

  /// Cuándo salió el correo del alta, si la pantalla se abre justo después del registro: la espera
  /// de 60 s para reenviar cuenta desde ahí, así que el botón arranca como en 12-A02,
  /// «Reenviar en Ns», sin el aviso «Te reenviamos el correo» (no hubo reenvío), y pasados los 60 s
  /// queda como en 12-A01 (decisión del orquestador, 08/10, #325). `null` cuando se llega por otro
  /// camino: la espera, si hay, sale de lo guardado en el teléfono.
  final DateTime? envioDelAlta;

  /// Reloj de la cuenta regresiva y del candado del reenvío; se inyecta solo en tests.
  final DateTime Function() ahora;

  @override
  ConsumerState<VerificacionEmailPage> createState() => _VerificacionEmailPageState();
}

class _VerificacionEmailPageState extends ConsumerState<VerificacionEmailPage>
    with WidgetsBindingObserver {
  /// Reglas de negocio de HU-AUTH-002: «máximo 1 reenvío cada 60 segundos»
  /// ([esperaReenvioVerificacion]), que se cuenta desde el último correo que salió a **esa
  /// dirección** —el del alta o un reenvío— y se guarda en el teléfono (decisión del orquestador,
  /// 08/10, #325); y, cuando Supabase rechaza por límite, el reenvío a esa dirección queda bloqueado
  /// una hora fija ([bloqueoReenvioVerificacion], decisión de Cristian, 29/09), también guardada: ni
  /// la espera ni el candado se pierden al salir de la pantalla o reiniciar la app (30/09, #249).
  static const Duration _cooldown = esperaReenvioVerificacion;

  /// Lo más que un reenvío espera a que se lean los reenvíos guardados: pasado ese tope se pide igual
  /// (el servidor tiene la última palabra) en vez de dejar el botón en «ocupado» sin fin (como #318).
  static const Duration _topeLectura = Duration(seconds: 3);

  late final TextEditingController _emailController;
  late EstadoVerificacionEmail _estado;

  /// El tic de 1 s de «Reenviar en Ns».
  Timer? _timer;

  /// El próximo cambio del texto o del candado: que venza uno o que pase el minuto que se muestra.
  Timer? _timerBloqueo;
  bool _saliendo = false;
  late final VerificacionEnEsperaNotifier _enEspera;
  DatosDeEsperaVerificacion? _datosEnEspera;

  /// Segundos que faltan para poder reenviar a la dirección que se ve; 0 si ya se puede.
  int _segundosRestantes = 0;

  /// Lo que sigue vigente de los reenvíos, por dirección: los candados y las esperas de 60 s. Sale
  /// del teléfono al abrir la pantalla y se completa con lo que pasa mientras está abierta.
  ReenviosGuardados _reenvios = ReenviosGuardados.vacio;

  /// `true` mientras se leen del teléfono los reenvíos guardados: un reenvío pedido en ese instante
  /// espera a [_lecturaReenvios] (hasta [_topeLectura]) para no saltearse un candado vigente.
  bool _leyendoReenvios = true;
  late final Future<void> _lecturaReenvios;

  /// La dirección para la que ya se anunció (al lector de pantalla) el aviso del límite: se anuncia
  /// una sola vez al aparecer, no cada vez que el texto cambia de minuto.
  String? _limiteAnunciadoA;
  bool _anuncioProgramado = false;

  /// La dirección a la que se reenvió con éxito: «Te reenviamos el correo» es de esa dirección.
  String? _correoReenviado;

  /// La dirección que ve la persona: la conocida o, si hay que escribirla, la que va en el campo.
  String get _correoVisible => _emailConocido ? widget.email : _emailController.text;

  bool _estaBloqueado(String correo) {
    final hasta = _reenvios.bloqueos[correoParaBloqueo(correo)];
    return hasta != null && widget.ahora().isBefore(hasta);
  }

  /// El reenvío a la dirección que se ve está bloqueado. Otra dirección no lo está.
  bool get _bloqueado => _estaBloqueado(_correoVisible);

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
    final delAlta = widget.envioDelAlta;
    if (delAlta != null && _emailConocido) {
      // El correo del alta es el primer envío: la espera de 60 s cuenta desde que salió.
      _reenvios = _reenvios.conEspera(correoParaBloqueo(widget.email), delAlta.add(_cooldown));
      _sincronizarEspera();
    }
    _lecturaReenvios = _leerReenviosGuardados();
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

  /// Lo que el teléfono recuerda de los reenvíos, a la hora de ahora. Nunca lanza: sin poder leerlo,
  /// es como si no hubiera nada (el candado es una comodidad de la pantalla; el servidor tiene la
  /// última palabra).
  Future<ReenviosGuardados> _consultarReenvios() async {
    final consultar = ref.read(consultarReenviosVerificacionUseCaseProvider);
    try {
      return (await consultar(
        ConsultarReenviosVerificacionParams(ahora: widget.ahora()),
      )).fold((_) => ReenviosGuardados.vacio, (guardados) => guardados);
    } on Object {
      return ReenviosGuardados.vacio;
    }
  }

  /// Suma a lo que ya se sabe lo guardado en el teléfono (lo de esta pantalla, que es más nuevo,
  /// manda) y retoma la espera y el candado de la dirección que se ve.
  void _adoptar(ReenviosGuardados guardados) {
    _reenvios = ReenviosGuardados(
      bloqueos: {...guardados.bloqueos, ..._reenvios.bloqueos},
      esperas: {...guardados.esperas, ..._reenvios.esperas},
    );
    _sincronizarEspera();
    _programarCambioDelLimite();
  }

  /// Lee del teléfono los reenvíos vigentes (los de cualquier dirección) y los retoma.
  Future<void> _leerReenviosGuardados() async {
    ReenviosGuardados guardados;
    try {
      guardados = await _consultarReenvios();
    } finally {
      _leyendoReenvios = false;
    }
    if (!mounted || guardados.estaVacio) return;
    setState(() => _adoptar(guardados));
  }

  /// Al volver de segundo plano los `Timer` estuvieron pausados y la hora pudo cambiar: la espera
  /// se recalcula desde la hora real y los vencimientos se recortan a su tope (una hora hacia atrás
  /// no estira un candado; #325). El recorte queda también en el teléfono.
  Future<void> _alVolver() async {
    setState(() {
      _sincronizarEspera();
      _programarCambioDelLimite();
    });
    final guardados = await _consultarReenvios();
    if (!mounted || guardados.estaVacio) return;
    setState(() => _adoptar(guardados));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_alVolver());
  }

  /// Retoma «Reenviar en Ns» para la dirección que se ve, desde su vencimiento guardado y la hora
  /// de ahora: la espera es de cada dirección, así que cambiar la que se escribe cambia (o quita) la
  /// cuenta regresiva. Sin espera vigente, la deja en cero.
  void _sincronizarEspera() {
    final ahora = widget.ahora();
    _reenvios = _reenvios.vigentesA(ahora);
    final vence = _reenvios.esperas[correoParaBloqueo(_correoVisible)];
    final restanteMs = vence == null ? 0 : vence.difference(ahora).inMilliseconds;
    final segundos = (restanteMs / 1000).ceil().clamp(0, _cooldown.inSeconds);
    if (segundos <= 0) {
      _terminarCooldown();
      return;
    }
    _segundosRestantes = segundos;
    if (_timer?.isActive != true) {
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
  }

  void _terminarCooldown() {
    _timer?.cancel();
    _timer = null;
    _segundosRestantes = 0;
    _mensajeReenvio = null;
  }

  /// Descarta los candados que ya vencieron y agenda el repintado para el próximo cambio: que venza
  /// alguno (de cualquier dirección: la persona puede cambiar la que escribió) o que pase el minuto
  /// que dice el aviso del límite de la dirección que se ve.
  void _programarCambioDelLimite() {
    _timerBloqueo?.cancel();
    _timerBloqueo = null;
    final ahora = widget.ahora();
    _reenvios = _reenvios.vigentesA(ahora);
    Duration? proximo;
    void considerar(Duration duracion) {
      if (proximo == null || duracion < proximo!) proximo = duracion;
    }

    for (final vence in _reenvios.bloqueos.values) {
      considerar(vence.difference(ahora));
    }
    if (_reenvios.bloqueos[correoParaBloqueo(_correoVisible)] case final vence?) {
      final restanteMs = vence.difference(ahora).inMilliseconds;
      final minutosPorVenir = (restanteMs / Duration.millisecondsPerMinute).ceil() - 1;
      considerar(
        Duration(milliseconds: restanteMs - minutosPorVenir * Duration.millisecondsPerMinute),
      );
    }
    final cuando = proximo;
    if (cuando == null) return;
    _timerBloqueo = Timer(cuando, _alCambiarElLimite);
  }

  /// Pasó un minuto del aviso o venció un candado: se repinta con la hora de ahora (a lo sumo una vez
  /// por minuto) y se agenda el próximo cambio.
  void _alCambiarElLimite() {
    if (!mounted) return;
    setState(_programarCambioDelLimite);
  }

  /// Dice cuánto falta del candado de la dirección que se ve, redondeado hacia arriba a minutos:
  /// «una hora» al rechazo (decisión de Cristian, 29/09), después lo que queda (decisión del
  /// orquestador, 08/10, #325; el canvas 12-A06 dibuja «en 4 minutos»).
  String _textoLimite() {
    final vence = _reenvios.bloqueos[correoParaBloqueo(_correoVisible)];
    final minutos = vence == null
        ? bloqueoReenvioVerificacion.inMinutes
        : (vence.difference(widget.ahora()).inMilliseconds / Duration.millisecondsPerMinute)
              .ceil()
              .clamp(1, bloqueoReenvioVerificacion.inMinutes);
    final cuanto = switch (minutos) {
      >= 60 => 'una hora',
      1 => '1 minuto',
      _ => '$minutos minutos',
    };
    return 'Demasiados intentos. Probá nuevamente en $cuanto.';
  }

  /// Anuncia el aviso del límite al lector de pantalla **una sola vez**, cuando aparece (al
  /// rechazo, al entrar a la pantalla con el candado, o al escribir una dirección bloqueada), y no
  /// cada minuto que el texto se actualiza (como en #297). Por eso el aviso no es un `liveRegion`.
  void _revisarAnuncioDelLimite() {
    final correo = correoParaBloqueo(_correoVisible);
    if (!_bloqueado) {
      _limiteAnunciadoA = null;
      return;
    }
    if (_limiteAnunciadoA == correo || _anuncioProgramado) return;
    _anuncioProgramado = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anuncioProgramado = false;
      if (!mounted || !_bloqueado) return;
      final actual = correoParaBloqueo(_correoVisible);
      if (_limiteAnunciadoA == actual) return;
      _limiteAnunciadoA = actual;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          _textoLimite(),
          Directionality.of(context),
        ),
      );
    });
  }

  /// Se escribe otra dirección: el candado, la espera y el aviso de éxito son de cada dirección.
  void _alCambiarCorreo(String _) {
    setState(() {
      _errorEmail = null;
      if (correoParaBloqueo(_correoVisible) != _correoReenviado) _mensajeReenvio = null;
      _sincronizarEspera();
      _programarCambioDelLimite();
    });
  }

  Future<void> _reenviar() async {
    if (_reenviando || _verificando || _segundosRestantes > 0 || _bloqueado) return;
    final email = _emailConocido ? widget.email : _emailController.text.trim();
    final sesion = ref.read(sesionProvider.notifier);
    final registrarBloqueo = ref.read(registrarBloqueoReenvioVerificacionUseCaseProvider);
    final registrarEnvio = ref.read(registrarEnvioVerificacionUseCaseProvider);
    setState(() {
      _reenviando = true;
      _errorEmail = null;
      _errorGeneral = null;
      _mensajeReenvio = null;
    });

    // Un reenvío pedido mientras se leen los reenvíos guardados espera a saber si esta dirección
    // está bloqueada o esperando, pero no más que [_topeLectura].
    if (_leyendoReenvios) {
      await _lecturaReenvios.timeout(_topeLectura, onTimeout: () {});
      if (!mounted) return;
      if (_estaBloqueado(email) || _segundosRestantes > 0) {
        setState(() => _reenviando = false);
        return;
      }
    }

    final failure = await sesion.reenviarVerificacion(email);

    // Lo que dejó el servidor se guarda aunque la pantalla ya no esté (el correo salió, o rechazó a
    // esta dirección) y antes de soltar el «ocupado»: al volver a entrar, ya está guardado.
    final cuando = widget.ahora();
    DateTime? venceBloqueo;
    DateTime? venceEspera;
    if (failure case FailureServidor(status: 429)) {
      venceBloqueo = (await registrarBloqueo(
        RegistrarBloqueoReenvioVerificacionParams(correo: email, ahora: cuando),
      )).fold((_) => cuando.add(bloqueoReenvioVerificacion), (vence) => vence);
    } else if (failure == null) {
      venceEspera = (await registrarEnvio(
        RegistrarEnvioVerificacionParams(correo: email, ahora: cuando),
      )).fold((_) => cuando.add(_cooldown), (vence) => vence);
    }

    if (!mounted) return;
    setState(() {
      _reenviando = false;
      switch (failure) {
        case null:
          // La espera es de la dirección a la que salió el correo, no de la que se vea cuando
          // conteste; «Te reenviamos el correo» solo se dice si sigue siendo la que se ve.
          _reenvios = _reenvios.conEspera(correoParaBloqueo(email), venceEspera!);
          if (correoParaBloqueo(_correoVisible) == correoParaBloqueo(email)) {
            _correoReenviado = correoParaBloqueo(email);
            _mensajeReenvio = 'Te reenviamos el correo. Puede tardar unos minutos.';
          }
          _sincronizarEspera();
        case FailureValidacion(:final campos):
          _errorEmail = campos['email'];
        case FailureServidor(status: 429):
          // Bloquea la dirección a la que se pidió el reenvío, no la que se vea cuando conteste.
          _reenvios = _reenvios.conBloqueo(correoParaBloqueo(email), venceBloqueo!);
          _programarCambioDelLimite();
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
    _revisarAnuncioDelLimite();

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
                            // Repinta siempre: el candado y la espera dependen de la dirección que se
                            // escribe.
                            onChanged: _alCambiarCorreo,
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
    final bloqueado = _bloqueado;
    // Con el candado puesto el botón dice lo mismo que en 12-A06, sin cuenta regresiva: la espera
    // de 60 s es mucho menos que la hora que falta.
    final conCuentaRegresiva = _segundosRestantes > 0 && !bloqueado;
    final etiquetaReenviar = conCuentaRegresiva
        ? 'Reenviar en ${_segundosRestantes}s'
        : (expirado ? 'Reenviar email de verificación' : 'Reenviar email');
    final ocupado = _reenviando || _verificando;
    final reenviar = ocupado || conCuentaRegresiva || bloqueado ? null : _reenviar;

    return [
      if (_mensajeReenvio case final mensaje?)
        _AvisoVerificacion(
          key: const Key('verificacion_email_mensaje_reenvio'),
          texto: mensaje,
          icono: Icons.check_circle_outline,
        ),
      if (bloqueado)
        _AvisoVerificacion(
          key: const Key('verificacion_email_limite'),
          texto: _textoLimite(),
          // El canvas 12-A06 dibuja «!» (el candado va en el botón).
          icono: Icons.error_outline,
          esError: true,
          // Lo anuncia `_revisarAnuncioDelLimite` una sola vez: el texto cambia cada minuto.
          liveRegion: false,
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
        // Con un reenvío en vuelo no se sale: el resultado (el correo que salió o el candado) se
        // guarda y se muestra en esta pantalla.
        onPressed: _reenviando ? null : (inutil ? _irAlLogin : _volverAlLogin),
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
    this.liveRegion = true,
  });

  final String texto;
  final IconData icono;
  final bool esError;

  /// `false` cuando quien lo muestra lo anuncia aparte (y una sola vez).
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    final color = esError ? esquema.error : esquema.primary;

    return Semantics(
      liveRegion: liveRegion,
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
