import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/usecases/inicializar_db_local_use_case.dart';
import '../providers/preparacion_db_local_notifier.dart';
import '../providers/sesion_notifier.dart';

/// Textos de la pantalla. Los de la HU y de ADR-006 van literales (en los `Failure`); los demás
/// son propios y están **para confirmar** (#27).
abstract final class TextosPreparacionDbLocal {
  /// HU-AUTH-009: "Preparando tu espacio seguro… 1/3, 2/3, 3/3".
  static const preparando = 'Preparando tu espacio seguro…';

  /// Paso [paso] de 3, con el formato de la HU.
  static String progreso(int paso) => '$preparando $paso/3';

  /// HU-AUTH-009, S10: el botón del consentimiento.
  static const aceptarRiesgo = 'Entiendo el riesgo y quiero continuar';

  // --- Para confirmar ---

  static const recuperando = 'Recuperando tus datos…';

  static const preguntaRiesgo = '¿Querés continuar con este celular?';

  static const otroCelular =
      'No preparamos tu espacio seguro. Para usar la app con la protección completa, iniciá sesión '
      'desde otro celular. Los modelos de los últimos años guardan las claves en un chip aparte, '
      'que es lo más seguro.';

  static const sinEspacioQueHacer =
      'Liberá espacio en el teléfono (fotos, videos o apps que no uses) y reintentá.';

  static const inesperadoQueHacer = 'Reintentá. Si sigue pasando, consultá a soporte.';

  static const sinRecuperacionQueHacer =
      'Puede ser algo pasajero: reintentá. No se borró nada de este teléfono.';

  static const empezarDeNuevoOferta =
      'Si sigue sin funcionar, podés empezar de nuevo con este teléfono.';

  static const empezarDeNuevoTitulo = '¿Empezar de nuevo?';

  static const empezarDeNuevoDetalle =
      'Los datos guardados en este teléfono no se pueden abrir sin su clave. Si empezás de nuevo, '
      'se borran: las personas y las notas que no se hayan sincronizado se pierden, y lo '
      'sincronizado se vuelve a bajar. No se puede deshacer.';

  static const actualizarComo =
      'Buscá Colportores en la tienda de tu celular (Google Play o App Store) y actualizala.';
}

/// La DB local de quien acaba de entrar, antes de la pantalla principal (HU-AUTH-009, #27).
///
/// Sin diseño de Claude Design: sigue el tema y los componentes de las pantallas de auth
/// (`ConfirmarRecuperacionPasswordPage`). Muestra el [estado] de `PreparacionDbLocalNotifier`:
/// - el progreso, con el paso de 3 de la HU (nunca un spinner mudo);
/// - la advertencia del Keystore por software (S10), con el consentimiento explícito;
/// - la recuperación con la contraseña (ADR-006);
/// - "Reintentar" ante una falla, y "empezar de nuevo" —que borra, con confirmación— recién
///   después de un reintento que volvió a fallar;
/// - la pantalla bloqueante de una DB de una versión más nueva de la app, sin ofrecer borrar.
///
/// Todas las fallas, salvo esa, ofrecen cerrar la sesión: nadie queda encerrado.
class PreparacionDbLocalPage extends ConsumerStatefulWidget {
  const PreparacionDbLocalPage({super.key, required this.estado});

  final EstadoPreparacionDbLocal estado;

  @override
  ConsumerState<PreparacionDbLocalPage> createState() => _PreparacionDbLocalPageState();
}

class _PreparacionDbLocalPageState extends ConsumerState<PreparacionDbLocalPage> {
  final _password = TextEditingController();
  bool _mostrarPassword = false;
  bool _mostrarComoActualizar = false;

  PreparacionDbLocalNotifier get _notifier => ref.read(preparacionDbLocalProvider.notifier);

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _cerrarSesion() async {
    final messenger = ScaffoldMessenger.of(context);
    final resultado = await ref.read(sesionProvider.notifier).cerrarSesion();
    // Si no se pudo, el usuario sigue adentro: se le dice por qué y puede volver a tocar.
    resultado.fold(
      (falla) => messenger.showSnackBar(SnackBar(content: Text(falla.mensaje))),
      (_) => null,
    );
  }

