import 'dart:async';

import 'package:dartz/dartz.dart' show Right;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../../core/usecases/use_case.dart';
import '../../domain/entities/enlace_recuperacion.dart';
import '../../domain/entities/estado_db_local.dart';
import '../../domain/entities/politica_password.dart';
import '../../domain/usecases/confirmar_recuperacion_password_use_case.dart';
import '../providers/db_local_providers.dart';
import '../providers/recuperacion_password_providers.dart';
import '../providers/sesion_notifier.dart';
import 'recuperacion_password_page.dart';

/// Textos de HU-AUTH-005 (literales de los criterios de aceptación) y de la vista 15.
abstract final class TextosConfirmacionRecuperacion {
  /// "Cambio exitoso": la pantalla de éxito (15-A09) antes de volver al login.
  static const exito = 'Contraseña actualizada. Iniciá sesión.';

  /// "Error - token expirado" (el mismo texto de `FailureEnlaceRecuperacionVencido`).
  static const vencido = 'El enlace expiró. Solicitá uno nuevo.';

  /// Para `mensajePara`, cuando el enlace no se pudo canjear por falta de red: "Necesitás conexión
  /// para abrir el enlace. Cuando tengas señal, volvé a abrirlo desde el correo." (propio, sin
  /// literal en la HU).
  static const accionAbrirEnlace =
      'abrir el enlace. Cuando tengas señal, volvé a abrirlo desde el correo.';

  /// Con DB local en este teléfono (15-A02, decisión de Cristian 30/09): ADR-006, se re-envuelve
  /// la DEK y la DB no se toca.
  static const datosConservados = 'Tus datos guardados en este teléfono se conservan.';

  /// Aviso de las sesiones, con y sin DB local (15-A01 / 15-A02).
  static const sesionesSinBase =
      'Al guardarla se cierran tus sesiones en todos tus teléfonos: vas a entrar de nuevo con la '
      'contraseña nueva.';
  static const sesionesConBase = 'Se cierran tus sesiones en todos tus teléfonos.';

  /// 15-A05.
  static const errorInesperado = 'No pudimos guardar la contraseña. Probá de nuevo.';

  /// 15-A08.
  static const sinConexionTitulo = 'Sin conexión';
  static const sinConexionDetalle =
      'Conectate para guardar la contraseña. No perdés lo que escribiste.';
}

