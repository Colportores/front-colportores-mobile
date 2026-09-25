import 'dart:async';

import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../auth/domain/entities/resumen_datos_locales.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../../jornada/presentation/providers/jornada_providers.dart';
import 'configuracion_page.dart' show colorEncabezado;

/// Configuración → Privacidad y datos → "Borrar datos locales" (HU-AUTH-010).
///
/// Doble confirmación obligatoria: esta pantalla con el resumen y el checkbox, y después el
/// diálogo final. Si hay operaciones sin sincronizar (o no se pudieron contar) el borrado se
/// puede hacer igual —decisión de Cristian en #66—, pero antes se avisa cuántas se pierden y se
/// pide confirmarlo con un checkbox aparte.
class BorrarDatosLocalesPage extends ConsumerStatefulWidget {
  const BorrarDatosLocalesPage({super.key});

  static Route<void> ruta() =>
      MaterialPageRoute<void>(builder: (_) => const BorrarDatosLocalesPage());

  @override
  ConsumerState<BorrarDatosLocalesPage> createState() => _BorrarDatosLocalesPageState();
}

/// Textos literales de HU-AUTH-010 (criterios de aceptación y aclaración de ADR-005) y avisos.
abstract final class TextosBorrado {
  static const explicacion =
      'Borraremos todos los datos que tengas en este dispositivo y cerraremos tu sesión. Tu '
      'cuenta seguirá existiendo en nuestro sistema (puede ser reactivada si te asignan a una '
      'campaña nueva). Si querés eliminar definitivamente tu cuenta, contactá a tu coordinador '
      'para una baja administrativa.';
  static const datosDelSistema =
      'Los datos del sistema (estado de las ubicaciones, estadísticas) no se borran con esta '
      'acción.';
  static const limiteBorrado =
      'El archivo se pisa con ceros antes de borrarse. En la memoria del teléfono eso no garantiza '
      'que desaparezca físicamente; lo que sí lo protege es que siempre estuvo cifrado.';
  static const checkbox = 'Entiendo que se van a borrar todos los datos de este teléfono.';
  static const conservarDrive = 'No, conservar mi backup en Drive';
  static const borrarDrive = 'Sí, borrar también mi backup en Drive';
  static const confirmarFinal = 'Sí, borrar datos locales';
  static const driveSinConexion =
      'No pudimos borrar el backup remoto; intentalo más tarde desde Drive.';
  static const driveFallo =
      'Tus datos locales se eliminaron. No pudimos borrar el backup en Drive; eliminalo '
      'manualmente desde drive.google.com o reintentá.';
  static const errorBorrado =
      'No pudimos terminar de borrar los datos de este teléfono. Reintentá.';

  /// Aviso de lo que se pierde (HU-AUTH-010: "las operaciones encoladas no se subirán").
  static String pendientes(int n) =>
      'Tenés $n operaciones sin sincronizar. Si borrás ahora, no se van a subir y se pierden.';
  static const pendientesDesconocidos =
      'No pudimos contar si hay operaciones sin sincronizar. Si hay alguna, no se va a subir y se '
      'pierde al borrar.';
  static String checkboxPendientes(int? n) => n == null
      ? 'Entiendo que puedo perder operaciones que no se sincronizaron.'
      : 'Entiendo que se pierden las $n operaciones sin sincronizar.';
}

class _BorrarDatosLocalesPageState extends ConsumerState<BorrarDatosLocalesPage> {
  late Future<Either<Failure, ResumenDatosLocales>> _resumen = _cargar();
  bool _entiende = false;
  bool _aceptaPerderPendientes = false;
  bool _borrando = false;

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

  Future<Either<Failure, ResumenDatosLocales>> _cargar() =>
      ref.read(obtenerResumenDatosLocalesUseCaseProvider)(const NoParams());

  void _reintentarCarga() => setState(() {
    _resumen = _cargar();
  });

  Future<void> _continuar(ResumenDatosLocales resumen) async {
    final eleccion = await showDialog<_EleccionFinal>(
      context: context,
      builder: (_) => _DialogoFinal(resumen: resumen),
    );
    if (!mounted) return;
    if (eleccion == null) {
      // "Cancelar" en el diálogo final: no se borra nada y se vuelve a Configuración.
      Navigator.of(context).pop();
      return;
    }
    await _borrar(eleccion);
  }

