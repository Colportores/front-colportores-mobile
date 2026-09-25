import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../../core/usecases/use_case.dart';
import '../../domain/entities/enlace_recuperacion.dart';
import '../../domain/entities/politica_password.dart';
import '../../domain/usecases/confirmar_recuperacion_password_use_case.dart';
import '../providers/recuperacion_password_providers.dart';
import '../providers/sesion_notifier.dart';
import 'recuperacion_password_page.dart';

/// Textos de HU-AUTH-005 (literales de los criterios de aceptación) y avisos propios.
abstract final class TextosConfirmacionRecuperacion {
  /// "Cambio exitoso": se muestra en el login.
  static const exito = 'Contraseña actualizada. Iniciá sesión.';

  /// "Error - token expirado" (el mismo texto de `FailureEnlaceRecuperacionVencido`).
  static const vencido = 'El enlace expiró. Solicitá uno nuevo.';

  /// Para `mensajePara`: "Necesitás conexión para cambiar tu contraseña" (#94).
  static const accionSinConexion = 'cambiar tu contraseña';

  /// Para `mensajePara`, cuando el enlace no se pudo canjear por falta de red: "Necesitás conexión
  /// para abrir el enlace. Cuando tengas señal, volvé a abrirlo desde el correo." (propio, sin
  /// literal en la HU).
  static const accionAbrirEnlace =
      'abrir el enlace. Cuando tengas señal, volvé a abrirlo desde el correo.';

  /// Qué pasa con los datos del teléfono (HU-AUTH-005, principio de no-sorpresa; ADR-006: se
  /// re-envuelve la DEK y la DB no se toca).
  static const datosLocales =
      'Los datos guardados en este teléfono no se tocan: los vas a seguir viendo cuando entres '
      'con la contraseña nueva.';

  static const errorInesperado =
      'No pudimos cambiar tu contraseña. Probá de nuevo; si sigue pasando, pedí un enlace nuevo.';
}

/// Contraseña nueva después de abrir el enlace de recuperación (HU-AUTH-005, #51).
///
/// Sin diseño de Claude Design: sigue el tema y los componentes de las pantallas de auth
/// (`RecuperacionPasswordPage`, `RegistroPage`).
///
/// - Con [EnlaceRecuperacion.valido]: el formulario (contraseña nueva y repetida, con la política
///   del registro). Al guardar, `ConfirmarRecuperacionPasswordUseCase` la fija, re-envuelve la DEK
///   si hay DB local y revoca todas las sesiones; la pantalla vuelve al login con "Contraseña
///   actualizada. Iniciá sesión.".
/// - Con [EnlaceRecuperacion.vencido] (o si la sesión del enlace vence mientras tanto): "El enlace
///   expiró. Solicitá uno nuevo.", con el botón para pedir otro (HU-AUTH-004) y volver al login.
/// - Con [EnlaceRecuperacion.sinConexion]: que hace falta conexión y que el enlace se vuelve a
///   abrir desde el correo (sigue sirviendo).
///
/// Si el usuario sale sin terminar, se suelta la sesión que abrió el enlace: si no, el próximo
/// arranque lo dejaría adentro sin haber puesto ninguna contraseña. Mientras guarda no se puede
/// salir (el "atrás" dejaría el cambio corriendo sin nadie que muestre cómo terminó).
class ConfirmarRecuperacionPasswordPage extends ConsumerStatefulWidget {
  const ConfirmarRecuperacionPasswordPage({super.key, required this.enlace});

  final EnlaceRecuperacion enlace;

  static Route<void> ruta(EnlaceRecuperacion enlace) =>
      MaterialPageRoute<void>(builder: (_) => ConfirmarRecuperacionPasswordPage(enlace: enlace));

  @override
  ConsumerState<ConfirmarRecuperacionPasswordPage> createState() =>
      _ConfirmarRecuperacionPasswordPageState();
}