/// Contraseña nueva después de abrir el enlace de recuperación (HU-AUTH-005, #51, vista 15).
///
/// - Con [EnlaceRecuperacion.valido]: el formulario (contraseña nueva y repetida). La política del
///   registro se muestra como lista de requisitos que se tildan al escribir (15-A01/A03), y
///   «Guardar contraseña» se habilita recién cuando cumple y las dos coinciden. Al guardar,
///   `ConfirmarRecuperacionPasswordUseCase` la fija, re-envuelve la DEK si hay DB local (ADR-006,
///   sin tarjetas «Restaurar»/«Borrar»: decisión de Cristian 30/09) y revoca todas las sesiones; la
///   pantalla muestra «Contraseña actualizada. Iniciá sesión.» con el botón al login (15-A09).
/// - Con [EnlaceRecuperacion.vencido] (o si la sesión del enlace vence mientras tanto): "El enlace
///   expiró. Solicitá uno nuevo.", con el botón para pedir otro (HU-AUTH-004) y volver al login.
/// - Con [EnlaceRecuperacion.sinConexion]: que hace falta conexión y que el enlace se vuelve a
///   abrir desde el correo (sigue sirviendo).
///
/// Si el usuario sale sin terminar, se suelta la sesión que abrió el enlace: si no, el próximo
/// arranque lo dejaría adentro sin haber puesto ninguna contraseña. Mientras guarda no se puede
/// salir (el "atrás" dejaría el cambio corriendo sin nadie que muestre cómo terminó).
///
/// El enlace ya usado (15-A07) lo cubre front-colportores-mobile#247: hoy se trata como vencido.
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
  static const _verde = Color(0xFF1F6E3A);
  static const _largoMinimo = 8;

  final _nueva = TextEditingController();
  final _repetida = TextEditingController();

  late bool _vencido = widget.enlace == EnlaceRecuperacion.vencido;
  bool _guardando = false;
  bool _terminado = false;
  bool _sesionSoltada = false;
  bool _hayBaseLocal = false;
  Map<String, String> _erroresCampo = const {};
  String? _errorGeneral;
  bool _sinConexion = false;

  @override
  void initState() {
    super.initState();
    if (widget.enlace == EnlaceRecuperacion.valido) unawaited(_leerBaseLocal());
  }

  @override
  void dispose() {
    _nueva.dispose();
    _repetida.dispose();
    super.dispose();
  }

  /// Si hay DB local en este teléfono (mismo criterio que el caso de uso): solo agrega una línea
  /// al aviso, nunca bloquea el formulario. Si no se puede leer, el aviso queda sin esa línea.
  Future<void> _leerBaseLocal() async {
    final estado = await ref.read(dbLocalRepositoryProvider).estado();
    if (!mounted) return;
    if (estado case Right(value: final EstadoDbLocal e)) {
      final hay = e.archivoExiste && e.marca == MarcaDbLocal.puesta;
      if (hay != _hayBaseLocal) setState(() => _hayBaseLocal = hay);
    }
  }

  bool get _cumpleLargo => _nueva.text.length >= _largoMinimo;
  bool get _cumpleMayuscula => _nueva.text.contains(RegExp('[A-Z]'));
  bool get _cumpleNumero => _nueva.text.contains(RegExp(r'\d'));
  bool get _cumple => PoliticaPassword.validar(_nueva.text) == null;
  bool get _coinciden => _repetida.text.isNotEmpty && _repetida.text == _nueva.text;
  bool get _puedeGuardar => !_guardando && _cumple && _coinciden;

  void _alCambiar() {
    setState(() {
      // Un error de una prueba anterior (p. ej. "distinta de la anterior") ya no aplica al texto
      // nuevo.
      _erroresCampo = const {};
    });
  }

  Future<void> _guardar() async {
    if (!_puedeGuardar) return;
    setState(() {
      _guardando = true;
      _erroresCampo = const {};
      _errorGeneral = null;
      _sinConexion = false;
    });

    final resultado = await ref.read(confirmarRecuperacionPasswordUseCaseProvider)(
      ConfirmarRecuperacionPasswordParams(nueva: _nueva.text, repetida: _repetida.text),
    );
    if (!mounted) return;

    switch (resultado.fold((f) => f, (_) => null)) {
      case null:
        await _terminar();
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
      case FailureSinConexion():
        setState(() {
          _guardando = false;
          _sinConexion = true;
        });
      case FailureInesperado():
        setState(() {
          _guardando = false;
          _errorGeneral = TextosConfirmacionRecuperacion.errorInesperado;
        });
      case final Failure falla:
        setState(() {
          _guardando = false;
          _errorGeneral = falla.mensaje;
        });
    }
  }

  /// La contraseña cambió y las sesiones quedaron revocadas: si la app tenía una sesión iniciada,
  /// también se cierra acá (DB, DEK en memoria), y se muestra la pantalla de éxito (15-A09).
  Future<void> _terminar() async {
    _terminado = true;
    if (ref.read(sesionProvider).value != null) {
      await ref.read(sesionProvider.notifier).cerrarSesion();
    }
    if (!mounted) return;
    setState(() => _guardando = false);
  }

  void _alSalir(bool salio) {
    if (salio) {
      _soltarSesionDelEnlace();
    } else if (_terminado) {
      _irAlLogin();
    }
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
    final formulario = !_vencido && widget.enlace == EnlaceRecuperacion.valido;

    return PopScope(
      // Guardando no se sale; terminado, el atrás lleva al login (no queda el formulario).
      canPop: !_guardando && !_terminado,
      onPopInvokedWithResult: (salio, _) => _alSalir(salio),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_terminado)
                      _exitoContenido(theme)
                    else ...[
                      Column(
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
                            _formularioArriba(theme),
                        ],
                      ),
                      if (formulario) _formularioAbajo(theme),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _encabezado(ThemeData theme, String eyebrow, String titulo, {Key? tituloKey}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: tituloKey != null,
          child: Text(
            titulo,
            key: tituloKey,
            style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
          ),
        ),
      ],
    );
  }

  /// 15-A09.
  Widget _exitoContenido(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 72),
      const Align(
        alignment: Alignment.centerLeft,
        child: ExcludeSemantics(
          child: _Insignia(icono: Icons.check, color: _verde),
        ),
      ),
      const SizedBox(height: 16),
      Semantics(
        liveRegion: true,
        child: Text(
          TextosConfirmacionRecuperacion.exito,
          key: const Key('confirmar_recuperacion_exito'),
          style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
        ),
      ),
      const SizedBox(height: 32),
      FilledButton(
        key: const Key('confirmar_recuperacion_exito_ir_al_login'),
        onPressed: _irAlLogin,
        child: const Text('Ir al login'),
      ),
    ],
  );

  /// 15-A06.
  Widget _vencidoContenido(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Align(
        alignment: Alignment.centerLeft,
        child: ExcludeSemantics(
          child: _Insignia(icono: Icons.hourglass_empty, color: Color(0xFF5B6B82)),
        ),
      ),
      const SizedBox(height: 16),
      _encabezado(
        theme,
        'ENLACE VENCIDO',
        TextosConfirmacionRecuperacion.vencido,
        tituloKey: const Key('confirmar_recuperacion_vencido'),
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
      _encabezado(theme, 'RECUPERAR CONTRASEÑA', 'Sin conexión'),
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

  /// 15-A01 a A05 y A08, parte de arriba: encabezado y campos.
  Widget _formularioArriba(ThemeData theme) {
    final colores = theme.extension<ColoresColportaje>()!;
    final nuevaVacia = _nueva.text.isEmpty;
    final debil = !nuevaVacia && !_cumple;
    final etiquetaNueva = _cumple
        ? 'CONTRASEÑA NUEVA · ✓ CUMPLE LOS REQUISITOS'
        : 'CONTRASEÑA NUEVA';
    final etiquetaRepetida = _coinciden ? 'REPETIR CONTRASEÑA · ✓ COINCIDEN' : 'REPETIR CONTRASEÑA';
    final noCoinciden = _repetida.text.isNotEmpty && _repetida.text != _nueva.text;

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _encabezado(theme, 'RECUPERAR CONTRASEÑA', 'Elegí una contraseña nueva'),
          const SizedBox(height: 22),
          Opacity(
            opacity: _guardando ? .55 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CampoPassword(
                  etiqueta: etiquetaNueva,
                  colorEtiqueta: _cumple
                      ? _verde
                      : debil
                      ? theme.colorScheme.error
                      : colores.gris,
                  campoKey: const Key('confirmar_recuperacion_nueva'),
                  controller: _nueva,
                  errorText: _erroresCampo['password'],
                  habilitado: !_guardando,
                  accionTeclado: TextInputAction.next,
                  alCambiar: _alCambiar,
                ),
                const SizedBox(height: 12),
                _Requisitos(
                  vacia: nuevaVacia,
                  largo: _cumpleLargo,
                  faltan: _largoMinimo - _nueva.text.length,
                  mayuscula: _cumpleMayuscula,
                  numero: _cumpleNumero,
                ),
                const SizedBox(height: 22),
                _CampoPassword(
                  etiqueta: etiquetaRepetida,
                  colorEtiqueta: _coinciden ? _verde : colores.gris,
                  campoKey: const Key('confirmar_recuperacion_repetida'),
                  controller: _repetida,
                  errorText: _erroresCampo['repetida'] ?? (noCoinciden ? _noCoinciden : null),
                  habilitado: !_guardando,
                  accionTeclado: TextInputAction.done,
                  alEnviar: (_) => _guardar(),
                  alCambiar: _alCambiar,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Parte de abajo, pegada al botón: el aviso de las sesiones, o el error.
  Widget _formularioAbajo(ThemeData theme) {
    final colores = theme.extension<ColoresColportaje>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        if (_sinConexion)
          const _AvisoSinConexion()
        else if (_errorGeneral case final error?)
          _AvisoError(mensaje: error)
        else
          _AvisoSesiones(conBase: _hayBaseLocal),
        const SizedBox(height: 12),
        _botonGuardar(theme, colores),
      ],
    );
  }

  static const _noCoinciden = 'Las contraseñas no coinciden';

  Widget _botonGuardar(ThemeData theme, ColoresColportaje colores) {
    final scheme = theme.colorScheme;
    return FilledButton(
      key: const Key('confirmar_recuperacion_guardar'),
      onPressed: _puedeGuardar ? _guardar : null,
      style: FilledButton.styleFrom(
        // 15-A03: gris hasta que cumple; 15-A04: azul con progreso.
        disabledBackgroundColor: _guardando ? scheme.primary : const Color(0xFFE3E7EE),
        disabledForegroundColor: _guardando ? scheme.onPrimary : colores.gris,
      ),
      child: _guardando
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    key: const Key('confirmar_recuperacion_guardando'),
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                const Flexible(child: Text('Guardando…')),
              ],
            )
          : const Text('Guardar contraseña'),
    );
  }
}

