import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../configuracion/presentation/pages/configuracion_page.dart';
import '../../domain/entities/estado_cuenta.dart';
import '../providers/estado_cuenta_providers.dart';

/// Textos de la pantalla de espera (HU-AUTH-008). Los que no están en la HU van "para confirmar"
/// en #63.
abstract final class TextosEsperaAsignacion {
  static const tituloPendiente = 'Esperando asignación';
  static const pendiente =
      'Tu cuenta fue creada. Estamos esperando que tu coordinador te asigne a una campaña.';
  static const comoRevisar =
      'Cuando te asigne vas a poder empezar a trabajar. Deslizá hacia abajo o tocá Actualizar '
      'para revisar.';
  static const aunNoAsignado = 'Aún no asignado';

  static const tituloSuspendida = 'Cuenta suspendida';
  static const suspendida = 'Tu cuenta está suspendida. Contactá al administrador.';

  static const tituloSinEstado = 'No pudimos revisar tu cuenta';
  static const sinEstadoSinConexion =
      'Necesitás conexión para saber si ya te asignaron a una campaña. Conectate y tocá '
      'Actualizar.';
  static const sinEstado =
      'No pudimos consultar el estado de tu cuenta. Tocá Actualizar para probar de nuevo; si '
      'sigue pasando, avisale a tu coordinador.';
}

/// Pantalla de la cuenta que todavía no puede trabajar (HU-AUTH-008): pendiente de asignación a
/// una campaña, suspendida, o sin estado conocido porque nunca se pudo consultar. Los módulos de
/// campo no están; Configuración sí (cerrar sesión, borrar datos).
///
/// Refrescar (deslizando o con "Actualizar") vuelve a consultar al backend: si la cuenta pasó a
/// activa, la raíz de la app lleva a la pantalla principal sola.
class EsperandoAsignacionPage extends ConsumerStatefulWidget {
  const EsperandoAsignacionPage({this.estado, this.falla, super.key})
    : assert(estado != null || falla != null, 'un estado o la falla de no tenerlo');

  /// [EstadoCuenta.pendienteAsignacion] o [EstadoCuenta.suspendida].
  final EstadoCuenta? estado;

  /// Por qué no se conoce el estado (cuando [estado] es `null`).
  final Failure? falla;

  @override
  ConsumerState<EsperandoAsignacionPage> createState() => _EsperandoAsignacionPageState();
}

class _EsperandoAsignacionPageState extends ConsumerState<EsperandoAsignacionPage> {
  bool _consultando = false;

  Future<void> _actualizar() async {
    if (_consultando) return;
    setState(() => _consultando = true);
    final falla = await ref.read(estadoCuentaProvider.notifier).refrescar();
    if (!mounted) return;
    setState(() => _consultando = false);

    final mensaje = switch (falla) {
      Failure(:final mensaje) => mensaje,
      null when ref.read(estadoCuentaProvider).value == EstadoCuenta.pendienteAsignacion =>
        TextosEsperaAsignacion.aunNoAsignado,
      null => null,
    };
    if (mensaje == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(key: const Key('espera_resultado'), content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (titulo, mensaje, ayuda) = switch ((widget.estado, widget.falla)) {
      (EstadoCuenta.suspendida, _) => (
        TextosEsperaAsignacion.tituloSuspendida,
        TextosEsperaAsignacion.suspendida,
        null,
      ),
      (EstadoCuenta.pendienteAsignacion || EstadoCuenta.activa, _) => (
        TextosEsperaAsignacion.tituloPendiente,
        TextosEsperaAsignacion.pendiente,
        TextosEsperaAsignacion.comoRevisar,
      ),
      (null, FailureSinConexion()) => (
        TextosEsperaAsignacion.tituloSinEstado,
        TextosEsperaAsignacion.sinEstadoSinConexion,
        null,
      ),
      (null, _) => (TextosEsperaAsignacion.tituloSinEstado, TextosEsperaAsignacion.sinEstado, null),
    };

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            key: const Key('espera_configuracion'),
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => unawaited(Navigator.of(context).push(ConfiguracionPage.ruta())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _actualizar,
          child: ListView(
            // Deslizar tiene que andar aunque el contenido no llene la pantalla.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
            children: [
              ExcludeSemantics(
                child: Icon(
                  widget.estado == EstadoCuenta.suspendida
                      ? Icons.block_outlined
                      : Icons.hourglass_empty_outlined,
                  size: 40,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  titulo,
                  key: const Key('espera_titulo'),
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 12),
              Text(mensaje, key: const Key('espera_mensaje'), style: theme.textTheme.bodyLarge),
              if (ayuda != null) ...[
                const SizedBox(height: 12),
                Text(ayuda, key: const Key('espera_ayuda'), style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 28),
              FilledButton(
                key: const Key('espera_actualizar'),
                onPressed: _consultando ? null : _actualizar,
                child: _consultando
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            key: const Key('espera_consultando'),
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Flexible(child: Text('Consultando…')),
                        ],
                      )
                    : const Text('Actualizar'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('espera_ir_a_configuracion'),
                onPressed: () => unawaited(Navigator.of(context).push(ConfiguracionPage.ruta())),
                child: const Text('Configuración', textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
