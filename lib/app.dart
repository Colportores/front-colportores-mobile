import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/tema_colportaje.dart';
import 'features/auth/domain/entities/enlace_recuperacion.dart';
import 'features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/verificacion_email_page.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
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

    // HU-AUTH-005: el enlace de recuperación de contraseña (válido o vencido) puede llegar con la
    // app en cualquier pantalla, o abriéndola. Mismo criterio que la verificación: este es el único
    // lugar que se entera. Si había una sesión iniciada, igual se muestra: el enlace es de la
    // cuenta de quien lo pidió, y al terminar se cierran todas las sesiones.
    ref.listen(enlacesRecuperacionProvider, (previous, next) {
      if (next case AsyncData(:final value)) _llevarAConfirmarRecuperacion(value);
    });

    return MaterialApp(
      navigatorKey: navigatorKeyColportores,
      title: 'Colportores',
      theme: temaClaro(),
      darkTheme: temaOscuro(),
      themeMode: ThemeMode.system,
      home: sesion.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => const LoginPage(),
        data: (s) => s == null ? const LoginPage() : JornadaPage(sesion: s),
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

  final navigator = navigatorKeyColportores.currentState;
  if (navigator == null) return;
  navigator.popUntil((route) => route.isFirst);
  unawaited(
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const VerificacionEmailPage(estadoInicial: EstadoVerificacionEmail.expirado),
      ),
    ),
  );
}

/// Lleva a la pantalla de la contraseña nueva (o de enlace vencido) desde la raíz de la pila.
void _llevarAConfirmarRecuperacion(EnlaceRecuperacion enlace) {
  final navigator = navigatorKeyColportores.currentState;
  if (navigator == null) return;
  navigator.popUntil((route) => route.isFirst);
  unawaited(navigator.push(ConfirmarRecuperacionPasswordPage.ruta(enlace)));
}