/// Círculo con un ícono (éxito, vencido): decorativo, el texto dice lo mismo.
class _Insignia extends StatelessWidget {
  const _Insignia({required this.icono, required this.color});

  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Icon(icono, color: Colors.white, size: 28),
    );
  }
}

/// La política de contraseña como lista que se tilda al escribir (15-A01/A03). Con el campo vacío
/// los renglones quedan neutros: todavía no hay nada mal.
class _Requisitos extends StatelessWidget {
  const _Requisitos({
    required this.vacia,
    required this.largo,
    required this.faltan,
    required this.mayuscula,
    required this.numero,
  });

  final bool vacia;
  final bool largo;
  final int faltan;
  final bool mayuscula;
  final bool numero;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        _Requisito(
          campoKey: const Key('confirmar_recuperacion_req_largo'),
          texto: 'Al menos 8 caracteres',
          extra: largo ? null : '· faltan $faltan',
          cumple: largo,
          neutro: vacia,
        ),
        _Requisito(
          campoKey: const Key('confirmar_recuperacion_req_mayuscula'),
          texto: 'Una mayúscula',
          cumple: mayuscula,
          neutro: vacia,
        ),
        _Requisito(
          campoKey: const Key('confirmar_recuperacion_req_numero'),
          texto: 'Un número',
          cumple: numero,
          neutro: vacia,
        ),
      ],
    );
  }
}

