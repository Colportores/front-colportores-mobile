import 'dart:async';

import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../auth/domain/entities/estado_cuenta.dart';
import '../../../auth/domain/entities/resultado_cierre_sesion.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/providers/estado_cuenta_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../../inicio/presentation/widgets/barra_pestanas_inicio.dart';
import '../../../notificaciones/presentation/pages/notificaciones_page.dart';
import '../../../notificaciones/presentation/widgets/aviso_notificaciones.dart';
import '../../../respaldo/presentation/providers/respaldo_drive_providers.dart';
import '../../../respaldo/presentation/textos_respaldo_drive.dart';
import '../../../respaldo/presentation/widgets/hojas_drive.dart';
import '../../../respaldo/presentation/widgets/seccion_respaldo_drive.dart';
import '../../../tiles/presentation/pages/mapas_offline_page.dart';
import '../../../tiles/presentation/providers/resumen_mapas_providers.dart';
import '../../../tiles/presentation/textos_mapas_offline.dart';
import '../providers/aviso_privacidad_providers.dart';
import '../providers/nombre_cuenta_provider.dart';
import '../widgets/hoja_cerrar_sesion.dart';
import 'borrar_datos_locales_page.dart';

/// Configuración de la cuenta en este teléfono (vista 16 del diseño): «Tu cuenta», «Privacidad y
/// datos» con el borrado de datos locales (HU-AUTH-010) y «Cerrar sesión» al pie (HU-AUTH-006),
/// con la confirmación en una hoja inferior. La sección «Mapas» lleva a «Mapas offline» (vista 35) y
/// se oculta con la cuenta pendiente de asignación. La barra de pestañas es la de la pantalla
/// principal; con una cuenta que todavía no accede a los módulos de campo no se muestra (vista 18
/// la arma bloqueada). La sección «Respaldo» muestra la fila «Cuenta Drive» (HU-SYNC-004): conectar,
/// ver y desconectar el respaldo en el Google Drive de la persona.
class ConfiguracionPage extends ConsumerStatefulWidget {
  const ConfiguracionPage({super.key});

  /// La ruta de la pantalla. Todavía no hay router (go_router llega con el mapa en Sprint 5). Si
  /// se sale por la barra de pestañas devuelve la pestaña elegida; con «volver», `null`.
  static Route<PestanaInicio> ruta() =>
      MaterialPageRoute<PestanaInicio>(builder: (_) => const ConfiguracionPage());

