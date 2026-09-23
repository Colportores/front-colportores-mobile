import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/tema_colportaje.dart';
import 'features/auth/presentation/pages/inicio_page.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/verificacion_email_page.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'features/auth/presentation/providers/sesion_notifier.dart';

/// Navegador raíz de la app — hace falta como referencia estable para poder navegar desde fuera
/// del árbol de widgets (el listener de deep link de verificación de email, más abajo), ya que
/// todavía no hay un router (`go_router` llega con el mapa en Sprint 5).
final navigatorKeyColportores = GlobalKey<NavigatorState>();

/// Raíz de la app. El router (go_router) llega con el mapa en Sprint 5; hasta entonces la
/// navegación es "hay sesión → inicio, no hay → login".
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
      // Con "Confirm email" activo, tener sesión implica cuenta ya verificada: si ya hay una,
      // este evento viene de un enlace viejo (de un mail anterior) y no corresponde interrumpir
      // al usuario ni vaciarle la pila de navegación con un aviso falso de "enlace vencido".
      final haySesion = ref.read(sesionProvider).value != null;
      if (haySesion) return;

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
        data: (s) => s == null ? const LoginPage() : InicioPage(sesion: s),
      ),
    );
  }
}
