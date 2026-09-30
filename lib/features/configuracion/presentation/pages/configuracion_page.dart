import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/providers/estado_cuenta_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../../inicio/presentation/widgets/barra_pestanas_inicio.dart';
import '../providers/nombre_cuenta_provider.dart';
import '../widgets/hoja_cerrar_sesion.dart';
import 'borrar_datos_locales_page.dart';

/// Configuración de la cuenta en este teléfono (vista 16 del diseño): «Tu cuenta», «Privacidad y
/// datos» con el borrado de datos locales (HU-AUTH-010) y «Cerrar sesión» al pie (HU-AUTH-006),
/// con la confirmación en una hoja inferior. La fila «Mapas offline» no se muestra hasta que exista
/// esa pantalla (#190). La barra de pestañas es la de la pantalla principal; con una cuenta que
/// todavía no accede a los módulos de campo no se muestra (vista 18 la arma bloqueada).
class ConfiguracionPage extends ConsumerStatefulWidget {
  const ConfiguracionPage({super.key});

  /// La ruta de la pantalla. Todavía no hay router (go_router llega con el mapa en Sprint 5). Si
  /// se sale por la barra de pestañas devuelve la pestaña elegida; con «volver», `null`.
  static Route<PestanaInicio> ruta() =>
      MaterialPageRoute<PestanaInicio>(builder: (_) => const ConfiguracionPage());

  @override
  ConsumerState<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends ConsumerState<ConfiguracionPage> {
  /// Mientras se cuentan las operaciones pendientes antes de abrir la hoja.
  bool _revisando = false;

  Future<void> _cerrarSesion() async {
    if (_revisando) return; // Doble tap: idempotente (HU-AUTH-006, casos borde).
    setState(() => _revisando = true);

    // Si no se puede contar, se cierra igual con la confirmación común: cerrar sesión no borra
    // nada, lo pendiente se sube en el próximo login.
    var pendientes = 0;
    try {
      final resumen = await ref.read(obtenerResumenDatosLocalesUseCaseProvider)(const NoParams());
      pendientes = resumen.fold((_) => 0, (r) => r.operacionesSinSincronizar ?? 0);
    } on Object {
      pendientes = 0;
    }
    if (!mounted) return;
    setState(() => _revisando = false);

    final navigator = Navigator.of(context);
    await mostrarHojaCerrarSesion(
      context,
      pendientes: pendientes,
      cerrar: () async {
        final resultado = await ref.read(sesionProvider.notifier).cerrarSesion();
        if (resultado.isLeft()) return false;
        // La raíz ya muestra el login (la sesión es `null`); solo queda sacar esta pantalla.
        // Idempotente: si la raíz ya vació la pila (aviso de cierre sin conexión), no hace nada.
        navigator.popUntil((route) => route.isFirst);
        return true;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final email = ref.watch(sesionProvider).value?.email ?? '';
    final nombre = ref.watch(nombreCuentaProvider);
    final conBarra = switch (ref.watch(estadoCuentaProvider)) {
      AsyncData(value: final estado) => estado == null || estado.accedeAModulosDeCampo,
      _ => false,
    };

    return Scaffold(
      key: const Key('configuracion_pagina'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            Semantics(
                              header: true,
                              child: Text(
                                'Configuración',
                                style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                      const _TituloSeccion('Tu cuenta'),
                      const SizedBox(height: 8),
                      _Tarjeta(
                        children: [_FilaCuenta(nombre: nombre, email: email)],
                      ),
                      const SizedBox(height: 24),
                      const _TituloSeccion('Privacidad y datos'),
                      const SizedBox(height: 8),
                      _Tarjeta(
                        children: [
                          ListTile(
                            key: const Key('configuracion_borrar_datos'),
                            enabled: !_revisando,
                            minVerticalPadding: 12,
                            leading: Icon(
                              Icons.delete_forever_outlined,
                              color: theme.colorScheme.error,
                            ),
                            title: Text(
                              'Borrar datos locales',
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: const Text(
                              'Borra todo lo guardado en este teléfono y cierra tu sesión',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => unawaited(
                              Navigator.of(context).push(BorrarDatosLocalesPage.ruta()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: _CierreDeSesion(revisando: _revisando, onPressed: _cerrarSesion),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: conBarra
          ? BarraPestanasInicio(onSeleccionar: (pestana) => Navigator.of(context).pop(pestana))
          : null,
    );
  }
}

/// Color del encabezado chico ("CONFIGURACIÓN", "PRIVACIDAD Y DATOS"): el color primario (paleta
/// única 1b, #121 — el dorado ya no forma parte de la paleta).
Color colorEncabezado(ThemeData theme, ColoresColportaje colores) => theme.colorScheme.primary;

/// «Cerrar sesión» al pie, al alcance del pulgar, con lo que pasa con los datos del teléfono.
class _CierreDeSesion extends StatelessWidget {
  const _CierreDeSesion({required this.revisando, required this.onPressed});

  final bool revisando;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final escala = MediaQuery.textScalerOf(context).scale(15);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          OutlinedButton.icon(
            key: const Key('configuracion_cerrar_sesion'),
            onPressed: revisando ? null : onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: escala > 20
                  ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                  : const StadiumBorder(),
              side: BorderSide(color: colores.bordeInput),
            ),
            icon: revisando
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      key: Key('configuracion_cerrando'),
                      strokeWidth: 2.5,
                      semanticsLabel: 'Cerrando sesión',
                    ),
                  )
                : const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
          Text(
            TextosCerrarSesion.datosGuardados,
            key: const Key('configuracion_datos_guardados'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
          ),
        ],
      ),
    );
  }
}

/// Avatar con iniciales, nombre (si se conoce) y el correo con el que se inició sesión.
class _FilaCuenta extends StatelessWidget {
  const _FilaCuenta({required this.nombre, required this.email});

  final String? nombre;
  final String email;

  static String _iniciales(String? nombre, String email) {
    final partes = (nombre ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isNotEmpty) {
      return partes.take(2).map((p) => p.substring(0, 1).toUpperCase()).join();
    }
    return email.isEmpty ? '' : email.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conNombre = nombre != null && nombre!.trim().isNotEmpty;
    return ListTile(
      minVerticalPadding: 12,
      leading: ExcludeSemantics(
        child: CircleAvatar(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          child: Text(_iniciales(nombre, email)),
        ),
      ),
      title: conNombre
          ? Text(nombre!.trim(), key: const Key('configuracion_nombre'))
          : const Text('Sesión iniciada como'),
      subtitle: conNombre
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sesión iniciada como'),
                Text(email, key: const Key('configuracion_email')),
              ],
            )
          : Text(email, key: const Key('configuracion_email')),
    );
  }
}

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