  @override
  ConsumerState<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends ConsumerState<ConfiguracionPage>
    with CierraSusAvisos<ConfiguracionPage> {
  /// Mientras se cuentan las operaciones pendientes antes de abrir la hoja.
  bool _revisando = false;

  /// Mientras «Reintentar» del aviso de módulo bloqueado consulta la cuenta: una sola consulta
  /// aunque se toque dos veces (#278).
  bool _reintentandoCuenta = false;

  /// Se está guardando «Mostrar el aviso de privacidad». Es un campo: corta el segundo toque aunque
  /// llegue antes de que se vuelva a dibujar.
  bool _cambiandoAviso = false;

  /// Se está abriendo una hoja del respaldo en Drive. Es un campo: corta el segundo toque aunque
  /// llegue antes de que la hoja termine de abrirse.
  bool _abriendoHojaDrive = false;

  /// «Conectar» / «Reconectar» de la fila «Cuenta Drive» (HU-SYNC-004): la hoja explica que los
  /// archivos van cifrados y lleva a la pantalla de Google. Al volver avisa cómo salió.
  Future<void> _conectarDrive() async {
    if (_abriendoHojaDrive) return;
    _abriendoHojaDrive = true;
    final avisoCancelado = ref.read(avisoDriveCanceladoProvider.notifier)..ocultar();
    try {
      final resultado = await mostrarHojaConectarDrive(context);
      if (!mounted) return;
      switch (resultado) {
        case DriveQuedoConectado(:final primerRespaldoHecho):
          final mensajero = ScaffoldMessenger.of(context)..clearSnackBars();
          recordarAviso(
            mensajero.showSnackBar(
              SnackBar(
                key: const Key('configuracion_drive_conectado'),
                content: Text(
                  primerRespaldoHecho
                      ? TextosRespaldoDrive.exitoConPrimerRespaldo
                      : TextosRespaldoDrive.exitoSinPrimerRespaldo,
                ),
              ),
            ),
          );
        case DriveNoQuedoConectado():
          avisoCancelado.mostrar();
        case DriveOcupado() || null:
          break;
      }
    } finally {
      _abriendoHojaDrive = false;
    }
  }

  /// Tocar la fila con Drive conectado: la hoja para desconectar.
  Future<void> _desconectarDrive() async {
    if (_abriendoHojaDrive) return;
    _abriendoHojaDrive = true;
    try {
      await mostrarHojaDesconectarDrive(context);
    } finally {
      _abriendoHojaDrive = false;
    }
  }

  /// «Mostrar el aviso de privacidad» (decisión de Cristian, 23/10, «Aviso privado», #445): enciende
  /// o apaga el aviso «Estos datos solo viven en tu celular…» de esta cuenta, el mismo del alta de
  /// persona y de las notas. Si no se pudo guardar, el interruptor queda como estaba y lo dice.
  Future<void> _cambiarAvisoDePrivacidad(String cuentaId, {required bool mostrar}) async {
    if (_cambiandoAviso) return;
    _cambiandoAviso = true;
    setState(() {});
    var guardado = false;
    try {
      final notificador = ref.read(avisoPrivacidadOcultoProvider(cuentaId).notifier);
      guardado = await (mostrar ? notificador.mostrar() : notificador.ocultar());
    } finally {
      _cambiandoAviso = false;
    }
    if (!mounted) return;
    setState(() {});
    if (!guardado) {
      recordarAviso(
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: Key('configuracion_aviso_privacidad_falla'),
            content: Text(TextosConfiguracion.noPudimosGuardarElAviso),
          ),
        ),
      );
    }
  }

  /// Toca un módulo de la barra bloqueada. Sin estado conocido el aviso es el de la causa y trae
  /// «Reintentar»; si ya hay una consulta en curso, muestra que está revisando.
  void _tocoModuloBloqueado(EstadoCuenta? estado, Object? error) {
    if (_reintentandoCuenta) {
      _mostrarRevisando();
      return;
    }
    recordarAviso(
      avisarModuloBloqueado(
        context,
        estado,
        sinConexion: error is FailureSinConexion,
        alReintentar: () => unawaited(_reintentarCuenta()),
      ),
    );
  }

  void _mostrarRevisando() {
    final mensajero = ScaffoldMessenger.of(context)..clearSnackBars();
    recordarAviso(
      mensajero.showSnackBar(
        const SnackBar(
          key: Key('modulo_bloqueado_revisando'),
          // Dura lo que tarde la consulta: se saca al terminar (o si esta pantalla se va).
          duration: Duration(days: 1),
          content: Text(TextosModuloBloqueado.revisando),
        ),
      ),
    );
  }

  /// «Reintentar» del aviso: consulta la cuenta con «Revisando con el servidor…» y después avisa
  /// el estado nuevo o la causa de nuevo con «Reintentar». Si la cuenta ya accede, no avisa nada:
  /// la raíz muestra el inicio.
  Future<void> _reintentarCuenta() async {
    if (_reintentandoCuenta) return;
    _reintentandoCuenta = true;
    _mostrarRevisando();
    Failure? falla;
    try {
      falla = await ref.read(estadoCuentaProvider.notifier).refrescar();
    } on Object catch (e) {
      falla = FailureInesperado(causa: e);
    }
    _reintentandoCuenta = false;
    cerrarAviso(); // Saca el «Revisando» (si la pantalla se fue, ya lo sacó al irse).
    if (!mounted) return;
    final estado = ref.read(estadoCuentaProvider).value;
    if (falla == null) {
      if (estado != null && !estado.accedeAModulosDeCampo) {
        recordarAviso(avisarModuloBloqueado(context, estado));
      }
      return;
    }
    recordarAviso(
      avisarModuloBloqueado(
        context,
        estado,
        sinConexion: falla is FailureSinConexion,
        alReintentar: () => unawaited(_reintentarCuenta()),
      ),
    );
  }

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
        final Either<Failure, ResultadoCierreSesion> resultado;
        try {
          resultado = await ref
              .read(sesionProvider.notifier)
              .cerrarSesion(avisarCierreSinConexion: true);
        } on Object {
          // Si el cierre lanzó pero la sesión ya quedó cerrada (el notifier la resetea igual), no
          // hay error que mostrar: el colportor salió. Con la sesión todavía abierta sí es un error.
          if (ref.read(sesionProvider).value != null) return false;
          navigator.popUntil((route) => route.isFirst);
          return true;
        }
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
    final cuentaId = ref.watch(sesionProvider).value?.usuarioId;
    // Mientras se lee, o si no se pudo leer, el aviso cuenta como encendido (ante la duda, se ve).
    final avisoOculto =
        cuentaId != null && (ref.watch(avisoPrivacidadOcultoProvider(cuentaId)).value ?? false);
    // Con la cuenta pendiente (o sin estado conocido) la barra se ve con los módulos bloqueados
    // (vista 16, nota; vista 18). Mientras se consulta el estado no hay barra.
    final estadoCuenta = ref.watch(estadoCuentaProvider);
    // Si la cuenta cambia por otro lado (una respuesta tardía, la consulta de la pantalla de
    // espera), un aviso del módulo sobre la cuenta anterior ya no es cierto.
    ref.listen(estadoCuentaProvider, (anterior, actual) {
      if (anterior?.value != actual.value || anterior?.error != actual.error) {
        cerrarAvisoAlTerminarElCuadro();
      }
    });
    // El respaldo en Drive (HU-SYNC-004). El aviso de «cancelaste» se queda mientras esta pantalla
    // esté abierta: se mira acá para que no se pierda entre una hoja y la otra.
    final estadoDrive = ref.watch(estadoRespaldoDriveProvider);
    final driveCancelado = ref.watch(avisoDriveCanceladoProvider);
    final ultimoRespaldo = ref.watch(ultimoRespaldoDriveProvider).value;
    final conBarra = estadoCuenta is! AsyncLoading;
    final estado = estadoCuenta.value;
    final accede = estadoCuenta is AsyncData && (estado == null || estado.accedeAModulosDeCampo);

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
                              // A texto grande el título encoge en vez de partirse a mitad de palabra.
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Configuración',
                                  maxLines: 1,
                                  style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                      // El permiso de Drive se perdió, o se cerró la pantalla de Google (16D·06, 07).
                      AvisoRespaldoDrive(
                        estado: estadoDrive.value,
                        cancelado: driveCancelado,
                        alReconectar: () => unawaited(_conectarDrive()),
                      ),
                      const _TituloSeccion('Tu cuenta'),
                      const SizedBox(height: 8),
                      _Tarjeta(
                        children: [
                          _FilaCuenta(nombre: nombre, email: email),
                          const Divider(),
                          // Las notificaciones (HU-NOT-001, vista 24): el permiso del teléfono, y
                          // las opciones de los recordatorios cuando lleguen (HU-NOT-004).
                          ListTile(
                            key: const Key('configuracion_notificaciones'),
                            minVerticalPadding: 12,
                            leading: const Icon(Icons.notifications_none_outlined),
                            // Con el texto al 200 % en 360 dp la palabra no entra entre el ícono y la
                            // flecha: se achica en vez de partirla (QA #153, menor 1).
                            title: const FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(TextosNotificaciones.filaConfiguracion, maxLines: 1),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                unawaited(Navigator.of(context).push(NotificacionesPage.ruta())),
                          ),
                        ],
                      ),
                      // La sección «Mapas» (vista 16): con la cuenta pendiente de asignación se oculta
                      // (vista 16, nota; vista 18).
                      if (accede) ...[
                        const SizedBox(height: 24),
                        const _TituloSeccion(TextosMapasOffline.seccionConfiguracion),
                        const SizedBox(height: 8),
                        _Tarjeta(
                          children: [
                            ListTile(
                              key: const Key('configuracion_mapas_offline'),
                              minVerticalPadding: 12,
                              leading: const Icon(Icons.map_outlined),
                              title: const Text(TextosMapasOffline.filaConfiguracion),
                              subtitle: Text(
                                ref.watch(resumenMapasDescargadosProvider),
                                key: const Key('configuracion_mapas_offline_resumen'),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  unawaited(Navigator.of(context).push(MapasOfflinePage.ruta())),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      SeccionRespaldoDrive(
                        estado: estadoDrive,
                        ultimoRespaldo: ultimoRespaldo,
                        ahora: DateTime.now(),
                        alConectar: () => unawaited(_conectarDrive()),
                        alVerCuenta: () => unawaited(_desconectarDrive()),
                        alReintentar: () =>
                            unawaited(ref.read(estadoRespaldoDriveProvider.notifier).recargar()),
                      ),
                      const SizedBox(height: 24),
                      const _TituloSeccion('Privacidad y datos'),
                      const SizedBox(height: 8),
                      _Tarjeta(
                        children: [
                          if (cuentaId != null)
                            _FilaAvisoDePrivacidad(
                              visible: !avisoOculto,
                              cambiando: _cambiandoAviso,
                              alCambiar: (mostrar) =>
                                  unawaited(_cambiarAvisoDePrivacidad(cuentaId, mostrar: mostrar)),
                            ),
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
          ? BarraPestanasInicio(
              bloqueadas: accede ? const {} : modulosDeCampo,
              onSeleccionar: (pestana) {
                if (accede || pestana == PestanaInicio.hoy) {
                  Navigator.of(context).pop(pestana);
                } else {
                  _tocoModuloBloqueado(estado, estadoCuenta.error);
                }
              },
            )
          : null,
    );
  }
}

/// «Mostrar el aviso de privacidad»: el interruptor que vuelve a encender (o apaga) el aviso «Estos
/// datos solo viven en tu celular. Nunca se suben a la nube.» del alta de persona y de las notas.
class _FilaAvisoDePrivacidad extends StatelessWidget {
  const _FilaAvisoDePrivacidad({
    required this.visible,
    required this.cambiando,
    required this.alCambiar,
  });

  final bool visible;
  final bool cambiando;
  final ValueChanged<bool> alCambiar;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: const Key('configuracion_aviso_privacidad'),
      value: visible,
      onChanged: cambiando ? null : alCambiar,
      minVerticalPadding: 12,
      secondary: const Icon(Icons.visibility_outlined),
      title: const Text(TextosConfiguracion.mostrarAvisoDePrivacidad),
      subtitle: const Text(TextosConfiguracion.mostrarAvisoDePrivacidadAyuda),
    );
  }
}

/// Los textos de Configuración que no son de una vista aprobada con literales en el canvas (mapa §2:
/// texto, a confirmar): «Mostrar el aviso de privacidad» es el rótulo que dio Cristian el 23/10.
abstract final class TextosConfiguracion {
  static const mostrarAvisoDePrivacidad = 'Mostrar el aviso de privacidad';
  static const mostrarAvisoDePrivacidadAyuda =
      'Sale cuando agregás una persona o una nota, para recordarte que esos datos solo viven '
      'en tu celular.';
  static const noPudimosGuardarElAviso = 'No pudimos guardar el cambio. Probá de nuevo.';
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
              children: [const Text('Sesión iniciada como'), _CorreoQueSeParte(email)],
            )
          : _CorreoQueSeParte(email),
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

/// El correo se lee a su tamaño, nunca encogido: si no entra en una línea se parte después de «@» y
/// de cada «.», sin límite de líneas ni elipsis. Lo anunciado es el correo completo.
class _CorreoQueSeParte extends StatelessWidget {
  const _CorreoQueSeParte(this.email);

  final String email;

  static const _corteSuave = '\u200B';

  @override
  Widget build(BuildContext context) {
    final estilo = DefaultTextStyle.of(context).style;
    final escala = MediaQuery.textScalerOf(context);
    final direccion = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final medido = TextPainter(
          text: TextSpan(text: email, style: estilo),
          textScaler: escala,
          textDirection: direccion,
          maxLines: 1,
        )..layout();
        final entra = medido.width <= c.maxWidth;
        medido.dispose();
        final texto = entra
            ? email
            : email.replaceAllMapped(RegExp(r'[@.]'), (m) => '${m[0]}$_corteSuave');
        return Semantics(
          label: email,
          excludeSemantics: true,
          child: Text(texto, key: const Key('configuracion_email')),
        );
      },
    );
  }
}
