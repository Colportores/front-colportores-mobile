import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/conectividad/conectividad_providers.dart';
import 'core/error/failure.dart';
import 'core/theme/tema_colportaje.dart';
import 'features/auth/domain/entities/destino_enlace_verificacion_usado.dart';
import 'features/auth/domain/entities/enlace_recuperacion.dart';
import 'features/auth/domain/entities/estado_cuenta.dart';
import 'features/auth/domain/entities/sesion.dart';
import 'features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'features/auth/presentation/pages/cuenta_asignada_page.dart';
import 'features/auth/presentation/pages/esperando_asignacion_page.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/preparacion_db_local_page.dart';
import 'features/auth/presentation/pages/verificacion_email_page.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'features/auth/presentation/providers/aviso_sesion_notifier.dart';
import 'features/auth/presentation/providers/enlace_verificacion_usado_providers.dart';
import 'features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'features/auth/presentation/providers/preparacion_db_local_notifier.dart';
import 'features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'features/auth/presentation/providers/sesion_notifier.dart';
import 'features/configuracion/presentation/providers/nombre_cuenta_provider.dart';
import 'features/inicio/presentation/pages/inicio_page.dart';

/// Navegador raíz de la app — hace falta como referencia estable para poder navegar desde fuera
/// del árbol de widgets (el listener de deep link de verificación de email, más abajo), ya que
/// todavía no hay un router (`go_router` llega con el mapa en Sprint 5).
final navigatorKeyColportores = GlobalKey<NavigatorState>();

/// Raíz de la app. El router (go_router) llega con el mapa en Sprint 5; hasta entonces la
/// navegación es "hay sesión → pantalla principal (la jornada, HU-JOR-001), no hay → login".
class ColportoresApp extends ConsumerWidget {
  const ColportoresApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);

    // HU-AUTH-007 (17-A02): la conexión se lee desde el arranque, en paralelo a la sesión. Si la
    // leyera recién el login, ya dibujado, el primer cuadro sería 17-A01 con el teléfono sin señal.
    ref.listen(conexionProvider, (previous, next) {});

    // HU-AUTH-002: si el deep link de verificación vuelve con un error (enlace vencido o ya
    // usado) mientras la app no está mostrando la pantalla de verificación — o ni siquiera
    // estaba abierta —, este es el único lugar que se entera, así que es el único lugar que
    // puede llevar al usuario ahí. `erroresVerificacionEmailProvider` es `keepAlive`: esto se
    // suscribe una sola vez por vida de la app (`ColportoresApp` es la raíz, siempre montada).
    ref.listen(erroresVerificacionEmailProvider, (previous, next) {
      if (next is! AsyncData<EventoVerificacionEmail>) return;
      unawaited(_resolverEnlaceUsado(context, ref));
    });

    // HU-AUTH-002 (issue #84): simétrico al listener de arriba, para el caso de éxito — el
    // enlace de verificación es válido y Supabase ya confirmó el email y creó la sesión. A
    // diferencia del caso de error, acá no hace falta esperar a `sesionProvider`: el evento en sí
    // ya es la prueba de que la sesión se acaba de crear (no hay ambigüedad de "enlace viejo" que
    // resolver, como sí la hay con `otp_expired`). Funciona igual en un arranque en frío: el deep
    // link se procesa durante `Supabase.initialize()`, antes de `runApp`, pero el intercambio de
    // código por sesión (red) tarda lo suficiente como para que este listener ya esté suscripto
    // cuando el evento llega.
    ref.listen(verificacionesExitosasProvider, (previous, next) {
      if (next is! AsyncData<EventoVerificacionEmail>) return;
      _navegarAVerificacion(context, EstadoVerificacionEmail.verificado);
    });

    // HU-AUTH-007: si la sesión vence o el servidor la revoca con la app abierta, `home:` pasa al
    // login, pero lo que estuviera apilado encima (configuración, otra pantalla) seguiría a la
    // vista: se vacía la pila para que se vea el login con el aviso.
    //
    // No en el arranque (#308): con el motivo del cierre guardado, el aviso se fija al terminar de
    // leer la sesión, y un enlace de recuperación o de verificación que llegó antes ya abrió su
    // pantalla; vaciar la pila la sacaría y gastaría el enlace. Mientras la sesión no se resolvió
    // ni una vez (el arranque), lo único apilado puede ser esa pantalla.
    ref.listen(avisoSesionProvider, (previous, next) {
      if (next == null) return;
      if (!ref.read(sesionProvider).hasValue) return;
      navigatorKeyColportores.currentState?.popUntil((route) => route.isFirst);
    });

    // HU-AUTH-005: el enlace de recuperación de contraseña (válido o vencido) puede llegar con la
    // app en cualquier pantalla, o abriéndola. Mismo criterio que la verificación: este es el único
    // lugar que se entera. Si había una sesión iniciada, igual se muestra: el enlace es de la
    // cuenta de quien lo pidió, y al terminar se cierran todas las sesiones.
    ref.listen(enlacesRecuperacionProvider, (previous, next) {
      if (next case AsyncData(:final value)) _llevarAConfirmarRecuperacion(value.enlace);
    });

    return _RevisionAlVolver(
      child: MaterialApp(
        navigatorKey: navigatorKeyColportores,
        title: 'Colportores',
        theme: temaClaro(),
        // Solo la primera lectura de la sesión (arranque) pasa por la pantalla de carga. Un
        // «Entrar» en vuelo vuelve a poner `AsyncLoading`, pero con la sesión (nula) de antes: si
        // eso cambiara la pantalla, el login se desmontaba con la respuesta en camino y el aviso del
        // intento (contraseña incorrecta, sin conexión, 17-A02) se perdía; el botón ya muestra el
        // «Entrando…».
        home: sesion.when(
          skipLoadingOnReload: true,
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => const LoginPage(),
          data: (s) => s == null ? const LoginPage() : _Principal(sesion: s),
        ),
      ),
    );
  }
}