  Future<void> _borrar(_EleccionFinal eleccion) async {
    if (_borrando) return;
    setState(() => _borrando = true);
    final resultado = await ref
        .read(sesionProvider.notifier)
        .borrarDatosLocales(incluirBackupDrive: eleccion.incluirBackupDrive);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    _ocultarAvisoReintentar();
    resultado.fold(
      (_) {
        setState(() => _borrando = false);
        final aviso = messenger.showSnackBar(
          SnackBar(
            key: const Key('borrar_datos_error'),
            content: const Text(TextosBorrado.errorBorrado),
            // Reintentar es seguro: el borrado es idempotente.
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: () {
                // Si la pantalla ya no está, el reintento no tiene dónde mostrar nada.
                if (mounted) unawaited(_borrar(eleccion));
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
        // La jornada todavía vive en memoria mientras la DB no se abra (#27): sin esto, el próximo
        // login mostraría datos que la pantalla acaba de decir que se borraron. Después del frame:
        // en este, la pantalla de jornada que está debajo reanuda sus providers mientras se
        // reconstruye, y una invalidación en el medio dispara un rebuild durante el build.
        final container = ProviderScope.containerOf(context, listen: false);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => container.invalidate(jornadaLocalDataSourceProvider),
        );
        final aviso = switch (r) {
          ResultadoBorradoDatosLocales.completo => null,
          ResultadoBorradoDatosLocales.backupDriveNoBorradoSinConexion =>
            TextosBorrado.driveSinConexion,
          ResultadoBorradoDatosLocales.backupDriveNoBorrado => TextosBorrado.driveFallo,
        };
        if (aviso != null) {
          messenger.showSnackBar(
            SnackBar(
              key: const Key('borrar_datos_aviso_drive'),
              content: Text(aviso),
              duration: const Duration(seconds: 10),
            ),
          );
        }
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;

    // Mientras borra no se puede salir: el "atrás" dejaría el borrado corriendo sin nadie que
    // muestre cómo terminó.
    return PopScope(
      canPop: !_borrando,
      child: Scaffold(
        body: SafeArea(
          child: FutureBuilder<Either<Failure, ResumenDatosLocales>>(
            future: _resumen,
            builder: (context, snapshot) {
              final Widget contenido;
              final datos = snapshot.data;
              if (datos == null) {
                contenido = const _Cargando(key: Key('borrar_datos_cargando'));
              } else {
                contenido = datos.fold(
                  (_) => _Error(
                    mensaje: const FailureDatosLocalesIlegibles().mensaje,
                    onReintentar: _reintentarCarga,
                  ),
                  (resumen) => _Resumen(
                    resumen: resumen,
                    entiende: _entiende,
                    aceptaPerderPendientes: _aceptaPerderPendientes,
                    borrando: _borrando,
                    onEntiende: (v) => setState(() => _entiende = v),
                    onAceptaPerderPendientes: (v) => setState(() => _aceptaPerderPendientes = v),
                    onContinuar: () => _continuar(resumen),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      key: const Key('borrar_datos_atras'),
                      tooltip: 'Volver',
                      onPressed: _borrando ? null : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PRIVACIDAD Y DATOS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorEncabezado(theme, colores),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Borrar datos locales',
                    style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                  ),
                  const SizedBox(height: 12),
                  contenido,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Revisando los datos de este teléfono…', textAlign: TextAlign.center),
      ],
    ),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('borrar_datos_error_resumen'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Aviso(icono: Icons.error_outline, texto: mensaje),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('borrar_datos_reintentar'),
        onPressed: onReintentar,
        child: const Text('Reintentar'),
      ),
    ],
  );
}

class _Resumen extends StatelessWidget {
  const _Resumen({
    required this.resumen,
    required this.entiende,
    required this.aceptaPerderPendientes,
    required this.borrando,
    required this.onEntiende,
    required this.onAceptaPerderPendientes,
    required this.onContinuar,
  });

  final ResumenDatosLocales resumen;
  final bool entiende;
  final bool aceptaPerderPendientes;
  final bool borrando;
  final ValueChanged<bool> onEntiende;
  final ValueChanged<bool> onAceptaPerderPendientes;
  final VoidCallback onContinuar;

  /// Hay (o puede haber) trabajo sin subir que se pierde: pide una confirmación aparte.
  bool get _hayPendientes =>
      resumen.operacionesSinSincronizar == null || resumen.operacionesSinSincronizar! > 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final pendientes = resumen.operacionesSinSincronizar;
    final puedeContinuar = entiende && (!_hayPendientes || aceptaPerderPendientes) && !borrando;

    return Column(
      key: const Key('borrar_datos_resumen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(TextosBorrado.explicacion, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colores.borde),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _Fila(
                icono: Icons.people_outline,
                titulo: 'Personas registradas en este teléfono',
                valor: '${resumen.personas}',
                valorKey: const Key('borrar_datos_personas'),
              ),
              const Divider(),
              _Fila(
                icono: Icons.event_note_outlined,
                titulo: 'Visitas registradas en este teléfono',
                valor: '${resumen.visitas}',
                valorKey: const Key('borrar_datos_visitas'),
              ),
              const Divider(),
              _Fila(
                icono: Icons.cloud_upload_outlined,
                titulo: 'Operaciones sin sincronizar',
                valor: pendientes == null ? 'No se pudieron contar' : '$pendientes',
                valorKey: const Key('borrar_datos_pendientes'),
              ),
              const Divider(),
              _Fila(
                icono: Icons.cloud_outlined,
                titulo: 'Backup en Drive',
                valor: resumen.hayBackupEnDrive ? 'Sí, vas a elegir si se borra' : 'No hay',
                valorKey: const Key('borrar_datos_backup'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_hayPendientes) ...[
          _AvisoPendientes(pendientes: pendientes),
          const SizedBox(height: 12),
        ],
        const _Aviso(icono: Icons.info_outline, texto: TextosBorrado.datosDelSistema),
        const SizedBox(height: 8),
        const _Aviso(icono: Icons.lock_outline, texto: TextosBorrado.limiteBorrado),
        const SizedBox(height: 12),
        CheckboxListTile(
          key: const Key('borrar_datos_checkbox'),
          value: entiende,
          onChanged: borrando ? null : (v) => onEntiende(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(TextosBorrado.checkbox),
        ),
        if (_hayPendientes)
          CheckboxListTile(
            key: const Key('borrar_datos_checkbox_pendientes'),
            value: aceptaPerderPendientes,
            onChanged: borrando ? null : (v) => onAceptaPerderPendientes(v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(TextosBorrado.checkboxPendientes(pendientes)),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('borrar_datos_continuar'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: puedeContinuar ? onContinuar : null,
          child: borrando
              ? SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    key: const Key('borrar_datos_borrando'),
                    strokeWidth: 2.5,
                    color: theme.colorScheme.onError,
                    semanticsLabel: 'Borrando datos',
                  ),
                )
              : const Text('Continuar'),
        ),
      ],
    );
  }
}

/// Lo que se pierde, destacado: es trabajo del colportor que no llegó al servidor.
class _AvisoPendientes extends StatelessWidget {
  const _AvisoPendientes({required this.pendientes});

  final int? pendientes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: const Key('borrar_datos_aviso_pendientes'),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                pendientes == null
                    ? TextosBorrado.pendientesDesconocidos
                    : TextosBorrado.pendientes(pendientes!),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.icono,
    required this.titulo,
    required this.valor,
    required this.valorKey,
  });

  final IconData icono;
  final String titulo;
  final String valor;
  final Key valorKey;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icono),
    title: Text(titulo),
    subtitle: Text(valor, key: valorKey, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icono, size: 20)),
        const SizedBox(width: 10),
        Expanded(child: Text(texto, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

/// Lo que el usuario eligió en el diálogo final; `null` si canceló.
final class _EleccionFinal {
  const _EleccionFinal({required this.incluirBackupDrive});

  final bool incluirBackupDrive;
}

/// Segunda confirmación. Con backup en Drive, además pregunta si se borra (por defecto se
/// conserva: es la opción que no pierde nada).
class _DialogoFinal extends StatefulWidget {
  const _DialogoFinal({required this.resumen});

  final ResumenDatosLocales resumen;

  @override
  State<_DialogoFinal> createState() => _DialogoFinalState();
}

class _DialogoFinalState extends State<_DialogoFinal> {
  bool _incluirDrive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendientes = widget.resumen.operacionesSinSincronizar;
    return AlertDialog(
      key: const Key('borrar_datos_dialogo_final'),
      title: const Text('¿Borrar datos locales?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Se van a borrar los datos de este teléfono y se va a cerrar tu sesión. No se puede '
              'deshacer.',
            ),
            if (pendientes == null || pendientes > 0) ...[
              const SizedBox(height: 8),
              Text(
                pendientes == null
                    ? TextosBorrado.pendientesDesconocidos
                    : TextosBorrado.pendientes(pendientes),
                key: const Key('borrar_datos_dialogo_pendientes'),
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
              ),
            ],
            if (widget.resumen.hayBackupEnDrive) ...[
              const SizedBox(height: 12),
              _Opcion(
                key: const Key('borrar_datos_conservar_drive'),
                texto: TextosBorrado.conservarDrive,
                seleccionada: !_incluirDrive,
                onTap: () => setState(() => _incluirDrive = false),
              ),
              _Opcion(
                key: const Key('borrar_datos_incluir_drive'),
                texto: TextosBorrado.borrarDrive,
                seleccionada: _incluirDrive,
                onTap: () => setState(() => _incluirDrive = true),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('borrar_datos_cancelar'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('borrar_datos_confirmar'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () =>
              Navigator.of(context).pop(_EleccionFinal(incluirBackupDrive: _incluirDrive)),
          child: const Text(TextosBorrado.confirmarFinal),
        ),
      ],
    );
  }
}

/// Opción excluyente del diálogo final (se evita `RadioListTile` por el cambio de API de
/// `RadioGroup`; la semántica es la misma).
class _Opcion extends StatelessWidget {
  const _Opcion({super.key, required this.texto, required this.seleccionada, required this.onTap});

  final String texto;
  final bool seleccionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: seleccionada,
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      selected: seleccionada,
      leading: Icon(seleccionada ? Icons.radio_button_checked : Icons.radio_button_unchecked),
      title: Text(texto),
      onTap: onTap,
    ),
  );
}