  Future<void> _confirmarEmpezarDeNuevo() async {
    final confirmo = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text(TextosPreparacionDbLocal.empezarDeNuevoTitulo),
        content: const Text(TextosPreparacionDbLocal.empezarDeNuevoDetalle),
        actions: [
          TextButton(
            key: const Key('preparacion_db_cancelar_empezar'),
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('preparacion_db_confirmar_empezar'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(contexto).colorScheme.error,
              foregroundColor: Theme.of(contexto).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Borrar y empezar de nuevo'),
          ),
        ],
      ),
    );
    if (confirmo ?? false) unawaited(_notifier.empezarDeNuevo());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ESPACIO SEGURO',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 8),
              ..._contenido(theme),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _contenido(ThemeData theme) => switch (widget.estado) {
    PreparandoDbLocal(:final paso) => _progreso(theme, paso),
    RecuperandoDbLocal() => _progreso(theme, null, texto: TextosPreparacionDbLocal.recuperando),
    AlmacenSoftwareRechazado() => _rechazado(theme),
    PreparacionDbLocalFallida(:final falla, :final reintentos, :final errorRecuperacion) =>
      switch (falla) {
        FailureAlmacenPocoSeguro() => _consentimiento(theme, falla),
        FailureAlmacenSeguroRecuperable() => _recuperacion(theme, falla, errorRecuperacion),
        FailureEsquemaPosterior() => _esquemaPosterior(theme, falla),
        FailureAlmacenSeguroSinRecuperacion() => _sinRecuperacion(theme, falla, reintentos),
        _ => _falla(theme, falla),
      },
    // Sin sesión o con la DB lista esta pantalla no se muestra; si llega a verse, es de paso.
    SinSesionDbLocal() || DbLocalLista() => _progreso(theme, null),
  };

  List<Widget> _progreso(ThemeData theme, PasoInicializacionDb? paso, {String? texto}) {
    final numero = paso == null ? null : paso.index + 1;
    final leyenda =
        texto ??
        (numero == null
            ? TextosPreparacionDbLocal.preparando
            : TextosPreparacionDbLocal.progreso(numero));
    return [
      _titulo(theme, 'Un momento'),
      const SizedBox(height: 24),
      Semantics(
        liveRegion: true,
        child: Text(
          leyenda,
          key: const Key('preparacion_db_progreso'),
          style: theme.textTheme.bodyLarge,
        ),
      ),
      const SizedBox(height: 16),
      LinearProgressIndicator(value: numero == null ? null : numero / 3, semanticsLabel: leyenda),
    ];
  }

  List<Widget> _consentimiento(ThemeData theme, Failure falla) => [
    _titulo(theme, 'Almacenamiento menos seguro'),
    const SizedBox(height: 16),
    _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
    const SizedBox(height: 8),
    Text(TextosPreparacionDbLocal.preguntaRiesgo, style: theme.textTheme.bodyLarge),
    const SizedBox(height: 24),
    FilledButton(
      key: const Key('preparacion_db_aceptar_riesgo'),
      onPressed: () => unawaited(_notifier.aceptarAlmacenSoftware()),
      child: const Text(TextosPreparacionDbLocal.aceptarRiesgo),
    ),
    const SizedBox(height: 8),
    OutlinedButton(
      key: const Key('preparacion_db_cancelar_riesgo'),
      onPressed: _notifier.rechazarAlmacenSoftware,
      child: const Text('Cancelar'),
    ),
  ];

  List<Widget> _rechazado(ThemeData theme) => [
    _titulo(theme, 'Usá otro celular'),
    const SizedBox(height: 16),
    _mensaje(theme, TextosPreparacionDbLocal.otroCelular, const Key('preparacion_db_mensaje')),
    const SizedBox(height: 24),
    FilledButton(
      key: const Key('preparacion_db_cerrar_sesion'),
      onPressed: () => unawaited(_cerrarSesion()),
      child: const Text('Cerrar sesión'),
    ),
    const SizedBox(height: 8),
    TextButton(
      key: const Key('preparacion_db_continuar_con_este'),
      onPressed: _notifier.revisarAlmacenSoftware,
      child: const Text('Prefiero seguir con este celular'),
    ),
  ];

