import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../auth/domain/entities/resultado_cierre_sesion.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import 'borrar_datos_locales_page.dart';

/// Configuración de la cuenta en este teléfono: cerrar sesión (HU-AUTH-006) y, bajo "Privacidad y
/// datos", borrar los datos locales (HU-AUTH-010). Sin diseño de Claude Design: sigue el tema y
/// los patrones de las pantallas de auth (encabezado dorado, título grande, tarjetas con borde).
class ConfiguracionPage extends ConsumerStatefulWidget {
  const ConfiguracionPage({super.key});

  /// La ruta de la pantalla. Todavía no hay router (go_router llega con el mapa en Sprint 5).
  static Route<void> ruta() => MaterialPageRoute<void>(builder: (_) => const ConfiguracionPage());

  @override
  ConsumerState<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

/// Textos de los criterios de aceptación de HU-AUTH-006 (literales) y de los avisos propios.
abstract final class TextosConfiguracion {
  static String advertenciaPendientes(int n) =>
      'Tenés $n operaciones sin sincronizar. Si cerrás sesión ahora, se subirán cuando vuelvas a '
      'iniciar sesión.';
  static const cerradaSinConexion =
      'Cerraste sesión en este teléfono. Se va a cerrar por completo cuando haya conexión.';
  static const confirmarCierre =
      'Tus datos quedan guardados en este teléfono: vas a volver a verlos cuando inicies sesión.';
  static const errorCierre = 'No pudimos cerrar la sesión. Probá de nuevo.';
}

class _ConfiguracionPageState extends ConsumerState<ConfiguracionPage> {
  bool _cerrando = false;

  /// El aviso de error con "Reintentar", mientras está visible (ver [_ocultarAvisoReintentar]).
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _avisoReintentar;

  /// Guardado en [didChangeDependencies]: en [dispose] ya no se puede buscar en el `context`.
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    // El SnackBar vive en el ScaffoldMessenger de la app, no en esta pantalla: sin esto, su
    // "Reintentar" seguiría visible afuera y sin hacer nada (#102). Después del frame y no acá:
    // en `dispose` el árbol está bloqueado, y con la navegación accesible (TalkBack, VoiceOver)
    // ocultarlo hace un `setState` en el messenger que dispara una aserción.
    if (_avisoReintentar != null) {
      _avisoReintentar = null;
      final messenger = _messenger;
      // Si la app entera se desmontó en el mismo frame, el messenger ya no está: nada que ocultar.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (messenger != null && messenger.mounted) messenger.hideCurrentSnackBar();
      });
    }
    super.dispose();
  }

  /// Saca el aviso con "Reintentar" si sigue visible. Siempre se cierra antes de mostrar otro, así
  /// que mientras [_avisoReintentar] no es `null` es el SnackBar actual.
  void _ocultarAvisoReintentar() {
    if (_avisoReintentar == null) return;
    _avisoReintentar = null;
    _messenger?.hideCurrentSnackBar();
  }

  Future<void> _cerrarSesion() async {
    if (_cerrando) return; // Doble tap: idempotente (HU-AUTH-006, casos borde).
    setState(() => _cerrando = true);

    // Si no se puede contar, se cierra igual con la confirmación común: cerrar sesión no borra
    // nada, lo pendiente se sube en el próximo login.
    final resumen = await ref.read(obtenerResumenDatosLocalesUseCaseProvider)(const NoParams());
    final pendientes = resumen.fold((_) => 0, (r) => r.operacionesSinSincronizar ?? 0);
    if (!mounted) return;
    setState(() => _cerrando = false);

    final confirmado = await _confirmarCierre(pendientes);
    if (confirmado != true || !mounted) return;

    setState(() => _cerrando = true);
    final resultado = await ref.read(sesionProvider.notifier).cerrarSesion();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    _ocultarAvisoReintentar();
    resultado.fold(
      (_) {
        setState(() => _cerrando = false);
        final aviso = messenger.showSnackBar(
          SnackBar(
            key: const Key('configuracion_error_cierre'),
            content: const Text(TextosConfiguracion.errorCierre),
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: () {
                // Si la pantalla ya no está, el reintento no tiene dónde mostrar nada.
                if (mounted) unawaited(_cerrarSesion());
              },
            ),
          ),
        );
        _avisoReintentar = aviso;
        unawaited(
          aviso.closed.then((_) {
            if (identical(_avisoReintentar, aviso)) _avisoReintentar = null;
          }),
        );
      },
      (r) {
        if (r == ResultadoCierreSesion.revocacionPendiente) {
          messenger.showSnackBar(
            const SnackBar(
              key: Key('configuracion_cierre_sin_conexion'),
              content: Text(TextosConfiguracion.cerradaSinConexion),
              duration: Duration(seconds: 8),
            ),
          );
        }
        // La raíz ya muestra el login (la sesión es `null`); solo queda sacar esta pantalla.
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }

  Future<bool?> _confirmarCierre(int pendientes) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('configuracion_dialogo_cierre'),
      title: const Text('Cerrar sesión'),
      content: Text(
        pendientes > 0
            ? TextosConfiguracion.advertenciaPendientes(pendientes)
            : TextosConfiguracion.confirmarCierre,
      ),
      actions: [
        TextButton(
          key: const Key('configuracion_dialogo_cancelar'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('configuracion_dialogo_confirmar'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(pendientes > 0 ? 'Cerrar sesión igual' : 'Cerrar sesión'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final email = ref.watch(sesionProvider).value?.email ?? '';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                key: const Key('configuracion_atras'),
                tooltip: 'Volver',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'CONFIGURACIÓN',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorEncabezado(theme, colores),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Tu cuenta', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            _Tarjeta(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colores.oro,
                    foregroundColor: colores.negro,
                    child: const Icon(Icons.person_outline),
                  ),
                  title: const Text('Sesión iniciada como'),
                  subtitle: Text(email, key: const Key('configuracion_email')),
                ),
                const Divider(),
                ListTile(
                  key: const Key('configuracion_cerrar_sesion'),
                  enabled: !_cerrando,
                  leading: const Icon(Icons.logout),
                  title: const Text('Cerrar sesión'),
                  subtitle: const Text('Tus datos quedan guardados en este teléfono'),
                  trailing: _cerrando
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
                            key: Key('configuracion_cerrando'),
                            strokeWidth: 2.5,
                            semanticsLabel: 'Cerrando sesión',
                          ),
                        )
                      : null,
                  onTap: _cerrarSesion,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _TituloSeccion('Privacidad y datos'),
            const SizedBox(height: 8),
            _Tarjeta(
              children: [
                ListTile(
                  key: const Key('configuracion_borrar_datos'),
                  enabled: !_cerrando,
                  leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
                  title: Text(
                    'Borrar datos locales',
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Borra todo lo guardado en este teléfono y cierra tu sesión',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(BorrarDatosLocalesPage.ruta()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Color del encabezado chico ("CONFIGURACIÓN", "PRIVACIDAD Y DATOS"): el dorado de las pantallas
/// de auth en el tema oscuro; en el claro el dorado sobre crema no llega al contraste mínimo
/// (2,3:1 contra 4,5:1), así que va el color primario.
Color colorEncabezado(ThemeData theme, ColoresColportaje colores) =>
    theme.brightness == Brightness.dark ? colores.oro : theme.colorScheme.primary;

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Semantics(header: true, child: Text(texto, style: theme.textTheme.titleMedium)),
    );
  }
}

/// Grupo de opciones con el borde de las tarjetas del tema.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).extension<ColoresColportaje>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colores.borde),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );
  }
}
