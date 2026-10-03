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

  /// 15-A06, el único enlace que no sirve: Supabase manda el mismo `otp_expired` para uno vencido y
  /// para uno ya usado, y el error llega sin el enlace, así que la app no adivina cuál de los dos
  /// es. Dice las dos cosas y guía (decisión de Cristian, 02/10, sobre «Error - token expirado» y
  /// «Error - token reutilizado» de HU-AUTH-005). El mismo texto de
  /// `FailureEnlaceRecuperacionVencido`.
  static const vencido = 'Este enlace ya no sirve: venció o ya se usó. Solicitá uno nuevo.';

  /// Rótulo de 15-A06: no afirma «vencido» (decisión del orquestador, 02/10).
  static const rotuloEnlaceNoValido = 'ENLACE NO VÁLIDO';

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

  /// La contraseña cambió pero la sesión que estaba abierta en este teléfono no se pudo cerrar
  /// (decisión de Cristian, 02/10): dice qué pasó y la salida.
  static const exitoSinCerrarSesion =
      'Cambiaste la contraseña, pero no pudimos cerrar la sesión en este teléfono. Cerrala desde '
      'Configuración.';

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
/// - Con [EnlaceRecuperacion.vencido] (o si la sesión del enlace vence mientras tanto): 15-A06,
///   «Este enlace ya no sirve: venció o ya se usó. Solicitá uno nuevo.» con el rótulo «ENLACE NO
///   VÁLIDO», el botón para pedir otro (HU-AUTH-004) y volver al login. Una sola pantalla para el
///   enlace vencido y el ya usado: Supabase los rechaza igual y la app no adivina cuál es (decisión
///   de Cristian, 02/10; el canvas dibuja además 15-A07 «ya fue utilizado», que se quitó).
/// - Con [EnlaceRecuperacion.sinConexion]: que hace falta conexión y que el enlace se vuelve a
///   abrir desde el correo (sigue sirviendo).
///
/// Si el usuario sale sin terminar, se suelta la sesión que abrió el enlace: si no, el próximo
/// arranque lo dejaría adentro sin haber puesto ninguna contraseña. Mientras guarda no se puede
/// salir (el "atrás" dejaría el cambio corriendo sin nadie que muestre cómo terminó).
///
/// 15-A06 es como el canvas: el contenido centrado con el anillo arriba, las salidas al pie y
/// **sin flecha de atrás** (se sale por los botones o por el atrás del sistema).
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
  static const _oro = Color(0xFFA98330);

  final _nueva = TextEditingController();
  final _repetida = TextEditingController();

  late bool _vencido = widget.enlace == EnlaceRecuperacion.vencido;
  bool _guardando = false;
  bool _terminado = false;

  /// La contraseña cambió pero la sesión abierta en la app no se pudo cerrar.
  bool _cierreFallido = false;
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

  bool get _cumpleLargo => PoliticaPassword.cumpleLargo(_nueva.text);
  bool get _cumpleMayuscula => PoliticaPassword.tieneMayuscula(_nueva.text);
  bool get _cumpleNumero => PoliticaPassword.tieneNumero(_nueva.text);
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

  /// «Listo» del teclado: si todavía no se puede guardar, dice qué falta en vez de no hacer nada.
  void _enviarDesdeTeclado() {
    if (_guardando) return;
    if (_puedeGuardar) {
      unawaited(_guardar());
      return;
    }
    setState(() {
      if (_nueva.text.isEmpty) {
        _erroresCampo = const {'password': _faltaNueva};
      } else if (!_cumple) {
        _erroresCampo = const {'password': _faltaRequisitos};
      } else if (_repetida.text.isEmpty) {
        _erroresCampo = const {'repetida': _faltaRepetida};
      }
      // Si no coinciden, el campo ya lo dice.
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
    var cierreFallido = false;
    try {
      if (ref.read(sesionProvider).value != null) {
        // El cierre lo hace la app, no la colportora: el correo de la última cuenta se conserva y
        // el login lo trae puesto (se borra solo con «Cerrar sesión» o al borrar los datos).
        final cierre = await ref.read(sesionProvider.notifier).cerrarSesion(conservarCorreo: true);
        cierreFallido = cierre.isLeft();
      }
    } on Object {
      // La contraseña ya cambió: el éxito se muestra igual; un cierre local que falló no puede
      // dejar la pantalla trabada en «Guardando…». Si lanzó pero la sesión quedó cerrada (el
      // notifier la cierra igual), no hay nada que avisar.
      cierreFallido = ref.read(sesionProvider).value != null;
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
          _cierreFallido = cierreFallido;
        });
      }
    }
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
    // 15-A06 tiene su propio armado: centrado, sin flecha, con las salidas al pie.
    final enlaceInservible = !_terminado && _vencido;

    return PopScope(
      // Guardando no se sale; terminado, el atrás lleva al login (no queda el formulario).
      canPop: !_guardando && !_terminado,
      onPopInvokedWithResult: (salio, _) => _alSalir(salio),
      child: Scaffold(
        body: SafeArea(
          child: enlaceInservible
              ? _enlaceInservible(theme)
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: paddingHorizontal,
                      vertical: 24,
                    ),
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
                                    onPressed: _guardando
                                        ? null
                                        : () => Navigator.of(context).maybePop(),
                                    icon: const Icon(Icons.arrow_back),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (widget.enlace == EnlaceRecuperacion.sinConexion)
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

  /// 15-A06 (el enlace no sirve: venció o ya se usó), como el canvas: el contenido centrado en lo
  /// que sobra encima de las salidas, que van pegadas al pie. Sin flecha de atrás.
  Widget _enlaceInservible(ThemeData theme) {
    final colores = theme.extension<ColoresColportaje>()!;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Con spaceBetween, el del medio queda centrado entre el borde de arriba y las salidas.
              const SizedBox.shrink(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
                child: _vencidoContenido(theme, colores),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: _vencidoSalidas(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _encabezado(ThemeData theme, String eyebrow, String titulo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text(titulo, style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26)),
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
        header: true,
        liveRegion: true,
        child: Text(
          // Con la sesión todavía abierta, «Iniciá sesión» sería falso: se dice qué pasó y qué hacer.
          _cierreFallido
              ? TextosConfirmacionRecuperacion.exitoSinCerrarSesion
              : TextosConfirmacionRecuperacion.exito,
          key: const Key('confirmar_recuperacion_exito'),
          style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
        ),
      ),
      const SizedBox(height: 32),
      FilledButton(
        key: const Key('confirmar_recuperacion_exito_ir_al_login'),
        onPressed: _irAlLogin,
        style: _estiloTextoGrande(context),
        child: Text(_cierreFallido ? 'Volver al inicio' : 'Ir al login'),
      ),
    ],
  );

  /// Título de 15-A06: serif de 28 con interlineado 1,2, como el canvas.
  TextStyle? _tituloEnlace(ThemeData theme) =>
      theme.textTheme.headlineMedium?.copyWith(fontSize: 28, height: 1.2);

  /// 15-A06, la parte del medio: anillo dorado con el reloj de arena, el rótulo y el texto.
  Widget _vencidoContenido(ThemeData theme, ColoresColportaje colores) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 16,
    children: [
      _Anillo(
        icono: Icons.hourglass_empty,
        colorBorde: _oro,
        colorIcono: theme.colorScheme.onSurface,
      ),
      Text(
        TextosConfirmacionRecuperacion.rotuloEnlaceNoValido,
        style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
      ),
      Semantics(
        header: true,
        liveRegion: true,
        child: Text(
          TextosConfirmacionRecuperacion.vencido,
          key: const Key('confirmar_recuperacion_vencido'),
          style: _tituloEnlace(theme),
        ),
      ),
    ],
  );

  /// 15-A06, al pie: pedir un enlace nuevo y volver al login.
  Widget _vencidoSalidas(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 10,
    children: [
      FilledButton(
        key: const Key('confirmar_recuperacion_pedir_otro'),
        onPressed: _pedirOtroEnlace,
        style: _estiloTextoGrande(context),
        child: const Text('Solicitar un enlace nuevo'),
      ),
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
        style: _estiloTextoGrande(context),
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
            // 15-A04: el canvas atenúa al 55 %, que da 2,4:1 en las etiquetas; con 95 % llegan a
            // 4,5:1 (decisión de Cristian, 02/10). El «Guardando…» lo dice además el botón.
            opacity: _guardando ? .95 : 1,
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
                  faltan: PoliticaPassword.largoMinimo - PoliticaPassword.largo(_nueva.text),
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
                  alEnviar: (_) => _enviarDesdeTeclado(),
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

  /// Con texto grande la etiqueta pasa a dos líneas y los extremos de píldora la recortan: ahí el
  /// radio baja y el relleno lateral sube (igual que la vista 13).
  ButtonStyle? _estiloTextoGrande(BuildContext context) {
    if (!_textoGrande(context)) return null;
    return FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  static const _noCoinciden = 'Las contraseñas no coinciden';
  static const _faltaNueva = 'Escribí la contraseña nueva.';
  static const _faltaRequisitos = 'Todavía no cumple los requisitos de abajo.';
  static const _faltaRepetida = 'Repetí la contraseña para confirmar que está bien escrita.';

  Widget _botonGuardar(ThemeData theme, ColoresColportaje colores) {
    final scheme = theme.colorScheme;
    return FilledButton(
      key: const Key('confirmar_recuperacion_guardar'),
      onPressed: _puedeGuardar ? _guardar : null,
      style: FilledButton.styleFrom(
        // 15-A03: gris hasta que cumple; 15-A04: azul con progreso.
        disabledBackgroundColor: _guardando ? scheme.primary : const Color(0xFFE3E7EE),
        disabledForegroundColor: _guardando ? scheme.onPrimary : colores.gris,
      ).merge(_estiloTextoGrande(context)),
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
                Flexible(
                  child: Text('Guardando…', style: TextStyle(color: scheme.onPrimary)),
                ),
              ],
            )
          : const Text('Guardar contraseña'),
    );
  }
}

/// Círculo lleno con un ícono (éxito, 15-A09): decorativo, el texto dice lo mismo.
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

/// Anillo con un ícono adentro (enlace que no sirve, 15-A06): borde de 1,5 y sin relleno, como el
/// canvas. Decorativo: el título dice lo mismo.
class _Anillo extends StatelessWidget {
  const _Anillo({required this.icono, required this.colorBorde, required this.colorIcono});

  final IconData icono;
  final Color colorBorde;
  final Color colorIcono;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colorBorde, width: 1.5),
        ),
        child: Icon(icono, color: colorIcono, size: 22),
      ),
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

/// Texto a partir de ~143 %: los botones píldora y el «Mostrar contraseña» como texto no entran.
bool _textoGrande(BuildContext context) => MediaQuery.textScalerOf(context).scale(14) > 20;

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

  void _alternar() => setState(() => _mostrar = !_mostrar);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final etiquetaMostrar = _mostrar ? 'Ocultar contraseña' : 'Mostrar contraseña';

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
            // Con texto grande, el texto «Mostrar contraseña» se come el campo: pasa a ícono con
            // tooltip (como en el login) y deja ver lo que se escribe.
            suffixIcon: _textoGrande(context)
                ? IconButton(
                    tooltip: etiquetaMostrar,
                    onPressed: widget.habilitado ? _alternar : null,
                    icon: Icon(_mostrar ? Icons.visibility_off : Icons.visibility),
                  )
                : TextButton(
                    onPressed: widget.habilitado ? _alternar : null,
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: Text(etiquetaMostrar),
                  ),
          ),
        ),
      ],
    );
  }
}
