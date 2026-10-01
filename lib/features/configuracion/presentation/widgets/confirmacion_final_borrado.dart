import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/domain/entities/resumen_datos_locales.dart';
import '../../../auth/domain/services/frase_borrado.dart';
import '../../../auth/domain/usecases/verificar_password_borrado_use_case.dart';
import '../../../auth/presentation/providers/borrado_providers.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../pages/borrar_datos_locales_page.dart' show TextosBorrado;
import '../providers/nombre_cuenta_provider.dart';

/// Segunda parte de «Borrar datos locales» (vista 19, artboards 05, 05b y 09): confirmación final a
/// pantalla completa, sin la barra inferior. Pide la frase `BORRAR-DATOS-<NOMBRE>-<APELLIDO>` y,
/// si hay una DEK envuelta con contraseña, la contraseña (se valida en el teléfono, sin red).
///
/// Con backup en Drive, también elige si se borra. Sin conexión esa opción queda deshabilitada
/// ("requiere conexión") y el resto sigue: los datos se borran igual.
class ConfirmacionFinalBorrado extends ConsumerStatefulWidget {
  const ConfirmacionFinalBorrado({
    super.key,
    required this.resumen,
    required this.onCancelar,
    required this.onConfirmado,
  });

  final ResumenDatosLocales resumen;

  /// "Cancelar": no se borra nada y se vuelve a Configuración.
  final VoidCallback onCancelar;

  /// Frase y contraseña correctas: pasa a borrar, con la elección del backup en Drive.
  final void Function({required bool incluirBackupDrive}) onConfirmado;

  @override
  ConsumerState<ConfirmacionFinalBorrado> createState() => _ConfirmacionFinalBorradoState();
}

class _ConfirmacionFinalBorradoState extends ConsumerState<ConfirmacionFinalBorrado> {
  final _frase = TextEditingController();
  final _password = TextEditingController();

  RequisitosBorrado? _requisitos;
  Failure? _falloRequisitos;
  bool _incluirDrive = false;
  bool _mostrarPassword = false;
  bool _verificando = false;
  bool _sinConexion = false;

  String? _errorFrase;
  String? _errorPassword;
  Failure? _falloGeneral;

  /// Fin de la espera por intentos agotados, mientras corre.
  DateTime? _bloqueadoHasta;
  Timer? _finDeEspera;
  StreamSubscription<TipoConexion>? _escuchaConexion;

  @override
  void initState() {
    super.initState();
    unawaited(_cargarRequisitos());
    unawaited(_escucharConexion());
  }