  List<Widget> _recuperacion(ThemeData theme, Failure falla, Failure? error) {
    final colores = theme.extension<ColoresColportaje>()!;
    final errorTexto = switch (error) {
      FailureValidacion(:final campos) => campos['password'],
      final Failure f => f.mensaje,
      null => null,
    };
    void recuperar() => unawaited(_notifier.recuperarConPassword(_password.text));
    return [
      _titulo(theme, 'Recuperá tus datos'),
      const SizedBox(height: 16),
      _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
      const SizedBox(height: 22),
      Text('CONTRASEÑA', style: theme.textTheme.labelMedium?.copyWith(color: colores.gris)),
      const SizedBox(height: 6),
      TextField(
        key: const Key('preparacion_db_password'),
        controller: _password,
        obscureText: !_mostrarPassword,
        autofillHints: const [AutofillHints.password],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => recuperar(),
        style: theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          errorText: errorTexto,
          errorMaxLines: 3,
          suffixIcon: IconButton(
            tooltip: _mostrarPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
            icon: Icon(
              _mostrarPassword ? Icons.visibility_off : Icons.visibility,
              color: colores.placeholder,
              size: 20,
            ),
            onPressed: () => setState(() => _mostrarPassword = !_mostrarPassword),
          ),
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('preparacion_db_recuperar'),
        onPressed: recuperar,
        child: const Text('Recuperar mis datos'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        key: const Key('preparacion_db_reintentar'),
        onPressed: () => unawaited(_notifier.reintentar()),
        child: const Text('Reintentar sin la contraseña'),
      ),
      const SizedBox(height: 8),
      _botonCerrarSesion(),
    ];
  }

  List<Widget> _sinRecuperacion(ThemeData theme, Failure falla, int reintentos) => [
    _titulo(theme, 'No pudimos abrir tus datos'),
    const SizedBox(height: 16),
    _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
    const SizedBox(height: 8),
    Text(
      reintentos == 0
          ? TextosPreparacionDbLocal.sinRecuperacionQueHacer
          : TextosPreparacionDbLocal.empezarDeNuevoOferta,
      style: theme.textTheme.bodyMedium,
    ),
    const SizedBox(height: 24),
    FilledButton(
      key: const Key('preparacion_db_reintentar'),
      onPressed: () => unawaited(_notifier.reintentar()),
      child: const Text('Reintentar'),
    ),
    // Borrar recién después de un reintento que volvió a fallar (revisión del PR #81, punto 7).
    if (reintentos > 0) ...[
      const SizedBox(height: 8),
      OutlinedButton(
        key: const Key('preparacion_db_empezar_de_nuevo'),
        style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
        onPressed: () => unawaited(_confirmarEmpezarDeNuevo()),
        child: const Text('Empezar de nuevo'),
      ),
    ],
    const SizedBox(height: 8),
    _botonCerrarSesion(),
  ];

  List<Widget> _esquemaPosterior(ThemeData theme, Failure falla) => [
    _titulo(theme, 'Actualizá la app'),
    const SizedBox(height: 16),
    _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
    const SizedBox(height: 24),
    FilledButton(
      key: const Key('preparacion_db_actualizar'),
      onPressed: () => setState(() => _mostrarComoActualizar = true),
      child: const Text('Actualizar'),
    ),
    if (_mostrarComoActualizar) ...[
      const SizedBox(height: 16),
      Semantics(
        liveRegion: true,
        child: Text(
          TextosPreparacionDbLocal.actualizarComo,
          key: const Key('preparacion_db_como_actualizar'),
          style: theme.textTheme.bodyMedium,
        ),
      ),
    ],
  ];

  List<Widget> _falla(ThemeData theme, Failure falla) {
    final queHacer = switch (falla) {
      FailureSinEspacio() => TextosPreparacionDbLocal.sinEspacioQueHacer,
      FailureInesperado() => TextosPreparacionDbLocal.inesperadoQueHacer,
      _ => null,
    };
    return [
      _titulo(theme, switch (falla) {
        FailureSinBloqueoPantalla() => 'Falta el bloqueo de pantalla',
        _ => 'No pudimos preparar tu espacio seguro',
      }),
      const SizedBox(height: 16),
      _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
      if (queHacer != null) ...[
        const SizedBox(height: 8),
        Text(queHacer, style: theme.textTheme.bodyMedium),
      ],
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('preparacion_db_reintentar'),
        onPressed: () => unawaited(_notifier.reintentar()),
        child: const Text('Reintentar'),
      ),
      const SizedBox(height: 8),
      _botonCerrarSesion(),
    ];
  }

  Widget _titulo(ThemeData theme, String texto) => Semantics(
    header: true,
    child: Text(texto, style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26)),
  );

  Widget _mensaje(ThemeData theme, String texto, Key key) => Semantics(
    liveRegion: true,
    child: Text(texto, key: key, style: theme.textTheme.bodyLarge),
  );

  Widget _botonCerrarSesion() => TextButton(
    key: const Key('preparacion_db_cerrar_sesion'),
    onPressed: () => unawaited(_cerrarSesion()),
    child: const Text('Cerrar sesión'),
  );
}
