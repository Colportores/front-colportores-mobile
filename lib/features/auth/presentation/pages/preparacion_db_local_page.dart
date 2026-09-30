import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/config_soporte.dart';
import '../../../../core/dispositivo/abridor_ajustes_sistema.dart';
import '../../../../core/dispositivo/abridor_enlace_externo.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/usecases/inicializar_db_local_use_case.dart';
import '../providers/preparacion_db_local_notifier.dart';
import '../providers/sesion_notifier.dart';
import 'recuperacion_password_page.dart';

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

  static const confirmandoPassword = 'Confirmando tu contraseña…';

  static const passwordIncorrecta = 'Esa no es la contraseña de tu cuenta. Probá de nuevo.';

  /// Lleva a restablecerla (HU-AUTH-004), revisión del PR #130, N1.
  static const olvidePassword = '¿Olvidaste tu contraseña?';

  /// Para `mensajePara`: "Necesitás conexión para confirmar tu contraseña." (#94).
  static const accionConfirmarPassword = 'confirmar tu contraseña.';

  static const otroCelular =
      'No preparamos tu espacio seguro. Para usar la app con la protección completa, iniciá sesión '
      'desde otro celular. Los modelos de los últimos años guardan las claves en un chip aparte, '
      'que es lo más seguro.';

  // --- Vista 13 (propuestas del diseño, en voseo) ---

  static const primerIngreso = 'PRIMER INGRESO EN ESTE TELÉFONO';

  static const espacioSeguro = 'ESPACIO SEGURO';

  static const pasoBloqueo = 'Revisando el bloqueo de pantalla';
  static const pasoClave = 'Creando y guardando tu clave';
  static const pasoBase = 'Creando tu base cifrada';

  /// Apoyo al pie de cada paso en curso (1/3, 2/3, 3/3).
  static const apoyoPaso1 = 'Lo que cargues queda cifrado en este teléfono. Se hace una sola vez.';
  static const apoyoPaso2 =
      'La clave se guarda en el almacenamiento seguro del teléfono. Nadie más la ve.';
  static const apoyoPaso3 = 'Ya casi. Después vas a poder trabajar sin conexión.';

  static const sinBloqueoEyebrow = 'PASO 1 DE 3 · EN PAUSA';
  static const sinBloqueoTitulo = 'Activá el bloqueo de pantalla';
  static const comoConfigurarlo = 'CÓMO CONFIGURARLO';
  static const rutaBloqueo = 'Ajustes > Seguridad > Bloqueo de pantalla';
  static const elegiBloqueo = 'Elegí PIN, patrón o contraseña y volvé a la app.';
  static const yaLoConfigure = 'Ya lo configuré';
  static const abrirAjustes = 'Abrir Ajustes';
  static const abrirAlmacenamiento = 'Abrir almacenamiento';

  /// Propuesta: si la plataforma no pudo abrir los ajustes, el usuario sabe cómo llegar a mano.
  static const noPudimosAbrirAjustes =
      'No pudimos abrir los ajustes. Abrilos a mano desde el menú del teléfono.';

  /// A06: abre el chat de WhatsApp de soporte con el código del error (decisión de Cristian, 30/09).
  static const contactarSoporte = 'Contactar a soporte';

  /// Propuesta: si no hay nada que abra WhatsApp (ni navegador), el usuario sabe a quién escribir y
  /// qué decir.
  static String noPudimosAbrirSoporte(String codigo) =>
      'No pudimos abrir WhatsApp. Escribile a soporte al ${ConfigSoporte.whatsappVisible} y '
      'decile este código: $codigo.';

  /// A09 (vista 13).
  static const interrumpidaTitulo = 'La preparación se cortó';
  static const pasoCortado = '· cortado';
  static const empezarDeNuevoInterrumpida = 'Empezar de nuevo';

  static const consentimientoEyebrow = 'PASO 2 DE 3 · EN PAUSA';
  static const consentimientoTitulo = 'Antes de seguir';
  static const continuar = 'Continuar';
  static const salirSinPreparar = 'Salir sin preparar';

  static const fallaTitulo = 'No se pudo terminar';
  static const fallaEmpezamosDeCero =
      'Si reintentás, empezamos de cero. No se perdió nada: todavía no había datos.';
  static const reintentarDesdeCero = 'Reintentar desde cero';

  static const sinEspacioQueHacer =
      'Liberá espacio borrando fotos, videos o apps que no uses, y volvé a intentarlo.';

  static const actualizacionNecesaria = 'ACTUALIZACIÓN NECESARIA';
  static const actualizaLaApp = 'Actualizá la app';

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
/// Vista 13 del diseño (#222): el progreso con la barra por pasos y la lista de los tres pasos, y
/// el resto de los estados con su eyebrow, título, apoyo y acciones al pie. Los estados que el
/// diseño no dibuja (recuperar con la contraseña, confirmarla, "no pudimos abrir tus datos",
/// "usá otro celular") siguen el mismo esquema. Muestra el [estado] de `PreparacionDbLocalNotifier`:
/// - el progreso, con el paso de 3 de la HU (nunca un spinner mudo);
/// - la advertencia del Keystore por software (S10), con el consentimiento explícito;
/// - la recuperación con la contraseña (ADR-006);
/// - la contraseña de la cuenta, cuando entra con contraseña y la DB quedaría sin envoltorio (una
///   sesión restaurada): se confirma contra el servidor antes de seguir (revisión del PR #130),
///   con "¿Olvidaste tu contraseña?" para quien no la recuerda;
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
  bool _entiendeRiesgo = false;

  /// «Abrir Ajustes» / «Abrir almacenamiento» en curso (guarda contra el doble toque) y, si no se
  /// pudo abrir, el aviso.
  bool _abriendoAjustes = false;
  String? _avisoAjustes;

  /// «Contactar a soporte» en curso (guarda contra el doble toque) y, si no se pudo abrir, el aviso.
  bool _abriendoSoporte = false;
  String? _avisoSoporte;

  @override
  void didUpdateWidget(PreparacionDbLocalPage anterior) {
    super.didUpdateWidget(anterior);
    // Al cambiar de pantalla y volver, nada queda marcado de la vez anterior: el consentimiento
    // hay que darlo de nuevo, y el aviso de los ajustes ya no aplica.
    if (anterior.estado.runtimeType != widget.estado.runtimeType ||
        _falloDistinto(anterior.estado, widget.estado)) {
      _entiendeRiesgo = false;
      _avisoAjustes = null;
      _avisoSoporte = null;
    }
  }

  static bool _falloDistinto(EstadoPreparacionDbLocal a, EstadoPreparacionDbLocal b) =>
      a is PreparacionDbLocalFallida &&
      b is PreparacionDbLocalFallida &&
      a.falla.runtimeType != b.falla.runtimeType;

  Future<void> _abrirAjustes(Future<bool> Function(AbridorAjustesSistema) abrir) async {
    if (_abriendoAjustes) return;
    setState(() {
      _abriendoAjustes = true;
      _avisoAjustes = null;
    });
    var abierta = false;
    try {
      abierta = await abrir(ref.read(abridorAjustesSistemaProvider));
    } on Object {
      // Una falla del abridor es lo mismo que no haber podido abrir: el aviso guía al usuario.
    } finally {
      if (mounted) {
        setState(() {
          _abriendoAjustes = false;
          if (!abierta) _avisoAjustes = TextosPreparacionDbLocal.noPudimosAbrirAjustes;
        });
      }
    }
  }

  Future<void> _contactarSoporte(String codigo) async {
    if (_abriendoSoporte) return;
    setState(() {
      _abriendoSoporte = true;
      _avisoSoporte = null;
    });
    var abierto = false;
    try {
      abierto = await ref
          .read(abridorEnlaceExternoProvider)
          .abrir(ConfigSoporte.enlaceWhatsapp(codigo));
    } on Object {
      // Una falla del abridor es lo mismo que no haber podido abrir: el aviso guía al usuario.
    } finally {
      if (mounted) {
        setState(() {
          _abriendoSoporte = false;
          if (!abierto) _avisoSoporte = TextosPreparacionDbLocal.noPudimosAbrirSoporte(codigo);
        });
      }
    }
  }

  Widget _botonSoporte(String codigo) => OutlinedButton(
    key: const Key('preparacion_db_contactar_soporte'),
    onPressed: _abriendoSoporte ? null : () => unawaited(_contactarSoporte(codigo)),
    child: const Text(TextosPreparacionDbLocal.contactarSoporte),
  );

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

  /// Una cuenta con contraseña que no la recuerda —p. ej. entra siempre con Google— no queda
  /// encerrada acá (revisión del PR #130, N1): la restablece (HU-AUTH-004) con el email de la
  /// sesión. Al guardar la nueva, esa pantalla cierra la sesión, y el login con la nueva protege
  /// la DB.
  void _olvidePassword() {
    final email = ref.read(sesionProvider).value?.email;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => RecuperacionPasswordPage(emailInicial: email)),
      ),
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
    final vista = _vista(theme);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, restricciones) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 60, 28, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (restricciones.maxHeight - 88).clamp(0, double.infinity),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 14,
                    children: [_eyebrow(theme, vista.eyebrow), ...vista.cuerpo],
                  ),
                  const SizedBox(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: vista.acciones,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _eyebrow(ThemeData theme, String texto) {
    final colores = theme.extension<ColoresColportaje>()!;
    return Text(texto, style: theme.textTheme.labelSmall?.copyWith(color: colores.gris));
  }

  _VistaPreparacion _vista(ThemeData theme) => switch (widget.estado) {
    PreparandoDbLocal(:final paso) => _progreso(theme, paso),
    RecuperandoDbLocal() => _progresoSimple(theme, TextosPreparacionDbLocal.recuperando),
    ConfirmandoPasswordDbLocal() => _progresoSimple(
      theme,
      TextosPreparacionDbLocal.confirmandoPassword,
    ),
    AlmacenSoftwareRechazado() => _rechazado(theme),
    PreparacionDbLocalFallida(:final falla, :final reintentos, :final errorRecuperacion) =>
      switch (falla) {
        FailureAlmacenPocoSeguro() => _consentimiento(theme, falla),
        FailureAlmacenSeguroRecuperable() => _recuperacion(theme, falla, errorRecuperacion),
        FailurePasswordParaProteger() => _confirmacionPassword(theme, falla, errorRecuperacion),
        FailureEsquemaPosterior() => _esquemaPosterior(theme, falla),
        FailureAlmacenSeguroSinRecuperacion() => _sinRecuperacion(theme, falla, reintentos),
        FailureSinBloqueoPantalla() => _sinBloqueo(theme, falla),
        FailureSinEspacio() => _sinEspacio(theme, falla),
        final FailurePreparacionInterrumpida f => _interrumpida(theme, f),
        _ => _falla(theme, falla),
      },
    // Sin sesión o con la DB lista esta pantalla no se muestra; si llega a verse, es de paso.
    SinSesionDbLocal() || DbLocalLista() => _progreso(theme, null),
  };

  /// A01/A02/A03: contador n/3 con la barra por pasos y la lista de los tres pasos. Con [paso]
  /// `null` (verificando el equipo) no hay número: el primer paso está en curso.
  _VistaPreparacion _progreso(ThemeData theme, PasoInicializacionDb? paso) {
    final numero = paso == null ? null : paso.index + 1;
    final leyenda = numero == null
        ? TextosPreparacionDbLocal.preparando
        : TextosPreparacionDbLocal.progreso(numero);
    final apoyo = switch (numero) {
      3 => TextosPreparacionDbLocal.apoyoPaso3,
      2 => TextosPreparacionDbLocal.apoyoPaso2,
      _ => TextosPreparacionDbLocal.apoyoPaso1,
    };
    return _VistaPreparacion(
      eyebrow: TextosPreparacionDbLocal.primerIngreso,
      cuerpo: [
        Semantics(
          liveRegion: true,
          child: Text(
            leyenda,
            key: const Key('preparacion_db_progreso'),
            style: _estiloTitulo(context, theme),
          ),
        ),
        _BarraPasos(hechos: numero ?? 0, etiqueta: leyenda),
        const SizedBox(height: 4),
        _ListaPasos(actual: (numero ?? 1) - 1),
        const SizedBox(height: 4),
        _Apoyo(texto: apoyo),
      ],
      acciones: const [],
    );
  }

  /// Recuperando o confirmando la contraseña: un solo texto, con la barra sin porcentaje.
  _VistaPreparacion _progresoSimple(ThemeData theme, String leyenda) => _VistaPreparacion(
    eyebrow: TextosPreparacionDbLocal.espacioSeguro,
    cuerpo: [
      _titulo(theme, 'Un momento'),
      Semantics(
        liveRegion: true,
        child: Text(
          leyenda,
          key: const Key('preparacion_db_progreso'),
          style: theme.textTheme.bodyLarge,
        ),
      ),
      LinearProgressIndicator(semanticsLabel: leyenda),
    ],
    acciones: const [],
  );

  /// A04: sin bloqueo de pantalla. El texto es el de la HU; "cómo configurarlo" es del diseño.
  _VistaPreparacion _sinBloqueo(ThemeData theme, Failure falla) {
    final colores = theme.extension<ColoresColportaje>()!;
    return _VistaPreparacion(
      eyebrow: TextosPreparacionDbLocal.sinBloqueoEyebrow,
      cuerpo: [
        _titulo(theme, TextosPreparacionDbLocal.sinBloqueoTitulo),
        _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
        _Tarjeta(
          hijos: [
            Text(
              TextosPreparacionDbLocal.comoConfigurarlo,
              style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
            ),
            Text(
              TextosPreparacionDbLocal.rutaBloqueo,
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(TextosPreparacionDbLocal.elegiBloqueo, style: theme.textTheme.bodyMedium),
          ],
        ),
        if (_avisoAjustes case final aviso?) _avisoAjustesWidget(theme, aviso),
      ],
      acciones: [
        FilledButton(
          key: const Key('preparacion_db_abrir_ajustes'),
          onPressed: _abriendoAjustes
              ? null
              : () => unawaited(_abrirAjustes((a) => a.abrirSeguridad())),
          child: const Text(TextosPreparacionDbLocal.abrirAjustes),
        ),
        OutlinedButton(
          key: const Key('preparacion_db_reintentar'),
          onPressed: () => unawaited(_notifier.reintentar()),
          child: const Text(TextosPreparacionDbLocal.yaLoConfigure),
        ),
        _botonCerrarSesion(),
      ],
    );
  }

  /// A05: almacenamiento por software. El texto y el botón son los de la HU (S10): «Continuar»
  /// recién se habilita al marcar «Entiendo el riesgo y quiero continuar».
  _VistaPreparacion _consentimiento(ThemeData theme, Failure falla) => _VistaPreparacion(
    eyebrow: TextosPreparacionDbLocal.consentimientoEyebrow,
    cuerpo: [
      _titulo(theme, TextosPreparacionDbLocal.consentimientoTitulo),
      _AvisoAlmacen(texto: falla.mensaje),
    ],
    acciones: [
      CheckboxListTile(
        key: const Key('preparacion_db_entiendo_riesgo'),
        value: _entiendeRiesgo,
        onChanged: (v) => setState(() => _entiendeRiesgo = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: const Text(TextosPreparacionDbLocal.aceptarRiesgo),
      ),
      FilledButton(
        key: const Key('preparacion_db_aceptar_riesgo'),
        onPressed: _entiendeRiesgo ? () => unawaited(_notifier.aceptarAlmacenSoftware()) : null,
        child: const Text(TextosPreparacionDbLocal.continuar),
      ),
      TextButton(
        key: const Key('preparacion_db_cancelar_riesgo'),
        onPressed: _notifier.rechazarAlmacenSoftware,
        child: const Text(TextosPreparacionDbLocal.salirSinPreparar),
      ),
    ],
  );

  _VistaPreparacion _rechazado(ThemeData theme) => _VistaPreparacion(
    eyebrow: TextosPreparacionDbLocal.espacioSeguro,
    cuerpo: [
      _titulo(theme, 'Usá otro celular'),
      _mensaje(theme, TextosPreparacionDbLocal.otroCelular, const Key('preparacion_db_mensaje')),
    ],
    acciones: [
      FilledButton(
        key: const Key('preparacion_db_cerrar_sesion'),
        onPressed: () => unawaited(_cerrarSesion()),
        child: const Text('Cerrar sesión'),
      ),
      TextButton(
        key: const Key('preparacion_db_continuar_con_este'),
        onPressed: _notifier.revisarAlmacenSoftware,
        child: const Text('Prefiero seguir con este celular'),
      ),
    ],
  );

  _VistaPreparacion _recuperacion(ThemeData theme, Failure falla, Failure? error) {
    void recuperar() => unawaited(_notifier.recuperarConPassword(_password.text));
    return _VistaPreparacion(
      eyebrow: TextosPreparacionDbLocal.espacioSeguro,
      cuerpo: [
        _titulo(theme, 'Recuperá tus datos'),
        _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
        ..._campoPassword(theme, error, recuperar),
      ],
      acciones: [
        FilledButton(
          key: const Key('preparacion_db_recuperar'),
          onPressed: recuperar,
          child: const Text('Recuperar mis datos'),
        ),
        OutlinedButton(
          key: const Key('preparacion_db_reintentar'),
          onPressed: () => unawaited(_notifier.reintentar()),
          child: const Text('Reintentar sin la contraseña'),
        ),
        _botonCerrarSesion(),
      ],
    );
  }

  /// Cuenta con contraseña y DB sin envoltorio (revisión del PR #130): se pide la contraseña antes
  /// de seguir. Sin "reintentar": sin la contraseña, el resultado sería el mismo.
  _VistaPreparacion _confirmacionPassword(ThemeData theme, Failure falla, Failure? error) {
    void confirmar() => unawaited(_notifier.confirmarPassword(_password.text));
    return _VistaPreparacion(
      eyebrow: TextosPreparacionDbLocal.espacioSeguro,
      cuerpo: [
        _titulo(theme, 'Confirmá tu contraseña'),
        _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
        ..._campoPassword(theme, error, confirmar),
      ],
      acciones: [
        FilledButton(
          key: const Key('preparacion_db_confirmar_password'),
          onPressed: confirmar,
          child: const Text('Confirmar contraseña'),
        ),
        TextButton(
          key: const Key('preparacion_db_olvide_password'),
          onPressed: _olvidePassword,
          child: const Text(TextosPreparacionDbLocal.olvidePassword),
        ),
        _botonCerrarSesion(),
      ],
    );
  }

  List<Widget> _campoPassword(ThemeData theme, Failure? error, void Function() alEnviar) {
    final colores = theme.extension<ColoresColportaje>()!;
    final errorTexto = switch (error) {
      FailureValidacion(:final campos) => campos['password'],
      FailureCredencialesInvalidas() => TextosPreparacionDbLocal.passwordIncorrecta,
      final FailureSinConexion f => mensajePara(
        f,
        accion: TextosPreparacionDbLocal.accionConfirmarPassword,
      ),
      final Failure f => f.mensaje,
      null => null,
    };
    return [
      Text('CONTRASEÑA', style: theme.textTheme.labelMedium?.copyWith(color: colores.gris)),
      const SizedBox(height: 6),
      TextField(
        key: const Key('preparacion_db_password'),
        controller: _password,
        obscureText: !_mostrarPassword,
        autofillHints: const [AutofillHints.password],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => alEnviar(),
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
    ];
  }

  _VistaPreparacion _sinRecuperacion(
    ThemeData theme,
    Failure falla,
    int reintentos,
  ) => _VistaPreparacion(
    eyebrow: TextosPreparacionDbLocal.espacioSeguro,
    cuerpo: [
      _titulo(theme, 'No pudimos abrir tus datos'),
      _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
      Text(
        reintentos == 0
            ? TextosPreparacionDbLocal.sinRecuperacionQueHacer
            : TextosPreparacionDbLocal.empezarDeNuevoOferta,
        style: theme.textTheme.bodyMedium,
      ),
      if (_avisoSoporte case final aviso?)
        _avisoWidget(theme, aviso, 'preparacion_db_aviso_soporte'),
    ],
    acciones: [
      FilledButton(
        key: const Key('preparacion_db_reintentar'),
        onPressed: () => unawaited(_notifier.reintentar()),
        child: const Text('Reintentar'),
      ),
      // Borrar recién después de un reintento que volvió a fallar (revisión del PR #81, punto 7).
      if (reintentos > 0)
        OutlinedButton(
          key: const Key('preparacion_db_empezar_de_nuevo'),
          style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: () => unawaited(_confirmarEmpezarDeNuevo()),
          child: const Text('Empezar de nuevo'),
        ),
      _botonSoporte(falla.codigo),
      _botonCerrarSesion(),
    ],
  );

  /// A08: la DB es de una versión más nueva. Bloqueante: sin "empezar de nuevo".
  _VistaPreparacion _esquemaPosterior(ThemeData theme, Failure falla) => _VistaPreparacion(
    eyebrow: TextosPreparacionDbLocal.actualizacionNecesaria,
    cuerpo: [
      const _IconoEstado(icono: Icons.arrow_upward),
      _titulo(theme, TextosPreparacionDbLocal.actualizaLaApp),
      _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
      if (_mostrarComoActualizar)
        Semantics(
          liveRegion: true,
          child: Text(
            TextosPreparacionDbLocal.actualizarComo,
            key: const Key('preparacion_db_como_actualizar'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
    ],
    acciones: [
      FilledButton(
        key: const Key('preparacion_db_actualizar'),
        onPressed: () => setState(() => _mostrarComoActualizar = true),
        child: const Text('Actualizar'),
      ),
    ],
  );

  /// A07: sin espacio. El título es el texto de la HU.
  _VistaPreparacion _sinEspacio(ThemeData theme, Failure falla) => _VistaPreparacion(
    eyebrow: TextosPreparacionDbLocal.espacioSeguro,
    cuerpo: [
      const _IconoEstado(icono: Icons.storage_outlined),
      Semantics(
        header: true,
        liveRegion: true,
        child: Text(
          falla.mensaje,
          key: const Key('preparacion_db_mensaje'),
          style: _estiloTitulo(context, theme),
        ),
      ),
      Text(TextosPreparacionDbLocal.sinEspacioQueHacer, style: theme.textTheme.bodyLarge),
      if (_avisoAjustes case final aviso?) _avisoAjustesWidget(theme, aviso),
    ],
    acciones: [
      FilledButton(
        key: const Key('preparacion_db_reintentar'),
        onPressed: () => unawaited(_notifier.reintentar()),
        child: const Text('Reintentar'),
      ),
      OutlinedButton(
        key: const Key('preparacion_db_abrir_almacenamiento'),
        onPressed: _abriendoAjustes
            ? null
            : () => unawaited(_abrirAjustes((a) => a.abrirAlmacenamiento())),
        child: const Text(TextosPreparacionDbLocal.abrirAlmacenamiento),
      ),
      _botonCerrarSesion(),
    ],
  );

  /// A09: la app se cerró a mitad de la preparación. Muestra hasta dónde llegó y ofrece empezar de
  /// nuevo, que descarta lo parcial (nunca se usó) y vuelve a preparar, sin pedir el login.
  _VistaPreparacion _interrumpida(ThemeData theme, FailurePreparacionInterrumpida falla) =>
      _VistaPreparacion(
        eyebrow: TextosPreparacionDbLocal.primerIngreso,
        cuerpo: [
          _titulo(theme, TextosPreparacionDbLocal.interrumpidaTitulo),
          _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
          _ListaPasos(actual: falla.pasoCortado, cortado: true),
        ],
        acciones: [
          FilledButton(
            key: const Key('preparacion_db_empezar_interrumpida'),
            onPressed: () => unawaited(_notifier.empezarDeNuevoInterrumpida()),
            child: const Text(TextosPreparacionDbLocal.empezarDeNuevoInterrumpida),
          ),
        ],
      );

  /// A06: falla del almacenamiento (o inesperada). El texto es el de ADR-006 / la HU.
  _VistaPreparacion _falla(ThemeData theme, Failure falla) => _VistaPreparacion(
    eyebrow: TextosPreparacionDbLocal.espacioSeguro,
    cuerpo: [
      const _IconoEstado(icono: Icons.priority_high),
      _titulo(theme, TextosPreparacionDbLocal.fallaTitulo),
      _mensaje(theme, falla.mensaje, const Key('preparacion_db_mensaje')),
      Text(TextosPreparacionDbLocal.fallaEmpezamosDeCero, style: theme.textTheme.bodyMedium),
      if (_avisoSoporte case final aviso?)
        _avisoWidget(theme, aviso, 'preparacion_db_aviso_soporte'),
    ],
    acciones: [
      FilledButton(
        key: const Key('preparacion_db_reintentar'),
        onPressed: () => unawaited(_notifier.reintentar()),
        child: const Text(TextosPreparacionDbLocal.reintentarDesdeCero),
      ),
      _botonSoporte(falla.codigo),
      _botonCerrarSesion(),
    ],
  );

  Widget _avisoAjustesWidget(ThemeData theme, String texto) =>
      _avisoWidget(theme, texto, 'preparacion_db_aviso_ajustes');

  Widget _avisoWidget(ThemeData theme, String texto, String clave) => Semantics(
    liveRegion: true,
    child: Text(
      texto,
      key: Key(clave),
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
    ),
  );

  Widget _titulo(ThemeData theme, String texto) =>
      Semantics(header: true, child: Text(texto, style: _estiloTitulo(context, theme)));

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

/// Lo que muestra cada estado: el eyebrow y el [cuerpo] arriba, las [acciones] al pie.
final class _VistaPreparacion {
  const _VistaPreparacion({required this.eyebrow, required this.cuerpo, required this.acciones});

  final String eyebrow;
  final List<Widget> cuerpo;
  final List<Widget> acciones;
}

/// La barra por pasos (3 segmentos): los primeros [hechos] van llenos.
class _BarraPasos extends StatelessWidget {
  const _BarraPasos({required this.hechos, required this.etiqueta});

  final int hechos;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    return Semantics(
      label: etiqueta,
      child: ExcludeSemantics(
        child: Row(
          spacing: 6,
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Container(
                  key: Key('preparacion_db_segmento_$i'),
                  height: 5,
                  decoration: BoxDecoration(
                    color: i < hechos ? theme.colorScheme.primary : colores.borde,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Los tres pasos con su estado: hecho, en curso (el [actual]) o pendiente.
///
/// Con [cortado] (A09), el [actual] es el paso en el que se cortó: los anteriores están hechos, él
/// lleva la ✕ y «· cortado», y los que siguen quedan pendientes.
class _ListaPasos extends StatelessWidget {
  const _ListaPasos({required this.actual, this.cortado = false});

  final int actual;
  final bool cortado;

  static const _pasos = [
    TextosPreparacionDbLocal.pasoBloqueo,
    TextosPreparacionDbLocal.pasoClave,
    TextosPreparacionDbLocal.pasoBase,
  ];

  String _estado(int i) => i < actual
      ? 'hecho'
      : i == actual
      ? (cortado ? 'cortado' : 'en curso')
      : 'pendiente';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    return Container(
      key: const Key('preparacion_db_pasos'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.borde),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _pasos.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: colores.borde),
            Semantics(
              container: true,
              excludeSemantics: true,
              label: '${_pasos[i]}, ${_estado(i)}',
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  spacing: 14,
                  children: [
                    SizedBox.square(
                      dimension: 22,
                      child: i < actual
                          ? Icon(Icons.check_circle, size: 22, color: theme.colorScheme.primary)
                          : i == actual
                          ? (cortado
                                ? Icon(Icons.cancel, size: 22, color: theme.colorScheme.error)
                                : const CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.circle_outlined, size: 22, color: colores.gris),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _pasos[i],
                            key: Key('preparacion_db_paso_$i'),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: i == actual ? FontWeight.w600 : FontWeight.w400,
                              color: i > actual ? colores.gris : null,
                            ),
                          ),
                          if (cortado && i == actual)
                            Text(
                              TextosPreparacionDbLocal.pasoCortado,
                              key: const Key('preparacion_db_paso_cortado'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// El candado con la frase de apoyo del paso.
class _Apoyo extends StatelessWidget {
  const _Apoyo({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        Expanded(
          child: Text(
            texto,
            key: const Key('preparacion_db_apoyo'),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta con borde, como las del diseño.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.hijos});

  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.borde),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: hijos),
    );
  }
}

/// El aviso del almacenamiento menos seguro: borde y ícono resaltados.
class _AvisoAlmacen extends StatelessWidget {
  const _AvisoAlmacen({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: esquema.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: esquema.primary, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            ExcludeSemantics(child: Icon(Icons.warning_amber_rounded, color: esquema.primary)),
            Expanded(
              child: Text(
                texto,
                key: const Key('preparacion_db_mensaje'),
                style: _achicarSiHaceFalta(context, theme.textTheme.bodyLarge, 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El cuadrado con el ícono del estado (A06, A07, A08).
class _IconoEstado extends StatelessWidget {
  const _IconoEstado({required this.icono});

  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ExcludeSemantics(
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: esquema.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icono, color: esquema.onPrimaryContainer),
        ),
      ),
    );
  }
}

/// Con texto muy grande (más de 1,5) una palabra larga como «Preparando» o «almacenamiento» no
/// entra en el ancho y se parte a mitad de palabra: se baja el tamaño, como en los botones de la
/// vista 12.
TextStyle? _achicarSiHaceFalta(BuildContext context, TextStyle? estilo, double factor) {
  if (estilo == null || MediaQuery.textScalerOf(context).scale(1) <= 1.5) return estilo;
  return estilo.copyWith(fontSize: (estilo.fontSize ?? 14) * factor);
}

TextStyle? _estiloTitulo(BuildContext context, ThemeData theme) =>
    _achicarSiHaceFalta(context, theme.textTheme.headlineMedium, 0.72);