/// Un enlace de verificación llegó con `otp_expired` (Supabase no distingue «vencido» de «ya
/// usado»): decide qué mostrar según HU-AUTH-002 («"Vencido" vs "ya usado"») y navega.
///
/// Espera a que `sesionProvider` termine de resolver: en un arranque en frío desde el enlace,
/// Supabase ya procesó el deep link durante `Supabase.initialize()` (antes de `runApp`), pero
/// `sesionActual()` hace I/O real y puede seguir en `AsyncLoading` cuando este evento llega —
/// decidir en ese momento daría «no hay sesión» cuando la hay, solo que todavía no terminó de
/// leerse.
Future<void> _resolverEnlaceUsado(BuildContext context, WidgetRef ref) async {
  final resuelto = await ref.read(resolutorEnlaceVerificacionUsadoProvider.notifier).resolver();
  if (resuelto == null || !context.mounted) return;
  _navegarAVerificacion(context, switch (resuelto.destino) {
    DestinoEnlaceVerificacionUsado.yaVerificado => EstadoVerificacionEmail.yaVerificado,
    DestinoEnlaceVerificacionUsado.expirado => EstadoVerificacionEmail.expirado,
    DestinoEnlaceVerificacionUsado.noSabemos => EstadoVerificacionEmail.enlaceInutil,
  }, email: resuelto.email);
}

/// Lleva a [VerificacionEmailPage] en [estadoInicial], vaciando la pila hasta la raíz primero —
/// compartido por los dos listeners globales de deep link de verificación (error arriba, éxito en
/// [ColportoresApp.build]): en los dos casos la pantalla puede tener que aparecer encima de
/// cualquier otra que estuviera mostrándose (o de ninguna, en un arranque en frío).
void _navegarAVerificacion(
  BuildContext context,
  EstadoVerificacionEmail estadoInicial, {
  String email = '',
}) {
  if (!context.mounted) return;

  final navigator = navigatorKeyColportores.currentState;
  if (navigator == null) return;
  navigator.popUntil((route) => route.isFirst);
  unawaited(
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => VerificacionEmailPage(email: email, estadoInicial: estadoInicial),
      ),
    ),
  );
}