  @override
  void dispose() {
    _finDeEspera?.cancel();
    unawaited(_escuchaConexion?.cancel());
    _frase.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _escucharConexion() async {
    final monitor = ref.read(monitorConectividadProvider);
    try {
      final actual = await monitor.actual();
      if (!mounted) return;
      _fijarConexion(actual);
      _escuchaConexion = monitor.cambios.listen((c) {
        if (mounted) _fijarConexion(c);
      });
    } on Object {
      // Sin saber, se asume conexión: borrar el backup solo falla con un aviso, nunca en silencio.
    }
  }

  void _fijarConexion(TipoConexion tipo) => setState(() {
    _sinConexion = tipo == TipoConexion.sinConexion;
    // Lo elegido ya no se puede hacer: vuelve a la opción que no pierde nada.
    if (_sinConexion) _incluirDrive = false;
  });

  Future<void> _cargarRequisitos() async {
    setState(() => _falloRequisitos = null);
    final r = await ref.read(verificarPasswordBorradoUseCaseProvider).requisitos();
    if (!mounted) return;
    r.fold((falla) => setState(() => _falloRequisitos = falla), (requisitos) {
      setState(() => _requisitos = requisitos);
      _programarFinDeEspera(requisitos.estadoIntentos.bloqueadoHasta);
      // Entra con la espera en curso (cerró la app o salió y volvió): lo dice desde el principio.
      if (_enEspera) setState(() => _errorPassword = _textoEspera);
    });
  }

  void _programarFinDeEspera(DateTime? hasta) {
    _finDeEspera?.cancel();
    _bloqueadoHasta = hasta;
    if (hasta == null) return;
    final falta = hasta.difference(ref.read(relojBorradoProvider)());
    if (falta <= Duration.zero) {
      _bloqueadoHasta = null;
      return;
    }
    _finDeEspera = Timer(falta, () {
      if (!mounted) return;
      setState(() {
        _bloqueadoHasta = null;
        _errorPassword = null;
      });
    });
  }

  bool get _enEspera {
    final hasta = _bloqueadoHasta;
    return hasta != null && ref.read(relojBorradoProvider)().isBefore(hasta);
  }

  String get _textoEspera {
    final hasta = _bloqueadoHasta!;
    final falta = hasta.difference(ref.read(relojBorradoProvider)());
    final minutos = (falta.inSeconds / 60).ceil().clamp(1, 5);
    return minutos == 1
        ? 'Demasiados intentos. Probá nuevamente en 1 minuto.'
        : 'Demasiados intentos. Probá nuevamente en $minutos minutos.';
  }

  Future<void> _confirmar(String esperada) async {
    // Doble toque: mientras Argon2id corre (1 a 2 s) no se entra de nuevo.
    if (_verificando) return;
    final requisitos = _requisitos;
    if (requisitos == null) return;

    if (!FraseBorrado.coincide(_frase.text, esperada)) {
      setState(() {
        _errorFrase = TextosBorrado.fraseNoCoincide;
        _falloGeneral = null;
      });
      return;
    }
    setState(() {
      _errorFrase = null;
      _errorPassword = null;
      _falloGeneral = null;
    });

    if (requisitos.pidePassword) {
      setState(() => _verificando = true);
      final r = await ref.read(verificarPasswordBorradoUseCaseProvider)(
        VerificarPasswordBorradoParams(password: _password.text),
      );
      if (!mounted) return;
      if (r.isRight()) {
        // Sigue "verificando" hasta que la pantalla cambia: ningún segundo toque entra.
        widget.onConfirmado(incluirBackupDrive: _incluirDrive);
        return;
      }
      final falla = r.swap().getOrElse(() => const FailureInesperado());
      setState(() {
        _verificando = false;
        switch (falla) {
          case FailureBorradoBloqueado(:final hasta):
            _password.clear();
            _programarFinDeEspera(hasta);
            _errorPassword = _textoEspera;
          case FailurePasswordBorradoIncorrecta(:final intentosRestantes):
            _password.clear();
            _errorPassword = TextosBorrado.passwordIncorrecta(intentosRestantes);
          case FailureValidacion(:final campos):
            _errorPassword = campos['password'] ?? TextosBorrado.ingresaPassword;
          default:
            _falloGeneral = falla;
        }
      });
      return;
    }

    widget.onConfirmado(incluirBackupDrive: _incluirDrive);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esperada = FraseBorrado.para(ref.watch(nombreCuentaProvider));
    final requisitos = _requisitos;

    final Widget cuerpo;
    if (_falloRequisitos != null) {
      cuerpo = _Aviso(
        key: const Key('borrar_datos_error_requisitos'),
        icono: Icons.error_outline,
        texto: _falloRequisitos!.mensaje,
        accion: OutlinedButton(
          key: const Key('borrar_datos_reintentar_requisitos'),
          onPressed: _cargarRequisitos,
          child: const Text('Reintentar'),
        ),
      );
    } else if (requisitos == null) {
      cuerpo = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(key: Key('borrar_datos_requisitos'))),
      );
    } else if (esperada == null) {
      cuerpo = const _Aviso(
        key: Key('borrar_datos_sin_nombre'),
        icono: Icons.info_outline,
        texto: TextosBorrado.sinNombre,
      );
    } else {
      cuerpo = _formulario(theme, colores, esperada, requisitos);
    }