class _Requisito extends StatelessWidget {
  const _Requisito({
    required this.campoKey,
    required this.texto,
    required this.cumple,
    required this.neutro,
    this.extra,
  });

  final Key campoKey;
  final String texto;
  final String? extra;
  final bool cumple;
  final bool neutro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final (marca, color) = cumple
        ? ('✓', _ConfirmarRecuperacionPasswordPageState._verde)
        : neutro
        ? ('○', colores.gris)
        : ('✕', theme.colorScheme.error);

    return Semantics(
      key: campoKey,
      label:
          '$texto${extra == null ? '' : ', ${extra!.replaceAll('· ', '')}'}: '
          '${cumple ? 'cumple' : 'no cumple'}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            marca,
            style: theme.textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: texto,
                children: [
                  if (extra != null)
                    TextSpan(
                      text: ' $extra',
                      style: TextStyle(color: colores.gris),
                    ),
                ],
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Qué pasa con las sesiones (y con los datos de este teléfono, si hay DB local): 15-A01/A02.
class _AvisoSesiones extends StatelessWidget {
  const _AvisoSesiones({required this.conBase});

  final bool conBase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('confirmar_recuperacion_aviso_sesiones'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          if (conBase)
            Text(
              TextosConfirmacionRecuperacion.datosConservados,
              key: const Key('confirmar_recuperacion_datos_conservados'),
              style: theme.textTheme.bodyMedium,
            ),
          Text(
            conBase
                ? TextosConfirmacionRecuperacion.sesionesConBase
                : TextosConfirmacionRecuperacion.sesionesSinBase,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// 15-A05: error genérico, con lo que hay que hacer.
class _AvisoError extends StatelessWidget {
  const _AvisoError({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: theme.colorScheme.error, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 11,
                backgroundColor: theme.colorScheme.error,
                child: const Text(
                  '!',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Expanded(
              child: Text(
                mensaje,
                key: const Key('confirmar_recuperacion_error'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 15-A08: sin conexión al guardar. Lo escrito se conserva y el botón sigue habilitado.
class _AvisoSinConexion extends StatelessWidget {
  const _AvisoSinConexion();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('confirmar_recuperacion_sin_conexion_guardar'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: colores.gris, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            const ExcludeSemantics(
              child: CircleAvatar(
                radius: 11,
                backgroundColor: Color(0xFF2A3A52),
                child: Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    TextosConfirmacionRecuperacion.sinConexionTitulo,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    TextosConfirmacionRecuperacion.sinConexionDetalle,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Campo de contraseña con "Mostrar contraseña" / "Ocultar contraseña" como texto (canvas 15).
class _CampoPassword extends StatefulWidget {
  const _CampoPassword({
    required this.etiqueta,
    required this.colorEtiqueta,
    required this.campoKey,
    required this.controller,
    required this.accionTeclado,
    required this.alCambiar,
    this.habilitado = true,
    this.errorText,
    this.alEnviar,
  });

  final String etiqueta;
  final Color colorEtiqueta;
  final Key campoKey;
  final TextEditingController controller;
  final TextInputAction accionTeclado;
  final VoidCallback alCambiar;
  final bool habilitado;
  final String? errorText;
  final ValueChanged<String>? alEnviar;

  @override
  State<_CampoPassword> createState() => _CampoPasswordState();
}

class _CampoPasswordState extends State<_CampoPassword> {
  bool _mostrar = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.etiqueta,
          style: theme.textTheme.labelMedium?.copyWith(color: widget.colorEtiqueta),
        ),
        const SizedBox(height: 6),
        TextField(
          key: widget.campoKey,
          controller: widget.controller,
          enabled: widget.habilitado,
          obscureText: !_mostrar,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: widget.accionTeclado,
          onChanged: (_) => widget.alCambiar(),
          onSubmitted: widget.alEnviar,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            errorText: widget.errorText,
            errorMaxLines: 3,
            constraints: const BoxConstraints(minHeight: 48),
            suffixIcon: TextButton(
              onPressed: widget.habilitado ? () => setState(() => _mostrar = !_mostrar) : null,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(_mostrar ? 'Ocultar contraseña' : 'Mostrar contraseña'),
            ),
          ),
        ),
      ],
    );
  }
}
