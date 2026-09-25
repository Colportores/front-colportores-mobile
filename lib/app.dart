import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/error/failure.dart';
import 'core/theme/tema_colportaje.dart';
import 'features/auth/domain/entities/enlace_recuperacion.dart';
import 'features/auth/domain/entities/sesion.dart';
import 'features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'features/auth/presentation/pages/esperando_asignacion_page.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/verificacion_email_page.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'features/auth/presentation/providers/aviso_sesion_notifier.dart';
import 'features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'features/auth/presentation/providers/sesion_notifier.dart';
import 'features/jornada/presentation/pages/jornada_page.dart';

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

    // HU-AUTH-002: si el deep link de verificación vuelve con un error (enlace vencido o ya
    // usado) mientras la app no está mostrando la pantalla de verificación — o ni siquiera
    // estaba abierta —, este es el único lugar que se entera, así que es el único lugar que
    // puede llevar al usuario ahí. `erroresVerificacionEmailProvider` es `keepAlive`: esto se
    // suscribe una sola vez por vida de la app (`ColportoresApp` es la raíz, siempre montada).
    ref.listen(erroresVerificacionEmailProvider, (previous, next) {
      if (next is! AsyncData<void>) return;
      unawaited(_llevarAVerificacionSiNoHaySesion(context, ref));
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
      if (next is! AsyncData<void>) return;
      _navegarAVerificacion(context, EstadoVerificacionEmail.verificado);
    });

    // HU-AUTH-007: si la sesión vence o el servidor la revoca con la app abierta, `home:` pasa al
    // login, pero lo que estuviera apilado encima (configuración, otra pantalla) seguiría a la
    // vista: se vacía la pila para que se vea el login con el aviso.
    ref.listen(avisoSesionProvider, (previous, next) {
      if (next == null) return;
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
        home: sesion.when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => const LoginPage(),
          data: (s) => s == null ? const LoginPage() : _Principal(sesion: s),
        ),
      ),
    );
  }
}

/// Decide si hay que llevar al usuario a [VerificacionEmailPage] en estado expirado, con el mismo
/// criterio que `home:` en [ColportoresApp.build] usa para elegir entre [LoginPage] e
/// [JornadaPage]: sesión → no corresponde (es un enlace viejo de un mail anterior); sin sesión →
/// sí. La diferencia con leer `sesion.value` directamente (bug de la ronda anterior) es esperar a
/// que `sesionProvider` termine de resolver: en un arranque en frío desde el enlace, Supabase ya
/// procesó el deep link durante `Supabase.initialize()` (antes de `runApp`), pero
/// `sesionActual()` hace I/O real (local y, si hace falta, de red) y puede seguir en
/// `AsyncLoading` cuando este evento llega — navegar en ese momento es el bug original: la sesión
/// existe, solo que todavía no terminó de leerse.
Future<void> _llevarAVerificacionSiNoHaySesion(BuildContext context, WidgetRef ref) async {
  bool haySesion;
  try {
    haySesion = await ref.read(sesionProvider.future) != null;
  } on Object {
    // Mismo criterio que `home:` ante un error de sesión (`error: (_, _) => LoginPage()`): se
    // trata como si no hubiera sesión.
    haySesion = false;
  }
  if (haySesion) return;
  if (!context.mounted) return;
  _navegarAVerificacion(context, EstadoVerificacionEmail.expirado);
}

/// Lleva a [VerificacionEmailPage] en [estadoInicial], vaciando la pila hasta la raíz primero —
/// compartido por los dos listeners globales de deep link de verificación (error arriba, éxito en
/// [ColportoresApp.build]): en los dos casos la pantalla puede tener que aparecer encima de
/// cualquier otra que estuviera mostrándose (o de ninguna, en un arranque en frío).
void _navegarAVerificacion(BuildContext context, EstadoVerificacionEmail estadoInicial) {
  if (!context.mounted) return;

  final navigator = navigatorKeyColportores.currentState;
  if (navigator == null) return;
  navigator.popUntil((route) => route.isFirst);
  unawaited(
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => VerificacionEmailPage(estadoInicial: estadoInicial)),
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

/// Con sesión, la pantalla principal depende del estado de la cuenta (HU-AUTH-008): solo una
/// cuenta activa ve los módulos de campo; las demás, la pantalla de espera con Configuración. Es
/// el único camino a los módulos de campo mientras no haya router (llega en Sprint 5): el gate de
/// deep links de la HU vive acá.
class _Principal extends ConsumerWidget {
  const _Principal({required this.sesion});

  final Sesion sesion;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (ref.watch(estadoCuentaProvider)) {
    AsyncData(value: final estado) when estado == null || estado.accedeAModulosDeCampo =>
      JornadaPage(sesion: sesion),
    AsyncData(value: final estado) => EsperandoAsignacionPage(estado: estado),
    AsyncError(:final error) => EsperandoAsignacionPage(
      falla: error is Failure ? error : FailureInesperado(causa: error),
    ),
    _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
  };
}

/// Lleva a la pantalla de la contraseña nueva (o de enlace vencido) desde la raíz de la pila.
void _llevarAConfirmarRecuperacion(EnlaceRecuperacion enlace) {
  final navigator = navigatorKeyColportores.currentState;
  if (navigator == null) return;
  navigator.popUntil((route) => route.isFirst);
  unawaited(navigator.push(ConfirmarRecuperacionPasswordPage.ruta(enlace)));
}