class _ConfirmarRecuperacionPasswordPageState
    extends ConsumerState<ConfirmarRecuperacionPasswordPage> {
  final _nueva = TextEditingController();
  final _repetida = TextEditingController();

  late bool _vencido = widget.enlace == EnlaceRecuperacion.vencido;
  bool _guardando = false;
  bool _terminado = false;
  bool _sesionSoltada = false;
  Map<String, String> _erroresCampo = const {};
  String? _errorGeneral;

  @override
  void dispose() {
    _nueva.dispose();
    _repetida.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() {
      _guardando = true;
      _erroresCampo = const {};
      _errorGeneral = null;
    });

    final resultado = await ref.read(confirmarRecuperacionPasswordUseCaseProvider)(
      ConfirmarRecuperacionPasswordParams(nueva: _nueva.text, repetida: _repetida.text),
    );
    if (!mounted) return;

    switch (resultado.fold((f) => f, (_) => null)) {
      case null:
        await _volverAlLogin();
      case FailureEnlaceRecuperacionVencido():
        setState(() {
          _guardando = false;
          _vencido = true;
        });
      case FailureValidacion(:final campos):
        setState(() {
          _guardando = false;
          _erroresCampo = campos;
        });
      case FailureInesperado():
        setState(() {
          _guardando = false;
          _errorGeneral = TextosConfirmacionRecuperacion.errorInesperado;
        });
      case final Failure falla:
        setState(() {
          _guardando = false;
          _errorGeneral = mensajePara(
            falla,
            accion: TextosConfirmacionRecuperacion.accionSinConexion,
          );
        });
    }
  }

  /// La contraseña cambió y las sesiones quedaron revocadas: si la app tenía una sesión iniciada,
  /// también se cierra acá (DB, DEK en memoria), y se vuelve al login con el aviso de la HU.
  Future<void> _volverAlLogin() async {
    _terminado = true;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (ref.read(sesionProvider).value != null) {
      await ref.read(sesionProvider.notifier).cerrarSesion();
    }
    navigator.popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      const SnackBar(
        key: Key('confirmar_recuperacion_exito'),
        content: Text(TextosConfirmacionRecuperacion.exito),
        duration: Duration(seconds: 8),
      ),
    );
  }

  void _alSalir(bool salio) {
    if (salio) _soltarSesionDelEnlace();
  }

  /// Sin terminar, se suelta la sesión que abrió el enlace (ver dartdoc de la clase). También si el
  /// enlace venció a mitad del flujo: un 401/403 del servidor no borra la sesión que gotrue guardó
  /// en el teléfono, y el próximo arranque entraría sin contraseña (revisión de #112). Un enlace
  /// que llegó vencido o sin red no abrió ninguna sesión: soltar cerraría la de quien ya estaba
  /// adentro. Una sola vez; si falla, ya quedó en el log y el usuario no puede hacer nada con eso.
  void _soltarSesionDelEnlace() {
    if (_terminado || _sesionSoltada || widget.enlace != EnlaceRecuperacion.valido) return;
    _sesionSoltada = true;
    unawaited(ref.read(abandonarRecuperacionPasswordUseCaseProvider)(const NoParams()));
  }

  /// `pushReplacement` no pasa por el `PopScope`: la sesión se suelta acá.
  void _pedirOtroEnlace() {
    _soltarSesionDelEnlace();
    unawaited(
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute<void>(builder: (_) => const RecuperacionPasswordPage())),
    );
  }

  void _irAlLogin() => Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const paddingHorizontal = 30.0;

    return PopScope(
      canPop: !_guardando,
      onPopInvokedWithResult: (salio, _) => _alSalir(salio),
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    key: const Key('confirmar_recuperacion_atras'),
                    tooltip: 'Volver',
                    onPressed: _guardando ? null : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
                const SizedBox(height: 12),
                if (_vencido)
                  _vencidoContenido(theme)
                else if (widget.enlace == EnlaceRecuperacion.sinConexion)
                  _sinConexionContenido(theme)
                else
                  _formulario(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _encabezado(ThemeData theme, String titulo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RECUPERAR CONTRASEÑA',
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Text(titulo, style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26)),
      ],
    );
  }

  Widget _vencidoContenido(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _encabezado(theme, 'Enlace vencido'),
      const SizedBox(height: 16),
      Semantics(
        liveRegion: true,
        child: Text(
          TextosConfirmacionRecuperacion.vencido,
          key: const Key('confirmar_recuperacion_vencido'),
          style: theme.textTheme.bodyLarge,
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('confirmar_recuperacion_pedir_otro'),
        onPressed: _pedirOtroEnlace,
        child: const Text('Solicitar un enlace nuevo'),
      ),
      const SizedBox(height: 8),
      TextButton(
        key: const Key('confirmar_recuperacion_ir_al_login'),
        onPressed: _irAlLogin,
        child: const Text('Volver al login'),
      ),
    ],
  );

  Widget _sinConexionContenido(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _encabezado(theme, 'Sin conexión'),
      const SizedBox(height: 16),
      Semantics(
        liveRegion: true,
        child: Text(
          mensajePara(
            const FailureSinConexion(),
            accion: TextosConfirmacionRecuperacion.accionAbrirEnlace,
          ),
          key: const Key('confirmar_recuperacion_sin_conexion'),
          style: theme.textTheme.bodyLarge,
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('confirmar_recuperacion_ir_al_login'),
        onPressed: _irAlLogin,
        child: const Text('Volver al login'),
      ),
    ],
  );

  Widget _formulario(ThemeData theme) {
    final colores = theme.extension<ColoresColportaje>()!;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _encabezado(theme, 'Elegí una contraseña nueva'),
          const SizedBox(height: 12),
          Text(TextosConfirmacionRecuperacion.datosLocales, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 22),
          _CampoPassword(
            etiqueta: 'CONTRASEÑA NUEVA',
            campoKey: const Key('confirmar_recuperacion_nueva'),
            controller: _nueva,
            errorText: _erroresCampo['password'],
            ayuda: PoliticaPassword.requisitos,
            accionTeclado: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          _CampoPassword(
            etiqueta: 'REPETIR CONTRASEÑA',
            campoKey: const Key('confirmar_recuperacion_repetida'),
            controller: _repetida,
            errorText: _erroresCampo['repetida'],
            accionTeclado: TextInputAction.done,
            alEnviar: (_) => _guardar(),
          ),
          if (_errorGeneral case final error?) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                key: const Key('confirmar_recuperacion_error'),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('confirmar_recuperacion_guardar'),
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          key: const Key('confirmar_recuperacion_guardando'),
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Flexible(child: Text('Guardando…')),
                    ],
                  )
                : const Text('Guardar contraseña'),
          ),
          const SizedBox(height: 12),
          Text(
            'Al guardarla se cierran tus sesiones en todos tus teléfonos: vas a entrar de nuevo con '
            'la contraseña nueva.',
            style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
          ),
        ],
      ),
    );
  }
}

