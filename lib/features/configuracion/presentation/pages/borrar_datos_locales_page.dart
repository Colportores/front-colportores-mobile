import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/colores_colportaje.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../auth/domain/entities/resumen_datos_locales.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import 'configuracion_page.dart' show colorEncabezado;

/// Configuración → Privacidad y datos → "Borrar datos locales" (HU-AUTH-010).
///
/// Doble confirmación obligatoria: esta pantalla con el resumen y el checkbox, y después el
/// diálogo final. Si hay operaciones sin sincronizar no se ofrece borrar: perder el trabajo de un
/// colportor no se revierte, así que se bloquea y se explica qué hacer.
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
  static const errorBorrado = 'No pudimos borrar los datos de este teléfono. Probá de nuevo.';
  static String bloqueoPendientes(int n) =>
      'Tenés $n operaciones sin sincronizar. Para no perderlas, no se puede borrar hasta que se '
      'suban: conectate a internet y esperá a que se sincronicen.';
}

class _BorrarDatosLocalesPageState extends ConsumerState<BorrarDatosLocalesPage> {
  late Future<Either<Failure, ResumenDatosLocales>> _resumen = _cargar();
  bool _entiende = false;
  bool _borrando = false;

  /// Si el borrado se negó por operaciones sin sincronizar que entraron después del resumen.
  int? _pendientesAlBorrar;

  Future<Either<Failure, ResumenDatosLocales>> _cargar() =>
      ref.read(obtenerResumenDatosLocalesUseCaseProvider)(const NoParams());

  void _reintentarCarga() => setState(() {
    _pendientesAlBorrar = null;
    _resumen = _cargar();
  });

  Future<void> _continuar(ResumenDatosLocales resumen) async {
    final eleccion = await showDialog<_EleccionFinal>(
      context: context,
      builder: (_) => _DialogoFinal(hayBackupEnDrive: resumen.hayBackupEnDrive),
    );
    if (!mounted) return;
    if (eleccion == null) {
      // "Cancelar" en el diálogo final: no se borra nada y se vuelve a Configuración.
      Navigator.of(context).pop();
      return;
    }

    setState(() => _borrando = true);
    final resultado = await ref
        .read(sesionProvider.notifier)
        .borrarDatosLocales(incluirBackupDrive: eleccion.incluirBackupDrive);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    resultado.fold(
      (failure) {
        setState(() {
          _borrando = false;
          if (failure is FailureDatosSinSincronizar) _pendientesAlBorrar = failure.cantidad;
        });
        if (failure is FailureDatosSinSincronizar) return;
        messenger.showSnackBar(
          SnackBar(
            key: const Key('borrar_datos_error'),
            content: Text(
              failure is FailureDatosLocalesIlegibles
                  ? failure.mensaje
                  : TextosBorrado.errorBorrado,
            ),
          ),
        );
      },
      (r) {
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

    return Scaffold(
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
                (failure) => _Error(
                  mensaje: failure is FailureDatosLocalesIlegibles
                      ? failure.mensaje
                      : const FailureDatosLocalesIlegibles().mensaje,
                  onReintentar: _reintentarCarga,
                ),
                (resumen) {
                  final pendientes = _pendientesAlBorrar ?? resumen.operacionesSinSincronizar;
                  if (pendientes > 0) return _Bloqueado(pendientes: pendientes);
                  return _Resumen(
                    resumen: resumen,
                    entiende: _entiende,
                    borrando: _borrando,
                    onEntiende: (v) => setState(() => _entiende = v),
                    onContinuar: () => _continuar(resumen),
                  );
                },
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

class _Bloqueado extends StatelessWidget {
  const _Bloqueado({required this.pendientes});

  final int pendientes;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('borrar_datos_bloqueado'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Aviso(icono: Icons.cloud_off_outlined, texto: TextosBorrado.bloqueoPendientes(pendientes)),
      const SizedBox(height: 16),
      OutlinedButton(
        key: const Key('borrar_datos_volver'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Volver a Configuración'),
      ),
    ],
  );
}

class _Resumen extends StatelessWidget {
  const _Resumen({
    required this.resumen,
    required this.entiende,
    required this.borrando,
    required this.onEntiende,
    required this.onContinuar,
  });

  final ResumenDatosLocales resumen;
  final bool entiende;
  final bool borrando;
  final ValueChanged<bool> onEntiende;
  final VoidCallback onContinuar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;

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
                icono: Icons.cloud_outlined,
                titulo: 'Backup en Drive',
                valor: resumen.hayBackupEnDrive ? 'Sí, vas a elegir si se borra' : 'No hay',
                valorKey: const Key('borrar_datos_backup'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('borrar_datos_continuar'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: entiende && !borrando ? onContinuar : null,
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
  const _DialogoFinal({required this.hayBackupEnDrive});

  final bool hayBackupEnDrive;

  @override
  State<_DialogoFinal> createState() => _DialogoFinalState();
}

class _DialogoFinalState extends State<_DialogoFinal> {
  bool _incluirDrive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            if (widget.hayBackupEnDrive) ...[
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