/// HU-AUTH-007: cada vez que la app vuelve al frente, revisa si la sesión venció por inactividad
/// mientras estaba en segundo plano (el proceso pudo quedar vivo días sin red).
class _RevisionAlVolver extends ConsumerStatefulWidget {
  const _RevisionAlVolver({required this.child});

  final Widget child;

  @override
  ConsumerState<_RevisionAlVolver> createState() => _RevisionAlVolverState();
}

class _RevisionAlVolverState extends ConsumerState<_RevisionAlVolver> {
  late final AppLifecycleListener _ciclo;

  @override
  void initState() {
    super.initState();
    _ciclo = AppLifecycleListener(
      onResume: () => unawaited(ref.read(sesionProvider.notifier).revisarVigencia()),
    );
  }

  @override
  void dispose() {
    _ciclo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Con sesión, primero la DB local cifrada (HU-AUTH-009, #27): hasta que esté abierta, la pantalla
/// de preparación. Después, la pantalla principal depende del estado de la cuenta (HU-AUTH-008):
/// solo una cuenta activa ve los módulos de campo; las demás, la pantalla de espera con
/// Configuración. Es el único camino a los módulos de campo mientras no haya router (llega en
/// Sprint 5): el gate de deep links de la HU vive acá.
class _Principal extends ConsumerStatefulWidget {
  const _Principal({required this.sesion});

  final Sesion sesion;

  @override
  ConsumerState<_Principal> createState() => _PrincipalState();
}

class _PrincipalState extends ConsumerState<_Principal> {
  /// El colportor vio la pantalla de espera con la cuenta pendiente: si pasa a activa con la app
  /// abierta, antes de la pantalla principal se le muestra «Ya te asignaron» (vista 18, 18-A07).
  /// Una cuenta que ya llega activa (o suspendida y reactivada) entra directo.
  bool _vioPendiente = false;
  bool _mostrandoAsignada = false;

  void _alCambiarEstado(AsyncValue<EstadoCuenta?>? anterior, AsyncValue<EstadoCuenta?> actual) {
    if (actual is! AsyncData<EstadoCuenta?>) return;
    final estado = actual.value;
    if (estado == EstadoCuenta.activa && _vioPendiente) {
      setState(() {
        _vioPendiente = false;
        _mostrandoAsignada = true;
      });
    } else if (estado != null && !estado.accedeAModulosDeCampo) {
      // Volvió a pendiente o suspendida (el coordinador revirtió la asignación): sin transición.
      setState(() {
        _vioPendiente = estado == EstadoCuenta.pendienteAsignacion;
        _mostrandoAsignada = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(copiaNombreSesionProvider);
    final preparacion = ref.watch(preparacionDbLocalProvider);
    if (preparacion is! DbLocalLista) return PreparacionDbLocalPage(estado: preparacion);
    ref.listen(estadoCuentaProvider, _alCambiarEstado);
    final estado = ref.watch(estadoCuentaProvider);
    if (estado case AsyncData(value: EstadoCuenta.pendienteAsignacion)) _vioPendiente = true;
    if (_mostrandoAsignada) {
      return CuentaAsignadaPage(onTerminar: () => setState(() => _mostrandoAsignada = false));
    }
    return switch (estado) {
      AsyncData(value: final e) when e == null || e.accedeAModulosDeCampo => InicioPage(
        sesion: widget.sesion,
      ),
      AsyncData(value: final e) => EsperandoAsignacionPage(estado: e),
      AsyncError(:final error) => EsperandoAsignacionPage(
        falla: error is Failure ? error : FailureInesperado(causa: error),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

/// Lleva a la pantalla de la contraseña nueva (o de enlace vencido) desde la raíz de la pila.
void _llevarAConfirmarRecuperacion(EnlaceRecuperacion enlace) {
  final navigator = navigatorKeyColportores.currentState;
  if (navigator == null) return;
  navigator.popUntil((route) => route.isFirst);
  unawaited(navigator.push(ConfirmarRecuperacionPasswordPage.ruta(enlace)));
}