/// Campo de contraseña con "mostrar/ocultar": misma estructura que `_CampoRegistro`.
class _CampoPassword extends StatefulWidget {
  const _CampoPassword({
    required this.etiqueta,
    required this.campoKey,
    required this.controller,
    required this.accionTeclado,
    this.errorText,
    this.ayuda,
    this.alEnviar,
  });

  final String etiqueta;
  final Key campoKey;
  final TextEditingController controller;
  final TextInputAction accionTeclado;
  final String? errorText;
  final String? ayuda;
  final ValueChanged<String>? alEnviar;

  @override
  State<_CampoPassword> createState() => _CampoPasswordState();
}

class _CampoPasswordState extends State<_CampoPassword> {
  bool _mostrar = false;

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
          key: widget.campoKey,
          controller: widget.controller,
          obscureText: !_mostrar,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: widget.accionTeclado,
          onSubmitted: widget.alEnviar,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            errorText: widget.errorText,
            errorMaxLines: 3,
            helperText: widget.ayuda,
            helperMaxLines: 3,
            helperStyle: TextStyle(color: colores.gris, fontSize: 11),
            suffixIcon: IconButton(
              tooltip: _mostrar ? 'Ocultar contraseña' : 'Mostrar contraseña',
              icon: Icon(
                _mostrar ? Icons.visibility_off : Icons.visibility,
                color: colores.placeholder,
                size: 20,
              ),
              onPressed: () => setState(() => _mostrar = !_mostrar),
            ),
          ),
        ),
      ],
    );
  }
}