    return Column(
      key: const Key('borrar_datos_confirmacion'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(TextosBorrado.subtituloConfirmacion, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        cuerpo,
        const SizedBox(height: 12),
        TextButton(
          key: const Key('borrar_datos_cancelar'),
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _verificando ? null : widget.onCancelar,
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _formulario(
    ThemeData theme,
    ColoresColportaje colores,
    String esperada,
    RequisitosBorrado requisitos,
  ) {
    final coincide = _frase.text.isNotEmpty && FraseBorrado.coincide(_frase.text, esperada);
    final enEspera = _enEspera;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.resumen.hayBackupEnDrive) ...[
          Text('TU BACKUP EN DRIVE', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          _Opcion(
            key: const Key('borrar_datos_conservar_drive'),
            texto: TextosBorrado.conservarDrive,
            seleccionada: !_incluirDrive,
            onTap: _verificando ? null : () => setState(() => _incluirDrive = false),
          ),
          _Opcion(
            key: const Key('borrar_datos_incluir_drive'),
            texto: _sinConexion
                ? '${TextosBorrado.borrarDrive} · requiere conexión'
                : TextosBorrado.borrarDrive,
            seleccionada: _incluirDrive,
            bloqueada: _sinConexion,
            onTap: _verificando || _sinConexion ? null : () => setState(() => _incluirDrive = true),
          ),
          const SizedBox(height: 16),
        ],
        Text('Escribí ${esperada.toUpperCase()}', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        TextField(
          key: const Key('borrar_datos_frase'),
          controller: _frase,
          enabled: !_verificando,
          // Hay que escribirla, no pegarla: sin menú de selección ni de portapapeles.
          enableInteractiveSelection: false,
          contextMenuBuilder: (context, editableTextState) => const SizedBox.shrink(),
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          textInputAction: requisitos.pidePassword ? TextInputAction.next : TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(esperada.length + 20)],
          onChanged: (_) => setState(() => _errorFrase = null),
          onSubmitted: requisitos.pidePassword ? null : (_) => _confirmar(esperada),
          decoration: InputDecoration(
            errorText: _errorFrase,
            errorMaxLines: 3,
            constraints: const BoxConstraints(minHeight: 48),
            helperText: coincide ? '✓ Coincide' : null,
            helperStyle: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        if (requisitos.pidePassword) ...[
          const SizedBox(height: 16),
          Text('TU CONTRASEÑA', style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          TextField(
            key: const Key('borrar_datos_password'),
            controller: _password,
            enabled: !_verificando && !enEspera,
            obscureText: !_mostrarPassword,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _errorPassword = enEspera ? _errorPassword : null),
            onSubmitted: (_) => _confirmar(esperada),
            decoration: InputDecoration(
              errorText: _errorPassword,
              errorMaxLines: 3,
              constraints: const BoxConstraints(minHeight: 48),
              suffixIcon: IconButton(
                key: const Key('borrar_datos_mostrar_password'),
                tooltip: _mostrarPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                onPressed: () => setState(() => _mostrarPassword = !_mostrarPassword),
                icon: Icon(_mostrarPassword ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            TextosBorrado.sinPassword,
            key: const Key('borrar_datos_sin_password'),
            style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
          ),
        ],
        if (_sinConexion) ...[
          const SizedBox(height: 12),
          const _Aviso(
            key: Key('borrar_datos_sin_conexion'),
            icono: Icons.cloud_off_outlined,
            texto: TextosBorrado.sinConexion,
          ),
        ],
        if (_falloGeneral != null) ...[
          const SizedBox(height: 12),
          _Aviso(
            key: const Key('borrar_datos_error_confirmacion'),
            icono: Icons.error_outline,
            texto: _falloGeneral!.mensaje,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('borrar_datos_confirmar'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _verificando || enEspera ? null : () => _confirmar(esperada),
          child: _verificando
              ? SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    key: const Key('borrar_datos_verificando'),
                    strokeWidth: 2.5,
                    color: theme.colorScheme.onError,
                    semanticsLabel: 'Verificando',
                  ),
                )
              : const Text(TextosBorrado.confirmarFinal),
        ),
      ],
    );
  }
}

/// Opción excluyente (se evita `RadioListTile` por el cambio de API de `RadioGroup`; la semántica
/// es la misma). [bloqueada] la muestra con candado y sin poder elegirla.
class _Opcion extends StatelessWidget {
  const _Opcion({
    super.key,
    required this.texto,
    required this.seleccionada,
    required this.onTap,
    this.bloqueada = false,
  });

  final String texto;
  final bool seleccionada;
  final bool bloqueada;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: seleccionada,
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      selected: seleccionada,
      enabled: onTap != null,
      leading: Icon(
        bloqueada
            ? Icons.lock_outline
            : seleccionada
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      title: Text(texto),
      onTap: onTap,
    ),
  );
}

class _Aviso extends StatelessWidget {
  const _Aviso({super.key, required this.icono, required this.texto, this.accion});

  final IconData icono;
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icono, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Text(texto, style: theme.textTheme.bodyMedium)),
          ],
        ),
        if (accion != null) ...[const SizedBox(height: 12), accion!],
      ],
    );
  }
}
